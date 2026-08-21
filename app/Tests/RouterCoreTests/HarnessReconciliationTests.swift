import Foundation
import Testing
@testable import RouterCore

/// R7 — is this harness actually routed, and what is it duplicating.
///
/// The two duplicate cases below are not invented: both were measured on the author's machine on
/// 2026-08-21 and both are in `planning/specs/spec-R7.md` §1.3. They point opposite ways, which is
/// the whole argument for comparing on two bases.
@Suite("Harness reconciliation")
struct HarnessReconciliationTests {
    static let port = 8879
    static let endpoint = "http://127.0.0.1:8879/mcp"

    private func entry(_ json: String) -> JSONValue {
        // swiftlint:disable:next force_try
        try! JSONParser.parse(Data(json.utf8))
    }

    private func server(_ name: String, _ json: String) -> DiscoveredServer {
        DiscoveredServer(name: name, raw: entry(json))
    }

    private func upstream(_ name: String, _ json: String) -> UpstreamConfig {
        guard case let .upstream(parsed) = ServerParser.parse(name: name, raw: entry(json)) else {
            fatalError("fixture \(name) is not adoptable")
        }
        return parsed
    }

    private func report(
        _ entries: [DiscoveredServer], against upstreams: [UpstreamConfig], client: MCPClient = .geminiCLI
    ) -> HarnessReport {
        HarnessReconciliation.report(
            client: client, path: "/tmp/fixture", result: .servers(entries),
            upstreams: upstreams, port: Self.port
        )
    }

    // MARK: - The four states the acceptance asks for

