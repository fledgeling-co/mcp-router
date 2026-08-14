#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    // MARK: - Geometry the design authority does not name

    /// Column widths and paddings, derived rather than picked.
    ///
    /// `DESIGN.md` §2 documents the row height, the control ladder, the selection inset and the
    /// focus ring; it does not document this board's column widths, because a column width is a
    /// consequence of content rather than a design token. `SWIFT_PRACTICES.md` §5 forbids
    /// hardcoding a size, so these are expressed as multiples of the documented dense-table unit
    /// (`MetricToken.tableRows`, 24pt) and the selection inset. Nothing here is a number chosen by
    /// eye, and a change to the documented unit moves the whole grid with it.
    enum ServersBoardMetrics {
        private static var unit: Double { MetricToken.tableRows.leadingScalar }
        private static var inset: Double { MetricToken.selectionInset.leadingScalar }

        static var hairline: Double { MetricToken.focusRing.leadingScalar / 2 }
        static var tightGap: Double { inset }
        static var gap: Double { inset * 2 }
        static var sectionGap: Double { inset * 4 }
        static var rowPadding: Double { MetricToken.selectionRadius.leadingScalar }
        static var panePadding: Double { MetricToken.selectionRadius.leadingScalar * 2 }

        static var nameColumn: Double { unit * 7 }
        static var transportColumn: Double { unit * 3 }
        static var toolsColumn: Double { unit * 2 }
        static var callsColumn: Double { unit * 3 }
        static var lastUsedColumn: Double { unit * 3 }
        static var filterWidth: Double { unit * 14 }
        static var searchWidth: Double { unit * 9 }
        static var tagMinimum: Double { unit * 4 }

        /// The inspector is a trailing panel inside the content zone rather than a third
        /// `NavigationSplitView` column: M1 pinned the split view to two columns, and a third would
        /// change the shell's chrome, which is another item's surface.
        static var inspectorWidth: Double { MetricToken.sidebar.leadingScalar + unit * 2 }
        static var sheetWidth: Double { MetricToken.sidebar.leadingScalar * 2 }
        static var sheetHeight: Double { MetricToken.sidebar.leadingScalar * 2 }
    }
#endif

/// Where each of `DESIGN.md` §5's nine states is met on this board.
///
/// **A19 used to claim an exhaustive `switch` over `SurfaceState` in a preview surface, which was
/// the wrong gate on the wrong thing** — the board's own switch is over `LoadState` and has six
/// branches, so a compile check on a preview would have proved that a screen nobody opens is
/// exhaustive. The nine are not alternatives to one another: five are load states, and Success,
/// Disabled and Overflow are properties a *populated* board also has, all at once.
///
/// So the mapping is declared here instead, exhaustively, and a tenth case stops this compiling —
/// which is the moment someone should be deciding what it looks like. Each entry names the place
/// the state is actually rendered, so the claim is checkable by reading rather than by hoping.
enum ServersBoardStates {
    static func treatment(for state: SurfaceState) -> String {
        switch state {
        case .populated: "LoadState.loaded with rows — the table"
        case .empty: "LoadState.loaded([]) — ServersBoardCopy.empty"
        case .loading: "LoadState.loading — SkeletonRows at MetricToken.serversRow"
        case .partial: "LoadState.stale — StaleReadingBanner; and PartialIndexNote for an unindexed server"
        case .error: "LoadState.failed — ConnectionFailurePane from ControlAPIError"
        case .success: "in place, from the server the router returned via apply(updated:)"
        case .offline: "ControlAPIError.routerNotRunning, in either failed or stale"
        case .disabled: "per control — canWrite, writesInFlight, and DisabledAction for Start the router"
        case .overflow: "ServerRowView — one line, tail truncation, fixed row height"
        }
    }
}
