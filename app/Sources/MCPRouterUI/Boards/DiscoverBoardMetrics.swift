#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Column widths and paddings for the Discover board, derived rather than picked.
    ///
    /// Same construction as the Skills and Servers boards': `DESIGN.md` §2 documents the dense-table
    /// unit, the selection inset and the control ladder but not a column width, because a column
    /// width is a consequence of content. `SWIFT_PRACTICES.md` §5 forbids a hardcoded size, so every
    /// value here is a multiple of a documented token and a change to the token moves the grid.
    enum DiscoverBoardMetrics {
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
        /// The detail tile, at §4's detail size (64pt, radius 14).
        static var detailTile: Double { unit * 2 + unit * 2 / 3 }
        static var detailTileRadius: Double { MetricToken.selectionRadius.leadingScalar + inset + 2 }

        static var nameColumn: Double { unit * 9 }
        static var markColumn: Double { unit * 2 }
        static var figureColumn: Double { unit * 4 }
        static var dateColumn: Double { unit * 5 }
        static var stateColumn: Double { unit * 3 }
        static var searchWidth: Double { unit * 10 }

        /// Fixed, and identical in the skeleton. A row whose height depends on its content makes the
        /// board jump when data lands, and §5's Overflow rule is that rows never change height.
        static var rowHeight: Double { unit * 2 }

        static var sheetWidth: Double { MetricToken.sidebar.leadingScalar * 2 }

        /// The provenance mark's two cells.
        static var markCell: Double { unit / 2 + inset / 2 }
        static var markRadius: Double { MetricToken.focusRing.leadingScalar }
    }

    /// Where each of `DESIGN.md` §5's nine states is met on this board.
    ///
    /// Declared exhaustively so a tenth `SurfaceState` case stops this compiling — the moment
    /// someone should be deciding what it looks like, rather than the moment a user meets an
    /// unhandled screen. The nine are not alternatives: four are load states, and Success, Disabled
    /// and Overflow are properties a *populated* board also has, all at once.
    enum DiscoverBoardStates {
        static func treatment(for state: SurfaceState) -> String {
            switch state {
            case .populated: "LoadState.loaded with rows — the table"
            case .empty:
                "RegistryPresentation.emptyMessage — three distinct empties, keyed on query and ordering"
            case .loading: "LoadState.loading — DiscoverSkeletonRows at DiscoverBoardMetrics.rowHeight"
            case .partial:
                "RegistryPresentation.footerNotes on a loaded board; StaleReadingBanner on LoadState.stale"
            case .error: "LoadState.failed — ConnectionFailurePane from ControlAPIError"
            case .success:
                "install returns AddedServer — the row gains `installed` and the sheet's action becomes Added"
            case .offline: "ControlAPIError.routerNotRunning, in either failed or stale"
            case .disabled:
                "a scoped ordering segment with an empty universe; the sheet's action when installed or uninstallable"
            case .overflow: "DiscoverBoardRow — one line per field, tail truncation, fixed row height"
            }
        }
    }
#endif
