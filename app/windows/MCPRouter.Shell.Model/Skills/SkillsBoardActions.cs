using MCPRouter.Shell.Model.Control;

namespace MCPRouter.Shell.Model.Skills;

/// <summary>
/// The Skills board's held-version writes, as the Mac's <c>SkillsBoardModel</c> makes them. Each write sets the
/// board's write state, sends one route, and reports the outcome in the router's own words. A refusal is kept
/// beside the write that made it (DESIGN.md §6); a success says what changed. Promote and undo re-read the board,
/// because the router's answer changes what the next read says. Keep does not, since a kept version is recorded
/// without anything being installed.
/// </summary>
public sealed class SkillsBoardActions
{
    /// <summary>A promotion this board made: the plugin's own name, the store name, and the reference its undo needs.</summary>
    public sealed record PromotedEntry(string Plugin, string Name, string Restore);

    private readonly ISkillsControlClient _client;
    private readonly Func<Task> _reload;

    public SkillsBoardActions(ISkillsControlClient client, Func<Task> reload)
    {
        _client = client;
        _reload = reload;
    }

    /// <summary>Raised when a write starts and when it ends, so the controls that show its state can read it again.</summary>
    public event Action? Changed;

    /// <summary>The last write's refusal, in the router's words. Cleared when the next write starts.</summary>
    public SkillsControlError? WriteFailure { get; private set; }

    /// <summary>Whether a write is in flight, so its controls can say so and not start a second one.</summary>
    public bool Writing { get; private set; }

    /// <summary>What the last write did, in a sentence. Nil until a write succeeds.</summary>
    public string? Notice { get; private set; }

    /// <summary>The promotion the board can take back. A promote sets it and its undo clears it.</summary>
    public PromotedEntry? LastPromotion { get; private set; }

    public Task KeepHeldVersionAsync(Skill skill) => throw new NotImplementedException();

    public Task PromoteHeldVersionAsync(Skill skill) => throw new NotImplementedException();

    public Task UndoLastPromotionAsync() => throw new NotImplementedException();
}
