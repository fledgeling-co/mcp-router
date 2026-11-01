#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The Settings window owns this irreversible decision and uses the shell's router client.
    struct SettingsResetHistorySheet: View {
        @Bindable var model: SettingsWindowModel

        private var confirmLabel: String {
            if model.isResetting { return "Updating history…" }
            guard model.resetAcknowledgement == nil else { return "Read updated history" }
            return CleanupPresentation.resetConfirm
        }

        var body: some View {
            VStack(alignment: .leading, spacing: SettingsMetrics.groupGap) {
                Text(CleanupPresentation.resetTitle)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                Text(CleanupPresentation.resetConsequence(calls: nil, window: nil))
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let acknowledgement = model.resetAcknowledgement {
                    Text(
                        "Reset confirmed at \(acknowledgement.since). Read history to finish."
                    )
                    .typeRole(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if let error = model.resetError {
                    Text(error.userFacingDescription)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.fail.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings-reset-error")
                }
                HStack {
                    Spacer(minLength: 0)
                    Button(model.resetAcknowledgement == nil ? "Cancel" : "Close") {
                        model.cancelHistoryReset()
                    }
                    .buttonStyle(StandardButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isResetting)
                    Button(confirmLabel) {
                        Task { await model.resetHistory() }
                    }
                    .buttonStyle(StandardButtonStyle())
                    .disabled(model.isResetting)
                    .accessibilityIdentifier("settings-confirm-reset-history")
                }
            }
            .padding(SettingsMetrics.panePadding)
            .frame(width: M7BoardMetrics.sheetWidth)
            .interactiveDismissDisabled(model.isResetting)
        }
    }
#endif
