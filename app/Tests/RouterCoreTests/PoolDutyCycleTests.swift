import Foundation
import Testing
@testable import RouterCore

/// The share of wall-clock time each child was alive.
///
/// This is the product's own argument, so the thing under test is that it is **counted** rather
/// than derived: the pool already measured every interval to write `closing idle child … Ns alive`
/// into its log, and the failure this suite guards is that interval being thrown away on one of the
/// two paths an incarnation can end on.
@Suite("Pool duty cycle")
struct PoolDutyCycleTests {
    private func makePool(
        _ upstreams: [UpstreamConfig], transport: FakeTransport, clock: TestClock
    ) -> UpstreamPool {
        UpstreamPool(
            upstreams: upstreams,
            defaultIdleMilliseconds: 60000,
            defaultStartupTimeoutMilliseconds: 1000,
            transporting: transport,
            clock: clock
        )
    }

    @Test("every declared upstream has a row, including the ones that never opened")
    func everyDeclaredUpstreamHasARow() async {
        let clock = TestClock()
        let pool = makePool(
            [stdioUpstream("a"), stdioUpstream("b")], transport: FakeTransport(), clock: clock
        )
        clock.advance(5000)
        let reading = await pool.dutyCycle()
        #expect(reading.servers.map(\.name) == ["a", "b"])
        // A server that has never been opened is the most informative row on this chart. A reading
        // that dropped it would look like a shorter list rather than like a zero.
        #expect(reading.servers.allSatisfy { $0.aliveMilliseconds == 0 })
        #expect(reading.uptimeMilliseconds == 5000)
    }

    @Test("a still-open incarnation counts, and keeps counting")
    func openIncarnationCounts() async throws {
        let clock = TestClock()
        let pool = makePool([stdioUpstream("a")], transport: FakeTransport(), clock: clock)
        let lease = try await pool.lease("a")
        clock.advance(4000)
        let first = await pool.dutyCycle()
        #expect(first.servers.first?.aliveMilliseconds == 4000)
        clock.advance(1000)
        let second = await pool.dutyCycle()
        #expect(second.servers.first?.aliveMilliseconds == 5000)
        await pool.release(lease)
    }

    @Test("a reaped incarnation is kept, and a second one adds to it")
    func closedIncarnationsAccumulate() async throws {
        let clock = TestClock()
        let pool = makePool([stdioUpstream("a")], transport: FakeTransport(), clock: clock)

        let first = try await pool.lease("a")
        clock.advance(3000)
        await pool.release(first)
        await pool.reap(name: "a", force: true)
        #expect(await pool.dutyCycle().servers.first?.aliveMilliseconds == 3000)

        clock.advance(1000)
        let second = try await pool.lease("a")
        clock.advance(2000)
        await pool.release(second)
        await pool.reap(name: "a", force: true)
        // 3000 + 2000. The gap between them is uptime the server was not alive for, which is what
        // the whole chart is about.
        #expect(await pool.dutyCycle().servers.first?.aliveMilliseconds == 5000)
    }

    @Test("an upstream that ends on its own is counted too")
    func selfEndedIncarnationIsCounted() async throws {
        let clock = TestClock()
        let transport = FakeTransport()
        let pool = makePool([stdioUpstream("a")], transport: transport, clock: clock)

        let lease = try await pool.lease("a")
        clock.advance(2500)
        await pool.release(lease)
        // The other way an incarnation ends. A duty cycle counted only at the reaper would
        // under-report exactly the servers that fall over — which are the ones a reader is looking
        // for.
        await pool.sessionEnded(name: "a", handle: lease.handle)
        #expect(await pool.dutyCycle().servers.first?.aliveMilliseconds == 2500)
    }
}
