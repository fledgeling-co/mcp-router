#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// What the board does with the router's answer — a failure reported against its row, the write
    /// gate the keyboard shares, and the success that has to be visible without anything being
    /// guessed. Split from `ServersBoardWriteTests`, which owns what goes out.
    @Suite("Servers board — what it does with the answer")
    struct ServersBoardOutcomeTests {
        typealias RecordingClient = ServersBoardRecordingClient

        @MainActor
        static func board(_ client: RecordingClient) -> ServersBoardModel {
            ServersBoardModel(client: client, tracker: ServerStateTracker(client: client, stream: nil))
        }

        static func server(name: String = "s") throws -> MCPServer {
            var s = try FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)
            s.name = name
            return s
        }

        // MARK: - Failure is reported, never swallowed

        @MainActor
        @Test("a failed write lands against its row and clears the in-flight mark")
        func failedWriteIsReportedAgainstTheRow() async {
            // No `patchResponse`, so the stub refuses exactly as an unreachable router would.
            let client = RecordingClient()
            let board = Self.board(client)
            await board.setWarm("s", to: true)
            #expect(board.rowErrors["s"] == .routerNotRunning)
            #expect(board.writesInFlight.isEmpty)
        }

        // MARK: - The write gate the keyboard shares

        @MainActor
        @Test("A29 — writes are refused while the router is not answering")
        func writesAreGatedOnTheLoad() {
            let board = Self.board(RecordingClient())
            let loaded = ServerStateTracker.TrackerState(load: .loaded([]), stream: .notConfigured)
            let stale = ServerStateTracker.TrackerState(
                load: .stale([], .routerNotRunning), stream: .notConfigured
            )
            let failed = ServerStateTracker.TrackerState(
                load: .failed(.routerNotRunning), stream: .notConfigured
            )
            let loading = ServerStateTracker.TrackerState(load: .loading, stream: .notConfigured)

            // The gate `Space` and the Keep-warm toggle share, so the key cannot write where the
            // control it mirrors would be dimmed.
            #expect(board.canWrite(to: loaded))
            #expect(!board.canWrite(to: stale))
            #expect(!board.canWrite(to: failed))
            #expect(!board.canWrite(to: loading))
        }

        // MARK: - Success is the router's own answer, applied in place

        @MainActor
        @Test("a successful patch is reflected from the server the router returned")
        func successAppliesTheRoutersAnswer() async throws {
            let client = RecordingClient()
            var updated = try Self.server(name: "obscura")
            updated.warm = true
            client.patchResponse = updated

            let tracker = ServerStateTracker(client: client, stream: nil)
            let board = ServersBoardModel(client: client, tracker: tracker)

            // The tracker has to know the server before a write response can correct it — a write
            // reply is not licence to conjure a row.
            var before = try Self.server(name: "obscura")
            before.warm = false
            await tracker.apply(
                poll: ServersResponse(
                    port: 1, idleMs: 300_000, since: "", pendingAuth: nil, servers: [before]
                )
            )
            #expect(await tracker.state().servers.first?.warm == false)

            await board.setWarm("obscura", to: true)
            #expect(
                await tracker.state().servers.first?.warm == true,
                "the router's own answer did not reach the surface, so a success is invisible"
            )
        }

        @MainActor
        @Test("a write response for a server the poll never listed is ignored")
        func unknownServerIsNotConjured() async throws {
            let client = RecordingClient()
            let tracker = ServerStateTracker(client: client, stream: nil)
            await tracker.apply(
                poll: ServersResponse(port: 1, idleMs: 1, since: "", pendingAuth: nil, servers: [])
            )
            try await tracker.apply(updated: Self.server(name: "ghost"))
            #expect(await tracker.state().servers.isEmpty)
        }
    }
#endif
