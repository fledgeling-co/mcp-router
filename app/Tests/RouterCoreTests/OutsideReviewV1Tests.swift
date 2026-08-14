import Foundation
import Testing
@testable import RouterCore

/// Regressions found by V1's out-of-family review of the router items.
///
/// Each test here exists because a defect survived every reviewer the item had. They are kept in
/// one file rather than folded into the suites they touch for a reason worth stating: each of these
/// behaviours *was* covered by a test that passed, and the tests passed because they exercised the
/// value the harness supplied rather than the one production uses. Grouping them keeps that shared
/// cause visible instead of scattering three unrelated-looking assertions.
@Suite("V1 — out-of-family review regressions", .serialized)
struct OutsideReviewV1Tests {
    // MARK: - R2-W · the run must resolve both halves of its home from one place

    /// The whole watcher must follow one `HOME`, not one per path family.
    ///
    /// `WatchPaths` reads `HOME` (X10, W-D2) and `RouterHome()` reads `NSHomeDirectory()`, which
    /// ignores it. While `WatchRunner.init` defaulted `home` to `RouterHome()`, a run that took both
    /// defaults — which is every production run, `WatchVerb.swift:14` — read `~/.claude.json` out of
    /// `$HOME` and wrote `servers.json`, `manifest.json` and the adoption's backups into the account
    /// directory instead. That is the exact hazard X10's own comment says it prevents, and no test
    /// could see it: `WatchWorld.runner` passes `home:` explicitly, so the harness always supplied a
    /// matching pair.
    ///
    /// The reference has no way to produce two homes in one run — `src/config.ts:79` and
    /// `src/watch.ts:45` both derive from a single `homedir()`.
    @Test("R2-W — the runner's default router home follows the same HOME as its staging file")
    func routerHomeFollowsTheSameHome() {
        let paths = WatchPaths(
            environment: ["HOME": "/tmp/v1-fakehome"], homeDirectory: "/Users/somebody"
        )
        #expect(paths.claudeJSON == "/tmp/v1-fakehome/.claude.json")
        #expect(paths.routerHome.root == "/tmp/v1-fakehome/.claude/mcp-router")

        // The regression proper: the default, which production is the only caller of.
        let runner = WatchRunner(paths: paths)
        #expect(
            runner.home.root == paths.routerHome.root,
            "servers.json must come from the same HOME as ~/.claude.json"
        )
        #expect(runner.home.configPath.hasPrefix("/tmp/v1-fakehome/"))
    }

    /// `MCP_ROUTER_HOME` still wins, and still reaches both halves.
    @Test("R2-W — an explicit MCP_ROUTER_HOME overrides both halves together")
    func explicitRouterHomeStillWins() {
        let paths = WatchPaths(
            environment: ["HOME": "/tmp/v1-fakehome", "MCP_ROUTER_HOME": "/tmp/v1-elsewhere"],
            homeDirectory: "/Users/somebody"
        )
        #expect(paths.claudeJSON == "/tmp/v1-fakehome/.claude.json")
        #expect(WatchRunner(paths: paths).home.root == "/tmp/v1-elsewhere")
    }

    // MARK: - R2-W · a hostile number in servers.json must not abort the process

    /// `Int(_: Double)` traps on an infinite, NaN or out-of-range value, and `startupTimeoutMs` is
    /// read straight off `servers.json` with no clamp.
    ///
    /// `JSONCursor.parseNumber` turns `1e400` into an infinity, matching `JSON.parse` — its own
    /// comment says so. Measured before the fix: `Int(Double("1e400")!)` aborts with "Double value
    /// cannot be converted to Int because it is either infinite or NaN", killing the launchd
    /// one-shot on every fire until the file is edited by hand. The reference hands the raw number
    /// to the pool and never converts, so it has no such edge.
    ///
    /// A trap takes the whole test process down rather than failing one case, so the red for this
    /// is an aborted run — which is exactly the production symptom.
    @Test("R2-W — startupTimeoutMs of 1e400 does not abort the run")
    func hostileStartupTimeoutDoesNotAbort() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let entry = try WatchWorld.childEntry(in: scratch, name: "probe")
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)

        // Written as literal source text, not built through `JSStringify`: an infinity serialises
        // back out as `null` (matching `JSON.stringify`), so a round-tripped fixture would quietly
        // test the absent-key path instead. `1e400` has to reach the parser as the characters a
        // user's editor would leave in the file.
        let config = """
        {
          "port": 8879,
          "startupTimeoutMs": 1e400,
          "mcpServers": {}
        }

        """
        try WatchWorld.write(config, to: scratch.configPath)

        // Reaching the end at all is the assertion: the pre-fix build aborted inside this call.
        try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()
        #expect(FileManager.default.fileExists(atPath: scratch.configPath))
    }

    // MARK: - R3 · the control token is a secret and must be stored like one

    /// `control.token` gates the endpoint that installs a server, and installing a server runs an
    /// arbitrary command line with the user's environment. The reference writes it `0600` inside a
    /// `0700` directory (`src/control.ts:51-53`); `ControlToken.load` used the mode-less `FileSystem`
    /// overloads, so it landed at the umask default — `0644` in a `0755` directory — while the type's
    /// own documentation claimed "a `0600` file no web page can read".
    ///
    /// `FileAuthStore` already writes its records at `0700`/`0600`, so the codebase had both the API
    /// and the precedent; B18 simply never named a mode, which is why no reviewer checked. Asserted
    /// on the bits actually on disk rather than on the call.
    @Test("R3 — a newly minted control token is 0600 inside a 0700 directory")
    func controlTokenIsWrittenPrivately() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("v1-token-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("control.token").path

        let fileSystem = RealFileSystem()
        let token = try ControlToken(
            path: path,
            fileSystem: fileSystem,
            randomBytes: { count in [UInt8](repeating: 7, count: count) }
        ).load()

        #expect(token == String(repeating: "07", count: 32))
        #expect(try fileSystem.fileMode(atPath: path) == 0o600)
        #expect(try fileSystem.fileMode(atPath: root.path) == 0o700)
    }

    /// The directory is tightened even when it already exists with looser bits — the case that
    /// actually occurs, since the router home is created by whichever component runs first.
    @Test("R3 — an existing loose router home is tightened when the token is minted")
    func existingLooseHomeIsTightened() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("v1-token-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o755)]
        )
        let path = root.appendingPathComponent("control.token").path

        let fileSystem = RealFileSystem()
        _ = try ControlToken(path: path, fileSystem: fileSystem).load()
        #expect(try fileSystem.fileMode(atPath: root.path) == 0o700)
        #expect(try fileSystem.fileMode(atPath: path) == 0o600)
    }

    // MARK: - R3 · servers.json holds every server's env, which is where API keys live

    /// B31 names `0600` as part of `editConfigFile`'s byte contract and the reference writes the
    /// temporary at that mode (`src/control.ts:95`); the mode travels with the rename. The call used
    /// the mode-less overload, so `servers.json` landed at the umask default.
    ///
    /// Both out-of-family reviews found this independently, which is what a clause with no test
    /// looks like from the outside.
    @Test("R3 — an edited servers.json is committed at 0600")
    func editedConfigIsPrivate() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("v1-cfg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent("servers.json").path

        let fileSystem = RealFileSystem()
        try ConfigEdit.edit(path: path, fileSystem: fileSystem) { servers in
            servers.append(JSONMember(key: JSString("s1"), value: .object([
                JSONMember(key: JSString("command"), value: .string(JSString("/bin/echo")))
            ])))
        }
        #expect(try fileSystem.fileMode(atPath: path) == 0o600)
        // The temporary must not survive the commit, at any mode.
        let temporary = "\(path).tmp-\(ProcessInfo.processInfo.processIdentifier)"
        #expect(!FileManager.default.fileExists(atPath: temporary))
    }

    // MARK: - R3 · a JSON number must not be able to abort the process

    /// `Int(_: Double)` and `Int32(_: Double)` are trapping conversions, and both were applied
    /// straight to numbers read out of a file. JavaScript carries the `Double` and never aborts, so
    /// each of these is a file that halts a process the reference keeps running.
    ///
    /// `ServerParser` is on the path of every config load, every `ConfigEdit.reload` after a control
    /// API write, and every watcher fire; `UsageRecord` is on `UsageStore.init`'s `readTail`, so a
    /// single line in `usage.jsonl` decided whether the daemon could start.
    @Test("R3 — a hostile number in a server entry yields nil, not an abort")
    func hostileServerNumbersDoNotAbort() throws {
        for text in ["1e400", "1e300", "-1e400"] {
            let source = #"{"command":"/bin/echo","idleMs":\#(text),"startupTimeoutMs":\#(text)}"#
            let raw = try JSONParser.parse(Data(source.utf8))
            guard case let .upstream(parsed) = ServerParser.parse(name: "s", raw: raw) else {
                Issue.record("\(text) should still parse as an upstream")
                continue
            }
            #expect(parsed.idleMs == nil, "\(text) must not become an Int")
            #expect(parsed.startupTimeoutMs == nil)
        }
        // A representable value still arrives intact — the guard must not swallow real numbers.
        let ok = try JSONParser.parse(Data(#"{"command":"/bin/echo","idleMs":30000}"#.utf8))
        guard case let .upstream(parsed) = ServerParser.parse(name: "s", raw: ok) else {
            Issue.record("a normal entry must parse")
            return
        }
        #expect(parsed.idleMs == 30000)
    }

    @Test("R3 — a hostile pid in the usage log yields nil, not an abort")
    func hostilePidDoesNotAbort() throws {
        let hostile = #"{"ts":"2026-08-14T00:00:00.000Z","server":"s","tool":"t","#
            + #""ok":true,"ms":1,"cold":false,"pid":3000000000}"#
        let record = try UsageRecord(JSONParser.parse(Data(hostile.utf8)))
        #expect(record != nil, "the line is well formed; it must not be dropped")
        #expect(record?.pid == nil, "an out-of-range pid is absent, not an abort")

        let ordinary = #"{"ts":"2026-08-14T00:00:00.000Z","server":"s","tool":"t","#
            + #""ok":true,"ms":1,"cold":false,"pid":4242}"#
        #expect(try UsageRecord(JSONParser.parse(Data(ordinary.utf8)))?.pid == 4242)
    }

    // MARK: - R2-W · a staging file deleted mid-run stays deleted

    /// `watch.ts:328` reads the mode with `statSync(CLAUDE_JSON)` immediately before writing, and
    /// that throws when the path has gone — so the reference leaves a deleted `~/.claude.json`
    /// deleted. The Swift mode rule fell back to a default instead and rebuilt the file from the
    /// snapshot parsed moments earlier, restoring session state the user had just discarded.
    @Test("R2-W — a ~/.claude.json deleted mid-run is not recreated")
    func deletedStagingFileIsNotRecreated() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let entry = try WatchWorld.childEntry(in: scratch, name: "probe")
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)

        // Index first, so the second run reaches the staging write with something to remove.
        let runner = WatchWorld.runner(scratch, kicks: RestartRecorder())
        try? await runner.run()

        // Now the file goes away between the re-read and the write. Deleting it before the run and
        // re-creating nothing is the same observable state the race produces at the write.
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)
        let vanishing = VanishingFileSystem(
            wrapped: RealFileSystem(), unlink: scratch.claudeJSON
        )
        let runner2 = WatchRunner(
            paths: scratch.paths,
            home: scratch.routerHome,
            fileSystem: vanishing,
            kick: { _ in nil },
            emit: { _ in }
        )
        await #expect(throws: (any Error).self) { try await runner2.run() }
        #expect(
            !FileManager.default.fileExists(atPath: scratch.claudeJSON),
            "a deleted staging file must stay deleted"
        )
    }

    // MARK: - R3 · two coercions the comments described and the code did not do

    /// `s.firstSeen ??= r.ts` is **nullish**, so a present `null` is replaced. Testing `== nil` is
    /// absence only, which leaves `"firstSeen": null` on the wire permanently — every later call
    /// finds the key present and declines to fill it in.
    @Test("R3 — a null firstSeen is filled in, as ??= does")
    func nullFirstSeenIsReplaced() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("v1-usage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stats = root.appendingPathComponent("usage-stats.json").path
        let seeded = #"{"version":1,"since":"2026-01-01T00:00:00.000Z","servers":"#
            + #"{"s":{"calls":0,"errors":0,"projects":{},"firstSeen":null}}}"#
        try seeded.write(toFile: stats, atomically: true, encoding: .utf8)

        let store = UsageStore(
            logPath: root.appendingPathComponent("usage.jsonl").path, statsPath: stats
        )
        store.record(UsageRecord(
            ts: "2026-08-14T00:00:01.000Z", server: "s", tool: "t", ok: true, ms: 1, cold: false
        ))
        let seen = store.statFor("s")?.member("firstSeen")?.asString?.string
        #expect(seen == "2026-08-14T00:00:01.000Z", "a null firstSeen must be filled in")
    }

    /// The aggregate is keyed by `JSString`; the ring was filtered with Swift `String ==`, which is
    /// canonical equivalence. Two servers whose names differ only by Unicode normalisation are two
    /// distinct servers to every other part of this port, so forgetting one dropped the other's
    /// history too (S5).
    @Test("R3 — forgetting a server leaves a canonically-equivalent sibling alone")
    func forgetDoesNotDropAnEquivalentName() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("v1-forget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = UsageStore(
            logPath: root.appendingPathComponent("usage.jsonl").path,
            statsPath: root.appendingPathComponent("usage-stats.json").path
        )

        let composed = "caf\u{00E9}"
        let decomposed = "cafe\u{0301}"
        for name in [composed, decomposed] {
            store.record(UsageRecord(
                ts: "2026-08-14T00:00:01.000Z", server: name, tool: "t",
                ok: true, ms: 1, cold: false
            ))
        }
        store.forget(composed)

        let survivors = store.recent(limit: 200, server: nil, cwd: nil).map(\.server)
        #expect(survivors == [decomposed], "only the composed name's history may be dropped")
    }

    /// `JSObjectDraft.get` returns `.some(.null)` for a member that is present and null, so Swift's
    /// `??` never fires on it. The registry merge used `??` in five places the reference writes with
    /// nullish semantics, so `"description": null` survived to the wire and a Smithery row carrying
    /// an explicit `"useCount": null` **overwrote** the official row's real count with null.
    ///
    /// `registry/search` has no differential oracle — the reference calls live registries, which is
    /// deferred child `D-m` — so this class of defect had nothing to catch it.
    @Test("R3 — a present null does not survive the registry merge's nullish defaults")
    func registryMergeTreatsNullAsAbsent() {
        var official = JSObjectDraft()
        official.set("useCount", .number(42))
        official.set("description", .null)
        #expect(official.nullish("description") == nil, "a present null reads as absent")
        #expect(official.nullish("useCount") != nil, "a real value still reads as present")

        var smithery = JSObjectDraft()
        smithery.set("useCount", .null)
        // The merge takes Smithery's value only when it has one; a null must not erase 42.
        let merged = smithery.nullish("useCount") ?? official.get("useCount")
        #expect(merged?.asNumber == 42, "a null useCount must not overwrite the official count")
    }
}

