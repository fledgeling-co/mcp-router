import Foundation

/// Recordings for the two boards M22 adds, **authored in Swift rather than as JSON**.
///
/// `Control/Fixtures` holds bodies captured from a live router, and `parity-fixture.sh` replays
/// every file in it against the running TypeScript reference. `GET /harnesses` and `GET /insights`
/// are Swift-only routes the reference answers 404, so a file there would fail a gate that is
/// working correctly. `SkillFixtures` is authored for the same reason and this follows it.
///
/// Every figure below is plausible rather than measured, and none of it ever reaches a running
/// app: these drive the state matrix and the measurement harness, both of which need the unhappy
/// frames a live machine will not produce on request.
public enum HarnessFixtures {
    /// The ideal frame: all four readings present at once, which is the only arrangement in which
    /// a view's four arms are all exercised.
    public static let populated: [DetectedHarness] = [
        DetectedHarness(
            harness: "claudeCode", displayName: "Claude Code", path: "~/.claude.json",
            exists: true, state: .routedOverHTTP, route: .http, entries: 0, duplicateCount: 0,
            httpCapability: "speaks streamable HTTP — measured on claude, 2026-08-21: "
                + "~/.claude.json carries type:http",
            capability: .measured
        ),
        DetectedHarness(
            harness: "cursor", displayName: "Cursor", path: "~/.cursor/mcp.json",
            exists: true, state: .routedOverHTTP, route: .http, entries: 0, duplicateCount: 0,
            httpCapability: "speaks streamable HTTP — measured on cursor-agent 2026.08.11",
            capability: .measured
        ),
        DetectedHarness(
            harness: "grokCLI", displayName: "grok", path: "~/.grok/config.toml",
            exists: true, state: .routedViaShim, route: .stdioShim, bridge: "mcp-remote",
            entries: 0, duplicateCount: 0,
            httpCapability: "speaks streamable HTTP — measured on grok 1.0.5",
            capability: .measured
        ),
        DetectedHarness(
            harness: "codexCLI", displayName: "Codex CLI", path: "~/.codex/config.toml",
            exists: true, state: .routedWithDirectServers, route: .http, entries: 7,
            duplicateCount: 4,
            duplicates: [
                HarnessDuplicate(harnessName: "dossier", routerName: "dossier", basis: .name),
                HarnessDuplicate(harnessName: "obscura", routerName: "obscura", basis: .name),
                HarnessDuplicate(
                    harnessName: "Ref", routerName: "ref-tools-mcp", basis: .identity
                ),
                HarnessDuplicate(
                    harnessName: "google-search", routerName: "google-search", basis: .name
                )
            ],
            httpCapability: "speaks streamable HTTP — measured on codex 0.146.0",
            capability: .measured
        ),
        DetectedHarness(
            harness: "geminiCLI", displayName: "Gemini CLI",
            path: "~/.gemini/config/mcp_config.json", exists: true, state: .notRouted,
            route: .none, entries: 18, duplicateCount: 10,
            httpCapability: "speaks streamable HTTP — measured on agy 1.1.17",
            capability: .measured
        ),
        DetectedHarness(
            harness: "opencode", displayName: "opencode", path: "~/.config/opencode/opencode.json",
            exists: true, state: .notRouted, route: .none, entries: 0, duplicateCount: 0,
            httpCapability: "streamable HTTP support not established",
            capability: .unknown
        )
    ]

    /// One config the router could not parse, and the rest read normally.
    ///
    /// The frame the mock draws as this board's error state, and the one worth having a fixture
    /// for: an unreadable row arrives as the *empty* report, so every count on it says 0 and
    /// `state` says `not-wired` — byte-identical to the clean unwired row two lines below it. Only
    /// `unreadable` separates them, and only a surface that reads it first renders them apart.
    public static var partiallyUnreadable: [DetectedHarness] {
        var rows = populated
        rows[3] = DetectedHarness(
            harness: "codexCLI", displayName: "Codex CLI", path: "~/.codex/config.toml",
            exists: true,
            unreadable: "~/.codex/config.toml:14812 — unexpected key after table header",
            state: .notRouted, route: .none, entries: 0, duplicateCount: 0,
            httpCapability: "speaks streamable HTTP — measured on codex 0.146.0",
            capability: .measured
        )
        return rows
    }

