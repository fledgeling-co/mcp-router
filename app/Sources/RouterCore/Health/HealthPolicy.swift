import Foundation

/// A configured health value that was **not** applied, and why.
///
/// Carried out to the wire rather than logged and dropped. A router that silently substitutes its
/// own default for a number the operator wrote is a router whose settings screen lies: the file
/// says 500 and the behaviour is 5000, with nothing anywhere saying which one is real. Every
/// refusal below names the key, the value as written, and the reason — so the answer to "why is my
/// probe not running every half second" is in the same response as the probe result.
public struct HealthPolicyRefusal: Sendable, Hashable {
    /// `global` for the top-level block in `servers.json`, `server` for one server's own.
    ///
    /// Carried because the two are fixed in different places, and a reader told only that
    /// `probeTimeoutMs` was refused has to go and look in both.
    public let scope: String
    public let key: String
    public let value: Int
    public let reason: String

    public init(scope: String, key: String, value: Int, reason: String) {
        self.scope = scope
        self.key = key
        self.value = value
        self.reason = reason
    }
}

/// What a health probe costs, how often it runs, and how many consecutive failures trip an upstream.
///
/// ## Background probing is OFF by default, and that is a product decision rather than caution
///
/// A health probe on a stdio upstream is a **child process**. `README.md`'s first guarantee — and
/// `REQ-001` — is that at rest there are zero of those: nothing is spawned until a tool on that
/// server is actually called. An interval probe that cold-started every declared upstream would
/// hold one child per server open forever, which is not a health check with a cost, it is the
/// router's central promise inverted.
///
/// So two rules keep the two compatible, and they are the reason this type exists rather than a
/// pair of loose integers:
///
/// 1. ``probeIntervalMs`` defaults to zero, which arms no background probing at all.
/// 2. A **scheduled** probe never cold-starts an upstream — ``UpstreamHealthMonitor/sweepOnce()``
///    probes only what is already live. A **manual** probe may, because a person asked for it.
///
/// The brief's own assumption said this from the other side: *background health checks run
/// passively during idle windows rather than issuing disruptive polling storms*.
public struct HealthPolicy: Sendable, Hashable {
    /// Milliseconds between background probes of one upstream. Zero disables them for that server.
    public var probeIntervalMs: Int
    /// How long one probe's `tools/list` may take before it is recorded as a timeout.
    ///
    /// It bounds the **request**, not the acquisition. A cold upstream is bounded by the
    /// `startupTimeoutMs` it already has, and a second budget over the same spawn would be two
    /// numbers racing to describe one failure — the caller would be told the probe timed out where
    /// the truth is that the child never started, which are different things to act on.
    public var probeTimeoutMs: Int
    /// Consecutive failures that move an upstream from degraded to tripped.
    public var tripAfter: Int

    public init(probeIntervalMs: Int, probeTimeoutMs: Int, tripAfter: Int) {
        self.probeIntervalMs = probeIntervalMs
        self.probeTimeoutMs = probeTimeoutMs
        self.tripAfter = tripAfter
    }

    /// No background probing; a five-second bound on a manual one; tripped on the third failure.
    public static let standard = HealthPolicy(
        probeIntervalMs: 0, probeTimeoutMs: 5000, tripAfter: 3
    )

    /// The floor on ``probeIntervalMs``. A sub-second interval over twenty-one upstreams is the
    /// polling storm this feature was asked not to be.
    public static let minimumIntervalMs = 1000
    /// The floor on ``tripAfter``, and the one validation rule here that is not about cost.
    ///
    /// With a threshold of 1 the first failure trips, so `degraded` is unreachable and the
    /// guarantee *an upstream is flagged degraded before it is marked tripped* would hold only
    /// because nothing can ever enter the state it names. That is a guarantee satisfied by the
    /// absence of the thing it constrains, which is the one shape this repository has decided to
    /// refuse rather than ship.
    public static let minimumTripAfter = 2
}

