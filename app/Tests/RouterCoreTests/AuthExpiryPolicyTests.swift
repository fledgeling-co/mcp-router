import Foundation
import Testing
@testable import RouterCore

/// R26 — the policy, and the state machine it drives.
///
/// The state assertions live here rather than beside the routes for the reason
/// `UpstreamHealthPolicyTests` gives about its own: the derivation is a pure function of five
/// stored facts, and it is the half a route test cannot exercise at every boundary.
@Suite("R26 auth expiry policy")
struct AuthExpiryPolicyTests {
    private static let now: Double = 1_770_000_000_000

    private static func record(
        _ json: String,
        upstream: UpstreamConfig = httpUpstream("mobbin"),
        indexError: String? = nil,
        warnWithinMs: Int = AuthExpiryPolicy.standard.warnWithinMs,
        at nowMilliseconds: Double = AuthExpiryPolicyTests.now
    ) throws -> AuthExpiryRecord {
        let parsed = try JSONParser.parse(json)
        let stored = try #require(AuthRecord(parsed))
        return AuthExpiryRecord.derive(
            upstream: upstream, record: stored, indexError: indexError,
            warnWithinMs: warnWithinMs, nowMilliseconds: nowMilliseconds
        )
    }

    /// A record whose access token expires `seconds` after `authorizedAt`, itself `agoMs` back.
    private static func token(expiresIn seconds: Double?, authorizedAgoMs: Double?) -> String {
        var tokens = #""access_token":"a""#
        if let seconds { tokens += ",\"expires_in\":\(seconds)" }
        var members = "\"tokens\":{\(tokens)}"
        if let authorizedAgoMs {
            members += ",\"authorizedAt\":\"\(JSDate.iso8601(milliseconds: now - authorizedAgoMs))\""
        }
        return "{\(members)}"
    }

    // MARK: - The floors

