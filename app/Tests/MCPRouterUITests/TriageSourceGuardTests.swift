#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// Structural guards over I3's own source, and the client rule a Release build must not bend.
    ///
    /// Each guards a claim no runtime assertion on the macOS host can reach: an interaction that is
    /// absent, a method that is never referenced, and a dispatch arm that routes to the wrong
    /// screen. Scanning is done with comments and string literals stripped first, for the reason
    /// `PhoneSourceGuardTests` states — the naive version matches its own documentation and then
    /// gets deleted for being noisy, which is how a gate dies.
    @Suite("Triage, Queue and Library source guards")
    struct TriageSourceGuardTests {
        enum GuardError: Error { case rootNotFound, nothingScanned }

        static func repoRoot() throws -> URL {
            var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            for _ in 0 ..< 8 {
                if FileManager.default.fileExists(atPath: dir.appendingPathComponent("DESIGN.md").path) {
                    return dir
                }
                dir = dir.deletingLastPathComponent()
            }
            throw GuardError.rootNotFound
        }

        static func swiftFiles(under relativePath: String) throws -> [(name: String, source: String)] {
            let root = try repoRoot().appendingPathComponent(relativePath)
            guard let walker = FileManager.default.enumerator(atPath: root.path) else {
                throw GuardError.nothingScanned
            }
            var files: [(String, String)] = []
            for case let path as String in walker where path.hasSuffix(".swift") {
                let url = root.appendingPathComponent(path)
                try files.append((path, String(contentsOf: url, encoding: .utf8)))
            }
            // A scan that scanned nothing must not read as a pass. `GuardError.nothingScanned`
            // catches a wholly empty root; the *partial* coverage failure is closed by placement —
            // these directories are the ones the views actually live in (A29).
            guard !files.isEmpty else { throw GuardError.nothingScanned }
            return files
        }

        static func stripped(_ source: String) -> String {
            var out = ""
            for line in source.components(separatedBy: .newlines) {
                let withoutComment = line.components(separatedBy: "//").first ?? ""
                var inString = false
                var kept = ""
                for character in withoutComment {
                    if character == "\"" { inString.toggle(); continue }
                    if !inString { kept.append(character) }
                }
                out += kept + "\n"
            }
            return out
        }

        /// The three directories this item added. Named rather than globbed, so a new sibling root
        /// is a deliberate addition to this list rather than something silently unscanned.
        static let surfaceRoots = [
            "app/Sources/MCPRouterUI/Phone/Triage",
            "app/Sources/MCPRouterUI/Phone/Queue",
            "app/Sources/MCPRouterUI/Phone/Library"
        ]

        // MARK: - A1: no gesture commits anything

        /// The rejected swipe deck, Apple Mail's swipe-to-reveal and Whering's numbered stepper all
        /// share one property that disqualified them: the act happens where the affordance is not
        /// visible before it is touched. The criterion is therefore the negative one, and it is
        /// checkable — **no view in this feature attaches a drag or a swipe action.**
        @Test("no Triage, Queue or Library view attaches a drag or a swipe action")
        func noSwipeOrDragAnywhere() throws {
            var offenders: [String] = []
            for root in Self.surfaceRoots {
                for file in try Self.swiftFiles(under: root) {
                    let source = Self.stripped(file.source)
                    let forbiddenGestures = ["DragGesture", "swipeActions", "onDelete", "gesture("]
                    for forbidden in forbiddenGestures where source.contains(forbidden) {
                        offenders.append("\(root)/\(file.name): \(forbidden)")
                    }
                }
            }
            #expect(offenders.isEmpty, "a gesture-committed act reached the surface: \(offenders)")
        }

        // MARK: - A22: the Library is read-only

        /// The phone queues and never installs, and the Library is the narrowest surface in the
        /// app. Asserted structurally because a screen that merely *does not currently call* a
        /// mutating method looks identical to one that cannot.
        @Test("the Library references no mutating control-API method")
        func libraryIsReadOnly() throws {
            let mutating = [
                "add(", "remove(", "patch(", "reindex(", "resetUsage(",
                "approvePendingChange(", "beginAuthorization(", "signOut("
            ]
            var offenders: [String] = []
            for file in try Self.swiftFiles(under: "app/Sources/MCPRouterUI/Phone/Library") {
                let source = Self.stripped(file.source)
                for method in mutating where source.contains(method) {
                    offenders.append("\(file.name): \(method)")
                }
            }
            #expect(offenders.isEmpty, "the Library reached for a mutating method: \(offenders)")
        }

        /// A16: the Queue ships no send control. Two independent reasons — it would be a false
        /// affordance even after the transport lands, and `SendCommitBar` binds
        /// `.disabled(!state.canSend)` while the app passes a hardcoded `.reachable`, so it would
        /// render **enabled**: an active "Send N to Mac" that does nothing.
        @Test("the Queue ships no send control")
        func queueHasNoSendControl() throws {
            var offenders: [String] = []
            for file in try Self.swiftFiles(under: "app/Sources/MCPRouterUI/Phone/Queue") {
                let source = Self.stripped(file.source)
                for forbidden in ["SendCommitBar", "canSend"] where source.contains(forbidden) {
                    offenders.append("\(file.name): \(forbidden)")
                }
            }
            #expect(offenders.isEmpty, "a send control reached the Queue: \(offenders)")
        }

        // MARK: - A30: the dispatch is a switch, and each arm reaches its own surface

        /// **The mechanism an earlier draft described was wrong in a way its own test could not
        /// catch.** The shipped dispatch was `if .discover { … } else if let key = awaitingKey { … }
        /// else { PhoneSettingsScreen }` — so making `awaitingKey` return nil for the three new tabs
        /// would have routed all three to the final `else`, rendering **Settings** on Triage, Queue
        /// and Library while every "no awaiting copy is compiled" check stayed green.
        ///
        /// This reads the whole `content(for:)` body rather than matching one line, the way
        /// `board-registry.sh` collects a whole registry rather than grepping a row: reformatting
        /// then cannot make it quietly match nothing and read as a pass.
        @Test("each tab's dispatch arm names its own screen")
        func dispatchArmsAreCorrect() throws {
            let shell = try Self.swiftFiles(under: "app/Sources/MCPRouterUI/Phone")
                .first { $0.name.hasSuffix("PhoneShell.swift") }
            let source = try Self.stripped(#require(shell?.source, "PhoneShell.swift was not scanned"))

            let body = try #require(
                source.components(separatedBy: "private func content(for tab: Tab)").last,
                "content(for:) was not found — the dispatch was renamed and this guard went blind"
            )

            let expected: [(String, String)] = [
                ("case .discover:", "DiscoverScreen"),
                ("case .triage:", "TriageScreen"),
                ("case .queue:", "QueueScreen"),
                ("case .library:", "LibraryScreen"),
                ("case .settings:", "PhoneSettingsScreen")
            ]

            var cursor = body
            for (arm, screen) in expected {
                let parts = cursor.components(separatedBy: arm)
                #expect(parts.count > 1, "the dispatch has no \(arm)")
                guard parts.count > 1 else { continue }
                let rest = parts[1]
                // The arm's screen must be the FIRST view named after it, so an arm falling through
                // to a later case cannot pass by naming the right type further down.
                let nextArm = expected
                    .compactMap { rest.range(of: $0.0)?.lowerBound }
                    .min()
                let armBody = nextArm.map { String(rest[rest.startIndex ..< $0]) } ?? rest
                #expect(
                    armBody.contains(screen),
                    "\(arm) does not reach \(screen) — it renders something else"
                )
                cursor = rest
            }
        }

        /// `awaitingKey` and `AwaitingTab` are dead once every tab has a surface, and are deleted
        /// with **all four** keys — `.discoverAwaiting` included, which has had no caller since I2
        /// and would survive a scan of `MCPRouterUI` because the key lives in `MCPRouterKit`.
        @Test("the awaiting placeholder is gone from the phone entirely")
        func awaitingIsRetired() throws {
            var offenders: [String] = []
            for file in try Self.swiftFiles(under: "app/Sources/MCPRouterUI/Phone") {
                let source = Self.stripped(file.source)
                for forbidden in ["awaitingKey", "AwaitingTab"] where source.contains(forbidden) {
                    offenders.append("\(file.name): \(forbidden)")
                }
            }
            #expect(offenders.isEmpty, "the awaiting placeholder survived: \(offenders)")
        }

        /// `PhoneShell` gained an `initialTab` parameter so A30's per-tab assertion can host the
        /// shell *on* a tab — the failure it exists to catch, three tabs all rendering Settings, is
        /// indistinguishable from success unless a test can select one and read what came back.
        ///
        /// **The shipped default must not have moved.** Adding a seed to a merged shared surface is
        /// the change that silently alters which screen the app opens on, so the default is pinned
        /// here rather than left to a reader of the signature. A phone with no paired Mac has to
        /// open on Settings, because pairing is the only useful act there.
        @Test("the shell still opens on Settings by default")
        func defaultTabIsUnchanged() throws {
            let shell = try Self.swiftFiles(under: "app/Sources/MCPRouterUI/Phone")
                .first { $0.name.hasSuffix("PhoneShell.swift") }
            let source = try Self.stripped(#require(shell?.source))

            #expect(
                source.contains("initialTab: Tab = .settings"),
                "the shell's default tab moved away from Settings"
            )
            #expect(
                source.contains("_selection = State(initialValue: initialTab)"),
                "the seed is declared but not applied — initialTab would be silently ignored"
            )
        }

        // MARK: - A32: a Release build may never render a fixture

        /// The Library is the one surface whose entire claim is *this is what you have installed*: a
        /// fixture there presents invented servers as the user's real declared set, in the present
        /// tense, on a device with no router. `isDebugBuild` is a parameter rather than a read
        /// precisely so a Debug test run can assert the Release branch — the only way this rule is
        /// checkable at all.
        @Test("a Release build takes the live client and ignores the environment")
        func releaseIgnoresTheEnvironment() {
            let choice = PhoneClientFactory.choice(
                isDebugBuild: false,
                environment: [PhoneClientFactory.scenarioVariable: "populated"]
            )
            #expect(choice == .live, "a Release build was talked into a fixture by an env var")

            for scenario in FixtureControlAPIClient.Scenario.allCases {
                let forced = PhoneClientFactory.choice(
                    isDebugBuild: false,
                    environment: [PhoneClientFactory.scenarioVariable: scenario.rawValue]
                )
                #expect(forced == .live, "Release honoured the scenario \(scenario.rawValue)")
            }
        }

        /// The other half: Debug reads the scenario, which is what gives the acceptance lane a way
        /// to drive Loading, Partial, Error and Offline at all.
        @Test("a Debug build takes the named scenario")
        func debugHonoursTheScenario() {
            let choice = PhoneClientFactory.choice(
                isDebugBuild: true,
                environment: [PhoneClientFactory.scenarioVariable: "offline"]
            )
            #expect(choice == .fixture(.offline))
        }

        /// An unrecognised name falls back to the populated fixture rather than to `.live`: in Debug
        /// the honest failure is the designed default, not a silent switch to a client that will
        /// answer nothing on a simulator.
        @Test("an unknown scenario name falls back to the populated fixture in Debug")
        func debugFallsBackToPopulated() {
            #expect(
                PhoneClientFactory.choice(
                    isDebugBuild: true,
                    environment: [PhoneClientFactory.scenarioVariable: "not-a-scenario"]
                ) == .fixture(.populated)
            )
            #expect(PhoneClientFactory.choice(isDebugBuild: true, environment: [:]) == .fixture(.populated))
        }
    }
#endif
