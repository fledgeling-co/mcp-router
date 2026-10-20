import Foundation
import Testing
@testable import MCPRouterKit

/// The window the Insights board asks for, and the two windows the router answered with it.
///
/// The samples are the TypeScript route's answers, captured by `GET /insights?window=7d` and `GET /insights`
/// over one fixture call log, so the wire pinned here is the wire the router sends. The seven-day answer is
/// the one that matters: observation began two days before it was taken, so its window is not whole, and
/// its unobserved hours are `null`.
@Suite("Insights window decoding")
struct InsightsWindowDecodingTests {
    /// The two captured answers, read from `app/Tests/Captured`. They are the router's wire as JSON, kept as
    /// files so they do not inflate the test source.
    static func captured(_ name: String) throws -> Data {
        // `#filePath` is `app/Tests/MCPRouterKitTests/<this file>`, so two levels up is `app/Tests`.
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: tests.appending(path: "Captured/\(name)"))
    }

    @Test("a seven-day answer decodes to 168 buckets, and the unobserved ones are nil rather than zero")
    func sevenDayDecodes() throws {
        let sevenDay = try Self.captured("insights-window-7d.json")
        let response = try JSONDecoder().decode(InsightsResponse.self, from: sevenDay)
        #expect(response.windowHours == 168)
        #expect(response.callsPerHour.count == 168)
        let unobserved = response.callsPerHour.filter { $0.calls == nil }.count
        #expect(unobserved == 120, "the 120 hours before observation are null on the wire and in the model")
        #expect(response.callsPerHour.compactMap(\.calls).allSatisfy { $0 >= 0 })
    }

    @Test("a seven-day answer says it is not whole, and when observation began")
    func sevenDayIsIncomplete() throws {
        let sevenDay = try Self.captured("insights-window-7d.json")
        let response = try JSONDecoder().decode(InsightsResponse.self, from: sevenDay)
        #expect(response.windowComplete == false)
        #expect(response.observedSince == "2026-10-18T02:46:25.116Z")
        #expect(response.retention?.days == 7)
        #expect(response.retention?.capMegabytes == 256)
        #expect(response.retention?.capped.records == 0, "nothing was removed by the cap in this run")
    }

    @Test("a day answer whose window observation predates is whole, and every hour is a count")
    func oneDayIsComplete() throws {
        let oneDay = try Self.captured("insights-window-24h.json")
        let response = try JSONDecoder().decode(InsightsResponse.self, from: oneDay)
        #expect(response.windowHours == 24)
        #expect(response.windowComplete == true)
        #expect(response.callsPerHour.count == 24)
        #expect(response.callsPerHour.allSatisfy { $0.calls != nil })
        #expect(response.calls.total == 4, "the record three days old is outside the day")
    }

    @Test("a router that does not report coverage decodes with the coverage members nil, and makes no claim")
    func absentCoverageIsNil() throws {
        // The same shape the Swift router sends today: no observedSince, windowComplete or retention.
        let oneDay = try Self.captured("insights-window-24h.json")
        var root = try #require(JSONSerialization.jsonObject(with: oneDay) as? [String: Any])
        root.removeValue(forKey: "observedSince")
        root.removeValue(forKey: "windowComplete")
        root.removeValue(forKey: "retention")
        let data = try JSONSerialization.data(withJSONObject: root)
        let response = try JSONDecoder().decode(InsightsResponse.self, from: data)
        #expect(response.observedSince == nil)
        #expect(response.windowComplete == nil)
        #expect(response.retention == nil)
        #expect(response.calls.total == 4, "the figures still decode without the coverage members")
    }

    @Test("the period's hours and wire spelling are the window the router is asked for")
    func periodSpelling() {
        #expect(InsightsPeriod.last24Hours.rawValue == "24h")
        #expect(InsightsPeriod.last7Days.rawValue == "7d")
        #expect(InsightsPeriod.last24Hours.hours == 24)
        #expect(InsightsPeriod.last7Days.hours == 168)
        #expect(
            InsightsPeriod(rawValue: "30d") == nil,
            "the board cannot ask for a window the router refuses"
        )
    }

    @Test("the copy names the window the router answered, and states a partial one as partial")
    func copyFollowsTheAnsweredWindow() {
        #expect(InsightsBoardCopy.periodLabel(hours: 24) == "last 24 hours")
        #expect(InsightsBoardCopy.periodLabel(hours: 168) == "last 7 days")
        #expect(InsightsBoardCopy.callsLabel(hours: 168) == "Tool calls, last 7 days")
        #expect(InsightsBoardCopy.callsPerHour(hours: 24) == "Calls per hour, last 24 hours")
        let since = "2026-10-18T02:46:25.116Z"
        let caption = InsightsBoardCopy.incompleteCaption(observedSince: since, hours: 168)
        #expect(caption.contains("last 7 days"))
        #expect(caption.contains("not a whole one"))
        let answered = InsightsBoardCopy.answeredCaption(answered: 24, asked: 168)
        #expect(answered.contains("answered the last 24 hours, not the last 7 days"))
    }

    @Test("the live client asks for the window it names, and reads it back from the route")
    func liveClientSendsTheWindow() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        let sevenDay = try Self.captured("insights-window-7d.json")
        let body = try #require(String(bytes: sevenDay, encoding: .utf8))
        stub.on("GET", "/insights", .json(200, body))
        let client = LiveControlAPIClient(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            store: InMemoryTokenStore("test-token"),
            tokenFile: RouterTokenFile(url: URL(fileURLWithPath: "/nonexistent/control.token")),
            log: ControlLog()
        )
        let response = try await client.insights(period: .last7Days)
        #expect(response.windowHours == 168)
        #expect(stub.requests.contains { $0.hasPrefix("GET /insights?window=7d") })
    }
}
