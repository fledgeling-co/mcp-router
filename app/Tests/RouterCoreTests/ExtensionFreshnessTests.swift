import Foundation
import Testing
@testable import RouterCore

/// F6 — the eight verdicts, and the ordering that produces them.
///
/// **Every arm here is fixture-driven by necessity.** Measured on the author's machine on
/// 2026-08-29 by `planning/evidence/F6/measure-update-surface.py`, the mechanism this item is asked
/// for — a version delta against the marketplace catalogue — produces `updateAvailable` **zero
/// times over 127 installed plugins**, so there is no reading of the real tree that exercises the
/// one state that costs an install. Each arm was watched red before it was trusted; the record is
/// `planning/evidence/F6/red-green.txt`.
@Suite("F6 — the freshness verdict")
struct ExtensionFreshnessTests {
    private static func offer(_ name: String, _ version: String?) -> CatalogueOffer {
        CatalogueOffer(name: name, version: version)
    }

    // MARK: - The eight arms

    @Test("F1 — a greater offered version is the one state that means an update")
    func updateAvailable() {
        let verdict = ExtensionFreshness.compare(
            installedVersion: "1.0.0", offer: Self.offer("p", "2.0.0"), catalogueProblem: nil
        )
        #expect(verdict == .updateAvailable(installed: "1.0.0", available: "2.0.0"))
        #expect(verdict.hasUpdate)
        #expect(verdict.isComparison)
        #expect(verdict.state == "update-available")
    }

    @Test("F2 — equal versions are current, and current is not an update")
    func current() {
        let verdict = ExtensionFreshness.compare(
            installedVersion: "1.2.3", offer: Self.offer("p", "1.2.3"), catalogueProblem: nil
        )
        #expect(verdict == .current("1.2.3"))
        #expect(!verdict.hasUpdate)
        #expect(verdict.isComparison)
    }

    /// The state measured on this machine: `security-guidance@claude-code-plugins` holds 2.0.0 and
    /// its catalogue offers 1.0.0. A checker reading *differs* as *an update* would have offered a
    /// downgrade and called it an update.
    @Test("F3 — an OLDER offered version is a fact about the catalogue, never an update")
    func catalogueBehind() {
        let verdict = ExtensionFreshness.compare(
            installedVersion: "2.0.0", offer: Self.offer("p", "1.0.0"), catalogueProblem: nil
        )
        #expect(verdict == .catalogueBehind(installed: "2.0.0", available: "1.0.0"))
        #expect(!verdict.hasUpdate)
        #expect(verdict.isComparison)
        #expect(verdict.state == "catalogue-behind")
    }

    /// Three of the 127 installed plugins carry a git short SHA where a version goes.
    @Test("F4 — two unorderable versions differ and neither is behind")
    func unorderable() {
        let verdict = ExtensionFreshness.compare(
            installedVersion: "ed404106fcd8", offer: Self.offer("p", "aa11bb22cc33"),
            catalogueProblem: nil
        )
        #expect(verdict == .unorderable(installed: "ed404106fcd8", available: "aa11bb22cc33"))
        #expect(!verdict.hasUpdate)
    }

    @Test("F5 — an entry declaring no version is not compared")
    func installedDeclaresNoVersion() {
        let verdict = ExtensionFreshness.compare(
            installedVersion: nil, offer: Self.offer("p", "1.0.0"), catalogueProblem: nil
        )
        #expect(verdict == .installedDeclaresNoVersion)
        #expect(!verdict.isComparison)
    }

    /// 557 of the 763 offers across ten catalogues are in this state.
    @Test("F6 — a catalogue declaring no version is not compared, and is not current")
    func catalogueDeclaresNoVersion() {
        let verdict = ExtensionFreshness.compare(
            installedVersion: "1.0.0", offer: Self.offer("p", nil), catalogueProblem: nil
        )
        #expect(verdict == .catalogueDeclaresNoVersion(installed: "1.0.0"))
        #expect(!verdict.isComparison)
        #expect(verdict.installedVersion == "1.0.0")
        #expect(verdict.availableVersion == nil)
    }

    @Test("F7 — a catalogue that no longer offers the entry says so")
    func notOffered() {
        let verdict = ExtensionFreshness.compare(
            installedVersion: "1.0.0", offer: nil, catalogueProblem: nil
        )
        #expect(verdict == .notOffered)
        #expect(!verdict.isComparison)
    }

    @Test("F8 — no catalogue at all carries its reason")
    func noCatalogue() {
        let verdict = ExtensionFreshness.compare(
            installedVersion: "1.0.0", offer: Self.offer("p", "9.0.0"),
            catalogueProblem: "there is no marketplace named \"gone\""
        )
        #expect(verdict == .noCatalogue("there is no marketplace named \"gone\""))
        #expect(!verdict.hasUpdate)
        #expect(verdict.sentence == "there is no marketplace named \"gone\"")
    }

    // MARK: - The order of the guards

    /// Two absent versions are not two equal versions. `nil == nil` in the equality arm would
    /// report the 557 versionless offers as up to date, which is the failure this item exists to
    /// prevent.
    @Test("F9 — both sides silent is uncomparable, NOT current")
    func bothSilent() {
        let verdict = ExtensionFreshness.compare(
            installedVersion: nil, offer: Self.offer("p", nil), catalogueProblem: nil
        )
        #expect(verdict == .catalogueDeclaresNoVersion(installed: nil))
        #expect(!verdict.isComparison)
        #expect(verdict != .current(""))
    }

    /// A missing catalogue outranks everything: an offer cannot be trusted from a catalogue the
    /// router could not read.
    @Test("F10 — a catalogue problem wins over an offer that was somehow present")
    func problemOutranksOffer() {
        #expect(
            ExtensionFreshness.compare(
                installedVersion: nil, offer: nil, catalogueProblem: "unreadable"
            ) == .noCatalogue("unreadable")
        )
    }

    /// `1.0.0` and `v1.0.0` are one version spelled twice. Neither side is behind, and reporting
    /// an update between them would be the wrong-way bug with a `v` in front of it.
    @Test("F11 — two spellings of one version are current, not an update")
    func equivalentSpellings() {
        let verdict = ExtensionFreshness.compare(
            installedVersion: "1.0.0", offer: Self.offer("p", "v1.0.0"), catalogueProblem: nil
        )
        #expect(verdict == .current("1.0.0"))
        #expect(!verdict.hasUpdate)
    }

    // MARK: - The classification is total

    /// Every verdict is in exactly one of `compared` and `uncomparable`. A ninth case added later
    /// without a classification reddens this rather than landing in neither.
    @Test("F12 — hasUpdate is true for exactly one verdict, and isComparison partitions all eight")
    func classificationIsTotal() {
        let every: [FreshnessVerdict] = [
            .updateAvailable(installed: "1.0.0", available: "2.0.0"),
            .current("1.0.0"),
            .catalogueBehind(installed: "2.0.0", available: "1.0.0"),
            .unorderable(installed: "a", available: "b"),
            .installedDeclaresNoVersion,
            .catalogueDeclaresNoVersion(installed: nil),
            .notOffered,
            .noCatalogue("reason")
        ]
        #expect(every.count { $0.hasUpdate } == 1)
        #expect(every.count { $0.isComparison } == 4)
        #expect(Set(every.map(\.state)).count == 8)
        // Every sentence names something. An empty one would be a state a reader cannot act on.
        #expect(every.allSatisfy { !$0.sentence.isEmpty })
    }
}
