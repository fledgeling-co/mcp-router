import Foundation
import Testing
@testable import RouterCore

/// The recorded trap, and the ways a port can appear to close it while leaving it open.
///
/// The reference reads `raw.mcpServers`, finds nothing, and loads **zero servers with no error at
/// all**. A surface renders that as "you have no servers", which is indistinguishable from the
/// truth — the worst failure mode available, because nothing about it looks like a failure.
@Suite("The flat servers.json trap")
struct ConfigTrapTests {
    private func withTemporaryConfig(_ contents: String, _ body: (String) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("router-core-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("servers.json").path
        try Data(contents.utf8).write(to: URL(fileURLWithPath: path))
        try body(path)
    }

    private func load(_ path: String) throws -> LoadedConfig {
        try ConfigLoader.load(options: .init(configPath: path), home: RouterHome(root: "/tmp/router-home"))
    }

    /// A5 of the brief, and the reason this item exists.
    @Test("a flat server map fails loudly instead of loading nothing")
    func flatServerMapIsAnError() throws {
        let flat = """
        {
          "docker-mcp": { "command": "uvx", "args": ["docker-mcp"] },
          "Ref": { "command": "ref-tools-mcp", "args": ["--stdio"] }
        }
        """
        try withTemporaryConfig(flat) { path in
            do {
                let loaded = try load(path)
                Issue.record("loaded \(loaded.config.upstreams.count) servers instead of failing — this is the trap")
            } catch let problem as ConfigProblem {
                guard case let .unrecognisedShape(_, found) = problem, found == .missingKey else {
                    Issue.record("wrong failure: \(problem)")
                    return
                }
                #expect(problem.description.contains("servers.json"), "the error names the file")
                #expect(problem.description.contains("mcpServers"), "the error names the missing key")
                #expect(problem.description.contains("wrap them"), "the error says what to do")
            }
        }
    }

    /// The defect a decoder that special-cased the recorded fixture would still have. Every one of
    /// these is a shape whose obvious handling is "no servers found".
    @Test("an mcpServers that is present but not an object is an error, not an empty config",
          arguments: [#""bad""#, "[]", "null", "7", "true"])
    func nonObjectMCPServersIsAnError(_ literal: String) throws {
        try withTemporaryConfig("{\"mcpServers\": \(literal)}") { path in
            do {
                _ = try load(path)
                Issue.record("mcpServers: \(literal) loaded as a valid config")
            } catch let problem as ConfigProblem {
                guard case .unrecognisedShape(_, .wrongType) = problem else {
                    Issue.record("wrong failure for \(literal): \(problem)")
                    return
                }
            }
        }
    }

    /// The distinction the whole design exists to preserve: these four outcomes are different
    /// values, so a surface can render four different screens without guessing.
    @Test("absent, unparseable, unrecognised and legitimately-empty are four distinct outcomes")
    func fourOutcomesAreDistinguishable() throws {
        // Absent.
        do {
            _ = try ConfigLoader.load(options: .init(configPath: "/nonexistent/servers.json"))
            Issue.record("a missing file should not load")
        } catch let problem as ConfigProblem {
            guard case .missingFile = problem else {
                Issue.record("wrong failure: \(problem)")
                return
            }
            #expect(problem.description.contains("mcp-router import"), "says how to create one")
        }

        // Not JSON.
        try withTemporaryConfig("{ not json") { path in
            do {
                _ = try load(path)
                Issue.record("invalid JSON should not load")
            } catch let problem as ConfigProblem {
                guard case .notJSON = problem else {
                    Issue.record("wrong failure: \(problem)")
                    return
                }
            }
        }

        // Unrecognised — covered above, asserted here as a distinct case value.
        try withTemporaryConfig(#"{"servers": {}}"#) { path in
            #expect(throws: ConfigProblem.self) { _ = try load(path) }
        }

        // Legitimately empty. This one is NOT an error: it is a first-run state.
        try withTemporaryConfig(#"{"mcpServers": {}}"#) { path in
            let loaded = try load(path)
            #expect(loaded.declaresNoServers, "an empty declaration is a state, not a failure")
            #expect(loaded.config.upstreams.isEmpty)
            #expect(loaded.skipped.isEmpty)
        }
    }

    @Test("a null server value aborts the load rather than becoming one skipped server")
    func nullServerValueAbortsTheLoad() throws {
        try withTemporaryConfig(#"{"mcpServers": {"a": {"command": "x"}, "b": null}}"#) { path in
            do {
                _ = try load(path)
                Issue.record("a null entry should abort the load, as it does in the reference")
            } catch let problem as ConfigProblem {
                guard case let .malformedServerEntry(_, name) = problem else {
                    Issue.record("wrong failure: \(problem)")
                    return
                }
                #expect(name == "b")
            }
        }
    }

    @Test("a server that cannot be adopted is reported with its reason, and the rest still load")
    func partialLoadReportsSkippedServers() throws {
        let mixed = """
        {"mcpServers": {
          "good": {"command": "x"},
          "bad name": {"command": "y"},
          "foo__bar": {"command": "z"},
          "nocommand": {}
        }}
        """
        try withTemporaryConfig(mixed) { path in
            let loaded = try load(path)
            #expect(loaded.config.upstreams.map(\.name) == ["good"])
            #expect(loaded.skipped.count == 3)
            #expect(!loaded.declaresNoServers, "a partial load is not an empty one")
            #expect(loaded.skipped.contains { $0.hasPrefix("bad name (name is not [A-Za-z0-9_-]+") })
            #expect(loaded.skipped.contains { $0.contains("namespace separator") })
            #expect(loaded.skipped.contains { $0 == "nocommand (stdio server has no command)" })
        }
    }

    /// Nullish, not truthy. An implementation using `??`-as-`||` silently replaces a deliberate
    /// zero with the default.
    @Test("an explicit zero or empty string in the file is honoured, not replaced by a default")
    func nullishPrecedence() throws {
        try withTemporaryConfig(#"{"port": 0, "host": "", "idleMs": 0, "mcpServers": {}}"#) { path in
            let loaded = try load(path)
            #expect(loaded.config.port == 0)
            #expect(loaded.config.host == "")
            #expect(loaded.config.idleMs == 0)
            #expect(loaded.config.startupTimeoutMs == RouterHome.defaultStartupTimeoutMs)
        }
    }

    @Test("an explicit option outranks the file, and the file outranks the default")
    func precedenceOrder() throws {
        try withTemporaryConfig(#"{"port": 1234, "mcpServers": {}}"#) { path in
            let fromFile = try load(path)
            #expect(fromFile.config.port == 1234)

            let overridden = try ConfigLoader.load(
                options: .init(configPath: path, port: 9999),
                home: RouterHome(root: "/tmp/router-home")
            )
            #expect(overridden.config.port == 9999)
            #expect(overridden.config.host == RouterHome.defaultHost, "unset fields still fall to the default")
        }
    }

    @Test("every state path derives from the router home, even when the config is elsewhere")
    func homeOwnsEveryPath() throws {
        try withTemporaryConfig(#"{"mcpServers": {}}"#) { path in
            let home = RouterHome(root: "/custom/home")
            let loaded = try ConfigLoader.load(options: .init(configPath: path), home: home)
            #expect(loaded.config.manifestPath == "/custom/home/manifest.json")
            #expect(loaded.config.logPath == "/custom/home/router.log")
            #expect(loaded.config.usagePath == "/custom/home/usage.jsonl")
            #expect(loaded.config.statsPath == "/custom/home/usage-stats.json")
            #expect(loaded.config.authDir == "/custom/home/auth")
        }
    }

    @Test("MCP_ROUTER_HOME relocates every path together")
    func environmentOverridesHome() {
        let home = RouterHome(environment: ["MCP_ROUTER_HOME": "/elsewhere"], homeDirectory: "/Users/x")
        #expect(home.configPath == "/elsewhere/servers.json")
        #expect(home.authDir == "/elsewhere/auth")

        let fallback = RouterHome(environment: [:], homeDirectory: "/Users/x")
        #expect(fallback.configPath == "/Users/x/.claude/mcp-router/servers.json")
    }
}

@Suite("Writing servers.json")
struct ConfigWriterTests {
    private func inTemporaryDirectory(_ body: (String) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("router-write-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("servers.json").path)
    }

    /// The reference's writer emits four keys, so a read/modify/write cycle resets anything else
    /// the user has set — `startupTimeoutMs` included, even though the loader reads it.
    @Test("a rewrite preserves top-level keys it did not set")
    func rewritePreservesUnknownKeys() throws {
        try inTemporaryDirectory { path in
            let original = #"{"startupTimeoutMs": 1234, "somethingCustom": {"a": 1}, "mcpServers": {}}"#
            try Data(original.utf8).write(to: URL(fileURLWithPath: path))

            try ConfigWriter.write(
                servers: [JSONMember(key: JSString("a"), value: .object([
                    JSONMember(key: JSString("command"), value: .string(JSString("x")))
                ]))],
                port: 8879, host: "127.0.0.1", idleMs: 300_000, toPath: path
            )

            let reloaded = try ConfigLoader.load(options: .init(configPath: path),
                                                 home: RouterHome(root: "/tmp/h"))
            #expect(reloaded.config.startupTimeoutMs == 1234, "a supported setting survived the rewrite")
            #expect(reloaded.config.upstreams.map(\.name) == ["a"])

            let raw = try JSONParser.parse(Data(contentsOf: URL(fileURLWithPath: path)))
            #expect(raw.member("somethingCustom") != nil, "an unknown key survived too")
        }
    }

    @Test("the written file is valid, re-readable, and leaves no temporary behind")
    func writeIsCleanAndAtomic() throws {
        try inTemporaryDirectory { path in
            try ConfigWriter.write(servers: [], port: 1, host: "h", idleMs: 2, toPath: path)
            let reloaded = try ConfigLoader.load(options: .init(configPath: path),
                                                 home: RouterHome(root: "/tmp/h"))
            #expect(reloaded.declaresNoServers)
            #expect(reloaded.config.port == 1)

            let directory = (path as NSString).deletingLastPathComponent
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory)
                .filter { $0.contains(".tmp-") }
            #expect(leftovers.isEmpty, "a temp file survived a successful write")
        }
    }

    @Test("an existing list is backed up before it is replaced")
    func existingListIsBackedUp() throws {
        try inTemporaryDirectory { path in
            try Data(#"{"mcpServers": {"old": {"command": "x"}}}"#.utf8)
                .write(to: URL(fileURLWithPath: path))
            try ConfigWriter.write(servers: [], port: 1, host: "h", idleMs: 2, toPath: path)

            let directory = (path as NSString).deletingLastPathComponent
            let backups = try FileManager.default.contentsOfDirectory(atPath: directory)
                .filter { $0.contains(".bak-") }
            #expect(backups.count == 1)
            let restored = try JSONParser.parse(
                Data(contentsOf: URL(fileURLWithPath: (directory as NSString).appendingPathComponent(backups[0])))
            )
            #expect(restored.member("mcpServers")?.member("old") != nil, "the backup holds the previous list")
        }
    }
}
