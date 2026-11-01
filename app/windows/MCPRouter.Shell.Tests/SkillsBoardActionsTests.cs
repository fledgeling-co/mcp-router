using MCPRouter.Shell.Model.Control;
using MCPRouter.Shell.Model.Skills;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The held-version writes, as the Mac's <c>SkillsBoardModel</c> makes them: keep records a decision and does not
/// reload, promote and undo each reload the board, a refusal stays beside the write that made it, and a second
/// write while one is in flight is ignored. The client is a recording fake, so each test states exactly which
/// route the board called and with what.
/// </summary>
public sealed class SkillsBoardActionsTests
{
    /// <summary>A client that records the write calls and can be told to refuse them or hold them open.</summary>
    private sealed class RecordingClient : ISkillsControlClient
    {
        public List<string> Calls { get; } = [];
        public TaskCompletionSource? Gate { get; set; }
        public SkillsControlError? WriteError { get; set; }
        public string[] RouterCopies { get; set; } = ["trawl@fledgeling-plugins", "first@fledgeling-plugins", "refused@fledgeling-plugins", "last@fledgeling-plugins", "same@market"];
        public HashSet<string> RefusedNames { get; } = [];

        public KeepAck Keep { get; } = new("trawl@fledgeling-plugins", StoredExtensionKind.Plugins, "2.3.0");
        public PromotionAck Promotion { get; } =
            new("trawl@fledgeling-plugins", StoredExtensionKind.Plugins, "2.3.0", "2.2.0", "1002");
        public UndoAck Undo { get; } =
            new("trawl@fledgeling-plugins", StoredExtensionKind.Plugins, "2.2.0", "2.3.0");

        public Task<SkillsResponse> SkillsAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult(new SkillsResponse([], []));

        public Task<MarketplacesResponse> MarketplacesAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult(new MarketplacesResponse([]));

        public Task<ExtensionUpdatesResponse> ExtensionUpdatesAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult(new ExtensionUpdatesResponse(RouterCopies.Select(name => new ExtensionUpdateEntry(StoredExtensionKind.Plugins, name, "current", "1.0.0", "1.0.0", false, "current router copy", null)).ToArray(), []));

        public async Task<KeepAck> KeepHeldVersionAsync(
            string name, string pluginVersion, CancellationToken cancellationToken = default)
        {
            Calls.Add($"keep {name} {pluginVersion}");
            await Settle();
            ThrowIfRefused(name);
            return Keep with { Kept = name };
        }

        public async Task<PromotionAck> PromoteFromCacheAsync(
            string name, string pluginVersion, CancellationToken cancellationToken = default)
        {
            Calls.Add($"promote {name} {pluginVersion}");
            await Settle();
            ThrowIfRefused(name);
            return Promotion with { Promoted = name };
        }

        public async Task<UndoAck> UndoPromotionAsync(
            string name, string restore, CancellationToken cancellationToken = default)
        {
            Calls.Add($"undo {name} {restore}");
            await Settle();
            ThrowIfRefused(name);
            return Undo with { Restored = name };
        }

        private async Task Settle()
        {
            if (Gate is not null) await Gate.Task;
        }

        private void ThrowIfRefused(string name)
        {
            if (RefusedNames.Contains(name)) throw new SkillsControlException(new SkillsControlError.Server(409, "the version remains held", null), null);
            if (WriteError is not null) throw new SkillsControlException(WriteError, null);
        }
    }

    private static Skill HeldTrawl() => new(
        Name: "trawl",
        Description: "Mines past sessions for evidence.",
        Path: "/cache/trawl/2.2.0/skills/trawl",
        Source: new SkillSource.PluginOrigin("trawl", "fledgeling-plugins", "2.2.0", null, null, null, 1),
        Presence: new Dictionary<string, SkillPresence>(),
        Held: new HeldVersion("2.3.0", ["capabilities not compared with the installed version"], 1));

