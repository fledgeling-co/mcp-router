import Foundation

/// What made two entries the same server.
///
/// Recorded per duplicate rather than assumed, because on the machine R7 was measured on the two
/// bases point opposite ways and neither alone is right (spec §1.3): the harness's `Ref` and the
/// router's `ref-tools-mcp` are byte-identical commands under different names, so a name-only
/// comparison misses them; and a harness's `mobbin` and the router's `mobbin` are the same name
/// aimed at different hosts, so an identity-only comparison misses that one.
public enum DuplicateBasis: Sendable, Hashable {
    /// Byte-equal names. Case-sensitive, because the router's own namespace is.
    case name
    /// Equal ``UpstreamHash`` — same transport, command, args, cwd and env. `name` is excluded
    /// from that digest by design, which is what lets it see through a rename.
    case identity(hash: String)

    public var describedShort: String {
        switch self {
        case .name: "same name"
        case .identity: "same command, different name"
        }
    }
}

/// One harness entry that the router already fronts.
public struct Duplicate: Sendable, Hashable {
    /// The name the **harness** uses. The user has to find this line in their own file.
    public let harnessName: String
    /// The name the **router** uses. Equal to `harnessName` under `.name`, different under
    /// `.identity` — which is the case worth printing both halves of.
    public let routerName: String
    public let basis: DuplicateBasis

    public init(harnessName: String, routerName: String, basis: DuplicateBasis) {
        self.harnessName = harnessName
        self.routerName = routerName
        self.basis = basis
    }

    public var described: String {
        harnessName == routerName
            ? harnessName
            : "\(harnessName) (the router calls it \(routerName) — \(basis.describedShort))"
    }
}

/// The brief's four answers, derived from the report rather than stored.
///
/// Spec §3: the four are not alternatives, so they are computed from two independent axes and the
/// route survives inside the duplicate case. Nothing is lost by collapsing, and the acceptance
/// criterion asks for a value the type can produce.
public enum HarnessState: Sendable, Hashable {
    /// Not wired. `overlapping` is what adopting it would consolidate — called an overlap rather
    /// than a duplicate because nothing is being duplicated when there is no route.
    case notWired(overlapping: Int)
    case wiredViaHTTP
    case wiredViaShim(bridge: String)
    case wiredWithDuplicates(route: HarnessRoute, count: Int)
}

/// Everything R7 can say about one harness, from one read of its config.
public struct HarnessReport: Sendable, Hashable {
    public let client: MCPClient
    public let path: String
    /// Nil when there is no file, or the file could not be read — carried separately from "the
    /// file is fine and declares nothing", which is a different fact about the machine.
    public let unreadable: String?
    public let exists: Bool
    /// Entries the harness declares, excluding the one that points at this router.
    public let entryCount: Int
    public let route: HarnessRoute
    public let capability: HTTPCapability
    public let duplicates: [Duplicate]
    /// Entries `ServerParser` could not read, with the reason. Reported rather than dropped: an
    /// entry nobody could parse is not evidence that it is not a duplicate.
    public let unparsed: [String]

    public var state: HarnessState {
        if !duplicates.isEmpty, route.isWired {
            return .wiredWithDuplicates(route: route, count: duplicates.count)
        }
        switch route {
        case .notWired: return .notWired(overlapping: duplicates.count)
        case .directHTTP: return .wiredViaHTTP
        case let .stdioShim(_, bridge, _): return .wiredViaShim(bridge: bridge)
        }
    }

    /// The one-line headline. Every figure in it was counted from this run's read of the file.
    public var headline: String {
        switch state {
        case let .notWired(overlapping):
            overlapping == 0
                ? "not wired"
                : "not wired — \(overlapping) of its \(entryCount) servers are ones "
                + "the router already fronts"
        case .wiredViaHTTP:
            "wired via HTTP"
        case let .wiredViaShim(bridge):
            "wired via a stdio shim (\(bridge)) — one child process per session"
        case let .wiredWithDuplicates(route, count):
            switch route {
            case .directHTTP:
                "wired via HTTP, and carrying \(count) duplicate direct upstream(s)"
            case let .stdioShim(_, bridge, _):
                "wired via a stdio shim (\(bridge)), and carrying "
                    + "\(count) duplicate direct upstream(s)"
            case .notWired:
                "not wired"
            }
        }
    }

