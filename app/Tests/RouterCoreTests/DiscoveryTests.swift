import Foundation
import Testing
@testable import RouterCore

/// The brief's second named trap: the two CLIs spell the same table differently.
@Suite("Client-config discovery")
struct DiscoveryTests {
    /// Transcribed from `~/Dev/dAIolog/.codex-cli/config.toml` — bare keys under `mcp_servers`.
    static let codexShape = """
    # Codex CLI
    model = "gpt-5.6-terra"

    [mcp_servers.chrome-devtools]
    command = "/Users/x/node_modules/.bin/chrome-devtools-mcp"
    args = ["--stdio"]

    [mcp_servers.Ref]
    command = "/Users/x/node_modules/.bin/ref-tools-mcp"
    args = ["--stdio"]

    [mcp_servers.Ref.env]
    REF_API_KEY = "ref-16742f3e50e5e8046336"

    [mcp_servers.docker-mcp]
    command = "uvx"
    args = ["docker-mcp"]

    [projects."/Users/x/Dev"]
    trust_level = "trusted"
    """

    /// Transcribed from `~/Dev/dAIolog/.chatgpt/config.toml` — quoted keys under `mcpServers`.
    static let chatGPTShape = """
    [mcpServers."chrome-devtools"]
    command = "/Users/x/node_modules/.bin/chrome-devtools-mcp"
    args = ["--stdio"]

    [mcpServers."Ref"]
    command = "/Users/x/node_modules/.bin/ref-tools-mcp"
    args = ["--stdio"]

    [mcpServers."Ref".env]
    REF_API_KEY = "ref-16742f3e50e5e8046336"

    [mcpServers."docker-mcp"]
    command = "uvx"
    args = ["docker-mcp"]
    """

    private func servers(from toml: String) throws -> [DiscoveredServer] {
        let result = try ClientConfigs.read(
            client: .codexCLI,
            path: write(toml),
            routerPort: RouterHome.defaultPort,
            fileSystem: RealFileSystem()
        )
        guard case let .servers(found) = result else {
            Issue.record("expected servers, got \(result)")
            return []
        }
        return found
    }

