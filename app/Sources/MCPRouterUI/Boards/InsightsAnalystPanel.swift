#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The Insights board's analyst card — F7, and the end of `DEF-065`.
    ///
    /// **Three states, and the two empty ones are not the same empty.** A router with no analyst
    /// draws a dim action with the version-skew reason `DESIGN.md` §3.4 asks for; a router that has
    /// one and has never run it draws the settings, a live action and no reading; a router that has
    /// run draws the design's four readouts and what it found. Collapsing the first two would put a
    /// live button on a router that cannot serve it, which is the failure the dim-with-a-reason rule
    /// exists to prevent.
    ///
    /// A view of its own rather than a computed property on `InsightsBoard`, because that type's
    /// members are `private` and because this card alone is longer than the four charts above it.
    struct InsightsAnalystPanel: View {
        @Bindable var board: InsightsBoardModel

        var body: some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.gap) {
                Text(InsightsBoardCopy.analyst)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                    .measured(
                        "section-analyst", role: "section-header", kind: .text,
                        tokens: ["foreground": .t3], type: .subheadline,
                        text: InsightsBoardCopy.analyst
                    )
                if let run = board.analyst {
                    present(run)
                } else {
                    unsupported
                }
            }
            .measured("section-analyst-block", role: "board-section", kind: .vstack)
        }

        /// The router does not serve the analyst at all. Dim rather than absent, with the reason on
        /// the control itself rather than only in a caption — the pointer and the screen reader get
        /// the same sentence.
        private var unsupported: some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.labelGap) {
                label(InsightsBoardCopy.analystUnsupportedTitle, id: "analyst-title", token: .t1)
                body(InsightsBoardCopy.analyseUnavailable, id: "analyst-body")
                Button(InsightsBoardCopy.analyseNow) {}
                    .buttonStyle(StandardButtonStyle())
                    .disabled(true)
                    .help(InsightsBoardCopy.analyseUnavailable)
                    .accessibilityHint(InsightsBoardCopy.analyseUnavailable)
                    .measured(
                        "analyse-now", role: "board-action", type: .body,
                        text: InsightsBoardCopy.analyseNow
                    )
            }
            .measured("analyst-empty", role: "analyst-panel", kind: .vstack)
        }

        private func present(_ run: AnalystRun) -> some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.gap) {
                settings(run)
                if run.hasRun {
                    findings(run)
                } else {
                    label(InsightsBoardCopy.analystAbsentTitle, id: "analyst-title", token: .t1)
                    body(InsightsBoardCopy.analystAbsentBody, id: "analyst-body")
                }
                if let unread = InsightsBoardCopy.analystUnreadSummary(run) {
                    body(unread, id: "analyst-unread")
                }
                if !run.scheduled { body(InsightsBoardCopy.analystNotScheduled, id: "analyst-cadence-note") }
                body(InsightsBoardCopy.analystCallout, id: "analyst-callout")
            }
            .measured("analyst-panel", role: "analyst-panel", kind: .vstack)
        }

        /// The design's four readouts, three of which are menus.
        private func settings(_ run: AnalystRun) -> some View {
            HStack(alignment: .top, spacing: M22BoardMetrics.gap) {
                readout(InsightsBoardCopy.analystPrimary, id: "analyst-model") {
                    laneMenu(run.primary.label, id: "analyst-model-menu") { lane in
                        await board.choose(primary: lane)
                    }
                }
                readout(InsightsBoardCopy.analystFallback, id: "analyst-second-opinion") {
                    laneMenu(
                        run.fallback?.label ?? InsightsBoardCopy.analystNoFallback,
                        id: "analyst-second-opinion-menu"
                    ) { lane in
                        await board.choose(fallback: lane)
                    }
                }
                readout(InsightsBoardCopy.analystRuns, id: "analyst-cadence") {
                    Menu(run.cadenceLabel) {
                        ForEach(AnalystChoices.cadences, id: \.value) { choice in
                            Button(choice.label) {
                                Task { await board.choose(cadence: choice.value) }
                            }
                        }
                    }
                    .fixedSize()
                    .disabled(board.analysing)
                    .measured(
                        "analyst-cadence-menu", role: "board-action", type: .body,
                        text: run.cadenceLabel
                    )
                }
                readout(InsightsBoardCopy.analystLastRun, id: "analyst-last-run") {
                    body(InsightsBoardCopy.analystLastRunSummary(run), id: "analyst-last-run-value")
                }
                Spacer(minLength: 0)
                Button(InsightsBoardCopy.analyseNow) {
                    Task { await board.analyseNow() }
                }
                .buttonStyle(StandardButtonStyle())
                .disabled(!board.canAnalyse)
                .measured(
                    "analyse-now", role: "board-action", type: .body,
                    text: InsightsBoardCopy.analyseNow
                )
            }
            .measured("analyst-settings", role: "analyst-settings", kind: .hstack)
        }

        private func laneMenu(
            _ title: String, id: String, _ choose: @escaping (String) async -> Void
        ) -> some View {
            Menu(title) {
                ForEach(AnalystChoices.lanes, id: \.value) { choice in
                    Button(choice.label) { Task { await choose(choice.value) } }
                }
            }
            .fixedSize()
            .disabled(board.analysing)
            .measured(id, role: "board-action", type: .body, text: title)
        }

        private func findings(_ run: AnalystRun) -> some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.tightGap) {
                ForEach(run.recent) { card in
                    VStack(alignment: .leading, spacing: M22BoardMetrics.labelGap) {
                        label(card.subject, id: "finding-\(card.entryID)", token: .t1)
                        body(card.sentence, id: "finding-\(card.entryID)-sentence")
                        // The count and the judge, never folded into the sentence: a finding
                        // delivered with its evidence missing from the wording is the shape
                        // `AnalystFinding` was built to make impossible one subsystem over.
                        body(
                            "\(card.evidenceCount) observations · judged by \(card.judgedBy)",
                            id: "finding-\(card.entryID)-provenance"
                        )
                    }
                    .measured("finding-\(card.entryID)-block", role: "finding-card", kind: .vstack)
                }
            }
            .measured("analyst-findings", role: "analyst-findings", kind: .vstack)
        }

        private func readout(
            _ title: String, id: String, @ViewBuilder _ content: () -> some View
        ) -> some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.labelGap) {
                Text(title)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .measured(
                        id, role: "readout-label", kind: .text,
                        tokens: ["foreground": .t3], type: .caption, text: title
                    )
                content()
            }
        }

        private func label(_ text: String, id: String, token: ColorToken) -> some View {
            Text(text)
                .typeRole(.title3)
                .foregroundStyle(token.color)
                .measured(
                    id, role: "analyst-title", kind: .text,
                    tokens: ["foreground": token], type: .title3, text: text
                )
        }

        private func body(_ text: String, id: String) -> some View {
            Text(text)
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)
                .measured(
                    id, role: "analyst-body", kind: .text,
                    tokens: ["foreground": .t2], type: .body, text: text
                )
        }
    }

    /// What the three menus offer.
    ///
    /// **Spelled here rather than derived from the router's answer, and that is a limit rather than
    /// a choice.** `GET /insights` reports the two lanes in force; it does not enumerate the five
    /// the router would accept. Listing them in the app means a router that later grows a sixth
    /// lane is not offered until this list changes — recorded so that the divergence is a known one
    /// rather than a surprise, and refused by the route's own 422 rather than silently accepted if
    /// this list ever runs ahead.
    enum AnalystChoices {
        static let lanes: [(value: String, label: String)] = [
            ("claude", "Claude CLI · haiku"),
            ("cursor", "Cursor CLI · composer"),
            ("grok", "Grok CLI · grok-4.6 medium"),
            ("codex", "Codex CLI · gpt-5.6-luna low"),
            ("gemini", "Antigravity · gemini-3.7-flash-high")
        ]

        static let cadences: [(value: String, label: String)] = [
            ("manual", "Only when I ask"),
            ("sixHourly", "Every 6 hours"),
            ("twelveHourly", "Every 12 hours"),
            ("daily", "Once a day")
        ]
    }
#endif
