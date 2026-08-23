#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// One jack: a plug, a server's name, and its condition in words.
    ///
    /// A `Button` rather than a tap gesture, because selecting one is a real operation the keyboard
    /// reaches — it puts the server in the table's selection and in the inspector, which is the
    /// brief's *"one selection, three representations"*.
    struct JackView: View {
        let row: ServerRowModel
        let isSelected: Bool
        let select: () -> Void

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @FocusState private var isFocused: Bool

        private var geometry: SignalPathGeometry { .standard }

        /// The border changes with the state and so does the plug, so neither is the only signal —
        /// and the word under the name is the third. A dormant jack takes the ordinary line rather
        /// than a fourth hue, because "nothing is happening" is not a state that needs marking.
        private var border: ColorToken {
            row.jack.indicator ?? .line
        }

        /// The mock's own duration and curve, read from the geometry rather than written here, and
        /// `nil` under Reduce Motion. The state change is applied regardless — §7 requires the
        /// motion to go, never the meaning.
        private var transition: Animation? {
            guard let seconds = geometry.plugTransition(reduceMotion: reduceMotion) else { return nil }
            return .easeOut(duration: seconds)
        }

        var body: some View {
            Button(action: select) {
                HStack(spacing: geometry.jackGap) {
                    StatePlug(state: row.jack, ringed: true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.name)
                            .typeRole(.callout)
                            .foregroundStyle(ColorToken.t1.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        condition
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, geometry.jackInset)
                .frame(height: geometry.laneHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(
                        cornerRadius: MetricToken.selectionRadius.leadingScalar,
                        style: .continuous
                    )
                    .fill((isSelected ? ColorToken.f1 : ColorToken.raised).color)
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: MetricToken.selectionRadius.leadingScalar,
                        style: .continuous
                    )
                    .strokeBorder(
                        (isSelected ? ColorToken.lineStrong : border).color,
                        lineWidth: ServersBoardMetrics.hairline
                    )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($isFocused)
            .focusRing(isFocused)
            .animation(transition, value: row.jack)
            // The condition in **full** reaches assistive technology whatever the track's width
            // made the label draw, so the contraction is a drawing decision and never a state one.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.name)
            .accessibilityValue(row.condition.word)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .measured(
                "jack-\(row.id)", role: "jack", kind: .hstack,
                text: "\(row.name) \(row.condition.word)"
            )
        }

        /// The condition, in whichever form the track's real width can hold.
        ///
        /// `ViewThatFits` measures rather than estimates: the brief's rule is *"where the width is
        /// tight, drop the redundant word … rather than clipping the countdown"*, and a character
        /// budget derived from an average glyph width would be a guess wearing a measurement's
        /// clothes. Both forms carry the number, so what goes is only ever the word the plug is
        /// already saying.
        private var condition: some View {
            ViewThatFits(in: .horizontal) {
                conditionText(row.condition.word)
                conditionText(row.condition.contracted)
            }
        }

        private func conditionText(_ text: String) -> some View {
            Text(text)
                // Monospace is the instrument voice (§2): a countdown is instrument data.
                .typeRole(.subheadline, monospaced: true)
                .foregroundStyle(ColorToken.t2.color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
#endif
