import Foundation
import Testing
@testable import RouterCore

/// R30 — copy, verify, remove, and put it back. The other half of `ExtensionIngestTests.swift`,
/// split for the type-body limit rather than for a difference in subject.
///
/// Nothing here reads or writes the real `~/.claude`: every path descends from an
/// ``IngestBench``'s own temporary directory.
@Suite("R30 — applying and undoing an ingest")
struct ExtensionIngestApplyTests {
    @Test("G6 — copy, verify, remove: the router holds the bytes and Claude's path is empty")
    func applyMovesTheBytes() {
        let bench = IngestBench("apply")
        defer { bench.tearDown() }
        let scan = bench.scan()
        let source = "\(bench.claude.root)/skills/graphify"
        let sourceStamp = ExtensionStamp.measure(source)
        let run = bench.ingest().apply(scan.candidates)

        #expect(run.outcomes.count == 6)
        #expect(run.outcomes.allSatisfy { $0.state == .ingested })
        #expect(!FileManager.default.fileExists(atPath: source))

        let stored = bench.store.read(.skills, name: "graphify")
        #expect(stored?.problem == nil)
        #expect(stored?.title == "graphify")
        // Byte-faithful, asserted by digest rather than by file count: two files of the right
        // sizes and the wrong contents would satisfy a count.
        #expect(ExtensionStamp.measure("\(bench.store.root)/skills/graphify")?.digest
            == sourceStamp?.digest)

