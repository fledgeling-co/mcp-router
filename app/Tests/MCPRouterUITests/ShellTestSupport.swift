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
            "app/Sources/MCPRouterUI/Shell/ScaffoldPane.swift",
            "app/Sources/MCPRouterUI/Shell/ScrollEdge.swift",
            "app/Sources/MCPRouterUI/Shell/ShellChrome.swift",
            "app/Sources/MCPRouterUI/Shell/ShellCommands.swift",
            "app/Sources/MCPRouterUI/Shell/ShellCommandRouter.swift",
            "app/Sources/MCPRouterUI/Shell/ShellClientFactory.swift",
            "app/Sources/MCPRouterUI/Shell/ShellWindowFrame.swift",
            "app/Sources/MCPRouterUI/Shell/ShellMenuReasons.swift"
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
            "app/Sources/MCPRouterUI/Boards/SkillSheets.swift"
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
            "app/Sources/MCPRouterUI/Activity/ActivityModel+Presentation.swift"
        ]

        /// Everything the boundary gates scan.
        static var gatedFiles: [String] { shellFiles + boardFiles + activityFiles }

        /// Every file that draws a surface, and so must obey §7's entry-motion rule.
        static var animatedSurfaceFiles: [String] { shellFiles + boardFiles + activityFiles }
    }
#endif
