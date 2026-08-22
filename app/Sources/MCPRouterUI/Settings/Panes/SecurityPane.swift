#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Security — the control token, and the devices allowed to queue work on this Mac.
    ///
    /// The mock's `Rotate…` is **not** built: the router owns the token, writes it to its own file,
    /// and there is no rotate endpoint — `SettingsWindowModel.forget()`'s own docstring says so. What
    /// this pane offers instead is forgetting the cached copy, which is the fix when the router has
    /// been reset and the app is still sending the token it had before.
    ///
    /// `Hold schema changes` and `Keep call history for` are absent for the same class of reason:
    /// the held-change *behaviour* ships and the *setting* does not, and there is no retention
    /// window anywhere in the product.
    struct SecurityPane: View {
        @Bindable var shell: ShellModel
        let model: SettingsWindowModel

        var body: some View {
            VStack(alignment: .leading, spacing: SettingsMetrics.groupGap) {
                tokenGroup
                pairedGroup
            }
        }

        // MARK: - The control token

        private var tokenGroup: some View {
            SettingsGroup(SettingsPaneCopy.controlTokenGroup) {
                SettingsCard {
                    SettingsRow(label: SettingsPresentation.tokenLabel, value: model.status.value)
                    SettingsRow(
                        label: SettingsPresentation.tokenSourceLabel,
                        value: model.tokenPath,
                        dimmed: true,
                        truncatesFromLeft: true
                    )
                }
                if let banner = model.status.banner {
                    Banner(icon: .warn, tint: .attention) { Text(banner) }
                        .measured("token-banner", role: "state-detail", kind: .hstack)
                }
                HStack {
                    Spacer(minLength: SettingsMetrics.labelColumn)
                    forgetButton
                }
                .padding(.top, SettingsMetrics.tightGap)
                SettingsHelp(model.tokenHelp, id: "token-help")
            }
        }

        @ViewBuilder
        private var forgetButton: some View {
            let button = Button(SettingsPresentation.forgetAction) {
                Task { await model.forget() }
            }
            .disabled(!model.status.canForget)
            .help(model.status.canForget ? "" : SettingsPresentation.forgetDisabledReason)
            .accessibilityHint(model.status.canForget ? "" : SettingsPresentation.forgetDisabledReason)
            .measured(
                "forget-token", role: "state-action", kind: .leaf,
                type: .body, text: SettingsPresentation.forgetAction
            )

            // §3.4 allows one prominent accent-filled action per view. Forget is it only while the
            // router is rejecting the stored token — the one condition where it is the fix rather
            // than a maintenance chore. Security is the only pane in this window with one.
            if model.status.forgetIsProminent {
                button.buttonStyle(ProminentButtonStyle())
            } else {
                button.buttonStyle(StandardButtonStyle())
            }
        }

        // MARK: - Paired devices

        /// Read-only, and observed rather than served.
        ///
        /// The control API has no devices endpoint. What this Mac genuinely knows is the name on the
        /// inbox snapshot the shell is already polling, which is the one place a paired phone
        /// identifies itself. `Manage…` routes to Inbox — the mock's own `data-act="board:inbox"` —
        /// because that is where the queue and the pairing both live.
        private var pairedGroup: some View {
            SettingsGroup(SettingsPaneCopy.pairedDevicesGroup) {
                SettingsCard(id: "paired-card") {
                    SettingsRow(
                        label: SettingsPaneCopy.pairedDevicesLabel,
                        value: shell.inboxBoard.pairedDeviceName ?? SettingsPaneCopy.pairedDevicesNone,
                        dimmed: shell.inboxBoard.pairedDeviceName == nil
                    )
                }
                HStack {
                    Spacer(minLength: SettingsMetrics.labelColumn)
                    Button(SettingsPaneCopy.pairedDevicesAction) { shell.select(.inbox) }
                        .buttonStyle(StandardButtonStyle())
                        .measured(
                            "manage-devices", role: "state-action", kind: .leaf,
                            type: .body, text: SettingsPaneCopy.pairedDevicesAction
                        )
                }
                .padding(.top, SettingsMetrics.tightGap)
                SettingsHelp(SettingsPaneCopy.pairedDevicesHelp, id: "paired-help")
            }
        }
    }
#endif
