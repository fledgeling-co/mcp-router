import Foundation
import Testing
@testable import RouterCore

/// R27 — resolving a health policy, and the state a sequence of probes produces.
///
/// Pure: nothing here spawns, sleeps or holds a lease. The two things being asserted are
/// arithmetic on a configuration and a state machine over outcomes, and both are wrong in ways a
/// process-level test would report as a flake.
@Suite("R27 health policy and record")
struct UpstreamHealthPolicyTests {
    private static let global = HealthPolicy(probeIntervalMs: 0, probeTimeoutMs: 5000, tripAfter: 3)

    // MARK: - Resolution

    @Test("H1 — a server's own values override the global ones key by key")
    func overridesApplyPerKey() {
        let resolved = HealthPolicy.resolve(
            global: Self.global, override: HealthOverride(probeIntervalMs: 60000)
        )
        #expect(resolved.policy.probeIntervalMs == 60000)
        // The two it did not name are the global values, not the type's defaults. An override that
        // reset its siblings would make "set one thing" impossible to express.
        #expect(resolved.policy.probeTimeoutMs == 5000)
        #expect(resolved.policy.tripAfter == 3)
        #expect(resolved.refusals.isEmpty)
    }

    @Test("H2 — a trip threshold of 1 is refused, because it makes `degraded` unreachable")
    func tripAfterBelowTwoIsRefused() throws {
        let resolved = HealthPolicy.resolve(
            global: Self.global, override: HealthOverride(tripAfter: 1)
        )
        // The value is NOT clamped to 2. It is refused, and the global value stands.
        #expect(resolved.policy.tripAfter == 3)
        let refusal = try #require(resolved.refusals.first)
        #expect(refusal.key == "tripAfter")
        #expect(refusal.value == 1)
        #expect(refusal.scope == "server")
        #expect(refusal.reason.contains("floor of 2"))
    }

    @Test("H3 — a sub-second interval is refused; an explicit zero is taken")
    func intervalFloorAndZero() {
        let tooFast = HealthPolicy.resolve(
            global: Self.global, override: HealthOverride(probeIntervalMs: 10)
        )
        #expect(tooFast.policy.probeIntervalMs == 0)
        #expect(tooFast.refusals.map(\.key) == ["probeIntervalMs"])

        // Zero is not "below the floor" — it is the documented way to say "do not probe this one",
        // so it has to survive a floor written for the positive range.
        let off = HealthPolicy.resolve(
            global: HealthPolicy(probeIntervalMs: 60000, probeTimeoutMs: 5000, tripAfter: 3),
            override: HealthOverride(probeIntervalMs: 0)
        )
        #expect(off.policy.probeIntervalMs == 0)
        #expect(off.refusals.isEmpty)
    }

    @Test("H4 — a probe timeout of zero is refused; an unbounded probe cannot report a timeout")
    func timeoutMustBePositive() {
        let resolved = HealthPolicy.resolve(
            global: Self.global, override: HealthOverride(probeTimeoutMs: 0)
        )
        #expect(resolved.policy.probeTimeoutMs == 5000)
        #expect(resolved.refusals.map(\.key) == ["probeTimeoutMs"])
    }

