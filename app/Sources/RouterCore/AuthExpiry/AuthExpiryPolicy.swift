import Foundation

/// A configured auth-expiry value that was **not** applied, and why.
///
/// Its own type rather than a reuse of ``HealthPolicyRefusal``, which carries the same four
/// members. The members are the same; the *destination* is not. A refusal reaching the wire tells
/// its reader which block of `servers.json` to go and fix, and one labelled with a health type in
/// an auth-expiry response sends them to the wrong block — the one place where sharing a struct
/// costs something real.
public struct AuthExpiryRefusal: Sendable, Hashable {
    /// `global` for the top-level `authExpiry` block in `servers.json`. Only that scope exists
    /// today: this policy is a preference about when its owner wants to be told, which is a
    /// property of the person rather than of one upstream. A per-server override would need the
    /// writer `R26-C2` needs anyway, and is registered there rather than half-built here.
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

/// How far ahead of an expiry its owner is warned, and how often they are told again.
///
/// ## This feature derives; it does not ask
///
/// `R27` established the rule this inherits: a probe of a stdio upstream **is** a child process,
/// and `README.md`'s first guarantee — `REQ-001` — is that at rest there are none. So R27's
/// background probing defaults to off and a scheduled sweep never cold-starts.
///
/// The expiry of an access token needs no probe at all. It is `authorizedAt + expires_in`, and
/// both halves are already on disk in the record this router wrote when the flow settled
/// (``AuthRecord/accessTokenExpiry``). Evaluating this whole feature reads files and spawns
/// nothing, which is why — unlike ``HealthPolicy`` — it is **on by default** and needs no
/// justification for arming a loop: it arms none. Nothing here wakes on a timer. The report is
/// computed when somebody asks for it.
///
/// That is also why the two numbers below are about *notifying*, not about *measuring*. There is
/// no interval, because there is nothing to schedule.
public struct AuthExpiryPolicy: Sendable, Hashable {
    /// How long before an access token's expiry an upstream begins to read `expiring`.
    public var warnWithinMs: Int
    /// The smallest gap between two notifications that say the same thing about the same server.
    ///
    /// It throttles repetition and **never** an escalation: `expiring` becoming `expired`, or an
    /// expiry moving because the credential was replaced, are new facts and go out immediately.
    /// See ``AuthExpiryMonitor/claim(records:atMs:)``.
    public var renotifyAfterMs: Int

    public init(warnWithinMs: Int, renotifyAfterMs: Int) {
        self.warnWithinMs = warnWithinMs
        self.renotifyAfterMs = renotifyAfterMs
    }

    /// A day's warning, and at most one repeat every six hours.
    public static let standard = AuthExpiryPolicy(
        warnWithinMs: 86_400_000, renotifyAfterMs: 21_600_000
    )

    /// The floor on ``warnWithinMs``, and this item's own version of `R27`'s `tripAfter >= 2`.
    ///
    /// **Zero is not accepted here, and that is the whole point of the rule.** With a warning
    /// window of zero a token passes straight from `valid` to `expired`, `expiring` is unreachable,
    /// and the promise this feature exists to keep — *you are told before it stops working* —
    /// would hold only because nothing can enter the state it names. That is a guarantee satisfied
    /// by the absence of the thing it constrains, which is the shape this repository refuses rather
    /// than ships. A minute is the smallest window in which being told first is still worth
    /// anything.
    public static let minimumWarnWithinMs = 60000
    /// The floor on ``renotifyAfterMs``. Zero is not "no throttle", it is the alert spam the brief
    /// asked this feature not to be: a caller polling every second would raise a notification every
    /// second for as long as the credential stayed expired.
    public static let minimumRenotifyAfterMs = 60000
}

/// A policy and everything that was thrown away making it.
public struct AuthExpiryResolution: Sendable, Hashable {
    public let policy: AuthExpiryPolicy
    public let refusals: [AuthExpiryRefusal]

    public init(policy: AuthExpiryPolicy, refusals: [AuthExpiryRefusal]) {
        self.policy = policy
        self.refusals = refusals
    }
}

public extension AuthExpiryPolicy {
    /// The top-level `authExpiry` block of `servers.json`, resolved against ``standard``.
    ///
    /// **Refused rather than clamped**, for the reason `HealthPolicy.resolve` gives: a clamp
    /// invents a value nobody wrote, so the file says one number and the behaviour is another with
    /// nothing anywhere saying which is real. Every refusal reaches the wire carrying the key, the
    /// value as written, the floor that rejected it and its scope.
    ///
    /// `nil`, a non-object, and a member that is not a number all configure nothing rather than
    /// half-configuring something — the same reading `HealthOverride.read` does. A string is not a
    /// number to refuse, so it is absent here rather than reported.
    static func readGlobal(_ raw: JSONValue?) -> AuthExpiryResolution {
        var policy = AuthExpiryPolicy.standard
        var refusals: [AuthExpiryRefusal] = []

        func take(_ key: String, floor: Int, into field: inout Int) {
            guard let raw, case .object = raw else { return }
            guard let value = raw.member(key)?.asNumber.flatMap(JSNumber.int) else { return }
            guard value >= floor else {
                refusals.append(AuthExpiryRefusal(
                    scope: "global", key: key, value: value,
                    reason: "below the floor of \(floor)"
                ))
                return
            }
            field = value
        }

        take("warnWithinMs", floor: minimumWarnWithinMs, into: &policy.warnWithinMs)
        take("renotifyAfterMs", floor: minimumRenotifyAfterMs, into: &policy.renotifyAfterMs)
        return AuthExpiryResolution(policy: policy, refusals: refusals)
    }
}
