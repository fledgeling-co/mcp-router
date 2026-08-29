import Foundation
import Testing
@testable import RouterCore

/// The reply parser and the ladder — F7, REQ-030.3, .4, .5 and .6.
///
/// **Every judge here can refuse.** A double that always answers proves the happy path and nothing
/// else, and three of the six clauses this suite carries are about what happens when a rung does
/// not answer.
@Suite("F7 · the analyst judge")
struct AnalystJudgeTests {
    static let candidates = [
        AnalystCandidate(id: "docker-mcp", name: "Docker MCP", summary: "container control"),
        AnalystCandidate(id: "pgcli", name: "pgcli", summary: "a postgres shell")
    ]
    static let signals = ["docker logs", "pgcli"]

    static func read(_ reply: String) -> (accepted: [AnalystJudgement], rejected: Int) {
        AnalystPrompt.read(reply, candidates: candidates, signals: signals)
    }

    @Test("a well-formed line becomes a judgement")
    func wellFormed() {
        let outcome = Self.read(
            #"{"entry":"docker-mcp","signal":"docker logs","why":"you read logs by hand"}"#
        )
        #expect(outcome.rejected == 0)
        #expect(outcome.accepted.map(\.entryID) == ["docker-mcp"])
        #expect(outcome.accepted.first?.signal == "docker logs")
    }

    @Test("an id outside the candidate list is rejected and counted")
    func offListEntry() {
        let outcome = Self.read(
            #"{"entry":"kubernetes-mcp","signal":"docker logs","why":"invented"}"#
        )
        #expect(outcome.accepted.isEmpty)
        // The count is the assertion, not the emptiness: an engine that discarded everything and an
        // engine handed nothing both produce an empty list.
        #expect(outcome.rejected == 1)
    }

    @Test("a signal the run never counted is rejected, so the evidence figure cannot be invented")
    func offListSignal() {
        let outcome = Self.read(
            #"{"entry":"pgcli","signal":"kubectl get pods","why":"you use kubernetes"}"#
        )
        #expect(outcome.accepted.isEmpty)
        #expect(outcome.rejected == 1)
    }

    @Test("a truncated line is rejected rather than half-read")
    func truncated() {
        let outcome = Self.read(#"{"entry":"pgcli","signal":"pgcli","why":"#)
        #expect(outcome.accepted.isEmpty)
        #expect(outcome.rejected == 1)
    }

    @Test("prose around the answer is ignored, and the answer inside it still lands")
    func prose() {
        let outcome = Self.read(
            """
            Sure! Here is what I found:
            {"entry":"pgcli","signal":"pgcli","why":"your shell could not find it"}
            Let me know if you want more.
            """
        )
        #expect(outcome.accepted.count == 1)
        #expect(outcome.rejected == 0)
    }

    @Test("an empty reply is refused by the CLI judge as empty, not as a refusal")
    func emptyReply() async {
        let judge = CLIAnalystJudge(runner: StubRunner(outcome: AnalystCommandOutcome(
            status: 0, output: "   \n"
        )))
        await #expect(throws: AnalystJudgeError.empty) {
            try await judge.judge(prompt: "p", lane: .claude)
        }
    }

    @Test("a binary that is not installed is not a refusal, so the ladder can fall through")
    func notInstalled() async {
        let judge = CLIAnalystJudge(runner: StubRunner(outcome: nil))
        await #expect(throws: AnalystJudgeError.notInstalled("claude")) {
            try await judge.judge(prompt: "p", lane: .claude)
        }
    }

    struct StubRunner: AnalystCommandRunning {
        let outcome: AnalystCommandOutcome?

        func run(binary _: String, arguments _: [String]) async -> AnalystCommandOutcome? {
            outcome
        }
    }
}

/// The engine end to end, over a filesystem and a clock a test can put in any state.
@Suite("F7 · the analyst engine")
struct AnalystEngineTests {
    static let home = "/home/tester"
    static let statePath = "/router/analyst.json"

