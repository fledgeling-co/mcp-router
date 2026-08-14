import Foundation
import Testing
@testable import MCPRouterKit

/// The second half of the same subject, split only because neither one struct nor one file may
/// exceed the linter's limits. The fixtures are reached through the first suite rather than
/// duplicated, because two copies of a fixture drift and then two tests disagree about what a
/// skill looks like.
@Suite("Skill presentation — states and marketplaces")
struct SkillPresentationStateTests {
    // MARK: - Partial

    @Test("The partial note names the client, the consequence, the path and the reason")
    func partialNoteIsComplete() throws {
        var clients = SkillPresentationTests.testClients
        clients[2] = SkillClient(
            id: "cursor", displayName: "Cursor", supportsSkills: true,
            root: "/home/.cursor/skills", status: .unreadable, reason: "permission denied"
        )
        let note = SkillPresentation.partialNote(for: SkillsResponse(skills: [], clients: clients))
        let text = try #require(note)
        #expect(text.contains("Cursor"))
        #expect(text.contains("understates"))
        #expect(text.contains("/home/.cursor/skills"))
        #expect(text.contains("permission denied"))
    }

    @Test("A board with every client read has no partial note")
    func noPartialNoteWhenAllRead() {
        #expect(SkillPresentation.partialNote(for: SkillsResponse(
            skills: [],
            clients: SkillPresentationTests.testClients
        )) == nil)
    }

    // MARK: - Marketplaces

    @Test("A marketplace supplying nothing says so, and is not an error")
    func suppliesNothing() {
        let marketplace = Marketplace(
            name: "atlas-plugins", source: .directory(path: "/Dev/atlas"),
            installedPluginCount: 0, suppliedSkillCount: 0
        )
        #expect(SkillPresentation.supplyLine(for: marketplace) == "Supplies nothing")
        // A local directory has nothing to fetch, so its auto-update reason is about that rather
        // than about this build being read-only.
        #expect(SkillPresentation.autoUpdateLine(for: marketplace) == "Local directory")
        #expect(SkillPresentation.autoUpdateReason(for: marketplace).contains("nothing to fetch"))
    }

    @Test("Removing a marketplace that supplies skills is refused with the count in its reason")
    func removeReasonCarriesTheCount() {
        let marketplace = Marketplace(
            name: "fledgeling-plugins", source: .github(repo: "fledgeling-co/fledgeling-plugins"),
            installedPluginCount: 24, suppliedSkillCount: 22
        )
        let reason = SkillPresentation.removeReason(for: marketplace)
        #expect(reason.contains("22"))
        #expect(reason.contains("Remove them first"))
    }

    @Test("Auto-update reads off the record, and an absent flag is off")
    func autoUpdateReadsTheRecord() {
        let on = Marketplace(name: "a", source: .github(repo: "x/y"), autoUpdate: true)
        let off = Marketplace(name: "b", source: .github(repo: "x/z"), autoUpdate: false)
        #expect(SkillPresentation.autoUpdateLine(for: on) == "Auto-update on")
        #expect(SkillPresentation.autoUpdateLine(for: off) == "Auto-update off")
    }

    @Test("A missing marketplace record is said out loud, never drawn as a switch in the off position")
    func autoUpdateWithoutARecordSaysSo() {
        // Inspector item 7 reads a setting that lives on the marketplace. When the marketplace list
        // did not load there is no record to read, and "off" would be the board asserting a setting
        // nobody observed — the one thing DESIGN.md forbids everywhere else on this board.
        let unread = SkillPresentation.autoUpdateUnread
        #expect(unread.contains("didn't load"))
        #expect(!unread.lowercased().contains("auto-update off"))
        // It must not be mistakable for either real state.
        let off = Marketplace(name: "b", source: .github(repo: "x/z"), autoUpdate: false)
        #expect(unread != SkillPresentation.autoUpdateLine(for: off))
    }

    // MARK: - The held-version sheet

    @Test("The held sheet's title states the finding and names both versions")
    func heldTitleStatesTheFinding() {
        let skill = SkillPresentationTests.testPluginSkill(
            plugin: "trawl", version: "2.2.0",
            held: HeldVersion(pluginVersion: "2.3.0", addedCapabilities: ["runs x.sh"])
        )
        #expect(SkillPresentation.heldTitle(skill) == "trawl 2.3.0 wants more than 2.2.0")
    }

    @Test("The held sheet says how many skills a promotion would move when a plugin has siblings")
    func heldBodyNamesTheBlastRadius() {
        let skill = SkillPresentationTests.testPluginSkill(
            plugin: "vercel", siblings: 30,
            held: HeldVersion(
                pluginVersion: "0.46.0",
                addedCapabilities: ["runs x.sh"],
                affectedSkillCount: 30
            )
        )
        #expect(SkillPresentation.heldBody(skill).contains("all 30 skills"))
    }

    @Test("A single-skill plugin's held sheet does not talk about siblings")
    func heldBodyOmitsBlastRadiusForOne() {
        let skill = SkillPresentationTests.testPluginSkill(
            held: HeldVersion(pluginVersion: "2.3.0", addedCapabilities: ["runs x.sh"], affectedSkillCount: 1)
        )
        #expect(!SkillPresentation.heldBody(skill).contains("all 1"))
    }

    // MARK: - The rule the whole board exists to honour

    @Test("No presentation string offers a run count, a last run, or an evaluation")
    func nothingClaimsAnUnobservedFigure() {
        // The footer is the ONE place any of the three is mentioned, and it is mentioned as an
        // absence. Everything else on this board must be silent about them.
        let strings = [
            SkillPresentation.emptyTitle,
            SkillPresentation.emptyDetail,
            SkillPresentation.writesNotYetAvailable,
            SkillPresentation.capabilityDerivation,
            SkillPresentation.sourceLine(for: SkillPresentationTests.testPluginSkill()),
            SkillPresentation.version(for: SkillPresentationTests.testPluginSkill()).text,
            SkillPresentation.version(for: SkillPresentationTests.testStandaloneSkill()).text
        ]
        for text in strings {
            #expect(!text.lowercased().contains("last run"))
            #expect(!text.lowercased().contains("evaluation"))
            #expect(!text.lowercased().contains("times run"))
        }
        // And the footer states the absence rather than hiding it.
        #expect(SkillPresentation.observationFooter.contains("not shown"))
        #expect(SkillPresentation.observationFooter.contains("never reaches the router"))
    }

    // MARK: - Emptiness caused by the search rather than the filter

    @Test("A search matching nothing gets its own message under EVERY filter, including All")
    func searchEmptinessIsAlwaysExplained() {
        // The defect this guards: keying on the filter alone left `All` + a non-matching search
        // with no message at all, so the board drew column headers over blank space. That is the
        // most common way this board empties.
        for filter in SkillPresentation.Filter.allCases {
            let message = SkillPresentation.emptyInFilter(filter, search: "zzz")
            #expect(message != nil, "\(filter.title) with a non-matching search had no message")
            #expect(message?.title.contains("zzz") == true)
            // The action matches the cause: a search cleared, not a filter widened.
            #expect(message?.action == "Clear search")
            #expect(message?.clearsSearch == true)
        }
    }

    @Test("A whitespace-only search is not treated as a search")
    func blankSearchIsNotASearch() {
        #expect(SkillPresentation.emptyInFilter(.all, search: "   ") == nil)
        #expect(SkillPresentation.emptyInFilter(.held, search: "   ")?.action == "Show all skills")
    }

    @Test("Every empty message's button does what its own label says")
    func actionMatchesItsLabel() {
        // The defect: the view decided which action to take from `search.isEmpty`, untrimmed, while
        // the label came from the trimmed search. A search of "   " under a narrow filter therefore
        // offered "Show all skills" and then cleared the whitespace, leaving the filter narrow and
        // the list still empty — a button that appeared to do nothing. The two now read one flag.
        for filter in SkillPresentation.Filter.allCases {
            for search in ["", "   ", "\t\n", "zzz"] {
                guard let message = SkillPresentation.emptyInFilter(filter, search: search) else {
                    continue
                }
                #expect(
                    message.clearsSearch == (message.action == "Clear search"),
                    "\(filter.title)/\(search.debugDescription): label and action disagree"
                )
            }
        }
        // Specifically: whitespace offers the filter action, and takes it.
        let blank = SkillPresentation.emptyInFilter(.held, search: "   ")
        #expect(blank?.clearsSearch == false)
    }

    @Test("Filter counts follow the search, so a badge never contradicts the list beneath it")
    func countsFollowTheSearch() {
        let held = SkillPresentationTests.testPluginSkill(
            name: "trawl",
            held: HeldVersion(pluginVersion: "2.3.0", addedCapabilities: ["runs x.sh"])
        )
        let skills = [held, SkillPresentationTests.testPluginSkill(name: "design-craft")]

        #expect(SkillPresentation.count(skills, filter: .held, search: "") == 1)
        // With a search that excludes the held skill, the badge must go rather than read 1 over an
        // empty list — which was two claims on one screen, one of them false.
        #expect(SkillPresentation.count(skills, filter: .held, search: "design") == nil)
        #expect(SkillPresentation.count(skills, filter: .all, search: "design") == 1)
    }

    @Test("A plugin count of zero is not rendered as 'from 0 plugins'")
    func supplyLineGuardsTheDenominator() {
        let odd = Marketplace(
            name: "m", source: .github(repo: "a/b"),
            installedPluginCount: 0, suppliedSkillCount: 22
        )
        let line = SkillPresentation.supplyLine(for: odd)
        #expect(line == "22 skills")
        #expect(!line.contains("0 plugins"))
    }

    @Test("The held body does not promise an action the sheet cannot perform")
    func heldBodyDoesNotPromisePromotion() {
        let skill = SkillPresentationTests.testPluginSkill(
            version: "2.2.0",
            held: HeldVersion(pluginVersion: "2.3.0", addedCapabilities: ["runs x.sh"])
        )
        let body = SkillPresentation.heldBody(skill)
        // "until you promote it" sat ten lines above a permanently dimmed Promote button.
        #expect(!body.contains("until you promote"))
        #expect(body.contains("still running 2.2.0"))
    }

    @Test("The capability sentence attributes the reading to the router, not to this app")
    func capabilitySentenceAttributesCorrectly() {
        // Nothing in the app performs this analysis; the router reports it. Saying otherwise
        // describes work no code here does.
        #expect(SkillPresentation.capabilityDerivation.contains("As reported by the router"))
        #expect(SkillPresentation.capabilityDerivation.contains("can be incomplete"))
    }
}