/// A policy and everything that was thrown away making it.
public struct HealthPolicyResolution: Sendable, Hashable {
    public let policy: HealthPolicy
    public let refusals: [HealthPolicyRefusal]

    public init(policy: HealthPolicy, refusals: [HealthPolicyRefusal]) {
        self.policy = policy
        self.refusals = refusals
    }
}

public extension HealthPolicy {
    /// Resolve one upstream's effective policy: the global values, then this server's overrides,
    /// with every out-of-range number refused rather than clamped.
    ///
    /// Refused rather than clamped because clamping invents a value nobody wrote. A clamp turns
    /// `probeIntervalMs: 10` into 1000 and reports 1000, and the operator's next reading of their
    /// own file disagrees with the router for a reason neither of them can see.
    static func resolve(
        global: HealthPolicy, override: HealthOverride?, scope: String = "server"
    ) -> HealthPolicyResolution {
        var policy = global
        var refusals: [HealthPolicyRefusal] = []

        func take(_ key: String, _ value: Int?, floor: Int, allowingZero: Bool, into field: inout Int) {
            guard let value else { return }
            if allowingZero, value == 0 {
                field = 0
                return
            }
            guard value >= floor else {
                refusals.append(HealthPolicyRefusal(
                    scope: scope, key: key, value: value,
                    reason: "below the floor of \(floor)\(allowingZero ? " (0 disables it)" : "")"
                ))
                return
            }
            field = value
        }

        take(
            "probeIntervalMs", override?.probeIntervalMs, floor: minimumIntervalMs,
            allowingZero: true, into: &policy.probeIntervalMs
        )
        take(
            "probeTimeoutMs", override?.probeTimeoutMs, floor: 1,
            allowingZero: false, into: &policy.probeTimeoutMs
        )
        take(
            "tripAfter", override?.tripAfter, floor: minimumTripAfter,
            allowingZero: false, into: &policy.tripAfter
        )
        return HealthPolicyResolution(policy: policy, refusals: refusals)
    }
}

/// One server's `health` block, as written. Every member optional: an override that names one key
/// leaves the other two on the global value rather than resetting them to a default.
public struct HealthOverride: Sendable, Hashable {
    public var probeIntervalMs: Int?
    public var probeTimeoutMs: Int?
    public var tripAfter: Int?

    public init(probeIntervalMs: Int? = nil, probeTimeoutMs: Int? = nil, tripAfter: Int? = nil) {
        self.probeIntervalMs = probeIntervalMs
        self.probeTimeoutMs = probeTimeoutMs
        self.tripAfter = tripAfter
    }

    /// Read a `health` object out of a server entry or the top of `servers.json`.
    ///
    /// `nil` when the member is absent or is not an object, so `"health": 3` configures nothing
    /// rather than half-configuring something. A member present with a non-numeric value is
    /// likewise absent here, and is refused at ``HealthPolicy/resolve(global:override:)`` only
    /// where it carries a number the policy will not take — a string is not a number to refuse.
    public static func read(_ value: JSONValue?) -> HealthOverride? {
        guard let value, case .object = value else { return nil }
        func number(_ key: String) -> Int? {
            value.member(key)?.asNumber.flatMap(JSNumber.int)
        }
        return HealthOverride(
            probeIntervalMs: number("probeIntervalMs"),
            probeTimeoutMs: number("probeTimeoutMs"),
            tripAfter: number("tripAfter")
        )
    }
}

public extension HealthPolicy {
    /// The top-level `health` block of `servers.json`, resolved against ``standard``.
    ///
    /// Separate from ``resolve(global:override:scope:)`` only in what it labels its refusals. A
    /// global value the router would not take has to reach the wire the same way a server's does:
    /// dropping it here is how a settings screen ends up disagreeing with the file behind it.
    static func readGlobal(_ raw: JSONValue?) -> HealthPolicyResolution {
        resolve(global: .standard, override: HealthOverride.read(raw), scope: "global")
    }
}
