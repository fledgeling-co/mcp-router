#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The three panes this product has nothing to put in yet: Harnesses, Session analyst, Updates.
    ///
    /// **Not an empty pane, and not the mock's controls rendered inert.** Each draws its name, its
    /// one line, and one sentence saying what governs the thing and where it is decided today — the
    /// shape `SettingsPresentation.routerHelp` already ships and M8 approved. That satisfies
    /// `DESIGN.md` §6 (nothing invented) and §5 (say what happened and what to do), keeps the seven
    /// areas real rather than decorative, and is copy, which is the cheapest thing in this window to
    /// reverse when the capability lands.
    ///
    /// **One view rather than three files, and that is a deliberate departure from the plan's B4.**
    /// `HarnessesPane`, `AnalystPane` and `UpdatesPane` would be three files identical but for which
    /// `SettingsPaneCopy` case they read; the difference between the three panes is entirely copy,
    /// and copy already lives in the kit where a test can reach it. Three views differing in a
    /// constant is three places for the type role, the padding and the measurement id to drift.
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
