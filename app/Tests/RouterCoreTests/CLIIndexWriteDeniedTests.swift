import Foundation
import Testing

/// `mcp-router index` end to end, against a router home the process may read but not write.
///
/// This is the shape the defect was found in and the only shape that can prove it closed. The
/// per-server line and the closing count are printed by the real binary, in one run, over a real
/// child process and a real refusal from the kernel — and the defect was precisely that a happy
/// run and a refused one printed the same `ok` line, so an assertion that reads stdout on a
/// writable home cannot bite. `planning/test-campaign/bin/witness-arm-denial.sh` is the arming
/// control this is modelled on; it is a campaign instrument rather than a gate, so the denial is
/// rebuilt here where `make test` runs it.
///
/// **The exit code is pinned, not changed.** `index` answering 0 over a manifest that was never
/// written is half of DEF-049, and the half that belongs to whoever owns the CLI's exit-code
/// contract — the project has already taken the opposite decision once on a sibling path
/// (`ControlApproveDispatchTests.swift:114-118`). These tests record the code as it stands so that
/// moving it later is a decision somebody takes rather than a side effect of a report fix.
@Suite("mcp-router index — a router home that refuses the write", .serialized)
struct CLIIndexWriteDeniedTests {
    /// One stdio MCP server, in the smallest form the router will index: `initialize`, then
    /// `tools/list` with a single tool.
    ///
    /// Its tool surface is read from `FIXTURE_TOOLS` at each spawn, so one script can present a
    /// server whose surface CHANGES between runs — the shape that makes the bookkeeping hold the
    /// new tools rather than approve them.
    private static let fixture = """
    import json, os, sys

    def send(obj):
        sys.stdout.write(json.dumps(obj) + "\\n")
        sys.stdout.flush()

    surface = [
        {"name": "echo", "description": "Returns its input.",
         "inputSchema": {"type": "object"}},
        {"name": "reverse", "description": "Reverses its input.",
         "inputSchema": {"type": "object"}},
    ][: int(os.environ.get("FIXTURE_TOOLS", "1"))]

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except Exception:
            continue
        identifier, method = message.get("id"), message.get("method")
        if method == "initialize":
            send({"jsonrpc": "2.0", "id": identifier, "result": {
                "protocolVersion": "2025-06-18",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "fixture", "version": "1.0.0"}}})
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": identifier, "result": {"tools": surface}})
        elif identifier is not None:
            send({"jsonrpc": "2.0", "id": identifier,
                  "error": {"code": -32601, "message": "no method"}})
    """

    private struct Run {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// The built CLI. Absent is a hard failure rather than a skip: `swift test` builds every target
    /// in the package, so a missing binary means this ran somewhere it cannot measure anything, and
    /// a skip there is indistinguishable from a pass.
    private static func binary() throws -> URL {
        let root = try RepoTree.root()
        let candidates = [root.appendingPathComponent("app/.build/debug/MCPRouterCLI")]
            + ((try? FileManager.default.contentsOfDirectory(
                at: root.appendingPathComponent("app/.build"), includingPropertiesForKeys: nil
            )) ?? []).map { $0.appendingPathComponent("debug/MCPRouterCLI") }
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
        else {
            throw Failure.noBinary(candidates.map(\.path).joined(separator: ", "))
        }
        return found
    }

    private enum Failure: Error { case noBinary(String) }

    /// A router home holding one stdio upstream. The fixture script lives OUTSIDE the home, so that
    /// making the home unwritable changes exactly one thing: whether the manifest can be written.
    private static func makeHome(withABrokenServer: Bool = false) throws -> (root: URL, home: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mcprouter-r10-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("fixture-server.py")
        try fixture.write(to: script, atomically: true, encoding: .utf8)

        var servers: [String: Any] = [
            "fixture": [
                "type": "stdio",
                "command": "/usr/bin/python3",
                "args": [script.path]
            ]
        ]
        if withABrokenServer {
            // A command that does not exist, so the upstream fails to start and the verb takes its
            // FAIL arm — the second half of "failed to index, and failed to record that".
            servers["broken"] = [
                "type": "stdio",
                "command": root.appendingPathComponent("no-such-binary").path,
                "args": [] as [String]
            ]
        }
        let config: [String: Any] = ["port": 8879, "host": "127.0.0.1", "mcpServers": servers]
        // `.sortedKeys` so the upstream order the verb walks is the same on every run: a Swift
        // dictionary's serialization order is not stable, and a report whose line order moves is a
        // report no assertion can pin.
        let data = try JSONSerialization.data(
            withJSONObject: config, options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: home.appendingPathComponent("servers.json"))
        return (root, home)
    }