    private static Skill Standalone() => new(
        Name: "graphify",
        Description: "Graph generation.",
        Path: "~/.claude/skills/graphify",
        Source: new SkillSource.Standalone("~/.claude/skills/graphify"),
        Presence: new Dictionary<string, SkillPresence>());

    [Fact]
    public async Task BatchCopyReportsMissingRouterOwnershipWithoutMakingAWrite()
    {
        var client = new RecordingClient { RouterCopies = [] };
        var actions = new SkillsBoardActions(client, () => Task.CompletedTask);
        await actions.UpdateAllAsync([HeldTrawl() with { Held = new HeldVersion("2.3.0", [], 1) }]);
        Assert.Empty(client.Calls);
        Assert.Contains(SkillPresentation.NoRouterCopy, Assert.Single(actions.BatchFailures));
        Assert.StartsWith("Copied 0 of 1 plugins to the router store.", actions.Notice);
        Assert.Null(actions.LastPromotion);
    }

    [Fact]
    public void RouterOwnershipUsesExactPluginAndMarketplaceEvenWithoutAnUpdateOffer()
    {
        var row = new ExtensionUpdateEntry(StoredExtensionKind.Plugins, "trawl@fledgeling-plugins", "current", "2.2.0", "2.2.0", false, "current", null);
        Assert.True(SkillPresentation.HasRouterCopy(HeldTrawl(), [row]));
        Assert.False(SkillPresentation.HasRouterCopy(HeldTrawl(), [row with { Name = "trawl@other" }]));
        Assert.False(SkillPresentation.HasRouterCopy(HeldTrawl(), [row with { Kind = StoredExtensionKind.Skills }]));
        var snapshot = SkillsBoardSnapshot.FromResults(new SkillsResponse([HeldTrawl()], [], true), null, null, null, new ExtensionUpdatesResponse([row], []));
        Assert.True(snapshot.CanCopyToRouter(HeldTrawl()));
        Assert.False((snapshot with { Updates = null }).CanCopyToRouter(HeldTrawl()));
    }

    [Fact]
    public async Task ClaudeOnlyPluginCannotBeCopiedOrReportedAsInstalled()
    {
        var client = new RecordingClient { RouterCopies = [] };
        var reloads = 0;
        var actions = new SkillsBoardActions(client, () => { reloads++; return Task.CompletedTask; });
        await actions.PromoteHeldVersionAsync(HeldTrawl());
        Assert.Empty(client.Calls);
        Assert.Null(actions.Notice);
        Assert.Null(actions.LastPromotion);
        Assert.Contains(SkillPresentation.NoRouterCopy, actions.WriteFailure!.UserFacingDescription);
        Assert.Equal(0, reloads);
    }

    [Fact]
    public async Task KeepRecordsItsNoticeAndSendsTheHeldVersion()
    {
        var client = new RecordingClient();
        var reloads = 0;
        var actions = new SkillsBoardActions(client, () => { reloads++; return Task.CompletedTask; });

        await actions.KeepHeldVersionAsync(HeldTrawl());

        Assert.Equal(new[] { "keep trawl@fledgeling-plugins 2.3.0" }, client.Calls);
        Assert.Equal("Kept 2.3.0. The router has recorded that you kept it.", actions.Notice);
        Assert.Null(actions.WriteFailure);
        Assert.False(actions.Writing);
        // A keep changes what the router will say, not what is installed, so the board does not re-read.
        Assert.Equal(0, reloads);
    }

    [Fact]
    public async Task KeepIsNotSentForAStandaloneSkill()
    {
        // A hand-placed skill has no version to hold, so there is nothing to keep and no call to make.
        var client = new RecordingClient();
        var actions = new SkillsBoardActions(client, () => Task.CompletedTask);

        await actions.KeepHeldVersionAsync(Standalone());

        Assert.Empty(client.Calls);
        Assert.Null(actions.Notice);
        Assert.Null(actions.WriteFailure);
    }

