#if os(macOS)
    import Foundation
    import Testing

    // `@testable` for the Kit as well, so the wire types' memberwise initialisers are reachable.
    // They are `Codable` structs with no hand-written `public init`, so from another module the only
    // way to build one is to decode it — and a stub that had to keep a JSON fixture per response
    // would be testing the fixtures rather than the board.
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// What the Servers board actually sends.
    ///
    /// These assert on the **recorded request**, and where a body is involved on the **encoded
    /// bytes**, because that is the only place the guarantees this product makes are visible. A test
    /// that inspected a `ServerPatch` value would prove what the Swift type holds and nothing about
    /// what leaves the machine — `SWIFT_PRACTICES.md` §2 names that exact gap, since a computed
    /// property or a `CodingKeys` mapping can put a key on the wire that no stored property shows.
    @Suite("Servers board — what it sends")
    struct ServersBoardWriteTests {
        typealias RecordingClient = ServersBoardRecordingClient
        typealias Recorded = ServersBoardRecordingClient.Recorded

        @MainActor
        static func board(
            _ client: RecordingClient,
            opened: @escaping @MainActor (String) -> Void = { _ in }
        ) -> ServersBoardModel {
            ServersBoardModel(
                client: client,
                tracker: ServerStateTracker(client: client, stream: nil),
                openURL: opened,
                chooseDirectory: { "/tmp/project" }
            )
        }

        static func server(
            name: String = "s",
            placard: Placard? = nil,
            indexError: String? = nil,
            envKeys: [String]? = nil,
            headerKeys: [String]? = nil
        ) throws -> MCPServer {
            var s = try FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)
            s.name = name
            s.placard = placard
            s.indexError = indexError
            s.envKeys = envKeys
            s.headerKeys = headerKeys
            return s
        }

        // MARK: - A11 · Reset picks the operation that clears the mark

        @MainActor
        @Test("A11 — a server tripped by a failed index is re-indexed, not patched")
        func resetReindexesAnIndexFailure() async throws {
            let client = RecordingClient()
            let board = Self.board(client)
            let tripped = try Self.server(
                placard: Placard(reason: "spawn ENOENT", substitute: nil, until: nil),
                indexError: "spawn ENOENT"
            )
            await board.reset(tripped)
            #expect(client.calls.map(\.operation) == ["reindex"])
        }

        @MainActor
        @Test("A11 — a user placard is cleared with an explicit JSON null")
        func resetClearsAUserPlacard() async throws {
            let client = RecordingClient()
            client.patchResponse = try Self.server()
            let board = Self.board(client)
            let placarded = try Self.server(
                placard: Placard(reason: "under maintenance", substitute: nil, until: nil)
            )
            await board.reset(placarded)

            let call = try #require(client.calls.first)
            #expect(call.operation == "patch")
            // `encodeNil` is the only thing that produces this, and the synthesised encoder never
            // emits one — an omitted key would leave the mark alone and the reset would silently do
            // nothing at all.
            #expect(call.body == #"{"placard":null}"#)
        }

        @MainActor
        @Test("A11 — a re-index that fails again is reported against the row, not treated as success")
        func reindexFailureIsSurfaced() async throws {
            let client = RecordingClient()
            client.reindexError = "spawn ENOENT"
            let board = Self.board(client)
            let tripped = try Self.server(
                name: "broken",
                placard: Placard(reason: "spawn ENOENT", substitute: nil, until: nil),
                indexError: "spawn ENOENT"
            )
            await board.reset(tripped)
            #expect(board.rowErrors["broken"] != nil)
            #expect(board.writesInFlight.isEmpty, "the in-flight mark outlived the failed write")
        }

        // MARK: - A12 · the two Behaviour writes send exactly their own key

        @MainActor
        @Test("A12 — Keep warm sends exactly {\"warm\":…} and nothing else")
        func warmSendsOnlyWarm() async throws {
            let client = RecordingClient()
            client.patchResponse = try Self.server()
            let board = Self.board(client)
            await board.setWarm("s", to: true)
            #expect(client.calls.first?.body == #"{"warm":true}"#)

            await board.setWarm("s", to: false)
            #expect(client.calls.last?.body == #"{"warm":false}"#)
        }

        @MainActor
        @Test("A12 — scoping sends the array explicitly in both directions")
        func projectsSendsAnExplicitArray() async throws {
            let client = RecordingClient()
            client.patchResponse = try Self.server()
            let board = Self.board(client)
            await board.setProjects("s", to: ["~/Dev/mcp-router"])
            #expect(client.calls.first?.body == #"{"projects":["~\/Dev\/mcp-router"]}"#)

            // Clearing is an empty array, never an omitted key: omitting it leaves the restriction
            // in place, so a toggle that omitted would appear to turn off and change nothing.
            await board.setProjects("s", to: [])
            #expect(client.calls.last?.body == #"{"projects":[]}"#)
        }

        // MARK: - A13 · the command-line guarantee, against the bytes

        /// **Narrowed, deliberately, and the narrowing is the finding.**
        ///
        /// An earlier draft of this clause claimed no control on this surface could put `command`,
        /// `args` or `env` on the wire. That is false and could not be made true: `Add server…` is on
        /// this surface and issues `add(NewServer)`, and `NewServer` carries all three by design —
        /// `Models.swift` states it is "the **only** type in the client that carries `command`, `args`
        /// and `env`… Adding a server is an explicit act with its own surface."
        ///
        /// The guarantee that is real, and the one `SWIFT_PRACTICES.md` §2 actually states, is about
        /// **PATCH**: editing an existing server can never become installing one, because the patch
        /// type has no such field. Both halves are asserted below so the true claim is checked and
        /// the false one cannot be reintroduced as a comforting green test.
        @MainActor
        @Test("A13 — no PATCH the board can issue carries a command line")
        func noPatchCarriesACommandLine() async throws {
            let client = RecordingClient()
            client.patchResponse = try Self.server()
            let board = Self.board(client)

            await board.setWarm("s", to: true)
            await board.setProjects("s", to: ["/tmp"])
            try await board.reset(
                Self.server(placard: Placard(reason: "x", substitute: nil, until: nil))
            )

            let patches = client.calls.filter { $0.operation == "patch" }
            #expect(patches.count == 3, "a patch path was added that this test does not cover")
            for patch in patches {
                let body = try #require(patch.body)
                for forbidden in ServerPatch.forbiddenWireKeys {
                    #expect(!body.contains("\"\(forbidden)\""), "a patch put \(forbidden) on the wire")
                }
            }
        }

        @MainActor
        @Test("A13 — adding a server does carry one, which is the act that is allowed to")
        func addCarriesACommandLineByDesign() async throws {
            let client = RecordingClient()
            let board = Self.board(client)
            await board.add(NewServer(name: "new", command: "npx", args: ["-y", "@me/x"]))
            let body = try #require(client.calls.first?.body)
            #expect(body.contains("\"command\""))
            // And it is a separate type from `ServerPatch`, so no future field can widen a patch
            // into an installer — there is no shared shape to widen.
            #expect(!ServerPatch.permittedWireKeys.contains("command"))
        }

        // MARK: - A14 · the router's own advice

        @MainActor
        @Test("A14 — a refusal carrying a hint offers Add it anyway, and one without does not")
        func hintEnablesForce() async {
            let client = RecordingClient()
            client.addFailure = .server(
                status: 409, message: "it failed to start",
                hint: "retry with ?force=1 to add it anyway"
            )
            let board = Self.board(client)
            await board.add(NewServer(name: "new", command: "npx"))
            #expect(board.addCanForce)
            #expect(board.addFailure?.advice.contains("force=1") == true)

            await board.add(NewServer(name: "new", command: "npx"), force: true)
            #expect(client.calls.map(\.operation).contains("add(force)"))

            // A refusal with no hint offers nothing, because forcing is the router's suggestion and
            // not this app's guess.
            let quiet = RecordingClient()
            quiet.addFailure = .server(status: 500, message: "no", hint: nil)
            let second = Self.board(quiet)
            await second.add(NewServer(name: "x", command: "y"))
            #expect(!second.addCanForce)
        }

        // MARK: - A15, A16 · removal

        @MainActor
        @Test("A15 — the history checkbox reaches the request")
        func removeSendsKeepHistory() async {
            let client = RecordingClient()
            let board = Self.board(client)
            await board.remove("s", keepHistory: true)
            #expect(client.calls.first?.operation == "remove(keepHistory)")

            await board.remove("s", keepHistory: false)
            #expect(client.calls.last?.operation == "remove")
        }

        @MainActor
        @Test("A16 — the named consequence branches on whether the app could put the entry back")
        func removeConsequenceBranches() {
            let withSecrets = ServersBoardModel.removeConsequence(
                envKeys: ["API_KEY", "TOKEN"], headerKeys: nil
            )
            #expect(withSecrets.contains("2 values are set"))
            #expect(withSecrets.contains("cannot put this back"))

            let one = ServersBoardModel.removeConsequence(envKeys: ["API_KEY"], headerKeys: nil)
            #expect(one.contains("1 value is set"))

            let clean = ServersBoardModel.removeConsequence(envKeys: [], headerKeys: [])
            #expect(clean.contains("restores it exactly"))
            #expect(!clean.contains("cannot put this back"))
        }

        // MARK: - A17 · accept writes, keeping does not

        @MainActor
        @Test("A17 — accepting approves; keeping the old text sends nothing at all")
        func approveWritesAndKeepingDoesNot() async {
            let client = RecordingClient()
            let board = Self.board(client)
            await board.approveHeldChange("fetch-pro")
            #expect(client.calls.map(\.operation) == ["approve"])

            // "Keep serving the old text" closes the sheet. The router is already serving the
            // approved text and the change stays held, so a request would be describing an action
            // that does not happen.
            let quiet = RecordingClient()
            let second = Self.board(quiet)
            second.sheet = .heldChange(server: "fetch-pro")
            second.escape()
            #expect(second.sheet == nil)
            #expect(quiet.calls.isEmpty, "closing the sheet sent a request")
        }

        // MARK: - A18 · authorisation

        @MainActor
        @Test("A18 — signing in begins the flow and opens the URL the router returned")
        func signInOpensTheRoutersURL() async {
            let client = RecordingClient()
            var opened: [String] = []
            let board = Self.board(client) { opened.append($0) }
            await board.beginAuthorization("fetch-pro")
            #expect(client.calls.map(\.operation) == ["auth"])
            #expect(opened == ["https://auth.example/go"])
        }

        @MainActor
        @Test("reopening a pending page opens it without beginning a second authorisation")
        func reopenDoesNotBeginASecondFlow() {
            let client = RecordingClient()
            var opened: [String] = []
            let board = Self.board(client) { opened.append($0) }
            board.reopenAuthorizationPage("https://auth.example/existing")
            #expect(opened == ["https://auth.example/existing"])
            #expect(client.calls.isEmpty)
        }

        @MainActor
        @Test("signing out discards the stored credentials")
        func signOutIsReachable() async {
            let client = RecordingClient()
            let board = Self.board(client)
            await board.signOut("fetch-pro")
            #expect(client.calls.map(\.operation) == ["signOut"])
        }
    }
#endif
