import Foundation
import Testing
@testable import MCPRouterKit

/// The two boards' wire types and the copy that belongs to them.
///
/// Three properties are load-bearing and each has its own reason to be checked here rather than by
/// eye: a fifth reading must fail to decode, a count that does not exist must not arrive as zero,
/// and a bar's fill must be the text-safe ink rather than the published hue.
@Suite("M22 board models")
struct M22BoardModelTests {
    // MARK: - The four readings

    @Test("a fifth reading fails decoding rather than defaulting into one of the four")
    func fifthReadingFailsDecoding() throws {
        let body = Data(#"{"state":"wired-over-carrier-pigeon"}"#.utf8)
        struct Row: Decodable { let state: HarnessReading }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Row.self, from: body)
        }
        // And each of the four does decode, so the refusal above is about the value rather than
        // about the shape.
        for reading in HarnessReading.allCases {
            let json = Data(#"{"state":"\#(reading.rawValue)"}"#.utf8)
            #expect(try JSONDecoder().decode(Row.self, from: json).state == reading)
        }
    }

    @Test("the sentence belongs to the case, and the shim's names its cost")
    func sentencesBelongToTheCase() {
        let shim = HarnessStatus.routedViaShim(bridge: "mcp-remote")
        #expect(shim.sentence.contains("mcp-remote"))
        #expect(shim.sentence.contains("one extra process per session"))
        #expect(shim.label == "Routed through a stdio shim")

        // Every reading says something, and no two say the same thing — which is what stops a
        // surface reaching for a string of its own when one of them reads as a placeholder.
        let all: [HarnessStatus] = [
            .notRouted(entries: 18, overlapping: 10),
            .routedOverHTTP,
            shim,
            .routedWithDirectServers(transport: .http, bridge: nil, duplicates: 4, entries: 7)
        ]
        #expect(Set(all.map(\.sentence)).count == all.count)
        #expect(all.allSatisfy { !$0.sentence.isEmpty })
    }

    @Test("a status is read off the row, never assembled from its counts at a call site")
    func statusComesFromTheRow() {
        let row = DetectedHarness(
            harness: "grokCLI", displayName: "grok", path: "~/.grok/config.toml", exists: true,
            state: .routedViaShim, route: .stdioShim, bridge: "mcp-remote",
            entries: 0, duplicateCount: 0,
            httpCapability: "speaks streamable HTTP", capability: .measured
        )
        guard case let .routedViaShim(bridge) = HarnessStatus(row) else {
            Issue.record("the shim reading must survive the round trip")
            return
        }
        #expect(bridge == "mcp-remote")
    }

    @Test("a routed harness that also declares direct servers reads as that, not as routed")
    func duplicatesWinOverTransport() {
        let row = DetectedHarness(
            harness: "codexCLI", displayName: "Codex CLI", path: "~/.codex/config.toml",
            exists: true, state: .routedWithDirectServers, route: .stdioShim, bridge: "mcp-remote",
            entries: 7, duplicateCount: 4,
            httpCapability: "speaks streamable HTTP", capability: .measured
        )
        let status = HarnessStatus(row)
        #expect(status.label == "Routed, plus 7 direct servers")
        // The shim's cost survives inside the duplicate reading. It does not stop being real
        // because there is a second finding on the same row.
        #expect(status.sentence.contains("mcp-remote"))
        #expect(status.sentence.contains("4 of its 7"))
    }

    // MARK: - The counts that are absent rather than zero

