import Foundation
import Testing
@testable import RouterCore

/// The pieces the run is assembled from: the canonical hash, the state file, and the backup rules.
@Suite("Config watcher primitives")
struct WatchPrimitiveTests {
    // MARK: - W1's hash

    /// The reference is the oracle, not a hand-copied expectation.
    ///
    /// `hashOf(stable(v))` is reimplemented here in Swift, and the only way to know the
    /// reimplementation agrees is to run the original. A hardcoded digest would prove that this
    /// file agrees with itself.
    private func referenceHash(_ json: String) throws -> String {
        let script = """
        const crypto = require('crypto');
        function stable(v) {
          if (Array.isArray(v)) return v.map(stable);
          if (v && typeof v === 'object') {
            const out = {};
            for (const k of Object.keys(v).sort()) out[k] = stable(v[k]);
            return out;
          }
          return v;
        }
        const value = JSON.parse(require('fs').readFileSync(0, 'utf8'));
        process.stdout.write(
          crypto.createHash('sha256').update(JSON.stringify(stable(value))).digest('hex').slice(0, 32)
        );
        """
        // The JSON goes in on **stdin**, not as an argument. Measured: a non-ASCII codepoint does
        // not survive `Process.arguments` intact here, and the first version of this test reported
        // a hash divergence that was entirely the harness's — the two implementations agreed all
        // along. A test that lies about the thing it is checking is worse than no test.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "-e", script]
        let input = Pipe()
        let pipe = Pipe()
        process.standardInput = input
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(json.utf8))
        try input.fileHandleForWriting.close()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    @Test(
        "W1 — the hash agrees with the reference's, including the cases that usually diverge",
        arguments: [
            #"{}"#,
            #"{"b":1,"a":2}"#,
            #"{"a":{"z":1,"y":[3,2,1]},"A":null}"#,
            // Key order at depth, which is the whole point of `stable`.
            #"{"probe":{"env":{"Z":"1","A":"2"},"args":["x","y"],"command":"node"}}"#,
            // Escaping: a non-BMP codepoint as a surrogate pair, a quote, a backslash and a
            // JSON-escaped control character — four things `JSON.stringify` writes differently
            // from the bytes it read.
            #"{"k":"héllo"}"#,
            #"{"k":"a\u2028b"}"#,
            #"{"k":"a\u0007b"}"#,
            #"{"k":"a\ud83d\ude00b"}"#,
            #"{"k":"a\"b"}"#,
            #"{"k":"a\\b"}"#,
            // Number formatting — the classic JSON.stringify divergences.
            #"{"a":1e400,"b":-0,"c":1e21,"d":1e-7,"e":9007199254740993}"#,
            #"{"empty":[],"nested":[[],[{}]],"t":true,"f":false,"n":null}"#
        ]
    )
    func hashAgreesWithReference(_ json: String) throws {
        let value = try JSONParser.parse(Data(json.utf8))
        #expect(try StableHash.hash(of: value) == referenceHash(json), "for \(json)")
    }

    @Test("W1 — the truncation is 32 characters, not UpstreamHash's 16")
    func hashWidth() throws {
        let value = try JSONParser.parse(Data(#"{"a":1}"#.utf8))
        #expect(StableHash.hash(of: value).count == 32)
    }

    // MARK: - The state file

    @Test("W8 — corrupt watcher state recovers as empty state")
    func corruptStateRecovers() throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        try WatchWorld.write("{not json at all", to: scratch.statePath)
        let state = WatchState.load(path: scratch.statePath, fileSystem: RealFileSystem())
        #expect(state == WatchState())
    }

    @Test("state round-trips, including restartPending")
    func stateRoundTrips() throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let original = WatchState(
            mcpServersHash: "abc123",
            failures: [
                "broken": WatchState.Failure(hash: "hh", at: 1700, error: "broken: nope")
            ],
            restartPending: true
        )
        try original.save(
            path: scratch.statePath, fileSystem: RealFileSystem(), processIdentifier: 1
        )
        #expect(WatchState.load(path: scratch.statePath, fileSystem: RealFileSystem()) == original)

        // The reference reads this file too, and ignores keys it does not know — so the shape must
        // stay a plain object with the two members it expects.
        let text = WatchWorld.read(scratch.statePath)
        #expect(text.contains("\"mcpServersHash\": \"abc123\""))
        #expect(text.contains("\"failures\""))
    }

