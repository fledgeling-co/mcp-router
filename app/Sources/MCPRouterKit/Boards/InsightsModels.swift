import Foundation

/// How many child processes exist right now, against how many servers are declared.
public struct ChildProcessCount: Codable, Hashable, Sendable {
    public var alive: Int
    public var declared: Int

    public init(alive: Int, declared: Int) {
        self.alive = alive
        self.declared = declared
    }
}

/// Resident memory across every child that has a process.
///
/// **Absent rather than zero when nothing is running.** `residentMb()` omits an upstream with no
/// local process, and reporting a zero under a figure labelled *measured, not modelled* would be
/// the one thing that label rules out.
public struct ResidentMemory: Codable, Hashable, Sendable {
    public var megabytes: Int
    /// How many children the figure was taken across, so the number carries its own denominator.
    public var children: Int

    public init(megabytes: Int, children: Int) {
        self.megabytes = megabytes
        self.children = children
    }
}

/// Calls over the window, with the failure rate's numerator and denominator both present.
public struct CallTotals: Codable, Hashable, Sendable {
    public var total: Int
    public var failed: Int
    /// Log lines the router could not read. Carried so a surface can tell a quiet window from a
    /// damaged log — a count of what parsed is not a count of what was there.
    public var unreadableLines: Int

    public init(total: Int, failed: Int, unreadableLines: Int) {
        self.total = total
        self.failed = failed
        self.unreadableLines = unreadableLines
    }
}

/// One bar on the calls-by-harness chart.
///
/// `calls` is **optional and that is the substance of this type**. The router observes the peer
/// process, not the harness; where a process name identifies one harness the count is real, and
/// where it does not — two harnesses behind one `codex` binary, or a harness that runs under `node`
/// — there is no count to give and `reason` says so. A zero there would be a fabricated finding on
/// the one chart whose zero row *is* the finding.
public struct HarnessCallCount: Codable, Hashable, Sendable, Identifiable {
    public var harness: String
    public var displayName: String
    public var calls: Int?
    public var reason: String?

    public var id: String { harness }

    public init(harness: String, displayName: String, calls: Int?, reason: String? = nil) {
        self.harness = harness
        self.displayName = displayName
        self.calls = calls
        self.reason = reason
    }
}

/// One hour of the sparkline.
public struct HourlyCalls: Codable, Hashable, Sendable, Identifiable {
    public var hourStart: String
    public var calls: Int

    public var id: String { hourStart }

    public init(hourStart: String, calls: Int) {
        self.hourStart = hourStart
        self.calls = calls
    }
}

/// One server's share of wall-clock time.
public struct DutyCycleServer: Codable, Hashable, Sendable, Identifiable {
    public var server: String
    public var aliveSeconds: Int

    public var id: String { server }

    public init(server: String, aliveSeconds: Int) {
        self.server = server
        self.aliveSeconds = aliveSeconds
    }
}

/// The duty cycle, with its denominator rather than pre-divided shares.
///
/// The router reports both numbers because a share computed against four seconds of uptime is
/// arithmetically fine and means nothing, and only a surface holding both can decline to draw it.
public struct DutyCycle: Codable, Hashable, Sendable {
    public var uptimeSeconds: Int
    public var servers: [DutyCycleServer]

    public init(uptimeSeconds: Int, servers: [DutyCycleServer]) {
        self.uptimeSeconds = uptimeSeconds
        self.servers = servers
    }
}

/// One rung of the analyst's ladder, as the router names it.
public struct AnalystLaneChoice: Codable, Hashable, Sendable {
    public var lane: String
    public var model: String
    public var label: String

    public init(lane: String, model: String, label: String) {
        self.lane = lane
        self.model = model
        self.label = label
    }
}

/// One session store, read or not.
///
/// **Present for every store the router knows about, including the ones it did not open.** A store
/// omitted because it was absent or of a format the reader does not handle is indistinguishable on
/// this surface from one that held nothing, and only one of those is the user's to act on.
public struct AnalystStoreReport: Codable, Hashable, Sendable, Identifiable {
    public var harness: String
    public var path: String
    public var read: Bool
    public var lines: Int
    public var discarded: Int
    public var reason: String?

    public var id: String { harness }

    public init(
        harness: String,
        path: String,
        read: Bool,
        lines: Int,
        discarded: Int,
        reason: String? = nil
    ) {
        self.harness = harness
        self.path = path
        self.read = read
        self.lines = lines
        self.discarded = discarded
        self.reason = reason
    }
}

/// One recommendation, as the board draws it.
public struct AnalystFindingCard: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var entryID: String
    public var subject: String
    public var sentence: String
    public var evidenceCount: Int
    /// Which model judged, spelled the way the settings readout spells it, so a fallback run never
    /// reads as though the primary produced it.
    public var judgedBy: String
    public var signals: [String]

    public init(
        id: String,
        entryID: String,
        subject: String,
        sentence: String,
        evidenceCount: Int,
        judgedBy: String,
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
}

