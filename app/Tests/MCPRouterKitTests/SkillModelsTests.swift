import Foundation
import Testing
@testable import MCPRouterKit

/// The skills wire contract.
///
/// `SWIFT_PRACTICES.md` §2 is the whole subject of this suite: a closed set on the wire is a closed
/// set in Swift, an unrecognised shape fails decoding rather than being guessed at, and **no decode
/// path has emptiness as its failure mode**. That last rule exists because this repo already
/// shipped its opposite — a flat `servers.json` that loaded zero servers with no error at all,
/// which on screen is indistinguishable from "you have none".
@Suite("Skill wire contract")
struct SkillModelsTests {
    private func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Tagged unions

    @Test("A plugin source decodes with its plugin-level fields")
    func pluginSourceDecodes() throws {
        let source = try decode(
            """
            {"kind":"plugin","plugin":"vercel","marketplace":"official","pluginVersion":"0.45.1",
             "installedAt":"2026-01-26T08:11:09.391Z","lastUpdated":null,
             "commit":"6db48033d218","siblingSkillCount":30}
            """,
            as: SkillSource.self
        )
        let origin = try #require(source.pluginOrigin)
        #expect(origin.plugin == "vercel")
        #expect(origin.pluginVersion == "0.45.1")
        // The field that stops thirty rows looking like thirty independent versions.
        #expect(origin.siblingSkillCount == 30)
    }

    @Test("A standalone source has no version field at all")
    func standaloneSourceHasNoVersion() throws {
        let source = try decode(
            #"{"kind":"standalone","path":"/home/.agents/skills/graphify"}"#,
            as: SkillSource.self
        )
        #expect(source.isStandalone)
        // Structural, not conventional: there is nowhere on this case to put a version, so no later
        // edit can give a hand-placed skill one by accident.
        #expect(source.pluginOrigin == nil)
    }

    @Test("An unrecognised source kind FAILS decoding rather than being guessed")
    func unknownSourceKindFails() {
        #expect(throws: (any Error).self) {
            try decode(#"{"kind":"borrowed","path":"/x"}"#, as: SkillSource.self)
        }
    }

    @Test("An unrecognised marketplace source kind FAILS decoding")
    func unknownMarketplaceKindFails() {
        #expect(throws: (any Error).self) {
            try decode(#"{"kind":"ftp","repo":"x/y"}"#, as: MarketplaceSource.self)
        }
    }

    // MARK: - Closed enums

    @Test("An unrecognised presence value FAILS decoding")
    func unknownPresenceFails() {
        // "maybe" must not silently become "absent"; a guessed presence is a claim about whether a
        // skill is installed somewhere.
        #expect(throws: (any Error).self) {
            try decode(#""maybe""#, as: SkillPresence.self)
        }
    }

    @Test("An unrecognised client status FAILS decoding")
    func unknownStatusFails() {
        #expect(throws: (any Error).self) {
            try decode(#""probably""#, as: SkillClientStatus.self)
        }
    }

    @Test("The three presence values are all distinct and all decode")
    func presenceValuesDecode() throws {
        #expect(try decode(#""present""#, as: SkillPresence.self) == .present)
        #expect(try decode(#""absent""#, as: SkillPresence.self) == .absent)
        // The one that stops "we could not look" rendering as "not installed".
        #expect(try decode(#""unreadable""#, as: SkillPresence.self) == .unreadable)
    }

    // MARK: - A whole response

    @Test("A full skills response decodes, and identity is the resolved path")
    func fullResponseDecodes() throws {
        let response = try decode(
            """
            {"skills":[
              {"name":"intent-layer","description":"Ground a feature.",
               "path":"/home/.agents/skills/intent-layer",
               "source":{"kind":"standalone","path":"/home/.agents/skills/intent-layer"},
               "presence":{"claudeCode":"present","codex":"present","cursor":"present","opencode":"present"},
               "held":null,"provenance":null}],
             "clients":[
              {"id":"claudeCode","displayName":"Claude Code","supportsSkills":true,
               "root":"/home/.claude/skills","status":"read","reason":null},
              {"id":"claudeDesktop","displayName":"Claude Desktop","supportsSkills":false,
               "root":null,"status":"unsupported","reason":null}]}
            """,
            as: SkillsResponse.self
        )
        #expect(response.skills.count == 1)
        let skill = try #require(response.skills.first)
        // One skill reachable from four clients is ONE row. Keying on the name would have split it
        // into four; keying on the resolved path is what collapses the symlink farm.
        #expect(skill.id == "/home/.agents/skills/intent-layer")
        #expect(skill.presence.values.filter { $0 == .present }.count == 4)
        #expect(response.slotClients.map(\.id) == ["claudeCode"])
        #expect(response.unsupportedClients.map(\.id) == ["claudeDesktop"])
    }

