#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The grid both M22 boards draw on.
    ///
    /// One enum for two boards, following `M7BoardMetrics`: Harnesses and Insights are sibling
    /// surfaces built from the same card, the same section rhythm and the same bar row, and two
    /// near-identical metrics files are two things free to drift while nobody compares them.
    ///
    /// Every value is derived from a documented token. `scripts/lint/no-raw-design-values.sh`
    /// forbids a geometry literal anywhere under `Boards/`, which is what stops a chart arriving
    /// with a hand-picked bar height that no parity check can read.
    enum M22BoardMetrics {
        private static var unit: Double { MetricToken.tableRows.leadingScalar }
        private static var inset: Double { MetricToken.selectionInset.leadingScalar }

        static var hairline: Double { MetricToken.focusRing.leadingScalar / 2 }
        static var labelGap: Double { MetricToken.focusRing.leadingScalar }
        static var tightGap: Double { inset }
        static var gap: Double { inset * 2 }
        static var sectionGap: Double { MetricToken.selectionRadius.leadingScalar * 2 }
        static var cardPadding: Double { MetricToken.selectionRadius.leadingScalar + inset }
        static var panePadding: Double { MetricToken.selectionRadius.leadingScalar * 2 }
        static var cardRadius: Double { MetricToken.cardRadius.leadingScalar }

        /// The status pill on a harness row.
        static var pillHeight: Double { MetricToken.controlSmall.leadingScalar }
        static var pillRadius: Double { MetricToken.controlSmall.leadingScalar / 2 }
        static var pillPadding: Double { inset * 2 }
        static var dot: Double { inset * 2 }

        /// A bar row: the label gutter, the track, and the value column.
        ///
        /// The track's height is the selection inset rather than a picked thickness, so a bar and
        /// the gap above it are the same unit and the chart keeps the board's rhythm.
        static var barLabel: Double { unit * 5 }
        static var barValue: Double { unit * 3 }
        static var barHeight: Double { inset * 2 }
        static var barRadius: Double { inset }
        static var barRowHeight: Double { unit }

        /// The sparkline. As tall as two table rows, which is the smallest height at which a
        /// 24-point line reads as a shape rather than as noise.
        static var sparkHeight: Double { unit * 2 }
        static var sparkLine: Double { MetricToken.focusRing.leadingScalar }

        /// A headline stat card. Fixed, and identical in the skeleton, so the grid does not jump
        /// when the first answer lands.
        static var statHeight: Double { unit * 4 }
        static var statMinWidth: Double { unit * 6 }

        /// A harness card's resting height, used by the loading skeleton so the list does not
        /// re-flow when the read completes.
        static var harnessSkeletonHeight: Double { unit * 4 }
    }
#endif
