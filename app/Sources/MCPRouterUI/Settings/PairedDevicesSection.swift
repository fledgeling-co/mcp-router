#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    struct PairedDevicesSection: View {
        @Bindable var devices: PairedDevicesModel
        let pairAnother: () -> Void

        var body: some View {
            SettingsGroup("Paired devices") {
                if devices.error != nil, devices.phones != nil {
                    SettingsHelp(
                        "Last successful reading. Refresh before changing a phone’s access.",
                        id: "devices-stale"
                    )
                }
                if let phones = devices.phones {
                    SettingsCard(id: "paired-card") {
                        if phones.isEmpty {
                            SettingsRow(label: "Confirmed phones", value: "None", dimmed: true)
                        } else {
                            ForEach(phones) { phone in deviceRow(phone) }
                        }
                    }
                } else if devices.state != nil {
                    SettingsHelp(
                        """
                        This router does not provide a confirmed-device list. \
                        Update the router to manage paired phones.
                        """
                    )
                } else if devices.error == nil {
                    SettingsCard(id: "paired-card") {
                        SettingsRow(label: "Confirmed phones", value: nil)
                    }
                }
                if devices.isLoading {
                    SettingsHelp("Refreshing the device list…", id: "devices-loading")
                }
                if let error = devices.error {
                    Banner(icon: .warn, tint: .attention) { Text(error.userFacingDescription) }
                }
                if let notice = devices.notice {
                    SettingsHelp(notice, id: "device-result")
                }
                HStack {
                    Button("Refresh") { Task { await devices.load() } }
                        .disabled(devices.isLoading || devices.isRevoking)
                    Spacer(minLength: 0)
                    Button("Open Inbox…", action: pairAnother)
                        .help("Pair another phone from Inbox.")
                }
                .buttonStyle(StandardButtonStyle())
                SettingsHelp(
                    """
                    Unpairing removes a phone's permission to send new items. \
                    Items already in Inbox remain there.
                    """,
                    id: "paired-help"
                )
            }
            .task { await devices.load() }
            .sheet(item: $devices.pendingPhone) { phone in
                PairedDeviceRevokeSheet(devices: devices, phone: phone)
                    .interactiveDismissDisabled(devices.isRevoking)
            }
        }

        private func deviceRow(_ phone: ConfirmedPairedPhone) -> some View {
            let date = phone.pairedAt.formatted(date: .abbreviated, time: .omitted)
            return HStack(spacing: SettingsMetrics.gap) {
                VStack(alignment: .leading, spacing: SettingsMetrics.tightGap) {
                    Text(phone.phoneName)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t1.color)
                        .lineLimit(1)
                        .help(phone.phoneName)
                    Text(
                        "Paired \(date) · \(phone.phoneId)"
                    )
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t2.color)
                    .lineLimit(1)
                    .help(phone.phoneId)
                }
                Spacer(minLength: 0)
                Button("Unpair…") { devices.requestRevoke(phone) }
                    .buttonStyle(StandardButtonStyle())
                    .disabled(!devices.canRevoke)
                    .accessibilityLabel("Unpair \(phone.phoneName)")
            }
            .padding(.vertical, SettingsMetrics.gap)
        }
    }

    struct PairedDeviceRevokeSheet: View {
        @Bindable var devices: PairedDevicesModel
        let phone: ConfirmedPairedPhone

        var body: some View {
            SheetFrame(title: "Unpair \(phone.phoneName)?") {
                VStack(alignment: .leading, spacing: SettingsMetrics.gap) {
                    Text(
                        """
                        This phone will no longer be allowed to send new items to this Mac. \
                        Pair it again to restore access.
                        """
                    )
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                    Text("Device ID: \(phone.phoneId)")
                        .typeRole(.caption, monospaced: true)
                        .foregroundStyle(ColorToken.t3.color)
                        .textSelection(.enabled)
                    Text("Items already in Inbox remain there.")
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                }
            } actions: {
                Button("Cancel") { devices.cancelRevoke() }
                    .buttonStyle(StandardButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .disabled(devices.isRevoking)
                Button(devices.isRevoking ? "Unpairing…" : "Unpair", role: .destructive) {
                    Task { await devices.confirmRevoke() }
                }
                .buttonStyle(StandardButtonStyle())
                .disabled(!devices.canRevoke)
            }
        }
    }
#endif
