#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    // MARK: - One row

    /// A row of the board. Fixed height, whatever it contains.
    ///
    /// `DESIGN.md` §5's Overflow rule is "long names truncate with the full value in the inspector;
    /// rows never change height", and the fixed frame is what makes that true rather than hoped for
    /// — without it a long name wraps and the row grows, which is the failure the rule exists to
    /// rule out.
    struct ServerRowView: View {
        let row: ServerRowModel
        let isSelected: Bool
        let isWriting: Bool
        /// Whether the router can be told anything at all right now.
        ///
        /// The row's action is a **write** — a PATCH or a reindex — and it was gated on `isWriting`
        /// alone, so on a stale load it stayed live one column away from a Behaviour toggle dimming
        /// with `cannotWriteReason` for exactly that condition. Offering a control that will fail is
        /// worse than dimming one that explains itself (`DESIGN.md` §3.4), and the board already
        /// said so in `ServersBoardModel.cannotWriteReason` while this control ignored it.
        let canWrite: Bool
        let error: ControlAPIError?
        let select: () -> Void
        let act: (ServerRowAction) async -> Void

        /// Why the action is dimmed, or `nil` when it is live. Mirrors the inspector's property of
        /// the same name so the two cannot drift into disagreeing about one condition.
        private var disabledReason: String? {
            if isWriting { return ServersBoardModel.applyingReason }
            if !canWrite { return ServersBoardModel.cannotWriteReason }
            return nil
        }

        @FocusState private var isFocused: Bool

        var body: some View {
            Button(action: select) {
                HStack(spacing: ServersBoardMetrics.gap) {
                    // The indicator, not a switch: there is no start or stop operation on the
                    // control API, so a control offering one would be offering something that
                    // cannot happen. `Space` on the selected row toggles Keep warm instead, which is
                    // the lever the router actually has.
                    Breaker(state: row.breaker)
                        .measured("breaker", role: "row-indicator", kind: .leaf)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.name)
                            .typeRole(.body)
                            .foregroundStyle(ColorToken.t1.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .measured(
                                "name", role: "row-name", kind: .text,
                                tokens: ["foreground": .t1], type: .body, text: row.name
                            )
                        Text(subtitleText)
                            // Monospace is the instrument voice (§2): this line is status data.
                            .typeRole(.caption, monospaced: true)
                            .foregroundStyle(subtitleTint.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .measured(
                                "state", role: "row-state", kind: .text,
                                tokens: ["foreground": subtitleTint], type: .caption, text: subtitleText
                            )
                    }
                    .frame(width: ServersBoardMetrics.nameColumn, alignment: .leading)
                    .measured("name-block", role: "row-name-block", kind: .vstack, alignment: "leading")

                    cell(row.transport, width: ServersBoardMetrics.transportColumn, tint: .t2)
                    cell("\(row.tools)", width: ServersBoardMetrics.toolsColumn, tint: .t2)
                    callsCell
                    cell(
                        row.lastUsed.map { shortAgo($0) } ?? "Never",
                        width: ServersBoardMetrics.lastUsedColumn,
                        tint: row.lastUsed == nil ? .t3 : .t2
                    )

                    Spacer(minLength: 0)
                    action
                }
                .padding(.horizontal, ServersBoardMetrics.rowPadding)
                .frame(height: MetricToken.serversRow.leadingScalar)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .selectionFill(isSelected)
            .focused($isFocused)
            .focusRing(isFocused)
            // The full name reaches assistive technology even when the label truncates.
            .accessibilityElement(children: .contain)
            .accessibilityLabel(row.name)
            .accessibilityValue(subtitleText)
            .measured("row-\(row.id)", role: "table-row", kind: .hstack, text: rowText)
        }

        /// Every string this row draws, in draw order.
        ///
        /// A container that reports no text of its own is paired against a mock row whose label is
        /// its whole subtree's text, and the two are then not compared at all — which the M23 gate
        /// reports as `unclassified` rather than as agreement. Composing it here is what turns that
        /// row into a real comparison, and it is a concatenation of the cells above rather than a
        /// second spelling of them: change a cell and this changes with it.
        private var rowText: String {
            var parts = [row.name, subtitleText, row.transport, "\(row.tools)", "\(row.calls)"]
            if row.errors > 0 { parts.append("\(row.errors)") }
            parts.append(row.lastUsed.map { shortAgo($0) } ?? "Never")
            if let action = row.action { parts.append(action.label) }
            return parts.joined(separator: " ")
        }

        /// A failed write is reported **against this row**, replacing the state line, because that is
        /// where the thing that failed is (§5). It is never swallowed to keep the board tidy.
        private var subtitleText: String {
            if let error { return error.headline }
            return row.subtitle.text
        }

        private var subtitleTint: ColorToken {
            error == nil ? row.subtitle.tint : .fail
        }

        private func cell(_ text: String, width: Double, tint: ColorToken) -> some View {
            Text(text)
                .typeRole(.callout, monospaced: true)
                .foregroundStyle(tint.color)
                .frame(width: width, alignment: .trailing)
        }

        /// Calls, then the failures among them. `--fail` here is the one non-breaker place an
        /// indicator colour appears on a row, and it appears meaning exactly what it means.
        private var callsCell: some View {
            HStack(spacing: ServersBoardMetrics.tightGap) {
                Text("\(row.calls)")
                    .typeRole(.callout, monospaced: true)
                    .foregroundStyle((row.calls == 0 ? ColorToken.t3 : ColorToken.t2).color)
                if row.errors > 0 {
                    Text("\(row.errors)")
                        .typeRole(.callout, monospaced: true)
                        .foregroundStyle(ColorToken.fail.color)
                }
            }
            .frame(width: ServersBoardMetrics.callsColumn, alignment: .trailing)
            .accessibilityLabel(
                row.errors > 0
                    ? "\(row.calls) calls, \(row.errors) failed"
                    : "\(row.calls) calls"
            )
        }

        /// The contextual action, or nothing.
        ///
        /// Nothing is the common case and it renders an **empty cell**. The prototype fills it with
        /// an eval chip; the control API observes no eval for a server, so there is nothing behind
        /// one and §6 rules it out.
        @ViewBuilder
        private var action: some View {
            if let action = row.action {
                Button(action.label) {
                    Task { await act(action) }
                }
                // Not accent-filled: §3.4 allows one prominent action per view and it is
                // `Add server…`. The prototype paints `Review…` with the accent class, against its
                // own rule.
                .buttonStyle(StandardButtonStyle(scale: .small))
                .disabled(disabledReason != nil)
                // `.help` as well as the hint: a dimmed control owes a *visible* reason, and a
                // hint reaches VoiceOver only. This is the same carrier M1 used for a disabled
                // menu command.
                .help(disabledReason ?? "")
                .accessibilityHint(disabledReason ?? "")
            }
        }
    }

    // MARK: - Filter and search

    struct ServerFilterBar: View {
        @Binding var filter: ServerFilter
        let counts: [ServerFilter: Int]

        var body: some View {
            // §3.6: a segmented control switches the view in place and is never primary navigation.
            Picker("", selection: $filter) {
                ForEach(ServerFilter.allCases) { option in
                    Text(label(for: option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: ServersBoardMetrics.filterWidth)
            .accessibilityLabel("Filter servers")
        }

        /// The count is shown only when there is one, so a zero never reads as a considered figure.
        private func label(for option: ServerFilter) -> String {
            guard let count = counts[option], count > 0 else { return option.title }
            return "\(option.title) \(count)"
        }
    }

    struct ServerSearchField: View {
        @Binding var query: String

        var body: some View {
            HStack(spacing: ServersBoardMetrics.tightGap) {
                IconView(.search, size: TypeToken.callout.size)
                    .foregroundStyle(ColorToken.t3.color)
                TextField("Search servers and tools", text: $query)
                    .textFieldStyle(.plain)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t1.color)
            }
            .padding(.horizontal, ServersBoardMetrics.rowPadding)
            .frame(
                width: ServersBoardMetrics.searchWidth,
                height: MetricToken.controlRegular.leadingScalar
            )
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
        }
    }

#endif
