import Foundation
import Testing
@testable import RouterCore

/// The corpus walk and one whole pass, against a **real** directory tree.
///
/// `MemoryFileSystem.contentsOfDirectory` lists only the files immediately under a prefix, so a
/// nested fixture is invisible to it and a recursion proven against it would be proven against
/// something that is not a directory tree. That is ``ExtensionStoreTests``' reason for driving the
/// store against real temporary directories, and it applies here for the same reason: the walk is a
/// filesystem property.
///
/// It is also the only place the whole path is exercised end to end — walk, scan, ledger, append,
/// fold — through `FileManager` rather than through a double that agrees with the code by
/// construction.
@Suite("The corpus, on a real disk")
struct TranscriptCorpusTests {
    private static func scratch() -> String {
        let path = NSTemporaryDirectory() + "mcprouter-f5-" + UUID().uuidString
        try? FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true
        )
        return path
    }

    private static func write(_ text: String, to path: String) {
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try? Data(text.utf8).write(to: URL(fileURLWithPath: path))
    }

    private static func line(_ ts: String, _ tool: String, skill: String? = nil) -> String {
        let input = skill.map { #"{"skill":"\#($0)"}"# } ?? "{}"
        return #"{"type":"assistant","timestamp":"\#(ts)","message":{"content":"#
            + #"[{"type":"tool_use","name":"\#(tool)","input":\#(input)}]}}"#
    }

    /// Claude Code nests one level (`projects/<slug>/<session>.jsonl`); this fixture nests two, so
    /// a walk that only descended once would find three of the four files and look correct.
    @Test("The walk finds nested session files, sorts them, and ignores everything else")
    func walkIsRecursiveAndSorted() {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        Self.write("{}", to: "\(root)/a/one.jsonl")
        Self.write("{}", to: "\(root)/a/deeper/two.jsonl")
        Self.write("{}", to: "\(root)/b/three.jsonl")
        Self.write("not a session", to: "\(root)/b/notes.md")

        let walk = TranscriptCorpus.files(under: root, fileSystem: RealFileSystem())
        #expect(walk.paths.count == 3)
        #expect(walk.paths.allSatisfy { $0.hasSuffix(".jsonl") })
        #expect(walk.paths == walk.paths.sorted())
        #expect(walk.unreadableDirectories == 0)
    }

    @Test("A root that is not there is counted rather than reported as an empty corpus")
    func missingRootIsCounted() {
        let walk = TranscriptCorpus.files(
            under: NSTemporaryDirectory() + "mcprouter-f5-absent-" + UUID().uuidString,
            fileSystem: RealFileSystem()
        )
        #expect(walk.paths.isEmpty)
        // The distinction the count exists for: a corpus with nothing in it and a corpus behind an
        // unreadable path produce the same file list, and only this number tells them apart.
        #expect(walk.unreadableDirectories == 1)
    }

    /// Walk, scan, seed the ledger, append, fold — through `FileManager`, with the two boundaries
    /// arranged so the same capability lands on both sides of the attribution rule.
    @Test("One whole pass over a real tree attributes what it can and credits nothing else")
    func wholePassOverRealFiles() {
        let root = Self.scratch()
        let home = Self.scratch()
        defer {
            try? FileManager.default.removeItem(atPath: root)
            try? FileManager.default.removeItem(atPath: home)
        }
        Self.write(
            [
                // After the newest boundary — attributable.
                Self.line("2026-08-26T09:00:00.000Z", "Skill", skill: "trawl:trawl"),
                Self.line("2026-08-26T10:00:00.000Z", "Skill", skill: "trawl:trawl"),
                // Between the boundaries — superseded, and credited to neither version.
                Self.line("2026-08-23T09:00:00.000Z", "Skill", skill: "trawl:trawl"),
                // Three classes that produce no event, each counted as its own. Written out
                // separately because the first draft folded the last two together and the
                // assertion below caught it: a line with no timestamp is `withoutTimestamp`, and
                // only a line that HAS one and holds no tool call is `notAnInvocation`.
                Self.line("2026-08-26T09:30:00.000Z", "Bash"),
                #"{"type":"assistant","timestamp":"2026-08-26T09:31:00.000Z","message":{"content":[]}}"#,
                #"{"type":"assistant","message":{"content":[]}}"#
            ].joined(separator: "\n") + "\n",
            to: "\(root)/project/session.jsonl"
        )

        let history = InvocationHistory(
            sources: [TranscriptSource(harness: "claude-code", root: root)],
            invocationsPath: "\(home)/invocations.jsonl",
            ledgerPath: "\(home)/versions.jsonl",
            watermarkPath: "\(home)/watermarks.json"
        )
        history.observe([
            VersionObservation(
                ts: "2026-08-22T00:00:00.000Z", kind: .plugin, name: "trawl@fledgeling",
                version: "1.4.0", source: "test"
            ),
            VersionObservation(
                ts: "2026-08-25T00:00:00.000Z", kind: .plugin, name: "trawl@fledgeling",
                version: "1.4.2", source: "test"
            )
        ])
        let accounting = history.refresh()
        #expect(accounting.filesRead == 1)
        #expect(accounting.builtInTool == 1)
        #expect(accounting.notAnInvocation == 1)
        #expect(accounting.withoutTimestamp == 1)

        // 2026-08-27T12:00:00.000Z — the window is the seven whole days ending that day.
        let window = history.window(nowMilliseconds: 1_787_832_000_000, days: 7)
        #expect(window.rows.count == 1)
        #expect(window.rows.first?.version == "1.4.2")
        #expect(window.rows.first?.runs == 2)
        #expect(window.supersededRuns == 1)
        #expect(window.totalRuns == 3)

        // The accounting on the window is the SCAN's, not the log's. An earlier version filled it
        // from `invocations.jsonl`'s own line count, so `linesRead` on the wire counted invocations
        // while wearing the name of a transcript-line count — G4's subject, and invisible to any
        // test that only checked it was non-zero. `builtInTool` is the discriminator: the log
        // cannot produce it, so a window reporting 1 here can only be carrying the scan's figures.
        #expect(window.accounting.builtInTool == 1)
        #expect(window.accounting.withoutTimestamp == 1)
        #expect(window.accounting.linesRead == accounting.linesRead)

        // A second pass opens nothing and adds nothing — the watermark, over real stat data rather
        // than a seeded stamp.
        let again = history.refresh()
        #expect(again.filesSkipped == 1)
        #expect(again.filesRead == 0)
        #expect(history.window(nowMilliseconds: 1_787_832_000_000, days: 7).totalRuns == 3)

        // Nothing the transcript carried beyond the four members reached the log on disk.
        let written = (try? String(
            contentsOf: URL(fileURLWithPath: "\(home)/invocations.jsonl"), encoding: .utf8
        )) ?? ""
        #expect(written.contains(#""name":"trawl:trawl""#))
        #expect(!written.contains("tool_use"))
        #expect(!written.contains("input"))
    }
}

