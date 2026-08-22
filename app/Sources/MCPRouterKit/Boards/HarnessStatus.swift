import Foundation

/// A harness's reading, with everything that reading's own sentence needs.
///
/// The brief asks for four readings *each with its own honest sentence*, and this type is what
/// makes that true rather than aspirational: **the sentence belongs to the case**. A row that built
/// its own string would let two surfaces describe one state two ways, which is exactly what
/// `DESIGN.md` §6's "one name per state, taken from one source" forbids — and it is how a shim's
/// cost quietly becomes a tick somewhere.
///
/// Four cases and no `default` anywhere that switches on it, so a fifth transport cannot be added
/// without the views failing to compile.
public enum HarnessStatus: Hashable, Sendable {
    /// Not routed. `entries` is what it declares instead, and `overlapping` is how many of those
    /// this router already fronts — which is the sentence's whole point when it is not zero.
    case notRouted(entries: Int, overlapping: Int)
    /// Routed straight at the endpoint. The state the product exists to produce.
    case routedOverHTTP
    /// Routed, through a bridge process. One extra process per session, named rather than hidden.
    case routedViaShim(bridge: String?)
    /// Routed **and** still declaring servers this router already serves.
    case routedWithDirectServers(transport: HarnessTransport, bridge: String?, duplicates: Int, entries: Int)

    /// Read the reading off a row. The only constructor, so nothing derives a status by inspecting
    /// counts at a call site.
    public init(_ row: DetectedHarness) {
        switch row.state {
        case .notRouted:
            self = .notRouted(entries: row.entries, overlapping: row.duplicateCount)
        case .routedOverHTTP:
            self = .routedOverHTTP
        case .routedViaShim:
            self = .routedViaShim(bridge: row.bridge)
        case .routedWithDirectServers:
            self = .routedWithDirectServers(
                transport: row.route,
                bridge: row.bridge,
                duplicates: row.duplicateCount,
                entries: row.entries
            )
        }
    }

    /// The short label on the row's pill. Sentence case, per `DESIGN.md` §6.
    public var label: String {
        switch self {
        case .notRouted: "Not routed"
        case .routedOverHTTP: "Routed over HTTP"
        case .routedViaShim: "Routed through a stdio shim"
        case let .routedWithDirectServers(_, _, _, entries):
            "Routed, plus \(entries) direct server\(entries == 1 ? "" : "s")"
        }
    }

    /// The honest sentence under the label.
    ///
    /// Each one names the actual cost rather than reporting a condition. The shim's is the sentence
    /// the brief singles out: a bridge is a real process per session, and saying so is the whole
    /// difference between this board and a column of ticks.
    public var sentence: String {
        switch self {
        case let .notRouted(entries, overlapping):
            notRoutedSentence(entries: entries, overlapping: overlapping)
        case .routedOverHTTP:
            "Sessions reach every server this router fronts through one endpoint, and start no "
                + "child processes of their own to do it."
        case let .routedViaShim(bridge):
            "It reaches the router through \(bridge ?? "a bridge process"), which is one extra "
                + "process per session. That is a real cost, and it is named here rather than "
                + "shown as a clean tick."
        case let .routedWithDirectServers(transport, bridge, duplicates, entries):
            directServersSentence(
                transport: transport, bridge: bridge, duplicates: duplicates, entries: entries
            )
        }
    }

    /// Whether this reading wants a human decision — the one thing on this board allowed to carry
    /// the attention colour, and only because §6 requires a word beside it, which `label` is.
    public var wantsAttention: Bool {
        switch self {
        case .routedOverHTTP: false
        case let .notRouted(_, overlapping): overlapping > 0
        case .routedViaShim, .routedWithDirectServers: true
        }
    }

    private func notRoutedSentence(entries: Int, overlapping: Int) -> String {
        guard entries > 0 else {
            return "Nothing in this harness points at the router, and it declares no servers of "
                + "its own either. Wiring it is one entry and nothing to clean up."
        }
        guard overlapping > 0 else {
            return "Nothing in this harness points at the router. Its \(entries) server"
                + "\(entries == 1 ? "" : "s") start at every session, whether or not that session "
                + "uses \(entries == 1 ? "it" : "them")."
        }
        return "It runs \(entries) server\(entries == 1 ? "" : "s") of its own, \(overlapping) of "
            + "which this router already fronts. Those \(overlapping) start at every session and "
            + "serve what one endpoint already serves."
    }

    private func directServersSentence(
        transport: HarnessTransport, bridge: String?, duplicates: Int, entries: Int
    ) -> String {
        let shim = transport == .stdioShim
            ? " It also reaches the router through \(bridge ?? "a bridge process"), so its "
            + "sessions pay both costs at once."
            : ""
        guard duplicates > 0 else {
            return "It is pointed at the router and still declares \(entries) server"
                + "\(entries == 1 ? "" : "s") of its own, which start at every session.\(shim)"
        }
        return "\(duplicates) of its \(entries) own server\(entries == 1 ? "" : "s") duplicate "
            + "upstreams this router already serves. Removing them changes nothing an agent can "
            + "do and stops \(duplicates) process\(duplicates == 1 ? "" : "es") starting at every "
            + "session.\(shim)"
    }
}
