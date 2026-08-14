#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// How long the router has been recording, drawn at its real length.
    ///
    /// **The app's second subject-mined element**, which `DESIGN.md` §10 asks any new surface to add.
    /// The question Cleanup exists to answer is *how much do we actually know*, and the answer is
    /// dominated by one number nobody looks at: "never used" over 41 days is evidence, over two hours
    /// it is nothing, and a table showing only the verdict renders those two identically.
    ///
    /// The real figure sits beside the bar in mono, so nothing depends on reading the drawing — the
    /// bar is the shape of the answer and the number is the answer. Beyond the 30-day reference it
    /// pegs full rather than overflowing its own track.
    struct CleanupObservationTrack: View {
        let window: CleanupPresentation.Window?

        var body: some View {
            HStack(spacing: M7BoardMetrics.gap) {
                track
                Text(label)
                    .typeRole(.caption)
                    .monospaced()
                    .foregroundStyle(ColorToken.t2.color)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Observation window: \(label)")
        }

        private var label: String {
            guard let window else { return "window unknown" }
            return "\(window.days)d recorded"
        }

        private var fill: Color {
            // `--attn` at its own meaning — "wants a human decision" — and only for the weak window,
            // which is the same condition the banner reports. One condition, two renderings.
            guard let window, window.isWeak else { return ColorToken.t3.color }
            return ColorToken.attention.color
        }

        private var track: some View {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ColorToken.f2.color)
                    // Drawn only when there is a window to draw. A bar filled to zero for an
                    // unknown window is the same substitution as printing "0 days": the shape
                    // states a measurement, and an empty one states that nothing was recorded,
                    // which is a different claim from "the router did not say". The mono label
                    // beside it already reads "window unknown"; leaving the fill out keeps the two
                    // saying the same thing instead of the drawing contradicting the text.
                    if let window {
                        Capsule()
                            .fill(fill)
                            .frame(
                                width: proxy.size.width * CleanupPresentation.trackFraction(
                                    days: window.days
                                )
                            )
                    }
                }
            }
            .frame(width: M7BoardMetrics.trackWidth, height: M7BoardMetrics.trackHeight)
        }
    }

    /// One proposed row: what it is, and the observation that proposed it.
    ///
    /// No trash metaphor anywhere — not in the icon, not in the words. A never-used server was never
    /// deleted, and nothing here is rubbish awaiting disposal.
    struct CleanupBoardRow: View {
        let candidate: CleanupBoardModel.Candidate
        let isSelected: Bool

        var body: some View {
            HStack(spacing: M7BoardMetrics.rowPadding) {
                RoundedRectangle(cornerRadius: M7BoardMetrics.tileRadius, style: .continuous)
                    .fill(ColorToken.f2.color)
                    .frame(width: M7BoardMetrics.tile, height: M7BoardMetrics.tile)
                    .overlay {
                        IconView(candidate.kind == .server ? .servers : .skills, size: TypeToken.callout.size)
                            .foregroundStyle(ColorToken.t3.color)
                    }

                VStack(alignment: .leading, spacing: M7BoardMetrics.labelGap) {
                    Text(candidate.name)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t1.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(candidate.detail)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(width: M7BoardMetrics.nameColumn, alignment: .leading)

                Text(candidate.kind.label)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t2.color)
                    .frame(width: M7BoardMetrics.kindColumn, alignment: .leading)

                // The observation that proposed it — never a verdict about its worth.
                Text(candidate.reason)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t2.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: M7BoardMetrics.reasonColumn, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, M7BoardMetrics.rowPadding)
            .frame(height: M7BoardMetrics.rowHeight)
            .selectionFill(isSelected)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(candidate.name), \(candidate.kind.label). \(candidate.reason)")
        }
    }
#endif
