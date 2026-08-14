#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Whether the scroll-edge separator under the toolbar is showing, and how that is decided.
    ///
    /// **Not `offset > 0`.** That is the obvious spelling and it is wrong: a scroll view with content
    /// insets rests at a negative offset, and rubber-banding puts it above and below zero while the
    /// content has not moved at all. Either bug shows the separator on a window nobody has scrolled,
    /// which is exactly the artefact the effect exists to avoid.
    ///
    /// So the resting position is *measured* — the first geometry reading a scroll view emits is its
    /// resting offset, whatever number that happens to be — and everything after is compared to it.
    /// A view that has never scrolled reports its baseline again and the separator stays hidden.
    ///
    /// A value type with a mutating step rather than a view modifier, because A34's unit half needs
    /// to drive the threshold from both sides, and a threshold buried in a closure inside a view is
    /// a threshold no test can reach.
    public struct ScrollEdgeState: Equatable, Sendable {
        /// The offset this scroll view rests at when it is at the top. Captured once.
        public private(set) var baseline: Double?
        /// Whether the separator should be drawn.
        public private(set) var isSeparatorVisible = false

        /// The movement, in points, that counts as having scrolled.
        ///
        /// Not zero: a trackpad resting under a finger emits sub-point jitter, and a zero threshold
        /// makes the separator flicker on a stationary window. One point is below the smallest
        /// deliberate scroll and above the noise.
        public static let threshold: Double = 1

        public init() {}

        /// Feeds one geometry reading in, with the offset the view was at immediately before it.
        ///
        /// **`previous` is what makes the baseline the resting offset**, and getting this wrong was a
        /// measured defect rather than a theoretical one. `onScrollGeometryChange` fires only when
        /// the value *changes*, so the resting position is never delivered as a reading of its own —
        /// an earlier version took the baseline from the first reading it received, which is where
        /// the first scroll *ended up*. Driven on 2026-08-14 against a fresh launch: the separator
        /// stayed hidden through 40 points of scrolling and appeared only past 40% of the range,
        /// because the baseline had been set to wherever the first gesture landed. The old value of
        /// that first callback is the resting offset, and it is the number this needs.
        public mutating func observe(previous: Double, offset: Double) {
            if baseline == nil { baseline = previous }
            guard let baseline else { return }
            isSeparatorVisible = offset > baseline + Self.threshold
        }

        /// Forgets the baseline, so the next reading re-measures it.
        ///
        /// Needed when the content zone changes destination: the new surface has its own insets, and
        /// carrying the old baseline forward would compare one view's offset to another's resting
        /// position — which shows the separator on a freshly-selected pane nobody has scrolled.
        public mutating func reset() {
            baseline = nil
            isSeparatorVisible = false
        }
    }

    /// The hairline that appears where scrolled content meets the toolbar.
    ///
    /// `DESIGN.md` §2 gives `--line` as the hairline divider; the effect is its presence, not a
    /// gradient or a shadow, because §7 restricts motion to transform and opacity and a shadow
    /// blooming under a toolbar is neither.
    struct ScrollEdgeSeparator: View {
        let isVisible: Bool

        var body: some View {
            Rectangle()
                .fill(ColorToken.line.color)
                .frame(height: MetricToken.focusRing.leadingScalar / 2)
                .opacity(isVisible ? 1 : 0)
                .accessibilityHidden(true)
        }
    }
#endif