    [Fact]
    public async Task AKeepRefusalIsKeptBesideTheWriteAndNotCalledASuccess()
    {
        var refusal = new SkillsControlError.Server(409, "a kept version already exists", "undo first");
        var client = new RecordingClient { WriteError = refusal };
        var actions = new SkillsBoardActions(client, () => Task.CompletedTask);

        await actions.KeepHeldVersionAsync(HeldTrawl());

        Assert.Equal(refusal, actions.WriteFailure);
        Assert.Null(actions.Notice);
        Assert.False(actions.Writing);
    }

    [Fact]
    public async Task PromoteRecordsTheUndoAndReloadsTheBoard()
    {
        var client = new RecordingClient();
        var reloads = 0;
        var actions = new SkillsBoardActions(client, () => { reloads++; return Task.CompletedTask; });

        await actions.PromoteHeldVersionAsync(HeldTrawl());

        Assert.Equal(new[] { "promote trawl@fledgeling-plugins 2.3.0" }, client.Calls);
        Assert.Equal(
            new SkillsBoardActions.PromotedEntry("trawl", "trawl@fledgeling-plugins", "1002"),
            actions.LastPromotion);
        Assert.Equal(
            "Copied trawl 2.3.0 to the router store. Undo restores the previous router copy. Claude Code was not changed.",
            actions.Notice);
        Assert.Equal(1, reloads);
    }

    [Fact]
    public async Task APromoteRefusalLeavesNoUndoAndDoesNotReload()
    {
        var refusal = new SkillsControlError.Server(404, "the plugin cache holds no copy of trawl@fledgeling-plugins at 2.3.0", null);
        var client = new RecordingClient { WriteError = refusal };
        var reloads = 0;
        var actions = new SkillsBoardActions(client, () => { reloads++; return Task.CompletedTask; });

        await actions.PromoteHeldVersionAsync(HeldTrawl());

        Assert.Null(actions.LastPromotion);
        Assert.Equal(refusal, actions.WriteFailure);
        Assert.Null(actions.Notice);
        Assert.Equal(0, reloads);
    }

    [Fact]
    public async Task UndoPutsBackTheReplacedVersionAndReloads()
    {
        var client = new RecordingClient();
        var reloads = 0;
        var actions = new SkillsBoardActions(client, () => { reloads++; return Task.CompletedTask; });
        await actions.PromoteHeldVersionAsync(HeldTrawl());

        await actions.UndoLastPromotionAsync();

        Assert.Equal(
            new[] { "promote trawl@fledgeling-plugins 2.3.0", "undo trawl@fledgeling-plugins 1002" },
            client.Calls);
        Assert.Null(actions.LastPromotion);
        Assert.Equal("Restored the router copy of trawl at 2.2.0. Claude Code was not changed.", actions.Notice);
        Assert.Equal(2, reloads);
    }

    [Fact]
    public async Task AnUndoRefusalLeavesThePromotionInPlaceForTheReasonToBeReadAgainst()
    {
        var client = new RecordingClient();
        var actions = new SkillsBoardActions(client, () => Task.CompletedTask);
        await actions.PromoteHeldVersionAsync(HeldTrawl());

        var refusal = new SkillsControlError.Server(404, "no promotion is recorded at 1002", null);
        client.WriteError = refusal;
        await actions.UndoLastPromotionAsync();

        Assert.Equal(new SkillsBoardActions.PromotedEntry("trawl", "trawl@fledgeling-plugins", "1002"), actions.LastPromotion);
        Assert.Equal(refusal, actions.WriteFailure);
    }

    [Fact]
    public async Task AWriteStartedWhileAnotherIsInFlightIsIgnored()
    {
        var client = new RecordingClient { Gate = new TaskCompletionSource() };
        var actions = new SkillsBoardActions(client, () => Task.CompletedTask);

        var first = actions.KeepHeldVersionAsync(HeldTrawl());
        // A second press while the keep is still in flight.
        await actions.PromoteHeldVersionAsync(HeldTrawl());

        Assert.True(actions.Writing);
        Assert.Equal(new[] { "keep trawl@fledgeling-plugins 2.3.0" }, client.Calls);

        client.Gate!.SetResult();
        await first;

        Assert.False(actions.Writing);
        Assert.Equal(new[] { "keep trawl@fledgeling-plugins 2.3.0" }, client.Calls);
    }

