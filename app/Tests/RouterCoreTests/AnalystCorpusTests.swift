import Foundation
import Testing
@testable import RouterCore

/// What the analyst read, and the accounting for what it did not — F7, REQ-030.1 and .2.
///
/// Every assertion here reads a **positive** quantity or a **named** reason. A reader that opened
/// nothing produces an empty corpus, and an empty corpus satisfies "no wrong lines were counted";
/// asserting `linesRead > 0` beside every discard is what stops that from passing.
@Suite("F7 · the session corpus")
struct AnalystCorpusTests {
    static let home = "/home/tester"

    static func seeded() -> MemoryFileSystem {
        let fs = MemoryFileSystem()
        fs.seed(
            """
            {"display":"docker logs mcp-gateway --tail 50"}
            {"display":"docker logs mcp-gateway -f"}
            {"display":"docker ps -a"}
            not json at all
            {"noKnownMember":true}

            {"display":"zsh: command not found: pgcli"}
            """,
            atPath: "\(home)/.claude/history.jsonl"
        )
        fs.seed(
            """
            {"text":"docker logs router --since 1h"}
            {"text":"pgcli: command not found"}
            """,
            atPath: "\(home)/.codex/history.jsonl"
        )
        fs.seed(
            "{\"prompt\":\"docker compose up -d\"}\n",
            atPath: "\(home)/.grok/sessions/a.jsonl"
        )
        return fs
    }

    static func read(_ fs: MemoryFileSystem) -> SessionCorpus {
        SessionCorpusReader(fileSystem: fs, homeDirectory: home).read()
    }

    @Test("it reports the lines it parsed, and that number is not zero")
    func linesRead() {
        let corpus = Self.read(Self.seeded())
        // 4 from Claude (three docker lines and the not-found line, out of seven opened),
        // 2 from Codex, 1 from Grok. Written as the sum of the per-store figures as well as as a
        // constant, so the store table and the total cannot disagree silently.
        #expect(corpus.linesRead == corpus.reports.reduce(0) { $0 + $1.lines })
        #expect(corpus.linesRead == 7)
        #expect(corpus.entries.count == 7)
    }

    @Test("a line it cannot use is counted as discarded rather than dropped in silence")
    func discards() {
        let corpus = Self.read(Self.seeded())
        let claude = corpus.reports.first { $0.harness == .claudeCode }
        // `not json at all`, `{"noKnownMember":true}` and the blank line: three opened, none used.
        #expect(claude?.discarded == 3)
        #expect(corpus.discardedLines >= 3)
    }

    @Test("every store appears, and an absent one says why")
    func absentStoreIsNamed() {
        let corpus = Self.read(Self.seeded())
        // Five, written out. Comparing against `SessionStores.table(...).count` is the same
        // expression on both sides: dropping a store from the table would move both numbers
        // together and this assertion could never fail. Found by arming it — F7-A2 read MISS.
        #expect(corpus.reports.count == 5)
        #expect(SessionStores.table(homeDirectory: Self.home).count == 5)
        let gemini = corpus.reports.first { $0.harness == .geminiCLI }
        #expect(gemini?.read == false)
        #expect(gemini?.reason == "no .jsonl file in this directory")
        #expect(corpus.entries.contains { $0.harness == .geminiCLI } == false)
    }

    @Test("the SQLite store is enumerated, unread, and carries the reason it was not opened")
    func cursorIsDeclaredRatherThanOmitted() {
        let corpus = Self.read(Self.seeded())
        let cursor = corpus.reports.first { $0.harness == .cursor }
        #expect(cursor?.read == false)
        #expect(cursor?.reason?.contains("SQLite") == true)
    }

    @Test("a store the reader reached and could use nothing from is read, with a reason")
    func allDiscardedIsStillRead() {
        let fs = MemoryFileSystem()
        fs.seed("nonsense\nmore nonsense\n", atPath: "\(Self.home)/.claude/history.jsonl")
        let claude = Self.read(fs).reports.first { $0.harness == .claudeCode }
        #expect(claude?.read == true)
        #expect(claude?.lines == 0)
        #expect(claude?.discarded == 3)
        #expect(claude?.reason == "every line in this store was discarded")
    }
}

/// The counting half — REQ-030.2. Deterministic, and the model sees none of it.
@Suite("F7 · session patterns")
struct AnalystPatternTests {
    static func corpus(_ lines: [(MCPClient, String)]) -> SessionCorpus {
        SessionCorpus(
            entries: lines.map { SessionEntry(harness: $0.0, text: $0.1) },
            reports: []
        )
    }

    @Test("a signal under the floor does not reach the judge")
    func floorHolds() {
        let twice = Self.corpus([(.claudeCode, "docker logs a"), (.claudeCode, "docker logs b")])
        #expect(SessionPatterns.extract(from: twice).isEmpty)
        let thrice = Self.corpus([
            (.claudeCode, "docker logs a"), (.claudeCode, "docker logs b"),
            (.claudeCode, "docker logs c")
        ])
        #expect(SessionPatterns.extract(from: thrice).map(\.signal) == ["docker logs"])
        #expect(SessionPatterns.extract(from: thrice).first?.occurrences == 3)
    }

    @Test("a missing tool is its own kind, and the shell's two spellings both reach it")
    func missingTool() {
        let corpus = Self.corpus([
            (.claudeCode, "zsh: command not found: pgcli"),
            (.codexCLI, "bash: pgcli: command not found"),
            (.claudeCode, "command not found: pgcli")
        ])
        let found = SessionPatterns.extract(from: corpus)
        #expect(found.count == 1)
        #expect(found.first?.kind == .missingTool)
        #expect(found.first?.signal == "pgcli")
        #expect(found.first?.harnesses == [.claudeCode, .codexCLI])
    }

    @Test("prose does not become a command")
    func proseIsNotCounted() {
        let corpus = Self.corpus([
            (.claudeCode, "can you run the docker logs for me and tell me what broke"),
            (.claudeCode, "can you run the docker logs for me and tell me what broke"),
            (.claudeCode, "can you run the docker logs for me and tell me what broke")
        ])
        #expect(SessionPatterns.extract(from: corpus).isEmpty)
    }

    @Test("no more than three examples travel with a pattern")
    func examplesAreCapped() {
        let corpus = Self.corpus((1 ... 9).map { (.claudeCode, "docker logs container-\($0)") })
        let pattern = SessionPatterns.extract(from: corpus).first
        #expect(pattern?.occurrences == 9)
        #expect(pattern?.examples.count == 3)
    }
}
