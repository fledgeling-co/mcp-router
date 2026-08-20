import Foundation

/// A client backed by responses recorded from a real router.
///
/// Its reason to exist is that every UI surface in this product has nine states to get right, and
/// eight of them are difficult to produce on demand against a live router — you cannot easily make
/// a real daemon return a partial index, or drop a stream, or hand back a name too long for its
/// column. A surface tested only against a healthy router is a surface tested in its easiest state.
///
/// Scenarios are **named** rather than assembled by the caller. `FixtureControlAPIClient(.offline)`
/// is a condition a test asks for; a pile of constructor arguments is a condition a test has to
/// build correctly, and one built slightly wrong silently tests something else.
public struct FixtureControlAPIClient: ControlAPIClient {
    /// The conditions a surface has to render: `DESIGN.md` §5's nine states, plus `unauthorized`
    /// — not one of the nine, but the other refusal that replaces a whole screen and so needs its
    /// own recording — and the live stream's three phases.
    public enum Scenario: String, Sendable, CaseIterable {
        /// The ideal, populated case.
        case populated
        /// The router answered and has nothing declared.
        case empty
        /// A request that never returns, for testing the placeholder.
        case loading
        /// Some servers reported their tools; some failed, with a reason.
        case partial
        /// The router refused the operation.
        case error
        /// A write that succeeded.
        case success
        /// The router is not running.
        case offline
        /// Reached, but the token is wrong or rotated away.
        case unauthorized
        /// A server whose name is wider than its column.
        case overflow
        /// A server the router has declared inoperative, with the reason it gives.
        ///
        /// The Disabled state as *data*. A placard is the router's own "this one is off, and here
        /// is why, and here is what to use instead" — which is what a surface dims in place and
        /// explains. A scenario that only named itself disabled would let a surface invent its own
        /// reason, and an invented reason is the thing `DESIGN.md` §6 exists to prevent.
        case disabled
        /// The stream is delivering.
        case streamLive
        /// The stream dropped and is retrying.
        case streamReconnecting
        /// The stream gave up.
        case streamDisconnected
        /// A cleanup proposal whose skill half is not empty.
        ///
        /// Every skill in `populated` is installed on at least one client, and a skill is only
        /// proposed for cleanup when every readable client lacks it — so the Cleanup board in
        /// Debug has always drawn three servers and no skills. Its skill row treatments were
        /// therefore unrenderable in a running build: the `Read first…` substitution a moved
        /// marketplace triggers, the skill-kind `Remove…` the row disables, and the candidacy
        /// reason itself. Unit tests reach them by building a reading directly; nothing could
        /// photograph them. This scenario is the fixture that can, and it is separate from
        /// `populated` rather than added to it because the Skills board publishes a count of
        /// what `populated` holds, and two surfaces should not have to move together.
        case cleanupSkills
    }

    public let scenario: Scenario

    public init(_ scenario: Scenario = .populated) {
        self.scenario = scenario
    }

    // MARK: - Loading the recordings

