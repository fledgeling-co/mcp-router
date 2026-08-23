import Foundation

/// How a harness reaches this router — one of exactly four readings, never a boolean.
///
/// A boolean would hide the reading that matters most: a harness that *is* routed and is paying
/// for a bridge process at every session, or one that is routed and still declaring its own copies
/// of servers this router already fronts. Both look like a tick.
///
/// **Closed on the wire, closed here.** A fifth transport fails decoding rather than being
/// defaulted into one of these, which is `SWIFT_PRACTICES.md` §2's rule and is what makes the
/// view's exhaustive switch a real guarantee: a router that grows a fifth reading cannot render as
/// one of the four this build knows.
public enum HarnessReading: String, Codable, Hashable, Sendable, CaseIterable {
    case notRouted = "not-wired"
    case routedOverHTTP = "wired-http"
    case routedViaShim = "wired-shim"
    case routedWithDirectServers = "wired-with-duplicates"
}

/// The transport behind the reading. Carried separately because it survives inside
/// ``HarnessReading/routedWithDirectServers``: a harness can be shimmed *and* duplicating, and the
/// shim's cost does not stop being real because there is a second finding on the same row.
public enum HarnessTransport: String, Codable, Hashable, Sendable, CaseIterable {
    case none
    case http
    case stdioShim = "stdio-shim"
}

/// Who established that this harness can speak streamable HTTP without a bridge.
///
/// It changes the **remedy**, never the reading. A harness on a shim is on a shim whatever its
/// capability; what moves is whether the honest next step is "point it at the router directly" or
/// "find out whether it can be".
public enum HarnessCapabilityProvenance: String, Codable, Hashable, Sendable, CaseIterable {
    case measured
    case documented
    case unknown
}

/// One entry a harness declares that this router already serves.
public struct HarnessDuplicate: Codable, Hashable, Sendable, Identifiable {
    /// What the **harness** calls it — the line a user has to find in their own file.
    public var harnessName: String
    /// What the **router** calls it. Different from `harnessName` under `.identity`, which is the
    /// case worth printing both halves of.
    public var routerName: String
    public var basis: Basis

    /// What made the two entries the same server.
    public enum Basis: String, Codable, Hashable, Sendable, CaseIterable {
        case name
        case identity
    }

    public var id: String { "\(harnessName)|\(routerName)" }

    public init(harnessName: String, routerName: String, basis: Basis) {
        self.harnessName = harnessName
        self.routerName = routerName
        self.basis = basis
    }
}

/// One harness found on this Mac, as `GET /harnesses` reports it.
///
/// **`unreadable` is the field to read first.** A config the router could not parse arrives as the
/// *empty* report — `state` says `not-wired`, `entries` and `duplicateCount` say 0 — which is
/// byte-identical to a clean unwired harness. This field is the only thing that tells them apart,
/// and the distinction has already cost one confident wrong answer against `~/.grok/config.toml`.
public struct DetectedHarness: Codable, Hashable, Sendable, Identifiable {
    public var harness: String
    public var displayName: String
    /// Where this harness's configuration lives. The router supplies it; the app never resolves a
    /// path of its own, because it is not allowed to read one.
    public var path: String
    public var exists: Bool
    public var unreadable: String?
    public var state: HarnessReading
    public var route: HarnessTransport
    /// What bridges a shimmed harness to the router — `mcp-remote` and its kind.
    public var bridge: String?
    /// Servers this harness declares other than the router entry itself.
    public var entries: Int
    public var duplicateCount: Int
    public var duplicates: [HarnessDuplicate]
    /// Entries the router could not parse, with the reason. Reported rather than dropped: an entry
    /// nobody could read is not evidence that it is not a duplicate.
    public var unparsed: [String]
    /// The capability sentence, with its provenance in its own words.
    public var httpCapability: String
    public var capability: HarnessCapabilityProvenance

    public var id: String { harness }

    public init(
        harness: String,
        displayName: String,
        path: String,
        exists: Bool,
        unreadable: String? = nil,
        state: HarnessReading,
        route: HarnessTransport,
        bridge: String? = nil,
        entries: Int,
        duplicateCount: Int,
        duplicates: [HarnessDuplicate] = [],
        unparsed: [String] = [],
        httpCapability: String,
        capability: HarnessCapabilityProvenance
    ) {
        self.harness = harness
        self.displayName = displayName
        self.path = path
        self.exists = exists
        self.unreadable = unreadable
        self.state = state
        self.route = route
        self.bridge = bridge
        self.entries = entries
        self.duplicateCount = duplicateCount
        self.duplicates = duplicates
        self.unparsed = unparsed
        self.httpCapability = httpCapability
        self.capability = capability
    }
}

public struct HarnessesResponse: Codable, Hashable, Sendable {
    public var port: Int
    /// `global` today. Project-scoped entries are not read — R7-C4 owns that, and R16 is the same
    /// blind spot from the adoption side.
    public var scope: String
    /// When the configs were read. The board's staleness clock, because these counts are only as
    /// fresh as the last read and a stale reading here is worse than no reading.
    public var readAt: String
    public var harnesses: [DetectedHarness]

    public init(port: Int, scope: String, readAt: String, harnesses: [DetectedHarness]) {
        self.port = port
        self.scope = scope
        self.readAt = readAt
        self.harnesses = harnesses
    }
}
