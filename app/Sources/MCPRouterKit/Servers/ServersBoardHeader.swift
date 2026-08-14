import Foundation

// The Servers board's header — the three figures under the title, and how much they may claim.
//
// Split out of `ServerPresentation.swift` when that file crossed the 400-line limit. The split is
// along a real seam rather than at a convenient line: everything left in that file describes one
// *row*, and this describes the *board*. Trimming the explanations instead would have bought the
// same six lines by deleting the reasoning this repository keeps deliberately.

/// The three figures under the board's title, and the one that goes absent.
public struct ServersBoardHeader: Equatable, Sendable {
    /// How much the header may claim.
    ///
    /// **Three cases, because a boolean produced a lie.** With `isCurrent: Bool`, `.loading` fell to
    /// the not-current branch and rendered "0 tools from 0 servers · last reading, not current" on
    /// every cold start, before any poll had answered — the zeros fabricated, and the sentence
    /// asserting a prior reading that had never happened. The stale wording exists for a router that
    /// answered once and has since gone quiet, which is a different thing.
    public enum Reading: Equatable, Sendable {
        /// A poll has answered and this is what it said.
        case current
        /// A poll answered earlier; the refresh has since broken.
        case stale
        /// No poll has answered yet. Nothing may be claimed at all.
        case none
    }

    public let tools: Int
    public let servers: Int
    /// **`nil` on a stale load, and that is the point.** "1 running" is a present-tense claim about
    /// a router that is not currently answering. Showing the last known figure as though it were
    /// current is a quieter lie than showing a zero, and the same kind — M1 draws this line for the
    /// readout and this is the same line on the board. Optional rather than a flag beside an `Int`,
    /// so the absent case cannot be rendered by accident.
    public let running: Int?
    /// Servers whose index failed, so their tools are missing from `tools`.
    ///
    /// The router reports `tools: 0` and `toolNames: []` for a server with an `indexError`
    /// (`src/control.ts` — `entry?.error ? 0 : …`), so the total genuinely understates. `DESIGN.md`
    /// §5's Partial state is "say what arrived and what did not, with the reason", and this is the
    /// count that makes that sentence sayable.
    public let unindexed: Int

    public let reading: Reading

    public init(servers list: [MCPServer], reading: Reading) {
        self.reading = reading
        tools = list.reduce(0) { $0 + $1.tools }
        servers = list.count
        running = reading == .current ? list.filter { $0.state == .running }.count : nil
        unindexed = list.filter { $0.indexError != nil }.count
    }

    /// The subtitle line.
    ///
    /// **There is no timestamp here, and its absence is deliberate.** A phrase like "as of 14:32" or
    /// "last read 2m ago" needs the moment the poll answered, and nothing observes it: `LoadState`
    /// carries servers and an error, and no `apply` entry point records a time. An earlier draft
    /// derived one from the newest `lastUsed` across the servers, which is when a *tool was called* —
    /// a different fact wearing the same clothes, and precisely the invention §6 exists to stop.
    ///
    /// So the stale form claims no precision. It says the reading is not current, which is the whole
    /// of what is actually known.
    public func subtitle() -> String {
        // Nothing has answered, so there is no count to give and no reading to describe. A figure
        // here would be a fabricated zero, which is the same defect as a fabricated total.
        guard reading != .none else { return "Reading the router…" }
        let noun = servers == 1 ? "server" : "servers"
        let head = "\(tools) tools from \(servers) \(noun)"
        if let running {
            return "\(head) · \(running) running"
        }
        return "\(head) · last reading, not current"
    }

    /// The Partial note, or nil when everything indexed.
    public var partialNote: String? {
        guard unindexed > 0 else { return nil }
        let subject = unindexed == 1 ? "One server" : "\(unindexed) servers"
        let verb = unindexed == 1 ? "its" : "their"
        return """
        \(subject) could not be indexed, so \(verb) tools are missing from this count. \
        Those rows say why.
        """
    }
}
