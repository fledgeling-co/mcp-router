using MCPRouter.Shell.Model.Registry;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The board's honesty decisions, as unit-level facts: what a date means, what a figure carries,
/// what the notes admit, and — the brief's named worst state — that a degraded search never
/// renders as "nothing found".
/// </summary>
public sealed class RegistryPresentationTests
{
    private static RegistryEntry Entry(
        string id = "io.github/owner/thing",
        string source = "official",
        string? updatedAt = "2025-09-14T15:20:36Z",
        int? useCount = null,
        int? stars = null,
        bool? archived = false,
        bool? installed = false) => new()
    {
        Id = id,
        Name = id,
        DisplayName = "thing",
        Description = "A description.",
        Source = source,
        UpdatedAt = updatedAt,
        UseCount = useCount,
        Stars = stars,
        Archived = archived,
        Installed = installed,
    };

    // ----------------------------------------------------------------- provenance

    [Fact]
    public void ProvenanceReadsTheIdPrefixNotTheSourceLabel()
    {
        // The wire's own fixture: two Smithery rows collided on a display name, and the merged
        // row is stamped source "both" with nothing official behind it. The id tells the truth
        // the label does not.
        var liar = Entry(id: "smithery:github", source: "both");
        var provenance = RegistryPresentation.ProvenanceFor(liar);
        Assert.False(provenance.IsOfficial);
        Assert.False(provenance.ShowsOfficialMark);
        Assert.True(provenance.IsSmithery);
    }

    [Fact]
    public void OfficialRowShowsTheMarkAndSmitheryRowDoesNot()
    {
        Assert.True(RegistryPresentation.ProvenanceFor(Entry(id: "io.github/owner/x")).ShowsOfficialMark);
        Assert.False(RegistryPresentation.ProvenanceFor(Entry(id: "smithery:@org/x")).ShowsOfficialMark);
    }

    // ----------------------------------------------------------------- dates

    [Fact]
    public void OfficialDateMeansUpdatedAndSmitheryDateMeansAdded()
    {
        var official = RegistryPresentation.DateCellFor(Entry(id: "io.github/o/x", updatedAt: "2025-09-14T15:20:36Z"));
        var smithery = RegistryPresentation.DateCellFor(Entry(id: "smithery:@o/x", updatedAt: "2025-11-19T07:26:28Z"));

        Assert.Equal(RegistryPresentation.DateMeaning.EntryUpdated, official!.Meaning);
        Assert.StartsWith("updated ", official.Text);
        Assert.Equal(RegistryPresentation.DateMeaning.FirstPublished, smithery!.Meaning);
        Assert.StartsWith("added ", smithery.Text);
    }

    [Fact]
    public void UnparseableDateDropsTheCellRatherThanDrawingAPlaceholder()
    {
        Assert.Null(RegistryPresentation.DateCellFor(Entry(updatedAt: null)));
        Assert.Null(RegistryPresentation.DateCellFor(Entry(updatedAt: "recently")));
    }

    // ----------------------------------------------------------------- figures

    [Fact]
    public void FigureCarriesItsUnitAndItsIndex()
    {
        var sessions = RegistryPresentation.FigureFor(Entry(useCount: 9880))!;
        Assert.Equal("9,880 sessions on Smithery", sessions.Text);
        Assert.Contains("Smithery", sessions.Attribution);

        var stars = RegistryPresentation.FigureFor(Entry(stars: 9))!;
        Assert.Equal("9 stars on GitHub", stars.Text);
        Assert.Contains("GitHub", stars.Attribution);
    }

    [Fact]
    public void NoFigureIsNeverADashAndNeverAZero()
    {
        // Absence says "not measured"; a rendered 0 says "measured, and none". For an
        // official-only row there is no usage figure in existence to be zero.
        Assert.Null(RegistryPresentation.FigureFor(Entry(useCount: null, stars: null)));
    }

    [Fact]
    public void ArchivedRowCarriesTheWarning()
    {
        Assert.Equal("repository archived", RegistryPresentation.ArchivedNoteFor(Entry(archived: true)));
        Assert.Null(RegistryPresentation.ArchivedNoteFor(Entry(archived: false)));
        Assert.Null(RegistryPresentation.ArchivedNoteFor(Entry(archived: null)));
    }

    // ----------------------------------------------------------------- the subtitle

    [Fact]
    public void SubtitleCountsWhatIsOnScreenNotWhatMatched()
    {
        var response = new RegistrySearchResponse
        {
            Results = { Entry(), Entry() },
            Sources = new RegistrySources { Official = 40, Smithery = 22, Merged = 47 },
        };
        Assert.Equal("Official registry · Smithery · 2 servers", RegistryPresentation.Subtitle(response));
    }

    // ----------------------------------------------------------------- the notes footer

    [Fact]
    public void TrendingRefusalIsAlwaysStated()
    {
        // The brief's conditional — a trending row carries a window and a signed delta, or it is
        // not drawn as trending — resolves to "not drawn" for every row this data can produce,
        // because nothing keeps history. The board says so, always.
        var notes = RegistryPresentation.FooterNotes(new RegistrySearchResponse { Results = { Entry() } });
        Assert.Contains(DiscoverCopy.TrendingNote, notes);

        var emptyNotes = RegistryPresentation.FooterNotes(new RegistrySearchResponse());
        Assert.Contains(DiscoverCopy.TrendingNote, emptyNotes);
    }

