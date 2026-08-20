import Foundation
import Testing
@testable import RouterCore

/// The pool's lifecycle edges: what happens when an upstream ends underneath us, when the reaper
/// races the call that paid for a cold start, and when two callers shut the pool down at once.
///
/// Split from `Pool reaping and reporting` for the suite length limit, not because the concerns
/// differ — the mutation gate filters by test function name, so the split is invisible to it.
@Suite("Pool lifecycle edges")
struct PoolLifecycleTests {
    private func makePool(
        _ upstreams: [UpstreamConfig],
        transport: FakeTransport,
        clock: TestClock = TestClock(),
        idleMs: Int = 60000,
        log: RouterLog? = nil
    ) -> UpstreamPool {
        UpstreamPool(
            upstreams: upstreams,
            defaultIdleMilliseconds: idleMs,
            defaultStartupTimeoutMilliseconds: 1000,
            transporting: transport,
            clock: clock,
            log: log
        )
    }

    @Test("P8 — a self-ended session is closed, not merely forgotten")
    func selfEndedSessionIsClosed() async throws {
        // Ending is the session telling us it went away; closing is releasing what we still hold.
        // Evicting without closing leaks the client, the transport, the descriptors and the process.
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a")], transport: transport)

        let lease = try await pool.lease("a")
        await pool.release(lease)
        let session = transport.sessions[0]

        // Awaited through the watcher that performs the eviction rather than through a window
        // chosen in advance; see `waitUntil` in `PoolTestSupport` for why the difference matters.
        let watcher = try #require(await pool.endWatcher("a"))
        session.endOnItsOwn()
        await watcher.value

        #expect(session.shutdownCount == 1, "the evicted session must be shut down exactly once")
        #expect(await !pool.isLive("a"))
    }

    @Test("P8 — eviction finishes before the close is logged, so no lease can take a dead session")
    func endedSessionIsEvictedBeforeAnySuspension() async throws {
        // The eviction and the log both live in `sessionEnded`, and the order is the whole safety
        // property: the log is a hop to another actor, so anything left undone before it happens
        // with the pool unlocked and a dead handle still installed.
        let sink = BlockingSink(matching: "closed on its own")
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a")], transport: transport, log: RouterLog(sink: sink))

        let first = try await pool.lease("a")
        await pool.release(first)
        let handleA = await pool.currentIdentities("a").handle

        transport.sessions[0].endOnItsOwn()
        // Not the watcher task here: awaiting it would wait out the blocked log too, and acting
        // *during* that log is the whole point. Eviction precedes the log and is what `isLive`
        // reports, so waiting on the eviction lands inside the window instead of guessing at it.
        await waitUntil("the dead handle to be evicted") { await !pool.isLive("a") }

        // Taken while the close is still being logged.
        let second = try await pool.lease("a")
        #expect(second.handle != handleA, "a lease must never be handed the session that just died")
        #expect(transport.sessions.count == 2, "the dead upstream is reopened, not reused")
        await pool.release(second)
    }

    @Test("P4a — no idle timer is armed while a caller still waits for the start it paid for")
    func reaperCannotBeatTheWaitingLease() async throws {
        // The cold-start window: installing a handle leaves nothing in flight, so an arming there
        // lets the reaper pass every one of its checks and close the child in the gap before the
        // waiting caller's lease is recorded — the call that paid for the start then fails on it.
        //
        // Asserted through the epoch counter rather than by racing a short idle window: the arming
        // at commit would be cancelled by the lease microseconds later, so a timing test would
        // usually miss it. Epochs are monotonic and count every arming that ever happened.
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a")], transport: transport)

        let lease = try await pool.lease("a")
        #expect(await pool.currentIdentities("a").epoch == nil, "a leased upstream has no idle timer")

        await pool.release(lease)
        #expect(
            await pool.currentIdentities("a").epoch == ReapEpoch(1),
            "release is the first arming in this upstream's life; an arming at commit would have taken #1"
        )
        #expect(transport.sessions[0].shutdownCount == 0)
    }

    @Test("P9 — a second shutdown awaits the first rather than returning early")
    func shutdownIsABarrier() async throws {
        // This is what a signal handler awaits before the process exits. A caller that returns
        // while children are still being terminated is exactly the orphan shutdown exists to
        // prevent, so "already shutting down" cannot mean "return immediately".
        let transport = FakeTransport()
        transport.setShutdownDelay(nanoseconds: 250_000_000)
        let pool = makePool([stdioUpstream("a"), stdioUpstream("b")], transport: transport)

        for name in ["a", "b"] {
            let lease = try await pool.lease(name)
            await pool.release(lease)
        }

        async let leader: Void = pool.shutdown()
        try? await Task.sleep(nanoseconds: 30_000_000)

        // The follower arrives with teardown already in flight and unfinished.
        await pool.shutdown()
        let closed = transport.sessions.allSatisfy { $0.shutdownCount == 1 }
        #expect(closed, "the second caller returned before teardown had finished")

        await leader
    }
}
