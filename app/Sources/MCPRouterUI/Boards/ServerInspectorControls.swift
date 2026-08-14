#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// A switch with its one quiet secondary sentence underneath (§6), which dims in place.
    struct ToggleRow: View {
        let title: String
        let help: String
        let isOn: Bool
        let disabledReason: String?
        let set: (Bool) -> Void

        var body: some View {
            Toggle(
                isOn: Binding(get: { isOn }, set: { set($0) })
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .typeRole(.body)
                        .foregroundStyle(disabledReason == nil ? ColorToken.t1.color : ColorToken.t4.color)
                    Text(disabledReason ?? help)
                        .typeRole(.callout)
                        .foregroundStyle(ColorToken.t3.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .disabled(disabledReason != nil)
            .accessibilityHint(disabledReason ?? help)
        }
    }

    /// The tool inventory, wrapping.
    struct FlowingTags: View {
        let names: [String]

        var body: some View {
            // `WrappingHStack` does not exist in SwiftUI; a `LazyVGrid` of adaptive columns is the
            // supported way to wrap a variable-width list without measuring text by hand.
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: ServersBoardMetrics.tagMinimum),
                        spacing: ServersBoardMetrics.tightGap,
                        alignment: .leading
                    )
                ],
                alignment: .leading,
                spacing: ServersBoardMetrics.tightGap
            ) {
                ForEach(names, id: \.self) { name in
                    Text(name)
                        .typeRole(.caption, monospaced: true)
                        .foregroundStyle(ColorToken.t2.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, ServersBoardMetrics.tightGap)
                        .frame(height: MetricToken.controlSmall.leadingScalar)
                        .background(
                            RoundedRectangle(
                                cornerRadius: MetricToken.selectionInset.leadingScalar,
                                style: .continuous
                            )
                            .fill(ColorToken.f2.color)
                        )
                }
            }
        }
    }
#endif
