using MCPRouter.Shell.Model.Skills;

namespace MCPRouter.Shell.Model.Control;

/// <summary>
/// The board the design of record draws, as data - the Windows twin of the Mac's
/// <c>SkillFixtures.swift</c>, and the reason the Debug fixture lane exists: against the router a
/// user runs today, <c>GET /skills</c> answers 404 (spec-WIN6 §2.1), and the populated board must
/// still be reachable to be measured.
///
/// This type is <b>not</b> a second source of truth and never ships data: it is wired only under
/// <c>#if DEBUG</c> behind the explicit <c>--fixture-skills</c> flag, so a release build cannot
/// draw fixture rows no matter how it is launched. The rows are the mock's
/// (<c>design/mcp-router-console.html</c> <c>#b-skills</c>) exactly.
/// </summary>
public sealed class FixtureSkillsControlClient : ISkillsControlClient
{
    public static readonly SkillsResponse Board = new(
        Skills:
        [
            new Skill(
                "trawl",
                "Mine your own past agent sessions for evidence about what happened or what you asked for.",
                "~/.claude/plugins/cache/fledgeling-plugins/trawl/1.4.2/skills/trawl",
                new SkillSource.PluginOrigin(
                    "trawl", "fledgeling-plugins", "1.4.2",
                    InstalledAt: "2026-08-02", LastUpdated: "2026-08-17",
                    Commit: "4c1e08a", SiblingSkillCount: 1),
                Presence: new Dictionary<string, SkillPresence>
                {
                    ["claudeCode"] = SkillPresence.Present,
                    ["cursor"] = SkillPresence.Present,
                    ["grok"] = SkillPresence.Present,
                    ["codex"] = SkillPresence.Present,
                    ["antigravity"] = SkillPresence.Absent,
                },
                Held: new HeldVersion("1.5.0", Array.Empty<string>(), 1)),

            new Skill(
                "design-review",
                "Design and docs review against DESIGN.md, with the evidence to show for it.",
                "~/.claude/plugins/cache/fledgeling-plugins/design-review/2.3.1/skills/design-review",
                new SkillSource.PluginOrigin(
                    "design-review", "fledgeling-plugins", "2.3.1",
                    InstalledAt: "2026-08-02", LastUpdated: "2026-08-17",
                    Commit: "4c1e08a", SiblingSkillCount: 1),
                Presence: new Dictionary<string, SkillPresence>
                {
                    ["claudeCode"] = SkillPresence.Present,
                    ["cursor"] = SkillPresence.Present,
                    ["grok"] = SkillPresence.Absent,
                    ["codex"] = SkillPresence.Absent,
                    ["antigravity"] = SkillPresence.Absent,
                },
                // The board's security case, exactly as the design of record draws it: the new
                // version asks for network access the installed one never had. It is held.
                Held: new HeldVersion("2.4.0", ["network access"], 1)),

            new Skill(
                "mac-craft",
                "macOS subject craft.",
                "~/.claude/plugins/cache/fledgeling-plugins/mac-craft/1.1.0/skills/mac-craft",
                new SkillSource.PluginOrigin(
                    "mac-craft", "fledgeling-plugins", "1.1.0",
                    InstalledAt: "2026-08-02", LastUpdated: "2026-08-17",
                    Commit: "4c1e08a", SiblingSkillCount: 1),
                Presence: new Dictionary<string, SkillPresence>
                {
                    ["claudeCode"] = SkillPresence.Present,
                    ["cursor"] = SkillPresence.Absent,
                    ["grok"] = SkillPresence.Absent,
                    ["codex"] = SkillPresence.Absent,
                    ["antigravity"] = SkillPresence.Absent,
                }),

            new Skill(
                "ux-craft",
                "UX subject craft.",
                "~/.claude/plugins/cache/diolog-plugins/ux-craft/3.0.4/skills/ux-craft",
                new SkillSource.PluginOrigin(
                    "ux-craft", "diolog-plugins", "3.0.4",
                    InstalledAt: "2026-08-02", LastUpdated: "2026-08-20",
                    Commit: "91f7d20", SiblingSkillCount: 1),
                Presence: new Dictionary<string, SkillPresence>
                {
                    ["claudeCode"] = SkillPresence.Present,
                    ["cursor"] = SkillPresence.Present,
                    ["grok"] = SkillPresence.Present,
                    ["codex"] = SkillPresence.Absent,
                    ["antigravity"] = SkillPresence.Absent,
                },
                Held: new HeldVersion("3.0.5", Array.Empty<string>(), 1)),

            new Skill(
                "acceptance-e2e",
                "End-to-end acceptance suites derived from requirements.",
                "~/.claude/plugins/cache/diolog-plugins/acceptance-e2e/2.1.0/skills/acceptance-e2e",
                new SkillSource.PluginOrigin(
                    "acceptance-e2e", "diolog-plugins", "2.1.0",
                    InstalledAt: "2026-08-02", LastUpdated: "2026-08-20",
                    Commit: "91f7d20", SiblingSkillCount: 1),
                Presence: new Dictionary<string, SkillPresence>
                {
                    ["claudeCode"] = SkillPresence.Present,
                    ["cursor"] = SkillPresence.Absent,
                    ["grok"] = SkillPresence.Absent,
                    ["codex"] = SkillPresence.Absent,
                    ["antigravity"] = SkillPresence.Absent,
                }),

            new Skill(
                "create-mac-icon",
                "macOS icon generation.",
                "~/.claude/plugins/cache/fledgeling-plugins/create-mac-icon/1.6.0/skills/create-mac-icon",
                new SkillSource.PluginOrigin(
                    "create-mac-icon", "fledgeling-plugins", "1.6.0",
                    InstalledAt: "2026-08-02", LastUpdated: "2026-08-17",
                    Commit: "4c1e08a", SiblingSkillCount: 1),
                Presence: new Dictionary<string, SkillPresence>
                {
                    ["claudeCode"] = SkillPresence.Present,
                    ["cursor"] = SkillPresence.Absent,
                    ["grok"] = SkillPresence.Absent,
                    ["codex"] = SkillPresence.Absent,
                    ["antigravity"] = SkillPresence.Present,
                },
                Held: new HeldVersion("1.6.1", Array.Empty<string>(), 1)),

            new Skill(
                "graphify",
                "Graph generation.",
                "~/.claude/skills/graphify",
                new SkillSource.Standalone("~/.claude/skills/graphify"),
                Presence: new Dictionary<string, SkillPresence>
                {
                    ["claudeCode"] = SkillPresence.Present,
                }),
        ],
        Clients:
        [
            new SkillClient("claudeCode", "Claude Code", true, "~/.claude/skills", SkillClientStatus.Read, null),
            new SkillClient("cursor", "Cursor", true, "~/.cursor/skills", SkillClientStatus.Read, null),
            new SkillClient("grok", "Grok", true, "~/.grok/installed-plugins", SkillClientStatus.Read, null),
            new SkillClient("codex", "Codex", true, "~/.codex/skills", SkillClientStatus.Read, null),
            new SkillClient("antigravity", "Antigravity", true, "~/.agents/skills", SkillClientStatus.Read, null),
            new SkillClient("windsurf", "Windsurf", false, null, SkillClientStatus.Unsupported, null),
        ]);

