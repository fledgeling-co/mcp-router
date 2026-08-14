import Foundation

/// The skills a fixture client answers with, per scenario.
///
/// Held in code rather than in a recorded JSON file, unlike the server fixtures, and the reason is
/// that these are not recordings: there is no captured session to be faithful to, because the
/// endpoint is new in this item. Writing them as Swift keeps the fixture honest about what it is —
/// invented data for a Debug build — instead of dressing it as a capture.
///
/// **A Release build never reaches any of this.** `ShellClientFactory` returns `.live`
/// unconditionally outside Debug, so nothing here can render in a shipped app.
public enum SkillFixtures {
    public static let clients: [SkillClient] = [
        SkillClient(
            id: "claudeCode", displayName: "Claude Code", supportsSkills: true,
            root: "/Users/you/.claude/skills", status: .read
        ),
        SkillClient(
            id: "codex", displayName: "Codex", supportsSkills: true,
            root: "/Users/you/.codex/skills", status: .read
        ),
        SkillClient(
            id: "cursor", displayName: "Cursor", supportsSkills: true,
            root: "/Users/you/.cursor/skills", status: .read
        ),
        SkillClient(
            id: "opencode", displayName: "opencode", supportsSkills: true,
            root: "/Users/you/.config/opencode/skills", status: .read
        ),
        SkillClient(
            id: "claudeDesktop", displayName: "Claude Desktop", supportsSkills: false, status: .unsupported
        ),
        SkillClient(id: "chatGPT", displayName: "ChatGPT", supportsSkills: false, status: .unsupported)
    ]

    private static func presence(
        _ claudeCode: SkillPresence,
        _ codex: SkillPresence,
        _ cursor: SkillPresence,
        _ opencode: SkillPresence
    ) -> [String: SkillPresence] {
        ["claudeCode": claudeCode, "codex": codex, "cursor": cursor, "opencode": opencode]
    }

    /// The populated set, chosen to put every row treatment on screen at once.
    public static let populated: [Skill] = [
        Skill(
            name: "design-craft",
            description: "Design and review user-facing visual artifacts.",
            path: "/Users/you/.claude/plugins/cache/diolog-plugins/design-craft/1.14.0/skills/design-craft",
            source: .plugin(PluginOrigin(
                plugin: "design-craft", marketplace: "diolog-plugins", pluginVersion: "1.14.0",
                installedAt: "2026-03-02T10:14:00.000Z", lastUpdated: "2026-08-01T09:00:00.000Z",
                commit: "a1c93f2e77b1", siblingSkillCount: 1
            )),
            presence: presence(.present, .absent, .present, .present)
        ),
        // A held version that wants MORE than the one installed: the trust-decay case.
        Skill(
            name: "trawl",
            description: "Mine past sessions for evidence about what happened.",
            path: "/Users/you/.claude/plugins/cache/fledgeling-plugins/trawl/2.2.0/skills/trawl",
            source: .plugin(PluginOrigin(
                plugin: "trawl", marketplace: "fledgeling-plugins", pluginVersion: "2.2.0",
                installedAt: "2026-06-03T05:30:52.695Z", lastUpdated: "2026-07-18T03:32:37.892Z",
                commit: "423563cfe38c", siblingSkillCount: 1
            )),
            presence: presence(.present, .present, .present, .absent),
            held: HeldVersion(
                pluginVersion: "2.3.0",
                addedCapabilities: ["runs scripts/collect.sh", "network api.fledgeling.app"],
                affectedSkillCount: 1
            )
        ),
        // A moved owner. Provenance is the router's own first sighting, never the install date.
        Skill(
            name: "changelog-writer",
            description: "Turn a diff into release notes.",
            path: "/Users/you/.claude/plugins/cache/community/changelog-writer/0.4.1/skills/changelog-writer",
            source: .plugin(PluginOrigin(
                plugin: "changelog-writer", marketplace: "community", pluginVersion: "0.4.1",
                installedAt: "2026-02-14T11:00:00.000Z", lastUpdated: "2026-02-14T11:00:00.000Z",
                commit: "9f2b1c04ade7", siblingSkillCount: 1
            )),
            presence: presence(.present, .absent, .absent, .absent),
            provenance: SkillProvenance(
                firstSeenSource: "github:acme-tools/skills",
                currentSource: "github:unknown-user/skills",
                firstSeenAt: "2026-02-14T11:00:00.000Z"
            )
        ),
        // Reachable from all four clients — one skill, four slots, not four skills.
        Skill(
            name: "intent-layer",
            description: "Ground a feature in what users actually intend.",
            path: "/Users/you/.agents/skills/intent-layer",
            source: .standalone(path: "/Users/you/.agents/skills/intent-layer"),
            presence: presence(.present, .present, .present, .present)
        ),
        // One of thirty siblings sharing a plugin version.
        Skill(
            name: "ai-gateway",
            description: "Route model traffic through the gateway.",
            path: "/Users/you/.claude/plugins/cache/claude-plugins-official/vercel/0.45.1/skills/ai-gateway",
            source: .plugin(PluginOrigin(
                plugin: "vercel", marketplace: "claude-plugins-official", pluginVersion: "0.45.1",
                installedAt: "2026-01-26T08:11:09.391Z", lastUpdated: "2026-08-08T23:38:48.154Z",
                commit: "6db48033d218", siblingSkillCount: 30
            )),
            presence: presence(.present, .absent, .absent, .absent)
        ),
        // A hand-placed skill: no install record anywhere, so genuinely no version.
        Skill(
            name: "graphify",
            description: "Turn any input into a knowledge graph.",
            path: "/Users/you/.claude/skills/graphify",
            source: .standalone(path: "/Users/you/.claude/skills/graphify"),
            presence: presence(.present, .absent, .absent, .absent)
        )
    ]

