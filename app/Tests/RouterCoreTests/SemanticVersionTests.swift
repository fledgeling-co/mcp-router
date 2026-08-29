import Foundation
import Testing
@testable import RouterCore

/// F6 — ordering two version strings, or declining to.
///
/// This is the only place an `updateAvailable` verdict can come from, so it is where the wrong-way
/// bug has to be impossible. Every arm that asserts an order asserts it in **both** argument
/// orders: an implementation that returned a constant would satisfy half of these and is exactly
/// the shape of unfailable oracle this fleet keeps finding.
@Suite("F6 — version ordering")
struct SemanticVersionTests {
    @Test("S1 — a plain semver parses to its three components")
    func parses() {
        let parsed = SemanticVersion.parse("1.2.3")
        #expect(parsed?.major == 1)
        #expect(parsed?.minor == 2)
        #expect(parsed?.patch == 3)
        #expect(parsed?.suffix.isEmpty == true)
        #expect(SemanticVersion.parse("v0.45.1")?.minor == 45)
    }

    @Test(
        "S2 — a git short SHA is not a version, in either alphabet",
        arguments: ["ed404106fcd8", "aa11bb22cc33", "6db48033d218", "abcdef0"]
    )
    func shaIsNotAVersion(text: String) {
        #expect(SemanticVersion.parse(text) == nil)
    }

    /// Two SHAs have no order. A string comparison would order them by hexadecimal accident and
    /// report an update that does not exist — the three plugins on this machine carrying
    /// `ed404106fcd8` are the population this protects.
    @Test("S3 — two unparseable strings compare to nil, both ways round")
    func unorderablePairs() {
        #expect(SemanticVersion.compare("ed404106fcd8", "aa11bb22cc33") == nil)
        #expect(SemanticVersion.compare("aa11bb22cc33", "ed404106fcd8") == nil)
        #expect(SemanticVersion.compare("1.0.0", "ed404106fcd8") == nil)
        #expect(SemanticVersion.compare("ed404106fcd8", "1.0.0") == nil)
    }

    @Test("S4 — ordering is antisymmetric across every component")
    func ordering() {
        let pairs = [("1.0.0", "2.0.0"), ("1.0.0", "1.1.0"), ("1.0.0", "1.0.1"), ("1.9.0", "1.10.0")]
        for (lower, higher) in pairs {
            #expect(SemanticVersion.compare(lower, higher) == .orderedAscending)
            #expect(SemanticVersion.compare(higher, lower) == .orderedDescending)
            #expect(SemanticVersion.compare(lower, lower) == .orderedSame)
        }
    }

    /// `1.9.0` against `1.10.0` is the case a lexical comparison gets backwards, and it is the one
    /// that would have produced a *downgrade offered as an update*.
    @Test("S5 — a lexical comparison would invert 1.9.0 against 1.10.0, and this does not")
    func numericNotLexical() {
        #expect("1.9.0" > "1.10.0")
        #expect(SemanticVersion.compare("1.9.0", "1.10.0") == .orderedAscending)
    }

    @Test("S6 — a release outranks a pre-release of the same numbers")
    func prerelease() {
        #expect(SemanticVersion.compare("1.0.0-beta.1", "1.0.0") == .orderedAscending)
        #expect(SemanticVersion.compare("1.0.0", "1.0.0-beta.1") == .orderedDescending)
    }

    /// A two-part version is refused rather than padded. Padding is the shape of guess this type
    /// exists to decline, and `1.2` padded to `1.2.0` would report an update against `1.2.1` that
    /// the publisher never made.
    @Test(
        "S7 — what is refused",
        arguments: ["1.2", "1", "", "   ", "1.2.3.4.5", "1.2.x", "1.2.3rc1", "v", "-1.0.0", "1234567890.0.0"]
    )
    func refused(text: String) {
        #expect(SemanticVersion.parse(text) == nil)
    }

    @Test("S8 — a four-part version keeps its tail as a suffix only behind a separator")
    func suffixes() {
        #expect(SemanticVersion.parse("1.2.3+build7")?.suffix == "+build7")
        #expect(SemanticVersion.parse("1.2.3-rc.1")?.suffix == "-rc.1")
    }
}
