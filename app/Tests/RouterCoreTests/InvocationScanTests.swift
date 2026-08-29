import Foundation
import Testing
@testable import RouterCore

/// The transcript reader: what it takes off a line, what it refuses to take, and what it counts.
///
/// Every fixture below is shaped from a **measured** line, not an imagined one. The shapes came from
/// a 400-file random sample of this machine's Claude Code corpus on 2026-08-29 (`spec-F5.md` §2), and
/// two of the counted classes are in here because that sample said they were real rather than
/// theoretical: 936 of 20,268 lines carried no `timestamp`, and 2,429 of 3,320 tool calls were
/// `Bash`.
@Suite("The transcript reader")
struct InvocationScanTests {
    private static let root = "/tmp/f5-scan"

    /// One assistant line carrying one `tool_use` block, in the shape the corpus writes it.
    private static func line(
        ts: String = "2026-08-20T09:00:00.000Z", tool: String, skill: String? = nil
    ) -> String {
        let input = skill.map { #"{"skill":"\#($0)","args":"do the thing"}"# } ?? #"{"x":1}"#
        return #"{"type":"assistant","timestamp":"\#(ts)","cwd":"/Users/x/Dev/secret-project","#
            + #""message":{"content":[{"type":"tool_use","name":"\#(tool)","input":\#(input)}]}}"#
    }

    private static func scan(
        _ lines: [String],
        watermarks: TranscriptWatermarks = TranscriptWatermarks(),
        modified: Date = Date(timeIntervalSince1970: 100)
    ) -> (TranscriptScanResult, MemoryFileSystem) {
        let fileSystem = MemoryFileSystem()
        let text = lines.joined(separator: "\n") + "\n"
        fileSystem.seed(text, atPath: "\(root)/a.jsonl", modified: modified)
        let result = TranscriptScan.scan(
            files: ["\(root)/a.jsonl"], harness: "claude-code",
            fileSystem: fileSystem, watermarks: watermarks
        )
        return (result, fileSystem)
    }

    // MARK: - A1, A2 — what becomes an event

    @Test("A Skill block becomes one skill invocation naming the skill")
    func skillBlockBecomesAnEvent() {
        let (result, _) = Self.scan([Self.line(tool: "Skill", skill: "ship-feature:ship-feature")])
        #expect(result.events.count == 1)
        #expect(result.events.first?.kind == .skill)
        #expect(result.events.first?.name == "ship-feature:ship-feature")
        #expect(result.events.first?.harness == "claude-code")
    }

    /// The relayed shape is the one that would break a naive split. `mcp__router__diolog-tasks__get_issue`
    /// is a real name from the sample: the router relays, so the tool half carries the separator
    /// again, and splitting into exactly two segments drops the relayed server's own name.
    @Test("An MCP tool becomes a server invocation, and a relayed name keeps its whole tool")
    func mcpBlockBecomesAServerEvent() {
        let (result, _) = Self.scan([
            Self.line(tool: "mcp__obscura__browser_navigate"),
            Self.line(tool: "mcp__router__diolog-tasks__get_issue")
        ])
        #expect(result.events.count == 2)
        #expect(result.events[0].kind == .server)
        #expect(result.events[0].name == "obscura")
        #expect(result.events[0].tool == "browser_navigate")
        #expect(result.events[1].name == "router")
        #expect(result.events[1].tool == "diolog-tasks__get_issue")
    }

    @Test("A harness built-in is counted as one and produces no event")
    func builtInToolIsCountedNotDropped() {
        let (result, _) = Self.scan([Self.line(tool: "Bash"), Self.line(tool: "Read")])
        #expect(result.events.isEmpty)
        #expect(result.accounting.builtInTool == 2)
        // The distinction this asserts: a built-in is a real tool call, not a prose line. Folding
        // the two together would hide the reader's own yield, which on the measured sample is 79 of
        // 3,320 blocks.
        #expect(result.accounting.notAnInvocation == 0)
    }

    // MARK: - A3, A4 — what is counted rather than dropped

    @Test("A line with no timestamp is counted and produces nothing")
    func lineWithoutTimestampIsCounted() {
        let bare = #"{"type":"assistant","message":{"content":"#
            + #"[{"type":"tool_use","name":"Skill","input":{"skill":"trawl"}}]}}"#
        let (result, _) = Self.scan([bare])
        #expect(result.events.isEmpty)
        #expect(result.accounting.withoutTimestamp == 1)
    }

    /// A six-digit fractional second is Codex's shape, and it is the one that would silently
    /// reorder runs around a boundary rather than failing loudly — `'3' < 'Z'` makes
    /// `…30.333543Z` sort before `…30.33Z` under the string comparison the join uses.
    @Test("A timestamp that cannot be ordered is refused rather than bucketed")
    func unorderableTimestampIsRefused() {
        let (result, _) = Self.scan([
            Self.line(ts: "2026-06-05T04:26:30.333543Z", tool: "Skill", skill: "trawl")
        ])
        #expect(result.events.isEmpty)
        #expect(result.accounting.withoutTimestamp == 1)
    }

    @Test("A torn last line costs the line and not the file")
    func tornLastLineIsCounted() {
        let good = Self.line(tool: "Skill", skill: "trawl")
        let fileSystem = MemoryFileSystem()
        // No trailing newline after the torn fragment: a live session is being appended to, so the
        // fragment is left OUTSIDE the offset for the next scan to read whole.
        fileSystem.seed("\(good)\n{\"type\":\"assis", atPath: "\(Self.root)/a.jsonl")
        let result = TranscriptScan.scan(
            files: ["\(Self.root)/a.jsonl"], harness: "claude-code",
            fileSystem: fileSystem, watermarks: TranscriptWatermarks()
        )
        #expect(result.events.count == 1)
        #expect(result.accounting.linesRead == 1)
        #expect(result.accounting.unparseable == 0)
        // The fragment is not consumed, so a later append completes it rather than losing it.
        #expect(
            result.watermarks.watermark(for: "\(Self.root)/a.jsonl")?.offset
                == good.utf8.count + 1
        )
    }

