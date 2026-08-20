#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Column widths and paddings for the Skills board, derived rather than picked.
    ///
    /// Same construction as the Servers board's: `DESIGN.md` §2 documents the dense-table unit, the
    /// selection inset and the control ladder, but not a column width — a column width is a
    /// consequence of content. `SWIFT_PRACTICES.md` §5 forbids a hardcoded size, so every value here
    /// is a multiple of a documented token and a change to the token moves the whole grid.
    enum SkillsBoardMetrics {
        private static var unit: Double { MetricToken.tableRows.leadingScalar }
        private static var inset: Double { MetricToken.selectionInset.leadingScalar }

        /// One point, expressed as half the focus ring rather than as `1`. Used for the hairline
        /// between rows and for the tightest label stacks, so a change to the ring's documented
        /// width moves them with it instead of leaving a literal behind.
        static var hairline: Double { MetricToken.focusRing.leadingScalar / 2 }
        /// Two points — the gap inside a two-line label, and between slot pips.
        static var labelGap: Double { MetricToken.focusRing.leadingScalar }
        static var tightGap: Double { inset }
        static var gap: Double { inset * 2 }
        static var rowPadding: Double { MetricToken.selectionRadius.leadingScalar }
        static var panePadding: Double { MetricToken.selectionRadius.leadingScalar * 2 }

        /// The row tile, at `DESIGN.md` §4's row size.
        static var tile: Double { unit + inset * 1.5 }
        static var tileRadius: Double { inset + MetricToken.focusRing.leadingScalar / 2 }

        static var nameColumn: Double { unit * 8 }
        static var slotsColumn: Double { unit * 5.5 }
        static var versionColumn: Double { unit * 4 }
        static var slotWidth: Double { unit + inset }
        static var searchWidth: Double { unit * 9 }

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

        static var inspectorWidth: Double { MetricToken.sidebar.leadingScalar + unit * 2 }
        static var sheetWidth: Double { MetricToken.sidebar.leadingScalar * 2 }
    }

    /// Where each of `DESIGN.md` §5's nine states is met on this board.
    ///
    /// Declared exhaustively so a tenth `SurfaceState` case stops this compiling — which is the
    /// moment someone should be deciding what it looks like, rather than the moment a user meets an
    /// unhandled screen. Each entry names the place the state is actually rendered, so the claim is
    /// checkable by reading rather than by hoping.
    ///
    /// The nine are not alternatives to one another: four are load states, and Success, Disabled and
    /// Overflow are properties a *populated* board also has, all at once.
    enum SkillsBoardStates {
        static func treatment(for state: SurfaceState) -> String {
            switch state {
            case .populated: "LoadState.loaded with rows — the table"
            case .empty: "LoadState.loaded with no skills — SkillPresentation.emptyTitle/emptyDetail"
            case .loading: "LoadState.loading — SkillSkeletonRows at SkillsBoardMetrics.rowHeight"
            case .partial:
                "SkillPresentation.partialNote on a loaded board; StaleReadingBanner on LoadState.stale"
            case .error: "LoadState.failed — ConnectionFailurePane from ControlAPIError"
            case .success:
                "not reachable in M4 — the board is read-only, and every write control is disabled in place"
            case .offline: "ControlAPIError.routerNotRunning, in either failed or stale"
            case .disabled: "DisabledAction with SkillPresentation.writesNotYetAvailable, per control"
            case .overflow: "SkillsBoardRow — one line per field, tail truncation, fixed row height"
            }
        }
    }
#endif
