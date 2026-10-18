using MCPRouter.Shell.Model.Registry;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The two bands' membership and ordering, and the guards that keep them honest: absence is not
/// zero, the window never reaches Most used, and a band empty within results is its own state.
/// </summary>
public sealed class DiscoverBandsTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 31, 12, 0, 0, TimeSpan.Zero);

    private static RegistryEntry Row(
        string id,
        int? useCount = null,
        string? updatedAt = null) => new()
    {
        Id = id,
        Name = id,
        DisplayName = id,
        Description = "",
        Source = "official",
        UpdatedAt = updatedAt,
        UseCount = useCount,
    };

    private static readonly RegistryEntry Used = Row("b", useCount: 200);
    private static readonly RegistryEntry MoreUsed = Row("a", useCount: 300);
    private static readonly RegistryEntry SameUsedAsB = Row("c", useCount: 200);
    private static readonly RegistryEntry NeverUsed = Row("d", useCount: null);
    private static readonly RegistryEntry Fresh = Row("e", updatedAt: "2026-08-30T00:00:00Z");
    private static readonly RegistryEntry Old = Row("f", updatedAt: "2025-01-01T00:00:00Z");
    private static readonly RegistryEntry Undated = Row("g", updatedAt: null);

    private static readonly List<RegistryEntry> All = [MoreUsed, SameUsedAsB, Used, NeverUsed, Fresh, Old, Undated];

    // ----------------------------------------------------------------- Most used

    [Fact]
    public void MostUsedSortsDescendingAndExcludesTheUnmeasured()
    {
        var members = DiscoverBands.Members(DiscoverBand.MostUsed, All, RecencyWindow.AnyTime, Now);

        // NeverUsed has no session count: absent, never ranked at zero — a zero would claim
        // Smithery measured nobody using an entry it does not index.
        Assert.Equal(["a", "b", "c"], members.Select(e => e.Id));

        // ...and the excluded row is still reachable from the other band and from search.
        Assert.Contains(NeverUsed, All);
    }

    [Fact]
    public void MostUsedTiesBreakOnIdAscendingAndStable()
    {
        var members = DiscoverBands.Members(DiscoverBand.MostUsed, All, RecencyWindow.AnyTime, Now);
        Assert.Equal("b", members[1].Id);
        Assert.Equal("c", members[2].Id);
    }

    [Fact]
    public void TheWindowNeverReachesMostUsed()
    {
        // The guard on the tidy-looking change: filtering this band by the window would silently
        // claim a per-window session count that was never measured.
        foreach (var window in Enum.GetValues<RecencyWindow>())
        {
            var members = DiscoverBands.Members(DiscoverBand.MostUsed, All, window, Now);
            Assert.Equal(["a", "b", "c"], members.Select(e => e.Id));
        }
    }

    // ----------------------------------------------------------------- Recently changed

    [Fact]
    public void RecentlyChangedSortsNewestFirstAndDropsTheUndated()
    {
        var members = DiscoverBands.Members(DiscoverBand.RecentlyChanged, All, RecencyWindow.AnyTime, Now);
        Assert.Equal(["e", "f"], members.Select(e => e.Id));
    }

    [Fact]
    public void TheWindowScopesRecentlyChanged()
    {
        var members = DiscoverBands.Members(DiscoverBand.RecentlyChanged, All, RecencyWindow.Seven, Now);
        Assert.Equal(["e"], members.Select(e => e.Id)); // Old is outside the window
    }

    [Fact]
    public void AnyTimeIsTheDefaultAndExcludesNothing()
    {
        Assert.Null(RecencyWindow.AnyTime.Days());
        var members = DiscoverBands.Members(DiscoverBand.RecentlyChanged, All, RecencyWindow.AnyTime, Now);
        Assert.Equal(2, members.Count);
    }

    // ----------------------------------------------------------------- band empties

    [Fact]
    public void BandEmptyWithinResultsIsItsOwnState()
    {
        // An all-official page (no Smithery counts) empties Most used — the common case.
        var officialOnly = new List<RegistryEntry> { Fresh, Old };
        Assert.Equal(
            RegistryPresentation.BandEmptyKind.MostUsed,
            DiscoverBands.EmptyWithinResults(DiscoverBand.MostUsed, officialOnly, RecencyWindow.AnyTime, Now));

        // A windowed Recently changed whose rows are old or undated empties the other way. The
        // population must genuinely lack band members - Fresh would populate it.
        var staleOrUndated = new List<RegistryEntry> { Old, Undated };
        Assert.Equal(
            RegistryPresentation.BandEmptyKind.RecentlyChangedWindowed,
            DiscoverBands.EmptyWithinResults(DiscoverBand.RecentlyChanged, staleOrUndated, RecencyWindow.Seven, Now));
    }

    [Fact]
    public void WholeListEmptyIsNotABandEmpty()
    {
        // The band-empty sentence must not render over a board that has nothing at all — that
        // state has its own copy.
        Assert.Equal(
            RegistryPresentation.BandEmptyKind.None,
            DiscoverBands.EmptyWithinResults(DiscoverBand.MostUsed, [], RecencyWindow.AnyTime, Now));
    }

    [Fact]
    public void WindowedBandEmptyAndAnyTimeBandEmptyAreDifferentStates()
    {
        var anyTime = DiscoverBands.EmptyWithinResults(DiscoverBand.RecentlyChanged, [Undated], RecencyWindow.AnyTime, Now);
        var windowed = DiscoverBands.EmptyWithinResults(DiscoverBand.RecentlyChanged, [Undated], RecencyWindow.Seven, Now);
        Assert.Equal(RegistryPresentation.BandEmptyKind.RecentlyChangedAnyTime, anyTime);
        Assert.Equal(RegistryPresentation.BandEmptyKind.RecentlyChangedWindowed, windowed);

        // The windowed sentence carries the number; the any-time sentence cannot grammatically.
        var windowedMessage = RegistryPresentation.BandEmptyMessage(windowed, 7)!;
        Assert.Contains("7 days", windowedMessage.Headline);
        Assert.Equal(DiscoverCopy.ShowAnyTimeAction, windowedMessage.Action);

        var anyTimeMessage = RegistryPresentation.BandEmptyMessage(anyTime, 0)!;
        Assert.DoesNotContain("0 days", anyTimeMessage.Headline);
        Assert.Null(anyTimeMessage.Action);
    }

    [Fact]
    public void PopulatedBandsReportNoEmptyKind()
    {
        Assert.Equal(
            RegistryPresentation.BandEmptyKind.None,
            DiscoverBands.EmptyWithinResults(DiscoverBand.MostUsed, All, RecencyWindow.AnyTime, Now));
        Assert.Equal(
            RegistryPresentation.BandEmptyKind.None,
            DiscoverBands.EmptyWithinResults(DiscoverBand.RecentlyChanged, All, RecencyWindow.Seven, Now));
    }
}
