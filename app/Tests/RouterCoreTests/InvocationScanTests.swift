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