    @Test("A skills response missing its skills key FAILS rather than decoding as empty")
    func missingSkillsKeyFails() {
        // The flat-servers.json trap, in Swift. An empty result here would render as "you have no
        // skills", which is the most confident possible way to be wrong.
        #expect(throws: (any Error).self) {
            try decode(#"{"clients":[]}"#, as: SkillsResponse.self)
        }
    }

    @Test("A marketplaces response missing its key FAILS rather than decoding as empty")
    func missingMarketplacesKeyFails() {
        #expect(throws: (any Error).self) {
            try decode(#"{}"#, as: MarketplacesResponse.self)
        }
    }

    // MARK: - Held versions

    @Test("A held version with no added capabilities does not want more")
    func emptyDeltaWantsNothing() throws {
        let held = try decode(
            #"{"pluginVersion":"2.3.0","addedCapabilities":[],"affectedSkillCount":1}"#,
            as: HeldVersion.self
        )
        #expect(held.wantsMore == false)
    }

    @Test("A held version with an added capability wants more and is held")
    func nonEmptyDeltaWantsMore() throws {
        let held = try decode(
            #"""
            {"pluginVersion":"2.3.0","addedCapabilities":["runs scripts/collect.sh"],
             "affectedSkillCount":1}
            """#,
            as: HeldVersion.self
        )
        #expect(held.wantsMore)
    }

    // MARK: - The absence that is the point

    @Test("No skill type carries a run count, a last run, or an evaluation")
    func noUnobservableFieldsExist() throws {
        // Asserted against the ENCODED JSON rather than by reflection, for the same reason
        // SWIFT_PRACTICES.md §2 requires it of the command-line guarantee: reflection sees stored
        // properties and would miss a computed property or a CodingKeys mapping that still puts a
        // key on the wire.
        let skill = Skill(
            name: "trawl",
            path: "/x/trawl",
            source: .plugin(PluginOrigin(plugin: "trawl", marketplace: "m", pluginVersion: "2.2.0")),
            presence: ["claudeCode": .present],
            held: HeldVersion(pluginVersion: "2.3.0", addedCapabilities: ["runs x.sh"])
        )
        let encoded = try JSONEncoder().encode(skill)
        let text = try #require(String(data: encoded, encoding: .utf8)).lowercased()
        for forbidden in ["\"runs\"", "\"runcount\"", "\"lastrun\"", "\"eval\"", "\"evalresult\""] {
            #expect(!text.contains(forbidden), "the wire must not carry \(forbidden)")
        }
    }

    @Test("needsAttention is exactly held-wanting-more or a moved owner")
    func needsAttentionIsTheUnion() {
        let base = Skill(name: "s", path: "/s", source: .standalone(path: "/s"))
        #expect(base.needsAttention == false)

        var moved = base
        moved.provenance = SkillProvenance(
            firstSeenSource: "github:a/b", currentSource: "github:c/d", firstSeenAt: "2026-01-01T00:00:00Z"
        )
        #expect(moved.needsAttention)

        var quietUpdate = base
        quietUpdate.held = HeldVersion(pluginVersion: "2", addedCapabilities: [])
        // A version that wants nothing more may promote on its own, so it is not a decision.
        #expect(quietUpdate.needsAttention == false)

        var loudUpdate = base
        loudUpdate.held = HeldVersion(pluginVersion: "2", addedCapabilities: ["runs x.sh"])
        #expect(loudUpdate.needsAttention)
    }
}
