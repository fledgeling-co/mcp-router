import Foundation

/// The analyst, as the control API needs it.
///
/// Optional on ``ControlDeps`` for the reason ``ExtensionStoring`` and ``CacheProbing`` are: the
/// in-process differential oracle compares the routes `src/control.ts` answers and this whole
/// family is a declared divergence, and an analyst handed to it would put a developer's own session
/// logs and a spawned CLI inside every parity run. Absent, the routes answer 503 saying which
/// capability is missing rather than an empty run, which a router that had analysed nothing would
/// be indistinguishable from.
public protocol AnalystPort: Sendable {
    func settings() async -> AnalystSettings
    func lastRun() async -> AnalystRunRecord?
    func analyse() async -> Result<AnalystRunRecord, AnalystRunFailure>
    func update(_ patch: JSONValue) async -> Result<AnalystSettings, AnalystSettingsRefusal>
}

/// Corpus → patterns → candidates → judge → reject → dedupe → record.
///
/// An actor because ``analyse()`` reads every session store on the machine and spawns a CLI, and
/// two of those at once cost twice for one answer. The `running` flag is what turns the second
/// caller into a 409 rather than a queue: an actor would serialise them, and the second answer
/// would be a second full run nobody asked for.
public actor AnalystEngine: AnalystPort {
    let reader: SessionCorpusReader
    let judge: any AnalystJudging
    let candidateSource: (any AnalystCandidateSource)?
    let fileSystem: any FileSystem
    let clock: any RouterClock
    let statePath: String

    private var state: AnalystState
    private var running = false

    public init(
        reader: SessionCorpusReader,
        judge: any AnalystJudging,
        candidateSource: (any AnalystCandidateSource)?,
        fileSystem: any FileSystem,
        clock: any RouterClock,
        statePath: String
    ) {
        self.reader = reader
        self.judge = judge
        self.candidateSource = candidateSource
        self.fileSystem = fileSystem
        self.clock = clock
        self.statePath = statePath
        state = (try? fileSystem.readFile(atPath: statePath))
            .flatMap { try? JSONParser.parse($0) }
            .map(AnalystStateCoding.decode) ?? AnalystState()
    }

    public func settings() -> AnalystSettings {
        state.settings
    }

    public func lastRun() -> AnalystRunRecord? {
        state.lastRun
    }

    public func update(
        _ patch: JSONValue
    ) -> Result<AnalystSettings, AnalystSettingsRefusal> {
        do {
            state.settings = try AnalystSettingsCoding.apply(patch, to: state.settings)
            persist()
            return .success(state.settings)
        } catch {
            return .failure(error)
        }
    }

    public func analyse() async -> Result<AnalystRunRecord, AnalystRunFailure> {
        guard !running else { return .failure(.alreadyRunning) }
        running = true
        defer { running = false }

        let corpus = reader.read()
        let patterns = SessionPatterns.extract(from: corpus)
        // `nil` and `[]` are different answers and only the first is `candidatesUnavailable`:
        // a registry that could not be reached and a registry holding nothing for these signals
        // are the same list and different facts.
        let offered: [AnalystCandidate]? = patterns.isEmpty
            ? []
            : await candidateSource?.candidates(for: patterns.map(\.signal))
        guard let offered, !offered.isEmpty, !patterns.isEmpty else {
            return .success(record(
                corpus: corpus, Judged(unavailable: offered == nil)
            ))
        }
        let candidates = offered
        return await judged(corpus: corpus, patterns: patterns, candidates: candidates)
    }

    private func judged(
        corpus: SessionCorpus, patterns: [SessionPattern], candidates: [AnalystCandidate]
    ) async -> Result<AnalystRunRecord, AnalystRunFailure> {
        let prompt = AnalystPrompt.text(patterns: patterns, candidates: candidates)
        let signals = patterns.map(\.signal)
        var refusals: [String] = []
        for (index, lane) in state.settings.ladder.enumerated() {
            let reply: String
            do {
                reply = try await judge.judge(prompt: prompt, lane: lane)
            } catch {
                refusals.append("\(lane.rawValue): \(error)")
                continue
            }
            let read = AnalystPrompt.read(reply, candidates: candidates, signals: signals)
            return .success(record(corpus: corpus, Judged(
                lane: lane, usedFallback: index > 0, rejected: read.rejected,
                findings: deliver(
                    read.accepted, patterns: patterns, candidates: candidates, lane: lane
                )
            )))
        }
        return .failure(.ladderExhausted(refusals))
    }

    /// Turn accepted judgements into findings, dropping the ones already delivered inside the
    /// suppression window and recording the ones that survive.
    private func deliver(
        _ judgements: [AnalystJudgement],
        patterns: [SessionPattern],
        candidates: [AnalystCandidate],
        lane: AnalystLane
    ) -> [AnalystFindingRecord] {
        let now = clock.nowMilliseconds
        var fresh: [AnalystFindingRecord] = []
        for judgement in judgements {
            guard let candidate = candidates.first(where: { $0.id == judgement.entryID }),
                  let pattern = patterns.first(where: { $0.signal == judgement.signal })
            else { continue }
            let record = AnalystFindingRecord(
                id: AnalystEngine.identifier(judgement.entryID, judgement.signal),
                entryID: candidate.id, subject: candidate.name, sentence: judgement.sentence,
                evidenceCount: pattern.occurrences, judgedBy: lane, signals: [judgement.signal]
            )
            guard !state.isSuppressed(record.fingerprint, now: now) else { continue }
            state.delivered.removeAll { $0.fingerprint == record.fingerprint }
            state.delivered.append((fingerprint: record.fingerprint, atMilliseconds: now))
            fresh.append(record)
        }
        return fresh
    }

    /// The half of a run that is not the corpus: which rung answered, and what it produced.
    ///
    /// One value rather than five parameters, and the grouping is real: every member here is
    /// decided by the judging step, and every one is absent in the same way when nothing judged.
    struct Judged {
        var lane: AnalystLane?
        var usedFallback = false
        var rejected = 0
        var unavailable = false
        var findings: [AnalystFindingRecord] = []
    }

    private func record(corpus: SessionCorpus, _ judged: Judged) -> AnalystRunRecord {
        let made = AnalystRunRecord(
            lane: judged.lane, ranAtMilliseconds: clock.nowMilliseconds,
            linesRead: corpus.linesRead, discardedLines: corpus.discardedLines,
            usedFallback: judged.usedFallback, rejectedFindings: judged.rejected,
            candidatesUnavailable: judged.unavailable,
            stores: corpus.reports, findings: judged.findings
        )
        state.lastRun = made
        persist()
        return made
    }

    private func persist() {
        let text = JSStringify.prettyTwoSpace(AnalystStateCoding.encode(state))
        guard let data = text.data(using: .utf8) else { return }
        try? fileSystem.writeFile(data, atPath: statePath)
    }

    /// A stable id for one recommendation, so the same finding delivered twice is the same banner
    /// rather than two. FNV-1a over the fingerprint: short, deterministic, and not a hash anything
    /// security-bearing rests on.
    static func identifier(_ entryID: String, _ signal: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in "\(entryID)\u{1F}\(signal)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return "analyst-" + String(hash, radix: 16)
    }
}
