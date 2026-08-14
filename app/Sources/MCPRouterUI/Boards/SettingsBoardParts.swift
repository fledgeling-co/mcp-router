#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// A titled group of settings. Sentence case, secondary colour, no case transform anywhere —
    /// `DESIGN.md` §3.2 says the fix for a tracked upper-case header is to remove it, not to
    /// re-track it, so the label is stored the way it is drawn.
    struct SettingsGroup<Content: View>: View {
        let group: SettingsPresentation.Group
        @ViewBuilder let content: Content

        init(_ group: SettingsPresentation.Group, @ViewBuilder content: () -> Content) {
            self.group = group
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: SettingsMetrics.tightGap) {
                Text(group.rawValue)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                    .padding(.bottom, SettingsMetrics.tightGap)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(group.rawValue)
        }
    }

    /// An inset card. Concentric corners: the child radius is the parent's less its padding (§2).
    struct SettingsCard<Content: View>: View {
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
