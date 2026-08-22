#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// A titled group of settings. Sentence case, secondary colour, no case transform anywhere —
    /// `DESIGN.md` §3.2 says the fix for a tracked upper-case header is to remove it, not to
    /// re-track it, so the label is stored the way it is drawn.
    ///
    /// **It takes the title as a string now, and that is the whole of the change from the board's
    /// version.** It used to take `SettingsPresentation.Group`, a four-case enum that was the board's
    /// complete inventory of groups; a window of seven panes has no such closed set, and the headers
    /// it does carry are named on `SettingsPaneCopy` beside the rest of each pane's copy. The enum
    /// went with its last caller.
    struct SettingsGroup<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content

        init(_ title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: SettingsMetrics.tightGap) {
                Text(title)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                    .padding(.bottom, SettingsMetrics.tightGap)
                    .measured(
                        "group-title", role: "group-title", kind: .text,
                        tokens: ["foreground": .t3], type: .subheadline, text: title
                    )
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
            .measured("group", role: "settings-group", kind: .vstack, alignment: "leading")
        }
    }

    /// An inset card. Concentric corners: the child radius is the parent's less its padding (§2).
    struct SettingsCard<Content: View>: View {
        /// Unique among this card's siblings, so two cards in one pane are two nodes in the dump
        /// rather than one that overwrote the other. `index_nodes` refuses a tree in which a path
        /// names more than one node, so an unnamed second card is an inconclusive run, not a quiet
        /// one.
        var id = "card"
        @ViewBuilder let content: Content

        var body: some View {
            VStack(spacing: 0) { content }
                .padding(.horizontal, SettingsMetrics.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
                        .fill(ColorToken.panel.color)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
                        .strokeBorder(ColorToken.line.color, lineWidth: SettingsMetrics.hairline)
                )
                .measured(id, role: "table", kind: .vstack, tokens: ["background": .panel])
        }
    }

    /// One label-left / value-right row on the pane's shared axis.
    ///
    /// A `nil` value is the loading skeleton, and it occupies the **same** row height as a populated
    /// one — which is the whole requirement: a card that resizes when its values land makes the
    /// whole pane jump at the moment the user starts reading it.
    struct SettingsRow: View {
        let label: String
        let value: String?
        var dimmed = false
        var truncatesFromLeft = false

        var body: some View {
            HStack(spacing: SettingsMetrics.gap) {
                Text(label)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .frame(width: SettingsMetrics.labelColumn, alignment: .leading)
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .typeRole(.callout, monospaced: true)
                        .foregroundStyle((dimmed ? ColorToken.t2 : ColorToken.t1).color)
                        .lineLimit(1)
                        // A path is identified by its tail, so a long one truncates from the *left*
                        // — clipping the right end shows only the part every path shares. The whole
                        // value stays reachable in the help tag and the accessibility value, which
                        // is this pane's answer to §5's "the full value in the inspector" in a
                        // surface that has no inspector.
                        .truncationMode(truncatesFromLeft ? .head : .tail)
                        .help(value)
                        .accessibilityValue(value)
                } else {
                    RoundedRectangle(cornerRadius: SettingsMetrics.hairline * 4, style: .continuous)
                        .fill(ColorToken.f2.color)
                        .frame(width: SettingsMetrics.labelColumn * 0.7, height: TypeToken.callout.size)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: SettingsMetrics.rowHeight)
            .measured(
                "row-\(label)", role: "table-row", kind: .hstack,
                type: .body, text: label
            )
        }
    }

    /// A helper sentence under a card: what governs the values above, or where they are set.
    ///
    /// Was a private `helper(_:)` on the Settings board; it is a view now because seven panes draw
    /// it and a function copied into each of them is seven places for the type role to drift.
    struct SettingsHelp: View {
        let text: String
        /// Unique among this pane's siblings, for the reason `SettingsCard`'s is.
        var id = "help"

        init(_ text: String, id: String = "help") {
            self.text = text
            self.id = id
        }

        var body: some View {
            Text(text)
                .typeRole(.subheadline)
                .foregroundStyle(ColorToken.t3.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SettingsMetrics.tightGap)
                .measured(
                    id, role: "state-detail", kind: .text,
                    tokens: ["foreground": .t3], type: .subheadline, text: text
                )
        }
    }

    /// The warm servers, as chips that truncate rather than reflow the row.
    struct WarmChips: View {
        let names: [String]

        var body: some View {
            HStack(spacing: SettingsMetrics.tightGap) {
                ForEach(names, id: \.self) { name in
                    Text(name)
                        .typeRole(.subheadline, monospaced: true)
                        .foregroundStyle(ColorToken.t2.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, SettingsMetrics.gap)
                        .frame(height: SettingsMetrics.chipHeight)
                        .background(
                            RoundedRectangle(
                                cornerRadius: SettingsMetrics.hairline * 10,
                                style: .continuous
                            )
                            .fill(ColorToken.f2.color)
                        )
                        .help(name)
                        .accessibilityValue(name)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, SettingsMetrics.tightGap)
        }
    }
#endif
