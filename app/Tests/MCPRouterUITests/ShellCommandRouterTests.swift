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

        @Test("⌘, selects Settings — the destination, not a further view")
        func settingsSelectsTheDestination() {
            #expect(ShellCommandRouter.operation(for: .settings) == .select(.settings))
            // §3.4: no ellipsis means the command commits now. The two must agree, and this is the
            // one command where they could plausibly disagree.
            #expect(MenuCommand.settings.opensAFurtherView == false)
        }

        @Test("⌃⌘S toggles the sidebar rather than selecting anything")
        func showSidebarToggles() {
            #expect(ShellCommandRouter.operation(for: .showSidebar) == .toggleSidebar)
        }

        /// The direction that catches an invented operation: a command whose surface does not exist,
        /// or one macOS performs itself, must map to nothing. Without this, `showSidebar` could be
        /// quietly wired to a selection and only the first direction above would still pass.
        @Test("every command outside the View menu's own three has no shell operation")
        func nothingElseActsOnTheModel() {
            let acting: Set<MenuCommand> = Set(
                Destination.allCases
                    .filter { $0.selectionDigit != nil }
                    .map { MenuCommand.selectDestination($0) }
            )
            .union([.settings, .showSidebar, .about])

            for command in MenuCommand.allCases where !acting.contains(command) {
                #expect(
                    ShellCommandRouter.operation(for: command) == .none,
                    "\(command.title) claims an operation the shell does not perform"
                )
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

            ShellCommandRouter.perform(.settings, on: model)
            #expect(model.selection == .settings)
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
            for forbidden in ["model?.select", "model?.isSidebarVisible", "model.select"] {
                #expect(
                    !source.contains(forbidden),
                    "the Scene carries '\(forbidden)' — that decision belongs in ShellCommandRouter"
                )
            }
            #expect(source.contains("ShellCommandRouter.perform"))
        }
    }
#endif
