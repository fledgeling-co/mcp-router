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
        idleMs: Int = 60_000
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
        // Give the two joiners a chance to reach the cohort before the gate opens.
        try? await Task.sleep(nanoseconds: 20_000_000)
        transport.openGate()

        let leases = try await [first, second, third]
        #expect(transport.opens == 1, "three callers, one spawn")
        #expect(Set(leases.map(\.handle)).count == 1, "all three hold the same handle")
        for lease in leases { await pool.release(lease) }
    }

    @Test("P2a — a start that completes after shutdown is closed, not leaked")
    func lateStartIsClosed() async throws {
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
        let pool = makePool([stdioUpstream("a", idleMs: 30)], transport: transport)

        let lease = try await pool.lease("a")
        // Well past the idle window, but the call has not finished.
        try? await Task.sleep(nanoseconds: 120_000_000)
        #expect(await pool.isLive("a"), "the reaper must not close an upstream mid-call")

        await pool.release(lease)
        try? await Task.sleep(nanoseconds: 120_000_000)
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

    // MARK: - P5 / P6 / P6a: reaping rules

    @Test("P5 — a warm upstream is never reaped")
    func warmIsNeverReaped() async throws {
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a", idleMs: 20, warm: true)], transport: transport)

        let lease = try await pool.lease("a")
        await pool.release(lease)
        try? await Task.sleep(nanoseconds: 150_000_000)
        #expect(await pool.isLive("a"), "warm implies running; reaping it undoes what it bought")
    }

    @Test("P6 — idleMs of zero or less disables reaping")
    func zeroIdleDisablesReaping() async throws {
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a", idleMs: 0)], transport: transport, idleMs: 20)

        let lease = try await pool.lease("a")
        await pool.release(lease)
        try? await Task.sleep(nanoseconds: 120_000_000)
        #expect(await pool.isLive("a"))
    }

    @Test("P6 — a per-server idle window overrides the default")
    func perServerIdleWins() async throws {
        let transport = FakeTransport()
        // Default is effectively never; the server asks for a short window and must get it.
        let pool = makePool([stdioUpstream("a", idleMs: 25)], transport: transport, idleMs: 600_000)

        let lease = try await pool.lease("a")
        await pool.release(lease)
        try? await Task.sleep(nanoseconds: 150_000_000)
        #expect(await !pool.isLive("a"))
    }

    @Test("P6a — a woken timer from a previous arming cannot reap")
    func staleTimerCannotReap() async throws {
        // Swift cancellation is cooperative: a cancelled sleeping task can still wake and run. The
        // guard is exercised directly rather than through timing, because the window a guard closes
        // is by definition the one that is hard to hit on purpose — a timing test here passed even
        // with the guard removed, which made it worthless as evidence.
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a", idleMs: 5000)], transport: transport)

        let first = try await pool.lease("a")
        await pool.release(first)                       // arms timer #1
        let stale = await pool.currentIdentities("a")
        let staleEpoch = try #require(stale.epoch)
        let handle = try #require(stale.handle)

        let second = try await pool.lease("a")          // cancels #1 and re-arms on release
        await pool.release(second)                      // arms timer #2

        // Timer #1 wakes LATE — its own deadline has genuinely passed — and asks to reap. Only its
        // epoch is stale, so this is what isolates the identity check from the deadline check.
        let passed = ContinuousClock.now.advanced(by: .milliseconds(-1))
        await pool.reapIfStillDue(name: "a", epoch: staleEpoch, handle: handle, deadline: passed)
        #expect(await pool.isLive("a"), "a superseded timer must not close a live upstream")

        // The current timer, asked before its own deadline, is refused too — the other half.
        let current = await pool.currentIdentities("a")
        let future = ContinuousClock.now.advanced(by: .seconds(60))
        await pool.reapIfStillDue(
            name: "a", epoch: try #require(current.epoch), handle: handle, deadline: future
        )
        #expect(await pool.isLive("a"), "and not before its deadline has actually passed")
    }

    // MARK: - P8 / P8a: eviction on close

    @Test("P8 — an upstream that ends on its own is evicted and reopened next call")
    func selfClosedIsEvicted() async throws {
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a")], transport: transport)

        let lease = try await pool.lease("a")
        await pool.release(lease)
        transport.sessions[0].endOnItsOwn()
        try? await Task.sleep(nanoseconds: 60_000_000)

        #expect(await !pool.isLive("a"), "a dead upstream must not be handed out again")
        let next = try await pool.lease("a")
        #expect(transport.opens == 2, "the next call reopens it")
        await pool.release(next)
    }

    @Test("P8a — a close from a previous incarnation cannot evict its replacement")
    func staleCloseCannotEvict() async throws {
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a")], transport: transport)

        let first = try await pool.lease("a")
        await pool.release(first)
        let firstHandle = try #require(await pool.currentIdentities("a").handle)

        // The first dies and is replaced.
        transport.sessions[0].endOnItsOwn()
        try? await Task.sleep(nanoseconds: 60_000_000)
        #expect(await !pool.isLive("a"))
        let second = try await pool.lease("a")
        await pool.release(second)
        #expect(transport.opens == 2)
        let secondHandle = try #require(await pool.currentIdentities("a").handle)
        #expect(secondHandle != firstHandle)

        // The first session's watcher lands late — reap cancels it, but cancellation is not
        // preemptive, so the call still arrives — and names a handle that is no longer installed.
        await pool.sessionEnded(name: "a", handle: firstHandle)
        #expect(await pool.isLive("a"), "generation A's close must not evict generation B")

        // The live handle's own close still evicts, so the guard has not simply disabled eviction.
        await pool.sessionEnded(name: "a", handle: secondHandle)
        #expect(await !pool.isLive("a"))
    }

    // MARK: - P9: shutdown

    @Test("P9 — shutdown refuses new leases, closes everything, and is idempotent")
    func shutdownIsComplete() async throws {
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a"), stdioUpstream("b")], transport: transport)

        let held = try await pool.lease("a")   // deliberately still outstanding
        let released = try await pool.lease("b")
        await pool.release(released)

        await pool.shutdown()

        let allClosed = transport.sessions.allSatisfy { $0.wasShutDown }
        #expect(allClosed, "including the one with a call in flight")
        await #expect(throws: (any Error).self) { try await pool.lease("a") }

        await pool.shutdown() // twice
        let stillClosed = transport.sessions.allSatisfy { $0.shutdownCount >= 1 }
        #expect(stillClosed)
        _ = held
    }

    // MARK: - P11 / D6: the counter transition table

    @Test("P11 — callsServed counts acquisitions, and a cohort counts once")
    func counterTransitions() async throws {
        let transport = FakeTransport()
        transport.setGated(true)
        let pool = makePool([stdioUpstream("a", idleMs: 0)], transport: transport)

        async let first = pool.lease("a")
        await transport.waitForGatedOpen()
        async let second = pool.lease("a")
        try? await Task.sleep(nanoseconds: 20_000_000)
        transport.openGate()
        let cohort = try await [first, second]
        for lease in cohort { await pool.release(lease) }

        var status = await pool.status().first { $0.name == "a" }
        #expect(status?.callsServed == 1, "a cold cohort counts once in total, not once per waiter")

        let hot = try await pool.lease("a")
        await pool.release(hot)
        status = await pool.status().first { $0.name == "a" }
        #expect(status?.callsServed == 2, "a hot acquire counts")
    }

    @Test("P11 — status reports configuration order and distinguishes the three states")
    func statusShape() async throws {
        let transport = FakeTransport()
        transport.setGated(true)
        let pool = makePool(
            [stdioUpstream("zeta"), stdioUpstream("alpha"), stdioUpstream("mid")],
            transport: transport
        )

        async let starting = pool.lease("alpha")
        await transport.waitForGatedOpen()

        let status = await pool.status()
        #expect(status.map(\.name) == ["zeta", "alpha", "mid"], "configuration order, not sorted")
        #expect(status[0].state == "idle")
        #expect(status[1].state == "starting")
        #expect(status[1].callsServed == 0)

        transport.openGate()
        let lease = try await starting
        let after = await pool.status()
        #expect(after[1].state == "running")
        #expect(after[1].inFlight == 1, "inFlight is work outstanding, never the lifetime counter")
        await pool.release(lease)
    }

    // MARK: - P14 / P15: pending auth and the legacy-SSE gap

    @Test("P14 — pending authorization is recorded, reported and cleared")
    func pendingAuthLifecycle() async throws {
        let transport = FakeTransport()
        let pool = makePool([httpUpstream("h")], transport: transport)

        await pool.recordPendingAuth(PendingAuth(server: "h", url: "https://auth.test", at: "now"))
        #expect(await pool.pending().map(\.server) == ["h"])
        await pool.clearPending("h")
        #expect(await pool.pending().isEmpty)
    }

    @Test("P15 — a legacy SSE upstream fails loudly with the capability-gap message")
    func legacySSEIsRefused() async throws {
        let transport = FakeTransport()
        let pool = makePool([httpUpstream("legacy", transport: .sse)], transport: transport)

        do {
            _ = try await pool.lease("legacy")
            Issue.record("a legacy SSE upstream must not be treated as streamable HTTP")
        } catch let error as PoolError {
            #expect(error == .legacySSEUnsupported("legacy"))
            #expect(error.description.contains("legacy SSE transport"))
            #expect(error.description.contains("Keep this server on the TypeScript router"))
        }
        #expect(transport.opens == 0, "and it must not open anything first")
    }

    @Test("unknown upstreams and shutdown carry the reference's wording")
    func errorWording() async throws {
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a")], transport: transport)

        #expect(PoolError.unknownUpstream("nope").description == "unknown upstream server \"nope\"")
        #expect(PoolError.shuttingDown.description == "router is shutting down")
        #expect(
            PoolError.startupTimeout(name: "a", milliseconds: 60000).description
                == "upstream \"a\" did not initialize within 60000ms"
        )
        _ = pool
    }

    // MARK: - Warm set

    @Test("P7 — warm upstreams open at start-up, and one that fails does not stop the others")
    func warmUpOpensAndTolerates() async throws {
        let transport = FakeTransport()
        transport.failNextOpen()
        let pool = makePool(
            [stdioUpstream("bad", warm: true), stdioUpstream("good", warm: true), stdioUpstream("lazy")],
            transport: transport
        )

        await pool.warmUp()

        #expect(await !pool.isLive("lazy"), "warm-up must not open anything not marked warm")
        // One of the two warm servers failed; the other must still be up.
        let badLive = await pool.isLive("bad")
        let goodLive = await pool.isLive("good")
        let live = [badLive, goodLive].filter { $0 }.count
        #expect(live == 1, "a warm server that will not start is reported, not fatal")
    }

    // MARK: - Reference numeric semantics

    @Test("idleSec uses JavaScript's Math.round, which differs from Swift's on .5")
    func jsRoundParity() {
        #expect(jsRound(0.5) == 1)
        #expect(jsRound(1.5) == 2)
        #expect(jsRound(2.5) == 3)
        #expect(jsRound(2.4) == 2)
        #expect(jsRound(-2.5) == -2, "JavaScript rounds half toward +infinity; Swift rounds away from zero")
        #expect(jsRound(-2.6) == -3)
    }
}
