import Foundation
import Testing
@testable import RouterCore

/// `GET /invocations` and `GET /invocations/export`, driven through `ControlHandler.handle`.
///
/// The absent-dependency case is the one worth a test here rather than a comment. `ControlDeps`'
/// optional ports have shipped `nil` in `RouterServiceDispatch` twice with a green suite —
/// `registry` and `authFlow`, recorded as `control-registry-search` and `D-p1-a` — which is a 503 on
/// every route in a family that no unit test can see. This asserts the refusal is the one the spec
/// promises rather than a 404 or an empty body.
@Suite("The invocations routes")
struct ControlInvocationRoutesTests {
    typealias Support = ControlAuthSupport

    private struct StubReporter: InvocationReporting {
        let fixed: CapabilityUseWindow
        func window(nowMilliseconds _: Double, days _: Int) -> CapabilityUseWindow {
            fixed
        }
    }

    private static func request(_ path: String, query: String? = nil) -> ControlAPIRequest {
        var pairs: [(name: String, value: String)] = []
        if let query, let separator = query.firstIndex(of: "=") {
            pairs.append((
                name: String(query[query.startIndex ..< separator]),
                value: String(query[query.index(after: separator)...])
            ))
        }
        return ControlAPIRequest(
            method: "GET", encodedPath: path, query: pairs, headers: [], body: nil
        )
    }

    private static func window(days: Int = 7) -> CapabilityUseWindow {
        CapabilityUseWindow(
            generatedAt: "2026-08-27T00:00:00.000Z",
            days: days,
            windowStart: "2026-08-21",
            horizon: "2026-08-22T00:00:00.000Z",
            ledgerHorizon: "2026-06-18T03:32:37.892Z",
            rows: [CapabilityUseRow(
                kind: .skill,
                name: "trawl",
                version: "1.4.2",
                runs: 3,
                perDay: [0, 0, 1, 0, 2, 0, 0],
                lastUsed: "2026-08-26T09:00:00.000Z"
            )],
            supersededRuns: 4,
            unestablishedRuns: 9,
            harnesses: [HarnessInvocationCount(harness: "claude-code", runs: 16)],
            accounting: TranscriptAccounting()
        )
    }

    private static func body(_ response: ControlAPIResponse) -> String {
        guard case let .bytes(bytes) = response.body else { return "" }
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: bytes, as: UTF8.self)
    }

    @Test("With no reporter the route names what is missing rather than serving an empty history")
    func absentReporterIsA503() async throws {
        var deps = try Support.makeDeps()
        deps.invocations = nil
        let response = await ControlHandler(token: Support.token).handle(
            Self.request("/invocations"), &deps
        )
        #expect(response.handled)
        #expect(response.status == 503)
        // The exact sentence, not a substring that any refusal would satisfy: what makes this a
        // measurement is that the reply distinguishes a router nobody pointed anywhere from a
        // machine on which nothing ran.
        #expect(Self.body(response).contains("has not been pointed at a transcript corpus"))
    }

    @Test("The window is served as JSON with the unattributed figures beside the rows")
    func windowIsServed() async throws {
        var deps = try Support.makeDeps()
        deps.invocations = StubReporter(fixed: Self.window())
        let response = await ControlHandler(token: Support.token).handle(
            Self.request("/invocations"), &deps
        )
        #expect(response.status == 200)
        let text = Self.body(response)
        #expect(text.contains(#""name":"trawl""#))
        #expect(text.contains(#""supersededRuns":4"#))
        #expect(text.contains(#""unestablishedRuns":9"#))
        #expect(text.contains(#""ledgerHorizon":"2026-06-18T03:32:37.892Z""#))
    }

    @Test("The export answers CSV only when asked, and JSON otherwise")
    func exportHonoursTheFormat() async throws {
        var deps = try Support.makeDeps()
        deps.invocations = StubReporter(fixed: Self.window())
        let handler = ControlHandler(token: Support.token)
        let csv = await handler.handle(
            Self.request("/invocations/export", query: "format=csv"), &deps
        )
        #expect(csv.status == 200)
        #expect(csv.headers.contains { $0.name == "content-type" && $0.value.hasPrefix("text/csv") })
        #expect(Self.body(csv).hasPrefix("kind,name,version,runs,lastUsed,perDay"))
        // No `Access-Control-Allow-Origin` anywhere, matching every other reply on this API: a page
        // may be able to send a simple request, it must never read one back.
        #expect(!csv.headers.contains { $0.name.lowercased() == "access-control-allow-origin" })

        let json = await handler.handle(Self.request("/invocations/export"), &deps)
        #expect(json.headers.contains { $0.name == "content-type" && $0.value == "application/json" })
    }

    /// A day count arrives off the wire and is multiplied into a bucket array, so an unbounded one is
    /// an allocation a query string can ask for — the shape `UsageStore.recent`'s own note records
    /// as reachable and unclamped for `?limit=`.
    @Test("The day count is coerced and clamped rather than trusted")
    func daysAreClamped() {
        #expect(ControlHandler.requestedDays(Self.request("/invocations")) == 7)
        #expect(ControlHandler.requestedDays(Self.request("/invocations", query: "days=30")) == 30)
        #expect(ControlHandler.requestedDays(Self.request("/invocations", query: "days=abc")) == 7)
        #expect(ControlHandler.requestedDays(Self.request("/invocations", query: "days=0")) == 7)
        #expect(ControlHandler.requestedDays(Self.request("/invocations", query: "days=-4")) == 7)
        #expect(
            ControlHandler.requestedDays(Self.request("/invocations", query: "days=1e300"))
                == ControlHandler.invocationMaximumDays
        )
    }

    /// `/invocationsx` shares a prefix with an owned path and is not owned — the negative an
    /// exact-match arm exists for, and the one a `hasPrefix` would get wrong.
    @Test("A path that merely shares the prefix is not claimed")
    func neighbouringPathIsNotClaimed() {
        #expect(ControlPaths.isControlPath("/invocations"))
        #expect(ControlPaths.isControlPath("/invocations/export"))
        #expect(!ControlPaths.isControlPath("/invocationsx"))
        #expect(!ControlPaths.isControlPath("/invocations/anything-else"))
    }
}
