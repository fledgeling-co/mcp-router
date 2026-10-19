import Foundation
import Testing
@testable import MCPRouterKit

/// `GET /insights` with its `analyst` member decodes into the Mac board's analyst model, with every member
/// the model requires. Ported with the TypeScript analyst (F7, spec-F7.md §4 and §3.8).
///
/// The two analyst samples are captured from the TypeScript route: `analystRun` after one run over a fixture
/// home with three `docker logs` lines and a judge stub, and `analystNotRun` before any run. The home
/// directory is shortened to /Users/tester. The envelope around them is the smallest one `InsightsResponse`
/// requires.
@Suite("Insights analyst decoding")
struct InsightsAnalystDecodingTests {
    /// The envelope with the analyst member left for each test to supply.
    static let envelope = Data(#"""
    {
      "generatedAt": "2026-10-19T00:52:43.210Z",
      "windowHours": 24,
      "windowStart": "2026-10-18T01:00:00.000Z",
      "children": { "alive": 0, "declared": 0 },
      "calls": { "total": 0, "failed": 0, "unreadableLines": 0 },
      "callsByHarness": [],
      "otherCalls": 0,
      "callsPerHour": [],
      "analyst": null
    }
    """#.utf8)

    /// The analyst member after one run.
    static let analystRun = Data(#"""
    {
      "primary": { "lane": "claude", "model": "claude-haiku-4-5", "label": "Claude CLI · haiku" },
      "fallback": { "lane": "grok", "model": "grok-4.6", "label": "Grok CLI · grok-4.6 medium" },
      "cadence": "sixHourly",
      "cadenceLabel": "Every 6 hours",
      "scheduled": false,
      "nextRunAt": "2023-11-15T04:13:20.000Z",
      "lane": { "lane": "claude", "model": "claude-haiku-4-5", "label": "Claude CLI · haiku" },
      "ranAt": "2023-11-14T22:13:20.000Z",
      "linesRead": 3,
      "discarded": 1,
      "findings": 1,
      "usedFallback": false,
      "rejectedFindings": 0,
      "candidatesUnavailable": false,
      "stores": [
        {
          "harness": "claudeCode",
          "path": "/Users/tester/.claude/history.jsonl",
          "read": true,
          "lines": 3,
          "discarded": 1,
          "reason": null
        },
        {
          "harness": "codexCLI",
          "path": "/Users/tester/.codex/history.jsonl",
          "read": false,
          "lines": 0,
          "discarded": 0,
          "reason": "no file at this path"
        },
        {
          "harness": "grokCLI",
          "path": "/Users/tester/.grok/sessions",
          "read": false,
          "lines": 0,
          "discarded": 0,
          "reason": "this directory could not be listed"
        },
        {
          "harness": "geminiCLI",
          "path": "/Users/tester/.gemini/history",
          "read": false,
          "lines": 0,
          "discarded": 0,
          "reason": "this directory could not be listed"
        },
        {
          "harness": "cursor",
          "path": "/Users/tester/.cursor/chats",
          "read": false,
          "lines": 0,
          "discarded": 0,
          "reason": "this store is SQLite; the analyst reads JSON Lines only"
        }
      ],
      "recent": [
        {
          "id": "analyst-bfffb32d1e0beaf0",
          "entryID": "docker-mcp",
          "subject": "Docker MCP",
          "sentence": "you read container logs by hand",
          "evidenceCount": 3,
          "judgedBy": "Claude CLI · haiku",
          "signals": ["docker logs"]
        }
      ]
    }
    """#.utf8)

    /// The analyst member before any run: the settings are there, and every reading is absent, not zero.
    static let analystNotRun = Data(#"""
    {
      "primary": { "lane": "claude", "model": "claude-haiku-4-5", "label": "Claude CLI · haiku" },
      "fallback": { "lane": "grok", "model": "grok-4.6", "label": "Grok CLI · grok-4.6 medium" },
      "cadence": "sixHourly",
      "cadenceLabel": "Every 6 hours",
      "scheduled": false,
      "nextRunAt": null,
      "lane": null,
      "ranAt": null,
      "stores": [],
      "recent": []
    }
    """#.utf8)

    @Test("the analyst member decodes into the board's model, with the readings the router counted")
    func analystDecodes() throws {
        let body = try Self.withAnalyst(Self.analystRun)
        let response = try JSONDecoder().decode(InsightsResponse.self, from: body)
        let analyst = try #require(response.analyst)

        #expect(analyst.hasRun, "a run has happened, so there is a reading to draw")
        #expect(analyst.lane?.lane == "claude")
        #expect(analyst.primary.label == "Claude CLI · haiku")
        #expect(analyst.cadenceLabel == "Every 6 hours")
        #expect(analyst.scheduled == false, "the router does not fire the cadence, and says so on the wire")
        #expect(analyst.nextRunAt != nil)
        #expect(analyst.linesRead == 3)
        #expect(analyst.findings == 1)
        #expect(analyst.recent.first?.judgedBy == "Claude CLI · haiku")
        #expect(analyst.unreadStores.map(\.harness) == ["codexCLI", "grokCLI", "geminiCLI", "cursor"])
    }

    @Test("an analyst that has never run decodes, and draws no reading")
    func analystNotRunDecodes() throws {
        let body = try Self.withAnalyst(Self.analystNotRun)
        let response = try JSONDecoder().decode(InsightsResponse.self, from: body)
        let analyst = try #require(response.analyst)

        #expect(analyst.hasRun == false, "present but not run: the board shows its empty state")
        #expect(analyst.lane == nil)
        #expect(analyst.nextRunAt == nil)
        #expect(analyst.stores.isEmpty)
    }

    @Test("each member the analyst model requires fails to decode when the router does not send it")
    func analystRequiredMembersFailWhenAbsent() throws {
        // Paths are relative to the analyst object. Optional members (fallback, nextRunAt, ranAt, reason) are
        // left out on purpose: a model that rejected their absence would reject a router not yet run.
        let required: [[String]] = [
            ["primary"],
            ["primary", "lane"],
            ["primary", "model"],
            ["primary", "label"],
            ["cadence"],
            ["cadenceLabel"],
            ["scheduled"],
            ["stores"],
            ["stores", "harness"],
            ["stores", "path"],
            ["stores", "read"],
            ["stores", "lines"],
            ["stores", "discarded"],
            ["recent"],
            ["recent", "id"],
            ["recent", "entryID"],
            ["recent", "subject"],
            ["recent", "sentence"],
            ["recent", "evidenceCount"],
            ["recent", "judgedBy"],
            ["recent", "signals"]
        ]
        for path in required {
            let body = try Self.withAnalyst(Self.analystRun, removing: path)
            #expect(throws: (any Error).self, "analyst.\(path.joined(separator: ".")) is required") {
                try JSONDecoder().decode(InsightsResponse.self, from: body)
            }
        }
    }

    /// The envelope with `analyst` replaced, and with the member at `path` removed from that analyst object,
    /// so one required member can be taken out at a time.
    private static func withAnalyst(_ analyst: Data, removing path: [String] = []) throws -> Data {
        var root = try #require(JSONSerialization.jsonObject(with: envelope) as? [String: Any])
        let member = try #require(JSONSerialization.jsonObject(with: analyst) as? [String: Any])
        root["analyst"] = removing(path, from: member)
        return try JSONSerialization.data(withJSONObject: root)
    }

    /// Removes the member at `path`. A path element naming an array of objects applies the rest of the path
    /// to each element, so `["recent", "id"]` takes `id` out of every finding.
    private static func removing(_ path: [String], from object: [String: Any]) -> [String: Any] {
        var copy = object
        guard let head = path.first else { return copy }
        if path.count == 1 {
            copy.removeValue(forKey: head)
        } else if let child = copy[head] as? [String: Any] {
            copy[head] = removing(Array(path.dropFirst()), from: child)
        } else if let items = copy[head] as? [[String: Any]] {
            copy[head] = items.map { removing(Array(path.dropFirst()), from: $0) }
        }
        return copy
    }
}
