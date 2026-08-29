import Foundation

/// What one probe did.
///
/// ``declined`` is a fourth case rather than a flavour of ``failed`` and the distinction is the
/// whole reason a scheduled sweep is safe to run. A background sweep skips an upstream that is not
/// live, because probing it would spawn the child `REQ-001` promises is not there; recording that
/// skip as a failure would trip every idle server on the second sweep, which is a health check that
/// reports the router's own design as an outage.
public enum ProbeOutcome: Sendable, Hashable {
    /// The upstream answered `tools/list`, with the round trip and the number of tools it named.
    case ok(latencyMs: Int, tools: Int)
    /// The request outlived ``HealthPolicy/probeTimeoutMs``. Nothing is claimed about the upstream
    /// beyond that: a server that answers on the next millisecond is not distinguished here from
    /// one that never will.
    case timedOut(afterMs: Int)
    /// The upstream, or the acquisition of it, reported an error. Carries the reason verbatim.
    case failed(reason: String)
    /// No probe was attempted. Not evidence of anything about the upstream.
    case declined(reason: String)

    /// Whether this outcome counts against ``UpstreamHealthRecord/consecutiveFailures``.
    public var isFailure: Bool {
        switch self {
        case .ok, .declined: false
        case .timedOut, .failed: true
        }
    }

    /// A short word for the wire and the logs.
    public var kind: String {
        switch self {
        case .ok: "ok"
        case .timedOut: "timeout"
        case .failed: "error"
        case .declined: "declined"
        }
    }
}

/// The four states a probed upstream can be in.
///
/// `ServerState` — `idle`, `starting`, `running`, `stopping` — is deliberately **not** extended.
/// That enum is the control API's wire contract, transcribed from `describe()` in `src/control.ts`
/// and diffed byte for byte by R4's parity gate; adding a case to it would move a surface this
/// feature has no business touching, and it would also be a category error. Those four say what the
/// router is doing with a process. These four say whether the thing on the other end answers.
public enum UpstreamHealthState: String, Sendable, Hashable, CaseIterable {
    /// No probe has completed. Distinct from ``healthy`` in exactly the way `LoadState.loading` is
    /// distinct from `.loaded([])`: nothing has been measured, which is not the same as a
    /// measurement that came back clean.
    case unprobed
    /// The last probe succeeded.
    case healthy
    /// At least one consecutive failure, below the trip threshold.
    case degraded
    /// Consecutive failures reached ``HealthPolicy/tripAfter``.
    case tripped
}

/// One upstream's health, as measured.
///
/// **The state is derived, never stored.** A stored `state` beside a stored `consecutiveFailures`
/// makes `(state: .healthy, consecutiveFailures: 4)` representable, and the two would then be held
/// in agreement by one assignment being written correctly everywhere. `ServerStateTracker.hasLoaded`
/// records the same argument for the same reason; this is that rule applied a second time rather
/// than a coincidence of style.
public struct UpstreamHealthRecord: Sendable, Hashable {
    public let server: String
    /// The policy this server actually runs under — global values with its own overrides applied.
    public let policy: HealthPolicy
    /// Configured values that were not applied. Empty for almost every server, and the reason the
    /// wire carries a policy at all: a caller reading `probeTimeoutMs: 5000` deserves to know that
    /// the file said 0.
    public let refusals: [HealthPolicyRefusal]

    /// Probes actually attempted. A declined sweep does not move it.
    public private(set) var probesRun: Int = 0
    public private(set) var consecutiveFailures: Int = 0
    public private(set) var lastOutcome: ProbeOutcome?
    public private(set) var lastProbeAtMs: Double?
    public private(set) var lastOkAtMs: Double?
    /// Why the most recent sweep skipped this upstream, if it did. Cleared by any real attempt.
    public private(set) var lastDeclined: String?

    public init(server: String, policy: HealthPolicy, refusals: [HealthPolicyRefusal] = []) {
        self.server = server
        self.policy = policy
        self.refusals = refusals
    }

    public var state: UpstreamHealthState {
        guard probesRun > 0 else { return .unprobed }
        guard consecutiveFailures > 0 else { return .healthy }
        return consecutiveFailures >= policy.tripAfter ? .tripped : .degraded
    }

    /// Apply an outcome at `atMs`.
    ///
    /// Recovery is the single `consecutiveFailures = 0` below: one success returns a tripped
    /// upstream to healthy, with no cooling-off period and no second confirming probe. That is a
    /// deliberate asymmetry — failing takes ``HealthPolicy/tripAfter`` readings and recovering takes
    /// one — because the cost of the two mistakes is not symmetric. Reporting a working server as
    /// tripped sends somebody to debug a server that is fine.
    public mutating func apply(_ outcome: ProbeOutcome, atMs: Double) {
        guard case let .declined(reason) = outcome else {
            probesRun += 1
            lastProbeAtMs = atMs
            lastOutcome = outcome
            lastDeclined = nil
            if outcome.isFailure {
                consecutiveFailures += 1
            } else {
                consecutiveFailures = 0
                lastOkAtMs = atMs
            }
            return
        }
        lastDeclined = reason
    }

    /// Whether a sweep at `nowMs` is due, given this server's own interval.
    ///
    /// A server whose interval is zero is never due — that is what "background probing off" means,
    /// and it is checked here rather than in the loop so the loop cannot forget it.
    public func isDue(atMs nowMs: Double) -> Bool {
        guard policy.probeIntervalMs > 0 else { return false }
        guard let lastProbeAtMs else { return true }
        return nowMs - lastProbeAtMs >= Double(policy.probeIntervalMs)
    }
}
