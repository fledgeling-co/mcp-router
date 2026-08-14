import Foundation
import Testing
@testable import MCPRouterKit

/// The merge that stands in for a running-state feed the router does not publish, and — since F4 —
/// what it reports when a source fails.
///
/// Worth restating, because it is the thing most likely to be "fixed" later by someone who assumes
/// a subscription exists: the router answers `GET /servers` with a snapshot and streams call
/// records on `/usage/stream`. Those two are the whole of what it observes. Anything a surface
/// shows beyond them would be invented, and inventing state is exactly what `DESIGN.md` §6 forbids.
///
/// **On the failure tests below.** Several drive the real `pollLoop()` through `run()` rather than
/// calling `apply(pollFailure:)` directly. That distinction is the whole point: the original defect
/// was `if let response = try? await client.servers()`, which discards every typed error. A test
/// that calls `apply(pollFailure:)` by hand passes perfectly well against that defect, because it
/// never goes near the loop that drops the error. Only a test that makes a real poll fail can
/// observe it, so those are marked ‹real loop› and are the ones that die if `try?` comes back —
/// mechanised permanently as mutant `M40` in `scripts/red-green.py`.
@Suite("Live server state")
struct ServerStateTrackerTests {
    private func server(_ name: String, state: ServerState = .idle) throws -> MCPServer {
        var decoded = try FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)
        decoded.name = name
        decoded.state = state
        return decoded
    }

    private func response(_ servers: [MCPServer]) -> ServersResponse {
        ServersResponse(port: 8879, idleMs: 300_000, since: "2026-08-14T00:00:00.000Z", servers: servers)
    }

    private func record(for server: String) -> CallRecord {
        CallRecord(
            ts: "2026-08-14T00:00:01.000Z", server: server, tool: "t",
            ok: true, ms: 4, cold: false
        )
    }

    // MARK: - Test doubles for driving the real loop

    /// Allows `steps` poll intervals to elapse instantly, then parks until cancelled.
    ///
    /// `RecordingStreamClock` returns immediately forever, which spins the loop as fast as the
    /// actor can schedule it. Stepping gives a known number of real polls per `run()`, so a
    /// success-then-failure sequence is deterministic rather than a race the test hopes to win.
    actor SteppingClock: StreamClock {
        private var remaining: Int
        init(steps: Int) { self.remaining = steps }
        func sleep(for duration: Duration) async throws {
            if remaining > 0 {
                remaining -= 1
                return
            }
            try await Task.sleep(for: .seconds(3600))
        }
    }

    /// Serves a scripted sequence of `servers()` outcomes, repeating the last once exhausted.
    ///
    /// Everything other than `servers()` delegates to the populated fixture and is never exercised
    /// here — the poll loop calls exactly one endpoint, and that is the one being scripted.
    actor ScriptedControlAPIClient: ControlAPIClient {
        private let script: [Result<ServersResponse, ControlAPIError>]
        private var index = 0
        private let rest = FixtureControlAPIClient(.populated)

        init(_ script: [Result<ServersResponse, ControlAPIError>]) {
            self.script = script
        }

        /// How many polls actually reached the client. Proves the loop ran, rather than the state
        /// happening to look right.
        func pollCount() -> Int { index }

        func servers() async throws(ControlAPIError) -> ServersResponse {
            let entry = script[min(index, script.count - 1)]
            index += 1
            switch entry {
            case let .success(response): return response
            case let .failure(error): throw error
            }
        }

        func server(named name: String) async throws(ControlAPIError) -> MCPServer {
            try await rest.server(named: name)
        }

        func usage(limit: Int?, server: String?, cwd: String?) async throws(ControlAPIError) -> UsageResponse {
            try await rest.usage(limit: limit, server: server, cwd: cwd)
        }

        func usageSummary() async throws(ControlAPIError) -> UsageSummary {
            try await rest.usageSummary()
        }

        func heldChanges(for name: String) async throws(ControlAPIError) -> HeldChanges {
            try await rest.heldChanges(for: name)
        }

        func searchRegistry(query: String, limit: Int) async throws(ControlAPIError) -> RegistrySearchResponse {
            try await rest.searchRegistry(query: query, limit: limit)
        }

        func add(_ server: NewServer, force: Bool) async throws(ControlAPIError) -> AddedServer {
            try await rest.add(server, force: force)
        }

        func remove(_ name: String, keepHistory: Bool) async throws(ControlAPIError) -> RemovedServer {
            try await rest.remove(name, keepHistory: keepHistory)
        }

        func reindex(_ name: String) async throws(ControlAPIError) -> ReindexResult {
            try await rest.reindex(name)
        }

        func patch(server name: String, _ patch: ServerPatch) async throws(ControlAPIError) -> MCPServer {
            try await rest.patch(server: name, patch)
        }

        func approvePendingChange(server name: String) async throws(ControlAPIError) -> ApprovalResult {
            try await rest.approvePendingChange(server: name)
        }

        func beginAuthorization(for name: String) async throws(ControlAPIError) -> AuthorizationStart {
            try await rest.beginAuthorization(for: name)
        }

        func signOut(_ name: String) async throws(ControlAPIError) -> SignedOut {
            try await rest.signOut(name)
        }

        func resetUsage() async throws(ControlAPIError) -> UsageReset {
            try await rest.resetUsage()
        }
    }

    /// Runs the tracker's real loop until `predicate` holds or the budget expires, then cancels.
    ///
    /// Returns the state that satisfied the predicate, or the last one seen — so a failure message
    /// can say what it actually settled on rather than only that it timed out.
    @discardableResult
    private func runLoop(
        _ tracker: ServerStateTracker,
        until predicate: @Sendable (ServerStateTracker.TrackerState) -> Bool
    ) async throws -> ServerStateTracker.TrackerState {
        let running = Task { await tracker.run() }
        defer { running.cancel() }

        var latest = await tracker.state()
        for _ in 0 ..< 400 {
            latest = await tracker.state()
            if predicate(latest) { return latest }
            try await Task.sleep(for: .milliseconds(5))
        }
        return latest
    }

    // MARK: - The merge (unchanged behaviour, carried through the reshaped state)

    @Test("a call record marks an idle server running, until a poll says otherwise")
    func aCallCorrectsTheSnapshot() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        let idle = try server("alpha", state: .idle)

        await tracker.apply(poll: response([idle]))
        var state = await tracker.state()
        #expect(state.servers.first?.state == .idle)

        // A call is proof the server was running at that moment — the one correction the stream
        // can make between polls.
        await tracker.apply(record: record(for: "alpha"))
        state = await tracker.state()
        #expect(state.servers.first?.state == .running, "an arriving call did not correct the snapshot")

        // And the poll is authoritative again: it is the only thing that can move a server back.
        try await tracker.apply(poll: response([server("alpha", state: .idle)]))
        state = await tracker.state()
        #expect(state.servers.first?.state == .idle, "the poll must be able to contradict the stream")
    }

    /// The rule that keeps the merge honest. A record naming something the router never declared
    /// would otherwise conjure a row for a server that does not exist.
    @Test("a call record for a server the router never listed invents nothing")
    func unknownServersAreNotInvented() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        try await tracker.apply(poll: response([server("alpha", state: .idle)]))

        await tracker.apply(record: record(for: "ghost"))

        let state = await tracker.state()
        #expect(state.servers.count == 1, "a row was invented for a server no source reported")
        #expect(state.servers.first?.name == "alpha")
        #expect(
            state.servers.first?.state == .idle,
            "a record for an unlisted server changed a server that was listed"
        )
    }

    @Test("a poll removing a server removes it, rather than leaving a stale row behind")
    func pollIsAuthoritativeAboutMembership() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        try await tracker.apply(poll: response([server("alpha"), server("beta")]))
        #expect(await tracker.state().servers.count == 2)

        try await tracker.apply(poll: response([server("alpha")]))
        let state = await tracker.state()
        #expect(state.servers.map(\.name) == ["alpha"])
    }

    @Test("the router's own ordering is preserved rather than re-sorted")
    func orderComesFromTheRouter() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        try await tracker.apply(poll: response([server("zebra"), server("alpha"), server("mid")]))
        #expect(await tracker.state().servers.map(\.name) == ["zebra", "alpha", "mid"])
    }

    /// The precedence rule, stated on the type and asserted here.
    ///
    /// A record that arrives while a poll is in flight does not survive that poll's response. The
    /// poll describes the whole world at the moment the router answered; the record describes one
    /// server at one instant, and the instant is the earlier one.
    @Test("a completed poll overrides a record that arrived while it was in flight")
    func aCompletedPollOutranksAnInFlightRecord() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        try await tracker.apply(poll: response([server("alpha", state: .idle)]))

        // The record lands first, as it would while the next poll is still on the wire.
        await tracker.apply(record: record(for: "alpha"))
        #expect(await tracker.state().servers.first?.state == .running)

        // The response then arrives, still describing the server as idle.
        try await tracker.apply(poll: response([server("alpha", state: .idle)]))
        #expect(
            await tracker.state().servers.first?.state == .idle,
            "a record that predates the poll response outlived it"
        )
    }

    @Test("subscribers see the merged state as it changes")
    func updatesArePublished() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        let updates = await tracker.updates()

        let collector = Task { () -> [Int] in
            var seen: [Int] = []
            for await state in updates {
                seen.append(state.servers.count)
                if seen.count == 3 { break }
            }
            return seen
        }

        // No sleep before publishing: registration is synchronous inside `updates()`, so the
        // subscriber already exists. A sleep here would hide a regression rather than prevent one.
        try await tracker.apply(poll: response([server("alpha")]))
        try await tracker.apply(poll: response([server("alpha"), server("beta")]))

        let counts = await collector.value
        #expect(counts.count == 3, "expected the initial state and two updates, saw \(counts)")
        #expect(counts.last == 2)
    }

    /// Registration is synchronous, so nothing published after `updates()` returns can be missed.
    @Test("a state published immediately after subscribing is delivered")
    func subscriptionIsRegisteredBeforeUpdatesReturns() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        let updates = await tracker.updates()

        // Publish with no delay whatsoever. If registration were deferred into a Task, this update
        // would land before the subscriber existed and the collector would hang on the initial
        // value alone.
        try await tracker.apply(poll: response([server("alpha")]))

        let collector = Task { () -> Int? in
            for await state in updates where !state.servers.isEmpty {
                return state.servers.count
            }
            return nil
        }
        #expect(await collector.value == 1, "an update published right after subscribing was lost")
    }

    // MARK: - A4, A5 — the healthy states, and telling empty from unloaded

    @Test("a tracker that has not polled is loading, not loaded-and-empty")
    func loadingIsDistinctFromEmpty() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        #expect(await tracker.state().load == .loading, "a fresh tracker claimed to have loaded")

        // A successful poll that returns nothing is the genuine Empty state — a *successful* read
        // that found no servers. If emptiness alone meant "not loaded", a fresh router with none
        // declared would render as a failure, which is the silent-empty shape SWIFT_PRACTICES §2
        // names as the worst available.
        await tracker.apply(poll: response([]))
        let state = await tracker.state()
        #expect(state.load == .loaded([]), "an empty successful poll was not treated as loaded")
        #expect(state.servers.isEmpty)
        #expect(state.load != .loading)
    }

    @Test("a successful poll is loaded, in the router's order")
    func successfulPollIsLoaded() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        let expected = try [server("zebra"), server("alpha")]
        try await tracker.apply(poll: response([server("zebra"), server("alpha")]))
        let state = await tracker.state()
        #expect(state.load == .loaded(expected))
        #expect(state.servers.map(\.name) == ["zebra", "alpha"])
    }

    /// The brief's "healthy live state", named rather than assumed.
    ///
    /// `.loaded` alone does not mean healthy-live: loaded data behind a dropped stream is a
    /// different condition with different chrome, and a criterion that accepts `.loaded` regardless
    /// of the stream would pass for all three. The three shapes are asserted distinct so a surface
    /// has to choose between them deliberately.
    @Test("healthy-live, healthy polling-only and loaded-with-a-dead-stream are three states")
    func healthyLiveIsAJointClassification() async throws {
        let one = try [server("alpha")]

        let healthyStreaming = ServerStateTracker.TrackerState(load: .loaded(one), stream: .phase(.live))
        let healthyPollingOnly = ServerStateTracker.TrackerState(load: .loaded(one), stream: .notConfigured)
        let loadedStreamDown = ServerStateTracker.TrackerState(
            load: .loaded(one), stream: .phase(.disconnected)
        )

        #expect(healthyStreaming != healthyPollingOnly)
        #expect(healthyStreaming != loadedStreamDown)
        #expect(healthyPollingOnly != loadedStreamDown)

        // And the one the brief calls healthy live: fresh data AND a stream delivering it.
        #expect(healthyStreaming.load == .loaded(one))
        #expect(healthyStreaming.stream == .phase(.live))
    }

    // MARK: - A1, A2 — the failure states, through the real loop

    @Test("‹real loop› a router that is not running is reported, not retried in silence")
    func pollLoopReportsRouterNotRunning() async throws {
        let tracker = ServerStateTracker(
            client: FixtureControlAPIClient(.offline),
            pollInterval: .milliseconds(1),
            clock: SteppingClock(steps: 0)
        )

        let state = try await runLoop(tracker) { $0.load != .loading }

        #expect(
            state.load == .failed(.routerNotRunning),
            "the poll loop did not surface a typed error — it settled on \(state.load)"
        )
        #expect(state.servers.isEmpty, "a failure with nothing behind it showed rows")
    }

    @Test("‹real loop› an unauthorized token stays unauthorized, and is not flattened into “an error”")
    func pollLoopReportsUnauthorizedDistinctly() async throws {
        let tracker = ServerStateTracker(
            client: FixtureControlAPIClient(.unauthorized),
            pollInterval: .milliseconds(1),
            clock: SteppingClock(steps: 0)
        )

        let state = try await runLoop(tracker) { $0.load != .loading }

        #expect(state.load == .failed(.unauthorized), "settled on \(state.load)")
        // The distinction F3 went to trouble to draw, asserted at the one place that consumes it.
        #expect(
            state.load != .failed(.routerNotRunning),
            "unauthorized and routerNotRunning became the same state"
        )
    }

    // MARK: - A3 — the state the brief says must not be collapsed

    @Test("‹real loop› a failure after a success is stale, and keeps the servers it already had")
    func pollLoopGoesStaleKeepingServers() async throws {
        let expected = try [server("alpha"), server("beta")]
        let client = ScriptedControlAPIClient([
            .success(response(expected)),
            .failure(.transport(detail: "connection reset")),
        ])
        // One interval elapses, so a single `run()` performs both polls.
        let tracker = ServerStateTracker(
            client: client,
            pollInterval: .milliseconds(1),
            clock: SteppingClock(steps: 1)
        )

        let state = try await runLoop(tracker) { if case .stale = $0.load { true } else { false } }

        #expect(
            state.load == .stale(expected, .transport(detail: "connection reset")),
            "a failure after a success was not reported as stale — it settled on \(state.load)"
        )
        #expect(
            state.servers.map(\.name) == ["alpha", "beta"],
            "the last good snapshot was thrown away to report a refresh failure"
        )
        #expect(await client.pollCount() >= 2, "the loop did not actually poll twice")
    }

    @Test("‹real loop› recovery returns to loaded, in place")
    func pollLoopRecovers() async throws {
        let expected = try [server("alpha")]
        let client = ScriptedControlAPIClient([
            .success(response(expected)),
            .failure(.transport(detail: "connection reset")),
            .success(response(expected)),
        ])
        let tracker = ServerStateTracker(
            client: client,
            pollInterval: .milliseconds(1),
            clock: SteppingClock(steps: 2)
        )

        let state = try await runLoop(tracker) { current in
            if case .loaded = current.load { current.servers.count == 1 } else { false }
        }

        let polls = await client.pollCount()
        #expect(polls >= 3, "the loop did not reach the recovering poll — it made \(polls)")
        #expect(state.load == .loaded(expected), "the tracker never recovered — it settled on \(state.load)")
    }

    // MARK: - A10 — the whole of the typed error survives, hint included

    @Test("a server error keeps its status, message and hint")
    func serverErrorKeepsItsHint() async throws {
        let failure = ControlAPIError.server(
            status: 409, message: "already declared", hint: "retry with ?force=1 to add it anyway"
        )
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))

        await tracker.apply(pollFailure: failure)

        let state = await tracker.state()
        #expect(state.load == .failed(failure))
        // The hint is the difference between a dead end and a next step; a state that drops it
        // leaves the user told what failed and not what to do.
        guard case let .failed(carried) = state.load else {
            Issue.record("expected .failed, saw \(state.load)")
            return
        }
        #expect(carried.advice.contains("retry with ?force=1 to add it anyway"))
    }

    // MARK: - A11 — a failure is published, not only a success

    @Test("subscribers are notified of a poll failure, not only of a success")
    func subscribersSeeFailures() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        let updates = await tracker.updates()

        await tracker.apply(pollFailure: .routerNotRunning)

        let collector = Task { () -> ServerStateTracker.LoadState? in
            for await state in updates {
                if case .failed = state.load { return state.load }
                if case .stale = state.load { return state.load }
            }
            return nil
        }

        let seen = await collector.value
        #expect(
            seen == .failed(.routerNotRunning),
            "a surface subscribed to updates was never told the feed had failed"
        )
    }

    /// The other half of publishing: an unchanged state is not re-sent.
    ///
    /// A failing poll repeats every interval. Without this, each repeat pushes an identical
    /// snapshot into an unbounded buffer, so a subscriber that is merely backgrounded accumulates
    /// thousands of copies of one unchanging failure.
    @Test("an identical state is not published twice")
    func identicalStatesAreNotRepublished() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        let updates = await tracker.updates()

        await tracker.apply(pollFailure: .routerNotRunning)
        await tracker.apply(pollFailure: .routerNotRunning)
        await tracker.apply(pollFailure: .routerNotRunning)
        // A different state, so the collector has a terminator to look for.
        try await tracker.apply(poll: response([server("alpha")]))

        var seen: [ServerStateTracker.LoadState] = []
        for await state in updates {
            seen.append(state.load)
            if case .stale = state.load { break }
            if case .loaded = state.load, !state.servers.isEmpty { break }
        }

        let failures = seen.filter { if case .failed = $0 { true } else { false } }
        #expect(failures.count == 1, "the same failure was published \(failures.count) times")
    }

    // MARK: - A6, A7, A8 — the stream condition

    @Test("a tracker built without a stream is not-configured, never a dropped stream")
    func streamlessTrackerReportsNotConfigured() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        let state = await tracker.state()

        #expect(state.stream == .notConfigured)
        // The defect this replaces: `.disconnected` claims a stream existed and dropped, so a
        // surface trusting it drew disconnected chrome over live data forever.
        #expect(state.stream != .phase(.disconnected), "a polling-only tracker claimed a dropped stream")
    }

    @Test("a tracker built with a stream reports its phase, and a phase event moves it")
    func streamTrackerReportsPhase() async throws {
        let tracker = ServerStateTracker(
            client: FixtureControlAPIClient(.populated),
            stream: ControlEventStream()
        )
        #expect(await tracker.state().stream == .phase(.disconnected), "a configured stream started elsewhere")

        await tracker.apply(phase: .live)
        #expect(await tracker.state().stream == .phase(.live))

        // Losing the stream must not clear the rows already received: deleting history to report a
        // connection problem destroys data the user was reading.
        try await tracker.apply(poll: response([server("alpha")]))
        await tracker.apply(phase: .reconnecting)
        let state = await tracker.state()
        #expect(state.stream == .phase(.reconnecting))
        #expect(state.servers.count == 1, "a dropped stream cleared rows it never owned")
        if case .loaded = state.load {} else {
            Issue.record("a stream phase change disturbed what the poll had loaded: \(state.load)")
        }
    }

    @Test("a phase cannot be fabricated for a tracker that has no stream")
    func phaseIsIgnoredWithoutAStream() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))

        await tracker.apply(phase: .live)

        #expect(
            await tracker.state().stream == .notConfigured,
            "a polling-only tracker was made to claim a live stream it does not have"
        )
    }

    // MARK: - run() is singular

    /// Two `run()` calls must not start two poll loops.
    ///
    /// `run()` suspends at `waitForAll()`, which releases the actor, so without a guard a second
    /// caller starts a second loop. Overlapping polls let an older response land after a newer one
    /// and overwrite it — a lost update that looks exactly like the router changing its mind.
    @Test("running twice does not start a second poll loop")
    func runIsIdempotent() async throws {
        let expected = try [server("alpha")]
        let client = ScriptedControlAPIClient([.success(response(expected))])
        let tracker = ServerStateTracker(
            client: client,
            pollInterval: .milliseconds(1),
            clock: SteppingClock(steps: 0)
        )

        let first = Task { await tracker.run() }
        let second = Task { await tracker.run() }
        defer { first.cancel(); second.cancel() }

        // Let the single permitted poll land and the parked clock hold the loop.
        for _ in 0 ..< 200 {
            if await tracker.state().load != .loading { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(50))

        let polls = await client.pollCount()
        #expect(polls == 1, "two run() calls polled \(polls) times — a second loop is running")
    }
}
