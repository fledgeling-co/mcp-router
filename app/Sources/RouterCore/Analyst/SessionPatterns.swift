import Foundation

/// Something the machine did more than once, with the count that makes it worth saying.
public struct SessionPattern: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        /// A command line the user ran, reduced to its head and first bare subcommand.
        case command
        /// A shell reporting a binary it could not find — the strongest signal in the corpus,
        /// because it is the machine stating a missing capability rather than the analyst inferring
        /// one.
        case missingTool
    }

    public let kind: Kind
    public let signal: String
    public let occurrences: Int
    /// Every harness the signal was seen in, in ``MCPClient/allCases`` order so two reads agree.
    public let harnesses: [MCPClient]
    /// At most three verbatim lines. Capped because the excerpt is what reaches a model, and an
    /// unbounded one is an unbounded amount of a user's own history leaving the process.
    public let examples: [String]

    public init(
        kind: Kind, signal: String, occurrences: Int, harnesses: [MCPClient], examples: [String]
    ) {
        self.kind = kind
        self.signal = signal
        self.occurrences = occurrences
        self.harnesses = harnesses
        self.examples = examples
    }
}

/// Counting what recurs, before any model is asked anything.
///
/// **This half is deterministic and the model never sees the corpus.** What crosses into the judge
/// is a list of counted signals with three examples each, which is the difference between *the
/// analyst reads your logs locally* and *your logs are the prompt*.
public enum SessionPatterns {
    /// How many times a signal must recur. Three rather than two: two is a coincidence often enough
    /// that the floor would not be doing anything, and the design's own empty state says the
    /// analyst needs a body of sessions before it suggests anything at all.
    public static let floor = 3
    public static let examplesPerPattern = 3
    /// How many patterns reach the judge. The prompt is bounded so a machine with a thousand
    /// distinct commands does not produce a thousand-line prompt.
    public static let patternLimit = 12

    public static func extract(
        from corpus: SessionCorpus, floor: Int = SessionPatterns.floor
    ) -> [SessionPattern] {
        var tallies: [String: Tally] = [:] // swift-wire-exempt: local accumulator, never stored
        for entry in corpus.entries {
            for line in entry.text.split(separator: "\n") {
                let text = String(line).trimmingCharacters(in: .whitespaces)
                guard let signal = signal(in: text) else { continue }
                let key = "\(signal.kind.rawValue)\u{1F}\(signal.name)"
                tallies[key, default: Tally(kind: signal.kind, name: signal.name)]
                    .record(harness: entry.harness, example: text)
            }
        }
        let surviving: [SessionPattern] = tallies.values
            .filter { $0.occurrences >= floor }
            .map(\.pattern)
        let ranked = surviving.sorted { left, right in
            if left.occurrences != right.occurrences { return left.occurrences > right.occurrences }
            return left.signal < right.signal
        }
        return Array(ranked.prefix(patternLimit))
    }

    private struct Tally {
        let kind: SessionPattern.Kind
        let name: String
        var occurrences = 0
        var seen: Set<MCPClient> = []
        var examples: [String] = []

        mutating func record(harness: MCPClient, example: String) {
            occurrences += 1
            seen.insert(harness)
            if examples.count < examplesPerPattern, !examples.contains(example) {
                examples.append(example)
            }
        }

        var pattern: SessionPattern {
            SessionPattern(
                kind: kind, signal: name, occurrences: occurrences,
                harnesses: MCPClient.allCases.filter { seen.contains($0) }, examples: examples
            )
        }
    }

    /// What one line contributes, or nothing.
    ///
    /// **A stated heuristic rather than a parser, and its exclusions are the point.** A line counts
    /// as a command only when its head looks like a binary name *and* the line carries either a
    /// flag or a bare subcommand within eight tokens. Prose therefore does not count: *"can you run
    /// the docker logs for me"* has nine tokens and no flag, so it contributes nothing rather than
    /// contributing a command called `can you`. The cost is that a terse prose line can still slip
    /// through; the benefit is that the histogram is not made of English.
    static func signal(in line: String) -> (kind: SessionPattern.Kind, name: String)? {
        if let missing = missingTool(in: line) { return (.missingTool, missing) }
        let tokens = line.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard let head = tokens.first, isBinaryName(head), tokens.count <= 8 else { return nil }
        let rest = tokens.dropFirst()
        let hasFlag = rest.contains { $0.hasPrefix("-") && $0.count > 1 }
        let subcommand = rest.first.flatMap { isBareWord($0) ? $0 : nil }
        guard hasFlag || subcommand != nil else { return nil }
        return (.command, subcommand.map { "\(head) \($0)" } ?? head)
    }

    /// `zsh: command not found: pgcli`, `bash: pgcli: command not found`, and the bare form.
    static func missingTool(in line: String) -> String? {
        let marker = "command not found"
        guard let range = line.range(of: marker) else { return nil }
        let after = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        if after.hasPrefix(":") {
            let name = after.dropFirst().trimmingCharacters(in: .whitespaces)
            return isBinaryName(name) ? name : nil
        }
        let before = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let candidate = before.hasSuffix(":")
            ? String(before.dropLast()).split(separator: ":").last.map(String.init)
            : nil
        guard let candidate else { return nil }
        let name = candidate.trimmingCharacters(in: .whitespaces)
        return isBinaryName(name) ? name : nil
    }

    static func isBinaryName(_ token: String) -> Bool {
        guard token.count >= 2, token.count <= 24, let first = token.first, first.isLowercase
        else { return false }
        return token.allSatisfy { $0.isLowercase || $0.isNumber || "_.+-".contains($0) }
    }

    static func isBareWord(_ token: String) -> Bool {
        guard token.count >= 2, token.count <= 24, let first = token.first, first.isLowercase
        else { return false }
        return token.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" }
    }
}
