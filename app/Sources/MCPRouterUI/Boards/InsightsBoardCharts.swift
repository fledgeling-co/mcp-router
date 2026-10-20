#if os(macOS)
    import Charts
    import MCPRouterKit
    import SwiftUI

    /// One bar on a labelled bar chart.
    ///
    /// **Drawn as a row rather than by `Charts`, deliberately.** A bar chart's whole value here is
    /// the row reading zero — a harness at zero is one still calling its own servers — and a chart
    /// that drops or collapses an empty series hides exactly that. A row draws its label, its track
    /// and its value whatever the value is, so a zero is visible as a zero and an *absent* count is
    /// visible as neither.
    ///
    /// **The fill is `--live-ink` and `--attn-ink`, not `--live` and `--attn`.** The kit greens and
    /// ambers measure 2.22:1 and 2.31:1 on the light ground, under the 3:1 a non-text mark wants
    /// against a near-white track; the text-safe twins clear it. `Charts` would happily paint the
    /// brighter one, which is the other half of why this is a row.
    struct LabelledBar: View {
        let label: String
        /// Nil means the router has no figure for this row — not zero. A zero is a measurement and
        /// an absence is not.
        let value: Int?
        /// The words shown where a value would be, when there is none.
        let absentReason: String?
        let share: Double
        let tint: ColorToken
        let identifier: String
        var monospacedLabel = false

        var body: some View {
            HStack(spacing: M22BoardMetrics.gap) {
                labelText
                track
                valueText
            }
            .frame(height: M22BoardMetrics.barRowHeight)
            .measured("bar-\(identifier)", role: "bar-row", kind: .hstack)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        }

        private var labelText: some View {
            Text(label)
                .typeRole(.body)
                .monospaced(monospacedLabel)
                .foregroundStyle(ColorToken.t1.color)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: M22BoardMetrics.barLabel, alignment: .leading)
                .measured(
                    "bar-label-\(identifier)", role: "bar-label", kind: .text,
                    tokens: ["foreground": .t1], type: .body, text: label
                )
        }

        /// The track, and the fill drawn as a share of it.
        ///
        /// A `GeometryReader` rather than a fixed width, because the share is of whatever the
        /// column is; and the fill is drawn at zero width when the value is zero rather than being
        /// omitted, so the row still reads as a bar at nothing.
        private var track: some View {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: M22BoardMetrics.barRadius)
                        .fill(ColorToken.f2.color)
                    if value != nil {
                        RoundedRectangle(cornerRadius: M22BoardMetrics.barRadius)
                            .fill(tint.color)
                            .frame(width: max(0, geometry.size.width * share))
                            .measured(
                                "bar-fill-\(identifier)", role: "bar-fill",
                                tokens: ["background": tint]
                            )
                    }
                }
            }
            .frame(height: M22BoardMetrics.barHeight)
            .measured(
                "bar-track-\(identifier)", role: "bar-track", kind: .zstack,
                tokens: ["background": .f2]
            )
        }

        private var valueText: some View {
            Text(valueLabel)
                .typeRole(.body)
                .monospaced(value != nil)
                .foregroundStyle((value == nil ? ColorToken.t3 : ColorToken.t1).color)
                .lineLimit(1)
                .frame(width: M22BoardMetrics.barValue, alignment: .trailing)
                .measured(
                    "bar-value-\(identifier)", role: "bar-value", kind: .text,
                    tokens: ["foreground": value == nil ? .t3 : .t1], type: .body, text: valueLabel
                )
        }

        /// An em dash where there is no figure. Never a zero, and never blank: a blank cell in a
        /// populated chart reads as a claim about that row.
        private var valueLabel: String { value.map(String.init) ?? "—" }

        private var accessibilityText: String {
            guard let value else {
                return "\(label), no figure — \(absentReason ?? "the router cannot attribute these")"
            }
            return "\(label), \(value)"
        }
    }

    /// Calls per hour over the window.
    ///
    /// This one **is** a `Charts` chart: it is a continuous quantity over time with 24 points and
    /// no row that means anything on its own, which is the shape `Charts` is good at and the shape
    /// a stack of rows is bad at. The stroke is `--accent-ink`, a `fill` role used as a mark rather
    /// than as a label, which is what the accent is for.
    struct CallsPerHourChart: View {
        let hours: [HourlyCalls]
        /// The window as the copy names it, for the accessible summary.
        let periodLabel: String

        var body: some View {
            Chart(Self.points(hours)) { point in
                LineMark(
                    x: .value("Hour", point.hourStart),
                    y: .value("Calls", point.calls),
                    series: .value("Observed run", point.run)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(ColorToken.accentInk.color)
                .lineStyle(StrokeStyle(lineWidth: M22BoardMetrics.sparkLine, lineJoin: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0 ... Swift.max(1, hours.compactMap(\.calls).max() ?? 1))
            .frame(height: M22BoardMetrics.sparkHeight)
            .measured(
                "calls-per-hour", role: "sparkline", kind: .leaf,
                tokens: ["foreground": .accentInk]
            )
            .accessibilityElement()
            .accessibilityLabel(Self.summary(hours, periodLabel: periodLabel))
        }

        /// One plotted point per observed hour. An unobserved hour has no point at all, and each
        /// run of observed hours is its own series, so the line stops at the edge of the gap
        /// instead of joining across it.
        struct Point: Identifiable {
            let id: String
            let hourStart: String
            let calls: Int
            let run: Int
        }

        static func points(_ hours: [HourlyCalls]) -> [Point] {
            var run = 0
            var inRun = false
            var points: [Point] = []
            for hour in hours {
                guard let calls = hour.calls else {
                    inRun = false
                    continue
                }
                if !inRun {
                    run += 1
                    inRun = true
                }
                points.append(Point(id: hour.hourStart, hourStart: hour.hourStart, calls: calls, run: run))
            }
            return points
        }

        /// What the line says, for a reader who cannot see it.
        ///
        /// Composed from the series rather than written, so it cannot describe a shape the chart does not
        /// have. It
        /// counts the hours it could not observe, so a short line reads as short rather than as quiet.
        static func summary(_ hours: [HourlyCalls], periodLabel: String) -> String {
            let observed = hours.compactMap(\.calls)
            let unobserved = hours.count - observed.count
            let noun = unobserved == 1 ? "hour" : "hours"
            let gap = unobserved > 0 ? ", \(unobserved) \(noun) not observed" : ""
            let total = observed.reduce(0, +)
            guard total > 0, let peak = observed.max() else {
                return "Calls per hour over the \(periodLabel): none\(gap)"
            }
            return "Calls per hour over the \(periodLabel): \(total) in total, "
                + "peaking at \(peak) in one hour\(gap)"
        }
    }

    /// What the window is made of, beside its figures: whether it is whole, what the size cap removed from
    /// it, and whether the router answered the window that was asked for. Drawn only when there is something
    /// to say, so a whole, uncapped, matching window carries no caveat.
    struct InsightsCoverageNotes: View {
        let response: InsightsResponse
        /// The window the board asked for, which the answer is checked against.
        let askedHours: Int

        var body: some View {
            let answeredOther = response.windowHours != askedHours
            let capped = response.retention.flatMap { $0.capped.records > 0 ? $0 : nil }
            let incomplete = response.windowComplete == false ? response.observedSince : nil
            if answeredOther || capped != nil || incomplete != nil {
                VStack(alignment: .leading, spacing: M22BoardMetrics.tightGap) {
                    if answeredOther {
                        note(
                            InsightsBoardCopy.answeredCaption(
                                answered: response.windowHours, asked: askedHours
                            ),
                            id: "caption-answered"
                        )
                    }
                    if let since = incomplete {
                        note(
                            InsightsBoardCopy.incompleteCaption(
                                observedSince: since, hours: response.windowHours
                            ),
                            id: "caption-incomplete"
                        )
                    }
                    if let retention = capped {
                        note(
                            InsightsBoardCopy.cappedCaption(
                                retention.capped, capMegabytes: retention.capMegabytes
                            ),
                            id: "caption-capped"
                        )
                    }
                }
                .measured("coverage-notes", role: "board-section", kind: .vstack)
            }
        }

        private func note(_ text: String, id: String) -> some View {
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

    /// One headline count, with the provenance line that turns a number into a reading.
    struct StatCard: View {
        let label: String
        let value: String
        /// The line under the figure. `DESIGN.md` §6's difference between a number and a claim —
        /// *measured, not modelled* on the memory figure, the numerator beside the failure rate.
        let provenance: String?
        let provenanceTint: ColorToken
        let identifier: String

        var body: some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.labelGap) {
                Text(label)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                    .measured(
                        "stat-label-\(identifier)", role: "stat-label", kind: .text,
                        tokens: ["foreground": .t3], type: .subheadline, text: label
                    )
                Text(value)
                    .typeRole(.title1)
                    .monospaced()
                    .foregroundStyle(ColorToken.t1.color)
                    .measured(
                        "stat-value-\(identifier)", role: "stat-value", kind: .text,
                        tokens: ["foreground": .t1], type: .title1, text: value
                    )
                if let provenance {
                    Text(provenance)
                        .typeRole(.caption)
                        .foregroundStyle(provenanceTint.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .measured(
                            "stat-provenance-\(identifier)", role: "stat-provenance", kind: .text,
                            tokens: ["foreground": provenanceTint], type: .caption, text: provenance
                        )
                }
                Spacer(minLength: 0)
            }
            .padding(M22BoardMetrics.cardPadding)
            .frame(
                minWidth: M22BoardMetrics.statMinWidth,
                maxWidth: .infinity,
                minHeight: M22BoardMetrics.statHeight,
                alignment: .topLeading
            )
            .background(
                RoundedRectangle(cornerRadius: M22BoardMetrics.cardRadius)
                    .fill(ColorToken.raised.color)
                    .overlay(
                        RoundedRectangle(cornerRadius: M22BoardMetrics.cardRadius)
                            .strokeBorder(ColorToken.line.color, lineWidth: M22BoardMetrics.hairline)
                    )
            )
            .measured(
                "stat-\(identifier)", role: "stat-card", kind: .vstack,
                tokens: ["background": .raised, "border": .line]
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label), \(value)\(provenance.map { ", \($0)" } ?? "")")
        }
    }
#endif
