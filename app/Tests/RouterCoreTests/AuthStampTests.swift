import Foundation
import Testing
@testable import RouterCore

/// Ordering the two stamps that decide whether a recorded refusal is stale.
///
/// The rule this supports: a refusal the manifest recorded before the credential was last
/// authorized must not be reported, because it tells the user the credential they have just fixed
/// is still being refused. Measured 20 Aug 2026 — the oauth parity lane run inside the full gate
/// had the reference at `authorized: true` and the Swift router at `authorized: false` with an
/// `authorizedAt` newer than the error beside it; the same lane on its own had both at `true` over
/// 21 checks. Whichever side loses that race is a property of the machine that day, which is why
/// the field must not be decided by it.
@Suite("Ordering the stamps a stale refusal is judged by")
struct AuthStampTests {
    @Test("a later stamp is after an earlier one")
    func laterIsAfter() {
        #expect(AuthStamp.isAfter("2026-08-20T15:00:13.233Z", "2026-08-20T13:59:05.511Z"))
        #expect(!AuthStamp.isAfter("2026-08-20T13:59:05.511Z", "2026-08-20T15:00:13.233Z"))
    }

    /// Strictly after, not at-or-after. Two stamps in the same millisecond say nothing about which
    /// event came first, and the tie has to resolve toward reporting the refusal — the direction
    /// where being wrong costs a re-authorization rather than a silently toolless upstream.
    @Test("an identical stamp is not after itself, so a tie reports the refusal")
    func equalIsNotAfter() {
        #expect(!AuthStamp.isAfter("2026-08-20T15:00:13.233Z", "2026-08-20T15:00:13.233Z"))
    }

    /// The reference does this with `Date.parse`, which yields NaN on anything it cannot read, and
    /// every comparison against NaN is false. This has to answer the same way in the same cases,
    /// on either side of the comparison, or the two routers disagree on a garbled manifest.
    @Test("an unreadable stamp is not after anything, on either side")
    func unparseableIsNotAfter() {
        let good = "2026-08-20T15:00:13.233Z"
        #expect(!AuthStamp.isAfter("not a date", good))
        #expect(!AuthStamp.isAfter(good, "not a date"))
        #expect(!AuthStamp.isAfter("", good))
        #expect(!AuthStamp.isAfter(good, ""))
        #expect(!AuthStamp.isAfter("2026-08-20", good))
    }

    /// A stamp without fractional seconds is one somebody may have hand-written into a manifest.
    /// `withInternetDateTime` alone rejects the millisecond form this router writes, so both
    /// parses have to exist; this is the half that would go silently missing if only the precise
    /// one were tried, and it would fail closed — reporting every refusal as current.
    @Test("a stamp with no milliseconds still orders")
    func secondsPrecisionParses() {
        #expect(AuthStamp.isAfter("2026-08-20T15:00:13Z", "2026-08-20T13:59:05.511Z"))
        #expect(AuthStamp.isAfter("2026-08-20T15:00:13.233Z", "2026-08-20T13:59:05Z"))
    }
}
