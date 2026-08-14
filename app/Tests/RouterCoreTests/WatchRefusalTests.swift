import Foundation
import Testing
@testable import RouterCore

/// The runs that decide **not** to adopt: nothing changed, nothing parseable, nothing eligible.
///
/// Split from ``WatchAdoptionTests`` on the seam the reference itself has — `cmdWatch` decides
/// whether there is anything to do long before it spawns anything, and every clause here is
/// discharged without a child process. Their shared property is that the filesystem is untouched
/// afterwards, which is the property most easily lost in a refactor.
///
/// Every test runs under a scratch `HOME`, which is the whole reason ``WatchPaths`` reads the
/// environment rather than `NSHomeDirectory()`: a watcher that ignored `HOME` would run these
/// against the developer's own `~/.claude.json` and delete servers out of it (X10).
@Suite("Config watcher refusals", .serialized)
struct WatchRefusalTests {
    // MARK: - W1, W2, W8 — the paths that write nothing

    @Test("W1 — an unchanged mcpServers hash is a read, a hash and an exit")
    func fastPathSpawnsNothing() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let started = scratch.root.appendingPathComponent("started")
        let entry = try WatchWorld.childEntry(in: scratch, name: "probe", started: started)
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)
        try WatchWorld.write(WatchWorld.routerConfig([("probe", entry)]), to: scratch.configPath)

        let kicks = RestartRecorder()
        try await WatchWorld.runner(scratch, kicks: kicks).run()
        #expect(FileManager.default.fileExists(atPath: started.path), "the first run must index")

        // The second run is the one under test. Nothing may be spawned and nothing written.
        try? FileManager.default.removeItem(at: started)
        let before = try FileManager.default.attributesOfItem(atPath: scratch.claudeJSON)
        let configBefore = WatchWorld.read(scratch.configPath)
        let stateBefore = WatchWorld.read(scratch.statePath)

        try await WatchWorld.runner(scratch, kicks: kicks).run()

        #expect(
            !FileManager.default.fileExists(atPath: started.path),
            "the fast path spawned a child"
        )
        let after = try FileManager.default.attributesOfItem(atPath: scratch.claudeJSON)
        #expect(
            (before[.modificationDate] as? Date) == (after[.modificationDate] as? Date),
            "the fast path rewrote ~/.claude.json"
        )
        #expect(WatchWorld.read(scratch.configPath) == configBefore)
        #expect(WatchWorld.read(scratch.statePath) == stateBefore)
    }

    @Test("W2 — an unparseable initial read abandons the run and writes nothing")
    func unparseableInitialReadWritesNothing() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let entry = try WatchWorld.childEntry(in: scratch, name: "probe")
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)
        try WatchWorld.write("{ this is not json", to: scratch.claudeJSON)
        _ = entry

        let configBefore = WatchWorld.read(scratch.configPath)
        try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()

        #expect(WatchWorld.read(scratch.configPath) == configBefore)
        #expect(WatchWorld.read(scratch.claudeJSON) == "{ this is not json")
        #expect(
            !FileManager.default.fileExists(atPath: scratch.statePath),
            "a run that abandoned must not seal anything"
        )
        #expect(WatchWorld.read(scratch.logPath).contains("did not parse"))
    }

    @Test("W8 — a missing input or a missing router config exits without sealing")
    func missingInputsWriteNothing() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }

        // No ~/.claude.json at all.
        try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()
        #expect(!FileManager.default.fileExists(atPath: scratch.statePath))

        // Staged servers, but no servers.json to adopt into.
        let entry = try WatchWorld.childEntry(in: scratch, name: "probe")
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)
        try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()
        #expect(
            !FileManager.default.fileExists(atPath: scratch.statePath),
            "the hash must be withheld so the next fire retries once the config exists"
        )
        #expect(WatchWorld.read(scratch.logPath).contains("no router config at"))
    }

    @Test("an unparseable servers.json is refused before any child is spawned")
    func unparseableRouterConfigSpawnsNothing() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let started = scratch.root.appendingPathComponent("started")
        let entry = try WatchWorld.childEntry(in: scratch, name: "probe", started: started)
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)
        try WatchWorld.write("{ not json at all", to: scratch.configPath)

        await #expect(throws: WatchAdoption.Problem.self) {
            try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()
        }
        // The ordering is the claim. The reference parses the router config at `watch.ts:200`,
        // before it constructs a pool, so a corrupt config costs it nothing; a port that discovered
        // the same failure only at the merge would have spawned and torn down real children first.
        #expect(
            !FileManager.default.fileExists(atPath: started.path),
            "a child was spawned for a config that could never be written"
        )
        #expect(WatchWorld.read(scratch.configPath) == "{ not json at all")
        #expect(WatchWorld.serverNames(in: scratch.claudeJSON) == ["probe"])
    }

    // MARK: - W6, W9 — what is and is not a candidate

    @Test("W6/X13 — reserved names and the router's own self-reference are never adopted")
    func reservedAndSelfReferenceAreSkipped() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let selfURL = JSONValue.object([
            JSONMember(key: JSString("type"), value: .string(JSString("http"))),
            JSONMember(
                key: JSString("url"), value: .string(JSString("http://127.0.0.1:8879/mcp"))
            )
        ])
        try WatchWorld.write(
            WatchWorld.stagingFile([
                ("router", WatchWorld.childEntry(in: scratch, name: "router")),
                ("mcp-router", selfURL),
                ("elsewhere", selfURL)
            ]),
            to: scratch.claudeJSON
        )
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)

        try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()

        #expect(WatchWorld.serverNames(in: scratch.configPath) == [])
        // All three staged entries are still there: nothing was adopted, so nothing was deleted.
        #expect(
            WatchWorld.serverNames(in: scratch.claudeJSON).sorted()
                == ["elsewhere", "mcp-router", "router"]
        )
    }

    @Test("W9 — adoption covers every parseable transport, not only stdio")
    func httpEntriesAreAdopted() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        // A remote HTTP upstream on a port that is not the router's, so it is not a self-reference.
        let http = JSONValue.object([
            JSONMember(key: JSString("type"), value: .string(JSString("http"))),
            JSONMember(
                key: JSString("url"), value: .string(JSString("https://example.test/mcp"))
            )
        ])
        try WatchWorld.write(WatchWorld.stagingFile([("remote", http)]), to: scratch.claudeJSON)
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)

        try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()

        // It cannot be indexed — nothing is listening — so it stays staged and is recorded as a
        // failure rather than being silently dropped. What matters for W9 is that it was *tried*:
        // a stdio filter would have skipped it before it ever reached the indexer.
        #expect(WatchWorld.read(scratch.logPath).contains("failed to index \"remote"))
        #expect(WatchWorld.serverNames(in: scratch.claudeJSON) == ["remote"])
    }
}
