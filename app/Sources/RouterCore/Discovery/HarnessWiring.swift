import Foundation

/// Is a URL this router's own endpoint?
///
/// Separate from ``SelfReference`` on purpose, and the difference is the whole of R7's route
/// detection. `SelfReference.isSelfReference` returns true for the bare *name* `router` or
/// `mcp-router` with no url at all, which is correct for `import` — never adopt a thing called
/// router, whatever it points at — and wrong here, where the question is where a harness actually
/// connects. A harness entry named `router` aimed at some other host is **not routed**, and this
/// item exists to say so rather than to agree with the label.
///
/// The loopback host set is shared with ``SelfReference`` rather than copied, so the two cannot
/// drift into disagreeing about what loopback means.
public enum RouterEndpoint {
    /// True when `text` parses as a URL on a loopback host at this router's port.
    ///
    /// The port is compared **as the URL reports it**, which is the same rule ``SelfReference``
    /// follows: an omitted port is the empty string and does not match 80.
    public static func isThisRouter(url text: String, port: Int) -> Bool {
        guard let url = JSURL(text) else { return false }
        guard SelfReference.loopbackHosts.contains(url.host) else { return false }
        return url.port == String(port)
    }

    /// The first token in `candidates` that is this router's endpoint.
    static func firstEndpoint(in candidates: [String], port: Int) -> String? {
        candidates.first { isThisRouter(url: $0, port: port) }
    }
}

/// How one harness spells an entry's HTTP endpoint.
///
/// `url` is what Claude Code, Cursor, Codex and grok write. **Gemini writes `httpUrl`** — its
/// MCP-server config struct carries `json:"httpUrl"`, which is the evidence
/// ``HTTPCapability/known(for:)`` cites for that harness (`planning/specs/spec-R7.md` §1.2). A
/// reader keying on `url` alone cannot see a Gemini harness that is wired directly at all: it
/// reports `not-wired`, and then prints a remedy telling the user to create the exact state it is
/// unable to read. That is worse than a gap, because it is self-triggering.
///
/// **Per client, not global**, and that is the same rule ``HTTPCapability`` follows. Reading
/// `httpUrl` out of a Cursor or Codex file would be a claim about how *those* programs read their
/// own config, and nothing here has established that they read that key at all. An inert key in a
/// file this item merely inspects would become "wired via HTTP" — the fabrication `HTTPCapability`
/// exists to refuse, arriving through the back door. So each harness gets the spellings it has
/// been shown to use, and a harness nobody has probed gets the standard one.
public struct HarnessDialect: Sendable, Hashable {
    /// The keys this harness declares an endpoint under, in the order the file is read.
    public let endpointKeys: [String]

    public init(endpointKeys: [String]) {
        self.endpointKeys = endpointKeys
    }

    /// Every harness reads `url`. Nothing but Gemini has been shown to read anything else.
    public static let standard = HarnessDialect(endpointKeys: ["url"])

    public static func known(for client: MCPClient) -> HarnessDialect {
        switch client {
        case .geminiCLI: HarnessDialect(endpointKeys: ["url", "httpUrl"])
        case .claudeCode, .claudeDesktop, .codexCLI, .chatGPTCLI, .cursor, .grokCLI, .opencode:
            .standard
        }
    }

    /// Every endpoint this entry declares, in key order.
    ///
    /// All of them rather than the first, because route detection asks a yes/no question of each:
    /// an entry carrying a decoy `url` on some other host **and** an `httpUrl` on this router is
    /// wired, and a reader that stopped at the first spelling would call it not-wired and offer to
    /// wire it — the same wrong answer this widening exists to remove, one key along.
    ///
    /// A **string** rather than anything truthy. `"url": true` is not an endpoint, and coercing it
    /// to the text `"true"` would let a nonsense value shadow a real one.
    public func endpoints(in raw: JSONValue) -> [String] {
        endpointKeys.compactMap { key in
            guard let text = raw.member(key)?.asString?.string, !text.isEmpty else { return nil }
            return text
        }
    }

    /// The endpoint this entry means, under whichever spelling it used — or nil.
    public func endpoint(in raw: JSONValue) -> String? {
        endpoints(in: raw).first
    }

