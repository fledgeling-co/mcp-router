#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The Signal Path — the app's signature element, and the only loud thing in it.
    ///
    /// It reads left to right, because a breaker column answered *"is this on"* and the question
    /// this product exists to answer is *"what is wired to what, and what is it costing right now"*.
    /// The hub is the router as a live readout; each jack is one upstream, its plug lit exactly when
    /// a child process is up.
    ///
    /// **The metaphor is bound to observed state at every point**, which is the only thing keeping
    /// it from being decoration: the plug states are the real child lifecycle, `N at rest` is the
    /// warm set the reaper skips, and the topology line counts what the router declares. If the
    /// pooling model changes, this changes with it rather than being kept for its looks.
    ///
    /// **The harness column the brief describes is not drawn, and that is a measurement.** Its three
    /// states — routed over HTTP, routed through a stdio shim, not routed — are `HarnessState` in
    /// `RouterCore/Discovery/HarnessReconciliation.swift`, which neither app target links, and they
    /// are derived by reading harness config files off disk. The control API serves no harness
    /// reading at all: `src/control.ts` routes `/servers`, `/usage` and `/registry` and nothing
    /// else. A36 forbids a board reaching past it by any of the routes its own gate enumerates, a
    /// file read included, so this view cannot go and get them. The one thing the app *can* see —
    /// the `client` recorded on a call — cannot produce *not routed* at all: a harness that has
    /// never called cannot appear in a usage log, so the state carrying the finding is the state
    /// that reading cannot reach. M22 absorbs `R7-C1` and the route with it. Drawing the column
    /// from observed callers would fill the picture with a weaker reading of a different fact.
    ///
    /// The paragraph above is worded around the names A36's own grep looks for. That gate is a
    /// source grep and cannot tell a mention from a call, so the first draft of this comment failed
    /// the rule it was explaining. Rewording the prose is the fix; relaxing the grep to skip
    /// comments would put every forbidden call one `//` away from invisible.
    struct SignalPath: View {
        let rows: [ServerRowModel]
        let header: ServersBoardHeader
        let port: Int?
        @Binding var selection: String?

        private var geometry: SignalPathGeometry { .standard }

        var body: some View {
            VStack(alignment: .leading, spacing: ServersBoardMetrics.gap) {
                head
                rail
            }
            .padding(geometry.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(
                    cornerRadius: MetricToken.cardRadius.leadingScalar,
                    style: .continuous
                )
                .fill(ColorToken.panel.color)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: MetricToken.cardRadius.leadingScalar,
                    style: .continuous
                )
                .strokeBorder(ColorToken.line.color, lineWidth: ServersBoardMetrics.hairline)
            )
            .measured(
                "signal-path", role: "signature", kind: .vstack, alignment: "leading",
                tokens: ["background": .panel], text: bandText
            )
        }

        /// Every string this band draws, in draw order.
        ///
        /// The same composition `ServerRowView.rowText` makes, for the same reason: a container that
        /// reports no text of its own is paired against a mock card whose label **is** its whole
        /// subtree's text, and the two are then not compared at all — which M23's gate reports as
        /// `unclassified` rather than as agreement. Composing it here turns the band's row into a
        /// real comparison, and it is a concatenation of what is drawn below rather than a second
        /// spelling of it: change a part and this changes with it.
        private var bandText: String {
            var parts = [SignalPathCopy.title, header.topology]
            parts.append(contentsOf: SignalPathCopy.legend.map(\.word))
            parts.append(hubText)
            parts.append(contentsOf: rows.map { "\($0.name) \($0.condition.word)" })
            return parts.joined(separator: " ")
        }

        // MARK: - Head

        private var head: some View {
            HStack(spacing: ServersBoardMetrics.gap) {
                Text(SignalPathCopy.title)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t1.color)
                    .measured(
                        "signal-path-title", role: "card-title", kind: .text,
                        tokens: ["foreground": .t1], type: .body, text: SignalPathCopy.title
                    )
                Text(header.topology)
                    // Monospace is the instrument voice (§2): this is a count of what is wired.
                    .typeRole(.subheadline, monospaced: true)
                    .foregroundStyle(ColorToken.t2.color)
                    .measured(
                        "signal-path-topology", role: "card-subtitle", kind: .text,
                        tokens: ["foreground": .t2], type: .subheadline, text: header.topology
                    )
                Spacer(minLength: 0)
                legend
            }
            .measured("signal-path-head", role: "card-header", kind: .hstack)
        }

        /// The four swatches, one per colour rather than one per state.
        ///
        /// `needsSignIn` is deliberately absent: it shares `--attn` with `held`, because both are
        /// things waiting on a person, and a legend that listed it would show two rows of the same
        /// swatch. What tells those two apart is the word on the jack itself, which is the rule
        /// working the way §3 rule 10 intends — colour narrows, the word decides.
        private var legend: some View {
            HStack(spacing: ServersBoardMetrics.gap) {
                ForEach(SignalPathCopy.legend, id: \.self) { state in
                    HStack(spacing: ServersBoardMetrics.tightGap) {
                        StatePlug(state: state)
                        Text(state.word)
                            .typeRole(.subheadline)
                            .foregroundStyle(ColorToken.t2.color)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(state.word) is \(SignalPathCopy.swatchName(for: state))")
                }
            }
            .measured("signal-path-legend", role: "legend", kind: .hstack)
        }

        // MARK: - Rail

        private var rail: some View {
            HStack(alignment: .center, spacing: geometry.gutter) {
                hub
                IconView(.flow, size: TypeToken.body.size)
                    .foregroundStyle(ColorToken.t3.color)
                    .frame(width: geometry.flowArrowWidth)
                    .accessibilityHidden(true)
                    .measured("flow-arrow", role: "flow-arrow", kind: .leaf)
                jacks
            }
            .measured("signal-path-rail", role: "rail", kind: .hstack, alignment: "center")
        }

        /// The router itself, and the product's central claim as a live number.
        ///
        /// **Each line is drawn only when the fact behind it exists.** The port comes from the last
        /// poll that answered and is `nil` until one has; `at rest` is a count of child processes up
        /// right now, so it is withheld on a reading that is not current for the same reason the
        /// header withholds *"1 running"*. A zero here would be a fabricated figure, which is the
        /// defect rather than the fix.
        private var hub: some View {
            VStack(spacing: 0) {
                Text(SignalPathCopy.hub)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t1.color)
                if let port {
                    Text(":\(port)")
                        .typeRole(.subheadline, monospaced: true)
                        .foregroundStyle(ColorToken.t2.color)
                }
                if let atRest = header.atRest {
                    Text(SignalPathCopy.atRest(atRest))
                        .typeRole(.subheadline, monospaced: true)
                        .foregroundStyle(ColorToken.t2.color)
                }
            }
            .padding(.vertical, ServersBoardMetrics.tightGap)
            .frame(width: geometry.hubWidth)
            .background(
                RoundedRectangle(
                    cornerRadius: MetricToken.selectionRadius.leadingScalar,
                    style: .continuous
                )
                .fill(ColorToken.raised.color)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: MetricToken.selectionRadius.leadingScalar,
                    style: .continuous
                )
                .strokeBorder(ColorToken.lineStrong.color, lineWidth: ServersBoardMetrics.hairline)
            )
            .accessibilityElement(children: .combine)
            .measured("hub", role: "hub", kind: .vstack, text: hubText)
        }

        /// Every string the hub draws, in draw order — the same composition `ServerRowView.rowText`
        /// makes, and for the same reason: a container reporting no text of its own is compared
        /// against nothing at all.
        private var hubText: String {
            var parts = [SignalPathCopy.hub]
            if let port { parts.append(":\(port)") }
            if let atRest = header.atRest { parts.append(SignalPathCopy.atRest(atRest)) }
            return parts.joined(separator: " ")
        }

        /// The jack field: a grid of tracks that packs to the width available.
        ///
        /// `.adaptive(minimum:)` is the direct translation of the mock's
        /// `repeat(auto-fill, minmax(132px, 1fr))`, and a **fixed column count is what the brief
        /// measured as the failure** — laid out as a single column, eleven upstreams ran the band
        /// 500pt deep and pushed the table off the board.
        ///
        /// It draws every **declared** server rather than the table's filtered rows. The band is the
        /// router's whole signal path, and a band that shrank with the segmented control would
        /// contradict the topology line beside it. Selecting a jack whose row the filter hides still
        /// opens the inspector, because `selectedServer(in:)` reads the servers rather than the rows.
        private var jacks: some View {
            LazyVGrid(
                columns: [GridItem(
                    .adaptive(minimum: geometry.jackMinimum),
                    spacing: geometry.gutter,
                    alignment: .leading
                )],
                alignment: .leading,
                spacing: geometry.gutter
            ) {
                ForEach(rows) { row in
                    JackView(
                        row: row,
                        isSelected: selection == row.id,
                        select: { selection = row.id }
                    )
                }
            }
            // `flex:1` in the mock. Without it the grid negotiates its *ideal* width inside the
            // rail's HStack rather than the width available, so the last track absorbs the
            // remainder — measured at 142.5pt against its siblings' 132pt — and the packing stops
            // being the one the brief specified.
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(SignalPathCopy.jackField)
            .measured("jacks", role: "jack-field", kind: .grid)
        }
    }

    /// The band's words, in one place.
    ///
    /// Beside the view rather than inside it for the reason every other `*Copy` type in this repo
    /// exists: a string a test can read is a string a copy check can hold to `DESIGN.md` §6, and
    /// `at rest` in particular is a claim about the pooling model that someone will want to find.
    enum SignalPathCopy {
        static let title = "Signal path"
        static let hub = "Router"
        static let jackField = "Upstream servers"

        /// The four swatches, in the order the mock lists them: lit, unlit, waiting, failed.
        static let legend: [JackState] = [.live, .dormant, .held, .tripped]

        /// What the hub says about the pooling model.
        ///
        /// *"at rest"* is the router's own claim — a child process that stays up when nothing is
        /// calling — and the figure behind it is the warm set, which the reaper skips by design.
        static func atRest(_ count: Int) -> String {
            "\(count) at rest"
        }

        /// The legend's spoken form, so a swatch is never explained by colour alone.
        static func swatchName(for state: JackState) -> String {
            switch state {
            case .live: "green"
            case .held, .needsSignIn: "amber"
            case .tripped: "red"
            case .dormant: "unlit"
            }
        }
    }
#endif
