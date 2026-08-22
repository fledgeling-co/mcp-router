#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// A two-part badge, drawn from what it says.
    ///
    /// **Re-drawn rather than loaded, and that is the whole point of it.** A shields.io badge is a
    /// remote image, and requesting one tells a third party which capability the person at the
    /// machine is reading at the moment they are deciding whether to install it. There is no URL on
    /// `Shield` for this view to reach for.
    ///
    /// The value cell takes one of the app's own two fills. `--shield-good` exists because the
    /// published badge greens fail the contrast floor under white text at badge type size; it
    /// measures 6.88:1 light and 3.15:1 dark under `--on-accent`, and 9.72:1 / 6.60:1 under
    /// increased contrast. Neither fill is the badge's own colour, which `Shield` cannot carry.
    struct ShieldView: View {
        let shield: Shield
        /// Position in its row, so the measured node's name is unique among its siblings.
        let index: Int

        /// The fill for the value cell. Two arms, and both are tokens.
        private var valueFill: ColorToken {
            switch shield.tone {
            case .good: .shieldGood
            case .neutral: .accentInk
            }
        }

        var body: some View {
            HStack(spacing: 0) {
                cell(shield.key, foreground: .t2, background: .f1)
                cell(shield.value, foreground: .onAccent, background: valueFill)
            }
            .frame(height: DocumentMetrics.shieldHeight)
            .clipShape(RoundedRectangle(cornerRadius: DocumentMetrics.shieldRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DocumentMetrics.shieldRadius, style: .continuous)
                    .strokeBorder(ColorToken.line.color, lineWidth: DocumentMetrics.hairline)
            }
            // Announced as one phrase rather than two labels, for the reason `DESIGN.md` records
            // for the sidebar's readout card: a cell carrying a value announces as one sentence,
            // and splitting it costs a reader a swipe to reach a label with no value on its own.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(shield.key), \(shield.value)")
            .measured(
                "badge-\(index)", role: "badge", kind: .hstack,
                tokens: ["background": valueFill, "foreground": .onAccent],
                type: .subheadline, text: "\(shield.key) \(shield.value)"
            )
        }

        private func cell(_ text: String, foreground: ColorToken, background: ColorToken) -> some View {
            Text(text)
                .typeRole(.subheadline)
                .foregroundStyle(foreground.color)
                .padding(.horizontal, DocumentMetrics.shieldPadding)
                .frame(maxHeight: .infinity)
                .background(background.color)
        }
    }
#endif
