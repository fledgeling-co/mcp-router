using System.Text.RegularExpressions;
using Xunit;

namespace MCPRouter.Shell.Live.Tests;

/// <summary>
/// DESIGN.md §11 rule 2 on every string this board renders, and DESIGN.md §6's honesty rule in
/// both directions: no figure a wire field does not support, and the unhappy-path copy is the
/// spec's, not a paraphrase (spec-WIN5 §4).
/// </summary>
public sealed class ActivityCopyTests
{
    private static readonly HashSet<string> ProperNouns = new(StringComparer.Ordinal)
    {
        "MCP",
        "Router",
        "JSON",
        "CSV",
        "Windows",
        "PC",
    };

    /// <summary>Every string the board can put on screen.</summary>
    public static IEnumerable<object[]> AllSentences()
    {
        yield return new object[] { "mission", ActivityCopy.Mission };
        yield return new object[] { "foot", ActivityCopy.Foot };
        yield return new object[] { "empty title", ActivityCopy.EmptyTitle };
        yield return new object[] { "empty detail", ActivityCopy.EmptyDetail };
        yield return new object[] { "empty action", ActivityCopy.EmptyAction };
        yield return new object[] { "loading", ActivityCopy.LoadingStatus };
        yield return new object[] { "offline title", ActivityCopy.OfflineTitle };
        yield return new object[] { "offline detail", ActivityCopy.OfflineDetail };
        yield return new object[] { "reconnect", ActivityCopy.ReconnectLabel };
        yield return new object[] { "reconnect now", ActivityCopy.ReconnectNowLabel };
        yield return new object[] { "partial title", ActivityCopy.PartialReconnectingTitle };
        yield return new object[] { "disconnected title", ActivityCopy.DisconnectedTitle };
        yield return new object[] { "never connected title", ActivityCopy.NeverConnectedTitle };
        yield return new object[] { "never connected detail", ActivityCopy.NeverConnectedDetail };
        yield return new object[] { "filtered title", ActivityCopy.FilteredTitle };
        yield return new object[] { "clear filters", ActivityCopy.ClearFiltersLabel };
        yield return new object[] { "held title", ActivityCopy.HeldNothingTitle };
        yield return new object[] { "held detail", ActivityCopy.HeldNothingDetail };
        yield return new object[] { "pause", ActivityCopy.PauseLabel };
        yield return new object[] { "resume", ActivityCopy.ResumeLabel };
        yield return new object[] { "export", ActivityCopy.ExportLabel };
        yield return new object[] { "export dialog title", ActivityCopy.ExportDialogTitle };
        yield return new object[] { "export dialog detail", ActivityCopy.ExportDialogDetail };
        yield return new object[] { "export json", ActivityCopy.ExportJson };
        yield return new object[] { "export csv", ActivityCopy.ExportCsv };
        yield return new object[] { "export confirm", ActivityCopy.ExportConfirm };
        yield return new object[] { "export cancel", ActivityCopy.ExportCancel };
        yield return new object[] { "newest sentence", ActivityCopy.NewestSentence("2026-08-31T10:00:00Z") };
        yield return new object[] { "newest none", ActivityCopy.NewestSentence(null) };
        yield return new object[] { "disconnected detail", ActivityCopy.DisconnectedDetail(null) };
        yield return new object[] { "filtered detail", ActivityCopy.FilteredDetail(9) };
        yield return new object[] { "subtitle", ActivityCopy.Subtitle(4, "live") };
        yield return new object[] { "filtered count", ActivityCopy.FilteredCount(2, 9) };
        yield return new object[] { "paused arrivals 1", ActivityCopy.CallsArrivedWhilePaused(1) };
        yield return new object[] { "paused arrivals 4", ActivityCopy.CallsArrivedWhilePaused(4) };
        foreach (var column in ActivityCopy.Columns) yield return new object[] { $"column {column}", column };
        foreach (var filter in ActivityCopy.Filters) yield return new object[] { $"filter {filter}", filter };
    }

