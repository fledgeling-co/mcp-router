#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Settings areas governed by the command line or by another board in this app.
    /// Static directions make no claim about the connected router's current capabilities.
    struct GovernedElsewherePane: View {
        let pane: SettingsPane

        var body: some View {
            VStack(alignment: .leading, spacing: SettingsMetrics.gap) {
                if let sentence = SettingsPaneCopy.governance(for: pane) {
                    SettingsHelp(sentence, id: "governance")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
#endif
