import Foundation
import Testing
@testable import RouterCore

/// R27 — the health routes, **through `ControlHandler.handle`**.
///
/// Through the handler rather than by calling the response builders, for the reason
/// `ControlCacheRoutesTests` gives: `D-j` was never a broken function, it was a missing dispatch
/// arm, and a test that calls the function directly cannot fail when the arm is deleted. The
/// daemon's own wiring is a third thing again, and `scripts/acceptance/r27-health.sh` drives the
/// socket for that.
@Suite("R27 control routes")
struct ControlHealthRoutesTests {
    typealias Support = ControlAuthSupport

    private static func monitor(
        _ answers: [String: [ProbeOutcome]] = ["p1-stdio": [.ok(latencyMs: 4, tools: 2)]],
        live: Set<String> = [],
        upstreams: [UpstreamConfig]? = nil,
        refusals: [HealthPolicyRefusal] = []
    ) -> UpstreamHealthMonitor {
        UpstreamHealthMonitor(
            upstreams: upstreams ?? [stdioUpstream("p1-stdio"), httpUpstream("p1-http")],
            global: .standard,
            globalRefusals: refusals,
            probing: StubProbing(live: live, answers: answers),
            clock: TestClock()
        )
    }

    private static func answer(
        _ path: String,
        method: String = "GET",
        body: String? = "{}",
        authorized: Bool = true,
        contentType: Bool = true,
        _ deps: inout ControlDeps
    ) async -> (status: Int, body: String) {
        var headers: [(name: String, value: String)] = []
        if contentType { headers.append((name: "content-type", value: "application/json")) }
        if authorized { headers.append((name: "x-mcpr-token", value: Support.token)) }
        let response = await ControlHandler(token: Support.token).handle(
            ControlAPIRequest(
                method: method, encodedPath: path, query: [], headers: headers,
                body: body.map { Data($0.utf8) }
            ),
            &deps
        )
        guard case let .bytes(bytes) = response.body else { return (response.status, "") }
        // swiftlint:disable:next optional_data_string_conversion
        return (response.status, String(decoding: bytes, as: UTF8.self))
    }

    // MARK: - The collection

    @Test("H31 — GET /upstreams/health reports every declared upstream, unprobed, in order")
    func inventoryCoversEveryUpstream() async throws {
        var deps = try Support.makeDeps()
        deps.health = Self.monitor()

        let answer = await Self.answer("/upstreams/health", &deps)
        #expect(answer.status == 200)
        #expect(answer.body.contains(#""count":2"#))
        let stdio = try #require(answer.body.range(of: #""server":"p1-stdio""#))
        let http = try #require(answer.body.range(of: #""server":"p1-http""#))
        #expect(stdio.lowerBound < http.lowerBound, "configuration order, not dictionary order")
        #expect(answer.body.contains(#""state":"unprobed""#))
        // Absent rather than null: a `lastProbe` of null and a `lastProbe` carrying a failure both
        // read as "something is wrong" to a careless caller.
        #expect(answer.body.contains("lastProbe") == false)
    }

    @Test("H32 — with no monitor the route names the missing capability rather than reporting none")
    func absentMonitorIsA503() async throws {
        var deps = try Support.makeDeps()
        deps.health = nil

        let inventory = await Self.answer("/upstreams/health", &deps)
        #expect(inventory.status == 503)
        #expect(inventory.body.contains("no health monitor"))
        // An empty report would be indistinguishable from a router that had probed nothing, which
        // is the failure `D-p1-a` recorded on `/registry/search`: a dependency nil in the one
        // process that ships, invisible to every unit test.
        let probe = await Self.answer("/servers/p1-stdio/probe", method: "POST", &deps)
        #expect(probe.status == 503)
    }

    @Test("H33 — the collection is GET-only; another method is 405, not 404")
    func collectionRefusesOtherMethods() async throws {
        var deps = try Support.makeDeps()
        deps.health = Self.monitor()

        let answer = await Self.answer("/upstreams/health", method: "POST", &deps)
        // `isControlPath` claims the path, so "the method is wrong" is the true answer and "no such
        // route" is not.
        #expect(answer.status == 405)
    }

    // MARK: - The probe

