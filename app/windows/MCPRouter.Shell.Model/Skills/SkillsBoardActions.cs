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
    private readonly Stack<PromotedEntry> _promotions = new();
    public PromotedEntry? LastPromotion => _promotions.TryPeek(out var entry) ? entry : null;
    public IReadOnlyList<string> BatchFailures { get; private set; } = [];

    public async Task KeepHeldVersionAsync(Skill skill)
    {
        if (skill.Source.AsPlugin is not { } origin || skill.Held is not { } held || !BeginWrite()) return;
        try
        {
            var ack = await _client.KeepHeldVersionAsync(StoreName(origin), held.PluginVersion);
            Notice = SkillPresentation.Kept(ack.PluginVersion);
        }
        catch (SkillsControlException failure) { WriteFailure = failure.Error; }
        catch (Exception failure) { WriteFailure = Unexpected(failure); }
        finally { EndWrite(); }
    }

    public async Task PromoteHeldVersionAsync(Skill skill)
    {
        if (skill.Source.AsPlugin is not { } origin || skill.Held is not { } held || !BeginWrite()) return;
        try
        {
            var ack = await _client.PromoteFromCacheAsync(StoreName(origin), held.PluginVersion);
            _promotions.Push(new(origin.Plugin, ack.Promoted, ack.Restore));
            Notice = SkillPresentation.Promoted(origin.Plugin, ack.PluginVersion);
            await _reload();
        }
        catch (SkillsControlException failure) { WriteFailure = failure.Error; }
        catch (Exception failure) { WriteFailure = Unexpected(failure); }
        finally { EndWrite(); }
    }

    public async Task UndoLastPromotionAsync()
    {
        if (LastPromotion is not { } promoted || !BeginWrite()) return;
        try
        {
            var ack = await _client.UndoPromotionAsync(promoted.Name, promoted.Restore);
            _promotions.Pop();
            Notice = SkillPresentation.Undone(promoted.Plugin, ack.Version);
            await _reload();
        }
        catch (SkillsControlException failure) { WriteFailure = failure.Error; }
        catch (Exception failure) { WriteFailure = Unexpected(failure); }
        finally { EndWrite(); }
    }

    public async Task UpdateAllAsync(IEnumerable<Skill> skills)
    {
        var eligible = skills.Where(skill => skill.Source.AsPlugin is not null && skill.Held is { WantsMore: false })
            .DistinctBy(skill => StoreName(skill.Source.AsPlugin!)).ToList();
        if (eligible.Count == 0 || !BeginWrite()) return;
        var failures = new List<string>();
        var promoted = 0;
        try
        {
            foreach (var skill in eligible)
            {
                var origin = skill.Source.AsPlugin!;
                try
                {
                    var ack = await _client.PromoteFromCacheAsync(StoreName(origin), skill.Held!.PluginVersion);
                    _promotions.Push(new(origin.Plugin, ack.Promoted, ack.Restore));
                    promoted++;
                }
                catch (SkillsControlException failure) { failures.Add($"{origin.Plugin}: {failure.Error.UserFacingDescription}"); }
                catch (Exception failure) { failures.Add($"{origin.Plugin}: {Unexpected(failure).UserFacingDescription}"); }
            }
            Notice = $"Promoted {promoted} of {eligible.Count} plugins. Undo puts back each promoted copy in reverse order.";
            BatchFailures = failures;
            if (promoted > 0) await _reload();
        }
        catch (SkillsControlException failure) { WriteFailure = failure.Error; }
        catch (Exception failure) { WriteFailure = Unexpected(failure); }
        finally { EndWrite(); }
    }

    private bool BeginWrite()
    {
        if (Writing) return false;
        Writing = true;
        WriteFailure = null;
        Notice = null;
        BatchFailures = [];
        Changed?.Invoke();
        return true;
    }

    private void EndWrite() { Writing = false; Changed?.Invoke(); }
    private static string StoreName(SkillSource.PluginOrigin origin) => $"{origin.Plugin}@{origin.Marketplace}";
    private static SkillsControlError Unexpected(Exception failure) => new SkillsControlError.Transport(failure.GetType().Name);
}
