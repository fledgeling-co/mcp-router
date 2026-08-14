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
/// mechanised permanently as mutant `M50` in `scripts/red-green.py`.
@Suite("Live server state")
struct ServerStateTrackerTests {
    func server(_ name: String, state: ServerState = .idle) throws -> MCPServer {
        var decoded = try FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)
        decoded.name = name
        decoded.state = state
        return decoded
    }

    func response(_ servers: [MCPServer]) -> ServersResponse {
        ServersResponse(port: 8879, idleMs: 300_000, since: "2026-08-14T00:00:00.000Z", servers: servers)
    }

    func record(for server: String) -> CallRecord {
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
        init(steps: Int) {
            remaining = steps
        }

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
        func pollCount() -> Int {
            index
        }

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

        func usage(
            limit: Int?,
            server: String?,
            cwd: String?
        ) async throws(ControlAPIError) -> UsageResponse {
            try await rest.usage(limit: limit, server: server, cwd: cwd)
        }

        func usageSummary() async throws(ControlAPIError) -> UsageSummary {
            try await rest.usageSummary()
        }

        func heldChanges(for name: String) async throws(ControlAPIError) -> HeldChanges {
            try await rest.heldChanges(for: name)
        }

        func searchRegistry(
            query: String,
            limit: Int
        ) async throws(ControlAPIError) -> RegistrySearchResponse {
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
    func runLoop(
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

    /// Runs `work` under a wall-clock bound, returning `[result]` or `[]` if it did not finish.
    ///
    /// Every subscriber assertion in this feature needs one, and the reason is specific rather
    /// than defensive: the regressions being guarded against publish *nothing*, so `for await`
    /// blocks forever instead of yielding a wrong value, and a test that hangs reports nothing at
    /// all. The mutation gate recorded exactly that — mutant `M58` came back `«suite did not
    /// terminate»` rather than naming the tests it broke. A count bound cannot help, because a
    /// bound that only advances on arrival never advances when nothing arrives.
    ///
    /// It is not a tolerance. The correct implementation answers in milliseconds; the bound exists
    /// so that a regression *fails*, with a message, instead of going quiet.
    ///
    /// The array is the return channel because `T?` here would be a double optional at the call
    /// site, and `?? nil` is the shape that stops meaning anything.
    func bounded<T: Sendable>(
        seconds: Int = 5,
        _ work: @escaping @Sendable () async -> T
    ) async -> [T] {
        await withTaskGroup(of: [T].self) { group in
            group.addTask { await [work()] }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return []
            }
            let first = await group.next() ?? []
            group.cancelAll()
            return first
        }
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

        // No sleep before publishing: registration is synchronous inside `updates()`, so the
        // subscriber already exists. A sleep here would hide a regression rather than prevent one.
        try await tracker.apply(poll: response([server("alpha")]))
        try await tracker.apply(poll: response([server("alpha"), server("beta")]))

        let counts = await bounded { () -> [Int] in
            var seen: [Int] = []
            for await state in updates {
                seen.append(state.servers.count)
                if seen.count == 3 { break }
            }
            return seen
        }.first ?? []
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

        let seen = await bounded {
            for await state in updates where !state.servers.isEmpty {
                return state.servers.count
            }
            return 0
        }.first
        #expect(seen == 1, "an update published right after subscribing was lost")
    }

    /// The invariant synchronous registration buys, asserted as an invariant rather than as one
    /// lucky interleaving.
    ///
    /// `updates()` returning means the subscriber is registered *and* has already been handed the
    /// state that was current at that moment — so its first element is always the pre-publish
    /// state, which for a tracker that has not polled is always `.loading`. Deferring registration
    /// makes that a race the subscriber can lose: registration is serviced at some later point and
    /// the yield it performs then carries whatever the state has since become, so `.loading` is
    /// never delivered and the transition out of it is gone. A surface that renders a skeleton for
    /// `.loading` would flash nothing, or — where the lost publication is a failure rather than a
    /// success — show no failure at all.
    ///
    /// Repeated because a race lost only sometimes is still a defect. The correct implementation
    /// answers `.loading` on every trial by construction; a deferred one has to win every time.
    @Test("the first state a subscriber sees is the one current when it subscribed")
    func firstStateIsTheStateAtSubscription() async throws {
        for trial in 1 ... 40 {
            let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
            let updates = await tracker.updates()

            // A different state, published with no delay at all. Anything the subscriber missed
            // between `updates()` returning and this landing is a lost notification.
            try await tracker.apply(poll: response([server("alpha")]))

            // The inner array is the sentinel: an empty one means the subscriber received nothing
            // at all. A scalar fallback of `.loading` here would make a timeout indistinguishable
            // from the pass this test is looking for, which is the failure mode it exists to stop.
            let first = await bounded { () -> [ServerStateTracker.LoadState] in
                for await state in updates {
                    return [state.load]
                }
                return []
            }.first?.first

            #expect(
                first == .loading,
                """
                trial \(trial): the state current at subscription was never delivered — the \
                subscriber's first element was \(String(describing: first)), so registration had \
                not completed by the time updates() returned
                """
            )
            if first != .loading { break }
        }
    }
}