    [Fact]
    public void TruncationIsDisclosedOnlyWhenItHappened()
    {
        var truncated = RegistryPresentation.FooterNotes(new RegistrySearchResponse
        {
            Results = { Entry() },
            Sources = new RegistrySources { Official = 40, Smithery = 22, Merged = 47 },
        });
        Assert.Contains(truncated, notes => notes.Contains("Showing the first 1 matches", StringComparison.Ordinal));

        var whole = RegistryPresentation.FooterNotes(new RegistrySearchResponse { Results = { Entry() } });
        Assert.DoesNotContain(whole, notes => notes.StartsWith("Showing the first", StringComparison.Ordinal));
    }

    [Fact]
    public void RankingBiasIsDisclosed()
    {
        var notes = RegistryPresentation.FooterNotes(new RegistrySearchResponse());
        Assert.Contains(DiscoverCopy.RankingNote, notes);
    }

    [Theory]
    [InlineData("official registry unreachable: HTTP 503", "Showing Smithery only.")]
    [InlineData("Smithery unreachable: HTTP 502", "Showing the official registry only.")]
    [InlineData("GitHub rate limit reached; star counts are partial.", "Repository details are incomplete.")]
    [InlineData("GitHub allows 60 requests an hour without a token, so star counts are partial.", "Repository details are incomplete.")]
    public void KnownWarningsClassifyToTheirSentence(string warning, string headline)
    {
        var (gotHeadline, body) = RegistryPresentation.Expand(warning);
        Assert.Equal(headline, gotHeadline);
        Assert.False(string.IsNullOrEmpty(body));
    }

    [Fact]
    public void UnrecognisedWarningRendersVerbatimRatherThanBeingDropped()
    {
        const string strange = "the registry had a bad day";
        var (headline, body) = RegistryPresentation.Expand(strange);
        Assert.Equal(DiscoverCopy.PartialUnrecognisedHeadline, headline);
        Assert.Contains(strange, body);
    }

    // ----------------------------------------------------------------- empties and states

    [Fact]
    public void EmptyWithoutQuerySaysNeitherIndexListedAnything()
    {
        var message = RegistryPresentation.EmptyMessageFor(new RegistrySearchResponse(), query: "");
        Assert.NotNull(message);
        Assert.Equal(DiscoverCopy.EmptyNoQueryHeadline, message!.Headline);
        Assert.False(message.ClearsSearch);
    }

    [Fact]
    public void EmptyWithQueryEchoesSanitisedCappedQuery()
    {
        var message = RegistryPresentation.EmptyMessageFor(new RegistrySearchResponse(), query: "postgres");
        Assert.NotNull(message);
        Assert.Contains("postgres", message!.Headline);
        Assert.True(message.ClearsSearch);
    }

    [Fact]
    public void RateLimitedEmptySearchDrawsPartialNeverEmpty()
    {
        // THE BRIEF'S NAMED WORST STATE: a rate-limited or unreachable registry draws as itself,
        // distinctly from "nothing found". A degraded search that returned nothing is partial.
        var degraded = new RegistrySearchResponse
        {
            Results = [],
            Warnings = ["official registry unreachable: HTTP 503", "Smithery unreachable: HTTP 502"],
        };
        Assert.Null(RegistryPresentation.EmptyMessageFor(degraded, query: ""));
        Assert.Equal(RegistryPresentation.ListStateKind.Partial, RegistryPresentation.Resolve(degraded, query: "", offline: false, failed: false));
    }

    [Fact]
    public void StateResolutionCoversTheMatrix()
    {
        var populated = new RegistrySearchResponse { Results = { Entry() } };
        Assert.Equal(RegistryPresentation.ListStateKind.Offline, RegistryPresentation.Resolve(populated, "", offline: true, failed: false));
        Assert.Equal(RegistryPresentation.ListStateKind.Failed, RegistryPresentation.Resolve(populated, "", offline: false, failed: true));
        Assert.Equal(RegistryPresentation.ListStateKind.Loading, RegistryPresentation.Resolve(null, "", offline: false, failed: false));
        Assert.Equal(RegistryPresentation.ListStateKind.Populated, RegistryPresentation.Resolve(populated, "", offline: false, failed: false));
        Assert.Equal(RegistryPresentation.ListStateKind.Partial, RegistryPresentation.Resolve(
            new RegistrySearchResponse
            {
                Results = { Entry() },
                Warnings = ["GitHub rate limit reached; star counts are partial."],
            }, "", offline: false, failed: false));
        Assert.Equal(RegistryPresentation.ListStateKind.EmptyNoQuery, RegistryPresentation.Resolve(new RegistrySearchResponse(), "", offline: false, failed: false));
        Assert.Equal(RegistryPresentation.ListStateKind.EmptyQuery, RegistryPresentation.Resolve(new RegistrySearchResponse(), "postgres", offline: false, failed: false));
    }

    [Fact]
    public void PartialBeatsPopulatedWhenBothAreTrue()
    {
        // Results arrived AND a warning did: the board draws the warning band over the results.
        var partial = new RegistrySearchResponse
        {
            Results = { Entry() },
            Warnings = ["GitHub allows 60 requests an hour without a token, so star counts are partial."],
        };
        Assert.Equal(RegistryPresentation.ListStateKind.Partial, RegistryPresentation.Resolve(partial, "", offline: false, failed: false));
    }
}
