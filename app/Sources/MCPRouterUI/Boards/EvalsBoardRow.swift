#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// One subject's row: what it is, what was observed, and against what version.
    ///
    /// **The tally is a list of segments and this view cannot collapse it to one word.** It renders
    /// what `CheckPresentation.tally` returns, and that returns `(count, noun)` pairs — so there is no
    /// code path here that produces a bare verdict standing for a whole subject, which is the thing
    /// the design forbids. Only a *not met* segment is tinted, and it is tinted `--fail`, which is
    /// literally what it means. A confirmed check is never `--live`: `DESIGN.md` §2 binds that hue to
    /// "a child process is running", and a check that holds is not a running process.
    struct EvalsBoardRow: View {
        let subject: CheckPresentation.Subject
        let isSelected: Bool
        let isRechecking: Bool

        var body: some View {
            HStack(spacing: M7BoardMetrics.rowPadding) {
                RoundedRectangle(cornerRadius: M7BoardMetrics.tileRadius, style: .continuous)
                    .fill(ColorToken.f2.color)
                    .frame(width: M7BoardMetrics.tile, height: M7BoardMetrics.tile)
                    .overlay {
                        IconView(subject.kind == .server ? .servers : .skills, size: TypeToken.callout.size)
                            .foregroundStyle(ColorToken.t3.color)
                    }

                VStack(alignment: .leading, spacing: M7BoardMetrics.labelGap) {
                    Text(subject.name)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t1.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subject.detail)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(width: M7BoardMetrics.nameColumn, alignment: .leading)

                Text(subject.kind.label)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t2.color)
                    .frame(width: M7BoardMetrics.kindColumn, alignment: .leading)

                tally
                    .frame(width: M7BoardMetrics.tallyColumn, alignment: .leading)

                stamp
                    .frame(width: M7BoardMetrics.stampColumn, alignment: .leading)

                Spacer(minLength: 0)

                if isRechecking {
                    // Says what is happening rather than leaving the control looking inert.
                    Text("Re-checking…")
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                }
            }
            .padding(.horizontal, M7BoardMetrics.rowPadding)
            // Fixed, and identical in the skeleton, so the board does not jump when data lands.
            .frame(height: M7BoardMetrics.rowHeight)
            .selectionFill(isSelected)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        }

        private var tally: some View {
            HStack(spacing: M7BoardMetrics.tightGap) {
                ForEach(CheckPresentation.tally(subject.results)) { segment in
                    Text("\(segment.count) \(segment.noun)")
                        .typeRole(.caption)
                        .monospacedDigit()
                        // The token comes from Kit. This view chooses no colour.
                        .foregroundStyle(segment.token.color)
                }
            }
        }

        @ViewBuilder
        private var stamp: some View {
            if let stamp = subject.stamp {
                Text(stamp.value)
                    .typeRole(.caption)
                    .monospaced()
                    .foregroundStyle(ColorToken.t3.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                // Never a blank: an empty cell in a populated table reads as a claim about that row.
                Text(CheckCopy.unstampable)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }

        /// The whole row as one sentence, so the verdicts reach VoiceOver with their statements
        /// rather than as a run of adjectives.
        private var accessibilityLabel: String {
            let counts = CheckPresentation.tally(subject.results)
                .map { "\($0.count) \($0.noun)" }
                .joined(separator: ", ")
            return "\(subject.name), \(subject.kind.label). \(counts)."
        }
    }

    /// The loading skeleton, at exactly the populated row geometry (A27).
    struct M7SkeletonRows: View {
        var count: Int = 5

        var body: some View {
            VStack(spacing: M7BoardMetrics.hairline) {
                ForEach(0 ..< count, id: \.self) { _ in
                    HStack(spacing: M7BoardMetrics.rowPadding) {
                        RoundedRectangle(cornerRadius: M7BoardMetrics.tileRadius, style: .continuous)
                            .fill(ColorToken.f2.color)
                            .frame(width: M7BoardMetrics.tile, height: M7BoardMetrics.tile)
                        RoundedRectangle(cornerRadius: M7BoardMetrics.tileRadius, style: .continuous)
                            .fill(ColorToken.f2.color)
                            .frame(width: M7BoardMetrics.nameColumn, height: TypeToken.body.size)
                        RoundedRectangle(cornerRadius: M7BoardMetrics.tileRadius, style: .continuous)
                            .fill(ColorToken.f2.color)
                            .frame(width: M7BoardMetrics.tallyColumn, height: TypeToken.body.size)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, M7BoardMetrics.rowPadding)
                    .frame(height: M7BoardMetrics.rowHeight)
                }
            }
            .accessibilityHidden(true)
        }
    }
#endif
