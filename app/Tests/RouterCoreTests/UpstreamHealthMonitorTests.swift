import Foundation
import Synchronization
import Testing
@testable import RouterCore

/// A prober that records what it was asked and answers what the test staged.
///
/// Top level rather than nested, because the repo caps nesting at one level.
final class StubProbing: UpstreamProbing, Sendable {
    private struct State {
        var live: Set<String> = []
        var answers: [String: [ProbeOutcome]] = [:]
        var probed: [String] = []
        var liveAsked: [String] = []
    }

    private let state = Mutex(State())

    init(live: Set<String> = [], answers: [String: [ProbeOutcome]] = [:]) {
        state.withLock {
            $0.live = live
            $0.answers = answers
        }
    }

    var probed: [String] { state.withLock { $0.probed } }
    var liveAsked: [String] { state.withLock { $0.liveAsked } }

    func isLive(_ name: String) async -> Bool {
        state.withLock {
            $0.liveAsked.append(name)
            return $0.live.contains(name)
        }
    }

    /// The staged answers are consumed in order; the last one repeats. A queue that ran dry and
    /// silently returned `.ok` would make a test asserting "the third failure trips it" pass on a
    /// monitor that only ever saw two.
    func probe(_ name: String, timeoutMilliseconds _: Int) async -> ProbeOutcome {
        state.withLock { current in
            current.probed.append(name)
            guard var queued = current.answers[name], !queued.isEmpty else {
                return .failed(reason: "StubProbing was not given an answer for \(name)")
            }
            let next = queued.count == 1 ? queued[0] : queued.removeFirst()
            current.answers[name] = queued
            return next
        }
    }
}

/// R27 — the monitor: what it probes, what it declines, and what it arms.
@Suite("R27 health monitor")
struct UpstreamHealthMonitorTests {
    private static func upstream(
        _ name: String, intervalMs: Int? = nil, disabled: Bool? = nil, tripAfter: Int? = nil
    ) -> UpstreamConfig {
        var config = stdioUpstream(name, disabled: disabled)
        config.health = HealthOverride(probeIntervalMs: intervalMs, tripAfter: tripAfter)
        return config
    }

    private static func monitor(
        _ upstreams: [UpstreamConfig], probing: StubProbing, clock: TestClock = TestClock()
    ) -> UpstreamHealthMonitor {
        UpstreamHealthMonitor(
            upstreams: upstreams, global: .standard, probing: probing, clock: clock
        )
    }

    @Test("H14 — every declared upstream is reported, in configuration order, before any probe")
    func snapshotCoversEverythingUnprobed() async {
        let monitor = Self.monitor(
            [Self.upstream("b"), Self.upstream("a")], probing: StubProbing()
        )
        let rows = await monitor.snapshot()
        #expect(rows.map(\.server) == ["b", "a"])
        #expect(rows.allSatisfy { $0.state == .unprobed })
    }

    @Test("H15 — a manual probe cold-starts; the monitor never asks whether it was live")
    func manualProbeMayColdStart() async {
        let probing = StubProbing(live: [], answers: ["s1": [.ok(latencyMs: 4, tools: 2)]])
        let monitor = Self.monitor([Self.upstream("s1")], probing: probing)

        let record = await monitor.probeNow("s1")
        #expect(record?.state == .healthy)
        #expect(probing.probed == ["s1"])
        // Not merely "it probed anyway" — it did not even consult liveness, because on this path
        // the answer would not change what it does. A liveness read here would be a guard somebody
        // could later make load-bearing by mistake.
        #expect(probing.liveAsked.isEmpty)
    }

    @Test("H16 — a scheduled sweep declines an upstream that is not live, and spawns nothing")
    func sweepNeverColdStarts() async {
        let probing = StubProbing(live: [], answers: ["s1": [.ok(latencyMs: 1, tools: 1)]])
        let monitor = Self.monitor([Self.upstream("s1", intervalMs: 60000)], probing: probing)

        let touched = await monitor.sweepOnce()
        #expect(touched.count == 1)
        // The assertion that matters is on the PROBER, not on the record: `REQ-001` is that at rest
        // there are zero child processes, and the only way to state that here is that the thing
        // which would spawn one was never called.
        #expect(probing.probed.isEmpty)
        #expect(probing.liveAsked == ["s1"])
        #expect(touched.first?.state == .unprobed)
        #expect(touched.first?.lastDeclined?.contains("does not cold start") == true)
    }

    @Test("H17 — a scheduled sweep does probe an upstream that is already live")
    func sweepProbesLiveUpstreams() async {
        let probing = StubProbing(live: ["s1"], answers: ["s1": [.ok(latencyMs: 7, tools: 3)]])
        let monitor = Self.monitor([Self.upstream("s1", intervalMs: 60000)], probing: probing)

        let touched = await monitor.sweepOnce()
        #expect(probing.probed == ["s1"])
        #expect(touched.first?.state == .healthy)
    }