    // MARK: - W4's backup rules

    @Test("W4 — backups are pruned to ten, newest kept")
    func backupsArePrunedToTen() throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let target = scratch.root.appendingPathComponent("thing.json").path
        try WatchWorld.write("{}", to: target)

        // Twelve copies, each at a distinct instant so the names sort.
        for index in 0 ..< 12 {
            WatchBackup.backUp(
                path: target, into: scratch.paths.backupDirectory,
                fileSystem: RealFileSystem(),
                nowMilliseconds: 1_700_000_000_000 + Double(index) * 1000
            )
        }
        let kept = try FileManager.default
            .contentsOfDirectory(atPath: scratch.paths.backupDirectory)
            .filter { $0.hasPrefix("thing.json.") }
            .sorted()
        #expect(kept.count == WatchBackup.keep)
        // The two oldest are the ones dropped — a prune that kept the oldest would be worse than no
        // prune at all.
        // The two OLDEST are the ones dropped. `|| kept.last != nil` used to be the second half of
        // this and made the whole line always true — a tautology in the one place the prune's
        // direction is checked.
        #expect(kept.first == "thing.json.\(WatchBackup.stamp(1_700_000_002_000))")
        #expect(kept.last == "thing.json.\(WatchBackup.stamp(1_700_000_011_000))")
    }

    @Test("W4 — a fixed mode and a preserved mode are both honoured")
    func modesAreHonoured() throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let fileSystem = RealFileSystem()

        // Preserved: `~/.claude.json`'s rule.
        let preserved = scratch.root.appendingPathComponent("preserved.json").path
        try WatchWorld.write("{}", to: preserved, mode: 0o600)
        try WatchBackup.writeAtomic(
            "{\"a\":1}", toPath: preserved, fileSystem: fileSystem,
            processIdentifier: 1, mode: .preserveExisting
        )
        #expect(try fileSystem.fileMode(atPath: preserved) == 0o600)

        // Fixed: `servers.json`'s rule.
        let fixed = scratch.root.appendingPathComponent("fixed.json").path
        try WatchWorld.write("{}", to: fixed, mode: 0o600)
        try WatchBackup.writeAtomic(
            "{\"a\":1}", toPath: fixed, fileSystem: fileSystem,
            processIdentifier: 1, mode: .fixed(WatchAdoption.routerConfigMode)
        )
        #expect(try fileSystem.fileMode(atPath: fixed) == 0o644)
    }

    // MARK: - X10 / W-D2

    @Test("X10 — ~/.claude.json is resolved from HOME, not from NSHomeDirectory()")
    func homeComesFromTheEnvironment() {
        let paths = WatchPaths(
            environment: ["HOME": "/tmp/fakehome"], homeDirectory: "/Users/somebody"
        )
        // Measured 2026-08-15: node's os.homedir() honours $HOME and NSHomeDirectory() does not, so
        // reproducing the reference requires the environment. It is also what stops a test run
        // adopting servers out of the developer's own file.
        #expect(paths.claudeJSON == "/tmp/fakehome/.claude.json")
        #expect(paths.statePath == "/tmp/fakehome/.claude/mcp-router/watch-state.json")
        #expect(paths.launchdLabel == WatchPaths.defaultLaunchdLabel)
        #expect(
            WatchPaths(environment: ["MCPR_LAUNCHD_LABEL": "scratch"], homeDirectory: "/tmp/x")
                .launchdLabel == "scratch"
        )
    }
}
