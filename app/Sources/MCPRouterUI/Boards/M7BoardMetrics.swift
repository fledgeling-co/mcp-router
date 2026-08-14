#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The grid both M7 panes draw on.
    ///
    /// **One enum for two boards, deliberately** — the plan named two files and this is the stated
    /// deviation. Evals and Cleanup are sibling surfaces with the same row height, the same tile and
    /// the same column rhythm; two near-identical metrics files are two things that can drift apart
    /// while nobody is comparing them side by side, which is the same argument `MessageState` already
    /// won for the unhappy states.
    ///
    /// Every value is a multiple of a documented token, per `SWIFT_PRACTICES.md` §5 — a column width
    /// is a consequence of content, so a change to the token moves the whole grid rather than leaving
    /// a literal behind. In particular the row height is `unit * 2`, matching Servers and Skills
    /// exactly; the spec's earlier "44pt" would have been a hardcoded size *and* would have made
    /// these two boards a different height from every other board in the app.
    enum M7BoardMetrics {
        private static var unit: Double { MetricToken.tableRows.leadingScalar }
        private static var inset: Double { MetricToken.selectionInset.leadingScalar }

        static var hairline: Double { MetricToken.focusRing.leadingScalar / 2 }
        static var labelGap: Double { MetricToken.focusRing.leadingScalar }
        static var tightGap: Double { inset }
        static var gap: Double { inset * 2 }
        static var rowPadding: Double { MetricToken.selectionRadius.leadingScalar }
        static var panePadding: Double { MetricToken.selectionRadius.leadingScalar * 2 }

        static var tile: Double { unit + inset * 1.5 }
        static var tileRadius: Double { inset + MetricToken.focusRing.leadingScalar / 2 }

        static var nameColumn: Double { unit * 7.5 }
        static var kindColumn: Double { unit * 2.5 }
        static var tallyColumn: Double { unit * 7 }
        static var stampColumn: Double { unit * 6 }
        static var reasonColumn: Double { unit * 9 }
        static var searchWidth: Double { unit * 9 }

        /// Fixed, and identical in the skeleton, so neither board jumps when data lands (A27).
        static var rowHeight: Double { unit * 2 }

        static var inspectorWidth: Double { MetricToken.sidebar.leadingScalar + unit * 2 }
        static var sheetWidth: Double { MetricToken.sidebar.leadingScalar * 2 }

        /// The observation track: as tall as a hairline is thick times six, and as wide as the tally.
        static var trackHeight: Double { inset * 1.5 }
        static var trackWidth: Double { unit * 6 }
    }

    /// Where each of `DESIGN.md` §5's nine states is met on the Evals board.
    ///
    /// Exhaustive over `SurfaceState`, so a tenth case stops this compiling — which is the moment
    /// someone should be deciding what it looks like, rather than the moment a user meets an
    /// unhandled screen. M4's device, and the reason "all nine states ship" is checkable by compiler
    /// rather than by reading.
    enum EvalsBoardStates {
        static func treatment(for state: SurfaceState) -> String {
            switch state {
            case .populated: "LoadState.loaded with subjects — the table"
            case .empty: "LoadState.loaded with no servers and no skills — CheckCopy.evalsEmptyTitle"
            case .loading: "LoadState.loading — M7SkeletonRows at M7BoardMetrics.rowHeight"
            case .partial:
                "an unreadable client leaves reachability not observed; StaleReadingBanner on LoadState.stale"
            case .error: "LoadState.failed — ConnectionFailurePane from ControlAPIError"
            case .success:
                "a re-check lands in place: tally and stamp update, history gains a row, no toast"
            case .offline: "ControlAPIError.routerNotRunning, in either failed or stale"
            case .disabled: "DisabledAction with CheckCopy.runChecksNeedsSelection"
            case .overflow: "EvalsBoardRow — one line per field, tail truncation, fixed row height"
            }
        }
    }

    /// The same, for Cleanup.
    enum CleanupBoardStates {
        static func treatment(for state: SurfaceState) -> String {
            switch state {
            case .populated: "LoadState.loaded with candidates — the proposal"
            case .empty: "nothing is a candidate — CleanupPresentation.emptyTitle, and no action"
            case .loading: "LoadState.loading — M7SkeletonRows at M7BoardMetrics.rowHeight"
            case .partial: "an unreadable client holds every skill out — CleanupPresentation.heldOutBanner"
            case .error: "a refused removal leaves the row in place, with the router's own message"
            case .success: "the row leaves, counts decrement, and nothing is tallied as reclaimed"
            case .offline: "ControlAPIError.routerNotRunning, in either failed or stale"
            case .disabled: "DisabledAction with CheckCopy.skillRemoveDisabled on a skill row"
            case .overflow:
                "CleanupBoardRow truncates at a fixed height; the track pegs full beyond 30 days"
            }
        }
    }
#endif