/// The session analyst's own configuration and last run.
///
/// **Present means the router has an analyst; `ranAt == nil` means it has one that has not run.**
/// The board needs both facts and they are different: the first decides whether `Analyse now` is
/// live, the second decides whether there is a reading to draw. `InsightsResponse.analyst` being
/// nil is the third state — a router with no analyst at all, which is every build before F7 and
/// every router the reference implementation serves.
public struct AnalystRun: Codable, Hashable, Sendable {
    public var primary: AnalystLaneChoice
    public var fallback: AnalystLaneChoice?
    public var cadence: String
    public var cadenceLabel: String
    /// **False in this build, and on the wire rather than assumed.** The cadence is a stored
    /// setting and nothing fires it; a surface drawing "Every 6 hours" without this would be
    /// drawing a promise the router does not keep.
    public var scheduled: Bool
    public var nextRunAt: String?

    public var lane: AnalystLaneChoice?
    public var ranAt: String?
    public var linesRead: Int?
    public var discarded: Int?
    public var findings: Int?
    public var usedFallback: Bool?
    public var rejectedFindings: Int?
    public var candidatesUnavailable: Bool?
    public var stores: [AnalystStoreReport]
    public var recent: [AnalystFindingCard]

    public init(
        primary: AnalystLaneChoice,
        fallback: AnalystLaneChoice? = nil,
        cadence: String,
        cadenceLabel: String,
        scheduled: Bool = false,
        nextRunAt: String? = nil,
        lane: AnalystLaneChoice? = nil,
        ranAt: String? = nil,
        linesRead: Int? = nil,
        discarded: Int? = nil,
        findings: Int? = nil,
        usedFallback: Bool? = nil,
        rejectedFindings: Int? = nil,
        candidatesUnavailable: Bool? = nil,
        stores: [AnalystStoreReport] = [],
        recent: [AnalystFindingCard] = []
    ) {
        self.primary = primary
        self.fallback = fallback
        self.cadence = cadence
        self.cadenceLabel = cadenceLabel
        self.scheduled = scheduled
        self.nextRunAt = nextRunAt
        self.lane = lane
        self.ranAt = ranAt
        self.linesRead = linesRead
        self.discarded = discarded
        self.findings = findings
        self.usedFallback = usedFallback
        self.rejectedFindings = rejectedFindings
        self.candidatesUnavailable = candidatesUnavailable
        self.stores = stores
        self.recent = recent
    }

    /// Whether there is a reading to draw, as opposed to an analyst that exists and has not run.
    public var hasRun: Bool { ranAt != nil }

    /// Every store the run could not open, with the reason it gave.
    public var unreadStores: [AnalystStoreReport] { stores.filter { !$0.read } }
}

/// Everything the Insights board draws, and nothing it does not.
///
/// **Every figure here was counted from calls this router served or from processes it opened.**
/// There is no saving anywhere, because the router never ran the world one would be subtracted
/// from (`DESIGN.md` §6); the product's argument is ``dutyCycle``, and it is measured.
public struct InsightsResponse: Codable, Hashable, Sendable {
    public var generatedAt: String
    public var windowHours: Int
    public var windowStart: String
    /// The oldest record the log actually reached back to, or nil when the window holds none.
    /// This is what lets the board say *not enough history yet* as a measurement rather than a
    /// guess, and what stops it implying it covered a whole day it did not have.
    public var logHorizon: String?
    public var children: ChildProcessCount
    public var calls: CallTotals
    public var resident: ResidentMemory?
    public var callsByHarness: [HarnessCallCount]
    /// Calls from callers no harness claims — including the ones whose peer could not be named.
    /// Present so the bars and the headline total reconcile instead of quietly disagreeing.
    public var otherCalls: Int
    public var dutyCycle: DutyCycle?
    public var callsPerHour: [HourlyCalls]
    public var analyst: AnalystRun?

    public init(
        generatedAt: String,
        windowHours: Int,
        windowStart: String,
        logHorizon: String? = nil,
        children: ChildProcessCount,
        calls: CallTotals,
        resident: ResidentMemory? = nil,
        callsByHarness: [HarnessCallCount] = [],
        otherCalls: Int = 0,
        dutyCycle: DutyCycle? = nil,
        callsPerHour: [HourlyCalls] = [],
        analyst: AnalystRun? = nil
    ) {
        self.generatedAt = generatedAt
        self.windowHours = windowHours
        self.windowStart = windowStart
        self.logHorizon = logHorizon
        self.children = children
        self.calls = calls
        self.resident = resident
        self.callsByHarness = callsByHarness
        self.otherCalls = otherCalls
        self.dutyCycle = dutyCycle
        self.callsPerHour = callsPerHour
        self.analyst = analyst
    }

    /// Whether the window holds enough to draw anything the Activity log would not say better.
    ///
    /// A measurement rather than a threshold picked by eye: with no record in the window there is
    /// nothing to plot, and the brief's own instruction is that a window with too little history
    /// says so rather than extrapolating.
    public var hasHistory: Bool { logHorizon != nil }
}
