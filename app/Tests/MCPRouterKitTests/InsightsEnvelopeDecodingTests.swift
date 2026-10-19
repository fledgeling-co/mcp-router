import Foundation
import Testing
@testable import MCPRouterKit

/// `GET /insights` decodes into the Mac board's model, with every member the model requires.
///
/// The sample is one envelope the TypeScript route answered, captured by running the compiled route over a
/// fixture call log, so the wire pinned here is the wire the router sends. Each required member is checked by
/// removing it in turn: a router that stops sending one must fail to decode, rather than give the board a
/// blank where a count should be.
@Suite("Insights envelope decoding")
struct InsightsEnvelopeDecodingTests {
    // The sample is the router's wire, byte for byte, so its long reason string is not rewrapped.
    // swiftlint:disable line_length
    static let sample = Data(#"""
    {
      "generatedAt": "2026-10-19T00:52:43.210Z",
      "windowHours": 24,
      "windowStart": "2026-10-18T01:00:00.000Z",
      "logHorizon": "2026-10-18T20:52:43.209Z",
      "children": {
        "alive": 0,
        "declared": 2
      },
      "calls": {
        "total": 4,
        "failed": 1,
        "unreadableLines": 1
      },
      "resident": null,
      "callsByHarness": [
        {
          "harness": "claudeCode",
          "displayName": "Claude Code",
          "calls": 2,
          "reason": null
        },
        {
          "harness": "codexCLI",
          "displayName": "Codex CLI",
          "calls": null,
          "reason": "calls arrive as codex \u2014 the Codex and ChatGPT entries are the same binary, so a count cannot be split"
        }
      ],
      "otherCalls": 2,
      "dutyCycle": {
        "uptimeSeconds": 0,
        "servers": [
          {
            "server": "alpha-server",
            "aliveSeconds": 0
          },
          {
            "server": "beta-server",
            "aliveSeconds": 90
          }
        ]
      },
      "callsPerHour": [
        {
          "hourStart": "2026-10-18T01:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T02:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T03:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T04:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T05:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T06:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T07:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T08:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T09:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T10:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T11:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T12:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T13:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T14:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T15:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T16:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T17:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T18:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T19:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T20:00:00.000Z",
          "calls": 1
        },
        {
          "hourStart": "2026-10-18T21:00:00.000Z",
          "calls": 1
        },
        {
          "hourStart": "2026-10-18T22:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-18T23:00:00.000Z",
          "calls": 0
        },
        {
          "hourStart": "2026-10-19T00:00:00.000Z",
          "calls": 2
        }
      ],
      "analyst": null
    }
    """#.utf8)
    // swiftlint:enable line_length

    @Test("the router's envelope decodes, and carries the figures the board draws from")
    func envelopeDecodes() throws {
        let response = try JSONDecoder().decode(InsightsResponse.self, from: Self.sample)

        #expect(response.windowHours == 24)
        #expect(response.calls == CallTotals(total: 4, failed: 1, unreadableLines: 1))
        #expect(response.otherCalls == 2, "two calls are not claimed by any harness")
        #expect(response.callsPerHour.count == 24)
        #expect(response.hasHistory)
        #expect(response.analyst == nil, "the capture was taken with no analyst wired in")
        #expect(response.resident == nil, "no child process was running when this was captured")
        #expect(response.dutyCycle?.servers.map(\.server) == ["alpha-server", "beta-server"])
        #expect(response.dutyCycle?.servers.first?.aliveSeconds == 0, "never opened: a row at zero")
        #expect(response.dutyCycle?.servers.last?.aliveSeconds == 90)
    }

    @Test("a harness with a count decodes to it, and one without decodes to nil with its reason")
    func unattributedHarnessDecodesAsNil() throws {
        let response = try JSONDecoder().decode(InsightsResponse.self, from: Self.sample)
        let claude = response.callsByHarness.first { $0.harness == "claudeCode" }
        let codex = response.callsByHarness.first { $0.harness == "codexCLI" }

        #expect(claude?.calls == 2)
        #expect(claude?.reason == nil)
        #expect(codex?.calls == nil, "a zero here would be a fabricated finding")
        #expect(codex?.reason?.contains("codex") == true)
    }

    @Test("an empty window decodes with no horizon, so the board says so rather than guessing one")
    func emptyWindowDecodes() throws {
        var root = try #require(JSONSerialization.jsonObject(with: Self.sample) as? [String: Any])
        root["logHorizon"] = NSNull()
        let body = try JSONSerialization.data(withJSONObject: root)

        let response = try JSONDecoder().decode(InsightsResponse.self, from: body)
        #expect(response.logHorizon == nil)
        #expect(!response.hasHistory)
    }

    @Test("each member the model requires fails to decode when the router does not send it")
    func requiredMembersFailWhenAbsent() throws {
        let required: [[String]] = [
            ["generatedAt"],
            ["windowHours"],
            ["windowStart"],
            ["children"],
            ["children", "alive"],
            ["children", "declared"],
            ["calls"],
            ["calls", "total"],
            ["calls", "failed"],
            ["calls", "unreadableLines"],
            ["callsByHarness"],
            ["otherCalls"],
            ["callsPerHour"]
        ]
        for path in required {
            let body = try Self.sample(removing: path)
            #expect(throws: (any Error).self, "\(path.joined(separator: ".")) is required") {
                try JSONDecoder().decode(InsightsResponse.self, from: body)
            }
        }
    }

    /// The sample with the member at `path` removed, so one required member can be taken out at a time.
    private static func sample(removing path: [String]) throws -> Data {
        let root = try #require(JSONSerialization.jsonObject(with: sample) as? [String: Any])
        return try JSONSerialization.data(withJSONObject: removing(path, from: root))
    }

    private static func removing(_ path: [String], from object: [String: Any]) -> [String: Any] {
        var copy = object
        guard let head = path.first else { return copy }
        if path.count == 1 {
            copy.removeValue(forKey: head)
        } else if let child = copy[head] as? [String: Any] {
            copy[head] = removing(Array(path.dropFirst()), from: child)
        }
        return copy
    }
}
