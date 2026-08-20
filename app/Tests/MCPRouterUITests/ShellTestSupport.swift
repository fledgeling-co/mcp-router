#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// What the shell's suites share: the oracle reader, the scratch defaults domain, and the list
    /// of files the source-level gates scan.
    ///
    /// This is a namespace rather than a base type because Swift Testing suites are independent
    /// structs — four suites each re-declaring `repoFile` would be four chances for one of them to
    /// drift into reading a different file than the gate it backs.
    enum ShellTestSupport {
        enum OracleError: Error {
            case fileNotFound(String)
            case sectionNotFound(String)
        }

        /// Waits for a condition to hold rather than for a duration to elapse.
        ///
        /// A fixed `Task.sleep` reads like a wait but is really a bet on scheduler latency, and the
        /// bet is lost exactly when the machine is busy. M5 measured the consequence: a 120ms sleep
        /// before asserting a poll had run passed 5 of 5 in isolation and failed about **four runs
        /// in five under full-suite load**, so every other item's gate had a standing chance of
        /// going red for reasons unrelated to its work — which is the worst kind of gate, because it
        /// teaches the reader to re-run until green.
        ///
        /// The timeout bounds only the failure case. A healthy poll satisfies the condition in a few
        /// milliseconds, so this is also *faster* than the sleep it replaces in the common case.
        ///
        /// Use it only where the assertion is that something BECOMES true. Where the assertion is
        /// that a state *stays* put — `ShellTests.loadingIsTheAbsenceOfAnAnswer` races a
        /// never-returning refresh — there is no condition to wait for and a fixed delay is correct.
        ///
        /// **30 seconds, not 5.** The ceiling is not a guess at how long the work takes — it is the
        /// point past which a stuck condition is worth reporting, and a bound that generous costs a
        /// passing test nothing because it returns the moment the condition holds. Five seconds was
        /// measured to be inside the noise: on 20 Aug 2026 `make test` reported four failures at a
        /// one-minute load average of ~700 and passed all 1473 tests on the same source at load 46,
        /// minutes apart (DEF-030). A suite that reports a defect the product does not have is the
        /// failure this campaign has already paid for once, in DEF-029, where a dead instrument
        /// read as a dead product for ten consecutive runs.
        @MainActor
        static func waitUntil(
            within timeout: Duration = .seconds(30),
            polling interval: Duration = .milliseconds(5),
            _ isSatisfied: () -> Bool
        ) async throws {
            let deadline = ContinuousClock.now + timeout
            while !isSatisfied(), ContinuousClock.now < deadline {
                try await Task.sleep(for: interval)
            }
        }

        /// Walks up to the repository root, the way `MenuCommandTests` finds its oracle.
        ///
        /// `#filePath` defaults to the *calling* file, and every shell suite sits in this same
        /// directory, so the walk is the same distance from each of them.
        static func repoFile(_ relativePath: String, from filePath: String = #filePath) throws -> String {
            var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
            for _ in 0 ..< 8 {
                let candidate = dir.appendingPathComponent(relativePath)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return try String(contentsOf: candidate, encoding: .utf8)
                }
                dir = dir.deletingLastPathComponent()
            }
            throw OracleError.fileNotFound(relativePath)
        }

        /// The repository root, found by the file that is only ever at it.
        static func repoRoot(from filePath: String = #filePath) throws -> URL {
            var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
            for _ in 0 ..< 8 {
                if FileManager.default.fileExists(atPath: dir.appendingPathComponent("DESIGN.md").path) {
                    return dir
                }
                dir = dir.deletingLastPathComponent()
            }
            throw OracleError.fileNotFound("DESIGN.md")
        }

        /// A scratch `UserDefaults` domain, so restoration is tested against real defaults behaviour
        /// without writing into the developer's own preferences.
        ///
        /// A struct rather than a tuple: three anonymous members at a call site is three chances to
        /// unpack them in the wrong order, and the last two exist only to be torn down together.
        struct ScratchStore {
            let store: ShellRestoration
            let defaults: UserDefaults
            let suiteName: String

            func tearDown() {
                defaults.removePersistentDomain(forName: suiteName)
            }
        }

        static func scratchStore() throws -> ScratchStore {
            let suite = "mcprouter.tests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            return ScratchStore(
                store: ShellRestoration(defaults: defaults),
                defaults: defaults,
                suiteName: suite
            )
        }

        @MainActor
        static func model(
            _ scenario: FixtureControlAPIClient.Scenario,
            at now: Date = Date(timeIntervalSince1970: 1_000_000)
        ) throws -> ShellModel {
            let scratch = try scratchStore()
            return ShellModel(client: FixtureControlAPIClient(scenario), store: scratch.store, clock: { now })
        }

        /// Every file this item added under `MCPRouterUI`, so the source-level gates cannot silently
        /// stop covering one. `shellFileListIsComplete` holds this list to what is on disk.
        static let shellFiles = [
            "app/Sources/MCPRouterUI/Shell/ShellModel.swift",
            "app/Sources/MCPRouterUI/Shell/ShellWindow.swift",
            "app/Sources/MCPRouterUI/Shell/Sidebar.swift",
            "app/Sources/MCPRouterUI/Shell/Readout.swift",
            // M27's foot line, enrolled here rather than merely added to the directory: it is the
            // one element in the shell drawn on every board, so a token or indicator-colour gate
            // that could not see it would be blind on all nine surfaces at once.
            "app/Sources/MCPRouterUI/Shell/SidebarFoot.swift",
            "app/Sources/MCPRouterUI/Shell/ScaffoldPane.swift",
            "app/Sources/MCPRouterUI/Shell/ScrollEdge.swift",
            "app/Sources/MCPRouterUI/Shell/ShellChrome.swift",
            "app/Sources/MCPRouterUI/Shell/ShellCommands.swift",
            "app/Sources/MCPRouterUI/Shell/ShellCommandRouter.swift",
            "app/Sources/MCPRouterUI/Shell/ShellClientFactory.swift",
            "app/Sources/MCPRouterUI/Shell/ShellWindowFrame.swift",
            "app/Sources/MCPRouterUI/Shell/ShellMenuReasons.swift",
            // M8's menu-bar surfaces. Enrolled here rather than merely added to the directory,
            // because these files are the ones a token or indicator-colour gate most needs to
            // scan: the status item is the app's most visible surface and its dot is the busiest
            // use of `--attn` in the product.
            "app/Sources/MCPRouterUI/Shell/MenuBarPopover.swift",
            "app/Sources/MCPRouterUI/Shell/MenuBarStatusItem.swift",
            "app/Sources/MCPRouterUI/Shell/MenuBarRouter.swift",
            // Split out of ShellModel.swift to keep it under the 400-line limit — the limit was
            // met by splitting rather than raised, per this repo's own lesson from R2R.
            "app/Sources/MCPRouterUI/Shell/ShellRestoration.swift",
            // M6's badge lookup, moved out of ShellModel so it cannot mutate the model.
            "app/Sources/MCPRouterUI/Shell/ShellModelBadges.swift",
            // M6's factory. Enrolled here rather than merely added to the directory, because it is
            // the file that decides whether a build may render a fixture — and a fixture reaching a
            // Release build of *this* seam draws a QR code for an endpoint nothing is listening on.
            "app/Sources/MCPRouterUI/Shell/ShellPairingFactory.swift",
            // I6's inbox reach. Enrolled for the same reason M8's menu-bar files are: the band is
            // drawn on the app's most visible surface, and the factory is the file that decides
            // whether a notification centre is talked to at all — `UNUserNotificationCenter.current()`
            // traps in a process with no bundle identifier, which is every `swift test` run.
            "app/Sources/MCPRouterUI/Shell/ShellModelInbox.swift",
            "app/Sources/MCPRouterUI/Shell/ArrivalNotifierFactory.swift",
            "app/Sources/MCPRouterUI/Shell/InboxNotificationDelegate.swift",
            "app/Sources/MCPRouterUI/Shell/MenuBarInboxBand.swift"
        ]

        /// The board files, held separately because a completeness test pins `shellFiles` to the
        /// contents of `Shell/` — a directory listing is the only thing that stops a new file
        /// escaping every source-level gate, and folding two directories into one list would break
        /// that check rather than extend it.
        ///
        /// The gates that read both are the ones about *boundaries* rather than about the shell:
        /// A36's one-channel grep and the indicator-colour declaration. A board is more likely to be
        /// tempted past the control API than the window frame is, because it is the surface with
        /// data to show.
        static let boardFiles = [
            // M6's inbox and pairing surfaces.
            "app/Sources/MCPRouterUI/Boards/InboxBoard.swift",
            "app/Sources/MCPRouterUI/Boards/InboxBoardRow.swift",
            "app/Sources/MCPRouterUI/Boards/InboxBoardModel.swift",
            // I6's arrival half, on the same board.
            "app/Sources/MCPRouterUI/Boards/InboxBoardModel+Arrivals.swift",
            "app/Sources/MCPRouterUI/Boards/InboxBoardMetrics.swift",
            "app/Sources/MCPRouterUI/Boards/InboxReviewSheet.swift",
            "app/Sources/MCPRouterUI/Boards/PairingSheet.swift",
            "app/Sources/MCPRouterUI/Boards/PairingSessionModel.swift",
            "app/Sources/MCPRouterUI/Boards/ServersBoard.swift",
            "app/Sources/MCPRouterUI/Boards/ServersBoardRow.swift",
            "app/Sources/MCPRouterUI/Boards/ServersBoardBanners.swift",
            "app/Sources/MCPRouterUI/Boards/ServersBoardMetrics.swift",
            "app/Sources/MCPRouterUI/Boards/ServersBoardModel.swift",
            "app/Sources/MCPRouterUI/Boards/ServersBoardWrites.swift",
            "app/Sources/MCPRouterUI/Boards/ServerInspector.swift",
            "app/Sources/MCPRouterUI/Boards/ServerInspectorSections.swift",
            "app/Sources/MCPRouterUI/Boards/ServerInspectorControls.swift",
            "app/Sources/MCPRouterUI/Boards/ServerSheets.swift",
            "app/Sources/MCPRouterUI/Boards/SkillsBoard.swift",
            "app/Sources/MCPRouterUI/Boards/SkillsBoardRow.swift",
            "app/Sources/MCPRouterUI/Boards/SkillsBoardMetrics.swift",
            "app/Sources/MCPRouterUI/Boards/SkillsBoardModel.swift",
            "app/Sources/MCPRouterUI/Boards/SkillInspector.swift",
            "app/Sources/MCPRouterUI/Boards/SkillSheets.swift",
            // M8's Settings pane.
            "app/Sources/MCPRouterUI/Boards/SettingsBoard.swift",
            "app/Sources/MCPRouterUI/Boards/SettingsBoardModel.swift",
            "app/Sources/MCPRouterUI/Boards/SettingsBoardParts.swift",
            // Split out of ServerSheets.swift for the same reason. It is also the view M8
            // changed, so keeping it separately gated is the honest arrangement.
            "app/Sources/MCPRouterUI/Boards/ToolChangeCard.swift",
            // M5's Discover pane.
            "app/Sources/MCPRouterUI/Boards/DiscoverBoard.swift",
            "app/Sources/MCPRouterUI/Boards/DiscoverBoardRow.swift",
            "app/Sources/MCPRouterUI/Boards/DiscoverBoardMetrics.swift",
            "app/Sources/MCPRouterUI/Boards/DiscoverBoardModel.swift",
            "app/Sources/MCPRouterUI/Boards/DiscoverDetailSheet.swift",
            // M7's Evals and Cleanup panes. Enrolled with the rest rather than left in the
            // directory: `boardFileListIsComplete` caught all nine of these sitting outside every
            // source-level gate — the one-channel grep, the raw-design-value scan, the
            // indicator-hue declaration and the entry-motion guard — which is the same escape that
            // list's doc comment was written about after `ServerInspectorSections.swift`.
            "app/Sources/MCPRouterUI/Boards/EvalsBoard.swift",
            "app/Sources/MCPRouterUI/Boards/EvalsBoardModel.swift",
            "app/Sources/MCPRouterUI/Boards/EvalsBoardRow.swift",
            "app/Sources/MCPRouterUI/Boards/EvalsInspector.swift",
            "app/Sources/MCPRouterUI/Boards/CleanupBoard.swift",
            "app/Sources/MCPRouterUI/Boards/CleanupBoardModel.swift",
            "app/Sources/MCPRouterUI/Boards/CleanupBoardRow.swift",
            "app/Sources/MCPRouterUI/Boards/CleanupSheets.swift",
            "app/Sources/MCPRouterUI/Boards/M7BoardMetrics.swift"
        ]

        /// M2's board, listed for the same reason `boardFiles` is.
        ///
        /// It is called out separately because its absence was a live defect rather than a tidiness
        /// point: `neverFadesInFromZero` iterated `shellFiles` only, so the one board whose list
        /// animates insertions was the one file the entry-motion guard could not see, and a row
        /// that faded in from zero passed every gate in the repository.
        static let activityFiles = [
            "app/Sources/MCPRouterUI/Activity/ActivityBoard.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityRow.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityChrome.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityCondition.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityCopy.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityFilterBar.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityInspector.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityModel.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityModel+Merge.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityModel+Presentation.swift",
            "app/Sources/MCPRouterUI/Activity/ActivityResetHistorySheet.swift"
        ]

        /// Everything the boundary gates scan.
        static var gatedFiles: [String] { shellFiles + boardFiles + activityFiles }

        /// Every file that draws a surface, and so must obey §7's entry-motion rule.
        static var animatedSurfaceFiles: [String] { shellFiles + boardFiles + activityFiles }
    }
#endif
