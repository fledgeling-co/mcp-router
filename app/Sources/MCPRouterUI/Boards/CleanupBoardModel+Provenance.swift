#if os(macOS)
    import Foundation
    import MCPRouterKit

    /// What the board's two destructive dialogs are allowed to say about the age of the figures in
    /// them, and whether the removal dialog may act at all.
    ///
    /// **A separate file for the reason `ActivityModel+Presentation` is separate**: this is the part
    /// of the model most likely to be read by someone checking an honesty claim, and it is worth
    /// finding in one place. Nothing here writes a `private(set)` property — it reads `state` and the
    /// clock and returns a value — so the split costs the type no write barrier.
    ///
    /// Every decision below is a **value**, never a branch inside a view. A `Provenance` case and a
    /// refusal reason can both be asserted without a host; a `.disabled(board.isStale)` written into
    /// a sheet cannot be, and the one thing this item is about would then live in the one layer this
    /// repo has no test seam for.
    public extension CleanupBoardModel {
        /// Whether every figure this board states is the last reading the router gave rather than a
        /// current one.
        ///
        /// The board draws `StaleReadingBanner` above the table for this. A sheet presented over that
        /// board covers the banner, which is how M7's Phase D findings 4 and 8 reached a destructive
        /// dialog on a board that already discloses the state: the disclosure existed and the modal
        /// hid it.
        var isStale: Bool {
            if case .stale = state { return true }
            return false
        }

        /// The reset dialog's provenance, or `.none` when there is nothing to date.
        ///
        /// `.none` covers two different absences and neither wants a sentence: no reading has landed
        /// at all — the header's `Reset history…` is reachable while the board is still loading — or
        /// a fresh reading whose `usageSummary()` threw, where the consequence already says the
        /// router has not stated how many and there is no figure a date could belong to.
        var resetFigureProvenance: CleanupPresentation.Provenance {
            guard let reading = state.reading else { return .none }
            return CleanupPresentation.resetFigureProvenance(
                observedAt: reading.observedAt,
                isStale: isStale,
                calls: reading.recordedCalls,
                now: clock()
            )
        }

        /// The removal dialog's provenance, or `.none` when no reading has landed.
        ///
        /// The sheet asks for this only on the branch where it has a candidate, and a candidate comes
        /// from a reading — so the `.none` here is unreachable from today's view. It is a `guard`
        /// rather than a force-unwrap because `SWIFT_PRACTICES.md` §3 forbids the second, and because
        /// "unreachable from the one call site" is a claim about the call site rather than about this
        /// function.
        var removeFigureProvenance: CleanupPresentation.Provenance {
            guard let reading = state.reading else { return .none }
            return CleanupPresentation.removeFigureProvenance(
                observedAt: reading.observedAt,
                isStale: isStale,
                now: clock()
            )
        }

        /// The candidate a removal dialog is about, or `nil` once the row has left the reading.
        func candidate(named name: String) -> Candidate? {
            candidates.first { $0.kind == .server && $0.key.id == name }
        }

        /// Why the removal dialog's `Remove` button cannot act, or `nil` when it can.
        ///
        /// **A stale reading is deliberately not a reason.** `.stale` means the last *read* threw; it
        /// does not mean the write will. Dimming here would refuse an act the router may well accept,
        /// and would refuse it hardest in the case a reader most wants it — a wedged router whose
        /// history someone is trying to reset. `DESIGN.md` §9 scales friction to blast radius, and
        /// staleness does not change the blast radius; the typed write error already lands in place
        /// beside the control when a POST does fail (§5 Error).
        ///
        /// A missing candidate **is** a reason, and a different one in kind: there the disclosure is
        /// absent rather than old, and §9 does not allow an irreversible act to be offered with no
        /// consequence stated at all.
        ///
        /// On the model rather than in the sheet so that both halves — that a gone row refuses and
        /// that a stale reading does not — are assertable without a host.
        func removalRefusalReason(for name: String) -> String? {
            candidate(named: name) == nil ? CleanupPresentation.consequenceUnavailable : nil
        }
    }
#endif