/// Seeding the ledger from Claude's plugin register — the step without which every run reads
/// `unestablished` and the table credits nothing at all.
///
/// It has its own suite because it is the piece most likely to be built, tested and then never
/// called: `registry` and `authFlow` each existed, were unit-tested and shipped `nil` in
/// `RouterServiceDispatch` (`control-registry-search`, `D-p1-a`), and this item reproduced the same
/// shape once already with `ControlDeps.invocations`.
@Suite("Seeding the boundary set")
struct LedgerSeedTests {
    private static let register = #"""
    {"version":2,"plugins":{
      "trawl@fledgeling":[{"version":"1.4.2","installedAt":"2025-12-03T05:30:52.695Z",
        "lastUpdated":"2026-08-25T00:00:00.000Z","gitCommitSha":"423563c"}],
      "half@fledgeling":[{"version":"2.0.0","installedAt":"2025-12-03T05:30:52.695Z"}]
    }}
    """#

    @Test("The register becomes one boundary per usable record, and the rest are counted")
    func registerSeedsBoundaries() {
        let fileSystem = MemoryFileSystem()
        fileSystem.seed(Self.register, atPath: "/claude/installed_plugins.json")
        let seeded = InvocationSources.seed(
            at: "/claude/installed_plugins.json", fileSystem: fileSystem
        )
        #expect(seeded.observations.count == 1)
        #expect(seeded.observations.first?.name == "trawl@fledgeling")
        #expect(seeded.skipped == 1)
    }

    @Test("A register that is not there yields nothing and is not an error")
    func absentRegisterIsNotAFailure() {
        let seeded = InvocationSources.seed(at: "/nowhere.json", fileSystem: MemoryFileSystem())
        #expect(seeded.observations.isEmpty)
        #expect(seeded.skipped == 0)
    }

    @Test("The register path defaults to Claude's own and is overridable")
    func registerPathIsOverridable() {
        #expect(InvocationSources.registerPath(environment: [:], homeDirectory: "/h")
            == "/h/.claude/plugins/installed_plugins.json")
        #expect(InvocationSources.registerPath(
            environment: ["MCP_ROUTER_PLUGIN_REGISTER": "/elsewhere.json"], homeDirectory: "/h"
        ) == "/elsewhere.json")
        // Empty is not a path. Nullish rather than a presence test, so an exported-but-empty
        // variable falls back instead of naming the empty string — `RegistryDeps` records the
        // opposite convention for the reference's own `??`, and the difference is deliberate here
        // because there is no reference behaviour to match.
        #expect(InvocationSources.registerPath(
            environment: ["MCP_ROUTER_PLUGIN_REGISTER": ""], homeDirectory: "/h"
        ) == "/h/.claude/plugins/installed_plugins.json")
    }

    /// The whole point of seeding, asserted as a difference rather than as a state: the same events
    /// and the same corpus credit nothing without boundaries and credit a version with them.
    @Test("Without the seed every run is unestablished; with it they attribute")
    func seedingIsWhatMakesAttributionPossible() {
        let home = NSTemporaryDirectory() + "mcprouter-f5-seed-" + UUID().uuidString
        let corpus = NSTemporaryDirectory() + "mcprouter-f5-seedcorpus-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: corpus, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: home)
            try? FileManager.default.removeItem(atPath: corpus)
        }
        let line = #"{"type":"assistant","timestamp":"2026-08-26T09:00:00.000Z","message":"#
            + #"{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"trawl:trawl"}}]}}"#
        try? Data((line + "\n").utf8).write(to: URL(fileURLWithPath: "\(corpus)/s.jsonl"))

        func history(_ suffix: String) -> InvocationHistory {
            InvocationHistory(
                sources: [TranscriptSource(harness: "claude-code", root: corpus)],
                invocationsPath: "\(home)/\(suffix)-invocations.jsonl",
                ledgerPath: "\(home)/\(suffix)-versions.jsonl",
                watermarkPath: "\(home)/\(suffix)-watermarks.json"
            )
        }

        let bare = history("bare")
        bare.refresh()
        let without = bare.window(nowMilliseconds: 1_787_832_000_000, days: 7)
        #expect(without.rows.isEmpty)
        #expect(without.unestablishedRuns == 1)

        let fileSystem = MemoryFileSystem()
        fileSystem.seed(Self.register, atPath: "/claude/installed_plugins.json")
        let seeded = history("seeded")
        seeded.observe(
            InvocationSources.seed(
                at: "/claude/installed_plugins.json", fileSystem: fileSystem
            ).observations
        )
        seeded.refresh()
        let with = seeded.window(nowMilliseconds: 1_787_832_000_000, days: 7)
        #expect(with.rows.count == 1)
        #expect(with.rows.first?.version == "1.4.2")
        #expect(with.unestablishedRuns == 0)
    }
}
