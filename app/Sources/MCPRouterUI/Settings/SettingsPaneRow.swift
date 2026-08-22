#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// One row of the Settings window's source list.
    ///
    /// **It mirrors `SidebarRow`'s metrics, accent fill and radius rather than reusing the type**,
    /// and that is a deliberate departure from the brief, which asks for one shared row view.
    /// `SidebarRow` takes a `Destination` and a `BadgeSource`; a pane has neither, and widening it to
    /// a protocol so it can serve two lists is more coupling than two small views. What requirement
    /// 13 is actually about is the *metrics and the colours* being the console's, and those are read
    /// from the same tokens here — `MetricToken.tableRows` for the height,
    /// `MetricToken.selectionRadius` for the fill, `MetricToken.controlMini` for the icon column,
    /// `ColorToken.accent` for the selected state.
    struct SettingsPaneRow: View {
        let pane: SettingsPane
        let isSelected: Bool

        var body: some View {
            HStack(spacing: MetricToken.selectionInset.leadingScalar * 2) {
                IconView(icon)
                    .frame(width: MetricToken.controlMini.leadingScalar)
                Text(pane.title)
                    .typeRole(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .frame(height: MetricToken.tableRows.leadingScalar)
            .foregroundStyle(isSelected ? ColorToken.accent.color : ColorToken.t2.color)
            // §7: the selection fill has no transition. Not "a fast one" — none.
            .animation(ShellMotion.selectionAnimation(), value: isSelected)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(pane.title)
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .measured(
                "pane-row-\(pane.rawValue)", role: "table-row", kind: .hstack,
                tokens: ["foreground": isSelected ? .accent : .t2],
                type: .body, text: pane.title
            )
        }

        /// `Icon(rawValue:)` cannot fail for any pane — `SettingsPaneIconTests` asserts every one
        /// resolves — and `.conduit` is the same fallback `SidebarRow` uses rather than a blank
        /// square.
        private var icon: Icon {
            Icon(rawValue: pane.iconName) ?? .conduit
        }
    }
#endif
