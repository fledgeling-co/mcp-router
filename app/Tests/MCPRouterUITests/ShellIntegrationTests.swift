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
        /// Every spelling of "went around the control API" this gate knows about.
        ///
        /// The last four were added after a completeness critic observed that the set named sockets
        /// and processes but nothing that reads a **file** — and that reading a bundled JSON is
        /// precisely how a surface comes to display a number no router observed, which is what §6
        /// and A18 are about. A grep is the only check that reaches these: `MCPRouterUI` links
        /// Foundation, so all of them are always in scope and always one line away.
        private static let forbiddenChannels = [
            "URLSession", "Process(", "NSTask", "FileManager",
            "NWConnection", "Socket(", "socket(",
            "Data(contentsOf:", "Bundle", "URL(fileURLWithPath:", "contentsOfFile:"
        ]

        @Test("the shell opens no socket, no file and no process of its own")
        func theClientIsTheOnlyChannel() throws {
            for file in ShellTestSupport.gatedFiles {
                let source = try ShellTestSupport.repoFile(file)
                for forbidden in Self.forbiddenChannels {
                    #expect(
                        !source.contains(forbidden),
                        "\(file) reaches past the control API with \(forbidden)"
                    )
                }
            }
        }

        /// The inverse of what this test asserted before F4 merged.
        ///
        /// It used to require that the shell **not** use `ServerStateTracker`, because the tracker
        /// swallowed every typed error in a `try?` and pinned its phase at `.disconnected` with no
        /// stream attached — a shell built on it could not tell offline from an empty poll. F4
        /// fixed exactly that, so the guard now points the other way: a second poll loop beside the
        /// tracker's is the duplication that lets the shell and the boards disagree about what is
        /// running, and it must not come back.
        @MainActor
        @Test("the shell reads the router through ServerStateTracker and not a loop of its own")
        func theTrackerIsTheOneReader() throws {
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/ShellModel.swift")
            #expect(
                source.contains("ServerStateTracker("),
                "the shell no longer constructs the tracker that owns router state"
            )
            // The tell for a hand-rolled loop is a sleep on the shell's own cadence. The tracker
            // owns the interval; a `Task.sleep` here would mean a second one had grown back.
            #expect(
                !source.contains("Task.sleep"),
                "ShellModel is polling on a loop of its own again rather than through the tracker"
            )
        }

        /// A18 at the case F4 made expressible, and the one judgment the shell adds to the tracker.
        ///
        /// `.stale` means an earlier poll succeeded and the refresh has since broken. The servers
        /// behind it are real, so the badges keep them — but "3 running" is a claim about *now*,
        /// and the router is not answering now. The counts therefore go absent while the badge
        /// survives, and this asserts both halves in the same state so neither can be satisfied by
        /// dropping the other.
        @MainActor
        @Test("a stale poll keeps the badges it observed and still withdraws the live counts")
        func staleKeepsBadgesAndDropsCounts() async throws {
            let model = try ShellTestSupport.model(.populated)
            let good = Date(timeIntervalSince1970: 1_000_000)
            await model.refresh(at: good)

            // Precondition, so a broken fixture cannot make the assertion below vacuous.
            let observed = try #require(model.readout.declared)
            #expect(observed > 0)

            // The router stops answering. The tracker moves to `.stale` because a poll did succeed.
            await model.tracker.apply(pollFailure: .routerNotRunning)
            await model.refreshFromTracker(at: good.addingTimeInterval(2))

            #expect(model.readout.running == nil, "a stale poll rendered a count nobody observed")
            #expect(model.readout.declared == nil)
            #expect(model.readout.state == .failed(.routerNotRunning))
            // And the half that is genuinely still known survives.
            #expect(model.servers != nil, "a stale poll threw away servers that were really observed")
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

        /// The two sets are exact complements, in both directions.
        ///
        /// This used to read "M1 installs no board, so every destination is scaffolded" and asserted
        /// `installed.isEmpty`. That is not the invariant — it is the *state* the invariant happened
        /// to have while no board had shipped, and a board landing would have failed it for doing
        /// exactly what it was supposed to. What must always hold is that every destination has
        /// precisely one of the two, which is what makes "a board exists but is not registered"
        /// (the reader sees a placeholder over a finished surface) and "registered with no board"
        /// (the reader sees nothing at all) both impossible.
        @Test("installed and scaffolded are exact complements, both ways")
        func installedAndScaffoldedAreComplements() {
            let installed = BoardRegistry.installed
            let scaffolded = Set(BoardRegistry.scaffolded)

            #expect(installed.isDisjoint(with: scaffolded), "a destination cannot be both")
            #expect(
                installed.union(scaffolded) == Set(Destination.ordered),
                "every destination is one or the other"
            )
            #expect(
                BoardRegistry.installed.count + BoardRegistry.scaffolded.count
                    == Destination.allCases.count
            )
            #expect(
                BoardRegistry.scaffolded == Destination.ordered.filter { !installed.contains($0) },
                "the scaffolded list keeps sidebar order"
            )
        }

        /// The count, stated separately so a board landing is a deliberate edit here rather than
        /// something that slides through a set-algebra assertion unnoticed.
        @Test("this build installs exactly the boards that have shipped")
        func installedIsTheShippedSet() {
            #expect(
                BoardRegistry.installed == [.servers, .activity],
                "M2 ships Activity and M3 ships Servers; M4–M8 each add one and update this line"
            )
            #expect(BoardRegistry.scaffolded.count == 6)
        }

        /// M3's own half: the board is not merely written, it is **registered**.
        ///
        /// This is the assertion the item is actually done against. A board that compiles but is not
        /// in `installed` still shows the user "This part of the app isn't built yet", which is the
        /// exact failure the whole fleet was stopped over.
        @Test("the Servers board is installed, so its pane is not the placeholder")
        func serversBoardIsInstalled() {
            #expect(BoardRegistry.hasBoard(.servers))
            #expect(ScaffoldedDestination(.servers) == nil)
            #expect(!BoardRegistry.scaffolded.contains(.servers))
        }

        /// M2's own half, for the same reason.
        @Test("the Activity board is installed, so its pane is not the placeholder")
        func activityBoardIsInstalled() {
            #expect(BoardRegistry.hasBoard(.activity))
            #expect(ScaffoldedDestination(.activity) == nil)
            #expect(!BoardRegistry.scaffolded.contains(.activity))
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
            // Deliberately a destination that is still scaffolded. Asking for the placeholder copy
            // of an installed board would still pass — `ScaffoldCopy` is a pure formatter — while
            // testing a sentence the reader can never be shown.
            let example = try #require(BoardRegistry.scaffolded.first)
            let title = ScaffoldCopy.title(for: example)
            #expect(title == "\(example.title) isn't built yet")
            #expect(title.contains(ScaffoldCopy.sentinel))
            #expect(ScaffoldCopy.detail(for: example).contains(example.title.lowercased()))

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

        /// The same pin for the boards, and it is not a formality.
        ///
        /// `boardFiles` was written by hand and immediately drifted: `Boards/` held ten files and the
        /// list named nine, so `ServerInspectorSections.swift` — which renders the read-only
        /// configuration section, the one place env and header **keys** reach the screen — was
        /// skipped by both the one-channel grep and the indicator-colour declaration. The list's own
        /// doc comment said a directory listing is the only thing that stops a file escaping every
        /// source-level gate, and then did not have one. This is it.
        @Test("the board file list this suite scans is the whole of what is on disk")
        func boardFileListIsComplete() throws {
            let boardsDir = try ShellTestSupport.repoRoot()
                .appendingPathComponent("app/Sources/MCPRouterUI/Boards")
            let onDisk = try FileManager.default
                .contentsOfDirectory(atPath: boardsDir.path)
                .filter { $0.hasSuffix(".swift") }
                .sorted()
            let listed = ShellTestSupport.boardFiles
                .map { URL(fileURLWithPath: $0).lastPathComponent }
                .sorted()
            #expect(
                onDisk == listed,
                "a board file exists that the source-level gates never look at: \(onDisk) vs \(listed)"
            )
        }
    }
#endif
