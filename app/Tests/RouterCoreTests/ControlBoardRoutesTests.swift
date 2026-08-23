import Foundation
import Testing
@testable import RouterCore

/// `GET /harnesses` and `GET /insights`, **through `ControlHandler.handle`**.
///
/// Through the handler rather than by calling the two response builders, for the reason
/// `ControlApproveDispatchTests` states in its own words: `D-j` was never a broken function, it was
/// a missing dispatch arm, and a test that calls the function cannot fail when the arm is deleted.
/// Both of these routes are the whole reason `R7-C1` could not ship on its own, so an unreachable
/// one is the failure worth guarding.
@Suite("M22 control routes")
struct ControlBoardRoutesTests {
    typealias Support = ControlAuthSupport

    /// A harness inventory a test can put in any state. The real one reads `$HOME`, where none of
    /// the three interesting readings — unreadable, wired-with-duplicates, nothing detected — can
    /// be asked for.
    struct StubInventory: HarnessInventorySource {
        let rows: [HarnessReport]

        func reports(upstreams _: [UpstreamConfig], port _: Int) -> [HarnessReport] {
            rows
        }
    }

    struct StubInsights: InsightsSource {
        var readings: [ResidentReading] = []
        var duty = DutyCycleReading(uptimeMilliseconds: 0, servers: [])

        func resident() async -> [ResidentReading] {
            readings
        }

        func dutyCycle() async -> DutyCycleReading {
            duty
        }
    }

    private static func report(
        _ client: MCPClient,
        route: HarnessRoute = .notWired,
        entries: Int = 0,
        duplicates: [Duplicate] = [],
        unreadable: String? = nil,
        exists: Bool = true
    ) -> HarnessReport {
        HarnessReport(
            client: client, path: "/tmp/\(client.rawValue).json", unreadable: unreadable,
            exists: exists, entryCount: entries, route: route,
            capability: .known(for: client), duplicates: duplicates, unparsed: []
        )
    }

    private static func answer(
        _ path: String, method: String = "GET", authorized: Bool = false, _ deps: inout ControlDeps
    ) async -> (Int, String) {
        var headers: [(name: String, value: String)] = []
        if authorized {
            headers.append((name: "content-type", value: "application/json"))
            headers.append((name: "x-mcpr-token", value: Support.token))
        }
        let response = await ControlHandler(token: Support.token).handle(
            ControlAPIRequest(
                method: method, encodedPath: path, query: [], headers: headers, body: nil
            ),
            &deps
        )
        guard case let .bytes(bytes) = response.body else { return (response.status, "") }
        // swiftlint:disable:next optional_data_string_conversion
        return (response.status, String(decoding: bytes, as: UTF8.self))
    }

    // MARK: - /harnesses

    @Test("H1 — the four readings each reach the wire under their own word")
    func fourReadings() async throws {
        var deps = try Support.makeDeps()
        deps.harnesses = StubInventory(rows: [
            Self.report(.claudeCode, route: .directHTTP(name: "router", url: "u")),
            Self.report(.grokCLI, route: .stdioShim(name: "r", bridge: "mcp-remote", url: "u")),
            Self.report(
                .geminiCLI,
                route: .directHTTP(name: "router", url: "u"),
                entries: 18,
                duplicates: [Duplicate(harnessName: "a", routerName: "a", basis: .name)]
            ),
            Self.report(.opencode)
        ])
        let (status, body) = await Self.answer("/harnesses", &deps)
        #expect(status == 200)
        #expect(body.contains(#""state":"wired-http""#))
        #expect(body.contains(#""state":"wired-shim""#))
        #expect(body.contains(#""state":"wired-with-duplicates""#))
        #expect(body.contains(#""state":"not-wired""#))
        // The bridge is a member of its own, because the shim's cost is what the row has to name
        // and it survives a harness being shimmed *and* duplicating.
        #expect(body.contains(#""bridge":"mcp-remote""#))
        #expect(body.contains(#""entries":18"#))
        #expect(body.contains(#""scope":"global""#))
        // The reading is stamped. A stale one is worse than no reading, and a surface cannot say
        // so about a number that arrived with no clock on it.
        #expect(body.contains(#""readAt":"#))
    }

    @Test("H2 — an unreadable config is distinguishable from a clean unwired one")
    func unreadableIsNotTheSameAsUnwired() async throws {
        var deps = try Support.makeDeps()
        deps.harnesses = StubInventory(rows: [
            Self.report(.grokCLI, unreadable: "line 14812: unexpected key after table header")
        ])
        let (status, body) = await Self.answer("/harnesses", &deps)
        #expect(status == 200)
        // Both of these are true of the same row at the same time, and that is exactly the trap:
        // an unreadable config reaches the encoder as the EMPTY report, so `state` says not-wired
        // and every count says 0 — the same bytes a clean unwired harness produces. `unreadable`
        // is the only member that can tell them apart.
        #expect(body.contains(#""state":"not-wired""#))
        #expect(body.contains(#""entries":0"#))
        #expect(body.contains(#""unreadable":"line 14812: unexpected key after table header""#))
    }