    @Test("H18 — a disabled server is declined on both paths")
    func disabledIsNeverProbed() async {
        let probing = StubProbing(live: ["off"], answers: ["off": [.ok(latencyMs: 1, tools: 1)]])
        let monitor = Self.monitor(
            [Self.upstream("off", intervalMs: 60000, disabled: true)], probing: probing
        )

        let manual = await monitor.probeNow("off")
        #expect(manual?.lastDeclined == "the server is disabled")
        _ = await monitor.sweepOnce()
        // A probe route that spawned a disabled server would be a hole in the disable switch, not
        // a health check: `disabled` means never spawned to be warmed or indexed.
        #expect(probing.probed.isEmpty)
    }

    @Test("H19 — a server the router does not declare has no record and is not invented")
    func unknownServerIsNil() async {
        let monitor = Self.monitor([Self.upstream("s1")], probing: StubProbing())
        #expect(await monitor.probeNow("ghost") == nil)
        #expect(await monitor.snapshot().count == 1)
    }

    @Test("H20 — three failures trip, and the fourth probe's success recovers it")
    func failuresTripAndRecover() async {
        let probing = StubProbing(live: ["s1"], answers: ["s1": [
            .failed(reason: "one"), .failed(reason: "two"), .timedOut(afterMs: 5000),
            .ok(latencyMs: 2, tools: 1)
        ]])
        let monitor = Self.monitor([Self.upstream("s1")], probing: probing)

        #expect(await monitor.probeNow("s1")?.state == .degraded)
        #expect(await monitor.probeNow("s1")?.state == .degraded)
        #expect(await monitor.probeNow("s1")?.state == .tripped)
        #expect(await monitor.probeNow("s1")?.state == .healthy)
    }

    @Test("H21 — a refused override is carried on the record rather than dropped")
    func refusalsReachTheRecord() async throws {
        let monitor = UpstreamHealthMonitor(
            upstreams: [Self.upstream("s1", tripAfter: 1)],
            global: .standard,
            globalRefusals: [HealthPolicyRefusal(
                scope: "global", key: "probeTimeoutMs", value: 0, reason: "below the floor of 1"
            )],
            probing: StubProbing(),
            clock: TestClock()
        )
        let row = try #require(await monitor.snapshot().first)
        #expect(row.policy.tripAfter == HealthPolicy.standard.tripAfter)
        // Both scopes, global first: a reader given one row should not have to visit another to
        // learn that the file's top-level block was refused too.
        #expect(row.refusals.map(\.scope) == ["global", "server"])
    }

    @Test("H22 — no configured interval arms no background task at all")
    func noIntervalArmsNothing() async {
        let monitor = Self.monitor([Self.upstream("s1"), Self.upstream("s2")], probing: StubProbing())
        #expect(await monitor.tickMilliseconds == nil)
        await monitor.start()
        // An absence, asserted directly. A loop that woke every minute to find nothing due would be
        // indistinguishable from this in behaviour and would still be a timer nobody asked for.
        #expect(await monitor.isProbingInBackground == false)
        await monitor.stop()
    }

    @Test("H23 — the loop ticks at the smallest interval any server configured")
    func tickIsTheSmallestPositiveInterval() async {
        let monitor = Self.monitor(
            [Self.upstream("slow", intervalMs: 600_000),
             Self.upstream("fast", intervalMs: 60000),
             Self.upstream("off")],
            probing: StubProbing()
        )
        #expect(await monitor.tickMilliseconds == 60000)
        await monitor.start()
        #expect(await monitor.isProbingInBackground)
        await monitor.stop()
        #expect(await monitor.isProbingInBackground == false)
    }

    @Test("H24 — a sweep visits only what is due on its own interval")
    func sweepRespectsPerServerIntervals() async {
        let clock = TestClock()
        let probing = StubProbing(
            live: ["slow", "fast"],
            answers: [
                "slow": [.ok(latencyMs: 1, tools: 1)],
                "fast": [.ok(latencyMs: 1, tools: 1)]
            ]
        )
        let monitor = Self.monitor(
            [Self.upstream("slow", intervalMs: 600_000), Self.upstream("fast", intervalMs: 60000)],
            probing: probing, clock: clock
        )

        _ = await monitor.sweepOnce()
        #expect(Set(probing.probed) == ["slow", "fast"], "both are due on the first pass")

        clock.advance(60000)
        _ = await monitor.sweepOnce()
        #expect(probing.probed.filter { $0 == "fast" }.count == 2)
        #expect(probing.probed.filter { $0 == "slow" }.count == 1)
    }
}