    [Fact]
    public async Task AWriteClearsTheLastRefusalAndNoticeBeforeItRuns()
    {
        // A stale refusal never sits beside a new outcome.
        var client = new RecordingClient { WriteError = new SkillsControlError.Server(500, "boom", null) };
        var actions = new SkillsBoardActions(client, () => Task.CompletedTask);
        await actions.KeepHeldVersionAsync(HeldTrawl());
        Assert.NotNull(actions.WriteFailure);

        client.WriteError = null;
        client.Gate = new TaskCompletionSource();
        var pending = actions.KeepHeldVersionAsync(HeldTrawl());

        Assert.Null(actions.WriteFailure);
        Assert.Null(actions.Notice);
        Assert.True(actions.Writing);

        client.Gate.SetResult();
        await pending;
    }

    [Fact]
    public async Task TheBoardIsToldWhenAWriteStartsAndWhenItEnds()
    {
        var client = new RecordingClient();
        var actions = new SkillsBoardActions(client, () => Task.CompletedTask);
        var told = 0;
        actions.Changed += () => told++;

        await actions.KeepHeldVersionAsync(HeldTrawl());

        // Once when the write starts, so its controls can say so, and once when it ends.
        Assert.Equal(2, told);
    }

    [Fact]
    public async Task UpdateAllDeduplicatesPluginsAndNeverPromotesAddedCapabilities()
    {
        var first = HeldTrawl() with { Held = new HeldVersion("2.3.0", [], 2) };
        var sibling = first with { Name = "trawl-extra" };
        var asksMore = HeldTrawl() with { Name = "unsafe", Source = new SkillSource.PluginOrigin("unsafe", "fledgeling-plugins", "1.0.0", null, null, null, 1) };
        var client = new RecordingClient();
        var reloads = 0;
        var actions = new SkillsBoardActions(client, () => { reloads++; return Task.CompletedTask; });
        await actions.UpdateAllAsync([first, sibling, asksMore, Standalone()]);
        Assert.Equal(new[] { "promote trawl@fledgeling-plugins 2.3.0" }, client.Calls);
        Assert.Empty(actions.BatchFailures);
        Assert.Equal(1, reloads);
        Assert.StartsWith("Copied 1 of 1 plugins to the router store.", actions.Notice);
    }

    [Fact]
    public async Task APartialUpdateAllKeepsFailuresVisibleAndEachSuccessfulPromotionCanBeUndone()
    {
        Skill Offered(string name) => HeldTrawl() with
        {
            Name = name, Source = new SkillSource.PluginOrigin(name, "fledgeling-plugins", "2.2.0", null, null, null, 1),
            Held = new HeldVersion("2.3.0", [], 1),
        };
        var client = new RecordingClient();
        client.RefusedNames.Add("refused@fledgeling-plugins");
        var actions = new SkillsBoardActions(client, () => Task.CompletedTask);
        await actions.UpdateAllAsync([Offered("first"), Offered("refused"), Offered("last")]);
        Assert.StartsWith("Copied 2 of 3 plugins to the router store.", actions.Notice);
        Assert.Contains("refused:", Assert.Single(actions.BatchFailures));
        Assert.Equal("last", actions.LastPromotion?.Plugin);
        await actions.UndoLastPromotionAsync();
        Assert.Equal("first", actions.LastPromotion?.Plugin);
        await actions.UndoLastPromotionAsync();
        Assert.Null(actions.LastPromotion);
        Assert.EndsWith("last@fledgeling-plugins 1002", client.Calls[^2]);
        Assert.EndsWith("first@fledgeling-plugins 1002", client.Calls[^1]);
    }

}