    public static readonly MarketplacesResponse Marketplaces = new(
        [
            new Marketplace(
                "fledgeling-plugins",
                new MarketplaceSource.GitHub("fledgeling-co/fledgeling-plugins"),
                AutoUpdate: true,
                InstalledPluginCount: 18,
                SuppliedSkillCount: 24),

            new Marketplace(
                "diolog-plugins",
                new MarketplaceSource.GitHub("DiologIR/diolog-plugins"),
                AutoUpdate: false,
                InstalledPluginCount: 2,
                SuppliedSkillCount: 4),

            new Marketplace(
                "Local directory",
                new MarketplaceSource.Directory("~/.claude/skills"),
                AutoUpdate: false,
                InstalledPluginCount: 0,
                SuppliedSkillCount: 5),
        ]);

    public Task<SkillsResponse> SkillsAsync(CancellationToken cancellationToken = default) =>
        Task.FromResult(Board);

    public Task<MarketplacesResponse> MarketplacesAsync(CancellationToken cancellationToken = default) =>
        Task.FromResult(Marketplaces);

    public Task<ExtensionUpdatesResponse> ExtensionUpdatesAsync(CancellationToken cancellationToken = default) =>
        Task.FromResult(new ExtensionUpdatesResponse([], []));

    public Task<KeepAck> KeepHeldVersionAsync(string name, string pluginVersion, CancellationToken cancellationToken = default) =>
        Task.FromException<KeepAck>(new SkillsControlError.Server(409, "Fixture preview does not change installed skills.", null).AsException(null));

    public Task<PromotionAck> PromoteFromCacheAsync(string name, string pluginVersion, CancellationToken cancellationToken = default) =>
        Task.FromException<PromotionAck>(new SkillsControlError.Server(409, "Fixture preview does not change installed skills.", null).AsException(null));

    public Task<UndoAck> UndoPromotionAsync(string name, string restore, CancellationToken cancellationToken = default) =>
        Task.FromException<UndoAck>(new SkillsControlError.Server(409, "Fixture preview does not change installed skills.", null).AsException(null));
}
