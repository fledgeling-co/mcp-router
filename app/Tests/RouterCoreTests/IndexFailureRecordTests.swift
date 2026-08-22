import Foundation
import Testing
@testable import RouterCore

/// R17 — an upstream whose index fails leaves a record of that failure, whatever route it came in
/// by and whichever point of the index it died at.
///
/// THE MEASUREMENT THIS IS WRITTEN AGAINST, taken from the owner's machine on 2026-08-21: 14
/// upstreams configured, 13 manifest rows, 12 serving. `lifeline` and `namecheap` fail identically
/// — `MCP error -32000: Connection closed` — and only `lifeline` had a row. `namecheap` reported
/// `error: None, tools: 0, state: idle`, so nothing anywhere said it had ever been attempted.
///
/// The divergence was never in the failure. Both took the same branch of `buildManifest`. It was in
/// the ROUTE: `namecheap` is declared in `~/.claude.json` as well as in the router's own list, so
/// the watcher ran over it every five minutes, and the watcher deleted the row that
/// `buildManifest` had just written. `lifeline` is not staged, so nothing ran that deletion over it
/// and the row `index --force` wrote survived. `watch-state.json` held `namecheap`'s reason the
/// whole time, in a file no surface reads.
///
/// The fixture below is therefore two servers failing at two DIFFERENT points, adopted by the route
/// that used to discard the record — which is what makes this a property of the indexer rather than
/// a patch aimed at one server's name.
@Suite("A failed index leaves a record", .serialized)
struct IndexFailureRecordTests {
    /// The two points an index can fail at, named by what has happened when it does.
    ///
    /// `deadcommand` has no process at all: `pool.lease` throws before any session exists. Its
    /// `started` marker can never appear, which is what makes the distinction observable rather
    /// than asserted. `dieslisting` completes `initialize`, writes its marker, and then exits on
    /// `tools/list` — the point the owner's two upstreams both reach.
    private struct Fixture {
        let scratch: WatchWorld.Scratch
        let startedMarker: URL
    }

    private func stageTwoFailures() throws -> Fixture {
        let scratch = try WatchWorld.make()
        let started = scratch.root.appendingPathComponent("dieslisting.started")
        let diesListing = try WatchWorld.childEntry(
            in: scratch, name: "dieslisting", started: started, fail: "list"
        )
        let deadCommand = JSONValue.object([
            JSONMember(
                key: JSString("command"),
                value: .string(JSString("/nonexistent/definitely-not-a-server"))
            )
        ])
        let entries = [("deadcommand", deadCommand), ("dieslisting", diesListing)]
        // Declared in BOTH files, which is `namecheap`'s exact shape: a router upstream that is
        // also a staged Claude Code entry. Seeding servers.json with the same definitions is also
        // what keeps `configChanged` false, so no run here ever issues a launchctl kick.
        try WatchWorld.write(WatchWorld.stagingFile(entries), to: scratch.claudeJSON)
        try WatchWorld.write(WatchWorld.routerConfig(entries), to: scratch.configPath)
        return Fixture(scratch: scratch, startedMarker: started)
    }

    @Test("two upstreams failing at different points each leave a manifest row")
    func bothFailurePointsAreRecorded() async throws {
        let fixture = try stageTwoFailures()
        defer { WatchWorld.remove(fixture.scratch) }

        try await WatchWorld.runner(fixture.scratch, kicks: RestartRecorder()).run()

        let manifest = ManifestIO.load(
            path: fixture.scratch.manifestPath, fileSystem: RealFileSystem()
        ).manifest

        for name in ["deadcommand", "dieslisting"] {
            let entry = manifest.entry(named: name)
            #expect(entry != nil, "\(name) left no manifest row at all")
            #expect(
                entry?.error?.string.isEmpty == false,
                "\(name)'s row carries no reason, so a reader still cannot tell it was attempted"
            )
            #expect(entry?.tools.isEmpty == true, "\(name) must serve nothing while it is broken")
        }

        // The two really did die at different points, and this is measured rather than assumed:
        // the marker exists only if a child ran far enough to answer `initialize`.
        #expect(
            FileManager.default.fileExists(atPath: fixture.startedMarker.path),
            "dieslisting never started, so it did not fail at the point this fixture claims"
        )
        #expect(
            manifest.entry(named: "deadcommand")?.error != manifest
                .entry(named: "dieslisting")?.error,
            "two failure points reporting one identical string would make this fixture prove nothing"
        )

        // Neither is adopted: the gate on `entry.error` is what the deleted row used to be for,
        // and it still holds with the row present.
        #expect(
            WatchWorld.serverNames(in: fixture.scratch.claudeJSON).sorted()
                == ["deadcommand", "dieslisting"],
            "a server that cannot index must stay where the user declared it"
        )
    }

    /// R17 acceptance 4 — R14's report reads the row and shows the reason.
    ///
    /// Without a row, `indexError` is nil and the row reads "Re-index it and see what it reports",
    /// which is the report filing a server whose reason the router already had as a blameless
    /// not-an-auth-problem. The reason is what turns that into an actionable line.
    @Test("the four-state report shows the reason for an upstream that failed to index")
    func stateReportCarriesTheReason() async throws {
        let fixture = try stageTwoFailures()
        defer { WatchWorld.remove(fixture.scratch) }

        try await WatchWorld.runner(fixture.scratch, kicks: RestartRecorder()).run()

        let loaded = try ConfigLoader.load(
            options: .init(configPath: fixture.scratch.configPath),
            home: fixture.scratch.routerHome
        )
        let manifest = ManifestIO.load(
            path: fixture.scratch.manifestPath, fileSystem: RealFileSystem()
        ).manifest
        let rows = await UpstreamStateReport.rows(
            config: loaded.config,
            manifest: manifest,
            auth: FileAuthStore(authDir: fixture.scratch.routerHome.authDir),
            nowMilliseconds: 1_700_000_000_000,
            entry: "mcp-router"
        )

        #expect(rows.count == 2)
        for row in rows {
            #expect(row.kind == .notAnAuthProblem, "\(row.name) is a stdio child, not an auth story")
            #expect(
                row.detail?.isEmpty == false,
                "\(row.name) reached the report with no reason, which is the R17 defect"
            )
            #expect(
                row.remedy.contains("Fix the error below"),
                "\(row.name) was told to re-index and see, with the answer already in hand"
            )
        }

        // The same set reaches the model through `initialize`'s instructions, which is the surface
        // that answers "why can't you use namecheap" without the assistant having to guess.
        let instructions = UpstreamStateReport.instructions(from: rows)
        #expect(instructions.contains("deadcommand"))
        #expect(instructions.contains("dieslisting"))
    }
}
