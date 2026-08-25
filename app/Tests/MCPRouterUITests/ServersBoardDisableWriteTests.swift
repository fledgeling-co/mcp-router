#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// M29 — what the board sends when a server is switched off, and what it says when that fails.
    ///
    /// A separate file from `ServersBoardWriteTests` because that one is already near the
    /// file-length limit, and for the reason it gives itself: these assert on the **encoded bytes**
    /// rather than on a `ServerPatch` value, since a computed property or a `CodingKeys` mapping can
    /// put a key on the wire that no stored property shows.
    ///
    /// Oracle lines 6, 7 (wire half), 16 and 17 of `planning/specs/spec-M29.md`.
    @Suite("Servers board — the switch")
    struct ServersBoardDisableWriteTests {
        typealias RecordingClient = ServersBoardRecordingClient

        @MainActor
        private static func board(_ client: RecordingClient) -> ServersBoardModel {
            ServersBoardModel(
                client: client,
                tracker: ServerStateTracker(client: client, stream: nil),
                openURL: { _ in },
                chooseDirectory: { "/tmp/project" }
            )
        }

        private static func server(name: String = "s", disabled: Bool = false) throws -> MCPServer {
            var s = try FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)
            s.name = name
            s.disabled = disabled
            return s
        }

        @MainActor
        @Test("the switch sends exactly {\"disabled\":…} and nothing else, in both directions")
        func disableSendsOnlyDisabled() async throws {
            let client = RecordingClient()
            client.patchResponse = try Self.server()
            let board = Self.board(client)

            await board.setDisabled("s", to: true)
            #expect(client.calls.first?.body == #"{"disabled":true}"#)
            #expect(client.calls.first?.operation == "patch")

            // Explicit `false` rather than an omitted key. Omitting would leave the server switched
            // off while the row reported that it had been turned back on.
            await board.setDisabled("s", to: false)
            #expect(client.calls.last?.body == #"{"disabled":false}"#)
        }

        /// The row action is the only way back, so it has to send the write that reverses the sheet.
        @MainActor
        @Test("the row's Enable action switches the server back on")
        func enableRoutesToTheWrite() async throws {
            let client = RecordingClient()
            client.patchResponse = try Self.server()
            let board = Self.board(client)
            let off = try Self.server(disabled: true)

            let action = try #require(ServerRowAction.forServer(off, pendingAuth: nil))
            await board.perform(action, on: off)

            #expect(client.calls.map(\.operation) == ["patch"])
            #expect(client.calls.first?.body == #"{"disabled":false}"#)
        }

        /// Oracle 16. The row never disappears and the mark never outlives the write — a mark left
        /// behind would dim the action permanently and strand the only way back.
        @MainActor
        @Test("the in-flight mark is cleared when the write finishes, both ways")
        func theInFlightMarkDoesNotOutliveTheWrite() async throws {
            let client = RecordingClient()
            client.patchResponse = try Self.server()
            let board = Self.board(client)

            await board.setDisabled("s", to: true)
            #expect(board.writesInFlight.isEmpty, "the mark outlived a write that succeeded")

            client.patchResponse = nil // the next patch throws
            await board.setDisabled("s", to: false)
            #expect(board.writesInFlight.isEmpty, "the mark outlived a write that failed")
        }

        /// Oracle 17. The banner carries the error's own words rather than a second phrasing of the
        /// same failure — two spellings of one condition is how a product starts telling a user two
        /// different things about it.
        @MainActor
        @Test("a refused enable renders ControlAPIError's own wording, not a new sentence")
        func aRefusedEnableSaysWhatTheErrorSays() async throws {
            let client = RecordingClient()
            client.patchResponse = nil
            let board = Self.board(client)

            await board.setDisabled("s", to: false)

            let recorded = try #require(board.rowErrors["s"], "a refused write left the row silent")
            #expect(recorded == .routerNotRunning)
            #expect(
                recorded.userFacingDescription
                    == ControlAPIError.routerNotRunning.userFacingDescription,
                "the board re-worded the error rather than passing it through"
            )
        }
    }
#endif
