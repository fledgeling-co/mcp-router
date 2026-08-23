#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// The wire values these request tests are driven with.
    ///
    /// Duplicated from `CheckFixtures` rather than shared because that lives in the Kit test target
    /// and Swift test targets do not see each other. Kept deliberately minimal — only the fields
    /// these assertions actually depend on — so the two cannot drift in a way that matters.
    enum M7Fixtures {
        static func server(name: String = "alpha", calls: Int = 5) -> MCPServer {
            MCPServer(
                name: name, transport: .stdio, state: .idle, inFlight: 0, callsServed: calls,
                idleSec: 0, command: "node", args: ["server.js"], cwd: nil, url: nil,
                envKeys: nil, headerKeys: nil, hash: "abc123", tools: 3, toolNames: [],
                indexedAt: "2026-08-01T10:00:00Z", indexError: nil, projects: [], warm: false,
                placard: nil, pendingChange: nil,
                auth: ServerAuth(supported: false, authorized: false),
                usage: ServerUsage(calls: calls, errors: 0)
            )
        }

        static func skill(
            name: String = "pr-summariser",
            presence: [String: SkillPresence] = ["claude": .present],
            provenance: SkillProvenance? = nil
        ) -> Skill {
            Skill(
                name: name, description: "Summarises a pull request", path: "/skills/\(name)",
                source: .plugin(PluginOrigin(
                    plugin: "review-kit", marketplace: "fledgeling", pluginVersion: "0.4.1"
                )),
                presence: presence, held: nil, provenance: provenance
            )
        }

        /// A marketplace that resolves somewhere other than where the router first saw it.
        static func moved(
            firstSeen: String = "github:fledgeling/plugins",
            current: String = "github:pr-tools-collective/plugins"
        ) -> SkillProvenance {
            SkillProvenance(
                firstSeenSource: firstSeen,
                currentSource: current,
                firstSeenAt: "2026-03-14T09:00:00Z"
            )
        }

        static func client(_ id: String) -> SkillClient {
            SkillClient(id: id, displayName: id.capitalized, supportsSkills: true, status: .read)
        }
    }

    /// A client that records **every** call, reads included, so a test can assert what was NOT sent.
    ///
    /// `ServersBoardRecordingClient` records writes only, which is right for the board it was written
    /// for. A14 and A14b are the opposite question — "exactly one `reindex`, and no other write" and
    /// "zero writes at all" — and a double that does not see reads cannot distinguish "nothing else
    /// was sent" from "nothing else was recorded".
    final class M7RecordingClient: ControlAPIClient, @unchecked Sendable {
        /// `@unchecked Sendable` is honest and narrow: every access happens on the test's own task,
        /// and the lock guards the one mutable field regardless.
        private let lock = NSLock()
        private var recorded: [String] = []

        var serversToServe: [MCPServer] = []
        var skillsToServe = SkillsResponse()
        var summaryToServe = UsageSummary(since: "", servers: [])

        /// Set to make the next `servers()` throw. Added for M12, which has to reach
        /// `CleanupBoardModel.LoadState.stale` — the state where a poll failed and the previous
        /// reading is kept — and that state is unreachable against a double that always answers.
        var serversFailure: ControlAPIError?

        /// The same, for `usageSummary()`. It fails independently of `servers()` in the real client
        /// and the board handles it in its own `catch`, so a double that could only fail both at once
        /// would leave the branch that drops the call count untested.
        var summaryFailure: ControlAPIError?

        var calls: [String] {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }

        /// Everything that changes state on the router. A skill re-check must issue none of these.
        var writes: [String] {
            let writeVerbs = [
                "reindex",
                "remove",
                "add",
                "patch",
                "resetUsage",
                "approve",
                "signOut",
                "beginAuth"
            ]
            return calls.filter { call in writeVerbs.contains { call.hasPrefix($0) } }
        }

        private func record(_ entry: String) {
            lock.lock(); defer { lock.unlock() }
            recorded.append(entry)
        }

        func servers() async throws(ControlAPIError) -> ServersResponse {
            record("servers")
            if let serversFailure { throw serversFailure }
            return ServersResponse(
                port: 1,
                idleMs: 300_000,
                since: "",
                pendingAuth: nil,
                servers: serversToServe
            )
        }

        func server(named name: String) async throws(ControlAPIError) -> MCPServer {
            record("server(\(name))")
            guard let match = serversToServe.first(where: { $0.name == name }) else {
                throw ControlAPIError.routerNotRunning
            }
            return match
        }

        func usage(
            limit _: Int?,
            server _: String?,
            cwd _: String?
        ) async throws(ControlAPIError) -> UsageResponse {
            record("usage")
            return UsageResponse(since: "", records: [])
        }

        func usageSummary() async throws(ControlAPIError) -> UsageSummary {
            record("usageSummary")
            if let summaryFailure { throw summaryFailure }
            return summaryToServe
        }

        func heldChanges(for name: String) async throws(ControlAPIError) -> HeldChanges {
            record("heldChanges(\(name))")
            throw .malformedResponse(detail: "this double serves no held changes")
        }

        func searchRegistry(
            query _: String,
            limit _: Int
        ) async throws(ControlAPIError) -> RegistrySearchResponse {
            record("searchRegistry")
            throw .malformedResponse(detail: "this double serves no registry")
        }

        func skills() async throws(ControlAPIError) -> SkillsResponse {
            record("skills")
            return skillsToServe
        }

        func marketplaces() async throws(ControlAPIError) -> MarketplacesResponse {
            record("marketplaces")
            throw .malformedResponse(detail: "this double serves no marketplaces")
        }

        func add(_ server: NewServer, force _: Bool) async throws(ControlAPIError) -> AddedServer {
            record("add(\(server.name))")
            throw .malformedResponse(detail: "this double performs no adds")
        }

        func remove(_ name: String, keepHistory: Bool) async throws(ControlAPIError) -> RemovedServer {
            record("remove(\(name), keepHistory: \(keepHistory))")
            return RemovedServer(removed: name)
        }

        func reindex(_ name: String) async throws(ControlAPIError) -> ReindexResult {
            record("reindex(\(name))")
            return ReindexResult(name: name, tools: 1, error: nil)
        }

        func patch(server name: String, _: ServerPatch) async throws(ControlAPIError) -> MCPServer {
            record("patch(\(name))")
            throw .malformedResponse(detail: "this double performs no patches")
        }

        func approvePendingChange(server name: String) async throws(ControlAPIError) -> ApprovalResult {
            record("approve(\(name))")
            throw .malformedResponse(detail: "this double approves nothing")
        }

        func beginAuthorization(for name: String) async throws(ControlAPIError) -> AuthorizationStart {
            record("beginAuth(\(name))")
            throw .malformedResponse(detail: "this double authorises nothing")
        }

        func signOut(_ name: String) async throws(ControlAPIError) -> SignedOut {
            record("signOut(\(name))")
            throw .malformedResponse(detail: "this double signs nothing out")
        }

        func resetUsage() async throws(ControlAPIError) -> UsageReset {
            record("resetUsage")
            return UsageReset(ok: true, since: "")
        }
    }

    /// A14, A14b and A15b: what each pane's actions actually SEND.
    ///
    /// These are exercised-request assertions rather than string assertions, and the distinction is
    /// the one M5's worst finding turned on — a surface that displayed sanitised values while
    /// sending raw ones passes every copy test in the repository. The only way to catch it is to
    /// look at the request.
    @Suite("M7 — what the panes send")
    struct M7ExercisedRequestTests {
        @MainActor
        private static func scratchStore() throws -> CheckHistoryStore {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("m7-req-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return CheckHistoryStore(directory: directory)
        }

        /// A14: re-checking a server issues exactly one `reindex`, for that server, and no other write.
        @MainActor
        @Test("A14: a server re-check issues exactly one reindex and no other write")
        func serverRecheckIssuesOneReindex() async throws {
            let client = M7RecordingClient()
            client.serversToServe = [M7Fixtures.server(name: "alpha")]
            let board = try EvalsBoardModel(client: client, store: Self.scratchStore())
            await board.load()

            let subject = try #require(board.subjects.first { $0.kind == .server })
            await board.recheck(subject)

            let reindexes = client.calls.filter { $0.hasPrefix("reindex") }
            #expect(reindexes == ["reindex(alpha)"], "sent \(client.calls)")
            #expect(client.writes == ["reindex(alpha)"], "a re-check sent another write: \(client.writes)")
        }

        /// A14b: re-checking a **skill** issues zero writes.
        ///
        /// The control API is read-only for skills, so a skill re-check that wrote anything would be
        /// sending a request the router has no endpoint for — the say/send failure in its purest
        /// form, because the button says "re-check" either way.
        @MainActor
        @Test("A14b: a skill re-check re-reads and writes nothing at all")
        func skillRecheckWritesNothing() async throws {
            let client = M7RecordingClient()
            client.skillsToServe = SkillsResponse(
                skills: [M7Fixtures.skill(name: "pr-summariser")],
                clients: [M7Fixtures.client("claude")]
            )
            let board = try EvalsBoardModel(client: client, store: Self.scratchStore())
            await board.load()

            let subject = try #require(board.subjects.first { $0.kind == .skill })
            let before = client.calls.count
            await board.recheck(subject)

            #expect(client.writes.isEmpty, "a skill re-check wrote to the router: \(client.writes)")
            // And it did re-read, so this is not passing because nothing happened at all.
            let after = client.calls.dropFirst(before)
            #expect(after.contains("skills"), "a skill re-check did not re-read skills: \(Array(after))")
        }

        /// A15b: the reset dialog issues `resetUsage` only when confirmed, and cancelling sends nothing.
        @MainActor
        @Test("A15b: cancelling the reset dialog issues no request")
        func cancellingResetSendsNothing() async {
            let client = M7RecordingClient()
            client.serversToServe = [M7Fixtures.server(name: "alpha", calls: 0)]
            let board = CleanupBoardModel(client: client)
            await board.load()

            board.sheet = .resetHistory
            #expect(!client.calls.contains("resetUsage"), "opening the dialog already reset the history")

            board.sheet = nil
            #expect(!client.calls.contains("resetUsage"), "cancelling the dialog reset the history anyway")

            // And confirming does send it, so the assertions above are about the guard rather than
            // about a model that cannot reset at all.
            await board.resetHistory()
            #expect(client.calls.contains("resetUsage"), "confirming the dialog sent no reset")
        }

        /// The removal sends the toggle the user actually saw, in both positions.
        ///
        /// A dialog whose "Keep its recorded calls" switch did not reach the request would be
        /// destroying history the user asked to keep, while showing them a control that appeared to
        /// work. Both positions are asserted because a hardcoded `false` passes a one-sided test.
        @MainActor
        @Test("a removal sends the keepHistory the dialog showed, in both positions")
        func removalSendsTheToggleItShowed() async {
            for keepHistory in [true, false] {
                let client = M7RecordingClient()
                client.serversToServe = [M7Fixtures.server(name: "alpha", calls: 0)]
                let board = CleanupBoardModel(client: client)
                await board.load()

                await board.remove("alpha", keepHistory: keepHistory)
                #expect(
                    client.calls.contains("remove(alpha, keepHistory: \(keepHistory))"),
                    "the request did not carry keepHistory: \(keepHistory) — sent \(client.calls)"
                )
            }
        }
    }
#endif
