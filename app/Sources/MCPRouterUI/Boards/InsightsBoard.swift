#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The Insights board — what your agents actually used.
    ///
    /// **There is no saving figure anywhere on it.** `DESIGN.md` §6: the router never runs the
    /// world in which every server is resident, so it has nothing to subtract from, and a
    /// percentage describing that world would be modelled rather than measured. The product's
    /// argument is the duty-cycle chart, and it is counted — which is also why its caption states
    /// the mechanism instead of quoting the brief's own "every one of these sat at 100%".
    ///
    /// **The window is the router's to answer.** The period control asks for 24 hours or 7 days, and the
    /// board labels whatever window came back, so a router that answered another is named for that one.
    /// A window the history does not fully cover says so beside its figures, and the hours it did not
    /// observe are blank rather than zero. The capability-use table the mock draws, keyed on the version
    /// live when a call ran, is not here yet for the reason below.
    ///
    /// **The version table now has data behind it, and this board does not draw it yet.** When this
    /// comment was written it was true that `UsageRecord` carried no version anywhere. F5 built the
    /// other half — `GET /invocations` folds a version-stamped window out of the harness's own
    /// session transcripts, and refuses to credit any run whose version its boundary set cannot
    /// establish (`planning/specs/spec-F5.md`). The table is `D-f5-a`, deferred rather than absent:
    /// rule A36 in `scripts/lint/no-raw-design-values.sh` forbids a board reading a file, so it
    /// ships behind that route the way the Harnesses board shipped behind `GET /harnesses`.
    public struct InsightsBoard: View {
        @Bindable private var board: InsightsBoardModel
        private let showActivity: @MainActor () -> Void

        public init(board: InsightsBoardModel, showActivity: @escaping @MainActor () -> Void = {}) {
            self.board = board
            self.showActivity = showActivity
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.sectionGap) {
                header
                content
            }
            .padding(M22BoardMetrics.panePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task { await board.load() }
            // The board marks its own root and nothing more. `measureSurface` belongs to
            // the measurement harness, which wraps the surface and names it
            // `<surface>.<state>`; calling it here installed a second coordinate space and
            // a second preference reader, and the dump came back rooted at `insights`
            // rather than at the state that was asked for.
            .measured("board-column", role: "board-column", kind: .vstack, alignment: "leading")
        }

        private var header: some View {
            HStack(alignment: .top, spacing: M22BoardMetrics.gap) {
                VStack(alignment: .leading, spacing: M22BoardMetrics.labelGap) {
                    Text(InsightsBoardCopy.title)
                        .typeRole(.title1)
                        .foregroundStyle(ColorToken.t1.color)
                        .measured(
                            "board-title", role: "board-title", kind: .text,
                            tokens: ["foreground": .t1], type: .title1, text: InsightsBoardCopy.title
                        )
                    Text(InsightsBoardCopy.subtitle)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .measured(
                            "board-subtitle", role: "board-subtitle", kind: .text,
                            tokens: ["foreground": .t2], type: .body, text: InsightsBoardCopy.subtitle
                        )
                }
                .measured("board-head", role: "board-head", kind: .vstack)
                Spacer(minLength: 0)
                periodPicker
            }
        }

        /// The period the board asks the router for. It is a menu rather than a segmented control because the
        /// design draws it as a pop-up beside the board's one action.
        private var periodPicker: some View {
            Picker(InsightsBoardCopy.periodAccessibilityLabel, selection: periodBinding) {
                ForEach(InsightsPeriod.allCases, id: \.self) { period in
                    Text(InsightsBoardCopy.periodTitle(period)).tag(period)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(InsightsBoardCopy.periodAccessibilityLabel)
        }

        /// Reads through the model, so a change is a re-read rather than a local label swap.
        private var periodBinding: Binding<InsightsPeriod> {
            Binding(
                get: { board.period },
                set: { next in Task { await board.choosePeriod(next) } }
            )
        }

        @ViewBuilder
        private var content: some View {
            switch board.state {
            case .loading:
                SkeletonRows(count: 4)
                    .measured("insights-loading", role: "loading", kind: .vstack)
            case let .failed(error):
                MessageState(
                    StateMessage(
                        title: error.headline, detail: error.advice,
                        actionLabel: error.actionLabel
                    ),
                    icon: .insights
                )
                .frame(maxWidth: .infinity)
                .measured("insights-failed", role: "error", kind: .vstack)
            case let .loaded(response), let .stale(response, _):
                // A router that answered with nothing in the window is not a failed load. The
                // horizon it reported is what says so, which is why this reads the response rather
                // than inferring emptiness from a count of zero.
                if response.hasHistory {
                    populated(response)
                } else {
                    MessageState(
                        StateMessage(
                            title: InsightsBoardCopy.emptyTitle,
                            detail: InsightsBoardCopy.emptyBody,
                            actionLabel: InsightsBoardCopy.emptyAction
                        ),
                        icon: .insights,
                        action: { showActivity() }
                    )
                    .frame(maxWidth: .infinity)
                    .measured("insights-empty", role: "empty", kind: .vstack)
                }
            }
        }

        private func populated(_ response: InsightsResponse) -> some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.sectionGap) {
                InsightsCoverageNotes(response: response, askedHours: board.period.hours)
                headlines(response)
                callsByHarness(response)
                perHour(response)
                dutyCycle(response)
                InsightsAnalystPanel(board: board)
            }
            .measured("insights-populated", role: "board-body", kind: .vstack)
        }

        /// The four headline counts.
        ///
        /// Each carries its provenance line, because those lines are the difference between a
        /// number and a claim: *measured, not modelled* under the memory figure, and the numerator
        /// beside the failure rate so the percentage is readable as the ratio it is.
        private func headlines(_ response: InsightsResponse) -> some View {
            Grid(horizontalSpacing: M22BoardMetrics.gap, verticalSpacing: M22BoardMetrics.gap) {
                GridRow {
                    StatCard(
                        label: InsightsBoardCopy.childrenLabel,
                        value: String(response.children.alive),
                        provenance: "of \(response.children.declared) declared",
                        provenanceTint: .t3,
                        identifier: "children"
                    )
                    StatCard(
                        label: InsightsBoardCopy.residentLabel,
                        // Absent, not zero: `residentMb()` omits an upstream with no local
                        // process, so with nothing running there is no reading to show.
                        value: response.resident.map { "\($0.megabytes) MB" } ?? "—",
                        provenance: response.resident == nil
                            ? InsightsBoardCopy.residentAbsent
                            : InsightsBoardCopy.residentProvenance,
                        provenanceTint: response.resident == nil ? .t3 : .liveInk,
                        identifier: "resident"
                    )
                    StatCard(
                        label: InsightsBoardCopy.callsLabel(hours: response.windowHours),
                        value: String(response.calls.total),
                        provenance: nil,
                        provenanceTint: .t3,
                        identifier: "calls"
                    )
                    StatCard(
                        label: InsightsBoardCopy.failuresLabel,
                        value: InsightsBoardCopy.failureRate(response.calls),
                        provenance: InsightsBoardCopy.failureProvenance(response.calls),
                        provenanceTint: response.calls.failed > 0 ? .failInk : .t3,
                        identifier: "failures"
                    )
                }
            }
            .measured("headline-grid", role: "stat-grid", kind: .grid)
        }

        /// A bar per detected harness, including every row at zero and every row with no figure.
        private func callsByHarness(_ response: InsightsResponse) -> some View {
            section(InsightsBoardCopy.callsByHarness, id: "section-by-harness") {
                VStack(alignment: .leading, spacing: M22BoardMetrics.tightGap) {
                    ForEach(board.harnessBars) { row in
                        LabelledBar(
                            label: row.displayName,
                            value: row.calls,
                            absentReason: row.reason,
                            share: Double(row.calls ?? 0) / Double(board.harnessScale),
                            tint: InsightsBoardCopy.callsBarFill,
                            identifier: row.harness
                        )
                    }
                    if response.otherCalls > 0 {
                        LabelledBar(
                            label: "Other callers",
                            value: response.otherCalls,
                            absentReason: nil,
                            share: Double(response.otherCalls) / Double(board.harnessScale),
                            tint: .t3,
                            identifier: "other"
                        )
                    }
                    caption(
                        InsightsBoardCopy.unattributableCaption, id: "caption-unattributable"
                    )
                }
                .measured("harness-bars", role: "bar-chart", kind: .vstack)
            }
        }

        private func perHour(_ response: InsightsResponse) -> some View {
            section(InsightsBoardCopy.callsPerHour(hours: response.windowHours), id: "section-per-hour") {
                CallsPerHourChart(
                    hours: response.callsPerHour,
                    periodLabel: InsightsBoardCopy.periodLabel(hours: response.windowHours)
                )
            }
        }

        /// The product's argument, counted.
        private func dutyCycle(_ response: InsightsResponse) -> some View {
            section(InsightsBoardCopy.dutyCycle, id: "section-duty") {
                VStack(alignment: .leading, spacing: M22BoardMetrics.tightGap) {
                    if let cycle = response.dutyCycle {
                        ForEach(cycle.servers) { server in
                            LabelledBar(
                                label: server.server,
                                value: Int(
                                    (InsightsBoardCopy.share(server, of: cycle) * 100).rounded()
                                ),
                                absentReason: nil,
                                share: InsightsBoardCopy.share(server, of: cycle),
                                tint: InsightsBoardCopy.dutyBarFill,
                                identifier: "duty-\(server.server)",
                                monospacedLabel: true
                            )
                        }
                    }
                    caption(InsightsBoardCopy.dutyCycleCaption, id: "caption-duty")
                }
                .measured("duty-bars", role: "bar-chart", kind: .vstack)
            }
        }

        /// The analyst's own configuration and its last run — its empty state, because there is no
        /// analyst in this product yet and the brief asks for the panel rather than the analyst.
        private func section(
            _ title: String, id: String, @ViewBuilder _ content: () -> some View
        ) -> some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.gap) {
                Text(title)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                    .measured(
                        id, role: "section-header", kind: .text,
                        tokens: ["foreground": .t3], type: .subheadline, text: title
                    )
                content()
            }
            .measured("\(id)-block", role: "board-section", kind: .vstack)
        }

        private func caption(_ text: String, id: String) -> some View {
            Text(text)
                .typeRole(.caption)
                .foregroundStyle(ColorToken.t3.color)
                .fixedSize(horizontal: false, vertical: true)
                .measured(
                    id, role: "chart-caption", kind: .text,
                    tokens: ["foreground": .t3], type: .caption, text: text
                )
        }
    }
#endif
