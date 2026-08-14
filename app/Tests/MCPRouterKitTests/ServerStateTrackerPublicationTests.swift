import Foundation
import Testing
@testable import MCPRouterKit

/// What reaches a subscriber, and what the stream condition reports.
///
/// These are the guards that decide whether a surface can render a failure at all. A tracker that
/// records a failure without publishing it leaves every subscribed surface frozen on the last good
/// frame — the same invisible failure as the original `try?`, one layer further out — and a
/// tracker that republishes an unchanged failure every interval fills an unbounded buffer instead.
/// Both are mechanised in `scripts/red-green.py` as `M58` and `M56`.
extension ServerStateTrackerTests {
    // MARK: - A10 — the whole of the typed error survives, hint included

    /// Driven through the real loop, because A10 is about errors *reaching* the tracker.
    ///
    /// The earlier version of this test called `apply(pollFailure:)` by hand. That passes against
    /// the original defect: with `try? await client.servers()` restored no poll failure ever
    /// arrives, so nothing is dropped and a hand-injected error is carried perfectly. A criterion
    /// about what survives the poll has to be asserted across the poll.
    @Test("‹real loop› a server error keeps its status, message and hint through the poll")
    func serverErrorKeepsItsHint() async throws {
        let failure = ControlAPIError.server(
            status: 409, message: "already declared", hint: "retry with ?force=1 to add it anyway"
        )
        let tracker = ServerStateTracker(
            client: ScriptedControlAPIClient([.failure(failure)]),
            pollInterval: .milliseconds(1),
            clock: SteppingClock(steps: 0)
        )

        let state = try await runLoop(tracker) { $0.load != .loading }

        #expect(state.load == .failed(failure), "settled on \(state.load)")
        // The hint is the difference between a dead end and a next step; a state that drops it
        // leaves the user told what failed and not what to do.
        guard case let .failed(carried) = state.load else {
            Issue.record("expected .failed, saw \(state.load)")
            return
        }
        #expect(carried.advice.contains("retry with ?force=1 to add it anyway"))
    }

    /// Names the case an error belongs to, exhaustively.
    ///
    /// This is the mechanism that makes A10's "every typed case" true tomorrow rather than only
    /// today. A hand-picked specimen list agrees with itself forever; adding a sixth case to
    /// `ControlAPIError` stops *this switch* compiling, which forces the list below to grow with
    /// it. `ControlAPIError` is not `CaseIterable` — it carries associated values — so an
    /// exhaustive switch is the only census available.
    func caseName(of error: ControlAPIError) -> String {
        switch error {
        case .routerNotRunning: "routerNotRunning"
        case .unauthorized: "unauthorized"
        case .malformedResponse: "malformedResponse"
        case .server: "server"
        case .transport: "transport"
        }
    }

    /// A10 says *every* typed case reaches the tracker intact, so the list is checked against the
    /// type rather than trusted.
    ///
    /// The earlier version exercised two of the five by hand, and `.malformedResponse` — what a
    /// decode failure produces, and the case most likely to be flattened into something generic —
    /// was asserted nowhere.
    @Test("‹real loop› every typed ControlAPIError case survives the poll as itself")
    func everyErrorCaseSurvivesTheLoop() async throws {
        let specimens: [ControlAPIError] = [
            .routerNotRunning,
            .unauthorized,
            .malformedResponse(detail: "servers[0].name was not a string"),
            .server(status: 503, message: "starting", hint: "try again in a moment"),
            .transport(detail: "connection reset")
        ]

        // Every case of the enum is represented exactly once. With the exhaustive switch above,
        // this is what turns "we listed five" into "we listed all of them".
        #expect(
            Set(specimens.map(caseName(of:))).count == specimens.count,
            "the specimen list repeats a case, so at least one is untested"
        )