/// A real filesystem that unlinks one path the moment its mode is asked for.
///
/// That is precisely the reference's ordering — `statSync` is the last thing it does before writing
/// — so removing the file at that instant reproduces the window without a sleep or a second thread.
final class VanishingFileSystem: FileSystem, FileModeWriting, @unchecked Sendable {
    private let wrapped: RealFileSystem
    private let unlink: String

    init(wrapped: RealFileSystem, unlink: String) {
        self.wrapped = wrapped
        self.unlink = unlink
    }

    func fileMode(atPath path: String) throws -> UInt16 {
        if path == unlink { try? wrapped.removeItem(atPath: path) }
        return try wrapped.fileMode(atPath: path)
    }

    func fileExists(atPath path: String) -> Bool {
        wrapped.fileExists(atPath: path)
    }

    func readFile(atPath path: String) throws -> Data {
        try wrapped.readFile(atPath: path)
    }

    func writeFile(_ data: Data, atPath path: String) throws {
        try wrapped.writeFile(data, atPath: path)
    }

    func appendFile(_ data: Data, atPath path: String) throws {
        try wrapped.appendFile(data, atPath: path)
    }

    func createDirectory(atPath path: String) throws {
        try wrapped.createDirectory(atPath: path)
    }

    func moveItem(atPath source: String, toPath destination: String) throws {
        try wrapped.moveItem(atPath: source, toPath: destination)
    }

    func copyItem(atPath source: String, toPath destination: String) throws {
        try wrapped.copyItem(atPath: source, toPath: destination)
    }

    func removeItem(atPath path: String) throws {
        try wrapped.removeItem(atPath: path)
    }

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        try wrapped.contentsOfDirectory(atPath: path)
    }

    func attributes(atPath path: String) throws -> FileStamp {
        try wrapped.attributes(atPath: path)
    }

    func createDirectory(atPath path: String, mode: UInt16) throws {
        try wrapped.createDirectory(atPath: path, mode: mode)
    }

    func writeFile(_ data: Data, atPath path: String, mode: UInt16) throws {
        try wrapped.writeFile(data, atPath: path, mode: mode)
    }
}
