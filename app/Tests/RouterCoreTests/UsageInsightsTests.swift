import Foundation
import Testing
@testable import RouterCore

/// The fold that turns the call log into the Insights board's three counted charts.
///
/// Every assertion here is about a boundary rather than a middle: which record is inside the window
/// and which is one millisecond outside it, which hour a record at `:59:59.999` belongs to, and what
/// happens to a line nobody can read. The middle of this function has never been where it is wrong.
@Suite("Usage insights window")
struct UsageInsightsTests {
    /// 2026-08-22T12:30:00.000Z, so the current hour is 12:00 and a 24-hour window starts at
    /// 13:00 the previous day.
    private let now = 1_787_401_800_000.0

    private func record(
        _ timestamp: String, client: String? = "claude", ok: Bool = true, server: String = "s1"
    ) -> String {
        JSStringify.compact(UsageRecord(
            ts: timestamp, server: server, tool: "t", ok: ok, ms: 1, cold: false, client: client
        ).value)
    }

    @Test("the window is whole hours, oldest first, and there are exactly as many as asked for")
    func bucketsAreWholeHoursOldestFirst() {
        let reading = UsageInsights.over(lines: [], nowMilliseconds: now, windowHours: 24)
        #expect(reading.hours.count == 24)
        #expect(JSDate.iso8601(milliseconds: reading.hours[0].startMilliseconds)
            == "2026-08-21T13:00:00.000Z")
        #expect(JSDate.iso8601(milliseconds: reading.hours[23].startMilliseconds)
            == "2026-08-22T12:00:00.000Z")
        // The last bucket is the hour in progress, not "now minus 24h to the millisecond". A
        // window cut at the instant makes the first and last buckets partial, and a chart whose
        // end columns are short for arithmetic reasons reads as a fall in traffic.
        #expect(reading.windowStartMilliseconds == reading.hours[0].startMilliseconds)
    }

    @Test("a record one millisecond before the window is out, and one at its first instant is in")
    func windowBoundaryIsInclusiveAtTheStart() {
        let reading = UsageInsights.over(
            lines: [
                record("2026-08-21T12:59:59.999Z"),
                record("2026-08-21T13:00:00.000Z")
            ],
            nowMilliseconds: now, windowHours: 24
        )
        #expect(reading.totalCalls == 1)
        #expect(reading.horizon == "2026-08-21T13:00:00.000Z")
        #expect(reading.hours[0].calls == 1)
    }

    @Test("the hour boundary puts :59:59.999 in the hour it happened in")
    func hourBoundaryDoesNotBleed() {
        let reading = UsageInsights.over(
            lines: [
                record("2026-08-22T10:59:59.999Z"),
                record("2026-08-22T11:00:00.000Z")
            ],
            nowMilliseconds: now, windowHours: 24
        )
        #expect(reading.hours[21].calls == 1, "the 10:00 bucket")
        #expect(reading.hours[22].calls == 1, "the 11:00 bucket")
    }

    @Test("a line nobody can read is counted, never bucketed and never silently dropped")
    func unreadableLinesAreAccounted() {
        let reading = UsageInsights.over(
            lines: [
                record("2026-08-22T11:00:00.000Z"),
                "{not json",
                // A torn last line, which is normal after a hard kill.
                #"{"ts":"2026-08-22T11:00:00.000Z","server":"s1","to"#,
                // Parses, and its timestamp is not the fixed-width UTC shape this reader compares
                // by. Bucketing it by its first thirteen characters would put it wherever they
                // happened to land, which is the silent mis-count this branch exists to refuse.
                #"{"ts":"22/08/2026 11:00","server":"s1","tool":"t","ok":true,"ms":1,"cold":false}"#
            ],
            nowMilliseconds: now, windowHours: 24
        )
        #expect(reading.totalCalls == 1)
        #expect(reading.unreadableLines == 3)
    }

    @Test("failures are counted from ok, and callers rank by calls then by name")
    func failuresAndCallerRanking() {
        let reading = UsageInsights.over(
            lines: [
                record("2026-08-22T11:00:00.000Z", client: "claude"),
                record("2026-08-22T11:01:00.000Z", client: "claude"),
                record("2026-08-22T11:02:00.000Z", client: "agy", ok: false),
                record("2026-08-22T11:03:00.000Z", client: "grok"),
                // No client at all: the peer could not be named, which the reference records
                // rather than dropping. It has to land somewhere or the bars stop summing.
                record("2026-08-22T11:04:00.000Z", client: nil)
            ],
            nowMilliseconds: now, windowHours: 24
        )
        #expect(reading.totalCalls == 5)
        #expect(reading.failedCalls == 1)
        #expect(reading.callers.map(\.client) == ["claude", "agy", "grok", UsageInsights.unattributed])
        #expect(reading.callers.map(\.calls) == [2, 1, 1, 1])
    }

    @Test("an empty window reports no horizon, which is how a board knows to say so")
    func emptyWindowHasNoHorizon() {
        let reading = UsageInsights.over(
            lines: [record("2020-01-01T00:00:00.000Z")], nowMilliseconds: now, windowHours: 24
        )
        #expect(reading.totalCalls == 0)
        #expect(reading.horizon == nil)
        #expect(reading.hours.allSatisfy { $0.calls == 0 })
    }

    @Test("hourKey refuses anything that is not the fixed-width UTC shape")
    func hourKeyIsShapeChecked() {
        #expect(UsageInsights.hourKey("2026-08-22T11:00:00.000Z") == "2026-08-22T11")
        #expect(UsageInsights.hourKey("2026-08-22 11:00:00") == nil)
        #expect(UsageInsights.hourKey("22/08/2026 11") == nil)
        #expect(UsageInsights.hourKey("2026-08-22T1") == nil)
    }
}
