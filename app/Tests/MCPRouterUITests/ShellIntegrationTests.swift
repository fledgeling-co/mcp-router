#if os(macOS)
    import AppKit
    import Foundation
    import MCPRouterKit
    import SwiftUI
    import Testing
    @testable import MCPRouterUI

    /// Where the shell meets the system: what survives a relaunch, what it is allowed to talk to,
    /// how a disabled menu item explains itself, and the scaffold that must not outlive its surface.
    @Suite("Mac shell — restoration, boundary and commands")
    struct ShellIntegrationTests {
        // MARK: - A32 · restoration

        @MainActor
        @Test("the selected destination and the sidebar survive a new process")
        func restorationRoundTrips() throws {
            let scratch = try ShellTestSupport.scratchStore()
            defer { scratch.tearDown() }

            let first = ShellModel(client: FixtureControlAPIClient(.populated), store: scratch.store)
            first.select(.evals)
            first.isSidebarVisible = false

            // A second model reading the same store is what a relaunch is, minus the process.
            let second = ShellModel(client: FixtureControlAPIClient(.populated), store: scratch.store)
            #expect(second.selection == .evals)
            #expect(second.isSidebarVisible == false)
        }

        @MainActor
        @Test("a stored destination this build no longer has falls back rather than blanking")
        func unknownStoredDestinationFallsBack() throws {
            let scratch = try ShellTestSupport.scratchStore()
            defer { scratch.tearDown() }

            scratch.defaults.set("marketplaces", forKey: ShellRestoration.destinationKey)
            let model = ShellModel(client: FixtureControlAPIClient(.populated), store: scratch.store)
            #expect(model.selection == Destination.fallback)
            #expect(model.selection == .activity)
        }

        /// `bool(forKey:)` returns `false` for a key nobody wrote, which would hide the sidebar on
        /// every first launch. The boundary worth testing is the absent key, not the stored one.
        @MainActor
        @Test("a first launch shows the sidebar rather than inheriting Bool's zero value")
        func firstLaunchShowsTheSidebar() throws {
            let scratch = try ShellTestSupport.scratchStore()
            defer { scratch.tearDown() }
            #expect(scratch.defaults.object(forKey: ShellRestoration.sidebarVisibleKey) == nil)
            #expect(scratch.store.restoredSidebarVisible())
        }

        // MARK: - A36 · one channel

        /// Every way a Swift file can reach the outside world without going through the client.
        /// A dependency graph cannot see a direct call; a source grep can.
        private static let forbiddenChannels = [
            "URLSession", "Process(", "NSTask", "FileManager",
            "NWConnection", "Socket(", "socket("
        ]

        @Test("the shell opens no socket, no file and no process of its own")
        func theClientIsTheOnlyChannel() throws {
            for file in ShellTestSupport.shellFiles {
                let source = try ShellTestSupport.repoFile(file)
                for forbidden in Self.forbiddenChannels {
                    #expect(
                        !source.contains(forbidden),
                        "\(file) reaches past the control API with \(forbidden)"
                    )
                }
            }
        }

        @MainActor
        @Test("the shell does not use ServerStateTracker, whose typed errors are discarded")
        func theTrackerIsNotUsed() throws {
            for file in ShellTestSupport.shellFiles {
                let source = try ShellTestSupport.repoFile(file)
                #expect(
                    !source.contains("ServerStateTracker("),
                    "\(file) built a tracker that cannot tell offline from an empty poll"
                )
            }
        }

        // MARK: - A22 · the disabled reason is reachable

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

            for item in menu.items where item !== foreign {
                #expect(item.toolTip == CommandAvailability.surfaceAbsent.reason)
                #expect(item.accessibilityHelp() == CommandAvailability.surfaceAbsent.reason)
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

        // MARK: - A20 · the SwiftUI shortcut mapping

        /// The chord-level parity against §8 lives in `MenuCommandTests`. What is only checkable
        /// here is the crossing into SwiftUI, where a capital letter silently means shift.
        @Test("a chord's key never smuggles in a modifier the document did not ask for")
        func shortcutMappingAddsNoModifiers() {
            #expect(KeyChord("H").keyEquivalent.character == "h")
            #expect(KeyChord("H").eventModifiers == .command)
            #expect(KeyChord("H", [.command, .option]).eventModifiers == [.command, .option])
            #expect(KeyChord("N", [.command, .shift]).eventModifiers == [.command, .shift])
            #expect(KeyChord("S", [.command, .control]).eventModifiers == [.command, .control])
            #expect(KeyChord("⌫").keyEquivalent == .delete)
            #expect(KeyChord(",").keyEquivalent.character == ",")
            #expect(KeyChord("1").keyEquivalent.character == "1")
        }

        // MARK: - A25 · focus order

        @Test("the shell's focus order is a prefix of §8's, with nothing interposed")
        func focusOrderIsAPrefixOfTheDocument() throws {
            let design = try ShellTestSupport.repoFile("DESIGN.md")
            #expect(design.contains("Tab order runs sidebar → table → inspector"))
            let documented = ["sidebar", "table", "inspector"]
            let shipped = ShellWindow.focusOrder

            // M1 has no table and no inspector, so it ships the head of that order. What must be
            // true is that nothing of the shell's own sits between the sidebar and the content.
            #expect(shipped.first == documented.first)
            #expect(shipped.count == 2)
            #expect(shipped == ["sidebar", "content"])
        }

        // MARK: - The scaffold cannot outlive the surface it stands in for

        @Test("M1 installs no board, so every destination is scaffolded")
        func everyDestinationIsScaffoldedForNow() {
            #expect(BoardRegistry.installed.isEmpty)
            #expect(BoardRegistry.scaffolded == Destination.ordered)
        }

        /// The structural half of the orchestrator's condition: the placeholder cannot be built for
        /// a destination whose board has shipped. Not "should not" — the initialiser returns nil.
        @Test("the scaffold refuses to exist for a destination with a board")
        func scaffoldRefusesAnInstalledDestination() {
            for destination in Destination.allCases {
                let permission = ScaffoldedDestination(destination)
                #expect(
                    (permission != nil) == !BoardRegistry.hasBoard(destination),
                    "\(destination.title)'s scaffold and its board disagree about which exists"
                )
            }
        }

        @Test("the scaffold copy names the surface and offers no action it cannot perform")
        func scaffoldCopyIsHonest() throws {
            let title = ScaffoldCopy.title(for: .activity)
            #expect(title == "Activity isn't built yet")
            #expect(title.contains(ScaffoldCopy.sentinel))
            #expect(ScaffoldCopy.detail(for: .activity).contains("activity"))

            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/ScaffoldPane.swift")
            #expect(!source.contains("Button("), "the scaffold offered a control with nothing behind it")
        }

        // MARK: - Icons

        @Test("every destination's icon name resolves to a real case")
        func destinationIconsResolve() {
            for destination in Destination.allCases {
                #expect(
                    Icon(rawValue: destination.iconName) != nil,
                    "\(destination.title) names an icon that does not exist"
                )
            }
        }

        /// Holds the scanned-file list to what is actually on disk, so a shell file added later
        /// cannot quietly escape every source-level gate above.
        @Test("the file list this suite scans is the whole of what the item added")
        func shellFileListIsComplete() throws {
            let shellDir = try ShellTestSupport.repoRoot()
                .appendingPathComponent("app/Sources/MCPRouterUI/Shell")
            let onDisk = try FileManager.default
                .contentsOfDirectory(atPath: shellDir.path)
                .filter { $0.hasSuffix(".swift") }
                .sorted()
            let listed = ShellTestSupport.shellFiles
                .map { URL(fileURLWithPath: $0).lastPathComponent }
                .sorted()
            #expect(
                onDisk == listed,
                "a shell file exists that the source-level gates never look at: \(onDisk) vs \(listed)"
            )
        }
    }
#endif
