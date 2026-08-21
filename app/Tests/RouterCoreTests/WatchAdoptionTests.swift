import Foundation
import Testing
@testable import RouterCore

/// The watcher's own clauses — W1 through W9 — against real files and real children.
///
/// Every test here runs under a scratch `HOME`, which is the whole reason ``WatchPaths`` reads the
/// environment rather than `NSHomeDirectory()`: a watcher that ignored `HOME` would run these
/// against the developer's own `~/.claude.json` and delete servers out of it (X10).
@Suite("Config watcher", .serialized)
struct WatchAdoptionTests {
    // MARK: - W3, W5, W7 — the adoption itself

    @Test("W3/W5/W7 — a server is indexed, adopted, deleted from staging, and the hash sealed")
    func adoptionEndToEnd() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let entry = try WatchWorld.childEntry(in: scratch, name: "probe")
        try WatchWorld.write(
            WatchWorld.stagingFile([("probe", entry), ("keepme", .object([
                JSONMember(key: JSString("note"), value: .string(JSString("not adoptable")))
            ]))]),
            to: scratch.claudeJSON,
            mode: 0o600
        )
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)

        let kicks = RestartRecorder()
        try await WatchWorld.runner(scratch, kicks: kicks).run()

        #expect(WatchWorld.serverNames(in: scratch.configPath) == ["probe"])
        #expect(
            WatchWorld.serverNames(in: scratch.claudeJSON) == ["keepme"],
            "the adopted entry must be deleted from staging and nothing else touched"
        )
        // W4 — the mode survives.
        let mode = try RealFileSystem().fileMode(atPath: scratch.claudeJSON)
        #expect(mode == 0o600, "~/.claude.json's mode was not preserved (got \(String(mode, radix: 8)))")
        // W4 — both writes were backed up.
        let backups = try FileManager.default
            .contentsOfDirectory(atPath: scratch.paths.backupDirectory)
        #expect(backups.contains { $0.hasPrefix(".claude.json.") })
        #expect(backups.contains { $0.hasPrefix("servers.json.") })
        // X6/W-D1 — the restart was issued as soon as servers.json changed.
        #expect(kicks.issued == ["scratch-label"])

        // W7 — the hash is of what is on disk NOW, so the fire our own write triggers is fast.
        let state = WatchState.load(path: scratch.statePath, fileSystem: RealFileSystem())
        let onDisk = StableHash.hash(
            of: .object(WatchStaging.stagedServers(of: WatchWorld.json(scratch.claudeJSON) ?? .null))
        )
        #expect(state.mcpServersHash == onDisk)
        #expect(state.restartPending == false)
    }

    @Test("W5 — an entry edited while it was being indexed is left in place")
    func editedWhileIndexingIsLeftAlone() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let started = scratch.root.appendingPathComponent("started")
        let gate = scratch.root.appendingPathComponent("gate")
        let entry = try WatchWorld.childEntry(
            in: scratch, name: "probe", started: started, gate: gate
        )
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)

        // Deterministic, not a sleep: wait for the child to announce itself, edit the staged entry
        // while it is held at the door, then release it.
        let editor = Task.detached {
            _ = WatchWorld.waitUntil(seconds: 30) {
                FileManager.default.fileExists(atPath: started.path)
            }
            let edited = try WatchWorld.childEntry(
                in: scratch, name: "probe", started: started, gate: gate, tool: "edited"
            )
            try WatchWorld.write(
                WatchWorld.stagingFile([("probe", edited)]), to: scratch.claudeJSON
            )
            FileManager.default.createFile(atPath: gate.path, contents: Data("1".utf8))
        }

        try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()
        try await editor.value

        #expect(
            WatchWorld.serverNames(in: scratch.claudeJSON) == ["probe"],
            "an entry edited during indexing must not be deleted"
        )
        let log = WatchWorld.read(scratch.logPath)
        #expect(log.contains("changed in ~/.claude.json while it was being indexed"))
        #expect(log.contains("still pending (not adopted): probe"))
        // W8 — pending withholds the hash so the next fire re-indexes the edited definition.
        let state = WatchState.load(path: scratch.statePath, fileSystem: RealFileSystem())
        #expect(state.mcpServersHash == nil)
    }

    @Test("W5 — an entry deleted while it was being indexed is not resurrected")
    func deletedWhileIndexingIsNotResurrected() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let started = scratch.root.appendingPathComponent("started")
        let gate = scratch.root.appendingPathComponent("gate")
        let entry = try WatchWorld.childEntry(
            in: scratch, name: "probe", started: started, gate: gate
        )
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)

        let editor = Task.detached {
            _ = WatchWorld.waitUntil(seconds: 30) {
                FileManager.default.fileExists(atPath: started.path)
            }
            try WatchWorld.write(WatchWorld.stagingFile([]), to: scratch.claudeJSON)
            FileManager.default.createFile(atPath: gate.path, contents: Data("1".utf8))
        }

        try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()
        try await editor.value

        #expect(WatchWorld.serverNames(in: scratch.claudeJSON) == [])
    }

    // MARK: - W3 — the backoff

    @Test("W3 — a failure backs off for five minutes, and an edit retries at once")
    func failureBackoffIsHashSensitive() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let clock = ManualClock(milliseconds: 1_700_000_000_000)
        let broken = JSONValue.object([
            JSONMember(
                key: JSString("command"),
                value: .string(JSString("/nonexistent/definitely-not-a-server"))
            )
        ])
        try WatchWorld.write(WatchWorld.stagingFile([("broken", broken)]), to: scratch.claudeJSON)
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)

        try await WatchWorld.runner(scratch, kicks: RestartRecorder(), clock: clock).run()
        var state = WatchState.load(path: scratch.statePath, fileSystem: RealFileSystem())
        #expect(state.failures["broken"] != nil, "a failed index must be recorded")
        #expect(state.mcpServersHash == nil, "a pending name withholds the hash")
        // R17 — the failure is recorded in BOTH places, and neither substitutes for the other.
        // The backoff above is the retry policy; the manifest row below is what `/servers` and
        // `UpstreamStateReport` read. This used to assert the entry was `nil`, and that deletion
        // is why `namecheap` reported `error: None, tools: 0, state: idle` on the owner's machine.
        let manifest = ManifestIO.load(
            path: scratch.manifestPath, fileSystem: RealFileSystem()
        ).manifest
        let brokenEntry = manifest.entry(named: "broken")
        #expect(brokenEntry != nil, "a failed index must leave a manifest row, not nothing")
        #expect(brokenEntry?.error?.string.isEmpty == false, "and the row must carry the reason")
        #expect(brokenEntry?.tools.isEmpty == true, "with no tools, so nothing is served from it")

        // Inside the window: no spawn is attempted, so no new failure is recorded at the new time.
        clock.advance(by: 60000)
        try await WatchWorld.runner(scratch, kicks: RestartRecorder(), clock: clock).run()
        state = WatchState.load(path: scratch.statePath, fileSystem: RealFileSystem())
        #expect(state.failures["broken"]?.at == 1_700_000_000_000, "it retried inside the backoff")

        // Past the window: retried.
        clock.advance(by: 5 * 60000)
        try await WatchWorld.runner(scratch, kicks: RestartRecorder(), clock: clock).run()
        state = WatchState.load(path: scratch.statePath, fileSystem: RealFileSystem())
        #expect(state.failures["broken"]?.at == 1_700_000_360_000, "the backoff never expired")

        // An edited definition retries immediately, because the recorded hash no longer matches.
        let editedBroken = JSONValue.object([
            JSONMember(
                key: JSString("command"), value: .string(JSString("/nonexistent/also-not-a-server"))
            )
        ])
        try WatchWorld.write(
            WatchWorld.stagingFile([("broken", editedBroken)]), to: scratch.claudeJSON
        )
        clock.advance(by: 1000)
        try await WatchWorld.runner(scratch, kicks: RestartRecorder(), clock: clock).run()
        state = WatchState.load(path: scratch.statePath, fileSystem: RealFileSystem())
        #expect(
            state.failures["broken"]?.at == 1_700_000_361_000,
            "an edited definition must not wait out the old definition's backoff"
        )
    }

    @Test("W3 — a failure record for a name no longer staged is dropped")
    func staleFailureRecordsArePruned() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let broken = JSONValue.object([
            JSONMember(key: JSString("command"), value: .string(JSString("/nonexistent/nope")))
        ])
        try WatchWorld.write(WatchWorld.stagingFile([("broken", broken)]), to: scratch.claudeJSON)
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)
        try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()
        #expect(
            WatchState.load(path: scratch.statePath, fileSystem: RealFileSystem())
                .failures["broken"] != nil
        )

        // The user removes it from staging, and a different server appears.
        let entry = try WatchWorld.childEntry(in: scratch, name: "probe")
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)
        try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()

        let state = WatchState.load(path: scratch.statePath, fileSystem: RealFileSystem())
        #expect(state.failures["broken"] == nil, "a record for an unstaged name is dead weight")
    }

    // MARK: - X14 / W-D7

    @Test("X14/W-D7 — a flat servers.json is refused rather than overwritten")
    func flatRouterConfigIsRefused() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let entry = try WatchWorld.childEntry(in: scratch, name: "probe")
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)
        // The trap shape: servers at the top level, no `mcpServers` wrapper. The reference creates
        // an empty `mcpServers` over this and writes it back, discarding `existing` entirely.
        let flat = #"{"existing": {"command": "true", "args": []}}"#
        try WatchWorld.write(flat, to: scratch.configPath)

        await #expect(throws: WatchAdoption.Problem.flatRouterConfig(path: scratch.configPath)) {
            try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()
        }
        #expect(WatchWorld.read(scratch.configPath) == flat, "the flat config was modified")
        #expect(WatchWorld.serverNames(in: scratch.claudeJSON) == ["probe"])
    }
}
