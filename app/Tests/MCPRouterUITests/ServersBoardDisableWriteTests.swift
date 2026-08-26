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

        /// Oracle 16, the half the test above cannot state. **The mark must be SET while the write
        /// runs**, not merely absent afterwards: `writesInFlight` is inserted before the operation
        /// and removed in a `defer`, so every assertion made after `setDisabled` returns sees an
        /// empty set — and so would a mechanism that never inserted anything. Deleting
        /// `writesInFlight.insert(name)` and the `defer` together left the whole suite green.
        ///
        /// Observed from inside the client's own `patch`, which is the one moment the set state
        /// exists, and paired with the dim it drives: `Applying…` is what the row's action reads
        /// while the mark is held, which is the acceptance line's actual words.
        @MainActor
        @Test("the in-flight mark is set while the write runs, and it dims the row's action")
        func theInFlightMarkIsHeldDuringTheWrite() async throws {
            let client = RecordingClient()
            client.patchResponse = try Self.server()
            let board = Self.board(client)
            let midWrite = MidWriteObservation()

            client.duringPatch = { @Sendable [board] in
                await MainActor.run { midWrite.record(board.writesInFlight) }
            }
            await board.setDisabled("s", to: true)

            #expect(midWrite.observations == [["s"]], "the mark was never set during the write")
            #expect(board.writesInFlight.isEmpty, "the mark outlived the write")

            // What the mark is *for*: the row's action dims in place with a reason, rather than
            // vanishing or accepting a second press. Asserted against the row's own property so
            // the mark and the dimming cannot drift apart.
            let row = try ServerRowModel(server: Self.server(), idleMs: 300_000, pendingAuth: nil)
            #expect(Self.row(row, isWriting: true).disabledReason == ServersBoardModel.applyingReason)
            #expect(Self.row(row, isWriting: false).disabledReason == nil)
        }

        /// Oracle 17. The banner carries the error's own words rather than a second phrasing of the
        /// same failure — two spellings of one condition is how a product starts telling a user two
        /// different things about it.
        ///
        /// **The refusal carries a payload, and that is what makes this assertable.** This test
        /// previously drove the write with `.routerNotRunning`, then compared the recorded error's
        /// `userFacingDescription` to `ControlAPIError.routerNotRunning.userFacingDescription` —
        /// two spellings of one payload-free case, so the comparison was a value against itself and
        /// no implementation could fail it. A `.server(status:message:hint:)` puts the router's own
        /// two sentences on the wire, and the assertion is that both arrive in the rendered text
        /// unrewritten.
        @MainActor
        @Test("a refused enable renders ControlAPIError's own wording, not a new sentence")
        func aRefusedEnableSaysWhatTheErrorSays() async throws {
            let message = "servers.json is held by another writer"
            let hint = "try again once the watcher has finished"
            let client = RecordingClient()
            client.patchFailure = .server(status: 409, message: message, hint: hint)
            let board = Self.board(client)

            await board.setDisabled("s", to: false)

            let recorded = try #require(board.rowErrors["s"], "a refused write left the row silent")
            let rendered = recorded.userFacingDescription
            #expect(rendered.contains(message), "the board dropped the router's own sentence")
            #expect(rendered.contains(hint), "the board dropped the router's next step")
            #expect(rendered.contains("409"), "the board dropped the status the router refused with")
            // And the row renders the same two strings the pane would, rather than a second
            // wording composed for this surface.
            #expect(rendered == "\(recorded.headline). \(recorded.advice)")

            // The control: a *different* refusal renders different words, so the assertions above
            // measure the payload rather than a sentence that happens to contain them.
            let other = RecordingClient()
            other.patchFailure = .server(status: 503, message: "the router is restarting", hint: nil)
            let second = Self.board(other)
            await second.setDisabled("s", to: false)
            let secondText = try #require(second.rowErrors["s"]).userFacingDescription
            #expect(!secondText.contains(message))
            #expect(secondText.contains("the router is restarting"))
        }

        @MainActor
        private static func row(_ model: ServerRowModel, isWriting: Bool) -> ServerRowView {
            ServerRowView(
                row: model, isSelected: false, isWriting: isWriting, canWrite: true,
                error: nil, select: {}, act: { _ in }
            )
        }
    }

    /// A box for a value read on the main actor from inside a `@Sendable` closure.
    ///
    /// Nested types are capped at one level in this repo and a `var` cannot be captured by a
    /// sendable closure, so the observation lands here rather than in a local.
    final class MidWriteObservation: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [Set<String>] = []

        func record(_ marks: Set<String>) {
            lock.withLock { seen.append(marks) }
        }

        var observations: [Set<String>] { lock.withLock { seen } }
    }
#endif
