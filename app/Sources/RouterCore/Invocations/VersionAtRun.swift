import Foundation

/// What version a capability was at when a run happened — or why nothing may be credited.
///
/// **This type is the item.** The brief asks for "the exact version of each tool at the moment it
/// was executed", and the honest answer for most historical runs on this machine is that it is not
/// recoverable: a session transcript names the skill and the time and never the version (measured
/// 2026-08-29 — the `version` on a Claude Code transcript line is `2.1.2xx`, the harness's own), and
/// `installed_plugins.json` keeps one `lastUpdated` rather than a history.
///
/// So the choice is between crediting today's version to yesterday's run and refusing. Refusing is
/// what the design of record's own callout requires — *"a run against 1.4.0 never counts toward
/// 1.4.2's evidence"* — printed, in that mock, under a table that does the opposite.
public enum VersionAtRun: Sendable, Hashable {
    /// The boundary set puts this capability at this version across the whole of the run's moment.
    /// `since` is the boundary the claim rests on.
    case attributed(String, since: String)
    /// A boundary **after** the run asserts a different version, so the change happened at some
    /// moment in between and the run may have been on either side of it. Counted toward nothing.
    case superseded(movedAt: String)
    /// No boundary reaches this run at all, or its timestamp is not a shape that can be ordered.
    case unestablished(reason: String)

    public var version: String? {
        if case let .attributed(version, _) = self { return version }
        return nil
    }

    /// The word a wire member carries, so a consumer branches on the outcome rather than on whether
    /// a version string happens to be present.
    public var outcome: String {
        switch self {
        case .attributed: "attributed"
        case .superseded: "superseded"
        case .unestablished: "unestablished"
        }
    }
}

public extension VersionLedger {
    /// The join, and the whole of the reasoning behind it.
    ///
    /// A boundary asserts *at `ts`, this capability was at `version`* — nothing wider. Two
    /// consecutive boundaries carrying different versions therefore bracket a change whose **moment
    /// is unknown**: the router observed `U` at `ts_p` and `V` at `ts_b`, and the swap happened
    /// somewhere in between. A run inside that interval could have been on either side of it.
    ///
    /// So a run is attributed only when the newest boundary at or before it says `V` **and no later
    /// boundary disagrees**. That is deliberately conservative, and the alternative it beats is the
    /// one that produces the big numbers: take the newest boundary at or before the run and stop
    /// looking. That credits every run in an unresolved interval to whichever version happened to be
    /// observed first, and its right answer and its wrong answer are the same shade of green.
    ///
    /// A later boundary carrying the **same** version is confirming evidence, not a supersession —
    /// nothing moved, so nothing is in doubt.
    func version(of kind: CapabilityKind, _ name: String, at runTimestamp: String) -> VersionAtRun {
        guard VersionLedger.isOrderable(runTimestamp) else {
            return .unestablished(reason: "the run's timestamp is not a fixed-width UTC instant")
        }
        let rows = boundaries(kind, name)
        guard let earliest = rows.first else {
            return .unestablished(reason: "no version boundary is recorded for \(name)")
        }
        guard runTimestamp >= earliest.ts else {
            return .unestablished(
                reason: "the run predates the oldest boundary held for \(name) (\(earliest.ts))"
            )
        }
        // The newest boundary at or before the run. `rows` is oldest first, so the last one whose
        // stamp does not exceed the run's is it.
        var standing = earliest
        for row in rows where row.ts <= runTimestamp {
            standing = row
        }
        // Anything later that disagrees puts the change on an unknown side of the run.
        if let moved = rows.first(where: { $0.ts > runTimestamp && $0.version != standing.version }) {
            return .superseded(movedAt: moved.ts)
        }
        return .attributed(standing.version, since: standing.ts)
    }

    /// `YYYY-MM-DDTHH:MM:SS.sssZ` — the shape ``JSDate/iso8601(milliseconds:)`` writes and the shape
    /// Claude Code stamps a transcript line with.
    ///
    /// Checked rather than assumed, because the ordering above is a **string** comparison and that
    /// is only chronological while the width is fixed. A six-digit fractional part sorts
    /// `…30.333543Z` *before* `…30.33Z`, since `'3' < 'Z'` — so one foreign timestamp in the corpus
    /// would not fail loudly, it would silently reorder two runs around a boundary. Codex writes
    /// exactly that shape (measured 2026-08-29), which is why this is a real guard and not a
    /// defensive habit.
    static func isOrderable(_ timestamp: String) -> Bool {
        let characters = Array(timestamp)
        guard characters.count == 24, characters[23] == "Z",
              characters[4] == "-", characters[7] == "-", characters[10] == "T",
              characters[13] == ":", characters[16] == ":", characters[19] == "."
        else { return false }
        let digits: [Int] = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18, 20, 21, 22]
        return digits.allSatisfy { characters[$0].isASCII && characters[$0].isNumber }
    }
}