    [Theory]
    [MemberData(nameof(AllSentences))]
    public void Every_sentence_is_sentence_case(string owner, string sentence)
    {
        Assert.False(string.IsNullOrWhiteSpace(sentence), $"{owner} is empty");

        // Several of these strings are two or three sentences in one constant, and a capital
        // that opens a new sentence is sentence case doing its job. Split on the boundaries
        // first, then hold each unit to the rule.
        var units = Regex.Split(sentence, "(?<=[.!?])\\s+")
            .Where(u => u.Length > 0)
            .ToList();

        foreach (var unit in units)
        {
            var words = Regex.Split(unit, @"\s+")
                .Select(w => w.Trim('…', '.', ',', '?', '!', '(', ')', ':', ';', '"', '“', '”'))
                .Where(w => w.Length > 0)
                .ToList();

            Assert.True(char.IsUpper(words[0][0]) || ProperNouns.Contains(words[0])
                    || char.IsDigit(words[0][0]),
                $"{owner}: '{unit}' in '{sentence}' does not start with a capital");

            foreach (var word in words.Skip(1))
            {
                if (!char.IsUpper(word[0])) continue;
                Assert.True(ProperNouns.Contains(word),
                    $"{owner}: '{unit}' in '{sentence}' capitalises '{word}' mid-sentence - §11 rule 2 is sentence case, with no menu carve-out on Windows");
            }
        }
    }

    [Fact]
    public void The_columns_are_the_brief_s_five_in_order()
    {
        Assert.Equal(new[] { "Time", "Harness", "Tool", "Duration", "Result" }, ActivityCopy.Columns);
    }

    [Fact]
    public void The_filters_are_the_design_of_record_s_four_in_order()
    {
        Assert.Equal(new[] { "All", "Errors", "Slow (> 2 s)", "Held" }, ActivityCopy.Filters);
    }

    [Fact]
    public void No_sentence_claims_a_retention_figure_the_wire_does_not_carry()
    {
        // The mock's callout claims 90 days; no field on this wire says anything of the kind
        // (spec-WIN5 §6). The sweep covers every constant and every composed sentence.
        var all = AllSentences().Select(row => (string)row[1]).ToList();
        foreach (var sentence in all)
        {
            Assert.DoesNotContain("90 day", sentence);
            Assert.DoesNotContain("days", sentence);
        }
    }

    [Fact]
    public void No_sentence_claims_router_uptime_or_a_completeness_watermark()
    {
        var all = AllSentences().Select(row => (string)row[1]).ToList();
        foreach (var sentence in all)
        {
            Assert.DoesNotContain("since the router started", sentence);
            Assert.DoesNotContain("every call", sentence, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("nothing was missed", sentence, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public void The_offline_wording_is_the_mac_s_router_not_running_sentence()
    {
        // §6's one name per state: the wording is ControlAPIError.routerNotRunning's, carried
        // across platforms. Only the action differs, and spec-WIN5 §3.6 records why.
        Assert.Equal("The router isn't running", ActivityCopy.OfflineTitle);
        Assert.StartsWith("Nothing is listening on the control port", ActivityCopy.OfflineDetail);
    }

    [Fact]
    public void The_feed_labels_are_one_phrase_per_phase()
    {
        Assert.Equal("connecting", ActivityCopy.FeedLabel(StreamPhase.Connecting, paused: false));
        Assert.Equal("live", ActivityCopy.FeedLabel(StreamPhase.Live, paused: false));
        Assert.Equal("reconnecting", ActivityCopy.FeedLabel(StreamPhase.Reconnecting, paused: false));
        Assert.Equal("no live feed", ActivityCopy.FeedLabel(StreamPhase.Disconnected, paused: false));
        // Pause is the view's state, and it outranks the feed's: the subtitle says what the
        // reader is looking at, and a paused reader is not looking at a live log.
        Assert.Equal("paused", ActivityCopy.FeedLabel(StreamPhase.Live, paused: true));
    }

    [Fact]
    public void The_subtitle_says_showing_never_a_total()
    {
        Assert.Equal("Showing 1 call · live", ActivityCopy.Subtitle(1, "live"));
        Assert.Equal("Showing 500 calls · reconnecting", ActivityCopy.Subtitle(500, "reconnecting"));
        Assert.Equal("3 of 28", ActivityCopy.FilteredCount(3, 28));
    }

    [Fact]
    public void The_pause_arrival_sentence_counts_what_was_actually_held()
    {
        Assert.Equal("1 call arrived while paused.", ActivityCopy.CallsArrivedWhilePaused(1));
        Assert.Equal("2 calls arrived while paused.", ActivityCopy.CallsArrivedWhilePaused(2));
    }
}