    /// A judge that answers per lane, so a ladder can be driven rung by rung.
    struct LadderJudge: AnalystJudging {
        var replies: [AnalystLane: String] = [:] // swift-wire-exempt: test double, never serialised

        func judge(prompt _: String, lane: AnalystLane) async throws(AnalystJudgeError) -> String {
            guard let reply = replies[lane] else { throw AnalystJudgeError.refused("no \(lane)") }
            return reply
        }
    }

    struct FixedCandidates: AnalystCandidateSource {
        var rows: [AnalystCandidate]?

        func candidates(for _: [String]) async -> [AnalystCandidate]? {
            rows
        }
    }

    static func corpusFileSystem() -> MemoryFileSystem {
        let fs = MemoryFileSystem()
        fs.seed(
            """
            {"display":"docker logs a"}
            {"display":"docker logs b"}
            {"display":"docker logs c"}
            """,
            atPath: "\(home)/.claude/history.jsonl"
        )
        return fs
    }

    static let dockerReply =
        #"{"entry":"docker-mcp","signal":"docker logs","why":"you read container logs by hand"}"#
    static let candidates = [
        AnalystCandidate(id: "docker-mcp", name: "Docker MCP", summary: "container control")
    ]

    static func engine(
        fileSystem: MemoryFileSystem,
        clock: ManualClock,
        judge: any AnalystJudging,
        candidates rows: [AnalystCandidate]? = candidates
    ) -> AnalystEngine {
        AnalystEngine(
            reader: SessionCorpusReader(fileSystem: fileSystem, homeDirectory: home),
            judge: judge, candidateSource: FixedCandidates(rows: rows),
            fileSystem: fileSystem, clock: clock, statePath: statePath
        )
    }

    @Test("a run records what it read, what it found, and which rung judged")
    func happyPath() async throws {
        let fs = Self.corpusFileSystem()
        let engine = Self.engine(
            fileSystem: fs, clock: ManualClock(milliseconds: 1000),
            judge: LadderJudge(replies: [.claude: Self.dockerReply])
        )
        let run = try #require(try? await engine.analyse().get())
        #expect(run.lane == .claude)
        #expect(run.usedFallback == false)
        #expect(run.linesRead == 3)
        #expect(run.findings.count == 1)
        #expect(run.findings.first?.entryID == "docker-mcp")
        #expect(run.findings.first?.evidenceCount == 3)
        // The state file is a different channel from the returned value: a run that only built a
        // struct would satisfy every line above and leave nothing behind.
        #expect(fs.contents(atPath: Self.statePath)?.contains("docker-mcp") == true)
    }

    @Test("the primary refusing runs the fallback, and the run says so")
    func fallbackRuns() async throws {
        let engine = Self.engine(
            fileSystem: Self.corpusFileSystem(), clock: ManualClock(milliseconds: 1000),
            judge: LadderJudge(replies: [.grok: Self.dockerReply])
        )
        let run = try #require(try? await engine.analyse().get())
        #expect(run.lane == .grok)
        #expect(run.usedFallback)
        #expect(run.findings.first?.judgedBy == .grok)
    }

    @Test("every rung refusing records no run at all and carries what each one said")
    func ladderExhausted() async {
        let engine = Self.engine(
            fileSystem: Self.corpusFileSystem(), clock: ManualClock(milliseconds: 1000),
            judge: LadderJudge(replies: [:])
        )
        guard case let .failure(failure) = await engine.analyse() else {
            Issue.record("a ladder with no answering rung must not produce a run")
            return
        }
        guard case let .ladderExhausted(refusals) = failure else {
            Issue.record("expected ladderExhausted, got \(failure)")
            return
        }
        #expect(refusals.count == 2)
        #expect(await engine.lastRun() == nil)
    }

