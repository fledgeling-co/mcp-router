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