    @Test("H5 — a global refusal is labelled `global`, so the reader knows which block to fix")
    func globalRefusalsCarryTheirScope() throws {
        let raw = try JSONParser.parse(#"{"tripAfter": 1, "probeIntervalMs": 60000}"#)
        let resolved = HealthPolicy.readGlobal(raw)
        #expect(resolved.policy.probeIntervalMs == 60000)
        #expect(resolved.policy.tripAfter == HealthPolicy.standard.tripAfter)
        let refusal = try #require(resolved.refusals.first)
        #expect(refusal.scope == "global")
    }

    @Test("H6 — a `health` member that is not an object configures nothing")
    func nonObjectHealthIsIgnored() throws {
        #expect(try HealthOverride.read(JSONParser.parse("3")) == nil)
        #expect(try HealthOverride.read(JSONParser.parse(#""fast""#)) == nil)
        #expect(HealthOverride.read(nil) == nil)
    }

    @Test("H7 — the parser reads a server's own health block off its entry")
    func serverParserReadsHealth() throws {
        let raw = try JSONParser.parse("""
        {"command": "/bin/echo", "health": {"probeIntervalMs": 60000, "tripAfter": 4}}
        """)
        guard case let .upstream(upstream) = ServerParser.parse(name: "s1", raw: raw) else {
            Issue.record("the fixture should parse as an upstream")
            return
        }
        #expect(upstream.health?.probeIntervalMs == 60000)
        #expect(upstream.health?.tripAfter == 4)
        #expect(upstream.health?.probeTimeoutMs == nil)
        // The health block must not reach the identity hash: how often the router asks a server for
        // its tools does not change which tools it advertises, and a re-index per settings change
        // would spawn every server the moment somebody moved a slider.
        var without = upstream
        without.raw = try JSONParser.parse(#"{"command": "/bin/echo"}"#)
        #expect(UpstreamHash.hash(upstream) == UpstreamHash.hash(without))
    }

    // MARK: - The state machine

    private static func record(tripAfter: Int = 3) -> UpstreamHealthRecord {
        UpstreamHealthRecord(
            server: "s1",
            policy: HealthPolicy(probeIntervalMs: 0, probeTimeoutMs: 5000, tripAfter: tripAfter)
        )
    }

    @Test("H8 — nothing probed is `unprobed`, which is not `healthy`")
    func unprobedIsItsOwnState() {
        #expect(Self.record().state == .unprobed)
    }

    @Test("H9 — degraded strictly precedes tripped, at every threshold from 2 upwards")
    func degradedPrecedesTripped() {
        for tripAfter in 2 ... 5 {
            var record = Self.record(tripAfter: tripAfter)
            for failure in 1 ..< tripAfter {
                record.apply(.failed(reason: "no"), atMs: Double(failure))
                #expect(
                    record.state == .degraded,
                    "failure \(failure) of \(tripAfter) should be degraded, not \(record.state)"
                )
            }
            record.apply(.failed(reason: "no"), atMs: 99)
            #expect(record.state == .tripped)
        }
    }

    @Test("H10 — one success recovers a tripped upstream, and the asymmetry is deliberate")
    func oneSuccessRecovers() {
        var record = Self.record(tripAfter: 2)
        record.apply(.failed(reason: "no"), atMs: 1)
        record.apply(.timedOut(afterMs: 5000), atMs: 2)
        #expect(record.state == .tripped)

        record.apply(.ok(latencyMs: 3, tools: 2), atMs: 3)
        #expect(record.state == .healthy)
        #expect(record.consecutiveFailures == 0)
        #expect(record.lastOkAtMs == 3)
    }

    @Test("H11 — a declined probe is not a failure and does not move anything")
    func declineIsNotAFailure() {
        var record = Self.record(tripAfter: 2)
        for tick in 1 ... 10 {
            record.apply(.declined(reason: "not live"), atMs: Double(tick))
        }
        // The whole point: a sweep that declines twenty-one idle servers forever must not trip
        // them. Counting a decline would report the router's own design as an outage.
        #expect(record.state == .unprobed)
        #expect(record.probesRun == 0)
        #expect(record.consecutiveFailures == 0)
        #expect(record.lastDeclined == "not live")
    }

    @Test("H12 — a real attempt clears the decline that preceded it")
    func attemptClearsDecline() {
        var record = Self.record()
        record.apply(.declined(reason: "not live"), atMs: 1)
        record.apply(.ok(latencyMs: 1, tools: 0), atMs: 2)
        #expect(record.lastDeclined == nil)
        // Zero tools is a reading, not a failure. A server that advertises none is healthy.
        #expect(record.state == .healthy)
    }

    @Test("H13 — a server with no interval is never due, however long it waits")
    func zeroIntervalIsNeverDue() {
        let off = Self.record()
        #expect(off.isDue(atMs: 0) == false)
        #expect(off.isDue(atMs: 1_000_000_000) == false)

        var timed = UpstreamHealthRecord(
            server: "s1",
            policy: HealthPolicy(probeIntervalMs: 1000, probeTimeoutMs: 500, tripAfter: 3)
        )
        #expect(timed.isDue(atMs: 0), "a server that has never been probed is due immediately")
        timed.apply(.ok(latencyMs: 1, tools: 1), atMs: 10000)
        #expect(timed.isDue(atMs: 10500) == false)
        #expect(timed.isDue(atMs: 11000))
    }
}
