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
        /// Six units, not four. Measured on the rendered board: `2,984 sessions` in the instrument
        /// face needs ~130pt, and at four units it truncated to `2,984 sessi…` — which loses the
        /// **unit**, and the unit is the entire reason this column exists. A bare `2,984` beside a
        /// `9` on the next row reads as one scale, and they are not on one scale.
        static var figureColumn: Double { unit * 6 }
        static var dateColumn: Double { unit * 5 }
        static var stateColumn: Double { unit * 3 }
        static var searchWidth: Double { unit * 10 }

        /// The narrowest this board's search field may become before the row stops fitting.
        ///
        /// **Four units, and it is a floor rather than a size.** The field renders at
        /// `searchWidth` whenever there is room; this is what it gives back when there is not.
        /// Measured on glass at a 980pt window, which is an ordinary size and not a stress case:
        /// this board's controls row is a `.fixedSize()` segmented picker that cannot compress at
        /// all, plus this field, and the two together wanted more than the detail pane had. The
        /// board then laid out wider than the pane and its trailing chrome was cut — DEF-015.
        ///
        /// A field this narrow shows about eight characters, which is less than anyone wants and
        /// more than nothing: it still takes focus, still accepts a query, and still submits.
        /// Losing eight characters of a search field at the narrowest window this app is used at
        /// is a better trade than losing whichever control happened to sit at the right edge.
        static var searchMinWidth: Double { unit * 4 }

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
                """
                a scoped ordering segment with an empty universe; the sheet's action when \
                installed or uninstallable
                """
            case .overflow: "DiscoverBoardRow — one line per field, tail truncation, fixed row height"
            }
        }
    }
#endif
