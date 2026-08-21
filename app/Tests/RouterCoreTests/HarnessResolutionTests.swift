import Foundation
import Testing
@testable import RouterCore

/// R7, second pass — **which file, and what counts as evidence of a route.**
///
/// The first pass added `httpUrl` to Gemini's key list. That closed a route; the property behind it
/// — *R7 reports the truth about the Gemini harness* — stayed false, because R7 was reading a file
/// the harness had stopped reading. `agy` 1.1.17 reads `~/.gemini/config/mcp_config.json`; R7 read
/// `~/.gemini/settings.json`; and on this machine the two disagree about the transport, the entry
/// count and two of the servers.
///
/// So these tests are about the two things a route claim rests on before any key is read: **the
/// file the harness actually resolves**, and **what in an entry is evidence that it reaches this
/// router** as opposed to merely mentioning its address.
@Suite("Harness resolution — the file, and what counts as a route")
struct HarnessResolutionTests {
    static let port = 8879
    static let endpoint = "http://127.0.0.1:8879/mcp"

    // MARK: - Fixtures

    /// A scratch home. Each file is written only when its text is given, so the three cases —
    /// migrated, pre-migration, and both present — are expressed by which arguments are passed.
    private func home(settings: String? = nil, mcpConfig: String? = nil) throws -> String {
        let root = NSTemporaryDirectory() + "r7-resolve-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: root + "/.gemini/config", withIntermediateDirectories: true
        )
        if let settings {
            try Data(settings.utf8).write(to: URL(fileURLWithPath: root + "/.gemini/settings.json"))
        }
        if let mcpConfig {
            try Data(mcpConfig.utf8)
                .write(to: URL(fileURLWithPath: root + "/.gemini/config/mcp_config.json"))
        }
        return root
    }

    private func gemini(_ home: String) -> ClientConfigReport? {
        ClientConfigs.inventory(homeDirectory: home, routerPort: Self.port)
            .first { $0.client == .geminiCLI }
    }

    private func entry(_ json: String) -> JSONValue {
        // swiftlint:disable:next force_try
        try! JSONParser.parse(Data(json.utf8))
    }

    private func server(_ name: String, _ json: String) -> DiscoveredServer {
        DiscoveredServer(name: name, raw: entry(json))
    }

    private func report(
        _ entries: [DiscoveredServer],
        against upstreams: [UpstreamConfig] = [],
        client: MCPClient = .geminiCLI
    ) -> HarnessReport {
        HarnessReconciliation.report(
            client: client, path: "/tmp/fixture", result: .servers(entries),
            upstreams: upstreams, port: Self.port
        )
    }

    /// The migrated file, as `agy` writes it: `serverUrl`, and two servers `settings.json` has never
    /// heard of.
    static let migrated = """
    {"mcpServers":{
      "router":{"serverUrl":"\(endpoint)"},
      "diolog-tasks":{"serverUrl":"https://mcp.diolog.com.au/api/tasks/mcp"},
      "obscura":{"command":"obscura","args":["mcp"]}
    }}
    """

    /// The pre-migration file, as it still sits on this machine: all stdio, wired through a shim.
    static let legacy = """
    {"mcpServers":{
      "router":{"command":"npx","args":["-y","mcp-remote","\(endpoint)"]},
      "obscura":{"command":"obscura","args":["mcp"]}
    }}
    """

    // MARK: - B1 · the file the harness resolves

    @Test("""
    both Gemini config files present and disagreeing: the migrated one wins, because it is the one \
    agy reads
    """)
    func bothPresentTheMigratedOneWins() throws {
        // This is not a hypothetical fixture — it is this machine's live state, and it is the case
        // neither pass had an assertion for. `~/.gemini/settings.json` (18 servers, all stdio, the
        // router on an `mcp-remote` shim) and `~/.gemini/config/mcp_config.json` (20 servers,
        // `serverUrl` x6, the router direct) both exist and disagree about the transport.
        //
        // The migrated file wins on four independent lines of evidence, all from the shipped
        // binary: `agy`'s `mcp` subcommands are documented as managing "your user-level
        // `mcp_config.json`"; its help text names `serverUrl` as the required HTTP key; its error
        // string is `MCP server %q must have either command or serverUrl`; and the only config
        // paths its binary carries are `.gemini/config/mcp_config.json` and `config/mcp_config.json`.
        // `~/.gemini/config/.migrated` dates the move. `agy mcp list` prints exactly the migrated
        // file's twenty rows.
        let root = try home(settings: Self.legacy, mcpConfig: Self.migrated)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let found = try #require(gemini(root))
        #expect(found.path == root + "/.gemini/config/mcp_config.json")
        guard case let .servers(entries) = found.result else {
            Issue.record("expected servers, got \(found.result)")
            return
        }
        #expect(
            entries.map(\.name) == ["router", "diolog-tasks", "obscura"],
            "reading the stale file loses two of the servers the harness actually runs"
        )
    }

    @Test("with both present, the reported route is the migrated file's, not the stale file's")
    func bothPresentTheRouteIsTheMigratedOne() throws {
        let root = try home(settings: Self.legacy, mcpConfig: Self.migrated)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let found = try #require(gemini(root))
        let harness = HarnessReconciliation.report(
            client: .geminiCLI, path: found.path, result: found.result, upstreams: [], port: Self.port
        )
        #expect(harness.route == .directHTTP(name: "router", url: Self.endpoint))
        #expect(harness.headline == "wired via HTTP")
        let plan = ReconciliationPlan.from(harness)
        #expect(
            plan.replaceShim == nil,
            "R7 proposed a stdio-shim -> HTTP migration the user performed on 14 Aug"
        )
        #expect(plan.addRouterEntry == nil)
    }

    @Test("with only settings.json present, a pre-migration install is still read")
    func preMigrationStillRead() throws {
        let root = try home(settings: Self.legacy)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let found = try #require(gemini(root))
        #expect(found.path == root + "/.gemini/settings.json")
        guard case let .servers(entries) = found.result else {
            Issue.record("a straight path swap breaks this install; expected servers, got \(found.result)")
            return
        }
        #expect(entries.map(\.name) == ["router", "obscura"])
    }

    @Test("with only the migrated file present, it is read")
    func migratedOnly() throws {
        let root = try home(mcpConfig: Self.migrated)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let found = try #require(gemini(root))
        #expect(found.path == root + "/.gemini/config/mcp_config.json")
    }

    @Test("with neither present, the path reported is the one agy would write")
    func neitherPresent() throws {
        let root = try home()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let found = try #require(gemini(root))
        #expect(found.path == root + "/.gemini/config/mcp_config.json")
        #expect(found.result == .absent)
    }

    @Test("every other harness still resolves to exactly one path")
    func otherHarnessesAreUnchanged() {
        for client in MCPClient.allCases where client != .geminiCLI {
            let candidates = ClientConfigs.candidatePaths(
                for: client, homeDirectory: "/Users/x", projectDirectory: "/Users/x/proj"
            )
            #expect(
                candidates.count <= 1,
                "\(client) has not been shown to read a second file, and guessing one is F1 inverted"
            )
        }
        #expect(
            ClientConfigs.candidatePaths(
                for: .geminiCLI, homeDirectory: "/Users/x", projectDirectory: nil
            ) == ["/Users/x/.gemini/config/mcp_config.json", "/Users/x/.gemini/settings.json"]
        )
    }

    // MARK: - B3 · what counts as evidence of a route

    @Test("a health-check curl that merely mentions the router's address is not a route")
    func healthCheckCurlIsNotARoute() {
        let found = report([server(
            "health",
            #"{"command":"curl","args":["-s","http://127.0.0.1:8879/health"]}"#
        )])
        #expect(
            found.route == .notWired,
            "no MCP route exists here; the harness runs curl at a health endpoint"
        )
        #expect(found.entryCount == 1, "and the entry does not vanish out of the count")
    }

    @Test("an endpoint key aimed at a non-MCP path on this router is not a route either")
    func nonMCPPathIsNotARouteOnTheHTTPAxisEither() {
        // The route nobody has named. B3 was filed against the shim axis — a `curl` at `/health`
        // read `wired-shim` — and the same evidence rule was wrong one axis along: a plain `url` at
        // `/health` read `wired-http`. Both come from the same place, which is that
        // `RouterEndpoint.isThisRouter` compared host and port and never asked what the URL pointed
        // at on this router.
        #expect(report([server("probe", #"{"url":"http://127.0.0.1:8879/health"}"#)]).route == .notWired)
        #expect(report([server("probe", #"{"url":"http://127.0.0.1:8879/status"}"#)]).route == .notWired)
        #expect(report([server("probe", #"{"url":"http://127.0.0.1:8879"}"#)]).route == .notWired)
        #expect(report([server("probe", #"{"url":"http://127.0.0.1:8879/"}"#)]).route == .notWired)
    }

    @Test("and the MCP endpoint itself is still a route, however it is spelled")
    func theMCPEndpointIsStillARoute() {
        // The other direction of the same rule: a path test that refuses the real endpoint would be
        // a worse defect than the one it replaced.
        #expect(report([server("r", #"{"url":"\#(Self.endpoint)"}"#)]).route
            == .directHTTP(name: "r", url: Self.endpoint))
        #expect(report([server("r", #"{"url":"http://127.0.0.1:8879/mcp/"}"#)]).route
            == .directHTTP(name: "r", url: "http://127.0.0.1:8879/mcp/"))
        #expect(report([server("r", #"{"url":"http://localhost:8879/mcp?session=1"}"#)]).route
            == .directHTTP(name: "r", url: "http://localhost:8879/mcp?session=1"))
    }

    @Test("a stdio server carrying a stale url is a stdio server, not an HTTP route")
    func aStdioServerCarryingAStaleURLIsNotWiredOverHTTP() {
        let found = report(
            [server("fs", #"{"command":"npx","args":["-y","fs-mcp"],"url":"\#(Self.endpoint)"}"#)]
        )
        #expect(
            found.route == .notWired,
            "a leftover URL beat a live stdio server, because the endpoint keys were read first"
        )
        #expect(found.entryCount == 1)
    }

    @Test("an entry declaring type http keeps its endpoint even beside a leftover command")
    func anExplicitHTTPTypeStillReadsAsHTTP() {
        // The other direction again. `type` is what Claude Code writes, and an explicit transport
        // is a statement rather than an inference — refusing it would turn a wired harness unwired.
        let found = report([server("r", #"{"type":"http","url":"\#(Self.endpoint)","command":"npx"}"#)])
        #expect(found.route == .directHTTP(name: "r", url: Self.endpoint))
    }

    @Test("an mcp-remote shim is still a shim")
    func theShimStillReads() {
        let found = report([server(
            "router",
            #"{"command":"npx","args":["-y","mcp-remote","\#(Self.endpoint)"]}"#
        )])
        #expect(found.route == .stdioShim(name: "router", bridge: "mcp-remote", url: Self.endpoint))
    }

    @Test("a direct HTTP entry still wins over a shim declared before it")
    func directBeatsShim() {
        let found = report([
            server("shim", #"{"command":"npx","args":["-y","mcp-remote","\#(Self.endpoint)"]}"#),
            server("direct", #"{"serverUrl":"\#(Self.endpoint)"}"#)
        ])
        #expect(found.route == .directHTTP(name: "direct", url: Self.endpoint))
    }
}