    @Test("a harness with no entry pointing at the router is not wired")
    func notWired() {
        let found = report([server("a", #"{"command":"a"}"#)], against: [])
        #expect(found.route == .notWired)
        #expect(found.state == .notWired(overlapping: 0))
        #expect(found.headline == "not wired")
    }

    @Test("an http entry on the router's endpoint is wired via HTTP")
    func wiredViaHTTP() {
        let found = report([server("router", #"{"type":"http","url":"\#(Self.endpoint)"}"#)], against: [])
        #expect(found.route == .directHTTP(name: "router", url: Self.endpoint))
        #expect(found.state == .wiredViaHTTP)
    }

    @Test("a stdio entry carrying the endpoint in its args is a shim, and the bridge is named")
    func wiredViaShim() {
        let found = report(
            [server("router", #"{"command":"npx","args":["-y","mcp-remote","\#(Self.endpoint)"]}"#)],
            against: []
        )
        #expect(found.route == .stdioShim(name: "router", bridge: "mcp-remote", url: Self.endpoint))
        #expect(found.state == .wiredViaShim(bridge: "mcp-remote"))
        #expect(found.headline.contains("one child process per session"))
    }

    @Test("a bridge that is not mcp-remote is still a shim — detection is by endpoint, not by package")
    func shimIsNotAnAllowlist() {
        let found = report(
            [server("r", #"{"command":"/opt/bin/supergateway","args":["--sse","\#(Self.endpoint)"]}"#)],
            against: []
        )
        #expect(found.route == .stdioShim(name: "r", bridge: "supergateway", url: Self.endpoint))
    }

    @Test("wired and carrying duplicates is the fourth state, and the route survives inside it")
    func wiredWithDuplicates() {
        let found = report(
            [
                server("router", #"{"type":"http","url":"\#(Self.endpoint)"}"#),
                server("obscura", #"{"command":"obscura","args":["mcp"]}"#)
            ],
            against: [upstream("obscura", #"{"command":"obscura","args":["mcp"]}"#)]
        )
        #expect(found.state == .wiredWithDuplicates(
            route: .directHTTP(name: "router", url: Self.endpoint), count: 1
        ))
        #expect(found.duplicates.map(\.harnessName) == ["obscura"])
    }

    // MARK: - Route is decided by endpoint, never by name

    @Test("an entry NAMED router pointing somewhere else is not wired")
    func nameIsNotEvidence() {
        let found = report(
            [server("router", #"{"type":"http","url":"https://example.com/mcp"}"#)],
            against: []
        )
        #expect(found.route == .notWired, "the question is where it connects, not what it is called")
        // The contrast that makes the point: adoption's rule says the opposite about the same entry,
        // and both are right for their own question.
        #expect(SelfReference.isSelfReference(
            name: "router", raw: entry(#"{"type":"http","url":"https://example.com/mcp"}"#), port: Self.port
        ))
    }

    @Test("a loopback url on another port is not this router")
    func otherPort() {
        let found = report([server("x", #"{"type":"http","url":"http://127.0.0.1:9999/mcp"}"#)], against: [])
        #expect(found.route == .notWired)
    }

    // MARK: - The two duplicate bases, both taken from the machine

    @Test("a renamed duplicate is caught by config identity — Gemini's Ref is the router's ref-tools-mcp")
    func identityBasis() {
        let raw = #"{"command":"npx","args":["-y","ref-tools-mcp@3.0.3"],"env":{"REF_API_KEY":"k"}}"#
        let found = report(
            [
                server("router", #"{"type":"http","url":"\#(Self.endpoint)"}"#),
                server("Ref", raw)
            ],
            against: [upstream("ref-tools-mcp", raw)]
        )
        #expect(found.duplicates.count == 1)
        #expect(found.duplicates[0].harnessName == "Ref")
        #expect(found.duplicates[0].routerName == "ref-tools-mcp")
        guard case .identity = found.duplicates[0].basis else {
            Issue.record("expected the identity basis, got \(found.duplicates[0].basis)")
            return
        }
        #expect(found.duplicates[0].described.contains("the router calls it ref-tools-mcp"))
    }

    @Test("a same-name duplicate aimed elsewhere is caught by name — grok's mobbin is not the router's")
    func nameBasis() {
        let found = report(
            [
                server("router", #"{"type":"http","url":"\#(Self.endpoint)"}"#),
                server("mobbin", #"{"type":"http","url":"https://mcp.mobbin.com/mcp"}"#)
            ],
            against: [upstream("mobbin", #"{"type":"http","url":"https://api.mobbin.com/mcp"}"#)],
            client: .grokCLI
        )
        #expect(found.duplicates.count == 1)
        #expect(found.duplicates[0].basis == .name)
        #expect(found.duplicates[0].described == "mobbin", "same name both sides, so print it once")
    }

    @Test("neither basis alone answers this machine")
    func neitherBasisAlone() {
        let refRaw = #"{"command":"npx","args":["-y","ref-tools-mcp@3.0.3"]}"#
        let entries = [
            server("router", #"{"type":"http","url":"\#(Self.endpoint)"}"#),
            server("Ref", refRaw),
            server("mobbin", #"{"type":"http","url":"https://mcp.mobbin.com/mcp"}"#)
        ]
        let upstreams = [
            upstream("ref-tools-mcp", refRaw),
            upstream("mobbin", #"{"type":"http","url":"https://api.mobbin.com/mcp"}"#)
        ]
        let found = report(entries, against: upstreams)
        #expect(found.duplicates.count == 2, "name-only misses Ref; identity-only misses mobbin")
        #expect(Set(found.duplicates.map(\.harnessName)) == ["Ref", "mobbin"])
    }

    @Test("the harness's own router entry is never counted as a duplicate of anything")
    func routerEntryIsNotADuplicate() {
        let found = report(
            [server("router", #"{"type":"http","url":"\#(Self.endpoint)"}"#)],
            against: [upstream("router", #"{"command":"x"}"#)]
        )
        #expect(found.duplicates.isEmpty)
        #expect(found.entryCount == 0)
    }

    // MARK: - Honesty about what could not be read

    @Test("an entry the parser cannot read is reported as unparsed, not as no-duplicate")
    func unparsedIsNotAbsence() {
        let found = report(
            [
                server("router", #"{"type":"http","url":"\#(Self.endpoint)"}"#),
                server("broken", #"{"type":"carrier-pigeon"}"#)
            ],
            against: []
        )
        #expect(found.duplicates.isEmpty)
        #expect(found.unparsed.count == 1)
        #expect(found.unparsed[0].hasPrefix("broken: "))
    }

    @Test("a not-wired harness reports overlaps rather than duplicates")
    func overlapNotDuplicate() {
        let found = report(
            [server("obscura", #"{"command":"obscura","args":["mcp"]}"#)],
            against: [upstream("obscura", #"{"command":"obscura","args":["mcp"]}"#)],
            client: .codexCLI
        )
        #expect(found.state == .notWired(overlapping: 1))
        #expect(found.headline.contains("the router already fronts"))
        #expect(found.headline.contains("not wired"))
    }
}

/// R7, part two — what changes the remedy, what the plan says, and the two readers R7 added.
///
/// A second suite rather than a longer one: the cases above are about the comparison, these are
/// about what is done with its answer, and one struct holding both trips the type-length rule for
/// a reason that is also true of reading it.
@Suite("Harness reconciliation — remedies, plans and readers")
struct HarnessRemedyTests {
    static let port = 8879
    static let endpoint = "http://127.0.0.1:8879/mcp"

    private func entry(_ json: String) -> JSONValue {
        // swiftlint:disable:next force_try
        try! JSONParser.parse(Data(json.utf8))
    }

    private func server(_ name: String, _ json: String) -> DiscoveredServer {
        DiscoveredServer(name: name, raw: entry(json))
    }

    private func upstream(_ name: String, _ json: String) -> UpstreamConfig {
        guard case let .upstream(parsed) = ServerParser.parse(name: name, raw: entry(json)) else {
            fatalError("fixture \(name) is not adoptable")
        }
        return parsed
    }

    private func report(
        _ entries: [DiscoveredServer], against upstreams: [UpstreamConfig], client: MCPClient = .geminiCLI
    ) -> HarnessReport {
        HarnessReconciliation.report(
            client: client, path: "/tmp/fixture", result: .servers(entries),
            upstreams: upstreams, port: Self.port
        )
    }

    // MARK: - Capability changes the remedy, never the state

    @Test("a shim on a harness known to speak HTTP is told to switch; an unknown one is told to check")
    func capabilityDrivesTheRemedy() {
        let shim = [server("router", #"{"command":"npx","args":["-y","mcp-remote","\#(Self.endpoint)"]}"#)]
        let measured = report(shim, against: [], client: .geminiCLI)
        let unknown = report(shim, against: [], client: .opencode)
        #expect(measured.state == unknown.state, "capability must not move the state")
        #expect(measured.remedy?.contains("drop the shim") == true)
        #expect(unknown.remedy?.contains("Check whether") == true)
        #expect(unknown.remedy?.contains("drop the shim") == false)
    }

    @Test("every client's capability names its provenance")
    func capabilityProvenance() {
        for client in MCPClient.allCases {
            let summary = HTTPCapability.known(for: client).summary
            #expect(
                summary.contains("measured on") || summary.contains("taken on documentation")
                    || summary.contains("not established"),
                "\(client) states a capability with no provenance: \(summary)"
            )
        }
        #expect(HTTPCapability.known(for: .opencode) == .unknown, "nobody probed it, so it is unknown")
    }

    // MARK: - The plan, which nothing applies

    @Test("the plan names every duplicate and the shim it would replace")
    func planNamesTheWork() {
        let raw = #"{"command":"obscura","args":["mcp"]}"#
        let found = report(
            [
                server("router", #"{"command":"npx","args":["-y","mcp-remote","\#(Self.endpoint)"]}"#),
                server("obscura", raw)
            ],
            against: [upstream("obscura", raw)]
        )
        let plan = ReconciliationPlan.from(found)
        #expect(plan.remove == ["obscura"])
        #expect(plan.replaceShim == "router")
        #expect(plan.addRouterEntry == nil)
        #expect(plan.render().contains("nothing applies this plan"))
    }

    @Test("an unread config proposes nothing — absence of evidence is not evidence of absence")
    func unreadableProposesNothing() {
        let found = HarnessReconciliation.report(
            client: .grokCLI, path: "/tmp/x", result: .unreadable(reason: "line 8: nope"),
            upstreams: [], port: Self.port
        )
        #expect(found.unreadable != nil)
        #expect(ReconciliationPlan.from(found).isEmpty, "it read nothing, so it may propose nothing")
    }

    @Test("a missing config proposes nothing either")
    func absentProposesNothing() {
        let found = HarnessReconciliation.report(
            client: .opencode, path: "/tmp/x", result: .absent, upstreams: [], port: Self.port
        )
        #expect(ReconciliationPlan.from(found).isEmpty)
    }

    // MARK: - The readers R7 added

    @Test("grok's config.toml is readable — an array of tables elsewhere no longer blinds the reader")
    func grokShape() throws {
        let toml = """
        [cli]
        theme = "dark"

        [[marketplace.sources]]
        name = "official"

        [mcp_servers.router]
        url = "http://127.0.0.1:8879/mcp"
        enabled = true

        [mcp_servers.proctor]
        command = "/Applications/Proctor.app/Contents/MacOS/proctor-shim"
        args = [
            "serve",
            "--profile",
            "full",
        ]
        """
        let document = try MiniTOML.parse(toml)
        #expect(document.childNames(of: ["mcp_servers"]) == ["router", "proctor"])
        let proctor = try #require(document.table(matching: ["mcp_servers", "proctor"]))
        let args = try #require(proctor.first { $0.key == "args" })
        #expect(args.value == .array([.string("serve"), .string("--profile"), .string("full")]))
    }

    @Test("a server declared AS an array of tables is still refused rather than guessed at")
    func serverArrayOfTablesRefused() {
        #expect(throws: TOMLProblem.self) {
            try MiniTOML.parse("[[mcp_servers.x]]\ncommand = \"a\"")
        }
    }

    @Test("an array that never closes is an error, not a silent truncation")
    func unclosedArray() {
        #expect(throws: TOMLProblem.self) {
            try MiniTOML.parse("[mcp_servers.x]\nargs = [\n  \"a\",")
        }
    }

    @Test("the two harnesses R7 added have stable paths and the inventory keeps the router entry")
    func newClientPaths() throws {
        let reports = ClientConfigs.discover(homeDirectory: "/Users/x", projectDirectory: nil)
        let byClient = Dictionary(uniqueKeysWithValues: reports.map { ($0.client, $0.path) })
        // Under a home where nothing exists, Gemini resolves to the file `agy` would write —
        // `~/.gemini/config/mcp_config.json` — rather than to the pre-migration one it used to name.
        // `HarnessResolutionTests` covers what happens when one, both or neither is actually there.
        #expect(byClient[.geminiCLI] == "/Users/x/.gemini/config/mcp_config.json")
        #expect(byClient[.grokCLI] == "/Users/x/.grok/config.toml")

        // The load-bearing difference between the two entry points: `discover` drops the router's
        // own entry so adoption cannot proxy to itself, and `inventory` keeps it because it is the
        // only evidence that a harness is wired at all.
        let home = try scratchHome(#"{"mcpServers":{"router":{"type":"http","url":"\#(Self.endpoint)"}}}"#)
        defer { try? FileManager.default.removeItem(atPath: home) }
        let adopting = ClientConfigs.discover(homeDirectory: home, routerPort: Self.port)
        let reconciling = ClientConfigs.inventory(homeDirectory: home, routerPort: Self.port)
        #expect(adopting.first { $0.client == .geminiCLI }?.result == .declaresNone)
        guard case let .servers(kept)? = reconciling.first(where: { $0.client == .geminiCLI })?.result else {
            Issue.record("the inventory dropped the entry it exists to keep")
            return
        }
        #expect(kept.map(\.name) == ["router"])
    }

    private func scratchHome(_ geminiSettings: String) throws -> String {
        let root = NSTemporaryDirectory() + "r7-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: root + "/.gemini", withIntermediateDirectories: true
        )
        try Data(geminiSettings.utf8).write(to: URL(fileURLWithPath: root + "/.gemini/settings.json"))
        return root
    }
}
