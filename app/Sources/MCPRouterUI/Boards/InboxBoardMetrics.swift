#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Column widths and paddings for the Inbox board, derived rather than picked.
    ///
    /// Same construction as the Discover, Skills and Servers boards': `DESIGN.md` §2 documents the
    /// dense-table unit, the selection inset and the control ladder but not a column width, because a
    /// column width is a consequence of content. `SWIFT_PRACTICES.md` §5 forbids a hardcoded size, so
    /// every value here is a multiple of a documented token.
    enum InboxBoardMetrics {
        private static var unit: Double { MetricToken.tableRows.leadingScalar }
        private static var inset: Double { MetricToken.selectionInset.leadingScalar }

        static var hairline: Double { MetricToken.focusRing.leadingScalar / 2 }
        static var labelGap: Double { MetricToken.focusRing.leadingScalar }
        static var tightGap: Double { inset }
        static var gap: Double { inset * 2 }
        static var rowPadding: Double { MetricToken.selectionRadius.leadingScalar }
        static var panePadding: Double { MetricToken.selectionRadius.leadingScalar * 2 }

        /// The row tile, at `DESIGN.md` §4's row size (30pt, radius 7).
        static var tile: Double { unit + inset * 1.5 }
        static var tileRadius: Double { inset + MetricToken.focusRing.leadingScalar / 2 }
        /// The review sheet's tile, at §4's detail size (64pt, radius 14).
        static var detailTile: Double { unit * 2 + unit * 2 / 3 }
        static var detailTileRadius: Double { MetricToken.selectionRadius.leadingScalar + inset + 2 }

        static var nameColumn: Double { unit * 8 }
        /// The capability headline's column. Wide, because the headline is the sentence the whole
        /// row exists to carry — "Runs a program on this Mac" truncated to "Runs a program on…"
        /// loses the words that matter.
        ///
        /// **There is no eval column, and its absence is deliberate.** The prototype draws one from
        /// its mock's `ev` field; `RegistryEntry` has no evaluation of any kind, and neither index
        /// publishes one. M7's vocabulary describes checks the router ran against a *declared*
        /// server or an installed skill — a queued item is neither, so there is nothing observed to
        /// report. A column here would be `DESIGN.md` §6's forbidden number in words.
        static var capabilityColumn: Double { unit * 9 }

        /// Fixed, and identical in the skeleton. `DESIGN.md` §2 gives 56pt for the equivalent
        /// dense row, and §5's Overflow rule is that rows never change height — a row that grew for
        /// a long name would make the board jump as items arrive.
        static var rowHeight: Double { unit * 2 }

        static var sheetWidth: Double { MetricToken.sidebar.leadingScalar * 2 }

        /// The QR's drawn size. Large enough that a phone camera resolves it at arm's length across
        /// a desk, and expressed in the sidebar unit so it moves with the rest of the system.
        static var qrSize: Double { MetricToken.sidebar.leadingScalar - unit * 2 }
        static var qrRadius: Double { MetricToken.selectionRadius.leadingScalar }
    }

    /// Where each of `DESIGN.md` §5's nine states is met on this board.
    ///
    /// Declared exhaustively so a tenth `SurfaceState` case stops this compiling — the moment someone
    /// should be deciding what it looks like, rather than the moment a user meets an unhandled
    /// screen.
    enum InboxBoardStates {
        static func treatment(for state: SurfaceState) -> String {
            switch state {
            case .populated: "LoadState.loaded with rows — the table"
            case .empty: "InboxCopy.emptyTitle + emptyDetail, with pairing as the one action"
            case .loading: "LoadState.loading — InboxSkeletonRows at InboxBoardMetrics.rowHeight"
            case .partial:
                "InboxItem.resolved == nil — the row lists, says why, and cannot be accepted"
            case .error: "LoadState.failed — InboxCopy.readFailure, or the stale banner on LoadState.stale"
            case .success: "the row leaves `rows` in place, with the undo line beneath — never a toast"
            case .offline:
                """
                ControlAPIError.routerNotRunning on accept — the queue still lists and the action \
                dims with that reason
                """
            case .disabled:
                """
                accept dims for an unresolved entry, for a missing requirement, or while the router \
                is down
                """
            case .overflow: "InboxBoardRow — one line per field, tail truncation, fixed row height"
            }
        }
    }

    /// Where each of the nine is met on the **pairing sheet**, which is a different surface with a
    /// different set of conditions and so needs its own declaration.
    enum PairingSheetStates {
        static func treatment(for state: SurfaceState) -> String {
            switch state {
            case .populated: "Phase.live — the QR, the code, the countdown"
            case .empty:
                """
                not a state here: a sheet with no code is Phase.noEndpoint or .preparing, both of \
                which say why rather than reading as empty
                """
            case .loading: "Phase.preparing — InboxCopy.Pairing.preparing"
            case .partial: "not a state here: a code is whole or it has not been issued"
            case .error: "Phase.failed — the issue attempt failed, stated rather than blank"
            case .success: "InboxCopy.Pairing.paired(with:) in place, no toast"
            case .offline:
                """
                Phase.noEndpoint — the state a Release build reaches, because this build ships no \
                way to listen for a phone
                """
            case .disabled: "the typed-code commit stays dim until eight characters are entered"
            case .overflow: "a long Mac name truncates; the code and the QR never wrap"
            }
        }
    }
#endif
