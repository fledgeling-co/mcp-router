import Foundation

/// The outcome of trying to adopt one entry of an `mcpServers` object.
public enum ParsedServer: Sendable, Hashable {
    case upstream(UpstreamConfig)
    case skipped(reason: String)
}

/// Turns one entry of an `mcpServers` object into an upstream, or explains why not.
///
/// Shared by the config loader, `import` and `watch` in the reference so that all three agree on
/// what is adoptable — they previously disagreed, and a server rejected by one was adopted by
/// another depending on which ran first.
///
/// The **order of the checks is load-bearing** and is preserved: name charset, then the namespace
/// separator, then transport selection, then the per-transport requirement. A server with both a
/// bad name and no command reports the name.
public enum ServerParser {
    public static func parse(name: String, raw: JSONValue) -> ParsedServer {
        guard isAdoptableName(name) else {
            return .skipped(reason: "name is not [A-Za-z0-9_-]+, so it cannot be a tool namespace")
        }
        // `__` is the namespace separator, so a server carrying one makes `<server>__<tool>`
        // ambiguous: "foo__bar" exposing "run" publishes "foo__bar__run", which splits back to
        // server "foo", tool "bar__run".
        guard !name.contains("__") else {
            return .skipped(reason: "name contains \"__\", which is the tool namespace separator")
        }

        let declaredType = raw.member("type")
        let typeName: String = if let declaredType, declaredType != .null {
            declaredType.jsDisplayString
        } else {
            // Nullish on `type`, but *truthy* on `url` — so `url: ""` selects stdio.
            (raw.member("url")?.isTruthy ?? false) ? "http" : "stdio"
        }

        let common = commonFields(name: name, raw: raw)

        switch typeName {
        case "stdio":
            guard let command = raw.member("command"), command.isTruthy else {
                return .skipped(reason: "stdio server has no command")
            }
            var upstream = common
            upstream.transport = .stdio
            upstream.command = command.jsDisplayString
            upstream.args = (raw.member("args")?.asArray ?? []).map(\.jsDisplayString)
            upstream.env = raw.member("env")?.objectEntries ?? []
            upstream.cwd = raw.member("cwd")?.asString?.string
            return .upstream(upstream)

        case "http", "sse", "streamable-http":
            guard let url = raw.member("url"), url.isTruthy else {
                return .skipped(reason: "\(typeName) server has no url")
            }
            let text = url.jsDisplayString
            // A malformed url must fail here, not at first call: the router would otherwise index
            // fine and every tool on it would error at use time.
            guard JSURL(text) != nil else {
                return .skipped(reason: "url is not parseable: \(text)")
            }
            var upstream = common
            // `streamable-http` collapses to `http`; `sse` keeps its own identity, and the two
            // hash differently.
            upstream.transport = typeName == "sse" ? .sse : .http
            upstream.url = text
            upstream.headers = raw.member("headers")?.objectEntries ?? []
            upstream.oauth = raw.member("oauth")?.asBool
            return .upstream(upstream)

        default:
            return .skipped(reason: "unsupported transport \"\(typeName)\"")
        }
    }

    private static func commonFields(name: String, raw: JSONValue) -> UpstreamConfig {
        UpstreamConfig(
            name: name,
            transport: .stdio,
            raw: raw,
            idleMs: raw.member("idleMs")?.asNumber.flatMap(JSNumber.int),
            startupTimeoutMs: raw.member("startupTimeoutMs")?.asNumber.flatMap(JSNumber.int),
            projects: raw.member("projects")?.asArray?.map(\.jsDisplayString),
            warm: raw.member("warm")?.asBool,
            placard: placard(from: raw.member("placard")),
            command: nil,
            args: [],
            env: [],
            cwd: nil,
            url: nil,
            headers: [],
            oauth: nil
        )
    }

    private static func placard(from value: JSONValue?) -> Placard? {
        guard let value, case .object = value, let reason = value.member("reason") else { return nil }
        return Placard(
            reason: reason.jsDisplayString,
            substitute: value.member("substitute")?.asString?.string,
            until: value.member("until")?.asString?.string
        )
    }

    /// `/^[A-Za-z0-9_-]+$/` — written out rather than regex-matched so it is obvious that an empty
    /// name fails and that nothing outside ASCII passes.
    private static func isAdoptableName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        for scalar in name.unicodeScalars {
            switch scalar {
            case "A" ... "Z", "a" ... "z", "0" ... "9", "_", "-": continue
            default: return false
            }
        }
        return true
    }
}

/// True when this entry is the router itself.
///
/// `~/.claude.json` gains an `mcp-router` HTTP entry at install time, so anything that adopts HTTP
/// servers out of that file will otherwise adopt the router — which then proxies to itself, and
/// every `tools/list` recurses until something gives up. Checked by URL as well as by name,
/// because renaming the entry must not defeat it.
public enum SelfReference {
    private static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1", "[::1]"]

    public static func isSelfReference(name: String, raw: JSONValue, port: Int) -> Bool {
        if name == "mcp-router" || name == "router" { return true }
        guard let urlValue = raw.member("url"), urlValue.isTruthy else { return false }
        guard let url = JSURL(urlValue.jsDisplayString) else { return false }
        guard loopbackHosts.contains(url.host) else { return false }
        // Compared against the port **as the URL reports it**, which is empty when the port is the
        // default for the scheme. So `http://localhost:80` against port 80 is NOT a self-reference
        // — a faithful reproduction of the reference, and a trap for any implementation that
        // resolves the effective port instead.
        return url.port == String(port)
    }
}
