import Foundation

/// One thing the router could recommend, as the router knows it.
public struct AnalystCandidate: Sendable, Hashable {
    public let id: String
    public let name: String
    public let summary: String

    public init(id: String, name: String, summary: String) {
        self.id = id
        self.name = name
        self.summary = summary
    }
}

/// Where the candidate list comes from.
///
/// A port rather than a call into ``RegistrySearch`` for the reason `ControlDeps.registry` is
/// optional: that path reaches the network, and a test that can only reach the real registry can
/// prove the happy path and nothing else. `nil` means **the router has no way to name a
/// capability**, which the run reports as `candidatesUnavailable` rather than as zero findings —
/// the two are the same number and different facts.
public protocol AnalystCandidateSource: Sendable {
    func candidates(for signals: [String]) async -> [AnalystCandidate]?
}

/// What the model said, once it has been checked.
public struct AnalystJudgement: Sendable, Hashable {
    public let entryID: String
    public let sentence: String
    /// The one counted signal the model said it was answering. **Checked against the patterns that
    /// reached the prompt**, for the reason the entry id is checked against the candidates: without
    /// it the finding's evidence count would be the run's total, which is the same number under
    /// every recommendation and therefore not evidence for any of them.
    public let signal: String

    public init(entryID: String, sentence: String, signal: String) {
        self.entryID = entryID
        self.sentence = sentence
        self.signal = signal
    }
}

public enum AnalystJudgeError: Error, Sendable, Hashable {
    /// The binary is not on `PATH`, so this rung was never tried.
    case notInstalled(String)
    /// It ran and did not succeed — a usage limit, a signed-out CLI, a non-zero exit.
    case refused(String)
    /// It ran, succeeded, and wrote nothing. Distinct from ``refused`` because a lane that answers
    /// empty is not a lane that is down, and the ladder treats them the same only by choice.
    case empty
}

public protocol AnalystJudging: Sendable {
    func judge(prompt: String, lane: AnalystLane) async throws(AnalystJudgeError) -> String
}

/// One process run, as the judge needs it.
public struct AnalystCommandOutcome: Sendable, Hashable {
    public let status: Int32
    public let output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }
}

/// Running a CLI. `nil` when the binary is not on `PATH` — an absence rather than a failure,
/// because a rung that is not installed should fall through to the next one silently while a rung
/// that is installed and refusing should say so.
public protocol AnalystCommandRunning: Sendable {
    func run(binary: String, arguments: [String]) async -> AnalystCommandOutcome?
}

/// The judge that shells out to a CLI the user is already signed into.
public struct CLIAnalystJudge: AnalystJudging {
    let runner: any AnalystCommandRunning

    public init(runner: any AnalystCommandRunning) {
        self.runner = runner
    }

    public func judge(
        prompt: String, lane: AnalystLane
    ) async throws(AnalystJudgeError) -> String {
        guard let outcome = await runner.run(
            binary: lane.binary, arguments: lane.arguments(prompt: prompt)
        ) else {
            throw AnalystJudgeError.notInstalled(lane.binary)
        }
        guard outcome.status == 0 else {
            let tail = outcome.output.split(separator: "\n").last.map(String.init) ?? ""
            throw AnalystJudgeError.refused("\(lane.binary) exited \(outcome.status): \(tail)")
        }
        guard !outcome.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalystJudgeError.empty
        }
        return outcome.output
    }
}

/// The prompt, and the reading of what comes back.
public enum AnalystPrompt {
    /// **The candidate ids are in the prompt and the answer is checked against them anyway.**
    /// Asking for an id from a list is a request; ``read(_:candidates:)`` is the enforcement, and
    /// the two are deliberately not the same mechanism.
    public static func text(patterns: [SessionPattern], candidates: [AnalystCandidate]) -> String {
        var lines = [
            "You are reading a summary of one developer's own terminal history.",
            "Recommend capabilities that would remove repeated manual work.",
            "",
            "Answer with one JSON object per line and nothing else:",
            "{\"entry\": \"<id from the list below>\", "
                + "\"signal\": \"<one signal from What recurred>\", \"why\": \"<one sentence>\"}",
            "Recommend nothing rather than guessing. A line naming anything not in these two "
                + "lists is discarded.",
            "",
            "What recurred:"
        ]
        for pattern in patterns {
            let seenIn = pattern.harnesses.map(\.displayName).joined(separator: ", ")
            lines.append("- \(pattern.kind.rawValue) \"\(pattern.signal)\" "
                + "\u{00D7}\(pattern.occurrences) in \(seenIn)")
            for example in pattern.examples {
                lines.append("    e.g. \(example)")
            }
        }
        lines.append("")
        lines.append("Capabilities available to install:")
        for candidate in candidates {
            lines.append("- \(candidate.id) — \(candidate.name): \(candidate.summary)")
        }
        return lines.joined(separator: "\n")
    }

    /// Read the reply, keeping only what names a candidate.
    ///
    /// Returns the accepted judgements **and the count it threw away**, because an engine that
    /// silently discarded everything and an engine that was handed nothing produce the same empty
    /// list, and only one of them is working.
    public static func read(
        _ reply: String, candidates: [AnalystCandidate], signals: [String]
    ) -> (accepted: [AnalystJudgement], rejected: Int) {
        let known = Set(candidates.map(\.id))
        let knownSignals = Set(signals)
        var accepted: [AnalystJudgement] = []
        var rejected = 0
        for line in reply.split(separator: "\n") {
            let text = String(line).trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("{") else { continue }
            guard let parsed = try? JSONParser.parse(text),
                  let entry = parsed.member("entry")?.asString?.string,
                  let signal = parsed.member("signal")?.asString?.string,
                  let why = parsed.member("why")?.asString?.string,
                  !why.isEmpty
            else {
                rejected += 1
                continue
            }
            guard known.contains(entry), knownSignals.contains(signal),
                  !accepted.contains(where: { $0.entryID == entry })
            else {
                rejected += 1
                continue
            }
            accepted.append(AnalystJudgement(entryID: entry, sentence: why, signal: signal))
        }
        return (accepted, rejected)
    }
}
