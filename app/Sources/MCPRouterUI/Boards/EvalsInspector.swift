#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// One subject's checks in full, with the input behind each, and the evidence stored earlier.
    ///
    /// **The input line is not decoration.** The footer promises a check is "something MCP Router
    /// performed and can show you the input to", and without the input on screen that promise is
    /// unverifiable by the person it is addressed to — which is precisely what makes a derived row
    /// indistinguishable from a grade. This is the strongest objection this surface faces, and
    /// rendering `indexError = "spawn ENOENT"` beside the verdict is the answer to it.
    struct EvalsInspector: View {
        let subject: CheckPresentation.Subject
        let server: MCPServer?
        let skill: Skill?
        let clients: [SkillClient]
        let history: [StoredRun]
        let historyError: String?

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: M7BoardMetrics.gap * 2) {
                    header
                    checks
                    stampSection
                    historySection
                }
                .padding(M7BoardMetrics.panePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: M7BoardMetrics.inspectorWidth)
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: M7BoardMetrics.labelGap) {
                Text(subject.name)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                Text("\(subject.kind.label) · \(subject.detail)")
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
            }
        }

        private var checks: some View {
            VStack(alignment: .leading, spacing: M7BoardMetrics.gap) {
                SectionLabel("Checks")
                ForEach(subject.results) { result in
                    VStack(alignment: .leading, spacing: M7BoardMetrics.labelGap) {
                        HStack(alignment: .firstTextBaseline, spacing: M7BoardMetrics.tightGap) {
                            // The verdict never appears without the statement it judges: they are the
                            // same value, so there is no call site holding one and not the other.
                            Text(CheckCopy.tallyNoun(for: result.verdict))
                                .typeRole(.caption)
                                .foregroundStyle(CheckPresentation.token(for: result.verdict).color)
                                .frame(width: M7BoardMetrics.kindColumn * 2, alignment: .leading)
                            Text(result.statement)
                                .typeRole(.body)
                                .foregroundStyle(ColorToken.t1.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let reason = result.reason {
                            Text(reason)
                                .typeRole(.caption)
                                .foregroundStyle(ColorToken.t2.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // The field and value this verdict was computed from.
                        Text(
                            CheckPresentation.input(
                                result.check,
                                server: server,
                                skill: skill,
                                clients: clients
                            )
                        )
                        .typeRole(.caption)
                        .monospaced()
                        .foregroundStyle(ColorToken.t3.color)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }

        /// The token comes from `CheckPresentation.token(for:)`, in Kit. This view chooses no colour
        /// — which is both the thesis of these boards and the only way A21 has a function to iterate
        /// over rather than a source scan alone.
        @ViewBuilder
        private var stampSection: some View {
            VStack(alignment: .leading, spacing: M7BoardMetrics.labelGap) {
                SectionLabel("Checked against")
                if let stamp = subject.stamp {
                    Text(stamp.value)
                        .typeRole(.body)
                        .monospaced()
                        .foregroundStyle(ColorToken.t1.color)
                } else {
                    Text(CheckCopy.unstampable)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                    Text(CheckCopy.unstampableDetail)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        @ViewBuilder
        private var historySection: some View {
            VStack(alignment: .leading, spacing: M7BoardMetrics.gap) {
                SectionLabel("History")
                if let historyError {
                    // "Could not be read" and "there is none" are different claims, and the pane must
                    // not make the second when the first is true.
                    Text(CheckCopy.historyUnreadable)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHint(historyError)
                } else if history.isEmpty {
                    Text(subject.stamp == nil ? CheckCopy.unstampableDetail : CheckCopy.historyEmpty)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(history) { run in
                        historyRow(run)
                    }
                }
            }
        }

        private func historyRow(_ run: StoredRun) -> some View {
            let state = CheckPresentation.historyRowState(run: run, live: subject.stamp)
            let counts = CheckPresentation.tally(run.results)
                .map { "\($0.count) \($0.noun)" }
                .joined(separator: " · ")
            return VStack(alignment: .leading, spacing: M7BoardMetrics.labelGap) {
                Text(counts)
                    .typeRole(.caption)
                    .monospacedDigit()
                    // Invalidated evidence dims to `--t3`, never `--t4`: §2 binds `--t4` to disabled
                    // controls only, and a history row is live text.
                    .foregroundStyle(state.isInvalidated ? ColorToken.t3.color : ColorToken.t2.color)
                Text("\(state.label(for: subject.kind)) · \(shortAgo(run.ranAt)) ago")
                    .typeRole(.caption)
                    .monospaced()
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// A quiet section label. Sentence case, no tracked uppercase (§3.2).
    struct SectionLabel: View {
        private let text: String
        init(_ text: String) { self.text = text }

        var body: some View {
            Text(text)
                .typeRole(.caption)
                .foregroundStyle(ColorToken.t3.color)
        }
    }
#endif