    /// What the user should do next, and it is the **capability** that decides the wording for a
    /// shim rather than the state. `.unknown` gets a question; nothing here asserts that a
    /// harness has an HTTP key when nobody has looked for one.
    public var remedy: String? {
        var lines: [String] = []
        switch (route, capability) {
        case (.stdioShim, .measured), (.stdioShim, .documented):
            lines.append(
                "This harness speaks streamable HTTP: point it at the router directly and drop the shim."
            )
        case (.stdioShim, .unknown):
            lines.append("Check whether this harness speaks streamable HTTP; if it does, the shim can go.")
        case (.notWired, _) where exists:
            lines.append("Point this harness at http://127.0.0.1:<port>/mcp.")
        default:
            break
        }
        if !duplicates.isEmpty, route.isWired {
            lines.append("Remove the duplicate entries below; the router already serves them.")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }
}

/// Compare each harness's declared servers against the router's own upstream set.
///
/// Detection and the diff. **Nothing here writes a harness config, and there is no seam that
/// could** — no apply, no writer protocol, no conformer. Spec §7 carries the reason, and
/// `scripts/lint/no-harness-config-writes.sh` keeps it true.
public enum HarnessReconciliation {
    /// One harness against the router's upstreams.
    public static func report(
        client: MCPClient,
        path: String,
        result: ClientConfigResult,
        upstreams: [UpstreamConfig],
        port: Int
    ) -> HarnessReport {
        let capability = HTTPCapability.known(for: client)
        switch result {
        case .absent:
            return empty(client, path, exists: false, unreadable: nil, capability: capability)
        case let .unreadable(reason):
            return empty(client, path, exists: true, unreadable: reason, capability: capability)
        case .declaresNone:
            return empty(client, path, exists: true, unreadable: nil, capability: capability)
        case let .servers(entries):
            return compare(
                Subject(client: client, path: path, capability: capability),
                entries, upstreams: upstreams, port: port
            )
        }
    }

    /// Every harness, in ``MCPClient/allCases`` order, so two runs report the same list.
    public static func reportAll(
        inventory: [ClientConfigReport],
        upstreams: [UpstreamConfig],
        port: Int
    ) -> [HarnessReport] {
        inventory.map {
            report(client: $0.client, path: $0.path, result: $0.result, upstreams: upstreams, port: port)
        }
    }

    private static func empty(
        _ client: MCPClient, _ path: String, exists: Bool, unreadable: String?, capability: HTTPCapability
    ) -> HarnessReport {
        HarnessReport(
            client: client, path: path, unreadable: unreadable, exists: exists, entryCount: 0,
            route: .notWired, capability: capability, duplicates: [], unparsed: []
        )
    }

    /// The three values that travel together through ``compare(_:_:upstreams:port:)`` and say
    /// nothing about the comparison — which harness this is, where its file is, and what is known
    /// about its transport.
    private struct Subject {
        let client: MCPClient
        let path: String
        let capability: HTTPCapability
        /// How this harness spells an endpoint. Per client, so Gemini's `httpUrl` is read where it
        /// means something and nowhere else.
        var dialect: HarnessDialect { .known(for: client) }
    }

    private static func compare(
        _ subject: Subject,
        _ entries: [DiscoveredServer],
        upstreams: [UpstreamConfig],
        port: Int
    ) -> HarnessReport {
        // Detection runs on the entries exactly as the harness wrote them, so the dialect widening
        // in ``HarnessDialect/endpoint(in:)`` is the thing under test rather than something the
        // caller already did for it. The comparison below runs on the canonical form, because that
        // is where the shared parser and the identity digest need one spelling.
        let dialect = subject.dialect
        let route = HarnessRoute.detect(entries: entries, port: port, dialect: dialect)
        let routerEntryName = wiredEntryName(route)
        let others = entries.filter { $0.name != routerEntryName }

        let byName = Set(upstreams.map(\.name))
        var byHash: [String: String] = [:]
        for upstream in upstreams where byHash[UpstreamHash.hash(upstream)] == nil {
            byHash[UpstreamHash.hash(upstream)] = upstream.name
        }

        var duplicates: [Duplicate] = []
        var unparsed: [String] = []
        for entry in others {
            if byName.contains(entry.name) {
                duplicates.append(Duplicate(harnessName: entry.name, routerName: entry.name, basis: .name))
                continue
            }
            // The comparison runs on the canonical form, because that is where the shared parser
            // and the identity digest need one spelling. Detection above ran on the entries exactly
            // as the harness wrote them, so the dialect widening is the thing under test rather
            // than something the caller already did for it.
            let resolved: DiscoveredServer
            switch dialect.resolve(entry) {
            case let .entry(canonical):
                resolved = canonical
            case let .conflict(reason):
                unparsed.append("\(entry.name): \(reason)")
                continue
            }
            switch ServerParser.parse(name: resolved.name, raw: resolved.raw) {
            case let .upstream(parsed):
                let hash = UpstreamHash.hash(parsed)
                guard let routerName = byHash[hash] else { continue }
                duplicates.append(
                    Duplicate(
                        harnessName: resolved.name,
                        routerName: routerName,
                        basis: .identity(hash: hash)
                    )
                )
            case let .skipped(reason):
                unparsed.append("\(resolved.name): \(reason)")
            }
        }

        return HarnessReport(
            client: subject.client, path: subject.path, unreadable: nil, exists: true,
            entryCount: others.count, route: route, capability: subject.capability,
            duplicates: duplicates, unparsed: unparsed
        )
    }

    private static func wiredEntryName(_ route: HarnessRoute) -> String? {
        switch route {
        case .notWired: nil
        case let .directHTTP(name, _): name
        case let .stdioShim(name, _, _): name
        }
    }
}