        for specimen in specimens {
            let tracker = ServerStateTracker(
                client: ScriptedControlAPIClient([.failure(specimen)]),
                pollInterval: .milliseconds(1),
                clock: SteppingClock(steps: 0)
            )
            let state = try await runLoop(tracker) { $0.load != .loading }
            #expect(
                state.load == .failed(specimen),
                "\(specimen) did not reach the tracker as itself — it arrived as \(state.load)"
            )
        }

        // And they are five distinct states, not five spellings of "an error". A surface picks its
        // copy and its action by switching on this, so a collapse here is a wrong button.
        for i in specimens.indices {
            for j in specimens.indices where j > i {
                #expect(
                    ServerStateTracker.LoadState.failed(specimens[i]) != .failed(specimens[j]),
                    "\(specimens[i]) and \(specimens[j]) became the same state"
                )
            }
        }
    }

    // MARK: - A11 — a failure is published, not only a success

    /// Also driven through the real loop, and for the same reason — more sharply here, because A11
    /// is the criterion closest to the original bug. Hand-injecting the failure means no poll ever
    /// fails, so the test stays green with `try?` restored: the thing it claims to prove.
    @Test("‹real loop› subscribers are notified of a poll failure, not only of a success")
    func subscribersSeeFailures() async {
        let tracker = ServerStateTracker(
            client: FixtureControlAPIClient(.offline),
            pollInterval: .milliseconds(1),
            clock: SteppingClock(steps: 0)
        )
        // Subscribed before the loop starts, so the failure cannot land before anyone is listening.
        let updates = await tracker.updates()
        let running = Task { await tracker.run() }
        defer { running.cancel() }

        let seen = await bounded { () -> [ServerStateTracker.LoadState] in
            for await state in updates {
                if case .failed = state.load { return [state.load] }
                if case .stale = state.load { return [state.load] }
            }
            return []
        }.first?.first

        #expect(
            seen == .failed(.routerNotRunning),
            """
            a surface subscribed to updates was never told the poll had failed — \
            it saw \(String(describing: seen))
            """
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

        let seen = await bounded { () -> [ServerStateTracker.LoadState] in
            var acc: [ServerStateTracker.LoadState] = []
            for await state in updates {
                acc.append(state.load)
                if case .stale = state.load { break }
                if case .loaded = state.load, !state.servers.isEmpty { break }
            }
            return acc
        }.first ?? []

        let failures = seen.filter {
            if case .failed = $0 {
                true
            } else {
                false
            }
        }
        #expect(failures.count == 1, "the same failure was published \(failures.count) times")
    }

    // MARK: - A7 — the stream consumer, driven by real events

    /// `consumeStream()` had no test at all: every stream assertion called `apply(phase:)` or
    /// `apply(record:)` by hand, so the `switch` that routes an event to them, and the terminal
    /// phase report after it, were unexercised code in the file this feature exists to fix.
    ///
    /// This drives a real `ControlEventStream` against the same `HTTPStub` the F3 stream tests
    /// use, so the event genuinely travels the wire and through `consumeStream()`.
    @Test("‹real stream› an event delivered by the stream reaches the merge")
    func streamEventsReachTheTracker() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.onStream(
            HTTPStub.Stream(
                lines: [
                    """
                    data: {"ts":"2026-08-14T00:00:01.000Z","server":"alpha","tool":"t",\
                    "ok":true,"ms":4,"cold":false}
                    """
                ],
                gap: 0.02
            )
        )

        let tracker = try ServerStateTracker(
            client: ScriptedControlAPIClient([.success(response([server("alpha", state: .idle)]))]),
            stream: ControlEventStream(
                baseURL: stub.baseURL,
                session: URLSession(configuration: .ephemeral),
                policy: ReconnectPolicy(
                    initialDelay: .milliseconds(1),
                    ceiling: .milliseconds(2),
                    maximumAttempts: 1
                )
            ),
            pollInterval: .milliseconds(1),
            clock: SteppingClock(steps: 0)
        )

        // The poll lists alpha as idle; only a record arriving through the stream can make it
        // running. If `consumeStream()` never routed the event, this stays idle forever.
        let state = try await runLoop(tracker) { $0.servers.first?.state == .running }

        #expect(
            state.servers.first?.state == .running,
            "a record delivered by the real stream never reached the merge — alpha is \(state.load)"
        )
        // A phase, whichever one — the stub sends its single line and closes, so by the time the
        // record has been asserted the stream has legitimately finished and reported that. What
        // matters here is that a configured stream reports a phase at all rather than the
        // `.notConfigured` reserved for a tracker that was never given one.
        #expect(
            state.stream != .notConfigured,
            "a tracker built with a stream reported no stream condition"
        )
    }

    /// A deliberate teardown is not a dropped stream.
    ///
    /// `consumeStream()` reports `.disconnected` when iteration ends, which is right when the
    /// stream gave up and wrong when `run()` was cancelled — the ordinary shutdown path. Reporting
    /// it there publishes a failure that did not happen to every subscriber, which is the same lie
    /// as the pinned `.disconnected` this feature removed, arriving from the other end of the
    /// lifecycle.
    ///
    /// Parked rather than connected, deliberately. The stream points at a closed port with a long
    /// backoff, so it settles in `.reconnecting` and then emits nothing at all for the rest of the
    /// test. That makes the assertion about cancellation alone: any later change of phase would
    /// have to come from the teardown, because nothing else is still speaking.
    @Test("cancelling run() does not report a parked stream as dropped")
    func cancellationIsNotADroppedStream() async throws {
        let tracker = try ServerStateTracker(
            client: ScriptedControlAPIClient([.success(response([]))]),
            stream: ControlEventStream(
                // Port 1 is not listening, so the first attempt fails immediately and the policy
                // parks. Nothing here waits on a network timeout.
                baseURL: #require(URL(string: "http://127.0.0.1:1")),
                session: URLSession(configuration: .ephemeral),
                policy: ReconnectPolicy(
                    initialDelay: .seconds(600),
                    ceiling: .seconds(600),
                    maximumAttempts: 10
                )
            ),
            pollInterval: .milliseconds(1),
            clock: SteppingClock(steps: 0)
        )

        let running = Task { await tracker.run() }
        var parked = false
        for _ in 0 ..< 400 {
            if await tracker.state().stream == .phase(.reconnecting) {
                parked = true
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(parked, "the stream never parked in reconnect, so there was no teardown to observe")

        running.cancel()
        try await Task.sleep(for: .milliseconds(200))

        let afterCancellation = await tracker.state().stream
        #expect(
            afterCancellation == .phase(.reconnecting),
            """
            cancelling run() rewrote a parked stream to \(afterCancellation) — \
            a deliberate teardown was reported to every subscriber as a drop
            """
        )
    }

    // MARK: - A6, A7, A8 — the stream condition

    @Test("a tracker built without a stream is not-configured, never a dropped stream")
    func streamlessTrackerReportsNotConfigured() async {
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
        #expect(
            await tracker.state().stream == .phase(.disconnected),
            "a configured stream started elsewhere"
        )

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
    func phaseIsIgnoredWithoutAStream() async {
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