    @Test("E1 — an out-of-range value is refused with its key, its value and its scope")
    func refusalCarriesTheWholeStory() throws {
        let raw = try JSONParser.parse(#"{"warnWithinMs": 500, "renotifyAfterMs": 30}"#)
        let resolved = AuthExpiryPolicy.readGlobal(raw)

        #expect(resolved.refusals.count == 2)
        let warn = try #require(resolved.refusals.first { $0.key == "warnWithinMs" })
        #expect(warn.value == 500)
        #expect(warn.scope == "global")
        #expect(warn.reason.contains("60000"))
        // Refused, not clamped: the policy keeps the default rather than inventing 60000, so the
        // number the router uses is one somebody actually wrote.
        #expect(resolved.policy.warnWithinMs == AuthExpiryPolicy.standard.warnWithinMs)
        #expect(resolved.policy.renotifyAfterMs == AuthExpiryPolicy.standard.renotifyAfterMs)
    }

    @Test("E2 — a warning window of zero is refused, because `expiring` would be unreachable")
    func zeroWarnWindowIsRefusedRatherThanAccepted() throws {
        let raw = try JSONParser.parse(#"{"warnWithinMs": 0}"#)
        let resolved = AuthExpiryPolicy.readGlobal(raw)

        #expect(resolved.refusals.count == 1)
        #expect(resolved.policy.warnWithinMs == AuthExpiryPolicy.standard.warnWithinMs)
        // The whole reason for the floor, stated as an assertion rather than as a comment: with
        // zero accepted, a token one millisecond from death reads `valid` and the promise "you are
        // told before it stops working" holds only because nothing can enter the state it names.
        let almostGone = try Self.record(
            Self.token(expiresIn: 3600, authorizedAgoMs: 3_599_999), warnWithinMs: 0
        )
        #expect(almostGone.state == .valid, "which is exactly why zero is not a value this takes")
        let underPolicy = try Self.record(
            Self.token(expiresIn: 3600, authorizedAgoMs: 3_599_999),
            warnWithinMs: resolved.policy.warnWithinMs
        )
        #expect(underPolicy.state == .expiring)
    }

    @Test("E3 — a value at the floor is taken, and one above it is taken")
    func inRangeValuesAreApplied() throws {
        let raw = try JSONParser.parse(#"{"warnWithinMs": 60000, "renotifyAfterMs": 120000}"#)
        let resolved = AuthExpiryPolicy.readGlobal(raw)

        #expect(resolved.refusals.isEmpty)
        #expect(resolved.policy.warnWithinMs == 60000)
        #expect(resolved.policy.renotifyAfterMs == 120_000)
    }

    @Test("E4 — a member that is not a number configures nothing rather than half-configuring")
    func nonNumericMembersAreAbsentRatherThanRefused() throws {
        let raw = try JSONParser.parse(#"{"warnWithinMs": "soon"}"#)
        let resolved = AuthExpiryPolicy.readGlobal(raw)

        // Absent, not refused: a string is not a number to refuse, and reporting it as one would
        // put a `"value":0` on the wire that the file does not contain.
        #expect(resolved.refusals.isEmpty)
        #expect(resolved.policy.warnWithinMs == AuthExpiryPolicy.standard.warnWithinMs)
        #expect(AuthExpiryPolicy.readGlobal(nil).refusals.isEmpty)
        #expect(AuthExpiryPolicy.readGlobal(.number(3)).policy == .standard)
    }

    // MARK: - The states

    @Test("E5 — a token with no declared lifetime is `unknown`, and never `valid`")
    func aMissingLifetimeIsUnknown() throws {
        let record = try Self.record(Self.token(expiresIn: nil, authorizedAgoMs: 1000))

        #expect(record.state == .unknown)
        #expect(record.unknownReason == .noLifetimeDeclared)
        #expect(record.expiresAtMs == nil)
        #expect(record.remainingMs == nil)
    }

    @Test("E6 — a lifetime with no readable stamp is `unknown` for the other reason")
    func anUnreadableStampIsItsOwnUnknown() throws {
        let missing = try Self.record(Self.token(expiresIn: 3600, authorizedAgoMs: nil))
        #expect(missing.state == .unknown)
        #expect(missing.unknownReason == .unreadableAuthorizedAt)

        let garbage = try Self.record(
            #"{"tokens":{"access_token":"a","expires_in":3600},"authorizedAt":"whenever"}"#
        )
        #expect(garbage.state == .unknown)
        #expect(garbage.unknownReason == .unreadableAuthorizedAt)
    }

    @Test("E7 — valid, expiring and expired are the three sides of one boundary")
    func theWindowDecidesTheState() throws {
        let day = 86_400_000.0
        // Two days of life, one hour used: a day and 23 hours left, outside a 24-hour window.
        let fresh = try Self.record(Self.token(expiresIn: 172_800, authorizedAgoMs: 3_600_000))
        #expect(fresh.state == .valid)

        // An hour of life, half used: inside the window.
        let soon = try Self.record(Self.token(expiresIn: 3600, authorizedAgoMs: 1_800_000))
        #expect(soon.state == .expiring)
        #expect(try #require(soon.remainingMs) == 1_800_000)

        let gone = try Self.record(Self.token(expiresIn: 3600, authorizedAgoMs: 7_200_000))
        #expect(gone.state == .expired)
        #expect(try #require(gone.remainingMs) < 0)

        // The boundary itself: exactly one window away is `expiring`, one millisecond more is not.
        let onTheLine = try Self.record(Self.token(expiresIn: 172_800, authorizedAgoMs: 172_800_000 - day))
        #expect(onTheLine.state == .expiring)
    }

    @Test("E8 — a server that cannot be authorised, and one that holds nothing, are not warnings")
    func theTwoQuietStates() throws {
        let stdio = try Self.record(
            Self.token(expiresIn: 3600, authorizedAgoMs: 7_200_000), upstream: stdioUpstream("s")
        )
        #expect(stdio.state == .notApplicable, "a stdio child has no credential to expire")

        var noOAuth = httpUpstream("h")
        noOAuth.oauth = false
        let refused = try Self.record(
            Self.token(expiresIn: 3600, authorizedAgoMs: 7_200_000), upstream: noOAuth
        )
        #expect(refused.state == .notApplicable)

        #expect(try Self.record("{}").state == .noCredential)
        // `!!rec.tokens?.access_token` coerces, so an empty token is not a token.
        #expect(try Self.record(#"{"tokens":{"access_token":""}}"#).state == .noCredential)
    }

    @Test("E9 — a recorded refusal is read off the manifest error and never provoked")
    func refusalComesFromWhatWasAlreadyObserved() throws {
        let clean = try Self.record(Self.token(expiresIn: 172_800, authorizedAgoMs: 0))
        #expect(clean.credentialRefused == false)

        let refused = try Self.record(
            Self.token(expiresIn: 172_800, authorizedAgoMs: 0),
            indexError: "[-32603] Internal error: Authentication required"
        )
        #expect(refused.credentialRefused)
        // Still `valid`: the token has not expired. The refusal is a separate fact and it is what
        // makes this the case the brief names first — a call that fails while the clock says fine.
        #expect(refused.state == .valid)

        let unrelated = try Self.record(
            Self.token(expiresIn: 172_800, authorizedAgoMs: 0), indexError: "ECONNREFUSED"
        )
        #expect(unrelated.credentialRefused == false)
    }
}
