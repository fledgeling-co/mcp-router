import Foundation
import Testing
@testable import MCPRouterKit

/// The Skills board's decisions, checked without a host.
///
/// These are the rules the board would otherwise only express as pixels. Each one below is a claim
/// the spec makes, and several of them guard a defect that was actually made and caught: the wrong
/// entity for a version, a symlinked skill counted four times, an unreadable directory rendered as
/// an absence.
@Suite("Skill presentation")
struct SkillPresentationTests {
    // MARK: - Fixtures

    static func testPluginSkill(
        name: String = "trawl",
        plugin: String = "trawl",
        marketplace: String = "fledgeling-plugins",
        version: String = "2.2.0",
        siblings: Int = 1,
        presence: [String: SkillPresence] = [:],
        held: HeldVersion? = nil,
        provenance: SkillProvenance? = nil
    ) -> Skill {
        Skill(
            name: name,
            path: "/cache/\(marketplace)/\(plugin)/\(version)/skills/\(name)",
            source: .plugin(PluginOrigin(
                plugin: plugin, marketplace: marketplace, pluginVersion: version,
                siblingSkillCount: siblings
            )),
            presence: presence,
            held: held,
            provenance: provenance
        )
    }

    static func testStandaloneSkill(name: String = "graphify") -> Skill {
        Skill(
            name: name,
            path: "/home/.agents/skills/\(name)",
            source: .standalone(path: "/home/.agents/skills/\(name)")
        )
    }

    static let testClients: [SkillClient] = [
        SkillClient(id: "claudeCode", displayName: "Claude Code", supportsSkills: true, status: .read),
        SkillClient(id: "codex", displayName: "Codex", supportsSkills: true, status: .read),
        SkillClient(id: "cursor", displayName: "Cursor", supportsSkills: true, status: .read),
        SkillClient(id: "opencode", displayName: "opencode", supportsSkills: true, status: .read),
        SkillClient(
            id: "claudeDesktop",
            displayName: "Claude Desktop",
            supportsSkills: false,
            status: .unsupported
        ),
        SkillClient(id: "chatGPT", displayName: "ChatGPT", supportsSkills: false, status: .unsupported)
    ]

    // MARK: - The version cell

    @Test("A standalone skill reads 'unversioned', and not in the instrument face")
    func standaloneHasNoVersion() {
        let cell = SkillPresentation.version(for: Self.testStandaloneSkill())
        #expect(cell.text == "unversioned")
        // The face is the assertion that matters: monospace is reserved for readings off a file,
        // and this is the app stating there was nothing to read.
        #expect(cell.isInstrument == false)
        #expect(cell.isHeld == false)
    }

    @Test("A plugin skill shows its plugin's version, in the instrument face")
    func pluginVersionIsInstrument() {
        let cell = SkillPresentation.version(for: Self.testPluginSkill(version: "1.14.0"))
        #expect(cell.text == "1.14.0")
        #expect(cell.isInstrument)
    }

    @Test("A held version that wants more shows the arrow and is marked held")
    func heldVersionShowsArrow() {
        let held = HeldVersion(pluginVersion: "2.3.0", addedCapabilities: ["runs scripts/collect.sh"])
        let cell = SkillPresentation.version(for: Self.testPluginSkill(held: held))
        #expect(cell.text == "2.2.0 → 2.3.0")
        #expect(cell.isHeld)
    }

    @Test("A held version wanting nothing more is not held for review")
    func emptyDeltaIsNotHeld() {
        // The brief's rule: a version promotes on its own when its capability surface is unchanged.
        let held = HeldVersion(pluginVersion: "2.3.0", addedCapabilities: [])
        #expect(held.wantsMore == false)
        let cell = SkillPresentation.version(for: Self.testPluginSkill(held: held))
        #expect(cell.isHeld == false)
        #expect(cell.text == "2.2.0")
    }

    // MARK: - The source line

    @Test("A plugin supplying several skills names the plugin, so a shared version is explained")
    func multiSkillPluginNamesThePlugin() {
        let line = SkillPresentation.sourceLine(
            for: Self.testPluginSkill(
                name: "ai-gateway",
                plugin: "vercel",
                marketplace: "official",
                siblings: 30
            )
        )
        #expect(line == "vercel · official")
    }

