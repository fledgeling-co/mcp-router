import Foundation

/// The decisions the Evals board makes, as functions returning enums.
///
/// M4's precedent, and the reason eleven checks, two stamp renderings and a four-way filter are
/// provable without a host: the view is a `switch` over what this file returns and decides nothing
/// itself. A decision inside a view body is a decision no test can reach.
public enum CheckPresentation {
    // MARK: - The subject a row is about

    /// One row's subject, carrying everything the row and its inspector need.
    ///
    /// **Note what it does not carry: any path to the stored history.** The verdicts on this value are
    /// computed from the response the board just fetched, every time. That is what makes "a stale
    /// verdict cannot render as current" a property of the type rather than a claim about behaviour —
    /// there is no code path from a rendered verdict back to the store, and a source guard asserts it.
    public struct Subject: Identifiable, Sendable, Equatable {
        public let key: SubjectKey
        public let name: String
        public let detail: String
        /// The live stamp, or nil when this subject can never be stamped.
        public let stamp: Stamp?
        public let results: [CheckResult]

        public var id: String { "\(key.kind.rawValue):\(key.id)" }
        public var kind: CheckSubjectKind { key.kind }

        public init(key: SubjectKey, name: String, detail: String, stamp: Stamp?, results: [CheckResult]) {
            self.key = key
            self.name = name
            self.detail = detail
            self.stamp = stamp
            self.results = results
        }
    }

    public static func subject(for server: MCPServer) -> Subject {
        Subject(
            key: .server(server.name),
            name: server.name,
            detail: server.transport.rawValue,
            stamp: Stamp.forServer(server),
            results: ServerChecks.all(server)
        )
    }

    public static func subject(for skill: Skill, clients: [SkillClient]) -> Subject {
        Subject(
            key: .skill(path: skill.path),
            name: skill.name,
            detail: skill.source.pluginOrigin.map(\.plugin) ?? "standalone",
            stamp: Stamp.forSkill(skill),
            results: SkillChecks.all(skill, clients: clients)
        )
    }

    /// Every subject, in the router's own order: servers as `GET /servers` returned them, then skills
    /// as `GET /skills` did.
    ///
    /// Stable across refresh, deliberately. M3 recorded why it matters — a list that reorders itself
    /// as servers start and stop is a list nobody can point at — and `↑`/`↓` need a defined sequence.
    public static func subjects(servers: [MCPServer], skills: SkillsResponse?) -> [Subject] {
        let serverRows = servers.map(subject(for:))
        guard let skills else { return serverRows }
        let skillRows = skills.skills.map { subject(for: $0, clients: skills.clients) }
        return serverRows + skillRows
    }

    // MARK: - The tally

    /// One segment of a row's tally: a count and the word for what it counts.
    ///
    /// A list, never a string, and never collapsible to one word. The aggregate the design forbids is
    /// a bare verdict standing for a whole subject; a tally of segments is a description of what was
    /// observed, which is a claim the data supports.
    public struct TallySegment: Sendable, Equatable, Identifiable {
        public let verdict: CheckVerdict
        public let count: Int

        public var id: String { verdict.rawValue }
        public var noun: String { CheckCopy.tallyNoun(for: verdict) }
        /// Only a *not met* segment is tinted, and it is tinted `--fail`, which is literally what it
        /// means. A confirmed check is never `--live`: `DESIGN.md` §2 binds that hue to one meaning,
        /// "a child process is running", and a check that holds is not a running process.
        public var isTinted: Bool { verdict == .failed }
    }

    /// The segments for one subject's results, in verdict order, omitting empty ones.
    public static func tally(_ results: [CheckResult]) -> [TallySegment] {
        CheckVerdict.allCases.compactMap { verdict in
            let count = results.count { $0.verdict == verdict }
            guard count > 0 else { return nil }
            return TallySegment(verdict: verdict, count: count)
        }
    }

    // MARK: - The filter

    /// The four segments, named with the same words the verdicts use.
    ///
    /// One name per state (`DESIGN.md` §6). An earlier draft had a segment reading "Unchecked" beside
    /// a tally reading "unknown" — one letter apart, meaning different things, on the same screen.
    public enum Filter: String, CaseIterable, Sendable, Identifiable {
        case all
        case notMet
        case notObserved
        case unstamped

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .all: "All"
            case .notMet: "Not met"
            case .notObserved: "Not observed"
            case .unstamped: "Unstamped"
            }
        }

        func matches(_ subject: Subject) -> Bool {
            switch self {
            case .all: true
            case .notMet: subject.results.contains { $0.verdict == .failed }
            case .notObserved: subject.results.contains { $0.verdict == .unknown }
            // Every `.standalone` skill and any server with no `hash`. Given a home of its own
            // because its `checked against` cell and its empty history both want explaining, and a
            // state reachable only under "All" is a state nobody finds.
            case .unstamped: subject.stamp == nil
            }
        }
    }

    public static func rows(_ subjects: [Subject], filter: Filter, search: String) -> [Subject] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return subjects.filter { subject in
            guard filter.matches(subject) else { return false }
            guard !needle.isEmpty else { return true }
            return subject.name.lowercased().contains(needle)
                || subject.detail.lowercased().contains(needle)
        }
    }

    /// The count for a filter's badge, or `nil` when it is zero.
    ///
    /// M4's precedent: a zero count carries no badge at all rather than reading "0", which looks like
    /// a condition that resolved rather than one that never applied.
    public static func count(_ subjects: [Subject], filter: Filter, search: String) -> Int? {
        let n = rows(subjects, filter: filter, search: search).count
        return n == 0 ? nil : n
    }

    // MARK: - History

    /// How one stored run reads against the live stamp.
    ///
    /// Applies to **history rows only**. Nothing on screen outside the history section is ever read
    /// from the store, so there is no third "the current reading is stale" case to render — that
    /// state cannot arise.
    public enum HistoryRowState: Equatable, Sendable {
        /// Gathered against the version that is still live.
        case current(String)
        /// Gathered against a version that has since moved. Kept, labelled, and never presented as a
        /// reading of how things are now.
        case invalidated(stored: String, live: String)

        public var isInvalidated: Bool {
            if case .invalidated = self { return true }
            return false
        }

        public var label: String {
            switch self {
            case let .current(stamp): stamp
            case let .invalidated(stored, live): CheckCopy.invalidatedLabel(stored: stored, live: live)
            }
        }
    }

    public static func historyRowState(run: StoredRun, live: Stamp?) -> HistoryRowState {
        guard let live, live.value != run.stamp.value else {
            // No live stamp to compare against — the subject became unstampable, which cannot happen
            // for a subject that once had one, but the total function says what it would mean rather
            // than trapping.
            return .current(run.stamp.value)
        }
        return .invalidated(stored: run.stamp.value, live: live.value)
    }

    // MARK: - The input a check was computed from

    /// The field name and value behind one check, for the inspector.
    ///
    /// The footer promises a check is "something MCP Router performed and can show you the input to".
    /// Without the input on screen that promise is unverifiable by the person it is addressed to, and
    /// a derived row is indistinguishable from a grade — which is the strongest objection this surface
    /// faces. Rendering it is the answer, so it is required rather than decorative.
    public static func input(
        _ check: CheckID,
        server: MCPServer?,
        skill: Skill?,
        clients: [SkillClient]
    ) -> String {
        if let server, check.subjectKind == .server {
            return ServerChecks.input(check, server)
        }
        if let skill, check.subjectKind == .skill {
            return SkillChecks.input(check, skill, clients: clients)
        }
        return "—"
    }
}
