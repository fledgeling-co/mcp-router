import Foundation

/// What a notification would be about.
///
/// Three kinds and not one, because the three want different sentences and different remedies.
/// Collapsing them into "there is a problem with this credential" is how a notification becomes
/// something its reader learns to dismiss.
public enum AuthExpiryNoticeKind: String, Sendable, Hashable, CaseIterable {
    /// The expiry is known and inside the warning window. There is still time.
    case expiring
    /// The expiry is known and has passed.
    case expired
    /// The upstream refused the credential the router holds, recorded by an index that already
    /// ran. Independent of expiry: a token can be refused long before its declared lifetime is up,
    /// and that is the case the brief names first — *before an agent tool call fails in active
    /// use*.
    case refused
}

/// One thing worth telling the user about, with the words to tell them.
///
/// The copy lives here rather than in the surface that renders it for the reason
/// ``UpstreamStateReport`` gives about its own: the sentence and the decision to say it are the
/// same judgement, and splitting them is how a view ends up saying "expired" about a record whose
/// expiry this router never knew.
public struct AuthExpiryNotice: Sendable, Hashable {
    public let server: String
    public let kind: AuthExpiryNoticeKind
    /// `nil` on a ``AuthExpiryNoticeKind/refused`` notice whose expiry is not derivable — which is
    /// the case the headline has to say out loud rather than round to a date.
    public let expiresAtMs: Double?
    public let hasRefreshToken: Bool
    /// What is true, in one clause.
    public let headline: String
    /// What to do about it.
    public let remedy: String
    /// The command to type, present only when running it can actually help.
    public let command: String?

    public init(
        server: String,
        kind: AuthExpiryNoticeKind,
        expiresAtMs: Double?,
        hasRefreshToken: Bool,
        headline: String,
        remedy: String,
        command: String?
    ) {
        self.server = server
        self.kind = kind
        self.expiresAtMs = expiresAtMs
        self.hasRefreshToken = hasRefreshToken
        self.headline = headline
        self.remedy = remedy
        self.command = command
    }
}

public extension AuthExpiryNotice {
    /// The notice this record deserves, or `nil` when it deserves none.
    ///
    /// `nil` is the ordinary answer. A server that is not authorisable, holds no credential, or
    /// holds one that is valid and was not refused has nothing to say — and a record whose expiry
    /// is merely ``AuthExpiryState/unknown`` has nothing to say **either**, because a notification
    /// every time the router cannot compute a date is a notification nobody can act on and one
    /// that never stops. Unknown is reported in the inventory, where it is a fact a reader can go
    /// and look at, and it is never rounded up to `valid` there.
    static func about(_ record: AuthExpiryRecord, verb: String) -> AuthExpiryNotice? {
        guard record.authCapable, record.hasAccessToken else { return nil }
        let kind: AuthExpiryNoticeKind? = switch record.state {
        case .expired: .expired
        case .expiring: .expiring
        // A refusal is the fallback rather than an override: a credential that has expired **and**
        // was refused is reported as expired, because that is the fact with the remedy attached.
        default: record.credentialRefused ? .refused : nil
        }
        guard let kind else { return nil }
        return build(record, kind: kind, verb: verb)
    }

    private static func build(
        _ record: AuthExpiryRecord, kind: AuthExpiryNoticeKind, verb: String
    ) -> AuthExpiryNotice {
        let when = record.expiresAtMs.map { JSDate.iso8601(milliseconds: $0) }
        let headline: String = switch kind {
        case .expiring:
            "its access token expires on \(when ?? "an unknown date")"
        case .expired:
            "its access token expired on \(when ?? "an unknown date")"
        case .refused:
            // The one sentence that has to be able to say the router does not know. A refused
            // credential whose lifetime was never declared is exactly the state this feature must
            // not describe as healthy, and "expiry unknown" is the honest half of it.
            when.map { "the upstream refused it, and its access token expires on \($0)" }
                ?? "the upstream refused it, and this router cannot tell when it expires"
        }
        // The `mobbin` rule, applied to a notification rather than to a report: with a refresh
        // token held there is something to refresh from, and sending its owner to re-authorise
        // sends them round a loop that cannot succeed.
        let refreshable = record.hasRefreshToken
        return AuthExpiryNotice(
            server: record.server,
            kind: kind,
            expiresAtMs: record.expiresAtMs,
            hasRefreshToken: refreshable,
            headline: headline,
            remedy: refreshable
                ? "A refresh token is held, so this may renew itself. Authorise it again only if it does not."
                : "There is nothing to refresh from, so authorise it again.",
            command: refreshable ? nil : "\(verb) auth \(record.server)"
        )
    }
}
