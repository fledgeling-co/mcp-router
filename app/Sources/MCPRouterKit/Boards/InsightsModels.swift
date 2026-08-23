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

/// The session analyst's own configuration and last run.
///
/// Modelled and always `nil` today: `PRD.md` §6 specifies the analyst and nothing in `app/Sources`
/// implements one. The board draws its empty state, which is what the brief asks for — *its own
/// configuration and its last run* — rather than absorbing §6.
public struct AnalystRun: Codable, Hashable, Sendable {
    public var model: String
    public var ranAt: String
    public var linesRead: Int
    public var findings: Int

    public init(model: String, ranAt: String, linesRead: Int, findings: Int) {
        self.model = model
        self.ranAt = ranAt
        self.linesRead = linesRead
        self.findings = findings
    }
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
