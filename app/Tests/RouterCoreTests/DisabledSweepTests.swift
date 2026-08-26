import Foundation
import Testing
@testable import RouterCore

/// M29, oracle line 5 — **the automatic index sweeps skip a disabled server, and `reindex` does
/// not.** The two halves are a pair and neither says anything on its own: a sweep that skipped
/// everything would satisfy the first half and break the feature.
///
/// Both Swift guards were unmeasured when this suite was written. Deleting the `disabled` term from
/// the watcher's `toIndex` filter and from the serving process's stale warning, together, left all
/// 1960 tests passing — the clause was stated in two comments and asserted nowhere.
@Suite("M29 — the automatic sweeps and the switch", .serialized)
struct DisabledSweepTests {
    // MARK: - The serving process's startup warning

    private static func upstreams(_ json: String) throws -> [UpstreamConfig] {
        let parsed = try JSONParser.parse(json)
        return (parsed.member("mcpServers")?.asObjectMembers ?? []).compactMap { member in
            guard case let .upstream(upstream) = ServerParser.parse(
                name: member.key.string, raw: member.value
            ) else { return nil }
            return upstream
        }
    }

    /// A cold manifest makes **every** upstream stale, so the only thing that can keep one out of
    /// the warning is the switch. That is what makes this test about `disabled` rather than about
    /// `isStale`.
    @Test("the startup warning names a stale server and never a disabled one")
    func theWarningSkipsTheDisabled() throws {
        let both = try Self.upstreams("""
        {
          "mcpServers": {
            "live": { "command": "/bin/echo" },
            "off": { "command": "/bin/echo", "disabled": true }
          }
        }
        """)
        #expect(both.count == 2, "the fixture stopped parsing; the assertions below prove nothing")
        #expect(both.map(\.disabled) == [nil, true])

        let warning = try #require(
            RouterService.staleManifestWarning(.empty, upstreams: both),
            "a cold manifest with a live upstream produced no warning at all"
        )
        #expect(warning == .notInManifest(count: 1, names: ["live"]))
        // The rendered line is what `parity-log.sh` diffs, so the name is asserted in the text as
        // well as in the payload — a count of 1 beside a list of two would still read wrong.
        #expect(!warning.message.contains("off"))
        #expect(warning.message.contains("live"))
    }

    @Test("a router whose only stale servers are disabled warns about nothing")
    func nothingToWarnAbout() throws {
        let off = try Self.upstreams("""
        { "mcpServers": { "off": { "command": "/bin/echo", "disabled": true } } }
        """)
        #expect(RouterService.staleManifestWarning(.empty, upstreams: off) == nil)

        // The control, on the same fixture with the switch cleared: the warning appears. Without
        // it, an implementation that always returned `nil` would pass the line above.
        var on = off
        on[0].disabled = nil
        #expect(RouterService.staleManifestWarning(.empty, upstreams: on)
            == .notInManifest(count: 1, names: ["off"]))
    }

    // MARK: - The watcher's sweep, end to end

    /// Asserted by whether a **child process ever ran**, not by reading a filtered list: the point
    /// of the guard is that the router does not spawn something for a server that serves nobody,
    /// and the child announces itself by creating a file before it answers anything.
    @Test("a disabled staged entry is never spawned to be indexed")
    func theWatcherDoesNotSpawnADisabledServer() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let started = scratch.root.appendingPathComponent("off.started")
        let entry = try Self.disabling(
            WatchWorld.childEntry(in: scratch, name: "off", started: started)
        )
        try WatchWorld.write(
            WatchWorld.stagingFile([("off", entry)]), to: scratch.claudeJSON, mode: 0o600
        )
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)

        try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()

        #expect(
            !FileManager.default.fileExists(atPath: started.path),
            "the sweep spawned a child for a server the user had switched off"
        )
        #expect(
            WatchWorld.serverNames(in: scratch.configPath).isEmpty,
            "a server that was never indexed was adopted anyway"
        )
    }

    /// The control, and the reason it is a separate test rather than a second half: it exercises
    /// the same entry with the same child through the same runner, so the assertion above measures
    /// the switch and not a scratch world in which nothing was ever going to be indexed.
    @Test("the same entry with the switch cleared is spawned, indexed and adopted")
    func theWatcherDoesSpawnAnEnabledServer() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let started = scratch.root.appendingPathComponent("on.started")
        let entry = try WatchWorld.childEntry(in: scratch, name: "on", started: started)
        try WatchWorld.write(
            WatchWorld.stagingFile([("on", entry)]), to: scratch.claudeJSON, mode: 0o600
        )
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)

        try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()

        #expect(FileManager.default.fileExists(atPath: started.path), "the child never ran")
        #expect(WatchWorld.serverNames(in: scratch.configPath) == ["on"])
    }

    /// `{"command": …, "args": […]}` plus the switch. Written by hand rather than through a helper
    /// parameter, so the two tests above differ by exactly this member.
    private static func disabling(_ entry: JSONValue) throws -> JSONValue {
        guard case let .object(members) = entry else {
            throw WatchFixtureProblem.notAnObject
        }
        return .object(members + [
            JSONMember(key: JSString("disabled"), value: .bool(true))
        ])
    }
}

enum WatchFixtureProblem: Error {
    case notAnObject
}