        // Reversible: Claude's copy is aside, not gone.
        let quarantine = run.outcomes.first { $0.candidate.name == "graphify" }?.quarantinePath
        #expect(quarantine != nil)
        #expect(ExtensionStamp.measure(quarantine ?? "")?.digest == sourceStamp?.digest)
        #expect(run.manifestPath != nil)
    }

    @Test("G7 — settings.json loses exactly the keys that left, and keeps everything else")
    func applyPreservesSettings() {
        let bench = IngestBench("settings")
        defer { bench.tearDown() }
        let path = bench.claude.settingsPath
        let before = ClaudeFixtureTree.untouchableSettingsKeys.map {
            ClaudeFixtureTree.settingsMember($0, at: path)
        }
        let run = bench.ingest().apply(bench.scan().candidates)

        #expect(run.settingsFailure == nil)
        #expect(run.settings?.topLevelBefore == 8)
        #expect(run.settings?.topLevelAfter == 8)
        #expect(ClaudeFixtureTree.settingsKeys(at: path) == [
            "env", "includeCoAuthoredBy", "permissions", "model", "hooks", "statusLine",
            "enabledPlugins", "extraKnownMarketplaces"
        ])
        // Value AND position, for every member this item has no business touching.
        #expect(ClaudeFixtureTree.untouchableSettingsKeys.map {
            ClaudeFixtureTree.settingsMember($0, at: path)
        } == before)

        // The two keys whose plugins left are gone; `swift-lsp@fledgeling-plugins` stayed, because
        // its plugin was unidentifiable and was never moved.
        #expect(ClaudeFixtureTree.settingsMember("enabledPlugins", at: path)
            == "{\"swift-lsp@fledgeling-plugins\":true}")
        #expect(ClaudeFixtureTree.settingsMember("extraKnownMarketplaces", at: path) == "{}")
        #expect(run.settings?.backupPath != nil)
    }

    @Test("G10 — undo puts the bytes and the keys back, from the router's own disk")
    func undoRestores() {
        let bench = IngestBench("undo")
        defer { bench.tearDown() }
        let path = bench.claude.settingsPath
        // The two subtrees that hold extensions. `settings.json` is deliberately outside this
        // comparison: the writer re-serialises it, so its bytes legitimately differ from the
        // fixture's hand-written spacing while every member is restored. Its members are compared
        // as values below, which is the claim that actually matters.
        let skillsBefore = ExtensionStamp.measure("\(bench.claude.root)/skills")
        let pluginsBefore = ExtensionStamp.measure("\(bench.claude.root)/plugins")
        let enabledBefore = ClaudeFixtureTree.settingsMember("enabledPlugins", at: path)
        let run = bench.ingest().apply(bench.scan().candidates)
        #expect(run.outcomes.allSatisfy { $0.state == .ingested })

        let report = ExtensionIngestUndo.undo(
            run.manifest, store: bench.store, fileSystem: RealFileSystem(), clock: bench.clock
        )
        #expect(report.settingsFailure == nil)
        #expect(report.settingsRestored == 3)
        #expect(report.outcomes.allSatisfy { $0.state == .restored })
        #expect(ClaudeFixtureTree.settingsMember("enabledPlugins", at: path) == enabledBefore)
        #expect(ExtensionStamp.measure("\(bench.claude.root)/skills")?.digest
            == skillsBefore?.digest)
        #expect(ExtensionStamp.measure("\(bench.claude.root)/plugins")?.digest
            == pluginsBefore?.digest)
        #expect(bench.store.list(.skills).records.isEmpty)
    }

    @Test("G11 — undo refuses a path somebody else has taken back")
    func undoRefusesAnOccupiedPath() {
        let bench = IngestBench("occupied")
        defer { bench.tearDown() }
        let run = bench.ingest().apply(bench.scan().candidates)
        ClaudeFixtureTree.skill(
            "graphify", at: bench.claude.root, description: "a hand-written replacement"
        )
        let report = ExtensionIngestUndo.undo(
            run.manifest, store: bench.store, fileSystem: RealFileSystem(), clock: bench.clock
        )
        #expect(report.outcomes.first { $0.name == "graphify" }?.state == .skipped)
        // Left alone means left alone: the replacement is still the thing on disk.
        let text = try? String(
            contentsOf: URL(fileURLWithPath: "\(bench.claude.root)/skills/graphify/SKILL.md"),
            encoding: .utf8
        )
        #expect(text?.contains("a hand-written replacement") == true)
        #expect(report.outcomes.filter { $0.state == .restored }.count == 5)
    }

    @Test("G12 — --link-back leaves a link at Claude's path and keeps the registration")
    func linkBackKeepsTheRegistration() {
        let bench = IngestBench("link")
        defer { bench.tearDown() }
        let path = bench.claude.settingsPath
        let enabledBefore = ClaudeFixtureTree.settingsMember("enabledPlugins", at: path)
        let run = bench.ingest().apply(
            bench.scan().candidates, options: ExtensionIngest.Options(linkBack: true)
        )
        #expect(run.outcomes.allSatisfy { $0.state == .linked })
        // No key was withdrawn, because Claude can still reach every one of them.
        #expect(run.settings == nil)
        #expect(ClaudeFixtureTree.settingsMember("enabledPlugins", at: path) == enabledBefore)

        let source = "\(bench.claude.root)/skills/graphify"
        let target = try? FileManager.default.destinationOfSymbolicLink(atPath: source)
        #expect(target == "\(bench.store.root)/skills/graphify")
        // The link resolves to the router's copy, which is the only copy of the bytes.
        let text = try? String(
            contentsOf: URL(fileURLWithPath: "\(source)/SKILL.md"), encoding: .utf8
        )
        #expect(text?.contains("name: graphify") == true)
    }

    @Test("G13 — a run manifest round-trips through its own bytes")
    func manifestRoundTrips() {
        let bench = IngestBench("manifest")
        defer { bench.tearDown() }
        let run = bench.ingest().apply(bench.scan().candidates)
        guard let path = run.manifestPath,
              let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8),
              let parsed = IngestManifestJSON.parse(text)
        else {
            #expect(Bool(false), "the manifest could not be read back")
            return
        }

        #expect(parsed.runId == run.runId)
        #expect(parsed.entries.count == run.manifest.entries.count)
        #expect(parsed.removedSettingsKeys.count == 3)
        #expect(parsed.entries.allSatisfy { $0.quarantinePath != nil })
        // Everything an undo needs is in the file, so an undo can run in a process that never saw
        // the run: parse it and reverse it, with no scan and no network.
        let report = ExtensionIngestUndo.undo(
            parsed, store: DiskExtensionStore(root: parsed.storeRoot, clock: bench.clock),
            fileSystem: RealFileSystem(), clock: bench.clock
        )
        #expect(report.outcomes.allSatisfy { $0.state == .restored })
    }
}
