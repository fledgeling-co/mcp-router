#if os(macOS)
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// What the Skills board contributes to the menu bar.
    ///
    /// `DESIGN.md` §3.9 — the menu bar is the complete command surface — so a board that ships has
    /// to turn its own commands on. This suite exists because the opposite was true and shipped: the
    /// acceptance pass found `Add marketplace…` still carrying *"This part of the app isn't built
    /// yet."* after the Skills board was installed, which is the shell disagreeing with its own
    /// window.
    @Suite("The Skills board's menu contribution")
    struct SkillsMenuTests {
        private func context(skillsInstalled: Bool) -> MenuCommand.CommandContext {
            MenuCommand.CommandContext(
                installedDestinations: skillsInstalled ? [.servers, .skills] : [.servers],
                selectedServerIsTripped: nil
            )
        }

        @Test("Add marketplace… is disabled with the surface-absent reason before Skills ships")
        func disabledWithoutTheBoard() {
            let availability = MenuCommand.addMarketplace.availability(in: context(skillsInstalled: false))
            #expect(availability == .surfaceAbsent)
            #expect(availability.reason == "This part of the app isn't built yet.")
        }

        @Test("Add marketplace… goes live once the Skills board is installed")
        func enabledWithTheBoard() {
            let availability = MenuCommand.addMarketplace.availability(in: context(skillsInstalled: true))
            #expect(availability == .enabled)
            // The whole point: no reason, because there is nothing left to explain.
            #expect(availability.reason == nil)
        }

        @Test("It is live in the build that actually ships, not only in a synthetic context")
        func liveInTheRealRegistry() {
            // Reads `BoardRegistry.installed` rather than a hand-built set, so this fails if the
            // board is ever un-installed while the menu keeps claiming it works.
            let real = MenuCommand.CommandContext(
                installedDestinations: BoardRegistry.installed,
                selectedServerIsTripped: nil
            )
            #expect(MenuCommand.addMarketplace.availability(in: real) == .enabled)
        }

        @Test("Add marketplace… opens the marketplaces sheet")
        func routesToTheSheet() {
            #expect(ShellCommandRouter.operation(for: .addMarketplace) == .showMarketplaces)
        }

        @Test("The two commands whose surfaces have not shipped still say so")
        func othersStillAbsent() {
            let real = MenuCommand.CommandContext(
                installedDestinations: BoardRegistry.installed,
                selectedServerIsTripped: nil
            )
            // Narrowed by exactly what shipped, never relaxed.
            #expect(MenuCommand.pairPhone.availability(in: real) == .surfaceAbsent)
            #expect(MenuCommand.exportLibrary.availability(in: real) == .surfaceAbsent)
        }
    }
#endif