    /// Fixtures are read from the library's own bundle, so a consumer needs no test resources.
    ///
    /// **Two directories, and the difference is load-bearing.** `Control/Fixtures` holds
    /// *recordings*: bodies captured from a live router by `capture-control-fixtures.sh`, replayed
    /// one file at a time against the running TypeScript reference by
    /// `scripts/acceptance/parity-fixture.sh`, and required to carry a row in
    /// `planning/parity/surface.tsv`. A hand-written file in there is a file the parity harness will
    /// replay and the reference will not reproduce — it would fail a gate that is correct, for a
    /// reason that is not a defect.
    ///
    /// `Control/Authored` holds fixtures written by hand for states a capture cannot easily reach.
    /// Nothing replays them against a reference and nothing claims they are what the router said.
    /// `usage-call-log.json` is the only one, and it exists because the captured call log is a
    /// single record — enough to prove a record survives the wire, and not enough to drive a surface
    /// built out of records.
    public static func fixtureData(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Authored")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        else {
            throw ControlAPIError.malformedResponse(detail: "missing fixture \(name).json")
        }
        return try Data(contentsOf: url)
    }

    public static func decodeFixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: fixtureData(name))
    }

    /// Decode one recording.
    ///
    /// Module-internal rather than `private` so the writes extension in
    /// `FixtureControlAPIClient+Writes.swift` can reach it. Still not `public`: the fixture's
    /// decoding is its own business, and nothing outside this module constructs a recording.
    func decode<T: Decodable>(_ name: String, as type: T.Type) throws(ControlAPIError) -> T {
        do {
            return try Self.decodeFixture(name, as: type)
        } catch let error as ControlAPIError {
            throw error
        } catch {
            throw ControlAPIError.malformedResponse(detail: "fixture \(name): \(error)")
        }
    }

    /// The failure this scenario answers every call with, if it is a failing one.
    private var failure: ControlAPIError? {
        switch scenario {
        case .offline: .routerNotRunning
        case .unauthorized: .unauthorized
        case .error:
            .server(
                status: 422,
                message: "spawn /nonexistent/binary-that-cannot-start ENOENT",
                hint: "retry with ?force=1 to add it anyway"
            )
        default: nil
        }
    }

    func guardFailure() throws(ControlAPIError) {
        if let failure { throw failure }
    }

    // MARK: - Reading

    public func skills() async throws(ControlAPIError) -> SkillsResponse {
        try guardFailure()
        if scenario == .loading { try await Self.forever() }
        switch scenario {
        case .empty:
            return SkillsResponse(skills: [], clients: SkillFixtures.clients)
        case .partial:
            return SkillFixtures.partial()
        case .overflow:
            return SkillsResponse(skills: SkillFixtures.overflow, clients: SkillFixtures.clients)
        case .cleanupSkills:
            return SkillsResponse(
                skills: SkillFixtures.populated + SkillFixtures.uninstalled,
                clients: SkillFixtures.clients
            )
        default:
            return SkillsResponse(skills: SkillFixtures.populated, clients: SkillFixtures.clients)
        }
    }

    public func marketplaces() async throws(ControlAPIError) -> MarketplacesResponse {
        try guardFailure()
        if scenario == .loading { try await Self.forever() }
        if scenario == .empty { return MarketplacesResponse(marketplaces: []) }
        return MarketplacesResponse(marketplaces: SkillFixtures.marketplaces)
    }

    public func servers() async throws(ControlAPIError) -> ServersResponse {
        try guardFailure()
        if scenario == .loading {
            // Never returns. A loading state is the absence of an answer, so the honest way to
            // hold a surface in it is to not answer.
            try await Self.forever()
        }
        // The populated case uses the recording that carries an in-flight authorization, because a
        // surface that only ever sees the quiet shape is a surface that has never rendered the
        // busiest one it will meet.
        var response = try decode("servers-pending-auth", as: ServersResponse.self)
        switch scenario {
        case .empty:
            response.servers = []
            response.pendingAuth = nil
        case .partial:
            response.servers = response.servers.enumerated().map { index, server in
                var copy = server
                if index.isMultiple(of: 2) {
                    copy.indexError = "spawn ENOENT — the command is not on PATH"
                }
                return copy
            }
        case .overflow:
            response.servers = response.servers.map { server in
                var copy = server
                copy.name = "plugin_pixel-plugin_aseprite_headless_render_worker_arm64"
                return copy
            }
        case .disabled:
            // The placarded server is a real recording, so the reason a surface renders is one the
            // router actually served rather than one this double made up.
            let placarded = try decode("server-placarded", as: MCPServer.self)
            response.servers = response.servers.map { $0.name == placarded.name ? placarded : $0 }
        default:
            break
        }
        return response
    }

    public func server(named name: String) async throws(ControlAPIError) -> MCPServer {
        try guardFailure()
        var server = try decode("server-stdio", as: MCPServer.self)
        server.name = name
        return server
    }

    public func usage(
        limit: Int?,
        server: String?,
        cwd: String?
    ) async throws(ControlAPIError) -> UsageResponse {
        try guardFailure()
        if scenario == .loading { try await Self.forever() }
        var response = try decode(Self.usageFixtureName(for: scenario), as: UsageResponse.self)
        // A router that is up with nothing declared has also served nothing, and this scenario used
        // to answer `/usage` with the recording's records regardless — which made the empty call log
        // unreachable through the double, and so made a log surface's empty state untestable. The
        // scenario's own contract is that it is "genuinely empty rather than merely small".
        if scenario == .empty { response.records = [] }
        // The double filters the recording rather than ignoring the arguments. A double that
        // accepts a filter and returns everything lets a surface's test pass while the surface
        // shows the wrong rows against a real router.
        if let server { response.records = response.records.filter { $0.server == server } }
        if let cwd { response.records = response.records.filter { $0.cwd == cwd } }
        if let limit { response.records = Array(response.records.prefix(limit)) }
        return response
    }

    /// Which call-log recording a scenario answers with.
    ///
    /// `usage.json` is a **capture**, written by `scripts/capture-control-fixtures.sh` from a real
    /// router, and it is one record — enough to prove a record survives the wire, which is what it
    /// exists for, and not enough to drive a surface built *out of* records. Hand-editing it would
    /// turn a recording into an invention, so the scenarios that need a log with shape read
    /// `usage-call-log.json` instead: an **authored** fixture, deliberately a separate file so the
    /// two can never be confused for each other.
    ///
    /// What the authored one carries, and why each is there: two attributed sessions and one
    /// unattributed record (the router omits `pid`/`cwd` whenever `lsof` cannot name the caller, and
    /// a surface has to group those rather than drop them), three working directories, cold and warm
    /// calls, two failures with real `err` strings, and one tool name and one server name past any
    /// column's width. Every one of those is a state some surface has to render and could not
    /// otherwise be driven into.
    static func usageFixtureName(for scenario: Scenario) -> String {
        switch scenario {
        case .populated, .cleanupSkills, .overflow, .streamLive, .streamReconnecting, .streamDisconnected:
            "usage-call-log"
        case .empty, .loading, .partial, .error, .success, .offline, .unauthorized, .disabled:
            "usage"
        }
    }

    /// The per-server call summary, per scenario.
    ///
    /// `.empty` returns no servers, keeping `since` from the recording — the router has been
    /// counting since that moment and has nothing to report, which is a different statement from
    /// having no window at all. Cleanup is the surface that reads this, and it proposes servers to
    /// remove on the strength of their call counts; without this branch an empty router offered
    /// four never-used servers to cull, which is the same defect `searchRegistry` carried as
    /// DEF-009. Found by auditing the other reads once that one was fixed, not by a failing test —
    /// so it is recorded as DEF-014 and is not evidence of a case that watched it fail.
    public func usageSummary() async throws(ControlAPIError) -> UsageSummary {
        try guardFailure()
        if scenario == .loading { try await Self.forever() }
        let recorded = try decode("usage-summary", as: UsageSummary.self)
        if scenario == .empty {
            return UsageSummary(since: recorded.since, servers: [])
        }
        return recorded
    }

    public func heldChanges(for name: String) async throws(ControlAPIError) -> HeldChanges {
        try guardFailure()
        // `.populated` is the *interesting* case: a change actually held, carrying an added tool, a
        // removed one, and a description rewritten to hide a zero-width space. A double that only
        // ever reports "nothing pending" cannot exercise the surface it exists for.
        let fixture = scenario == .empty ? "changes-none" : "changes-pending"
        var changes = try decode(fixture, as: HeldChanges.self)
        changes.server = name
        return changes
    }

    /// The registry search, per scenario.
    ///
    /// **`.empty` is built here rather than recorded**, for the reason the `fixtureData` comment
    /// above gives: `registry-search.json` lives in `Control/Fixtures`, so it is a recording that
    /// `parity-fixture.sh` replays against the TypeScript reference and that owes a row in
    /// `planning/parity/surface.tsv`. A second hand-written file beside it would be replayed too,
    /// and the reference would not reproduce it. `skills()` and `marketplaces()` answer `.empty`
    /// the same way, in code.
    ///
    /// Until this branch existed the method ignored the scenario altogether and returned the
    /// three recorded results for every one of the fourteen. That is what made Discover's empty
    /// state unreachable on the phone — `MCPROUTER_SCENARIO=empty` reached the client, the client
    /// answered with a populated catalogue, and the on-glass test read a surface that was
    /// rendering its data correctly from the wrong answer. Registered as DEF-009.
    ///
    /// `sources` is zeroed alongside `results`, because a count of what each index contributed is
    /// a statement about this response: three official entries beside an empty result list would
    /// be the surface's own honesty guardrail reporting a number nothing in view supports.
    public func searchRegistry(
        query _: String,
        limit _: Int
    ) async throws(ControlAPIError) -> RegistrySearchResponse {
        try guardFailure()
        if scenario == .loading { try await Self.forever() }
        if scenario == .empty {
            return RegistrySearchResponse(
                results: [],
                sources: RegistrySources(official: 0, smithery: 0, merged: 0),
                warnings: []
            )
        }
        return try decode("registry-search", as: RegistrySearchResponse.self)
    }

    // MARK: - The stream

    /// The events this scenario's stream produces, ending in its phase.
    public func streamEvents() throws(ControlAPIError) -> [StreamEvent] {
        let backfill: [CallRecord]
        do {
            backfill = try Self.decodeFixture(
                Self.usageFixtureName(for: scenario),
                as: UsageResponse.self
            ).records
        } catch let error as ControlAPIError {
            throw error
        } catch {
            throw ControlAPIError.malformedResponse(detail: "fixture usage: \(error)")
        }

        // **The replayed records must not be the ones the backfill already returned.**
        //
        // They used to be, and the consequence was invisible: `ActivityRecords.prepend` de-duplicates
        // on `CallRecord.id`, and every replayed record shared an id with a record the backfill had
        // just delivered, so **no scenario could produce an arriving record at all**. A surface's
        // insert animation, its capacity-boundary drop and its live half had no runtime path — not
        // a weak test, no path — and an acceptance run could not have exercised them even in
        // principle.
        //
        // So the replay re-stamps them. The timestamp is what makes a call distinct on the wire, and
        // a fresh one is exactly what the router would send for a new call of the same shape.
        let arriving = backfill.prefix(4).enumerated().map { index, record -> CallRecord in
            var fresh = record
            fresh.ts = Self.replayTimestamp(offsetBy: index)
            return fresh
        }

        switch scenario {
        case .streamLive:
            return [.phase(.live)] + arriving.map { .record($0) }
        case .streamReconnecting:
            return [.phase(.live)] + arriving.prefix(2).map { .record($0) } + [.phase(.reconnecting)]
        case .streamDisconnected:
            return [.phase(.live)] + arriving.prefix(2).map { .record($0) }
                + [.phase(.reconnecting), .phase(.disconnected)]
        case .offline, .unauthorized, .error:
            // A router that refuses every request is not delivering a live feed. Reporting `.live`
            // here put "· live" in a surface's subtitle for a router that was not answering at all,
            // which is a fabricated status in the one path a Release build can never take but every
            // acceptance run does.
            return [.phase(.disconnected)]
        case .populated, .cleanupSkills, .empty, .loading, .partial, .success, .overflow, .disabled:
            return [.phase(.live)]
        }
    }

    /// A timestamp for a replayed record, distinct from anything in a recording.
    ///
    /// Dated far enough ahead of the fixtures' own stamps that it cannot collide with one, and
    /// spaced so the replayed records arrive in order.
    private static func replayTimestamp(offsetBy index: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date().addingTimeInterval(Double(index)))
    }

    /// Suspends until cancelled, and then refuses.
    ///
    /// The refusal matters. Falling out of the wait and returning the populated response would mean
    /// a cancelled load quietly delivers data — so a surface that navigated away, or a test that
    /// gave up waiting, would still receive an answer it no longer has anywhere to put.
    private static func forever() async throws(ControlAPIError) -> Never {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
        throw ControlAPIError.transport(detail: "the request was cancelled while loading")
    }
}
