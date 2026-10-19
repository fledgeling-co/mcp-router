#if os(macOS)
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// The update check on the Skills board, read through the board model against the fixture client, and the
    /// Promote
    /// control's gate on the router's cache route.
    @Suite("The Skills board's update check and Promote gate")
    @MainActor
    struct SkillsUpdatesModelTests {
        private func loaded(_ scenario: FixtureControlAPIClient.Scenario) async -> SkillsBoardModel {
            let board = SkillsBoardModel(client: FixtureControlAPIClient(scenario))
            await board.load()
            return board
        }

        /// The trawl row as the populated fixture holds it, with the plugin origin the update check matches
        /// on.
        private func trawl(_ board: SkillsBoardModel) throws -> Skill {
            try #require(board.state.response?.skills.first { $0.name == "trawl" })
        }

        @Test(
            "the check offers the installed plugin a newer version, with the changelog the router read for it"
        )
        func offersWithChangelog() async throws {
            let board = await loaded(.populated)

            #expect(board.updatesChecked)
            #expect(board.updatesError == nil)
            let offer = try #require(board.offer(for: trawl(board)))
            #expect(offer.name == "trawl@fledgeling-plugins")
            #expect(offer.available == "2.3.0")
            #expect(offer.reason == "2.3.0 is offered and 2.2.0 is installed")
            #expect(offer.changelog?.text == "## 2.3.0\n- Adds a network call to api.fledgeling.app.\n")
        }

        @Test("an entry the check found current is listed by the router but never offered")
        func currentEntryIsNotOffered() async {
            let board = await loaded(.populated)

            let current = board.updates.first { $0.name == "design-craft@diolog-plugins" }
            #expect(current?.hasUpdate == false)
            #expect(current?.changelog == nil)
            #expect(board.updates.filter(\.hasUpdate).count == 1)
        }

        @Test("a refused check is kept as the router's refusal, and offers nothing")
        func refusedCheckKeepsRows() async {
            let board = await loaded(.error)

            #expect(board.updatesChecked)
            #expect(board.updatesError == ControlAPIError.server(
                status: 422,
                message: "spawn /nonexistent/binary-that-cannot-start ENOENT",
                hint: "retry with ?force=1 to add it anyway"
            ))
            #expect(board.updates.isEmpty)
        }

        @Test("a check over a store with nothing to offer reads as checked and empty, not as still in flight")
        func emptyCheckIsChecked() async {
            let board = await loaded(.empty)

            #expect(board.updatesChecked)
            #expect(board.updatesError == nil)
            #expect(board.updates.isEmpty)
        }

        @Test("before the check answers it has not been checked, so the board shows nothing for it yet")
        func uncheckedBeforeAnswer() {
            let board = SkillsBoardModel(client: FixtureControlAPIClient(.populated))

            #expect(board.updatesChecked == false)
            #expect(board.updates.isEmpty)
        }

        @Test("Promote is taken on a router that serves the cache route, and not on one that predates it")
        func promoteGateFollowsTheRoute() async {
            let serving = await loaded(.populated)
            #expect(serving.promotesFromCache)

            let predating = SkillsBoardModel(client: FixtureControlAPIClient(.empty))
            await predating.load()
            #expect(predating.promotesFromCache == false)
        }

        @Test("a promotion is undone by the bar the board draws, and the undo clears it")
        func undoBarClearsOnUndo() async throws {
            let board = await loaded(.populated)
            let skill = try trawl(board)

            await board.promoteHeldVersion(skill)
            let promoted = try #require(board.lastPromotion)
            #expect(promoted.plugin == "trawl")

            await board.undoLastPromotion()
            #expect(board.lastPromotion == nil)
            #expect(board.writeFailure == nil)
        }
    }
#endif
