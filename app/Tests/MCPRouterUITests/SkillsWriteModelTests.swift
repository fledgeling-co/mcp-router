#if os(macOS)
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// The held-version sheet's writes, through the board model, against the fixture client.
    ///
    /// A promotion names only the version: the router reads the files from Claude's plugin cache, so the
    /// board never
    /// holds what it installs. The refusal path uses the fixture's error scenario, which refuses every call.
    /// That is the
    /// only refusal the fixture can produce without a second client, and it is enough to show the model keeps
    /// a refusal
    /// visible and claims no success for it.
    @Suite("The held-version sheet's writes")
    @MainActor
    struct SkillsWriteModelTests {
        /// The trawl row as the board reads it from the populated fixture.
        private func loadedTrawl() async throws -> (SkillsBoardModel, Skill) {
            let board = SkillsBoardModel(client: FixtureControlAPIClient(.populated))
            await board.load()
            let skill = try #require(board.state.response?.skills.first { $0.name == "trawl" })
            return (board, skill)
        }

        /// A plugin-held skill for the refusal path, where the board has no loaded row to read from.
        private func heldSkill() -> Skill {
            Skill(
                name: "trawl",
                path: "/Users/you/.claude/plugins/cache/fledgeling-plugins/trawl/2.2.0/skills/trawl",
                source: .plugin(PluginOrigin(
                    plugin: "trawl",
                    marketplace: "fledgeling-plugins",
                    pluginVersion: "2.2.0"
                )),
                held: HeldVersion(pluginVersion: "2.3.0", addedCapabilities: ["network api.fledgeling.app"])
            )
        }

        private let refusal = ControlAPIError.server(
            status: 422,
            message: "spawn /nonexistent/binary-that-cannot-start ENOENT",
            hint: "retry with ?force=1 to add it anyway"
        )

        @Test("keeping a held version records it and says so, with nothing to confirm first")
        func keepRecordsAndSays() async throws {
            let (board, skill) = try await loadedTrawl()

            await board.keepHeldVersion(skill)

            #expect(board.writeFailure == nil)
            #expect(board.notice == SkillPresentation.kept("2.3.0"))
            #expect(board.writing == false)
        }

        @Test("a refused keep is shown as the router's refusal, and nothing is reported as kept")
        func keepRefusalIsShown() async {
            let board = SkillsBoardModel(client: FixtureControlAPIClient(.error))

            await board.keepHeldVersion(heldSkill())

            #expect(board.writeFailure == refusal)
            #expect(board.notice == nil)
            #expect(board.writing == false)
        }

        @Test("a standalone skill has no held version to keep, so keeping it changes nothing")
        func standaloneKeepIsANoOp() async {
            let board = SkillsBoardModel(client: FixtureControlAPIClient(.populated))
            let standalone = Skill(
                name: "intent-layer",
                path: "/Users/you/.agents/skills/intent-layer",
                source: .standalone(path: "/Users/you/.agents/skills/intent-layer")
            )

            await board.keepHeldVersion(standalone)

            #expect(board.notice == nil)
            #expect(board.writeFailure == nil)
        }

        @Test("a promotion is reported and can be undone, and the undo says what it put back")
        func promoteThenUndo() async throws {
            let (board, skill) = try await loadedTrawl()

            await board.promoteHeldVersion(skill)

            #expect(board.writeFailure == nil)
            #expect(board.lastPromotion?.name == "trawl@fledgeling-plugins")
            #expect(board.notice == SkillPresentation.promoted(name: "trawl", version: "2.3.0"))

            await board.undoLastPromotion()

            #expect(board.writeFailure == nil)
            #expect(board.lastPromotion == nil)
            #expect(board.notice == SkillPresentation.undone(name: "trawl", version: "2.2.0"))
        }

        @Test("an unreadable store cannot authorize a router copy or report success")
        func promoteRefusalIsShown() async {
            let board = SkillsBoardModel(client: FixtureControlAPIClient(.error))

            await board.promoteHeldVersion(heldSkill())

            #expect(board.writeFailure == .server(
                status: 409, message: SkillPresentation.routerCopyNotRead,
                hint: SkillPresentation.installedPluginUpdateUnavailable
            ))
            #expect(board.lastPromotion == nil)
            #expect(board.notice == nil)
        }
    }
#endif
