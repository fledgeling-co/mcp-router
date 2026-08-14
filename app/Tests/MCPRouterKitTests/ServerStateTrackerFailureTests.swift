import Foundation
import Testing
@testable import MCPRouterKit

/// The states the tracker could not express before F4, and the healthy ones they have to be told
/// apart from.
///
/// Split from `ServerStateTrackerTests` for the file- and type-length limits, and kept as an
/// extension rather than a second suite so the fixtures and the scripted client have exactly one
/// definition. A second copy of `SteppingClock` is how two suites start disagreeing about what a
/// poll interval means.
///
/// The ‹real loop› tests drive `pollLoop()` through `run()` rather than calling
/// `apply(pollFailure:)` by hand. That is the whole point: the original defect was
/// `try? await client.servers()`, which a hand-driven test passes against, because it never goes
/// near the loop that discarded the error.
extension ServerStateTrackerTests {
    // MARK: - A4, A5 — the healthy states, and telling empty from unloaded

    @Test("a tracker that has not polled is loading, not loaded-and-empty")
    func loadingIsDistinctFromEmpty() async {
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
    func healthyLiveIsAJointClassification() throws {
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
            .failure(.transport(detail: "connection reset"))
        ])
        // One interval elapses, so a single `run()` performs both polls.
        let tracker = ServerStateTracker(
            client: client,
            pollInterval: .milliseconds(1),
            clock: SteppingClock(steps: 1)
        )

        let state = try await runLoop(tracker) {
            if case .stale = $0.load {
                true
            } else {
                false
            }
        }

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

    /// A9 — recovery, observed the way a surface actually observes it.
    ///
    /// This test replaced one that polled `state()` for “`.loaded` with one server”, and that
    /// predicate was satisfiable by the *first* successful poll — the one before the failure. It
    /// therefore returned before the failure had happened at all and only incidentally passed;
    /// the mutation pass caught it going red for a reason unrelated to the mutation. There is no
    /// way to repair it in place, because through `state()` the poll before the failure and the
    /// poll after it are the same value. The transition is only a fact about the *sequence*.
    ///
    /// Which is also the honest reading of A9: a surface does not poll, it renders from
    /// `updates()`, so “the banner clears” is a claim about what a subscriber receives. Asserting
    /// the whole sequence rather than the final value matters for the same reason — a tracker that
    /// went loaded → loaded, never publishing the failure at all, would satisfy any final-value
    /// check while showing the user nothing wrong.
    @Test("‹real loop› a subscriber sees the failure and its recovery, in order")
    func recoveryIsObservableThroughUpdates() async throws {
        let expected = try [server("alpha")]
        let failure = ControlAPIError.transport(detail: "connection reset")
        let client = ScriptedControlAPIClient([
            .success(response(expected)),
            .failure(failure),
            .success(response(expected))
        ])
        let tracker = ServerStateTracker(
            client: client,
            pollInterval: .milliseconds(1),
            clock: SteppingClock(steps: 2)
        )

        // Subscribed before the loop starts, so the sequence is the whole of what happened rather
        // than whatever was left by the time a late subscriber arrived.
        let updates = await tracker.updates()
        let running = Task { await tracker.run() }
        defer { running.cancel() }

        var seen: [ServerStateTracker.LoadState] = []
        // Two bounds, because they catch different regressions. The count bound catches a tracker
        // that publishes the *wrong* states forever. The wall-clock bound catches one that stops
        // publishing altogether — which is what dropping the failure does, and which the count
        // bound cannot see, because a bound that only advances on arrival never advances when
        // nothing arrives. A test that hangs reports nothing at all; this one fails and says what
        // it saw. Neither is a tolerance: the correct implementation finishes in milliseconds.
        let collected = Task { () -> [ServerStateTracker.LoadState] in
            var acc: [ServerStateTracker.LoadState] = []
            for await state in updates {
                acc.append(state.load)
                let loadedCount = acc.filter {
                    if case .loaded = $0 {
                        true
                    } else {
                        false
                    }
                }.count
                if loadedCount == 2 || acc.count >= 8 { break }
            }
            return acc
        }
        seen = await withTaskGroup(of: [ServerStateTracker.LoadState].self) { group in
            group.addTask { await collected.value }
            group.addTask {
                // The only path that yields an empty array, so a timeout cannot be mistaken for a
                // subscriber that legitimately saw nothing — it always sees at least `.loading`.
                try? await Task.sleep(for: .seconds(5))
                return []
            }
            let first = await group.next() ?? []
            group.cancelAll()
            collected.cancel()
            return first
        }

        #expect(
            seen == [.loading, .loaded(expected), .stale(expected, failure), .loaded(expected)],
            "a subscriber did not see loading → loaded → stale → loaded; it saw \(seen)"
        )
        let polls = await client.pollCount()
        #expect(polls >= 3, "the loop did not reach the recovering poll — it made \(polls)")
    }
}
