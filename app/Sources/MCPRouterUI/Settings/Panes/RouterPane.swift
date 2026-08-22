#if os(macOS)
    import AppKit
    import MCPRouterKit
    import SwiftUI

    /// Router — the endpoint, the reaper, the counting window and the warm set.
    ///
    /// Every value here is **read from the router and none is writable**, which is not a narrowing
    /// of the mock so much as what the wire allows: `ControlPaths.isControlPath` admits `/servers`,
    /// `/usage` and `/registry`, and the sole mutation shape for an existing server is
    /// `ServerPatch`, which carries no router setting. So the pane shows the facts and says, in
    /// place, where they are configured — which is `routerHelp`, unchanged from the board M8 shipped.
    ///
    /// The mock's `Start at login` and `Child PATH` rows are not built. There is no login-item
    /// mechanism in either target, and `/servers` carries no PATH field for the app to observe.
    struct RouterPane: View {
        @Bindable var shell: ShellModel
        let facts: SettingsPresentation.RouterFacts?
        let offlineError: ControlAPIError?

        var body: some View {
            VStack(alignment: .leading, spacing: SettingsMetrics.groupGap) {
                routerGroup
                warmSetGroup
            }
        }

        // MARK: - Router

        private var routerGroup: some View {
            SettingsGroup(SettingsPaneCopy.routerGroup) {
                if let error = offlineError {
                    // Verbatim from `ControlAPIError` — F3's wording, asserted by `ControlCopyTests`,
                    // and deliberately carrying no action: nothing in this tree can start a router,
                    // and a button that cannot act is worse than the sentence. Recorded as a
                    // deviation from `DESIGN.md` §5 in spec-M8 and re-recorded in spec-M15.
                    Banner(icon: .bang, tint: .fail) {
                        Text("\(error.headline). \(error.advice)")
                    }
                    .measured("router-offline", role: "state-detail", kind: .hstack)
                    SettingsHelp(SettingsPaneCopy.routerFactsUnavailable, id: "router-offline-detail")
                } else if let facts {
                    SettingsCard {
                        SettingsRow(label: SettingsPaneCopy.endpointLabel, value: facts.endpoint)
                        SettingsRow(
                            label: SettingsPaneCopy.homeLabel,
                            value: facts.homeDisplay(),
                            truncatesFromLeft: true
                        )
                        SettingsRow(label: SettingsPaneCopy.idleLabel, value: facts.reaper)
                        SettingsRow(label: SettingsPaneCopy.sinceLabel, value: facts.sinceDisplay())
                    }
                    copyEndpoint(facts.endpoint)
                    SettingsHelp(SettingsPresentation.routerHelp, id: "router-help")
                } else {
                    // Skeletons at the populated row's exact height, so nothing moves when the
                    // values land. Never a spinner over a blank card.
                    SettingsCard {
                        ForEach(Self.routerRowLabels, id: \.self) { label in
                            SettingsRow(label: label, value: nil)
                        }
                    }
                }
            }
        }

        static let routerRowLabels = [
            SettingsPaneCopy.endpointLabel,
            SettingsPaneCopy.homeLabel,
            SettingsPaneCopy.idleLabel,
            SettingsPaneCopy.sinceLabel
        ]

        /// The mock's one Router affordance that survives §4, and the reason it does: copying is an
        /// **app** affordance over a string already on screen, not a router setting. Nothing is sent
        /// anywhere and nothing is read from disk.
        private func copyEndpoint(_ endpoint: String) -> some View {
            HStack {
                Spacer(minLength: SettingsMetrics.labelColumn)
                Button(SettingsPaneCopy.copyEndpointAction) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(endpoint, forType: .string)
                }
                .buttonStyle(StandardButtonStyle())
                .measured(
                    "copy-endpoint", role: "state-action", kind: .leaf,
                    type: .body, text: SettingsPaneCopy.copyEndpointAction
                )
            }
            .padding(.top, SettingsMetrics.tightGap)
        }

        // MARK: - Warm set

        private var warmSetGroup: some View {
            SettingsGroup(SettingsPaneCopy.warmSetGroup) {
                let warm = shell.servers.map(SettingsPresentation.WarmSet.init(servers:))
                SettingsCard(id: "warm-card") {
                    SettingsRow(
                        label: SettingsPresentation.warmSetLabel,
                        value: warm?.summary ?? SettingsPresentation.warmSetUnknown,
                        dimmed: warm == nil
                    )
                }
                if let warm, !warm.isEmpty {
                    WarmChips(names: warm.names)
                }
                HStack {
                    Spacer(minLength: SettingsMetrics.labelColumn)
                    // It crosses a window boundary now: the selection moves on the shell model as
                    // before, and the console window comes forward on its own or not at all. What
                    // this button must never do is act on some other window's state silently, which
                    // is why it still goes through the one model the scene was handed.
                    Button(SettingsPresentation.warmSetAction) { shell.select(.servers) }
                        .buttonStyle(StandardButtonStyle())
                        .measured(
                            "show-in-servers", role: "state-action", kind: .leaf,
                            type: .body, text: SettingsPresentation.warmSetAction
                        )
                }
                .padding(.top, SettingsMetrics.tightGap)
                SettingsHelp(
                    (warm?.isEmpty ?? true)
                        ? SettingsPresentation.warmSetEmptyHelp
                        : SettingsPresentation.warmSetPopulatedHelp,
                    id: "warm-help"
                )
            }
        }
    }
#endif
