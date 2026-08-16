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
    public struct MenuBarStatusItem: View {
        let servers: [MCPServer]?
        /// How many items a paired phone has queued.
        ///
        /// A second reason for the same dot rather than a second dot: both conditions end in a human
        /// deciding something, so the bar still carries no count and still one colour. The
        /// alternative is a queue filling while the menu bar says nothing, which is the failure M8's
        /// own poller section names — a glanceable instrument that silently stops being true.
        let waiting: Int

        public init(servers: [MCPServer]?, waiting: Int = 0) {
            self.servers = servers
            self.waiting = waiting
        }

        @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

        private var wantsAttention: Bool {
            MenuBarPresentation.statusItemNeedsAttention(servers ?? [], waiting: waiting)
        }

        public var body: some View {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "square.stack.3d.up")
                    // Template rendering, so macOS tints it for the bar's appearance and it inverts
                    // correctly on a light menu bar.
                    .renderingMode(.template)
                if wantsAttention { dot }
            }
            .accessibilityLabel(MenuBarPresentation.statusItemLabel(servers ?? [], waiting: waiting))
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