    // MARK: - A5 — the record cannot carry what it was never given

    /// The privacy claim in `spec-F5.md` §3 is only worth what fails when it stops being true.
    /// The fixture line carries a `cwd` naming a project and an `args` carrying prompt text; neither
    /// may appear anywhere in the serialised event.
    @Test("An event's wire keys are exactly the four, and carry no prompt or path")
    func eventCarriesNothingItWasNotAskedFor() throws {
        let (result, _) = Self.scan([Self.line(tool: "Skill", skill: "trawl")])
        let event = try #require(result.events.first)
        let members = try #require(event.value.asObjectMembers)
        #expect(members.map(\.key.string) == ["ts", "kind", "name", "harness"])
        let serialised = JSStringify.compact(event.value)
        #expect(!serialised.contains("secret-project"))
        #expect(!serialised.contains("do the thing"))
        #expect(!serialised.contains("cwd"))
        // Every key the type can ever emit is enumerated, so a fifth member added later reddens
        // this rather than shipping quietly.
        #expect(InvocationEvent.wireKeys == ["ts", "kind", "name", "harness", "tool"])
    }

    // MARK: - A9, A10 — the watermark

    @Test("An unchanged file is not opened on the second scan")
    func unchangedFileIsSkipped() {
        let (first, fileSystem) = Self.scan([Self.line(tool: "Skill", skill: "trawl")])
        let again = TranscriptScan.scan(
            files: ["\(Self.root)/a.jsonl"], harness: "claude-code",
            fileSystem: fileSystem, watermarks: first.watermarks
        )
        #expect(again.accounting.filesSkipped == 1)
        #expect(again.accounting.filesRead == 0)
        #expect(again.events.isEmpty)
    }

    @Test("A file that grew is resumed, and only the new lines become events")
    func grownFileIsResumed() {
        let first = Self.line(tool: "Skill", skill: "trawl")
        let second = Self.line(tool: "Skill", skill: "tailings")
        let fileSystem = MemoryFileSystem()
        fileSystem.seed(
            "\(first)\n", atPath: "\(Self.root)/a.jsonl",
            modified: Date(timeIntervalSince1970: 100)
        )
        let one = TranscriptScan.scan(
            files: ["\(Self.root)/a.jsonl"], harness: "claude-code",
            fileSystem: fileSystem, watermarks: TranscriptWatermarks()
        )
        fileSystem.seed(
            "\(first)\n\(second)\n", atPath: "\(Self.root)/a.jsonl",
            modified: Date(timeIntervalSince1970: 200)
        )
        let two = TranscriptScan.scan(
            files: ["\(Self.root)/a.jsonl"], harness: "claude-code",
            fileSystem: fileSystem, watermarks: one.watermarks
        )
        #expect(one.events.count == 1)
        #expect(two.events.count == 1)
        #expect(two.events.first?.name == "tailings")
        #expect(two.accounting.filesReread == 0)
    }