    @Test("H3 — with no inventory source the route says which capability is missing")
    func noInventorySourceIs503() async throws {
        var deps = try Support.makeDeps()
        let (status, body) = await Self.answer("/harnesses", &deps)
        #expect(status == 503)
        // Not an empty list. An empty list is indistinguishable from a machine with no harnesses
        // on it, which is the exact reading this board exists to make.
        #expect(body.contains("harness detection is unavailable"))
    }

    @Test("H4 — the dispatch ladder answers in its documented order, and there is no sub-path")
    func methodAndSubPath() async throws {
        var deps = try Support.makeDeps()
        deps.harnesses = StubInventory(rows: [])

        // 401 before 405, because the token gate is stage 2 and the method dispatch is stage 7.
        // That is the same ordering `DELETE /servers/ghost` answers 401 rather than 404 under, and
        // it is a property of `handle` rather than of this route — asserted here so that claiming
        // the path cannot quietly change it.
        let (untokened, _) = await Self.answer("/harnesses", method: "POST", &deps)
        #expect(untokened == 401)

        let (status, _) = await Self.answer(
            "/harnesses", method: "POST", authorized: true, &deps
        )
        #expect(status == 405, "the path exists; the method is what is wrong")

        let response = await ControlHandler(token: Support.token).handle(
            ControlAPIRequest(
                method: "GET", encodedPath: "/harnesses/claude", query: [], headers: [], body: nil
            ),
            &deps
        )
        #expect(!response.handled, "there is no sub-path, so this is not a control path")
    }

    // MARK: - /insights

    @Test("I1 — with no pool the two pool figures are null rather than zero")
    func poolFiguresAreAbsentNotZero() async throws {
        var deps = try Support.makeDeps()
        deps.harnesses = StubInventory(rows: [])
        let (status, body) = await Self.answer("/insights", &deps)
        #expect(status == 200)
        // A zero is a measurement and this is an absence. The memory figure is labelled "measured,
        // not modelled" on the board, and a zero under that label would be a lie.
        #expect(body.contains(#""resident":null"#))
        #expect(body.contains(#""dutyCycle":null"#))
        // The analyst is present and null, so a board renders its empty state from a fact the
        // router stated rather than from a key it failed to find.
        #expect(body.contains(#""analyst":null"#))
    }

    @Test("I2 — resident memory is summed only over children that have a process")
    func residentIsSummed() async throws {
        var deps = try Support.makeDeps()
        deps.harnesses = StubInventory(rows: [])
        deps.insights = StubInsights(
            readings: [
                ResidentReading(server: "a", megabytes: 120),
                ResidentReading(server: "b", megabytes: 94)
            ],
            duty: DutyCycleReading(
                uptimeMilliseconds: 3_600_000,
                servers: [DutyCycleReading.Server(name: "a", aliveMilliseconds: 1_332_000)]
            )
        )
        let (_, body) = await Self.answer("/insights", &deps)
        #expect(body.contains(#""megabytes":214"#))
        #expect(body.contains(#""children":2"#))
        #expect(body.contains(#""uptimeSeconds":3600"#))
        #expect(body.contains(#""aliveSeconds":1332"#))
    }

    @Test("I3 — the sparkline is 24 whole hours, oldest first")
    func sparklineIsTwentyFourBuckets() async throws {
        var deps = try Support.makeDeps()
        deps.harnesses = StubInventory(rows: [])
        let (_, body) = await Self.answer("/insights", &deps)
        let parsed = try JSONParser.parse(body)
        let hours = try #require(parsed.member("callsPerHour")?.asArray)
        #expect(hours.count == 24)
        let first = hours.first?.member("hourStart")?.asString?.string
        let last = hours.last?.member("hourStart")?.asString?.string
        #expect(first != nil && last != nil)
        #expect((first ?? "") < (last ?? ""), "oldest first, so a chart reads left to right in time")
    }

    @Test("I4 — a harness that cannot be attributed carries null and a reason, never a zero")
    func unattributableHarnessesCarryNull() async throws {
        var deps = try Support.makeDeps()
        deps.harnesses = StubInventory(rows: [
            Self.report(.claudeCode, route: .directHTTP(name: "router", url: "u")),
            Self.report(.cursor, route: .directHTTP(name: "router", url: "u")),
            Self.report(.opencode)
        ])
        let (_, body) = await Self.answer("/insights", &deps)
        let parsed = try JSONParser.parse(body)
        let rows = try #require(parsed.member("callsByHarness")?.asArray)
        #expect(rows.count == 3, "a bar is drawn for every detected harness, including at zero")

        let claude = rows.first { $0.member("harness")?.asString?.string == "claudeCode" }
        #expect(claude?.member("calls")?.asNumber == 0, "measured and never seen is the finding")
        #expect(claude?.member("reason") == .null)

        // `cursor-agent` execs a bundled node, so its calls arrive as `node` and belong to nobody.
        // A zero here would be a fabricated finding, which is worse than no bar.
        let cursor = rows.first { $0.member("harness")?.asString?.string == "cursor" }
        #expect(cursor?.member("calls") == .null)
        #expect(cursor?.member("reason")?.asString?.string.contains("node") == true)
    }
}
