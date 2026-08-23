#if os(macOS)
    import AppKit
    import Foundation
    import MCPRouterKit
    import Observation
    import SwiftUI
    import Testing
    @testable import MCPRouterUI

    /// How a menu item explains itself — A22, and the context it reads to decide.
    ///
    /// Split out of `ShellIntegrationTests` at M11 rather than raising that file's length limit.
    /// The seam is real: everything here is about one question — what a command says about its own
    /// availability, and where that answer comes from — and M11 roughly doubled the section while
    /// closing a defect in exactly that seam.
    @Suite("Mac shell — the menu's disabled reasons and the live context")
    struct ShellMenuContextTests {
        /// The bridge exists because SwiftUI's `.help()` does not reach an `NSMenuItem` — every item
        /// reported `AXHelp` as `missing value` until this walker was written. A walker that matched
        /// nothing would look identical to one that worked, so the count is the assertion.
        @MainActor
        @Test("the reason walker sets a tool tip on exactly the commands that have one")
        func menuReasonsApplyToDisabledCommands() {
            let menu = NSMenu()
            let disabled = MenuCommand.allCases.filter { $0.availability.reason != nil }
            for command in disabled {
                menu.addItem(NSMenuItem(title: command.title, action: nil, keyEquivalent: ""))
            }
            // A system item the app never declared, which must be left exactly as macOS left it.
            let foreign = NSMenuItem(title: "Emoji & Symbols", action: nil, keyEquivalent: "")
            menu.addItem(foreign)

            let applied = ShellMenuReasons.apply(to: menu)
            #expect(applied == disabled.count)
            #expect(applied > 0, "the walker matched nothing, which reads exactly like success")

            // Each item carries **its own** command's reason, not one shared sentence.
            //
            // This used to compare every tooltip against `surfaceAbsent.reason`, which passed only
            // because every disabled command happened to share a single string. M14 gave export a
            // different one, and the old form could not have told a walker writing the *right*
            // reason from one writing *a* reason.
            //
            // It reads `reason(in:)` rather than `availability.reason` since M20, which is the
            // whole of `D-m14-a`: nine commands carry `.featureUnbuilt` now, so the availability's
            // own sentence is the generic fallback and the per-command one is what the menu shows.
            // Comparing against the fallback here would have passed a walker that wrote the
            // generic sentence onto all nine.
            for (item, command) in zip(menu.items, disabled) {
                #expect(item.toolTip == command.reason(), "\(command.title)")
                #expect(item.accessibilityHelp() == command.reason(), "\(command.title)")
                // The short form, which is what a person reading the menu actually sees.
                #expect(item.badge?.stringValue == command.availability.badge, "\(command.title)")
            }
            #expect(foreign.toolTip == nil, "the walker touched an item macOS owns")
        }

        @MainActor
        @Test("the walker descends into submenus rather than only the top level")
        func menuReasonsDescend() {
            let root = NSMenu()
            let parent = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.addItem(NSMenuItem(title: MenuCommand.addServer.title, action: nil, keyEquivalent: ""))
            parent.submenu = submenu
            root.addItem(parent)

            #expect(ShellMenuReasons.apply(to: root) == 1)
        }

        /// The half of A22 that had no test, and shipped broken for five items because of it.
        ///
        /// `SkillsMenuTests` asserts `MenuCommand.availability(in:)` returns `.enabled` once the
        /// board is installed, and it always passed. What nothing asserted is which context the
        /// **menu item** asks — and it asked `MenuCommand.availability`, the `.none` shorthand. So
        /// the rule was right, the reason walker was right, and the item on screen was dimmed
        /// anyway. This test is the missing link: it drives the same property the item's `.disabled`
        /// and `.help` modifiers read, through the same registered source the app uses.
        @MainActor
        @Test("a menu item reads the live context, not M1's empty one")
        func commandItemsReadTheLiveContext() {
            defer { ShellMenuReasons.ContextSource.shared.reset() }

            // Exactly what the shipping app registers: the real registry, nothing selected.
            ShellMenuReasons.provideContext {
                MenuCommand.CommandContext(
                    installedDestinations: BoardRegistry.installed,
                    selectedServerIsTripped: nil
                )
            }
            // The three that were dimmed with no reason at all. Each is `.surfaceAbsent` under
            // `.none`, so a regression to the shorthand fails here rather than on a screen.
            for command in [MenuCommand.addServer, .addMarketplace, .find] {
                #expect(CommandItem(command).resolvedAvailability == .enabled)
                #expect(CommandItem(command).resolvedAvailability.reason == nil)
            }
            // Disabled for a *live* reason, which is a different sentence from the absent one.
            for command in [MenuCommand.resetServer, .removeServer] {
                #expect(CommandItem(command).resolvedAvailability == .needsServerSelection)
            }
            // Pairing's board shipped at M6, so this reads the live context as enabled and silent.
            // It asserted `.surfaceAbsent` here until M14 — green, and describing an app that told
            // the user a shipped command did not exist.
            #expect(CommandItem(.pairPhone).resolvedAvailability == .enabled)
            #expect(CommandItem(.pairPhone).resolvedAvailability.reason == nil)
            // Export genuinely has no feature, and now says that rather than borrowing the
            // missing-surface sentence.
            #expect(CommandItem(.exportLibrary).resolvedAvailability == .featureUnbuilt)

            // With no window up there is no provider, and M1's world is the honest answer.
            ShellMenuReasons.ContextSource.shared.reset()
            #expect(CommandItem(.addServer).resolvedAvailability == .surfaceAbsent)
        }

        /// The *dynamic* half, which the test above cannot reach and the acceptance walk cannot
        /// either — it measures one static end state, and a menu built after the provider happened
        /// to register would pass it with Observation entirely broken.
        ///
        /// `CommandItem.body` reads `liveContext`, so SwiftUI re-evaluates the item only if that
        /// read is *tracked*. That is asserted here against `withObservationTracking` directly,
        /// which is the same machinery SwiftUI uses and needs no hosted view to exercise. Both ways
        /// the answer can change are covered: a window registering its provider after the menu was
        /// first built, and the server selection moving underneath an already-registered one.
        ///
        /// The second leg is worth stating precisely, because `serversBoard` is
        /// `@ObservationIgnored` on the model: what is tracked is `ServersBoardModel.selection` on
        /// the board object itself, which is `@Observable`. Reading it through two closures does not
        /// weaken that — tracking follows the access, not the call depth.
        @MainActor
        @Test("the live context is observable, so a menu item re-evaluates when it changes")
        func liveContextIsObservable() throws {
            defer { ShellMenuReasons.ContextSource.shared.reset() }
            ShellMenuReasons.ContextSource.shared.reset()

            final class Box: @unchecked Sendable { var fired = false }

            let scratch = try ShellTestSupport.scratchStore()
            defer { scratch.tearDown() }
            let model = ShellModel(client: FixtureControlAPIClient(.populated), store: scratch.store)

            let onRegister = Box()
            withObservationTracking {
                _ = ShellMenuReasons.liveContext
            } onChange: {
                onRegister.fired = true
            }
            ShellMenuReasons.provideContext { [weak model] in model?.menuContext ?? .none }
            #expect(
                onRegister.fired,
                """
                a window registering its provider did not invalidate a reader of liveContext \
                — a menu built at launch would stay dimmed
                """
            )

            let onSelect = Box()
            withObservationTracking {
                _ = ShellMenuReasons.liveContext
            } onChange: {
                onSelect.fired = true
            }
            model.serversBoard.selection = "any-server"
            #expect(
                onSelect.fired,
                """
                moving the server selection did not invalidate liveContext \
                — Reset server would never come out of needsServerSelection
                """
            )
        }

        /// A stale reason is worse than none: it tells the user a surface is missing while the menu
        /// offers it. The walker's first passes run before any window exists, so it annotates from
        /// `.none` and must be able to take the annotation back.
        @MainActor
        @Test("the reason walker clears a reason that has stopped being true")
        func menuReasonsClearWhenTheSurfaceArrives() {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: MenuCommand.addServer.title, action: nil, keyEquivalent: ""))
            let foreign = NSMenuItem(title: "Emoji & Symbols", action: nil, keyEquivalent: "")
            foreign.toolTip = "macOS wrote this"
            menu.addItem(foreign)

            #expect(ShellMenuReasons.apply(to: menu) == 1)
            #expect(menu.items[0].toolTip == CommandAvailability.surfaceAbsent.reason)

            let live = MenuCommand.CommandContext(
                installedDestinations: BoardRegistry.installed,
                selectedServerIsTripped: nil
            )
            #expect(ShellMenuReasons.apply(to: menu, context: live) == 0)
            #expect(menu.items[0].toolTip == nil)
            #expect(menu.items[0].accessibilityHelp() == nil)
            #expect(foreign.toolTip == "macOS wrote this", "the walker erased an item macOS owns")
        }

        /// A guard on the one number that decides whether A22 is true for a screen-reader user.
        ///
        /// SwiftUI builds a `CommandGroup`'s menu items bare when the menu opens, so the reasons are
        /// absent for however long the re-apply interval is. At one second, an accessibility read of
        /// a freshly-opened Edit menu returned an empty `AXHelp` — measured, in
        /// `scripts/acceptance/mac-shell.sh`, which failed on `Edit / Find`. A tool tip needs a
        /// second of hover and would have hidden this; the accessibility tree is read on focus and
        /// did not.
        @Test("the reasons are re-applied fast enough that a focused item is never bare")
        func reapplyIntervalStaysBelowAFocusRead() {
            #expect(ShellMenuReasons.reapplyInterval <= .milliseconds(250))
            #expect(ShellMenuReasons.reapplyInterval > .zero, "a zero interval is a busy loop")
        }
    }
#endif
