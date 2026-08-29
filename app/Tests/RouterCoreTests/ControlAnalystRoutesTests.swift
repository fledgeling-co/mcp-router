import Foundation
import Testing
@testable import RouterCore

/// The analyst's three arms, **through `ControlHandler.handle`** — F7, REQ-030.7 and .8.
///
/// Through the handler rather than by calling the response builders, for the reason
/// `ControlBoardRoutesTests` gives: a missing dispatch arm is not a broken function, and a test that
/// calls the function directly cannot fail when the arm is deleted. Half of what this suite asserts
/// is the *reachability* of the two new paths, which is a property of `ControlPaths` and `handle`
/// rather than of `ControlAnalyst.swift`.
@Suite("F7 · the analyst control routes")
struct ControlAnalystRoutesTests {
    typealias Support = ControlAuthSupport

    /// An analyst a test can put in any state, including the two a real one will not enter on
    /// request: a run already in flight, and a ladder with nothing behind it.
    actor StubAnalyst: AnalystPort {
        var stored: AnalystSettings
        var run: AnalystRunRecord?
        var outcome: Result<AnalystRunRecord, AnalystRunFailure>?
        private(set) var analyseCalls = 0

        init(
            settings: AnalystSettings = AnalystSettings(),
            run: AnalystRunRecord? = nil,
            outcome: Result<AnalystRunRecord, AnalystRunFailure>? = nil
        ) {
            stored = settings
            self.run = run
            self.outcome = outcome
        }

        func settings() -> AnalystSettings {
            stored
        }

        func lastRun() -> AnalystRunRecord? {
            run
        }

        func analyse() async -> Result<AnalystRunRecord, AnalystRunFailure> {
            analyseCalls += 1
            let answer = outcome ?? .success(ControlAnalystRoutesTests.record)
            if case let .success(made) = answer { run = made }
            return answer
        }

        func update(_ patch: JSONValue) -> Result<AnalystSettings, AnalystSettingsRefusal> {
            do {
                stored = try AnalystSettingsCoding.apply(patch, to: stored)
                return .success(stored)
            } catch {
                return .failure(error)
            }
        }
    }

    static let record = AnalystRunRecord(
        lane: .grok, ranAtMilliseconds: 1_700_000_000_000, linesRead: 4210, discardedLines: 96,
        usedFallback: true, rejectedFindings: 1, candidatesUnavailable: false,
        stores: [SessionStoreReport(
            harness: .cursor, path: "/h/.cursor/chats", read: false, lines: 0, discarded: 0,
            reason: "this store is SQLite; the analyst reads JSON Lines only"
        )],
        findings: [AnalystFindingRecord(
            id: "analyst-abc", entryID: "docker-mcp", subject: "Docker MCP",
            sentence: "you read container logs by hand", evidenceCount: 31, judgedBy: .grok,
            signals: ["docker logs"]
        )]
    )

    static func request(
        _ method: String, _ path: String, body: String = "{}", authorized: Bool = true
    ) -> ControlAPIRequest {
        var headers = [(name: "content-type", value: "application/json")]
        if authorized { headers.append((name: "x-mcpr-token", value: Support.token)) }
        return ControlAPIRequest(
            method: method, encodedPath: path, query: [], headers: headers, body: Data(body.utf8)
        )
    }

    static func answer(
        _ method: String,
        _ path: String,
        body: String = "{}",
        authorized: Bool = true,
        _ deps: inout ControlDeps
    ) async -> (status: Int, body: String) {
        let response = await ControlHandler(token: Support.token)
            .handle(request(method, path, body: body, authorized: authorized), &deps)
        guard case let .bytes(bytes) = response.body else { return (response.status, "") }
        // swiftlint:disable:next optional_data_string_conversion
        return (response.status, String(decoding: bytes, as: UTF8.self))
    }

    static func get(_ path: String, _ deps: inout ControlDeps) async -> (status: Int, body: String) {
        let response = await ControlHandler(token: Support.token).handle(
            ControlAPIRequest(method: "GET", encodedPath: path, query: [], headers: [], body: nil),
            &deps
        )
        guard case let .bytes(bytes) = response.body else { return (response.status, "") }
        // swiftlint:disable:next optional_data_string_conversion
        return (response.status, String(decoding: bytes, as: UTF8.self))
    }

    @Test("A1 — with no analyst the member is null and both routes name the missing capability")
    func noAnalyst() async throws {
        var deps = try Support.makeDeps()
        let insights = await Self.get("/insights", &deps)
        #expect(insights.body.contains(#""analyst":null"#))

        let run = await Self.answer("POST", "/insights/analyse", &deps)
        #expect(run.status == 503)
        // Not an empty run. An empty run is indistinguishable from a router that analysed and found
        // nothing, which is the exact reading this route exists to make.
        #expect(run.body.contains("session analysis is unavailable"))

        let patch = await Self.answer(
            "PATCH", "/insights/analyst", body: #"{"cadence":"daily"}"#, &deps
        )
        #expect(patch.status == 503)
    }