    @Test("a harness with no attributable count decodes as absent, never as zero")
    func absentCountIsNotZero() throws {
        let body = Data("""
        {"harness":"cursor","displayName":"Cursor","calls":null,"reason":"calls arrive as node"}
        """.utf8)
        let row = try JSONDecoder().decode(HarnessCallCount.self, from: body)
        #expect(row.calls == nil)
        #expect(row.reason == "calls arrive as node")

        // And a measured zero survives as a zero, which is the reading the whole chart exists for.
        let zeroed = Data(#"{"harness":"geminiCLI","displayName":"Gemini CLI","calls":0}"#.utf8)
        #expect(try JSONDecoder().decode(HarnessCallCount.self, from: zeroed).calls == 0)
    }

    @Test("no history is a fact the router reports, not an absence a surface infers")
    func historyIsReadFromTheHorizon() {
        #expect(!InsightsFixtures.thin.hasHistory)
        #expect(InsightsFixtures.populated.hasHistory)
        // The thin window still carries real counts and a full 24 buckets. Emptiness here is the
        // horizon being nil, not the numbers being zero — a response full of zeros would draw a
        // flat chart and imply a quiet day.
        #expect(InsightsFixtures.thin.callsPerHour.count == 24)
    }

    // MARK: - The bar fills

    @Test("both bar fills are text-safe inks rather than the published indicator hues")
    func barFillsAreTheInks() {
        for token in [InsightsBoardCopy.callsBarFill, InsightsBoardCopy.dutyBarFill] {
            // `text` rather than `pairedWithAWord`, which is what `--live` and `--attn` carry. The
            // published hues measure 2.22:1 and 2.31:1 on the light ground, under the 3:1 a
            // graphical object wants against a near-white track.
            #expect(token.contrastRole == .text, "\(token.rawValue) is not a text-safe token")
            #expect(token != .live && token != .attention && token != .fail)
        }
        #expect(InsightsBoardCopy.callsBarFill == .liveInk)
        #expect(InsightsBoardCopy.dutyBarFill == .attentionInk)
    }

    // MARK: - The finding

    @Test("the finding is a count taken off the rows it summarises, never a judgement")
    func findingIsCounted() throws {
        let finding = try #require(HarnessBoardCopy.finding(HarnessFixtures.populated))
        let worst = try #require(
            HarnessFixtures.populated.max { $0.duplicateCount < $1.duplicateCount }
        )
        #expect(finding.contains(String(worst.entries)))
        #expect(finding.contains(String(worst.duplicateCount)))
        #expect(finding.contains(worst.displayName))

        // Nothing to say is said by saying nothing, rather than by a reassuring sentence.
        let clean = HarnessFixtures.populated.filter { $0.duplicateCount == 0 }
        #expect(HarnessBoardCopy.finding(clean) == nil)

        // And an unreadable row never becomes the finding: every count on it is the empty report's
        // zero, so a headline built from it would be a number nobody took.
        #expect(HarnessBoardCopy.finding(
            HarnessFixtures.partiallyUnreadable.filter { $0.unreadable != nil }
        ) == nil)
    }

    // MARK: - The duty-cycle caption

    @Test("the duty-cycle caption states the mechanism and asserts no figure")
    func dutyCycleCaptionIsNotAClaim() {
        let caption = InsightsBoardCopy.dutyCycleCaption
        // The brief's own caption reads "before the router, every one of these sat at 100%", which
        // is a number about a world this router never ran — the thing DESIGN.md §6 forbids, two
        // paragraphs before the brief says no number here is modelled.
        #expect(!caption.contains("%"))
        #expect(!caption.lowercased().contains("before the router"))
        #expect(caption.contains("since the router started"))
    }

    @Test("the freshness line reads as a sentence at both ends of shortAgo's own boundary")
    func freshnessLineReadsAsASentence() {
        // Under five seconds `shortAgo` returns the WORD "now", and above it a duration. Composing
        // one sentence for both rendered "Read now ago" in the shipped app. The boundary is the
        // test, per SWIFT_PRACTICES §7 — testing the middle would have passed on the day this
        // shipped.
        let taken = Date(timeIntervalSince1970: 1_787_401_800)
        let iso = "2026-08-22T12:30:00.000Z"
        #expect(HarnessBoardCopy.readAt(iso, now: taken) == "Read just now")
        #expect(HarnessBoardCopy.readAt(iso, now: taken.addingTimeInterval(4)) == "Read just now")
        #expect(HarnessBoardCopy.readAt(iso, now: taken.addingTimeInterval(5)) == "Read 5s ago")
        #expect(HarnessBoardCopy.readAt(iso, now: taken.addingTimeInterval(600)) == "Read 10m ago")
        // And nothing composes a sentence with the bare word in it, at any age.
        for seconds in stride(from: 0.0, through: 200_000, by: 997) {
            let line = HarnessBoardCopy.readAt(iso, now: taken.addingTimeInterval(seconds))
            #expect(!line.contains("now ago"), "\(line) is not a sentence")
        }
    }

    @Test("the failure rate carries its own numerator and denominator")
    func failureRateShowsItsRatio() {
        let totals = CallTotals(total: 9418, failed: 12, unreadableLines: 0)
        #expect(InsightsBoardCopy.failureRate(totals) == "0.13%")
        #expect(InsightsBoardCopy.failureProvenance(totals) == "12 of 9418")
        // No calls means no rate. A "0.00%" over an empty window is a claim about reliability that
        // nothing measured.
        #expect(InsightsBoardCopy.failureRate(CallTotals(total: 0, failed: 0, unreadableLines: 0))
            == "—")
    }
}