    private static let overflowPath = "/Users/you/.claude/plugins/cache/"
        + "a-very-long-marketplace-name-that-keeps-going-plugins/"
        + "create-disclosure-consistency-page-generator-extended/10.14.2-rc.1/skills/"
        + "create-disclosure-consistency-page-generator-extended"

    /// A name and a marketplace wider than their columns.
    public static let overflow: [Skill] = [
        Skill(
            name: "create-disclosure-consistency-page-generator-extended",
            description: String(repeating: "A very long description that keeps going. ", count: 6),
            path: overflowPath,
            source: .plugin(PluginOrigin(
                plugin: "create-disclosure-consistency-page-generator-extended",
                marketplace: "a-very-long-marketplace-name-that-keeps-going-plugins",
                pluginVersion: "10.14.2-rc.1",
                installedAt: "2026-05-05T05:05:05.000Z", lastUpdated: "2026-05-05T05:05:05.000Z",
                commit: "0123456789ab", siblingSkillCount: 4
            )),
            presence: presence(.present, .absent, .absent, .absent)
        )
    ]

    /// Cursor could not be read: the Partial state, where a slot is *unknown* rather than off.
    public static func partial() -> SkillsResponse {
        let updated = populated.map { skill -> Skill in
            var copy = skill
            copy.presence["cursor"] = .unreadable
            return copy
        }
        var clients = clients
        if let index = clients.firstIndex(where: { $0.id == "cursor" }) {
            clients[index] = SkillClient(
                id: "cursor", displayName: "Cursor", supportsSkills: true,
                root: "/Users/you/.cursor/skills", status: .unreadable, reason: "permission denied"
            )
        }
        return SkillsResponse(skills: updated, clients: clients)
    }

    public static let marketplaces: [Marketplace] = [
        Marketplace(
            name: "claude-plugins-official", source: .github(repo: "anthropics/claude-plugins-official"),
            autoUpdate: false, installedPluginCount: 12, suppliedSkillCount: 47
        ),
        Marketplace(
            name: "diolog-plugins", source: .github(repo: "DiologIR/diolog-plugins"),
            autoUpdate: true, installedPluginCount: 54, suppliedSkillCount: 67
        ),
        Marketplace(
            name: "fledgeling-plugins", source: .github(repo: "fledgeling-co/fledgeling-plugins"),
            autoUpdate: true, installedPluginCount: 24, suppliedSkillCount: 22
        ),
        // A followed marketplace supplying nothing. A real observation, not an error.
        Marketplace(
            name: "atlas-plugins", source: .directory(path: "/Users/you/Dev/atlas-app/apps/atlas-plugins"),
            autoUpdate: false, installedPluginCount: 0, suppliedSkillCount: 0
        )
    ]
}