    public static func response(
        _ rows: [DetectedHarness], readAt: String = "2026-08-22T12:30:00.000Z"
    ) -> HarnessesResponse {
        HarnessesResponse(port: 8879, scope: "global", readAt: readAt, harnesses: rows)
    }
}

/// The Insights board's two frames a live router will not produce to order: a day with traffic in
/// it, and a window with too little history to say anything.
public enum InsightsFixtures {
    public static let generatedAt = "2026-08-22T12:30:00.000Z"
    public static let windowStart = "2026-08-21T13:00:00.000Z"

    /// 24 buckets with a mid-afternoon peak, so a sparkline has a shape rather than a slope.
    public static var hours: [HourlyCalls] {
        let counts = [
            18, 12, 9, 6, 4, 3, 5, 11, 26, 44, 61, 78,
            96, 88, 71, 64, 58, 47, 39, 31, 27, 22, 19, 14
        ]
        return counts.enumerated().map { index, calls in
            HourlyCalls(hourStart: hourStart(offset: index), calls: calls)
        }
    }

    /// `2026-08-21T13:00:00.000Z` plus whole hours, composed rather than taken from a `Date`, so
    /// the fixture reads the same on every machine and in every time zone.
    static func hourStart(offset: Int) -> String {
        let hour = 13 + offset
        return String(format: "2026-08-%02dT%02d:00:00.000Z", hour < 24 ? 21 : 22, hour % 24)
    }

    public static var populated: InsightsResponse {
        InsightsResponse(
            generatedAt: generatedAt,
            windowHours: 24,
            windowStart: windowStart,
            logHorizon: "2026-08-21T13:04:22.118Z",
            children: ChildProcessCount(alive: 2, declared: 11),
            calls: CallTotals(total: 853, failed: 12, unreadableLines: 0),
            resident: ResidentMemory(megabytes: 214, children: 2),
            callsByHarness: [
                HarnessCallCount(harness: "claudeCode", displayName: "Claude Code", calls: 604),
                HarnessCallCount(harness: "geminiCLI", displayName: "Gemini CLI", calls: 0),
                HarnessCallCount(harness: "grokCLI", displayName: "grok", calls: 91),
                // The two rows the chart exists to be honest about: a real process name that
                // identifies no single harness. A zero here would be a fabricated finding.
                HarnessCallCount(
                    harness: "cursor", displayName: "Cursor", calls: nil,
                    reason: "calls arrive as node — cursor-agent execs a bundled node, which "
                        + "every node MCP process shares"
                ),
                HarnessCallCount(
                    harness: "codexCLI", displayName: "Codex CLI", calls: nil,
                    reason: "calls arrive as codex — the Codex and ChatGPT entries are the same "
                        + "binary, so a count cannot be split"
                )
            ],
            otherCalls: 158,
            dutyCycle: DutyCycle(uptimeSeconds: 86400, servers: [
                DutyCycleServer(server: "obscura", aliveSeconds: 31968),
                DutyCycleServer(server: "dossier", aliveSeconds: 15552),
                DutyCycleServer(server: "google-search", aliveSeconds: 5184),
                DutyCycleServer(server: "ref-tools-mcp", aliveSeconds: 2592),
                // A declared server nobody has called. The most informative row on the chart, and
                // the one a chart that dropped empty series would lose.
                DutyCycleServer(server: "docker-mcp", aliveSeconds: 0)
            ]),
            callsPerHour: hours,
            analyst: nil
        )
    }

    /// A router that has been up for minutes with almost nothing through it.
    ///
    /// Not an empty struct: the counts are real and small, `logHorizon` is nil because no record is
    /// in the window, and that nil is the whole of *not enough history yet*. A response full of
    /// zeros would draw a flat chart and imply a quiet day.
    public static var thin: InsightsResponse {
        InsightsResponse(
            generatedAt: generatedAt,
            windowHours: 24,
            windowStart: windowStart,
            logHorizon: nil,
            children: ChildProcessCount(alive: 0, declared: 11),
            calls: CallTotals(total: 0, failed: 0, unreadableLines: 0),
            resident: nil,
            callsByHarness: [],
            otherCalls: 0,
            dutyCycle: DutyCycle(uptimeSeconds: 214, servers: []),
            callsPerHour: hours.map { HourlyCalls(hourStart: $0.hourStart, calls: 0) },
            analyst: nil
        )
    }
}
