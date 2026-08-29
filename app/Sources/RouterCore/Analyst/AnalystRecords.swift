import Foundation

/// One recommendation, as the router holds it.
public struct AnalystFindingRecord: Sendable, Hashable {
    public let id: String
    public let entryID: String
    public let subject: String
    public let sentence: String
    public let evidenceCount: Int
    /// The lane that produced it. Carried per finding rather than only per run, because a run whose
    /// primary refused half way would otherwise report one model over two models' findings.
    public let judgedBy: AnalystLane
    public let signals: [String]

    public init(
        id: String,
        entryID: String,
        subject: String,
        sentence: String,
        evidenceCount: Int,
        judgedBy: AnalystLane,
        signals: [String]
    ) {
        self.id = id
        self.entryID = entryID
        self.subject = subject
        self.sentence = sentence
        self.evidenceCount = evidenceCount
        self.judgedBy = judgedBy
        self.signals = signals
    }

    /// What suppression is keyed on: the entry, and the signals that argued for it.
    ///
    /// **The signals are in the key deliberately.** A finding whose evidence has grown a new signal
    /// is a different finding — that is `PRD.md` §6.3's *"unless triggered by a new explicit failure
    /// pattern"* expressed as an identity rather than as a second rule that could disagree with the
    /// first.
    public var fingerprint: String {
        ([entryID] + signals.sorted()).joined(separator: "\u{1F}")
    }
}

/// One run, with everything a surface is allowed to draw about it.
public struct AnalystRunRecord: Sendable, Hashable {
    /// The lane that judged, or **nil when nothing was judged** — no pattern reached the floor, or
    /// the router could name no capability to choose between. A lane here would say a model ran.
    public let lane: AnalystLane?
    public let ranAtMilliseconds: Double
    public let linesRead: Int
    public let discardedLines: Int
    public let usedFallback: Bool
    /// Replies the run threw away — an id outside the candidate list, or a line it could not read.
    public let rejectedFindings: Int
    /// The router could not name a single capability, so nothing was recommended and nothing was
    /// inferred. Reported rather than folded into a zero.
    public let candidatesUnavailable: Bool
    public let stores: [SessionStoreReport]
    public let findings: [AnalystFindingRecord]

    public init(
        lane: AnalystLane?,
        ranAtMilliseconds: Double,
        linesRead: Int,
        discardedLines: Int,
        usedFallback: Bool,
        rejectedFindings: Int,
        candidatesUnavailable: Bool,
        stores: [SessionStoreReport],
        findings: [AnalystFindingRecord]
    ) {
        self.lane = lane
        self.ranAtMilliseconds = ranAtMilliseconds
        self.linesRead = linesRead
        self.discardedLines = discardedLines
        self.usedFallback = usedFallback
        self.rejectedFindings = rejectedFindings
        self.candidatesUnavailable = candidatesUnavailable
        self.stores = stores
        self.findings = findings
    }
}

/// Why a run produced no record at all.
public enum AnalystRunFailure: Error, Sendable, Hashable {
    /// Every rung of the ladder was tried and none answered, with what each one said.
    case ladderExhausted([String])
    /// A run is already in flight. The analyst spawns a process and reads the whole corpus; two at
    /// once would double both for one answer.
    case alreadyRunning
}

/// What the analyst keeps between runs: the settings, the last run, and what it has already said.
///
/// Held as ``JSONValue`` and written through ``FileSystem`` for the reason every other persisted
/// shape in this router is: `Codable` decides member order and missing-key behaviour out of sight,
/// and this file is read by a build that may be older than the one that wrote it.
public struct AnalystState: Sendable, Hashable {
    public var settings: AnalystSettings
    public var lastRun: AnalystRunRecord?
    /// Fingerprint to the millisecond it was first delivered.
    public var delivered: [(fingerprint: String, atMilliseconds: Double)]

    public init(
        settings: AnalystSettings = AnalystSettings(),
        lastRun: AnalystRunRecord? = nil,
        delivered: [(fingerprint: String, atMilliseconds: Double)] = []
    ) {
        self.settings = settings
        self.lastRun = lastRun
        self.delivered = delivered
    }

    public static func == (lhs: AnalystState, rhs: AnalystState) -> Bool {
        lhs.settings == rhs.settings && lhs.lastRun == rhs.lastRun
            && lhs.delivered.map(\.fingerprint) == rhs.delivered.map(\.fingerprint)
            && lhs.delivered.map(\.atMilliseconds) == rhs.delivered.map(\.atMilliseconds)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(settings)
        hasher.combine(lastRun)
        hasher.combine(delivered.map(\.fingerprint))
    }

    /// How long a delivered finding stays quiet — `PRD.md` §6.3's thirty days.
    public static let suppressionMilliseconds: Double = 30 * 24 * 3_600_000

    public func isSuppressed(_ fingerprint: String, now: Double) -> Bool {
        guard let seen = delivered.first(where: { $0.fingerprint == fingerprint })
        else { return false }
        return now - seen.atMilliseconds < Self.suppressionMilliseconds
    }
}
