#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The status item's label — a template symbol, and a dot only when something wants a decision.
    ///
    /// The brief's rule, and the reason it is a rule: *"an icon that changes constantly is one the
    /// eye filters, and then it filters the one change that mattered."* So the glyph never changes,
    /// the dot carries no count, and the dot is `--attn` in every case — including when the only
    /// cause is a failed index, which the popover's own row draws in `--fail`. Two dot colours in a
    /// 16pt glyph are a code nobody learns; the distinction is drawn where there is a sentence to
    /// carry it.
    struct MenuBarStatusItem: View {
        let servers: [MCPServer]?
        @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

        private var wantsAttention: Bool {
            MenuBarPresentation.statusItemNeedsAttention(servers ?? [])
        }

        var body: some View {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "square.stack.3d.up")
                    // Template rendering, so macOS tints it for the bar's appearance and it inverts
                    // correctly on a light menu bar.
                    .renderingMode(.template)
                if wantsAttention { dot }
            }
            .accessibilityLabel(MenuBarPresentation.statusItemLabel(servers ?? []))
        }

        private var dot: some View {
            Circle()
                .fill(MenuBarPresentation.statusItemDotToken.color)
                .frame(width: PopoverMetrics.dot, height: PopoverMetrics.dot)
                // Colour is never the only signal: under Differentiate Without Color the dot gains
                // a ring so it reads as a shape rather than as a hue.
                .overlay(
                    Circle().strokeBorder(
                        ColorToken.t1.color,
                        lineWidth: differentiateWithoutColor ? PopoverMetrics.hairline : 0
                    )
                )
                .offset(x: PopoverMetrics.hairline * 2, y: -PopoverMetrics.hairline * 2)
        }
    }
#endif