    @Test("A plugin supplying one skill names only the marketplace")
    func singleSkillPluginNamesMarketplace() {
        #expect(SkillPresentation.sourceLine(for: Self.testPluginSkill(siblings: 1)) == "fledgeling-plugins")
    }

    @Test("A standalone skill says it is local rather than naming a marketplace")
    func standaloneSaysLocal() {
        #expect(SkillPresentation
            .sourceLine(for: Self.testStandaloneSkill()) == "local — not from a marketplace")
    }

    // MARK: - Slots

    @Test("An unreadable client renders unknown, never off")
    func unreadableIsNotAbsent() throws {
        // The defect this guards: a boolean presence would collapse "not installed there" and "we
        // could not look", and the board would assert an absence nobody checked.
        let skill = Self.testPluginSkill(presence: [
            "cursor": .unreadable,
            "codex": .absent,
            "claudeCode": .present
        ])
        let cursor = try #require(Self.testClients.first { $0.id == "cursor" })
        let codex = try #require(Self.testClients.first { $0.id == "codex" })
        let claude = try #require(Self.testClients.first { $0.id == "claudeCode" })
        #expect(SkillPresentation.slot(skill, client: cursor) == .unknown)
        #expect(SkillPresentation.slot(skill, client: codex) == .off)
        #expect(SkillPresentation.slot(skill, client: claude) == .on)
    }

    @Test("Only clients with a skills mechanism get a slot")
    func unsupportedClientsGetNoSlot() {
        let response = SkillsResponse(skills: [], clients: Self.testClients)
        #expect(response.slotClients.count == 4)
        #expect(response.unsupportedClients.map(\.id).sorted() == ["chatGPT", "claudeDesktop"])
    }

    // MARK: - The inspector's client sentences

    @Test("All six clients are accounted for, including the two with no mechanism")
    func inspectorNamesEveryClient() {
        let skill = Self.testPluginSkill(presence: [
            "claudeCode": .present, "codex": .present, "cursor": .absent, "opencode": .absent
        ])
        let lines = SkillPresentation.clientSentences(
            for: skill,
            in: SkillsResponse(skills: [skill], clients: Self.testClients)
        )
        #expect(lines.contains { $0.contains("Claude Code") && $0.contains("Codex") })
        #expect(lines.contains { $0.hasPrefix("Not in") && $0.contains("Cursor") && $0.contains("opencode") })
        // The sentence that explains why the table has four slots and not six.
        #expect(lines.contains { $0.contains("no skills mechanism") && $0.contains("Claude Desktop") })
    }

    @Test("An unreadable client is reported as unknown in the inspector too")
    func inspectorReportsUnknown() {
        var clients = Self.testClients
        clients[2] = SkillClient(
            id: "cursor", displayName: "Cursor", supportsSkills: true,
            root: "/home/.cursor/skills", status: .unreadable, reason: "permission denied"
        )
        let skill = Self.testPluginSkill(presence: ["cursor": .unreadable])
        let lines = SkillPresentation.clientSentences(
            for: skill,
            in: SkillsResponse(skills: [skill], clients: clients)
        )
        #expect(lines.contains { $0.contains("Cursor") && $0.contains("unknown") })
    }

    // MARK: - Header and counts

    @Test("The subtitle omits the held clause entirely at zero")
    func subtitleOmitsZeroHeld() {
        let response = SkillsResponse(skills: [Self.testPluginSkill()], clients: Self.testClients)
        let subtitle = SkillPresentation.subtitle(for: response)
        #expect(subtitle.contains("1 skill"))
        #expect(subtitle.contains("1 marketplace"))
        // "0 held for review" reads as a warning that resolved rather than one that never applied.
        #expect(!subtitle.contains("held"))
    }

    @Test("The subtitle counts a held skill when there is one")
    func subtitleCountsHeld() {
        let held = HeldVersion(pluginVersion: "2.3.0", addedCapabilities: ["runs x.sh"])
        let response = SkillsResponse(skills: [Self.testPluginSkill(held: held)], clients: Self.testClients)
        #expect(SkillPresentation.subtitle(for: response).contains("1 held for review"))
    }

    @Test("A zero filter count carries no badge")
    func zeroCountIsNil() {
        let skills = [Self.testPluginSkill()]
        #expect(SkillPresentation.count(skills, filter: .all) == 1)
        #expect(SkillPresentation.count(skills, filter: .held) == nil)
        #expect(SkillPresentation.count(skills, filter: .local) == nil)
    }

    // MARK: - Filters

    @Test("Each filter selects what it names")
    func filtersSelectCorrectly() {
        let held = Self.testPluginSkill(
            name: "trawl",
            held: HeldVersion(pluginVersion: "2.3.0", addedCapabilities: ["runs x.sh"])
        )
        let moved = Self.testPluginSkill(
            name: "changelog-writer",
            provenance: SkillProvenance(
                firstSeenSource: "github:acme/skills",
                currentSource: "github:unknown/skills",
                firstSeenAt: "2026-02-14T11:00:00.000Z"
            )
        )
        let local = Self.testStandaloneSkill()
        let plain = Self.testPluginSkill(name: "design-craft")
        let all = [held, moved, local, plain]

        #expect(SkillPresentation.rows(all, filter: .all, search: "").count == 4)
        #expect(SkillPresentation.rows(all, filter: .held, search: "").map(\.name) == ["trawl"])
        #expect(SkillPresentation.rows(all, filter: .local, search: "").map(\.name) == ["graphify"])
        // Needs attention is the union: a held version and a moved owner both want a human.
        #expect(
            SkillPresentation.rows(all, filter: .needsAttention, search: "").map(\.name).sorted()
                == ["changelog-writer", "trawl"]
        )
    }

    @Test("Search matches the name, the plugin and the marketplace")
    func searchMatchesThreeFields() {
        let skill = Self.testPluginSkill(
            name: "ai-gateway",
            plugin: "vercel",
            marketplace: "official",
            siblings: 30
        )
        #expect(SkillPresentation.rows([skill], filter: .all, search: "gateway").count == 1)
        #expect(SkillPresentation.rows([skill], filter: .all, search: "vercel").count == 1)
        #expect(SkillPresentation.rows([skill], filter: .all, search: "official").count == 1)
        #expect(SkillPresentation.rows([skill], filter: .all, search: "nothing").isEmpty)
    }

    @Test("An empty filter result offers a way back rather than the first-run empty state")
    func emptyInFilterIsNotFirstRun() {
        let message = SkillPresentation.emptyInFilter(.held)
        #expect(message != nil)
        #expect(message?.action == "Show all skills")
        // Claiming "no skills installed" while the user has dozens would be false.
        #expect(message?.title != SkillPresentation.emptyTitle)
        // The unfiltered board with no search has no such message; its emptiness is the genuine
        // first-run empty state and belongs to the board, not to this function.
        #expect(SkillPresentation.emptyInFilter(.all) == nil)
    }
}

/// The second half of the same subject, split only because one struct may not exceed the linter's
/// body-length limit. The fixtures are reached through the first suite rather than duplicated,
/// because two copies of a fixture drift and then two tests disagree about what a skill looks like.
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
        }
    }

    @Test("A whitespace-only search is not treated as a search")
    func blankSearchIsNotASearch() {
        #expect(SkillPresentation.emptyInFilter(.all, search: "   ") == nil)
        #expect(SkillPresentation.emptyInFilter(.held, search: "   ")?.action == "Show all skills")
    }

    @Test("Filter counts follow the search, so a badge never contradicts the list beneath it")
    func countsFollowTheSearch() {
        let held = Self.testPluginSkill(
            name: "trawl",
            held: HeldVersion(pluginVersion: "2.3.0", addedCapabilities: ["runs x.sh"])
        )
        let skills = [held, Self.testPluginSkill(name: "design-craft")]

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
        let skill = Self.testPluginSkill(
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