    /// The same entry with a non-standard spelling rewritten to `url`.
    ///
    /// ``ServerParser`` and ``UpstreamHash`` are shared with adoption, with `import` and `watch`,
    /// and through them with the TypeScript reference. Teaching either about `httpUrl` would change
    /// what the router adopts out of its own config and what a cached manifest hashes to, and
    /// neither of those is R7's to move. So the dialect is normalised **here**, at the one seam
    /// that reads another program's file, and the shared code goes on seeing the only shape it has
    /// ever seen.
    ///
    /// It has to be the raw JSON rather than the parsed value: ``UpstreamHash`` reads the endpoint
    /// off `raw`, so an entry parsed from `httpUrl` but hashed from `raw.member("url")` would
    /// digest a null endpoint and quietly fail to match its own twin on the router side.
    ///
    /// Two consequences worth naming rather than discovering. It changes `entryCount` and
    /// `unparsed` as well as the duplicate list, because an `httpUrl` entry that used to arrive as
    /// "stdio server has no command" now parses. And when the entry declares a **string** `url`
    /// already, nothing is rewritten even if a second spelling disagrees with it — the standard key
    /// wins, which is what ``ServerParser`` would have done with the same bytes. A file declaring
    /// two different endpoints for one server is registered as `D-r7-p` rather than guessed at.
    public func canonicalised(_ server: DiscoveredServer) -> DiscoveredServer {
        guard case let .object(members) = server.raw else { return server }
        // `raw.member(...)` throughout, never `members.first(where:)`. The two disagree about which
        // of a duplicated key wins, and the disagreement would let detection follow one endpoint
        // while the comparison hashed another.
        let declaredURL = server.raw.member("url")?.asString?.string
        guard declaredURL?.isEmpty != false, let endpoint = endpoint(in: server.raw) else {
            return server
        }
        // The non-standard spellings are dropped as well as replaced, so what leaves here declares
        // exactly one endpoint under exactly one key. `UpstreamHash` does not digest an unknown
        // member today; a canonical value that relies on it never starting to is a duplicate that
        // stops matching for a reason nobody would look for here.
        let dropped = Set(endpointKeys)
        let rewritten = members.filter { !dropped.contains($0.key.string) }
            + [JSONMember(key: JSString("url"), value: .string(JSString(endpoint)))]
        return DiscoveredServer(name: server.name, raw: .object(rewritten))
    }
}

/// How a harness reaches this router — or that it does not.
///
/// Three cases rather than the brief's four, because "carrying duplicates" is not a way of being
/// wired: it is orthogonal, and on the machine this was measured on one harness is a shim *and*
/// carries twelve duplicates. See `planning/specs/spec-R7.md` §3.
public enum HarnessRoute: Sendable, Hashable {
    /// No entry in this harness's config points at this router.
    case notWired
    /// An HTTP entry aimed at the router — the state the product exists to produce.
    case directHTTP(name: String, url: String)
    /// A stdio entry that bridges to the router's HTTP endpoint: one child process per session,
    /// which is the cost the router exists to remove. `bridge` is what does the bridging.
    case stdioShim(name: String, bridge: String, url: String)

    public var isWired: Bool {
        if case .notWired = self { return false }
        return true
    }
}

public extension HarnessRoute {
    /// Find the entry — if any — that points at this router.
    ///
    /// Order is the harness's own declaration order, so two runs over one file agree. A direct
    /// HTTP entry wins over a shim if a config somehow carries both: it is the better route, and
    /// reporting the shim would name a cost the harness is not actually paying to reach us.
    ///
    /// The endpoint is read through the harness's own ``HarnessDialect``, so a Gemini entry
    /// spelling it `httpUrl` is seen while a Cursor entry carrying that key is not — nothing has
    /// established that Cursor reads it. Reading `url` alone made
    /// ``HarnessRoute/directHTTP(name:url:)`` unreachable for the harness this item is about.
    static func detect(
        entries: [DiscoveredServer], port: Int, dialect: HarnessDialect = .standard
    ) -> HarnessRoute {
        var shim: HarnessRoute?
        for entry in entries {
            if let url = RouterEndpoint.firstEndpoint(
                in: dialect.endpoints(in: entry.raw), port: port
            ) {
                return .directHTTP(name: entry.name, url: url)
            }
            if shim == nil, let found = shimRoute(entry, port: port) {
                shim = found
            }
        }
        return shim ?? .notWired
    }

    /// A stdio entry is a bridge to this router when the endpoint appears among its arguments.
    ///
    /// Detected by the **endpoint**, not by a package allowlist: `mcp-remote`, `supergateway`,
    /// `mcp-proxy` and a hand-rolled node script all look the same from here, and an allowlist
    /// would report a bridge it had not heard of as "not wired" — the most misleading answer
    /// available, since the harness is paying for a child process and getting no credit for it.
    private static func shimRoute(_ entry: DiscoveredServer, port: Int) -> HarnessRoute? {
        guard let command = entry.raw.member("command")?.jsDisplayString, !command.isEmpty
        else { return nil }
        let args = (entry.raw.member("args")?.asArray ?? []).map(\.jsDisplayString)
        guard let url = RouterEndpoint.firstEndpoint(in: [command] + args, port: port)
        else { return nil }
        return .stdioShim(
            name: entry.name, bridge: bridgeName(command: command, args: args, url: url), url: url
        )
    }

    /// The first argument that is neither a flag nor the endpoint — `npx -y mcp-remote <url>`
    /// names `mcp-remote`. Falls back to the command's last path component, which is right for a
    /// bridge invoked directly rather than through a package runner.
    private static func bridgeName(command: String, args: [String], url: String) -> String {
        for arg in args where arg != url && !arg.hasPrefix("-") && !arg.isEmpty {
            return arg
        }
        return (command as NSString).lastPathComponent
    }
}