    @Test("H34 — POST /servers/:name/probe probes now and answers the record it produced")
    func probeAnswersTheRecord() async throws {
        var deps = try Support.makeDeps()
        deps.health = Self.monitor()

        let answer = await Self.answer("/servers/p1-stdio/probe", method: "POST", &deps)
        #expect(answer.status == 200)
        #expect(answer.body.contains(#""server":"p1-stdio""#))
        #expect(answer.body.contains(#""state":"healthy""#))
        #expect(answer.body.contains(#""outcome":"ok""#))
        #expect(answer.body.contains(#""tools":2"#))
        #expect(answer.body.contains(#""probesRun":1"#))
    }

    @Test("H35 — the record survives between requests, so failures accumulate to a trip")
    func recordsAccumulateAcrossRequests() async throws {
        var deps = try Support.makeDeps()
        deps.health = Self.monitor(["p1-stdio": [.failed(reason: "no")]])

        var last = (status: 0, body: "")
        for _ in 1 ... 3 {
            last = await Self.answer("/servers/p1-stdio/probe", method: "POST", &deps)
        }
        // The monitor is held by the service, not built per request. A per-request monitor would
        // report `degraded` forever and `tripped` would be unreachable — invisible to any test
        // that makes one request.
        #expect(last.body.contains(#""state":"tripped""#))
        #expect(last.body.contains(#""consecutiveFailures":3"#))
    }

    @Test("H36 — a degraded upstream says so before it is tripped")
    func degradedPrecedesTrippedOnTheWire() async throws {
        var deps = try Support.makeDeps()
        deps.health = Self.monitor(["p1-stdio": [.timedOut(afterMs: 5000)]])

        let first = await Self.answer("/servers/p1-stdio/probe", method: "POST", &deps)
        #expect(first.body.contains(#""state":"degraded""#))
        #expect(first.body.contains(#""outcome":"timeout""#))
        #expect(first.body.contains(#""afterMs":5000"#))
    }

    @Test("H37 — a server the router does not declare is 404 before the monitor is consulted")
    func unknownServerIs404() async throws {
        var deps = try Support.makeDeps()
        deps.health = Self.monitor()

        let answer = await Self.answer("/servers/ghost/probe", method: "POST", &deps)
        #expect(answer.status == 404)
        #expect(answer.body.contains(#"no server named \"ghost\""#))
    }

    @Test("H38 — the probe is gated: no token is 401, no content-type is 415")
    func probeIsGatedLikeEveryOtherMutation() async throws {
        var deps = try Support.makeDeps()
        deps.health = Self.monitor()

        let untokened = await Self.answer(
            "/servers/p1-stdio/probe", method: "POST", authorized: false, &deps
        )
        #expect(untokened.status == 401)
        let untyped = await Self.answer(
            "/servers/p1-stdio/probe", method: "POST", contentType: false, &deps
        )
        #expect(untyped.status == 415)
    }

    @Test("H39 — GET on the probe path is 405, and `/Probe` is not a probe at all")
    func probeIsPostOnlyAndLowercase() async throws {
        var deps = try Support.makeDeps()
        deps.health = Self.monitor()

        #expect(await Self.answer("/servers/p1-stdio/probe", &deps).status == 405)
        // B23: the sub-path is lowercase-only, so an uppercase spelling must not actuate anything.
        let shouted = await Self.answer("/servers/p1-stdio/Probe", method: "POST", &deps)
        #expect(shouted.status == 405)
    }

    @Test("H40 — a refused setting reaches the wire with the scope that says where to fix it")
    func refusalsAreOnTheWire() async throws {
        var deps = try Support.makeDeps()
        var stdio = stdioUpstream("p1-stdio")
        stdio.health = HealthOverride(tripAfter: 1)
        deps.health = Self.monitor(
            upstreams: [stdio],
            refusals: [HealthPolicyRefusal(
                scope: "global", key: "probeIntervalMs", value: 10, reason: "below the floor of 1000"
            )]
        )

        let answer = await Self.answer("/upstreams/health", &deps)
        #expect(answer.body.contains(#""scope":"global""#))
        #expect(answer.body.contains(#""scope":"server""#))
        #expect(answer.body.contains(#""key":"tripAfter""#))
        // And the policy reported is the one in force, not the one that was written.
        #expect(answer.body.contains(#""tripAfter":3"#))
    }
}
