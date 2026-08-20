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
        ///
        /// **`Child processes`, not `Running`, since M27.** The design of record labels this card
        /// `Child processes` and the build drew the count unlabelled; the string appeared in 0 of 9
        /// accessibility dumps of the running app. The label carries no honesty question — it names
        /// what the number already is — so the design wins. `Running` also collided with the
        /// sidebar's own `Running` group header, which is a different thing two rows above it.
        public static let childProcessesLabel = "Child processes"

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

    /// Which tier the counts numeral is painted in, held here so the rule is a value rather than a
    /// condition buried in a view body.
    ///
    /// `--live` means *a child process is running* and §2 makes that meaning exclusive. The numeral
    /// earns it while the count is above zero and does not while it is zero, which is the same test
    /// this branch applied to the mock's foot dot and then failed to apply to the number beside it.
    public enum ReadoutTint {
        public static func counts(running: Int) -> ColorToken {
            running > 0 ? .live : .t1
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

        /// The whole readout: a counts row, the trace, a footer row, and the card's own padding
        /// above and below.
        ///
        /// The padding term is `cardPadding`, not `spacing`, since M27 put the readout inside the
        /// card the design of record draws. The composition is what A29 turns on rather than the
        /// total: skeleton and populated form are held to one constant, whatever that constant is.
        public static let height =
            MetricToken.tableRows.leadingScalar * 2
                + traceHeight
                + spacing * 2
                + cardPadding * 2

        // MARK: - The card the readout sits in (M27)

        /// The gap between the card and the sidebar's three edges.
        ///
        /// The card is what `design/mocks/prototype.html` draws and the build had lost: the count
        /// was an uncarded row against the nav list, so nothing said where the list ended and the
        /// instrument began. Derived from the selection inset rather than picked, like every other
        /// number in this file.
        public static let cardMargin = MetricToken.selectionInset.leadingScalar * 2

        /// The card's own inner padding, which is what the readout's horizontal padding already was.
        public static let cardPadding = MetricToken.selectionRadius.leadingScalar

        /// `DESIGN.md` §2's "card radius 10–14", reached the way `SettingsMetrics.cardRadius`
        /// reaches it, so the two cards in this app are one radius rather than two.
        public static let cardRadius =
            MetricToken.selectionRadius.leadingScalar + MetricToken.selectionInset.leadingScalar / 2

        /// A hairline, at the focus ring's half — the width every other line in this app is drawn at.
        public static let hairline = MetricToken.focusRing.leadingScalar / 2

        /// What the card actually offers its contents: the whole height less the card's own padding
        /// above and below.
        ///
        /// Named because two things have to agree on it and they had already stopped: the populated
        /// form fills it by construction — two dense rows, the trace, and the two gaps between them
        /// — and the skeleton has to be given it explicitly. `SidebarFootTests` holds
        /// the two equal, which is A29's claim stated as arithmetic rather than as prose.
        public static let interiorHeight = height - cardPadding * 2
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
            .padding(ReadoutGeometry.cardPadding)
            .background(card)
        }

        /// The card itself — the element `prototype.html` draws around this readout and the build
        /// had lost. A quiet raised plate: the tertiary fill, a hairline bezel, and §2's card
        /// radius. Nothing here is an indicator colour; the instrument inside it is what carries
        /// meaning.
        private var card: some View {
            RoundedRectangle(cornerRadius: ReadoutGeometry.cardRadius, style: .continuous)
                .fill(ColorToken.f3.color)
                .overlay(
                    RoundedRectangle(cornerRadius: ReadoutGeometry.cardRadius, style: .continuous)
                        .strokeBorder(ColorToken.line.color, lineWidth: ReadoutGeometry.hairline)
                )
        }

        @ViewBuilder
        private func counts(running: Int, declared: Int, note: String?) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: ReadoutGeometry.spacing) {
                Text(ReadoutCopy.childProcessesLabel)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                Spacer(minLength: 0)
                // Instrument data, so monospaced — and `--live` because this number *is* the count
                // of child processes running, which is that token's one documented meaning.
                //
                // **Only while it is above zero**, which is the half M27 got wrong in the same
                // change that made it checkable. §2 gives `--live` exactly one meaning and this
                // branch's own design text refuses a green dot beside a card reading `0 of 4` on
                // that ground — while the numeral was painting `--live` on that very reading. Both
                // out-of-family reviews landed on it. `.populated(running: 0, declared: m)` is
                // reachable whenever servers are declared and all of them are idle, which is the
                // ordinary morning state of this app, so it is not a corner.
                //
                // Zero falls to `--t1` rather than to a dimmer tier: nothing is running, but the
                // reading is still the loudest thing the card has to say.
                Text(ReadoutCopy.counts(running: running, declared: declared))
                    .typeRole(.body, monospaced: true)
                    .foregroundStyle(ReadoutTint.counts(running: running).color)
                    // A35's sentence, carried by the numeral itself rather than by the merged row.
                    .accessibilityLabel(
                        ReadoutCopy.accessibilityLabel(running: running, declared: declared)
                    )
            }
            .frame(height: MetricToken.tableRows.leadingScalar)
            // **The row publishes two elements, and that was settled on glass rather than by
            // argument.** Three forms were tried against the running app:
            //
            // `.ignore` is what shipped, and it discarded the label: the row published one element
            // whose text was the counts sentence, so `Child processes` was on screen and absent
            // from every instrument that reads the accessibility plane. That is the same reading
            // the campaign's differential took when it reported the label missing, and a fix the
            // measuring instrument cannot see is a fix that gets re-reported.
            //
            // `.combine` looked better on paper and two out-of-family reviews asked for it — one
            // element, one VoiceOver stop, the label joined to the reading it heads. **It fails
            // A35's own on-glass assertion**, measured: that gate requires an element whose whole
            // text is `N of M declared servers running`, and a combined row publishes
            // `Child processes, N of M …` instead, so `mac-shell.sh` went red on the readout's
            // accessibility label. A35 is the older contract and it is anchored deliberately.
            //
            // So: no merge. The label is its own element and the numeral carries the sentence. That
            // is two stops for one card, which is the cost, and both stops are self-describing —
            // this is not the loose-number failure A35 was written about. A reader hears what the
            // number counts, then the number as a sentence.

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
    ///
    /// **The inner frame is the card's interior, and it subtracts `cardPadding` rather than
    /// `spacing`.** Those two were the same term until M27 put the readout inside a card: the
    /// wrapper's vertical padding was `spacing`, so `height - spacing * 2` *was* the interior. It is
    /// `cardPadding` now, and the stale subtraction left the skeleton 8pt taller than the interior
    /// it sits in — the one state whose whole job is to occupy the populated form's space, drawn
    /// overflowing it by 4pt top and bottom. `ReadoutGeometry.interiorHeight` names the quantity so
    /// the two cannot come apart again.
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
            .frame(height: ReadoutGeometry.interiorHeight, alignment: .leading)
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
