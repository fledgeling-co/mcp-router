#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Menu bar — the one preference in this window that is genuinely this app's to set.
    ///
    /// It is also why the router-stopped state does not refuse the whole window the way the mock's
    /// `v-empty` frame does: this pane reads nothing from the router, so it stays live and editable
    /// while everything else says it cannot be known.
    ///
    /// `Show the Dock icon` is not built: there is no activation-policy control anywhere in the app.
    /// `Approve from the popover` ships at M20, and it is the one preference in this product that
    /// opens an install path rather than changing what is drawn — which is why it is a row of its own
    /// under its own label rather than a second checkbox beneath the status item's.
    struct MenuBarPane: View {
        @Bindable var shell: ShellModel

        var body: some View {
            SettingsGroup(SettingsPaneCopy.menuBarGroup) {
                HStack(spacing: SettingsMetrics.gap) {
                    Text(SettingsPaneCopy.statusItemLabel)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                        .frame(width: SettingsMetrics.labelColumn, alignment: .leading)
                    Spacer(minLength: 0)
                    Toggle(SettingsPresentation.menuBarToggleLabel, isOn: $shell.isMenuBarVisible)
                        .toggleStyle(.checkbox)
                        .typeRole(.body)
                        .measured(
                            "menu-bar-toggle", role: "state-action", kind: .leaf,
                            type: .body, text: SettingsPresentation.menuBarToggleLabel
                        )
                }
                .frame(minHeight: SettingsMetrics.rowHeight)
                .measured(
                    "row-\(SettingsPaneCopy.statusItemLabel)", role: "table-row", kind: .hstack,
                    type: .body, text: SettingsPaneCopy.statusItemLabel
                )
                SettingsHelp(SettingsPresentation.menuBarHelp, id: "menu-bar-help")
                HStack(spacing: SettingsMetrics.gap) {
                    Text(SettingsPaneCopy.popoverApprovalLabel)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                        .frame(width: SettingsMetrics.labelColumn, alignment: .leading)
                    Spacer(minLength: 0)
                    Toggle(
                        SettingsPresentation.approveFromPopoverLabel,
                        isOn: $shell.isApproveFromPopoverEnabled
                    )
                    .toggleStyle(.checkbox)
                    .typeRole(.body)
                    .measured(
                        "popover-approval-toggle", role: "state-action", kind: .leaf,
                        type: .body, text: SettingsPresentation.approveFromPopoverLabel
                    )
                }
                .frame(minHeight: SettingsMetrics.rowHeight)
                .measured(
                    "row-\(SettingsPaneCopy.popoverApprovalLabel)", role: "table-row", kind: .hstack,
                    type: .body, text: SettingsPaneCopy.popoverApprovalLabel
                )
                SettingsHelp(SettingsPresentation.approveFromPopoverHelp, id: "popover-approval-help")
            }
        }
    }
#endif