    private func write(_ contents: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("discovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("config.toml").path
        try Data(contents.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    @Test("both TOML key shapes are read, and they yield the same servers")
    func bothKeyShapesParse() throws {
        let fromCodex = try servers(from: Self.codexShape)
        let fromChatGPT = try servers(from: Self.chatGPTShape)

        #expect(fromCodex.map(\.name).sorted() == ["Ref", "chrome-devtools", "docker-mcp"])
        #expect(fromChatGPT.map(\.name).sorted() == ["Ref", "chrome-devtools", "docker-mcp"])

        // Not just the names — the values have to survive the two spellings identically.
        for name in ["Ref", "chrome-devtools", "docker-mcp"] {
            let a = fromCodex.first { $0.name == name }?.raw
            let b = fromChatGPT.first { $0.name == name }?.raw
            #expect(a != nil && b != nil)
            #expect(
                JSStringify.compact(a ?? .null) == JSStringify.compact(b ?? .null),
                "\(name) differs between shapes"
            )
        }
    }

    @Test("a nested env sub-table is folded back into the server")
    func nestedEnvTable() throws {
        let found = try servers(from: Self.codexShape)
        let ref = found.first { $0.name == "Ref" }
        #expect(ref?.raw.member("env")?.member("REF_API_KEY")?.asString?.string == "ref-16742f3e50e5e8046336")

        // And the discovered shape feeds the shared parser without translation.
        guard case let .upstream(upstream) = ServerParser.parse(name: "Ref", raw: ref?.raw ?? .null) else {
            Issue.record("a discovered server must be adoptable by the same parser as a servers.json entry")
            return
        }
        #expect(upstream.args == ["--stdio"])
        #expect(upstream.env.first?.key == JSString("REF_API_KEY"))
    }

    @Test("the scanner walks past unrelated tables without trying to understand them")
    func unrelatedTablesAreIgnored() throws {
        let found = try servers(from: Self.codexShape)
        #expect(found.count == 3, "the projects table and the root keys are not servers")
    }

    @Test("a file with neither table shape declares none — distinct from unreadable and absent")
    func neitherShapeDeclaresNone() throws {
        let path = try write("[features]\nweb_search = true\n")
        let result = ClientConfigs.read(
            client: .codexCLI,
            path: path,
            routerPort: 8879,
            fileSystem: RealFileSystem()
        )
        #expect(result == .declaresNone)

        let absent = ClientConfigs.read(
            client: .codexCLI,
            path: "/nonexistent/config.toml",
            routerPort: 8879,
            fileSystem: RealFileSystem()
        )
        #expect(absent == .absent)
    }

    /// A silent skip inside a config reader produces a config that looks empty, which is the same
    /// defect class as the trap this item exists to close.
    @Test("syntax the reader does not understand is a named error citing the line, never a skip")
    func unsupportedSyntaxIsLoud() throws {
        let path = try write("""
        [mcp_servers.a]
        command = \"\"\"
        multi
        \"\"\"
        """)
        let result = ClientConfigs.read(
            client: .codexCLI,
            path: path,
            routerPort: 8879,
            fileSystem: RealFileSystem()
        )
        guard case let .unreadable(reason) = result else {
            Issue.record("expected a named failure, got \(result)")
            return
        }
        #expect(reason.contains("line 2"), "the error cites the line: \(reason)")
        #expect(reason.contains("multi-line"))
    }

    @Test("a name declared under both spellings is a conflict, not a silent preference")
    func conflictingTablesAreReported() throws {
        let both = """
        [mcp_servers.docker-mcp]
        command = "uvx"

        [mcpServers."docker-mcp"]
        command = "something-else"
        """
        let path = try write(both)
        let result = ClientConfigs.read(
            client: .codexCLI,
            path: path,
            routerPort: 8879,
            fileSystem: RealFileSystem()
        )
        guard case let .unreadable(reason) = result else {
            Issue
                .record(
                    "expected a conflict, got \(result) — a silent pick runs a command the user replaced"
                )
            return
        }
        #expect(reason.contains("docker-mcp"))
        #expect(reason.contains("both"))
    }

    @Test("the router's own entry is never discovered as a server to adopt")
    func routerEntryIsFilteredOut() throws {
        let selfEntry = """
        [mcp_servers.mcp-router]
        url = "http://127.0.0.1:8879/mcp"

        [mcp_servers.real]
        command = "x"
        """
        let found = try servers(from: selfEntry)
        #expect(found.map(\.name) == ["real"], "adopting the router makes it proxy to itself")
    }

    @Test("every client has a stable path, and discovery reports them in a fixed order")
    func clientPathsAndOrder() {
        let reports = ClientConfigs.discover(homeDirectory: "/Users/x", projectDirectory: "/Users/x/proj")
        #expect(reports.map(\.client) == MCPClient.allCases, "the order is fixed, so two runs agree")
        let byClient = Dictionary(uniqueKeysWithValues: reports.map { ($0.client, $0.path) })
        #expect(byClient[.claudeCode] == "/Users/x/.claude.json")
        #expect(byClient[.codexCLI] == "/Users/x/.codex/config.toml")
        #expect(byClient[.chatGPTCLI] == "/Users/x/proj/.chatgpt/config.toml")
        #expect(byClient[.cursor] == "/Users/x/.cursor/mcp.json")
        #expect(byClient[.opencode] == "/Users/x/.config/opencode/opencode.json")
        #expect(byClient[.claudeDesktop]?
            .hasSuffix("Library/Application Support/Claude/claude_desktop_config.json") == true)
        for report in reports {
            #expect(
                report.result == .absent,
                "nothing exists under a fabricated home, and that is a normal answer"
            )
        }
    }

    @Test("a JSON client with a wrong-typed servers key is unreadable, not empty")
    func jsonClientWrongType() throws {
        let path = try write(#"{"mcpServers": "nonsense"}"#)
        let result = ClientConfigs.read(
            client: .cursor,
            path: path,
            routerPort: 8879,
            fileSystem: RealFileSystem()
        )
        guard case .unreadable = result else {
            Issue.record("expected unreadable, got \(result)")
            return
        }
    }

    /// The real file on this machine is 24,753 lines of unrelated TOML. Parsing it is the check
    /// that the scanner genuinely walks past everything it does not care about.
    @Test("the real Codex config on this machine parses, when it is there")
    func realCodexConfigParses() {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/config.toml")
        guard FileManager.default.fileExists(atPath: path) else { return }
        let result = ClientConfigs.read(
            client: .codexCLI,
            path: path,
            routerPort: 8879,
            fileSystem: RealFileSystem()
        )
        if case let .unreadable(reason) = result {
            Issue.record("the real config did not parse: \(reason)")
        }
    }
}
