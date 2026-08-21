import Foundation

/// One server's credential record: `{ clientInformation?, tokens?, codeVerifier?, authorizedAt? }`.
///
/// Held as ordered `[JSONMember]` rather than a Swift struct with `Codable`, for the reason the
/// whole port is built on: the file's **bytes** are the contract, and a struct re-serialises in
/// declaration order, dropping any member the reference wrote that this type does not model. A
/// record written by a newer router and read by this one must survive a merge-write unchanged.
public struct AuthRecord: Sendable, Hashable {
    public var members: [JSONMember]

    public init(members: [JSONMember] = []) {
        self.members = members
    }

    public init?(_ value: JSONValue) {
        guard case let .object(members) = value else { return nil }
        self.members = members
    }

    public var value: JSONValue { .object(members) }

    public func member(_ key: String) -> JSONValue? {
        let wanted = JSString(key)
        return members.first { $0.key == wanted }?.value
    }

    /// `!!readRecord(server).tokens?.access_token`.
    ///
    /// False when `tokens` is absent, when it is not an object, and when it holds no
    /// `access_token` — and also when `access_token` is present but falsy, because the reference's
    /// `!!` coerces. An empty-string token is not a token.
    public var hasAccessToken: Bool {
        guard let tokens = member("tokens") else { return false }
        guard let token = tokens.member("access_token") else { return false }
        switch token {
        case let .string(text): return !text.isEmpty
        case let .bool(flag): return flag
        case let .number(value): return value != 0 && !value.isNaN
        case .null: return false
        case .array, .object: return true
        }
    }

    /// The record's `authorizedAt`, verbatim, or nil (B97).
    public var authorizedAt: JSString? { member("authorizedAt")?.asString }

    /// Whether a refresh token is held, which is what decides if a refused credential has a
    /// remedy the user can type.
    ///
    /// A server holding a refresh token and serving nothing is not an authorisation problem, and
    /// telling its owner to re-authorise sends them round a loop that cannot succeed. A server
    /// whose access token was refused with no refresh token behind it genuinely does need
    /// authorising again. `mobbin` is the first case and is why this accessor exists.
    public var hasRefreshToken: Bool {
        guard let token = member("tokens")?.member("refresh_token") else { return false }
        if case let .string(text) = token { return !text.isEmpty }
        return false
    }

    /// When the held access token expires, in milliseconds, from the stored `authorizedAt` plus
    /// `expires_in`.
    ///
    /// A stored stamp, never a cached verdict: REQ-007's rule is that the router does not display
    /// what it has not observed, and "expired" computed from two recorded numbers is an
    /// observation where "stale" copied from a status field is a belief. Nil when either half is
    /// missing, which is honest — a token with no declared lifetime has no knowable expiry.
    public var accessTokenExpiry: Double? {
        guard case let .number(seconds) = member("tokens")?.member("expires_in") ?? .null,
              seconds.isFinite,
              let stamp = authorizedAt?.string
        else { return nil }
        guard let parsed = AuthStamp.milliseconds(stamp) else { return nil }
        return parsed + seconds * 1000
    }

    /// The record's `codeVerifier`, verbatim, or nil. The *throwing* accessor the reference exposes
    /// lives on the provider (B97); this is the raw read it is built on.
    public var codeVerifier: JSString? { member("codeVerifier")?.asString }

    /// `{ ...readRecord(server), <key>: <value> }`.
    ///
    /// Spread-merge semantics, which are not the same as "append": a key the record already carries
    /// keeps its **existing position** and only genuinely new keys go on the end (B91). A fresh
    /// literal order here would rewrite a credential file's bytes on every save.
    public mutating func merge(_ key: String, _ value: JSONValue) {
        let wanted = JSString(key)
        if let index = members.firstIndex(where: { $0.key == wanted }) {
            members[index] = JSONMember(key: wanted, value: value)
        } else {
            members.append(JSONMember(key: wanted, value: value))
        }
    }

    /// The bytes: `JSON.stringify(rec, null, 2)`.
    public var serialized: String { JSStringify.prettyTwoSpace(value) }
}
