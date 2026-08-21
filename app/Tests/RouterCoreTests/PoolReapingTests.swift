import Foundation
import Testing
@testable import RouterCore

/// Reaping, the warm set, and what `/status` reports.
///
/// Split from `PoolTests` because the two together outgrew the file-length limit, not because they
/// test different objects — the reaping rules are the other half of the same state machine.
@Suite("Pool reaping and reporting")
struct PoolReapingTests {
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

    // MARK: - P5 / P6 / P6a: reaping rules

    @Test("P5 — a warm upstream is never reaped")
    func warmIsNeverReaped() async throws {
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a", idleMs: 20, warm: true)], transport: transport)

        let lease = try await pool.lease("a")
        await pool.release(lease)

        // Read on the arming rather than on a wall-clock window. Finding the upstream still live
        // 150ms later samples one instant, and the sample passes just as well when a reap is
        // merely late; an upstream with no timer armed cannot be reaped by the idle path at all,
        // which is the claim. The mutation still bites: drop the warm guard and a timer appears.
        let armed = await pool.armedReap("a")
        #expect(armed == nil, "a warm upstream is never armed, so its 20ms window never applies")
        #expect(await pool.isLive("a"), "warm implies running; reaping it undoes what it bought")
    }

    @Test("P6 — idleMs of zero or less disables reaping")
    func zeroIdleDisablesReaping() async throws {
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a", idleMs: 0)], transport: transport, idleMs: 20)

        let lease = try await pool.lease("a")
        await pool.release(lease)

        let armed = await pool.armedReap("a")
        #expect(armed == nil, "zero disables reaping here; the pool's 20ms default must not apply")
        #expect(await pool.isLive("a"))
    }

    @Test("P6 — a per-server idle window overrides the default")
    func perServerIdleWins() async throws {
        let transport = FakeTransport()
        // One pool, one default that is effectively never, and two servers: `own` asks for its own
        // short window, `inherits` takes the default. The second is what makes the claim testable
        // as a comparison instead of as a duration.
        let pool = makePool(
            [stdioUpstream("own", idleMs: 25), stdioUpstream("inherits")],
            transport: transport,
            idleMs: 600_000
        )

        // The release and the reading of what it armed are ONE actor operation. Two would be a
        // second hop, and a 25ms window can expire inside one: the timer fires, the reap clears
        // it, and a correct pool reports no timer. That is this test's own defect one layer in,
        // and it is what two out-of-family reviewers found in the first version of this fix.
        let inherited = try await pool.lease("inherits")
        let other = try #require(await pool.releaseObservingReap(inherited), "release arms a timer")
        let owned = try await pool.lease("own")
        let armed = try #require(await pool.releaseObservingReap(owned), "on both servers")

        // The window each arming RESOLVED TO, compared exactly. Not a duration measured against a
        // clock and not two deadlines ordered against each other — an integer the pool chose,
        // read back. Nothing here can be made wrong by a slow machine, and nothing here is a
        // threshold anybody could widen later.
        #expect(other.idleMilliseconds == 600_000, "a server that asks for nothing takes the default")
        try #require(armed.idleMilliseconds == 25, "and one that asks gets its own, not the default")

        // Then the reap itself, awaited through the timer's own task so it is observed when it
        // happens rather than sampled at a moment picked in advance. `Task.sleep` is at-least and
        // the deadline was taken before the task existed, so the woken timer's own deadline check
        // cannot fail: the reap is complete when the task returns. The 150ms sleep this replaces
        // passed in isolation four times running and failed under whole-suite load.
        await pool.awaitReap("own", epoch: armed.epoch)
        #expect(await !pool.isLive("own"))
        // Honestly a clock dependency, and stated as one rather than dressed up: it holds unless
        // ten minutes passed between arming `inherits` and here. Six hundred seconds of slack is
        // not the same as none.
        #expect(await pool.isLive("inherits"), "and the default window has not come round")
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
        await pool.release(first) // arms timer #1
        let stale = await pool.currentIdentities("a")
        let staleEpoch = try #require(stale.epoch)
        let handle = try #require(stale.handle)

        let second = try await pool.lease("a") // cancels #1 and re-arms on release
        await pool.release(second) // arms timer #2

        // Timer #1 wakes LATE — its own deadline has genuinely passed — and asks to reap. Only its
        // epoch is stale, so this is what isolates the identity check from the deadline check.
        let passed = ContinuousClock.now.advanced(by: .milliseconds(-1))
        await pool.reapIfStillDue(name: "a", epoch: staleEpoch, handle: handle, deadline: passed)
        #expect(await pool.isLive("a"), "a superseded timer must not close a live upstream")

        // The current timer, asked before its own deadline, is refused too — the other half.
        let current = await pool.currentIdentities("a")
        let future = ContinuousClock.now.advanced(by: .seconds(60))
        try await pool.reapIfStillDue(
            name: "a", epoch: #require(current.epoch), handle: handle, deadline: future
        )
        #expect(await pool.isLive("a"), "and not before its deadline has actually passed")
    }

    // MARK: - P8 / P8a: eviction on close

    @Test("P8 — an upstream that ends on its own is evicted and reopened next call")
    func selfClosedIsEvicted() async throws {
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a")], transport: transport)

        let lease = try await pool.lease("a")
        let handle = try #require(await pool.currentIdentities("a").handle)
        await pool.release(lease)

        // Eviction happens inside the watcher task, and the pool awaits its own. Naming the handle
        // makes the wait exact: if the eviction has already landed, there is nothing to wait for,
        // and that is the outcome rather than a missed one.
        transport.sessions[0].endOnItsOwn()
        await pool.awaitSessionEnded("a", handle: handle)

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
        let firstHandle = try #require(await pool.currentIdentities("a").handle)
        await pool.release(first)

        // The first dies and is replaced, awaited by naming the handle whose eviction is expected.
        transport.sessions[0].endOnItsOwn()
        await pool.awaitSessionEnded("a", handle: firstHandle)
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

        let held = try await pool.lease("a") // deliberately still outstanding
        let released = try await pool.lease("b")
        await pool.release(released)

        await pool.shutdown()

        let allClosed = transport.sessions.allSatisfy(\.wasShutDown)
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
        // The gate opens once the second caller has actually joined the cohort. Sleeping 20ms and
        // hoping is the same bet as the one above: lose it and the second caller takes a HOT
        // acquire instead, and the test reports that as a counting defect in the pool.
        try await waitUntil("both callers to join") { await pool.waitingCallers("a") >= 2 }
        transport.openGate()
        let cohort = try await [first, second]
        for lease in cohort {
            await pool.release(lease)
        }

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
    func pendingAuthLifecycle() async {
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
    func errorWording() {
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
    func warmUpOpensAndTolerates() async {
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
        let live = [badLive, goodLive].filter(\.self).count
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
