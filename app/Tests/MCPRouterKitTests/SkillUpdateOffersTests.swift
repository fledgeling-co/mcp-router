import Foundation
import Testing
@testable import MCPRouterKit

/// The update section's offers, merged from the register's held versions and the router's stored offers.
/// The rules the board draws from are checked here without a host, against the fixtures the Skills board
/// suite uses.
@Suite("Skill update offers")
struct SkillUpdateOffersTests {
    static func storedOffer(
        name: String,
        hasUpdate: Bool = true,
        changelog: ExtensionChangelog? = nil
    ) -> ExtensionUpdateEntry {
        ExtensionUpdateEntry(
            kind: .plugins,
            name: name,
            state: hasUpdate ? "update-available" : "current",
            installed: "1.0.0",
            available: hasUpdate ? "1.1.0" : "1.0.0",
            hasUpdate: hasUpdate,
            reason: hasUpdate
                ? "1.1.0 is offered and 1.0.0 is installed"
                : "1.0.0 is installed and is what the catalogue offers",
            changelog: changelog
        )
    }

    @Test("A held version is offered from Claude's register, with the changelog the held version carries")
    func heldVersionIsOffered() throws {
        let changelog = ExtensionChangelog(
            text: "## 2.3.0\n", note: "CHANGELOG.md from the cached 2.3.0 copy"
        )
        let held = HeldVersion(pluginVersion: "2.3.0", addedCapabilities: ["network"], changelog: changelog)

        let offers = SkillPresentation.updateOffers(
            skills: [SkillPresentationTests.testPluginSkill(held: held)],
            stored: []
        )

        #expect(offers.count == 1)
        let offer = try #require(offers.first)
        #expect(offer.kind == .plugins)
        #expect(offer.name == "trawl@fledgeling-plugins")
        #expect(offer.installed == "2.2.0")
        #expect(offer.available == "2.3.0")
        #expect(offer.hasUpdate)
        #expect(offer.reason == "2.3.0 is offered and 2.2.0 is installed")
        #expect(offer.changelog == changelog)
    }

    @Test("Every skill of one plugin shares the plugin's held version, so the plugin is offered once")
    func siblingsOfferOnce() {
        let held = HeldVersion(pluginVersion: "2.3.0", addedCapabilities: ["network"], affectedSkillCount: 2)
        let skills = [
            SkillPresentationTests.testPluginSkill(name: "alpha", siblings: 2, held: held),
            SkillPresentationTests.testPluginSkill(name: "beta", siblings: 2, held: held)
        ]

        #expect(SkillPresentation.updateOffers(skills: skills, stored: []).count == 1)
    }

    @Test("A plugin the register and the store both offer is listed once, with the register's changelog")
    func registerWinsOverStore() {
        let held = HeldVersion(
            pluginVersion: "2.3.0",
            addedCapabilities: ["network"],
            changelog: ExtensionChangelog(text: "from the register", note: "register")
        )
        let stored = [
            Self.storedOffer(
                name: "trawl@fledgeling-plugins",
                changelog: ExtensionChangelog(text: "from the store", note: "store")
            ),
            Self.storedOffer(name: "other@market")
        ]

        let offers = SkillPresentation.updateOffers(
            skills: [SkillPresentationTests.testPluginSkill(held: held)],
            stored: stored
        )

        #expect(offers.map(\.name) == ["trawl@fledgeling-plugins", "other@market"])
        #expect(offers.first?.changelog?.text == "from the register")
    }

    @Test("A stored offer the register does not hold is still listed, so the store's offers are not dropped")
    func storeOnlyOfferIsListed() {
        let stored = [Self.storedOffer(name: "stored@market")]

        #expect(SkillPresentation.updateOffers(skills: [], stored: stored).map(\.name) == ["stored@market"])
    }

    @Test("A stored entry the check found current is not an offer")
    func currentStoredEntryIsNotOffered() {
        let stored = [Self.storedOffer(name: "current@market", hasUpdate: false)]

        #expect(SkillPresentation.updateOffers(skills: [], stored: stored).isEmpty)
    }

    @Test("A skill with no held version offers nothing")
    func unheldSkillOffersNothing() {
        let skills = [
            SkillPresentationTests.testPluginSkill(),
            SkillPresentationTests.testStandaloneSkill()
        ]

        #expect(SkillPresentation.updateOffers(skills: skills, stored: []).isEmpty)
    }

    @Test("A held version from a router that sends no changelog is still offered, with no changelog")
    func heldWithoutChangelogIsOffered() throws {
        let held = HeldVersion(pluginVersion: "2.3.0", addedCapabilities: ["network"])
        let skills = [SkillPresentationTests.testPluginSkill(held: held)]

        let offer = try #require(SkillPresentation.updateOffers(skills: skills, stored: []).first)

        #expect(offer.name == "trawl@fledgeling-plugins")
        #expect(offer.changelog == nil)
    }
}
