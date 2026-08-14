#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Every string the readout renders, as data.
    ///
    /// Held here rather than inline in the view for two reasons that are both clauses. A15 forbids
    /// displaying a figure the router does not observe, and the only way to check that is to read
    /// the strings a surface can produce — which a SwiftUI view tree does not let a test do. And A28
    /// requires the failure copy to be `ControlAPIError`'s own wording *unchanged*, which is a claim
    /// about a string, testable only where the string is.
    ///
    /// Sentence case throughout, per `DESIGN.md` §6, and no uppercasing transform anywhere.
    public enum ReadoutCopy {
        /// The at-rest readout's own label. Prose, so it is never monospaced (§2).
        public static let runningLabel = "Running"

        /// "3 of 8" — child processes running against servers declared. Both numbers come from one
        /// `/servers` response and nothing is derived from them.
        public static func counts(running: Int, declared: Int) -> String {
            "\(running) of \(declared)"
        }

        /// §5's Partial: say what arrived and what did not. `indexError` is the router's own report
        /// that it could not read a server's tools, so this is observed rather than inferred.
        public static func notIndexed(_ count: Int) -> String {
            count == 1 ? "1 not indexed" : "\(count) not indexed"
        }

        /// §5's Empty: never a bare "No items".
        public static let emptyTitle = "No servers declared yet"
        public static let emptyDetail =
            "Point MCP Router at a config and the servers your agents already use appear here."

        /// What a screen reader is told while the readout is waiting for its first answer.
        public static let loadingLabel = "Loading the router's status"

        /// The accessibility label for the readout as a whole, so the counts are announced as a
        /// sentence rather than as two loose numbers (A35).
        public static func accessibilityLabel(running: Int, declared: Int) -> String {
            "\(running) of \(declared) declared servers running"
        }
    }

    /// The readout's geometry, so the skeleton can be exactly the populated form's size.
    ///
    /// A29 turns on this being one number rather than two: a skeleton at a different height makes
    /// the sidebar jump when the first poll lands, which is the single thing a skeleton exists to
    /// prevent. Composed from tokens, never from literals — the lint gate would reject a literal and
    /// the parity suite holds the tokens equal to `DESIGN.md`.
    public enum ReadoutGeometry {
        /// The trace strip. A control-ladder rung rather than a number picked for the drawing.
        public static let traceHeight = MetricToken.controlSmall.leadingScalar

        /// The gap between the readout's three rows, and its inner padding.
        public static let spacing = MetricToken.selectionInset.leadingScalar

        /// The whole readout: a counts row, the trace, a footer row, and padding above and below.
        public static let height =
            MetricToken.tableRows.leadingScalar * 2
                + traceHeight
                + spacing * 4
    }

    /// The at-rest readout in the sidebar's footer.
    ///
    /// It shows two numbers and a trace, and there is deliberately nothing here from which a memory
    /// saving could be computed — `DESIGN.md` §6 closes on that rule and this is the surface it was
    /// written about.
    struct Readout: View {
        let state: ReadoutState
        let tracePoints: [(x: Double, y: Double)]
        let traceLabel: String?

        var body: some View {
            VStack(alignment: .leading, spacing: ReadoutGeometry.spacing) {
                switch state {
                case .loading:
                    ReadoutSkeleton()
                case .empty:
                    ReadoutMessage(title: ReadoutCopy.emptyTitle, detail: ReadoutCopy.emptyDetail)
                case let .populated(running, declared):
                    counts(running: running, declared: declared, note: nil)
                case let .partial(running, declared, notIndexed):
                    counts(
                        running: running,
                        declared: declared,
                        note: ReadoutCopy.notIndexed(notIndexed)
                    )
                case let .failed(error):
                    // A28: the client's own wording, unchanged. No paraphrase, and no action
                    // control — the two actions this error names ("Start the router", "Re-pair…")
                    // have no operation behind them in this build, and a button that does nothing
                    // when pressed fails §5 more badly than omitting it.
                    ReadoutMessage(title: error.headline, detail: error.advice)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MetricToken.selectionRadius.leadingScalar)
            .padding(.vertical, ReadoutGeometry.spacing)
        }

        @ViewBuilder
        private func counts(running: Int, declared: Int, note: String?) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: ReadoutGeometry.spacing) {
                Text(ReadoutCopy.runningLabel)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                Spacer(minLength: 0)
                // Instrument data, so monospaced — and `--live` because this number *is* the count
                // of child processes running, which is that token's one documented meaning.
                Text(ReadoutCopy.counts(running: running, declared: declared))
                    .typeRole(.body, monospaced: true)
                    .foregroundStyle(ColorToken.live.color)
            }
            .frame(height: MetricToken.tableRows.leadingScalar)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ReadoutCopy.accessibilityLabel(running: running, declared: declared))

            TraceStrip(points: tracePoints)
                .frame(height: ReadoutGeometry.traceHeight)

            HStack(spacing: ReadoutGeometry.spacing) {
                if let traceLabel {
                    Text(traceLabel)
                        .typeRole(.caption, monospaced: true)
                        .foregroundStyle(ColorToken.t3.color)
                }
                Spacer(minLength: 0)
                if let note {
                    Text(note)
                        .typeRole(.caption, monospaced: true)
                        .foregroundStyle(ColorToken.t2.color)
                }
            }
            .frame(height: MetricToken.tableRows.leadingScalar)
        }
    }

    /// A title and a quiet sentence — the shape the empty and failed states both take.
    ///
    /// One view rather than two so the two cannot drift apart in spacing, and so the failure form is
    /// visibly the same shape as the empty one rather than a second design.
    struct ReadoutMessage: View {
        let title: String
        let detail: String

        var body: some View {
            VStack(alignment: .leading, spacing: ReadoutGeometry.spacing) {
                Text(title)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t1.color)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// The loading state: the readout's own geometry, drawn empty.
    ///
    /// §5 — "skeleton matching the real row geometry; never a spinner over a blank pane." The height
    /// is `ReadoutGeometry.height`, the same constant the populated form is held to, so the sidebar
    /// does not move when the first poll answers.
    struct ReadoutSkeleton: View {
        var body: some View {
            VStack(alignment: .leading, spacing: ReadoutGeometry.spacing) {
                RoundedRectangle(cornerRadius: MetricToken.focusRing.leadingScalar)
                    .fill(ColorToken.f2.color)
                    .frame(
                        maxWidth: MetricToken.sidebar.leadingScalar / 2,
                        maxHeight: MetricToken.tableRows.leadingScalar / 2
                    )
                RoundedRectangle(cornerRadius: MetricToken.focusRing.leadingScalar)
                    .fill(ColorToken.f3.color)
                    .frame(height: ReadoutGeometry.traceHeight)
                RoundedRectangle(cornerRadius: MetricToken.focusRing.leadingScalar)
                    .fill(ColorToken.f2.color)
                    .frame(
                        maxWidth: MetricToken.sidebar.leadingScalar / 3,
                        maxHeight: MetricToken.tableRows.leadingScalar / 3
                    )
            }
            .frame(height: ReadoutGeometry.height - ReadoutGeometry.spacing * 2, alignment: .leading)
            .accessibilityLabel(ReadoutCopy.loadingLabel)
        }
    }

    /// The last-60-seconds trace, drawn from the normalised points the model shaped.
    ///
    /// The view holds no arithmetic beyond scaling into its own rectangle: the window, the eviction
    /// and the peak are all `ReadoutModel`'s, where a test can drive them.
    struct TraceStrip: View {
        let points: [(x: Double, y: Double)]

        var body: some View {
            GeometryReader { geo in
                Path { path in
                    guard points.count > 1 else { return }
                    for (index, point) in points.enumerated() {
                        let position = CGPoint(
                            x: point.x * geo.size.width,
                            y: (1 - point.y) * geo.size.height
                        )
                        if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                    }
                }
                .stroke(ColorToken.live.color, lineWidth: MetricToken.focusRing.leadingScalar / 2)
            }
            // The trace repeats the counts already announced above it, so it is decoration to a
            // screen reader rather than a second reading of the same fact.
            .accessibilityHidden(true)
        }
    }
#endif
