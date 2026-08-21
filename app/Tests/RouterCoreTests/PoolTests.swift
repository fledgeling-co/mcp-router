import Foundation
import Testing
@testable import RouterCore

/// The pool's state machine.
///
/// Every race test here names the guard it exercises and is written so that **removing that guard
/// makes it fail** — a test that passes either way is not evidence, and four guards adopted on
/// principle would be four pieces of machinery nobody could justify.
///
/// These run against a fake transport, so per the spec's E0 they do **not** discharge the P-clauses
/// on their own; `PoolProcessTests` re-proves them against real spawned children.
@Suite("Pool state machine")
struct PoolTests {
    private func makePool(
        _ upstreams: [UpstreamConfig],
        transport: FakeTransport,
        clock: TestClock = TestClock(),
        idleMs: Int = 60000
    ) -> UpstreamPool {
        UpstreamPool(
            upstreams: upstreams,
            defaultIdleMilliseconds: idleMs,
            defaultStartupTimeoutMilliseconds: 1000,
            transporting: transport,
            clock: clock
        )
    }

    // MARK: - P1: laziness

    @Test("P1 — nothing is opened until a lease is taken")
    func nothingOpensUntilLeased() async throws {
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a"), stdioUpstream("b")], transport: transport)

        #expect(transport.opens == 0)
        _ = await pool.status()
        _ = await pool.pending()
        #expect(transport.opens == 0, "reading status must not open anything")

        let lease = try await pool.lease("a")
        #expect(transport.opens == 1)
        #expect(lease.cold, "the lease that started the upstream is the cold one")
        await pool.release(lease)

        let second = try await pool.lease("a")
        #expect(transport.opens == 1, "a hot acquire reuses the open upstream")
        #expect(!second.cold)
        await pool.release(second)
    }

    // MARK: - P2 / P2a: single flight

    @Test("P2 — concurrent leases on a cold upstream produce exactly one open")
    func singleFlight() async throws {
        let transport = FakeTransport()
        transport.setGated(true)
        let pool = makePool([stdioUpstream("a")], transport: transport)

        async let first = pool.lease("a")
        await transport.waitForGatedOpen()
        async let second = pool.lease("a")
        async let third = pool.lease("a")
        // Open the gate once the two joiners have actually reached the cohort, rather than after a
        // window long enough that they probably have. Losing that bet makes the pool look as
        // though it spawned three children, which is the defect this test exists to catch.
        try await waitUntil("all three callers to join the cohort") {
            await pool.waitingCallers("a") >= 3
        }
        transport.openGate()

        let leases = try await [first, second, third]
        #expect(transport.opens == 1, "three callers, one spawn")
        #expect(Set(leases.map(\.handle)).count == 1, "all three hold the same handle")
        for lease in leases {
            await pool.release(lease)
        }
    }

    @Test("P2a — a start that completes after shutdown is closed, not leaked")
    func lateStartIsClosed() async {
        // The plan gate's critical finding: a generation guard that merely declines to install a
        // late success leaves that success owning a live child, and shutdown never sees it.
        let transport = FakeTransport()
        transport.setGated(true)
        let pool = makePool([stdioUpstream("a")], transport: transport)

        async let attempt: UpstreamLease? = try? await pool.lease("a")
        await transport.waitForGatedOpen()

        // Shutdown deliberately *awaits* a start still in flight (P9) — that is what stops a child
        // spawned as SIGTERM arrives from being orphaned. So the gate has to open concurrently;
        // opening it after `shutdown()` returned would deadlock the test, not the pool.
        async let shutdownFinished: Void = pool.shutdown()
        try? await Task.sleep(nanoseconds: 20_000_000)
        transport.openGate()
        await shutdownFinished
        _ = await attempt

        // The session was created, so something owns a child. It must have been shut down.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let sessions = transport.sessions
        #expect(sessions.count == 1)
        #expect(sessions[0].wasShutDown, "a superseded start must close what it opened")
    }

    @Test("P2a — a failed start does not strand the retry that replaces it")
    func failedStartAllowsRetry() async throws {
        let transport = FakeTransport()
        transport.failNextOpen()
        let pool = makePool([stdioUpstream("a")], transport: transport)

        await #expect(throws: (any Error).self) { try await pool.lease("a") }

        let lease = try await pool.lease("a")
        #expect(transport.opens == 2, "the retry is a new attempt, not a joined dead cohort")
        await pool.release(lease)
    }

    // MARK: - P4 / P4a: leases and in-flight accounting

    @Test("P4 — an upstream with a call outstanding is never reaped")
    func noReapWhileInFlight() async throws {
        let transport = FakeTransport()
        // Both windows are short, deliberately. Which of the two the pool picks is P6's claim, not
        // this one, and setting them equal is what makes the await at the end bounded under any
        // mutation instead of needing a guard number to protect it.
        let pool = makePool([stdioUpstream("a", idleMs: 30)], transport: transport, idleMs: 30)

        let lease = try await pool.lease("a")
        // A call outstanding arms no timer at all, which is stronger than finding the upstream
        // still live 120ms into a 30ms window — that only says a reap had not happened *yet*.
        let duringCall = await pool.armedReap("a")
        #expect(duringCall == nil, "a call in flight leaves no idle timer armed")
        #expect(await pool.isLive("a"), "the reaper must not close an upstream mid-call")

        // And the close is awaited through the timer the release arms, so the second half is not a
        // second bet on 120ms being longer than whatever the machine is doing.
        let armed = try #require(await pool.releaseObservingReap(lease), "release arms the timer")
        try await awaitEvent("`a` to be reaped once the call had finished") {
            await pool.awaitReap("a", epoch: armed.epoch)
        }
        #expect(await !pool.isLive("a"), "and it must close once the call has finished")
    }

    @Test("P4a — a duplicated release is ignored")
    func releaseIsExactlyOnce() async throws {
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a", idleMs: 0)], transport: transport)

        let first = try await pool.lease("a")
        let second = try await pool.lease("a")
        await pool.release(first)
        await pool.release(first) // the duplicate
        await pool.release(first) // and another

        let status = await pool.status().first { $0.name == "a" }
        #expect(status?.inFlight == 1, "one live lease remains; duplicates must not decrement it")
        await pool.release(second)
        let after = await pool.status().first { $0.name == "a" }
        #expect(after?.inFlight == 0)
    }
}