    @Test("A file that shrank is re-read from zero and says so")
    func shrunkFileIsRereadFromZero() {
        let long = [Self.line(tool: "Skill", skill: "a"), Self.line(tool: "Skill", skill: "b")]
        let fileSystem = MemoryFileSystem()
        fileSystem.seed(
            long.joined(separator: "\n") + "\n", atPath: "\(Self.root)/a.jsonl",
            modified: Date(timeIntervalSince1970: 100)
        )
        let one = TranscriptScan.scan(
            files: ["\(Self.root)/a.jsonl"], harness: "claude-code",
            fileSystem: fileSystem, watermarks: TranscriptWatermarks()
        )
        #expect(one.events.count == 2)
        fileSystem.seed(
            Self.line(tool: "Skill", skill: "c") + "\n", atPath: "\(Self.root)/a.jsonl",
            modified: Date(timeIntervalSince1970: 300)
        )
        let two = TranscriptScan.scan(
            files: ["\(Self.root)/a.jsonl"], harness: "claude-code",
            fileSystem: fileSystem, watermarks: one.watermarks
        )
        #expect(two.accounting.filesReread == 1)
        #expect(two.events.count == 1)
        #expect(two.events.first?.name == "c")
    }
}

/// Where the router is pointed, and the fact that it is pointed nowhere by default.
///
/// The absent case is the one worth a test. `ControlDeps`' optional ports have shipped `nil` in
/// `RouterServiceDispatch` twice with a green suite — `control-registry-search` and `D-p1-a` — and
/// F5's own spec quotes that, so the wiring is asserted rather than assumed.
@Suite("Where the transcript corpus comes from")
struct InvocationSourcesTests {
    private static func fileSystem() -> MemoryFileSystem {
        let fileSystem = MemoryFileSystem()
        fileSystem.seed("{}", atPath: "/corpus/claude/a.jsonl")
        fileSystem.seed("{}", atPath: "/corpus/codex/b.jsonl")
        return fileSystem
    }

    /// The two roots the fixture has, and nothing else.
    ///
    /// Supplied rather than taken from `MemoryFileSystem`, because the double answers
    /// `contentsOfDirectory` for a path that does not exist by returning `[]` — so a guard written
    /// against the seam admits a missing root, which is exactly what the first version of
    /// `InvocationSources.parse` did and what the `gone=` arm below caught.
    private static let onDisk: @Sendable (String) -> Bool = {
        $0 == "/corpus/claude" || $0 == "/corpus/codex"
    }

    @Test("Unset and empty both name no corpus, and neither is an error")
    func absentVariableYieldsNothing() {
        #expect(InvocationSources.parse(nil, isDirectory: Self.onDisk).sources.isEmpty)
        #expect(InvocationSources.parse("", isDirectory: Self.onDisk).sources.isEmpty)
        #expect(InvocationSources.parse(nil, isDirectory: Self.onDisk).discarded == 0)
    }

    @Test("A pair naming a real directory is taken; a typo is dropped and counted")
    func pairsAreParsedAndBadOnesCounted() {
        let parsed = InvocationSources.parse(
            "claude-code=/corpus/claude:codex=/corpus/codex:broken:empty=:gone=/no/such/place",
            isDirectory: Self.onDisk
        )
        #expect(parsed.sources.map(\.harness) == ["claude-code", "codex"])
        // Three discarded, not one: a malformed pair, an empty half, and a root that is not there.
        // A caller that could not see this number would report a partial reading as a whole one.
        #expect(parsed.discarded == 3)
    }

    @Test("With nothing named, the daemon holds no history at all")
    func noVariableMeansNoHistory() {
        let home = RouterHome(root: "/router")
        #expect(InvocationSources.history(
            environment: [:], home: home, fileSystem: Self.fileSystem(),
            isDirectory: Self.onDisk
        ) == nil)
        #expect(InvocationSources.history(
            environment: [InvocationSources.environmentKey: "claude-code=/corpus/claude"],
            home: home, fileSystem: Self.fileSystem(), isDirectory: Self.onDisk
        ) != nil)
    }

    /// Both carry `nil` runs and a reason. A zero against either would read as *this harness ran no
    /// skills*, which is the finding, and it would be fabricated.
    @Test("The two harnesses with files and no capability calls report null, never zero")
    func unobservableHarnessesCarryNoFigure() {
        #expect(InvocationSources.unobservable.count == 2)
        #expect(InvocationSources.unobservable.allSatisfy { $0.runs == nil })
        #expect(InvocationSources.unobservable.allSatisfy { $0.reason?.isEmpty == false })
    }
}

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
