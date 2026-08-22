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
    /// **What it does not show, and why.** The mock draws a *Last 7 days* window pop-up and a
    /// capability-use table keyed on the version live when a call ran. The window is fixed at 24
    /// hours because the call log rotates and what a router can answer for is whatever survived —
    /// a control offering seven days on a machine holding two would lie about its own range. The
    /// version table has no data behind it at all: `UsageRecord` carries the server, the tool and
    /// the caller, and no version anywhere. Both are parked with those reasons.
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
            .measureSurface("insights")
        }

        private var header: some View {
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
                headlines(response)
                callsByHarness(response)
                perHour(response)
                dutyCycle(response)
                analyst
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
                        label: InsightsBoardCopy.callsLabel,
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
            section(InsightsBoardCopy.callsPerHour, id: "section-per-hour") {
                CallsPerHourChart(hours: response.callsPerHour)
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
        private var analyst: some View {
            section(InsightsBoardCopy.analyst, id: "section-analyst") {
                VStack(alignment: .leading, spacing: M22BoardMetrics.labelGap) {
                    Text(InsightsBoardCopy.analystAbsentTitle)
                        .typeRole(.title3)
                        .foregroundStyle(ColorToken.t1.color)
                        .measured(
                            "analyst-title", role: "analyst-title", kind: .text,
                            tokens: ["foreground": .t1], type: .title3,
                            text: InsightsBoardCopy.analystAbsentTitle
                        )
                    Text(InsightsBoardCopy.analystAbsentBody)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .measured(
                            "analyst-body", role: "analyst-body", kind: .text,
                            tokens: ["foreground": .t2], type: .body,
                            text: InsightsBoardCopy.analystAbsentBody
                        )
                }
                .measured("analyst-empty", role: "analyst-panel", kind: .vstack)
            }
        }

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
