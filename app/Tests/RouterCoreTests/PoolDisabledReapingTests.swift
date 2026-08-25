import Foundation
import Testing
@testable import RouterCore

/// M29 — the switch and the warm set, which are the only two pool settings that meet.
///
/// Split from `PoolReapingTests` for the reason that file was split from `PoolTests`: the two
/// together outgrow the file-length limit. They are the same state machine, and `P5` there — a warm
/// upstream is never armed for reaping — is the rule the second test here qualifies.
@Suite("Pool — a disabled upstream")
struct PoolDisabledReapingTests {
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
            clock: clock,
            log: nil
        )
    }

    /// Oracle 4. `warm` and `disabled` are the only two settings that meet, and they disagree.
    @Test("M29 — a disabled upstream is not opened at start-up even when it is marked warm")
    func warmUpSkipsADisabledUpstream() async {
        let transport = FakeTransport()
        let pool = makePool(
            [
                stdioUpstream("off", warm: true, disabled: true),
                stdioUpstream("on", warm: true)
            ],
            transport: transport
        )

        await pool.warmUp()

        #expect(await !pool.isLive("off"), "warm-up spawned a server the user had switched off")
        // The control. Without it this passes just as well on a warm-up that opens nothing at all.
        #expect(await pool.isLive("on"), "warm-up stopped opening warm servers altogether")
    }

    /// Oracle 13, and the one the plan found by enumerating the serving surface rather than reading
    /// the spec.
    ///
    /// `P5` above asserts that a warm upstream is never armed. That rule, left alone, means a warm
    /// server that is then disabled keeps a resident child process forever with no route to it —
    /// serving nobody and never reaped, which is the opposite of what the switch is for. So the
    /// arming is asserted here in both directions against the same 20ms window.
    @Test("M29 — a warm upstream that is disabled IS armed for reaping")
    func aDisabledWarmUpstreamIsReaped() async throws {
        let transport = FakeTransport()
        let pool = makePool(
            [
                stdioUpstream("off", idleMs: 20, warm: true, disabled: true),
                stdioUpstream("on", idleMs: 20, warm: true)
            ],
            transport: transport
        )

        for name in ["off", "on"] {
            let lease = try await pool.lease(name)
            await pool.release(lease)
        }

        #expect(
            await pool.armedReap("off") != nil,
            "a disabled warm upstream was left unarmed, so nothing will ever close its child"
        )
        #expect(
            await pool.armedReap("on") == nil,
            "the warm guard stopped applying to warm servers that are not disabled"
        )
    }
}
