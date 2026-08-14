#if os(macOS)
    import AppKit
    import Foundation
    import MCPRouterKit
    import SwiftUI
    import Testing
    @testable import MCPRouterUI

    /// Where the shell meets the system: what survives a relaunch, what it is allowed to talk to,
    /// and the scaffold that must not outlive its surface. How a disabled menu item explains itself
    /// moved to `ShellMenuContextTests` at M11, with the defect it was hiding.
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

        /// The same pin for `Activity/`, and it is the one that was actually missing.
        ///
        /// `activityFiles` did not exist at all: `Activity/` was outside every source-level gate,
        /// which is how a row that fades in from zero passed a repository containing a test named
        /// `neverFadesInFromZero`. A hand-written list without a directory pin would only have
        /// deferred the same failure to the next file added here.
        @Test("the Activity file list this suite scans is the whole of what is on disk")
        func activityFileListIsComplete() throws {
            let activityDir = try ShellTestSupport.repoRoot()
                .appendingPathComponent("app/Sources/MCPRouterUI/Activity")
            let onDisk = try FileManager.default
                .contentsOfDirectory(atPath: activityDir.path)
                .filter { $0.hasSuffix(".swift") }
                .sorted()
            let listed = ShellTestSupport.activityFiles
                .map { URL(fileURLWithPath: $0).lastPathComponent }
                .sorted()
            #expect(
                onDisk == listed,
                "an Activity file exists that the source-level gates never look at: \(onDisk) vs \(listed)"
            )
        }
    }
#endif
