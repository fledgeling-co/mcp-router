#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// A23's second half, as a test rather than as a drive of the running app.
    ///
    /// The clause is "⌘1–⌘7 and ⌘, change the **selected destination**, not merely the title: the
    /// sidebar row reports itself selected and the toolbar title follows it". That is a chain of four
    /// links, and each one is evidenced where it can actually be measured:
    ///
    /// 1. the chord is bound to the menu item the inventory names — measured on the **running** app's
    ///    menu bar by `scripts/acceptance/mac-shell.sh` (`AXMenuItemCmdChar` + modifiers);
    /// 2. macOS dispatches that chord to this app — measured in the same script, by posting `⌘H` to
    ///    the process and observing it hide;
    /// 3. the item's operation is a selection — **this suite**;
    /// 4. a selection makes the row report itself selected and the title follow — measured on the
    ///    running app, by setting `AXSelectedRows` and reading the title back.
    ///
    /// Link 3 was previously a closure in `app/MCPRouter`, which no test can reach, and it could not
    /// be exercised through the menu without the app frontmost — see `ShellCommandRouter`'s own note
    /// for the measurement. Moving it into `MCPRouterUI` is what makes it evidence.
    @MainActor
    @Suite("Shell command routing")
    struct ShellCommandRouterTests {
        @Test("every ⌘-digit command selects its own destination, and none selects another's")
        func digitsSelectTheirDestination() {
            for destination in Destination.allCases where destination.selectionDigit != nil {
                #expect(
                    ShellCommandRouter.operation(for: .selectDestination(destination))
                        == .select(destination)
                )
            }
        }

        /// **M8's clause, re-pointed rather than deleted.** It read `⌘, selects Settings — the
        /// destination, not a further view`, and `ShellCommandRouter`'s own comment named this as the
        /// line M8 would change. M15 changed it: Settings is a scene, so the command opens a further
        /// view and the title carries the ellipsis §3.4 requires for one.
        @Test("⌘, opens the Settings scene, and its title promises a further view")
        func settingsOpensTheScene() {
            #expect(ShellCommandRouter.operation(for: .settings) == .openSettingsScene)
            #expect(MenuCommand.settings.title == "Settings…")
            // §3.4: the ellipsis means "opens a further view". The two must agree, and this is the
            // one command where they could plausibly disagree.
            #expect(MenuCommand.settings.opensAFurtherView)
        }

        /// **The arm is not a no-op, and this is what proves it.**
        ///
        /// An earlier draft of this item made `perform(.settings, …)` do nothing, on the reasoning
        /// that `SettingsLink` performs the actuation and the operation need only keep the mapping
        /// falsifiable. An arm that does nothing cannot fail, and the test over it would assert that
        /// a command maps to inaction — so the opener is injected instead, from the one place that
        /// can reach `@Environment(\.openSettings)`, and the clause is behavioural.
        @Test("performing the settings command fires the opener the window installed")
        func performOpensTheSettingsScene() throws {
            let opened = Recorder()
            ShellCommandRouter.provideSettingsOpener { opened.fire() }
            defer { ShellCommandRouter.provideSettingsOpener {} }

            ShellCommandRouter.perform(.settings, on: nil)
            #expect(opened.count == 1, "⌘, reached an arm that does nothing")

            // It does not need a focused window, which is the point: the scene is the app's, not one
            // window's, and a settings window that only opened while the console had focus would be
            // unreachable from the menu-bar popover.
            let model = try ShellTestSupport.model(.populated)
            ShellCommandRouter.perform(.settings, on: model)
            #expect(opened.count == 2)
            #expect(model.selection == .activity, "opening Settings moved the console's selection")
        }

        /// A counter a closure can bump. `@MainActor` throughout, so no lock is needed.
        @MainActor
        final class Recorder {
            private(set) var count = 0
            func fire() {
                count += 1
            }
        }

        @Test("⌃⌘S toggles the sidebar rather than selecting anything")
        func showSidebarToggles() {
            #expect(ShellCommandRouter.operation(for: .showSidebar) == .toggleSidebar)
        }

        /// The direction that catches an invented operation: a command whose surface does not exist,
        /// or one macOS performs itself, must map to nothing. Without this, `showSidebar` could be
        /// quietly wired to a selection and only the first direction above would still pass.
        ///
        /// The acting set grows with each board that ships. M3 added the four the Servers board owns
        /// — `⌘N`, `⌘F`, `⌘R`, `⌘⌫` — which `DESIGN.md` §3.9 requires to work from the menu bar,
        /// since the menu bar is the complete command surface. Everything else is still asserted to
        /// map to nothing, so the guard is narrowed by exactly what shipped rather than relaxed.
        @Test("every command outside the acting set has no shell operation")
        func nothingElseActsOnTheModel() {
            let acting: Set<MenuCommand> = Set(
                Destination.allCases
                    .filter { $0.selectionDigit != nil }
                    .map { MenuCommand.selectDestination($0) }
            )
            .union([.settings, .showSidebar, .about])
            .union([.addServer, .find, .resetServer, .removeServer])
            // M4 adds the one the Skills board owns — `⌘⇧N`, which opens its marketplaces sheet.
            // The set is narrowed by exactly what shipped, never relaxed.
            .union([.addMarketplace])
            // M6 adds `Pair iPhone…`. M1 shipped the item routing to `.none`, which was honest while
            // nothing could answer it; the Inbox board gives it a surface, so it now claims an
            // operation. This is the set being narrowed by exactly what shipped — the same move M3
            // and M4 made — rather than an exemption.
            .union([.pairPhone])
            // M20 adds the three Router verbs the control API can actually perform: `Wake Selected
            // Server` is `patch(warm: true)`, `Review Held Changes…` is the held-change sheet the
            // popover's band already opens, and `Reveal Router Log in Finder` needs no router at
            // all. The other nine commands M20 added are `.featureUnbuilt` in every context and
            // stay outside this set, which is what the loop below asserts about them — a menu item
            // that claimed an operation for a route `src/control.ts` does not serve is exactly the
            // lie M14 was raised for.
            .union([.wakeServer, .reviewHeldChanges, .revealRouterLog])

            for command in MenuCommand.allCases where !acting.contains(command) {
                #expect(
                    ShellCommandRouter.operation(for: command) == .none,
                    "\(command.title) claims an operation the shell does not perform"
                )
            }
        }

        /// The Servers board's four, each mapped to its own operation rather than sharing one.
        @Test("the Servers board's commands each map to their own operation")
        func boardCommandsMapToTheirOperations() {
            #expect(ShellCommandRouter.operation(for: .addServer) == .addServer)
            #expect(ShellCommandRouter.operation(for: .find) == .focusSearch)
            #expect(ShellCommandRouter.operation(for: .resetServer) == .resetSelectedServer)
            #expect(ShellCommandRouter.operation(for: .removeServer) == .removeSelectedServer)
            // M6's, kept in the same shape: its own operation, not folded into an existing one.
            #expect(ShellCommandRouter.operation(for: .pairPhone) == .openPairing)
        }

        /// A26 — availability is a function of what is installed and what is selected.
        @Test("the board's commands enable only once the board is installed and a server is selected")
        func availabilityFollowsTheContext() {
            let nothing = MenuCommand.CommandContext.none
            #expect(MenuCommand.addServer.availability(in: nothing) == .surfaceAbsent)
            #expect(MenuCommand.find.availability(in: nothing) == .surfaceAbsent)
            #expect(MenuCommand.resetServer.availability(in: nothing) == .surfaceAbsent)
            #expect(MenuCommand.removeServer.availability(in: nothing) == .surfaceAbsent)

            let boardNoSelection = MenuCommand.CommandContext(
                installedDestinations: [.servers], selectedServerIsTripped: nil
            )
            #expect(MenuCommand.addServer.availability(in: boardNoSelection) == .enabled)
            #expect(MenuCommand.find.availability(in: boardNoSelection) == .enabled)
            #expect(MenuCommand.resetServer.availability(in: boardNoSelection) == .needsServerSelection)
            #expect(MenuCommand.removeServer.availability(in: boardNoSelection) == .needsServerSelection)

            let healthySelected = MenuCommand.CommandContext(
                installedDestinations: [.servers], selectedServerIsTripped: false
            )
            // Remove works on any selection; Reset only on a tripped one, because resetting a
            // healthy server is a request the router has nothing to do with.
            #expect(MenuCommand.removeServer.availability(in: healthySelected) == .enabled)
            #expect(MenuCommand.resetServer.availability(in: healthySelected) == .needsServerSelection)

            let trippedSelected = MenuCommand.CommandContext(
                installedDestinations: [.servers], selectedServerIsTripped: true
            )
            #expect(MenuCommand.resetServer.availability(in: trippedSelected) == .enabled)
            #expect(MenuCommand.removeServer.availability(in: trippedSelected) == .enabled)
        }

        /// A27 — M1's contract is untouched, which is what lets `spec-M1.md`'s inventory table and
        /// the test that parses it keep passing without an edit.
        @Test("the parameterless availability still answers in M1's world")
        func parameterlessAvailabilityIsUnchanged() {
            #expect(MenuCommand.addServer.availability == .surfaceAbsent)
            #expect(MenuCommand.find.availability == .surfaceAbsent)
            #expect(MenuCommand.resetServer.availability == .surfaceAbsent)
            #expect(MenuCommand.removeServer.availability == .surfaceAbsent)
            for command in MenuCommand.allCases {
                #expect(command.availability == command.availability(in: .none))
            }
        }

        @Test("performing a selection command moves the model's selection and the window title")
        func performMovesTheSelection() throws {
            let model = try ShellTestSupport.model(.populated)
            #expect(model.selection == .activity)

            ShellCommandRouter.perform(.selectDestination(.servers), on: model)
            #expect(model.selection == .servers)
            // The title `ShellWindow` renders is the selection's, so asserting the selection asserts
            // what the toolbar shows. The running app's half of A23 checks the rendered string.
            #expect(model.selection.title == "Servers")

            // `.settings` is deliberately absent here now: it opens a scene rather than moving a
            // selection, and `performOpensTheSettingsScene` above is where that is asserted.
        }

        @Test("performing the sidebar command toggles visibility both ways")
        func performTogglesTheSidebar() throws {
            let model = try ShellTestSupport.model(.populated)
            let start = model.isSidebarVisible
            ShellCommandRouter.perform(.showSidebar, on: model)
            #expect(model.isSidebarVisible == !start)
            ShellCommandRouter.perform(.showSidebar, on: model)
            #expect(model.isSidebarVisible == start)
        }

        /// A command that acts on a model, fired when there is no focused window, must do nothing
        /// rather than reach for some other window's state. This is the case `@FocusedValue` produces
        /// on an inactive app, and it is exactly the case that made A23 unexercisable through the
        /// menu — so it is asserted rather than assumed.
        @Test("a selection command with no focused window does nothing and does not crash")
        func performWithoutAModelIsSafe() {
            ShellCommandRouter.perform(.selectDestination(.evals), on: nil)
            ShellCommandRouter.perform(.showSidebar, on: nil)
        }

        /// The assembly layer must carry no per-command decision, because nothing there is testable.
        /// A grep, not a graph: a closure that mutates the model directly is exactly what this
        /// suite exists to have replaced, and it would compile perfectly well.
        @Test("the app's Scene mutates no model state directly")
        func assemblyCarriesNoOperation() throws {
            let source = try ShellTestSupport.repoFile("app/MCPRouter/MCPRouterApp.swift")
            for forbidden in [
                "model?.select", "model?.isSidebarVisible", "model.select",
                // M8's additions. The menu-bar popover's row action goes through `MenuBarRouter`
                // for the same reason a menu item goes through `ShellCommandRouter`: a decision
                // written in this file is a decision no test can reach. `isMenuBarVisible` may be
                // *bound* here — that is the `isInserted` binding, which is assembly — but never
                // assigned.
                "model.reveal", "model?.reveal",
                "model.isMenuBarVisible =", "NSApp.activate", "NSApp.terminate"
            ] {
                #expect(
                    !source.contains(forbidden),
                    "the Scene carries '\(forbidden)' — that decision belongs in ShellCommandRouter"
                )
            }
            #expect(source.contains("ShellCommandRouter.perform"))
        }
    }
#endif
