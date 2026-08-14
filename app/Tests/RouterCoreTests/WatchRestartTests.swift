import Foundation
import Testing
@testable import RouterCore

/// W-D1 / D7 — the restart the reference loses, and the two ways it can be lost.
///
/// The reference writes `servers.json`, then returns early at `watch.ts:299` when the pre-delete
/// re-read fails to parse — past the `restartRouter()` at `:336`. On the next fire the config
/// already matches, `configChanged` is false, and the restart is never issued: the adopted server
/// can never reach the running router.
///
/// The kickstart is injected in every test here. Measured on 2026-08-15, `gg.rhodes.mcp-router` is
/// loaded and serving on this machine, so a test that ran the real one would restart the
/// developer's own router (X8a).
@Suite("Config watcher restarts", .serialized)
struct WatchRestartTests {
    /// Stage a server, hold its child at the door, and corrupt `~/.claude.json` while it is held.
    ///
    /// Deterministic rather than a race: the child announces itself, the corruption lands, then the
    /// child is released. A `sleep` that lost to a fast index would exercise the ordinary path and
    /// report it as a pass.
    private func runIntoTheD7Window(
        _ scratch: WatchWorld.Scratch, kicks: RestartRecorder
    ) async throws {
        let started = scratch.root.appendingPathComponent("started")
        let gate = scratch.root.appendingPathComponent("gate")
        let entry = try WatchWorld.childEntry(
            in: scratch, name: "probe", started: started, gate: gate
        )
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)

        let saboteur = Task.detached {
            _ = WatchWorld.waitUntil(seconds: 30) {
                FileManager.default.fileExists(atPath: started.path)
            }
            try WatchWorld.write("{ truncated mid-write", to: scratch.claudeJSON)
            FileManager.default.createFile(atPath: gate.path, contents: Data("1".utf8))
        }
        try await WatchWorld.runner(scratch, kicks: kicks).run()
        try await saboteur.value
    }

    @Test("W-D1/X6 — the restart survives an unparseable re-read, which the reference loses")
    func restartIsIssuedBeforeTheStagingWrite() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let kicks = RestartRecorder()

        try await runIntoTheD7Window(scratch, kicks: kicks)

        // servers.json was written — which is exactly the state the reference reaches, and from
        // which it never restarts.
        #expect(WatchWorld.serverNames(in: scratch.configPath) == ["probe"])
        let log = WatchWorld.read(scratch.logPath)
        #expect(log.contains("no longer parses"), "the D7 window was not actually entered")
        #expect(
            kicks.issued == ["scratch-label"],
            "the restart was lost on the path the reference loses it on"
        )
        #expect(log.contains("restarted scratch-label to pick up the new upstream"))
        // And the hash is withheld, so the next fire retries the staging delete.
        let state = WatchState.load(path: scratch.statePath, fileSystem: RealFileSystem())
        #expect(state.mcpServersHash == nil)
        #expect(state.restartPending == false, "a successful restart clears the debt")
    }

    @Test("X7 — a failed restart is owed, and the next fire retries it")
    func failedRestartIsOwedAndRetried() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let entry = try WatchWorld.childEntry(in: scratch, name: "probe")
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)

        // launchd refuses — the reference logs this and moves on, losing the restart permanently.
        let failing = RestartRecorder(failing: "Could not find service")
        try await WatchWorld.runner(scratch, kicks: failing).run()

        #expect(failing.issued == ["scratch-label"])
        var state = WatchState.load(path: scratch.statePath, fileSystem: RealFileSystem())
        #expect(state.restartPending, "a failed restart must be recorded as owed")
        #expect(
            WatchWorld.read(scratch.logPath)
                .contains("could not restart scratch-label (Could not find service); run it manually")
        )

        // The next fire has nothing to adopt — the staging entry is gone and the hash is sealed —
        // and must still pay the debt.
        let succeeding = RestartRecorder()
        try await WatchWorld.runner(scratch, kicks: succeeding).run()
        #expect(
            succeeding.issued == ["scratch-label"],
            "an owed restart must be retried even on a fire with nothing to do"
        )
        #expect(WatchWorld.read(scratch.logPath).contains("retrying a restart owed from an earlier fire"))
        state = WatchState.load(path: scratch.statePath, fileSystem: RealFileSystem())
        #expect(state.restartPending == false)
    }

    @Test("X7 — the debt is on disk before the config write, so a crash cannot drop it")
    func restartIsOwedBeforeTheWriteLands() throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)

        // The ordering claim, checked at the only moment it is observable: inside the lock, after
        // the debt has been persisted and before the rename. A `SIGKILL` here is the window the
        // reviewer found, and this asserts the state file already carries the debt.
        var seen: WatchState?
        let changed = try WatchAdoption.merge(
            adopted: [("probe", .object([
                JSONMember(key: JSString("command"), value: .string(JSString("true")))
            ]))],
            into: WatchAdoption.Destination(
                path: scratch.configPath,
                backupDirectory: scratch.paths.backupDirectory,
                processIdentifier: 1,
                lockTimeoutMs: 5000
            ),
            fileSystem: RealFileSystem(),
            nowMilliseconds: 1_700_000_000_000
        ) {
            try WatchState(restartPending: true).save(
                path: scratch.statePath, fileSystem: RealFileSystem(), processIdentifier: 1
            )
            seen = WatchState.load(path: scratch.statePath, fileSystem: RealFileSystem())
            #expect(
                WatchWorld.serverNames(in: scratch.configPath) == [],
                "the debt must be durable BEFORE the rename, not after"
            )
        }

        #expect(changed)
        #expect(seen?.restartPending == true)
        #expect(WatchWorld.serverNames(in: scratch.configPath) == ["probe"])
    }

    @Test("no config change means no restart, on both routers")
    func unchangedConfigDoesNotRestart() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let entry = try WatchWorld.childEntry(in: scratch, name: "probe")
        // Already present in the router's list, identically. The reference's `configChanged` stays
        // false here (`watch.ts:273`), so neither router restarts — which is what lets the parity
        // lanes exercise adoption without bouncing a real service (X12b).
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)
        try WatchWorld.write(WatchWorld.routerConfig([("probe", entry)]), to: scratch.configPath)

        let kicks = RestartRecorder()
        try await WatchWorld.runner(scratch, kicks: kicks).run()

        #expect(kicks.issued.isEmpty, "an unchanged config must not restart the router")
        #expect(
            WatchWorld.serverNames(in: scratch.claudeJSON) == [],
            "the entry is still adopted and still deleted from staging"
        )
    }
}
