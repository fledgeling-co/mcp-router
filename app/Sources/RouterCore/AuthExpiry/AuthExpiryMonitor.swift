import Foundation

/// Every declared upstream's credential lifetime, plus the policy that judged them.
public struct AuthExpiryReport: Sendable {
    public let policy: AuthExpiryPolicy
    public let refusals: [AuthExpiryRefusal]
    public let records: [AuthExpiryRecord]

    public init(
        policy: AuthExpiryPolicy, refusals: [AuthExpiryRefusal], records: [AuthExpiryRecord]
    ) {
        self.policy = policy
        self.refusals = refusals
        self.records = records
    }
}

/// The seam the control API reads. `ControlDiff` supplies none — see ``ControlDeps/authExpiry``.
public protocol AuthExpiryReporting: Sendable {
    /// Read the state. **Changes nothing**, including the throttle.
    func report(manifest: Manifest, nowMilliseconds: Double) async -> AuthExpiryReport
    /// Take the notifications that are due now, and record that they went out.
    func claim(manifest: Manifest, nowMilliseconds: Double) async -> [AuthExpiryNotice]
}

/// Derives every upstream's credential lifetime, and decides which of them is worth saying out loud
/// right now.
///
/// ## It arms no task and spawns no child
///
/// `R27`'s monitor holds a loop it deliberately does not start by default, because a probe of a
/// stdio upstream is a child process and `REQ-001` says at rest there are none. This one has no
/// loop to hold. Everything it reports is arithmetic over files the router already wrote — the
/// credential record under `authDir` and the index error already in the manifest — so evaluation
/// costs a few reads and nothing observable from a process table. That is why there is no
/// `start()` here and no interval in ``AuthExpiryPolicy``: the alternative design, asking each
/// upstream whether its token still works, would have needed both and would have inverted the
/// promise it was watching.
///
/// ## Reading and claiming are two operations on purpose
///
/// ``report(manifest:nowMilliseconds:)`` is pure with respect to this actor's state and
/// ``claim(manifest:nowMilliseconds:)`` advances the throttle. Folding them together would make
/// `GET /upstreams/auth-expiry` consume the notification a caller was about to be shown, so
/// opening a settings pane would silence the next alert. A reader that mutates what it reads is
/// the same defect this repository refuses in its own gates.
public actor AuthExpiryMonitor: AuthExpiryReporting {
    /// What was last said about one server, and when.
    private struct Delivery: Hashable {
        let kind: AuthExpiryNoticeKind
        let expiresAtMs: Double?
        let atMs: Double
    }

    private let upstreams: [UpstreamConfig]
    private let policy: AuthExpiryPolicy
    private let refusals: [AuthExpiryRefusal]
    private let auth: FileAuthStore
    private let verb: String
    private var delivered: [String: Delivery] = [:]

    public init(
        upstreams: [UpstreamConfig],
        policy: AuthExpiryPolicy,
        refusals: [AuthExpiryRefusal] = [],
        auth: FileAuthStore,
        verb: String = UpstreamStateReport.entryPoint()
    ) {
        self.upstreams = upstreams
        self.policy = policy
        self.refusals = refusals
        self.auth = auth
        self.verb = verb
    }

    // MARK: - Reading

    /// Every declared upstream, in configuration order.
    ///
    /// A server that cannot be authorised at all is present and `not-applicable` rather than
    /// omitted, for the reason `UpstreamHealthMonitor.snapshot` keeps its unprobed rows: a caller
    /// cannot tell an absent row from a server this router does not know about, and those are
    /// different problems with different fixes.
    public func report(manifest: Manifest, nowMilliseconds: Double) async -> AuthExpiryReport {
        var records: [AuthExpiryRecord] = []
        for upstream in upstreams {
            let stored = await auth.read(JSString(upstream.name))
            records.append(AuthExpiryRecord.derive(
                upstream: upstream,
                record: stored,
                indexError: manifest.entry(named: upstream.name)?.error?.string,
                warnWithinMs: policy.warnWithinMs,
                nowMilliseconds: nowMilliseconds
            ))
        }
        return AuthExpiryReport(policy: policy, refusals: refusals, records: records)
    }

    // MARK: - Claiming

    /// The notices due now, with the throttle advanced for each one returned.
    ///
    /// Four ways a notice is due, and the first three are the reason the throttle cannot hide
    /// anything that matters:
    ///
    /// 1. nothing has been said about this server yet;
    /// 2. **the kind changed** — `expiring` becoming `expired` is an escalation and goes out
    ///    however recently the warning did, which is the arm a naive "one alert per six hours"
    ///    throttle swallows;
    /// 3. **the expiry moved** — the credential was replaced, so this is a new fact about a new
    ///    token rather than a repeat about the old one;
    /// 4. ``AuthExpiryPolicy/renotifyAfterMs`` has elapsed.
    ///
    /// And a server that stops deserving a notice has its record **dropped**, which is the brief's
    /// *resolving authentication immediately clears the warning status*: re-authorise, and the next
    /// thing that goes wrong is reported at once rather than waited out.
    public func claim(manifest: Manifest, nowMilliseconds: Double) async -> [AuthExpiryNotice] {
        let report = await report(manifest: manifest, nowMilliseconds: nowMilliseconds)
        var due: [AuthExpiryNotice] = []
        for record in report.records {
            guard let notice = AuthExpiryNotice.about(record, verb: verb) else {
                delivered[record.server] = nil
                continue
            }
            guard isDue(notice, atMs: nowMilliseconds) else { continue }
            delivered[record.server] = Delivery(
                kind: notice.kind, expiresAtMs: notice.expiresAtMs, atMs: nowMilliseconds
            )
            due.append(notice)
        }
        return due
    }

    private func isDue(_ notice: AuthExpiryNotice, atMs nowMilliseconds: Double) -> Bool {
        guard let prior = delivered[notice.server] else { return true }
        if prior.kind != notice.kind { return true }
        if prior.expiresAtMs != notice.expiresAtMs { return true }
        return nowMilliseconds - prior.atMs >= Double(policy.renotifyAfterMs)
    }

    /// Whether anything has been said about this server yet — for asserting that a read did
    /// **not** advance the throttle, which is a claim no amount of reading the report can make.
    public func hasDelivered(_ server: String) -> Bool {
        delivered[server] != nil
    }
}
