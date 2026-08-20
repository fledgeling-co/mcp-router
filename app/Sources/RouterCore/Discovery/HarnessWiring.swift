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
    static func detect(entries: [DiscoveredServer], port: Int) -> HarnessRoute {
        var shim: HarnessRoute?
        for entry in entries {
            if let url = entry.raw.member("url")?.jsDisplayString,
               RouterEndpoint.isThisRouter(url: url, port: port)
            {
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
