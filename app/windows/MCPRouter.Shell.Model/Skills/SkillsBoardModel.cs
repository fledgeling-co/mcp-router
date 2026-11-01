using MCPRouter.Shell.Model.Control;
using MCPRouter.Shell.Model.Skills;

namespace MCPRouter.Shell.Model.Skills;

/// <summary>
/// The Skills board's load-state machine: client results in, one snapshot out, and every
/// decision about which of DESIGN.md §5's nine states the board is in made here, where a test
/// can reach it - never in the view, where only a running window could exercise it.
///
/// The switch over <see cref="SkillsBoardState"/> in the view is exhaustive by construction: a
/// tenth state stops the build rather than drawing blank, which is the moment someone should be
/// deciding what it looks like.
/// </summary>
public enum SkillsBoardState
{
    /// <summary>Reads in flight; the view draws the skeleton.</summary>
    Loading,

    /// <summary>Skills arrived and are non-empty - the table, with any partial notes.</summary>
    Populated,

    /// <summary>Skills arrived and are empty - the first-run state, not an error.</summary>
    Empty,

    /// <summary>
    /// The router isn't running. Loopback means this is "not running", not "network down" - say
    /// so and offer the retry, per §5's Offline row.
    /// </summary>
    Offline,

    /// <summary>Anything else that failed; the error carries its own headline and advice.</summary>
    Failed,
}

/// <summary>
/// Everything the Skills board draws, at a moment, as values a test can compare. One record per
/// load, immutable, so the view never holds a half-updated board.
/// </summary>
public sealed record SkillsBoardSnapshot
{
    public static SkillsBoardSnapshot Loading { get; } = new() { State = SkillsBoardState.Loading };

    public required SkillsBoardState State { get; init; }

    /// <summary>The failure, when the state is Offline or Failed. Carries the §6 copy with it.</summary>
    public SkillsControlError? Error { get; init; }

    public SkillsResponse? Skills { get; init; }

    /// <summary>
    /// The marketplace list, when it loaded. Null when it did not - a different fact from an
    /// empty list, and the reason an auto-update cell can say "Not shown".
    /// </summary>
    public IReadOnlyList<Marketplace>? Marketplaces { get; init; }

    /// <summary>Why the marketplace list is not in hand, when it is not. Null when it loaded.</summary>
    public string? MarketplaceListNote { get; init; }

    /// <summary>§5's Partial: a client's directory could not be read. Null when every client was read.</summary>
    public string? PartialNote { get; init; }

    /// <summary>The held-for-review rows, wanting more - the board's security surface, drawn as banners.</summary>
    public IReadOnlyList<Skill> HeldForReview { get; init; } = Array.Empty<Skill>();

    public int InstalledCount => Skills?.SkillList.Count ?? 0;

    public int MarketplacesCount => Marketplaces?.Count ?? 0;

    /// <summary>Why the update check is not in hand, when it is not. Its own read, so its failure never blanks the board.</summary>
    public SkillsControlError? UpdatesError { get; init; }

    /// <summary>Every offer the Updates section draws: the register's held versions, then the store's own offers.</summary>
    public ExtensionUpdatesResponse? Updates { get; init; }
    public IReadOnlyList<ExtensionUpdateEntry> Offers => SkillPresentation.UpdateOffers(Skills?.SkillList ?? [], Updates?.EntryList ?? []);

    /// <summary>Every skill with a newer version fetched at all - what the Updates tab lists.</summary>
    public IReadOnlyList<Skill> Updated => Skills is null
        ? Array.Empty<Skill>()
        : SkillPresentation.Updated(Skills.SkillList);

    /// <summary>
    /// What "Update all" acts on: newer versions that ask for nothing more. Held-for-review rows
    /// are never counted - the brief's security clause (spec-WIN6 §3.1).
    /// </summary>
    public int UpdateAllCount => Skills is null
        ? 0
        : SkillPresentation.Updatable(Skills.SkillList).Select(skill => skill.Source.AsPlugin).Where(origin => origin is not null)
            .Select(origin => $"{origin!.Plugin}@{origin.Marketplace}").Distinct(StringComparer.Ordinal).Count();

    /// <summary>
    /// Builds the snapshot from the two reads' outcomes, both optional and both allowed to have
    /// failed independently - §5's Partial row is "say what arrived and what did not, with the
    /// reason", so one failed read never discards the other's result.
    /// </summary>
    public static SkillsBoardSnapshot FromResults(
        SkillsResponse? skills,
        SkillsControlError? skillsError,
        MarketplacesResponse? marketplaces,
        SkillsControlError? marketplacesError,
        ExtensionUpdatesResponse? updates = null,
        SkillsControlError? updatesError = null)
    {
        if (skillsError is not null)
        {
            return new SkillsBoardSnapshot
            {
                State = skillsError is SkillsControlError.RouterNotRunning
                    ? SkillsBoardState.Offline
                    : SkillsBoardState.Failed,
                Error = skillsError,
            };
        }

        if (skills is null)
        {
            throw new InvalidOperationException(
                "the skills read produced neither a response nor an error - the client lied");
        }

        if (skills.SkillList.Count == 0)
        {
            return new SkillsBoardSnapshot
            {
                State = SkillsBoardState.Empty,
                Skills = skills,
                Updates = updates,
                UpdatesError = updatesError,
                Marketplaces = marketplaces?.MarketplaceList,
                MarketplaceListNote = MarketplaceNote(marketplaces, marketplacesError),
            };
        }

        return new SkillsBoardSnapshot
        {
            State = SkillsBoardState.Populated,
            Skills = skills,
            Updates = updates,
            UpdatesError = updatesError,
            Marketplaces = marketplaces?.MarketplaceList,
            MarketplaceListNote = MarketplaceNote(marketplaces, marketplacesError),
            PartialNote = SkillPresentation.PartialNote(skills),
            HeldForReview = skills.SkillList
                .Where(s => s.Held?.WantsMore ?? false)
                .ToList(),
        };
    }

    /// <summary>
    /// The one-line partial note for a marketplace list that did not load - what arrived (the
    /// skills), what did not (the marketplace records), and the reason.
    /// </summary>
    private static string? MarketplaceNote(
        MarketplacesResponse? marketplaces, SkillsControlError? marketplacesError)
    {
        if (marketplaces is not null) return null;
        if (marketplacesError is null) return null;
        return $"The marketplace list didn't load ({marketplacesError.Headline}), so the "
               + "auto-update column says \"Not shown\" rather than a setting nobody read.";
    }
}