    @Test("A2 — an analyst that has never run reports its settings with every reading absent")
    func neverRun() async throws {
        var deps = try Support.makeDeps()
        deps.analyst = StubAnalyst()
        let (status, body) = await Self.get("/insights", &deps)
        #expect(status == 200)
        #expect(body.contains(#""label":"Claude CLI · haiku""#))
        #expect(body.contains(#""cadenceLabel":"Every 6 hours""#))
        // Absent rather than zero. A `linesRead: 0` here would be a measurement of a run that never
        // happened, and the board's two empty states turn on exactly this difference.
        #expect(body.contains(#""ranAt":null"#))
        #expect(body.contains(#""linesRead""#) == false)
    }

    @Test("A3 — the cadence is reported as a preference, never as a schedule")
    func cadenceIsNotASchedule() async throws {
        var deps = try Support.makeDeps()
        deps.analyst = StubAnalyst(run: Self.record)
        let (_, body) = await Self.get("/insights", &deps)
        #expect(body.contains(#""scheduled":false"#))
        #expect(body.contains(#""nextRunAt":"#))
    }

    @Test("A4 — pressing the button changes what a LATER GET reports")
    func analyseChangesTheRead() async throws {
        var deps = try Support.makeDeps()
        let analyst = StubAnalyst()
        deps.analyst = analyst

        let before = await Self.get("/insights", &deps)
        #expect(before.body.contains("docker-mcp") == false)

        let posted = await Self.answer("POST", "/insights/analyse", &deps)
        #expect(posted.status == 200)

        // The outcome, read on the channel the POST did not write: a second, separate GET.
        let after = await Self.get("/insights", &deps)
        #expect(after.body.contains(#""entryID":"docker-mcp""#))
        #expect(after.body.contains(#""linesRead":4210"#))
        #expect(after.body.contains(#""rejectedFindings":1"#))
        #expect(await analyst.analyseCalls == 1)
    }

    @Test("A5 — the store the analyst could not open is on the wire with its reason")
    func unreadStoreIsReported() async throws {
        var deps = try Support.makeDeps()
        deps.analyst = StubAnalyst(run: Self.record)
        let (_, body) = await Self.get("/insights", &deps)
        #expect(body.contains(#""harness":"cursor""#))
        #expect(body.contains(#""read":false"#))
        #expect(body.contains("SQLite"))
    }

    @Test("A6 — a run already in flight is refused rather than doubled")
    func inFlightIs409() async throws {
        var deps = try Support.makeDeps()
        deps.analyst = StubAnalyst(outcome: .failure(.alreadyRunning))
        let (status, body) = await Self.answer("POST", "/insights/analyse", &deps)
        #expect(status == 409)
        #expect(body.contains("already running"))
    }

    @Test("A7 — every rung refusing is a 502 that names which model was unreachable")
    func ladderExhaustedIs502() async throws {
        var deps = try Support.makeDeps()
        deps.analyst = StubAnalyst(
            outcome: .failure(.ladderExhausted(["claude: notInstalled(\"claude\")"]))
        )
        let (status, body) = await Self.answer("POST", "/insights/analyse", &deps)
        #expect(status == 502)
        #expect(body.contains("claude"))
    }

    @Test("A8 — a PATCH takes, and an unknown lane is refused by member name")
    func patchTakesAndRefuses() async throws {
        var deps = try Support.makeDeps()
        let analyst = StubAnalyst()
        deps.analyst = analyst

        let ok = await Self.answer(
            "PATCH", "/insights/analyst", body: #"{"primary":"codex"}"#, &deps
        )
        #expect(ok.status == 200)
        // Read back through GET rather than from the PATCH's own reply.
        let after = await Self.get("/insights", &deps)
        #expect(after.body.contains(#""model":"gpt-5.6-luna""#))
        #expect(await analyst.settings().primary == .codex)

        let refused = await Self.answer(
            "PATCH", "/insights/analyst", body: #"{"primary":"llama"}"#, &deps
        )
        #expect(refused.status == 422)
        #expect(refused.body.contains(#""member":"primary""#))
        #expect(await analyst.settings().primary == .codex)
    }

    @Test("A9 — the dispatch ladder: both paths are claimed, gated, and method-checked")
    func reachability() async throws {
        var deps = try Support.makeDeps()
        deps.analyst = StubAnalyst()

        // Claimed: an unauthorised mutation is 401, which only a path the control API OWNS can
        // answer. An unowned path is `.notHandled` and falls through to /mcp.
        let unauthorised = await Self.answer(
            "POST", "/insights/analyse", authorized: false, &deps
        )
        #expect(unauthorised.status == 401)

        // Claimed and method-checked: GET on the write path is 405, not 404.
        let wrongMethod = await Self.get("/insights/analyse", &deps)
        #expect(wrongMethod.status == 405)

        // NOT claimed: a neighbouring path is not owned, so a typo is not turned into a 405 that
        // reads as "the method is wrong".
        let neighbour = await ControlHandler(token: Support.token).handle(
            Self.request("POST", "/insights/analysex"), &deps
        )
        #expect(neighbour.handled == false)
    }
}
