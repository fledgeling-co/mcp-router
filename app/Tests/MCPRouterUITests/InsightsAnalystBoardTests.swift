#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// The Insights board's analyst card — F7, and the end of `DEF-065`.
    ///
    /// **The control is proved by actuation plus a state read outside it.** Pressing `Analyse now`
    /// is one channel; what the board then draws came back from a *second* `GET /insights` that the
    /// press did not write, and the client counts both. A test asserting only that the button's
    /// closure ran would pass against the empty closure this item replaced, because an empty closure
    /// also runs.
    @Suite("F7 · the Insights analyst card")
    @MainActor
    struct InsightsAnalystBoardTests {
        /// A client that answers `GET /insights` differently after the analyst has run, and counts
        /// every call.
        ///
        /// The staged second answer is the point: a client returning the same response either way
        /// makes "the board redrew from the router" and "the board did nothing" the same picture.
        final class StagingClient: AnalystTestClient, @unchecked Sendable {
            private let lock = NSLock()
            private var ran = false
            private(set) var insightsReads = 0
            private(set) var analystRuns = 0
            private(set) var patches: [AnalystPatch] = []
            /// When true, every analyst write refuses — the state a router without one produces.
            var refuses = false

            func insights() async throws(ControlAPIError) -> InsightsResponse {
                lock.withLock { insightsReads += 1 }
                let hasRun = lock.withLock { ran }
                var response = InsightsFixtures.populated
                response.analyst = hasRun ? InsightsFixtures.analystRun : InsightsFixtures.analystIdle
                return response
            }

            func runAnalyst() async throws(ControlAPIError) -> InsightsResponse {
                lock.withLock { analystRuns += 1 }
                if refuses { throw ControlAPIError.server(status: 502, message: "no model", hint: nil) }
                lock.withLock { ran = true }
                return try await insights()
            }

            func setAnalyst(
                primary: String?, fallback: String?, cadence: String?
            ) async throws(ControlAPIError) -> InsightsResponse {
                lock.withLock {
                    patches.append(
                        AnalystPatch(primary: primary, fallback: fallback, cadence: cadence)
                    )
                }
                if refuses { throw ControlAPIError.server(status: 422, message: "no", hint: nil) }
                return try await insights()
            }
        }

        static func loaded(_ client: StagingClient) async -> InsightsBoardModel {
            let board = InsightsBoardModel(client: client)
            await board.load()
            return board
        }

        @Test("before the press the card has settings and no reading")
        func idleBeforeThePress() async {
            let board = await Self.loaded(StagingClient())
            let analyst = board.analyst
            #expect(analyst != nil)
            #expect(analyst?.hasRun == false)
            #expect(analyst?.linesRead == nil)
            #expect(board.canAnalyse)
        }

        @Test("pressing Analyse now posts once and redraws from a SECOND read")
        func pressActuates() async {
            let client = StagingClient()
            let board = await Self.loaded(client)
            let readsBefore = client.insightsReads

            await board.analyseNow()

            // The actuation.
            #expect(client.analystRuns == 1)
            // The state read outside it: a further `GET /insights` happened, and what the board now
            // holds is what that read returned.
            #expect(client.insightsReads > readsBefore)
            #expect(board.analyst?.hasRun == true)
            #expect(board.analyst?.linesRead == 12400)
            #expect(board.analyst?.recent.map(\.entryID) == ["docker-mcp", "pgcli"])
            #expect(board.analystError == nil)
        }

        @Test("a run that fails leaves the previous reading on screen and says what refused")
        func failedRunKeepsTheReading() async {
            let client = StagingClient()
            client.refuses = true
            let board = await Self.loaded(client)

            await board.analyseNow()

            #expect(client.analystRuns == 1)
            #expect(board.analystError != nil)
            // The counts the write never touched are still there.
            #expect(board.state.response?.calls.total == 853)
            #expect(board.analyst?.hasRun == false)
        }

        @Test("each menu patches only its own member")
        func menusPatchOneMemberEach() async {
            let client = StagingClient()
            let board = await Self.loaded(client)

            await board.choose(primary: "codex")
            await board.choose(fallback: "gemini")
            await board.choose(cadence: "daily")

            #expect(client.patches.count == 3)
            #expect(client.patches[0] == .init(primary: "codex", fallback: nil, cadence: nil))
            #expect(client.patches[1] == .init(primary: nil, fallback: "gemini", cadence: nil))
            #expect(client.patches[2] == .init(primary: nil, fallback: nil, cadence: "daily"))
        }

        @Test("a router with no analyst offers nothing to press")
        func noAnalystNoControl() async {
            let board = InsightsBoardModel(client: NoAnalystClient())
            await board.load()
            #expect(board.analyst == nil)
            #expect(board.canAnalyse == false)
            // And the press is refused by the model as well as by the disabled control, so a
            // keyboard route to it cannot reach the router either.
            await board.analyseNow()
            #expect(board.analystError == nil)
        }

        /// A router that serves `/insights` and has no analyst — which is every router before F7
        /// and the TypeScript reference for ever.
        struct NoAnalystClient: AnalystTestClient {
            func insights() async throws(ControlAPIError) -> InsightsResponse {
                var response = InsightsFixtures.populated
                response.analyst = nil
                return response
            }
        }

        @Test("the card names every store the run could not open")
        func unreadStoresAreNamed() async {
            let client = StagingClient()
            let board = await Self.loaded(client)
            await board.analyseNow()
            let run = board.analyst
            let summary = InsightsBoardCopy.analystUnreadSummary(run ?? InsightsFixtures.analystIdle)
            #expect(run?.unreadStores.count == 2)
            #expect(summary?.contains("SQLite") == true)
            #expect(summary?.contains("grokCLI") == true)
        }
    }

    /// One settings write, in order. A named value rather than a three-member tuple so that
    /// "which member did this press patch" is readable at the assertion rather than positional.
    struct AnalystPatch: Sendable, Equatable {
        var primary: String?
        var fallback: String?
        var cadence: String?
    }

    /// Everything a board double has to conform to and nothing this suite is about.
    ///
    /// A protocol with defaults rather than the same sixteen forwarding methods typed twice: the
    /// two doubles below differ in exactly three operations, and repeating the rest would bury that.
    protocol AnalystTestClient: ControlAPIClient {}

    extension AnalystTestClient {
        var inner: FixtureControlAPIClient { FixtureControlAPIClient(.populated) }

        func servers() async throws(ControlAPIError) -> ServersResponse {
            try await inner.servers()
        }

        func server(named name: String) async throws(ControlAPIError) -> MCPServer {
            try await inner.server(named: name)
        }

        func usage(
            limit: Int?, server: String?, cwd: String?
        ) async throws(ControlAPIError) -> UsageResponse {
            try await inner.usage(limit: limit, server: server, cwd: cwd)
        }

        func usageSummary() async throws(ControlAPIError) -> UsageSummary {
            try await inner.usageSummary()
        }

        func heldChanges(for name: String) async throws(ControlAPIError) -> HeldChanges {
            try await inner.heldChanges(for: name)
        }

        func searchRegistry(
            query: String, limit: Int
        ) async throws(ControlAPIError) -> RegistrySearchResponse {
            try await inner.searchRegistry(query: query, limit: limit)
        }

        func skills() async throws(ControlAPIError) -> SkillsResponse {
            try await inner.skills()
        }

        func marketplaces() async throws(ControlAPIError) -> MarketplacesResponse {
            try await inner.marketplaces()
        }

        func add(_ server: NewServer, force: Bool) async throws(ControlAPIError) -> AddedServer {
            try await inner.add(server, force: force)
        }

        func remove(
            _ name: String, keepHistory: Bool
        ) async throws(ControlAPIError) -> RemovedServer {
            try await inner.remove(name, keepHistory: keepHistory)
        }

        func reindex(_ name: String) async throws(ControlAPIError) -> ReindexResult {
            try await inner.reindex(name)
        }

        func patch(
            server name: String, _ patch: ServerPatch
        ) async throws(ControlAPIError) -> MCPServer {
            try await inner.patch(server: name, patch)
        }

        func approvePendingChange(
            server name: String
        ) async throws(ControlAPIError) -> ApprovalResult {
            try await inner.approvePendingChange(server: name)
        }

        func beginAuthorization(
            for name: String
        ) async throws(ControlAPIError) -> AuthorizationStart {
            try await inner.beginAuthorization(for: name)
        }

        func signOut(_ name: String) async throws(ControlAPIError) -> SignedOut {
            try await inner.signOut(name)
        }

        func resetUsage() async throws(ControlAPIError) -> UsageReset {
            try await inner.resetUsage()
        }
    }
#endif