    private static func runIndex(home: URL, tools: Int = 1) throws -> Run {
        let process = Process()
        process.executableURL = try binary()
        process.arguments = ["index", "--force"]
        var environment = ProcessInfo.processInfo.environment
        environment["MCP_ROUTER_HOME"] = home.path
        // Inherited by the fixture through the CLI, which spawns it with the router's own
        // environment — the same route `MCP_ROUTER_HOME` above travels.
        environment["FIXTURE_TOOLS"] = String(tools)
        process.environment = environment
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        // Read before waiting: a verb that fills a pipe buffer would otherwise block forever.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // A marker rather than "" on invalid UTF-8, following `RecordingSink.text`: an empty string
        // would satisfy every `!contains(...)` below without anything having been read.
        func text(_ data: Data) -> String {
            String(bytes: data, encoding: .utf8) ?? "<invalid utf-8>"
        }
        return Run(
            status: process.terminationStatus,
            stdout: text(outData),
            stderr: text(errData)
        )
    }

    @Test("the control: a writable home indexes, prints ok, and caches the tool")
    func aWritableHomeStillPrintsOK() throws {
        let (root, home) = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: root) }

        let run = try Self.runIndex(home: home)

        #expect(run.status == 0, "stderr was: \(run.stderr)")
        #expect(run.stdout.contains("  ok    fixture (1 tools)"), "stdout was: \(run.stdout)")
        #expect(run.stdout.contains("1 tools cached ->"), "stdout was: \(run.stdout)")
        #expect(
            !run.stdout.contains("not cached"),
            "without this control, the denial test below passes on a CLI that says `not cached` always"
        )
        #expect(
            FileManager.default.fileExists(atPath: home.appendingPathComponent("manifest.json").path),
            "the manifest really is written when the home allows it"
        )
    }

    @Test("a home that refuses the write is never reported as ok")
    func aDeniedHomeIsNotReportedAsOK() throws {
        let (root, home) = try Self.makeHome()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path)
            try? FileManager.default.removeItem(at: root)
        }
        // `dr-x------`: the process may read and traverse the home, and may not create in it. This
        // is the denial control's own mode, and it is what makes the manifest write the only thing
        // that changes between this test and the one above.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: home.path)

        let run = try Self.runIndex(home: home)

        #expect(
            !run.stdout.contains("  ok    fixture"),
            "DEF-049: this line was printed over a manifest that does not exist. stdout: \(run.stdout)"
        )
        #expect(
            run.stdout.contains("not cached  fixture"),
            "the replacement names the server and says the row was not cached. stdout: \(run.stdout)"
        )
        #expect(
            run.stdout.contains("0 tools cached ->"),
            "the closing count is unchanged — it always read the truth off disk"
        )
        #expect(
            run.stdout.contains("did not reach the manifest, so that count is unchanged by them"),
            "and the run now reconciles the two, so `0 tools cached` cannot be read as `nothing to do`"
        )
        #expect(
            !FileManager.default.fileExists(atPath: home.appendingPathComponent("manifest.json").path),
            "the denial really took: without this the whole test is measuring a writable home"
        )
    }

    @Test("a server that failed to start and failed to be recorded says both, not one")
    func aFailedUpstreamWhoseFailureRowIsAlsoLostSaysSo() throws {
        let (root, home) = try Self.makeHome(withABrokenServer: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: home.path)

        let run = try Self.runIndex(home: home)

        #expect(
            run.stdout.contains("  FAIL  broken:"),
            "the upstream's own failure still leads. stdout: \(run.stdout)"
        )
        #expect(
            run.stdout.contains("not cached  broken (the failure was not recorded either)"),
            """
            and the lost failure row is its own line: an unwritten error row leaves the entry \
            non-stale, so the next unforced `index` skips a server that never indexed. \
            stdout: \(run.stdout)
            """
        )
        #expect(run.status == 0, "still pinned. stderr: \(run.stderr)")
    }

    @Test("with an older row still on disk, the closing sentence does not claim the server is missing")
    func anOlderRowIsNotClaimedMissingFromTheCount() throws {
        let (root, home) = try Self.makeHome()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path)
            try? FileManager.default.removeItem(at: root)
        }
        // Index once for real, so the manifest holds a row, then deny the update.
        let seeded = try Self.runIndex(home: home)
        #expect(seeded.stdout.contains("1 tools cached ->"), "the control: the first run landed")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: home.path)

        let run = try Self.runIndex(home: home)

        #expect(
            run.stdout.contains("not cached  fixture"),
            "the update was refused and says so. stdout: \(run.stdout)"
        )
        #expect(
            run.stdout.contains("1 tools cached ->"),
            "and the count is 1, not 0 — the older row is still served. stdout: \(run.stdout)"
        )
        #expect(
            run.stdout.contains("that count is unchanged by them"),
            """
            The sentence has to be true in EVERY shape this verb reaches, and this one is where \
            two earlier wordings died. "These are not in that count" is false here — the server \
            IS in the count, from a row this run did not write. And "nothing this run read from \
            them is in that count" is false too: the refused update re-read `echo`, which the \
            older row already holds, so what this run read is exactly what the count includes. \
            Only a claim about PROVENANCE survives both. stdout: \(run.stdout)
            """
        )
        #expect(
            run.stdout.contains("whatever they contribute to it is from an earlier run"),
            "and it says where the count's contents came from instead. stdout: \(run.stdout)"
        )
        for dead in ["reflects the manifest as it stood before this run",
                     "nothing this run read from them is in that count"] {
            #expect(!run.stdout.contains(dead), "an earlier wording this case is what caught: \(dead)")
        }
    }

    @Test("a held surface reports its change count, so no line contradicts the closing one")
    func aHeldSurfaceReportsChangesRatherThanTools() throws {
        let (root, home) = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try Self.runIndex(home: home, tools: 1)
        #expect(first.stdout.contains("  ok    fixture (1 tools)"), "stdout: \(first.stdout)")
        #expect(first.stdout.contains("1 tools cached ->"), "stdout: \(first.stdout)")

        // Same server, one more tool. The digest moves, so the bookkeeping HOLDS the new surface
        // and the manifest keeps serving the approved one — nothing about the filesystem changes.
        let run = try Self.runIndex(home: home, tools: 2)

        #expect(
            run.stdout.contains("  ok    fixture (1 change(s) held for approval)"),
            """
            The reference prints this, and `node dist/index.js index --force` was run against the \
            same fixture to confirm it. stdout: \(run.stdout)
            """
        )
        #expect(
            !run.stdout.contains("  ok    fixture (2 tools)"),
            """
            DEF-049's disagreement with no filesystem involved: `(2 tools)` over `1 tools cached`, \
            in one run, on a writable home. The 2 are pending and the 1 is what is served. \
            stdout: \(run.stdout)
            """
        )
        #expect(
            run.stdout.contains("1 tools cached ->"),
            "the approved surface is still the one counted. stdout: \(run.stdout)"
        )
        #expect(
            !run.stdout.contains("not cached"),
            "and a held surface is not a lost write — the row landed. stdout: \(run.stdout)"
        )
        #expect(run.status == 0, "stderr: \(run.stderr)")
    }

    @Test("the exit code is 0 over a manifest that was never written — pinned, not endorsed")
    func theExitCodeIsUnchanged() throws {
        let (root, home) = try Self.makeHome()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: home.path)

        let run = try Self.runIndex(home: home)

        #expect(
            run.status == 0,
            """
            The CLI's exit-code contract for a failed manifest write is recorded, not changed. \
            If this went red because someone made the write propagate, that is a decision to take \
            on purpose and to record — not a regression to patch. stderr: \(run.stderr)
            """
        )
    }
}
