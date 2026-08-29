import Foundation

/// What is known about one upstream's credential lifetime.
///
/// **``unknown`` is the case this whole type exists to keep reachable.** An access token whose
/// stored record declares no `expires_in` has no knowable expiry, and the tempting reading — it has
/// not expired, so it is fine — is the vacuity this campaign keeps finding: a state that reads
/// healthy because nothing measured it. There is no path below from a missing number to ``valid``.
public enum AuthExpiryState: String, Sendable, Hashable, CaseIterable {
    /// This upstream cannot be authorised at all, so it has no credential to expire. A stdio child
    /// and an HTTP upstream with `oauth: false`, which is `describe()`'s own test.
    case notApplicable = "not-applicable"
    /// Authorisable, and holding no access token. Nothing to expire, and nothing to warn about:
    /// a server nobody has authorised is not a server whose authorisation lapsed.
    case noCredential = "no-credential"
    /// A token is held and its expiry cannot be derived. **Never a synonym for ``valid``.**
    case unknown
    /// A token is held, its expiry is known, and it is further away than
    /// ``AuthExpiryPolicy/warnWithinMs``.
    case valid
    /// A token is held, its expiry is known, and it falls inside the warning window.
    case expiring
    /// A token is held and its expiry has passed.
    case expired
}

/// Why an expiry could not be derived. Carried out to the wire so the answer to *how long have I
/// got* can be "this router does not know, and here is what it is missing" rather than silence.
public enum AuthExpiryUnknownReason: String, Sendable, Hashable {
    /// The stored token object carries no finite `expires_in`. Common and legitimate: a provider
    /// issuing a token with no declared lifetime has told the router nothing to compute from.
    case noLifetimeDeclared = "no-lifetime-declared"
    /// `expires_in` is there and `authorizedAt` is absent or is not a stamp this router can read,
    /// so there is a duration and no origin to add it to.
    case unreadableAuthorizedAt = "unreadable-authorized-at"
}

/// One upstream's credential lifetime, as derived from what the router already holds.
///
/// **The state is derived, never stored** — ``UpstreamHealthRecord`` records the same rule for the
/// same reason. A stored `state` beside a stored `expiresAtMs` makes `(state: .valid,
/// expiresAtMs: <yesterday>)` representable, and the two would then be held in agreement only by
/// every assignment being written correctly everywhere.
///
/// It is derived from **files this router wrote**, not from a probe. See ``AuthExpiryPolicy`` for
/// why that distinction is the design rather than an optimisation.
public struct AuthExpiryRecord: Sendable, Hashable {
    public let server: String
    /// `!isStdio(u) && u.oauth !== false` — `describe()`'s own test for "this upstream can be
    /// authorised at all", and the same one `UpstreamStateReport` applies.
    public let authCapable: Bool
    public let hasAccessToken: Bool
    /// `authorizedAt + expires_in`, in milliseconds, or `nil` when either half is missing.
    public let expiresAtMs: Double?
    public let authorizedAtMs: Double?
    /// Whether a refresh token is held. The remedy turns on it: a server holding one and serving
    /// nothing does not need re-authorising, and telling its owner to re-authorise sends them round
    /// a loop that cannot succeed. `mobbin` is that case and is why `AuthRecord.hasRefreshToken`
    /// exists.
    public let hasRefreshToken: Bool
    /// Whether the error the manifest recorded for this upstream reads as a credential refusal.
    ///
    /// **Observed, never provoked.** It is the index error already on disk from a run that happened
    /// anyway, passed through ``AuthRefusal/isRefusal(_:)``. Nothing here calls an upstream to find
    /// out, which is what keeps this feature spawn-free.
    public let credentialRefused: Bool
    /// The window this record was judged against, carried so a reader can see why a token three
    /// hours out reads `expiring` here and `valid` on a machine configured differently.
    public let warnWithinMs: Int
    /// When the reading was taken. `state` is a function of it, so a record is a statement about a
    /// moment rather than a fact that ages silently.
    public let observedAtMs: Double

    public init(
        server: String,
        authCapable: Bool,
        hasAccessToken: Bool,
        expiresAtMs: Double?,
        authorizedAtMs: Double?,
        hasRefreshToken: Bool,
        credentialRefused: Bool,
        warnWithinMs: Int,
        observedAtMs: Double
    ) {
        self.server = server
        self.authCapable = authCapable
        self.hasAccessToken = hasAccessToken
        self.expiresAtMs = expiresAtMs
        self.authorizedAtMs = authorizedAtMs
        self.hasRefreshToken = hasRefreshToken
        self.credentialRefused = credentialRefused
        self.warnWithinMs = warnWithinMs
        self.observedAtMs = observedAtMs
    }

    public var state: AuthExpiryState {
        guard authCapable else { return .notApplicable }
        guard hasAccessToken else { return .noCredential }
        // The one branch that matters: no number, no verdict. There is no arm below this that can
        // be reached without an expiry, so `valid` cannot be reported by default.
        guard let expiresAtMs else { return .unknown }
        if expiresAtMs <= observedAtMs { return .expired }
        return expiresAtMs - observedAtMs <= Double(warnWithinMs) ? .expiring : .valid
    }

    public var unknownReason: AuthExpiryUnknownReason? {
        guard state == .unknown else { return nil }
        return authorizedAtMs == nil ? .unreadableAuthorizedAt : .noLifetimeDeclared
    }

    /// Milliseconds until expiry — negative once it has passed — or `nil` when it is not known.
    public var remainingMs: Double? {
        expiresAtMs.map { $0 - observedAtMs }
    }
}

public extension AuthExpiryRecord {
    /// Derive one upstream's record from its configuration and its stored credential.
    ///
    /// Every input is already in hand: the upstream as configured, the record on disk, and the
    /// error the last index left in the manifest. Nothing is asked of the upstream itself.
    static func derive(
        upstream: UpstreamConfig,
        record: AuthRecord,
        indexError: String?,
        warnWithinMs: Int,
        nowMilliseconds: Double
    ) -> AuthExpiryRecord {
        let capable = !upstream.isStdio && upstream.oauth != false
        let holdsToken = record.hasAccessToken
        // `authorizedAtMs` is read even when there is no `expires_in`, because it is what
        // distinguishes the two unknown reasons: a record with a stamp and no duration is a
        // provider that declared no lifetime, and one with neither is a record this router cannot
        // read at all.
        let stampMs = record.authorizedAt.flatMap { AuthStamp.milliseconds($0.string) }
        return AuthExpiryRecord(
            server: upstream.name,
            authCapable: capable,
            hasAccessToken: holdsToken,
            expiresAtMs: holdsToken ? record.accessTokenExpiry : nil,
            authorizedAtMs: stampMs,
            hasRefreshToken: record.hasRefreshToken,
            credentialRefused: indexError.map(AuthRefusal.isRefusal) ?? false,
            warnWithinMs: warnWithinMs,
            observedAtMs: nowMilliseconds
        )
    }
}