    @Test("an off-list recommendation is counted as rejected, not delivered")
    func offListIsCounted() async throws {
        let engine = Self.engine(
            fileSystem: Self.corpusFileSystem(), clock: ManualClock(milliseconds: 1000),
            judge: LadderJudge(replies: [
                .claude: #"{"entry":"invented-mcp","signal":"docker logs","why":"no"}"#
            ])
        )
        let run = try #require(try? await engine.analyse().get())
        #expect(run.findings.isEmpty)
        #expect(run.rejectedFindings == 1)
    }

    @Test("no candidate source means no findings AND a stated reason, never a bare zero")
    func candidatesUnavailable() async throws {
        let engine = Self.engine(
            fileSystem: Self.corpusFileSystem(), clock: ManualClock(milliseconds: 1000),
            judge: LadderJudge(replies: [.claude: Self.dockerReply]), candidates: nil
        )
        let run = try #require(try? await engine.analyse().get())
        #expect(run.candidatesUnavailable)
        #expect(run.lane == nil)
        #expect(run.findings.isEmpty)
    }

    @Test("the same finding inside thirty days is suppressed, and after them it fires again")
    func suppression() async throws {
        let fs = Self.corpusFileSystem()
        let clock = ManualClock(milliseconds: 1000)
        let engine = Self.engine(
            fileSystem: fs, clock: clock,
            judge: LadderJudge(replies: [.claude: Self.dockerReply])
        )
        #expect(try await engine.analyse().get().findings.count == 1)
        clock.advance(by: 29 * 24 * 3_600_000)
        #expect(try await engine.analyse().get().findings.isEmpty)
        clock.advance(by: 2 * 24 * 3_600_000)
        #expect(try await engine.analyse().get().findings.count == 1)
    }

    @Test("a finding whose evidence gained a new signal is a new finding")
    func grownEvidenceFiresAgain() async throws {
        let fs = Self.corpusFileSystem()
        let clock = ManualClock(milliseconds: 1000)
        let judge = LadderJudge(replies: [.claude: Self.dockerReply])
        #expect(try await Self.engine(fileSystem: fs, clock: clock, judge: judge)
            .analyse().get().findings.count == 1)

        fs.seed(
            """
            {"display":"docker logs a"}
            {"display":"docker logs b"}
            {"display":"docker logs c"}
            {"display":"docker compose up"}
            {"display":"docker compose down"}
            {"display":"docker compose ps"}
            """,
            atPath: "\(Self.home)/.claude/history.jsonl"
        )
        let grown = LadderJudge(replies: [
            .claude: #"{"entry":"docker-mcp","signal":"docker compose","why":"and compose too"}"#
        ])
        let second = try await Self.engine(fileSystem: fs, clock: clock, judge: grown)
            .analyse().get()
        #expect(second.findings.count == 1)
        #expect(second.findings.first?.signals == ["docker compose"])
    }

    @Test("settings survive a restart, and an unknown lane is refused by name")
    func settingsRoundTrip() async {
        let fs = MemoryFileSystem()
        let clock = ManualClock(milliseconds: 1000)
        let first = Self.engine(fileSystem: fs, clock: clock, judge: LadderJudge())
        let applied = await first.update(.object([
            JSONMember(key: JSString("primary"), value: .string(JSString("codex"))),
            JSONMember(key: JSString("cadence"), value: .string(JSString("daily")))
        ]))
        #expect((try? applied.get())?.primary == .codex)

        let reopened = Self.engine(fileSystem: fs, clock: clock, judge: LadderJudge())
        #expect(await reopened.settings().primary == .codex)
        #expect(await reopened.settings().cadence == .daily)
        // Unchanged by a patch that did not name it — the point of a patch.
        #expect(await reopened.settings().fallback == .grok)

        let refused = await reopened.update(.object([
            JSONMember(key: JSString("primary"), value: .string(JSString("llama")))
        ]))
        guard case let .failure(refusal) = refused else {
            Issue.record("an unknown lane must be refused")
            return
        }
        #expect(refusal.member == "primary")
        #expect(refusal.value == "llama")
        #expect(await reopened.settings().primary == .codex)
    }
}
