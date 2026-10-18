using Xunit;

namespace MCPRouter.Shell.Live.Tests;

/// <summary>
/// The window, the pause, the filters and the tallies - the claims the board's numbers rest
/// on, none of which a capture could check.
/// </summary>
public sealed class ActivityModelTests
{
    private static CallRecord Record(string ts, string server = "s", string tool = "t", bool ok = true,
        int ms = 100, int? pid = 1, string? client = "claude", string? err = null) =>
        new(ts, server, tool, ok, ms, Cold: false, Pid: pid, Client: client, Err: err);

    [Fact]
    public void A_record_already_held_is_dropped_rather_than_shown_twice()
    {
        var model = new ActivityModel();
        var record = Record("2026-08-31T10:00:00Z");

        Assert.True(model.Prepend(record));
        Assert.False(model.Prepend(record), "the same call arrived on the stream twice");
        Assert.Single(model.Records);
    }

    [Fact]
    public void The_backfill_and_the_stream_overlapping_yields_one_window()
    {
        var model = new ActivityModel();
        model.Load(new[]
        {
            Record("2026-08-31T10:00:02Z"),
            Record("2026-08-31T10:00:01Z"),
        });

        model.Prepend(Record("2026-08-31T10:00:01Z"));

        Assert.Equal(2, model.Records.Count);
        Assert.Equal("2026-08-31T10:00:02Z", model.Records[0].Ts);
    }

    [Fact]
    public void The_window_holds_the_capacity_and_drops_the_oldest()
    {
        var model = new ActivityModel();
        for (var i = 0; i < ActivityModel.Capacity + 5; i++)
        {
            model.Prepend(Record($"2026-08-31T10:{i / 60:00}:{i % 60:00}.{i:000}", tool: $"t{i}"));
        }

        Assert.Equal(ActivityModel.Capacity, model.Records.Count);
        Assert.Equal("t504", model.Records[0].Tool);
        Assert.Equal("t5", model.Records[^1].Tool);
        // The id set travels with the drop, or the next duplicate of a dropped record would
        // be treated as new.
        Assert.True(model.Prepend(Record("2026-08-31T10:00:00.000", tool: "t504")));
    }

    [Fact]
    public void Pause_holds_the_view_without_dropping_what_arrives()
    {
        var model = new ActivityModel();
        model.Prepend(Record("2026-08-31T10:00:01Z", tool: "before"));

        model.SetPaused(true);
        model.Prepend(Record("2026-08-31T10:00:02Z", tool: "while1"));
        model.Prepend(Record("2026-08-31T10:00:03Z", tool: "while2"));
        Assert.Equal(2, model.RecordsWhilePaused);

        // The window itself never stopped: resume is a refresh, not a catch-up fetch.
        model.SetPaused(false);
        Assert.Equal(0, model.RecordsWhilePaused);
        Assert.Equal(3, model.Records.Count);
        Assert.Equal("while2", model.Records[0].Tool);
    }

    [Fact]
    public void A_duplicate_during_pause_does_not_inflate_the_arrived_count()
    {
        var model = new ActivityModel();
        var record = Record("2026-08-31T10:00:01Z");
        model.Prepend(record);

        model.SetPaused(true);
        Assert.False(model.Prepend(record));

        Assert.Equal(0, model.RecordsWhilePaused);
    }

    [Fact]
    public void The_filters_admit_what_their_words_name()
    {
        var model = new ActivityModel();
        // Newest first, which is the order GET /usage and the stream deliver in.
        model.Load(new[]
        {
            Record("2026-08-31T10:00:04Z", tool: "slow-timeout", ok: false, ms: 30_000, err: "The request timed out"),
            Record("2026-08-31T10:00:03Z", tool: "fast-fail", ok: false, ms: 40, err: "connection closed"),
            Record("2026-08-31T10:00:02Z", tool: "slow-ok", ms: 3_000),
            Record("2026-08-31T10:00:01Z", tool: "fast-ok", ms: 40),
        });

        model.Filter = ResultFilter.All;
        Assert.Equal(4, model.VisibleRows().Count);

        model.Filter = ResultFilter.Errors;
        Assert.Equal(new[] { "slow-timeout", "fast-fail" }, model.VisibleRows().Select(r => r.Tool));

        model.Filter = ResultFilter.Slow;
        Assert.Equal(new[] { "slow-timeout", "slow-ok" }, model.VisibleRows().Select(r => r.Tool));

        // Nothing on this wire is held; the filter exists and matches nothing (spec §3.2).
        model.Filter = ResultFilter.Held;
        Assert.Empty(model.VisibleRows());
    }

    [Fact]
    public void The_slow_threshold_is_two_seconds_exclusive()
    {
        var model = new ActivityModel { Filter = ResultFilter.Slow };
        model.Load(new[]
        {
            Record("2026-08-31T10:00:01Z", tool: "exactly", ms: 2_000),
            Record("2026-08-31T10:00:02Z", tool: "over", ms: 2_001),
        });

        Assert.Equal(new[] { "over" }, model.VisibleRows().Select(r => r.Tool));
    }

    [Fact]
    public void The_tallies_count_the_result_filter_per_harness()
    {
        var model = new ActivityModel { Filter = ResultFilter.Errors };
        model.Load(new[]
        {
            Record("2026-08-31T10:00:01Z", ok: false, client: "claude", err: "x"),
            Record("2026-08-31T10:00:02Z", ok: true, client: "claude"),
            Record("2026-08-31T10:00:03Z", ok: false, client: "cursor", err: "y"),
        });

        var tallies = model.Tallies();

        // The ok record is behind the Errors filter, so neither harness may count it here -
        // this is the agreement the brief asks the tallies to keep with the rows.
        Assert.Equal(2, tallies.Count);
        Assert.All(tallies, t => Assert.Equal(1, t.Calls));
    }

    [Fact]
    public void An_unattributed_record_is_one_tally_row_named_once()
    {
        var model = new ActivityModel();
        model.Load(new[]
        {
            Record("2026-08-31T10:00:01Z", client: null),
            Record("2026-08-31T10:00:02Z", client: ""),
        });

        var tally = Assert.Single(model.Tallies());
        Assert.Equal("Unattributed", tally.Label);
        Assert.Equal(2, tally.Calls);
    }

    [Fact]
    public void Toggling_a_harness_hides_its_rows_and_keeps_the_window()
    {
        var model = new ActivityModel();
        model.Load(new[]
        {
            Record("2026-08-31T10:00:01Z", client: "claude"),
            Record("2026-08-31T10:00:02Z", client: "cursor"),
        });
        model.SetHarnessIncluded("claude", included: false);

        Assert.Equal(new[] { "cursor" }, model.VisibleRows().Select(r => r.Client));

        // Hidden, never deleted: the tally still counts what the toggle is hiding.
        Assert.Equal(2, model.Records.Count);
        model.SetHarnessIncluded("claude", included: true);
        Assert.Equal(2, model.VisibleRows().Count);
    }

    [Fact]
    public void Filtered_to_nothing_is_not_the_same_as_empty()
    {
        var empty = new ActivityModel();
        Assert.False(empty.IsFilteredToNothing());

        var populated = new ActivityModel();
        populated.Load(new[] { Record("2026-08-31T10:00:01Z", ok: true) });
        populated.Filter = ResultFilter.Errors;
        Assert.True(populated.IsFilteredToNothing());
    }

    [Fact]
    public void The_tallies_order_by_count_then_name()
    {
        var model = new ActivityModel();
        model.Load(new[]
        {
            Record("2026-08-31T10:00:01Z", client: "cursor"),
            Record("2026-08-31T10:00:02Z", client: "claude"),
            Record("2026-08-31T10:00:03Z", client: "claude"),
            Record("2026-08-31T10:00:04Z", client: "zz-custom"),
        });

        Assert.Equal(new[] { "Claude Code", "Cursor", "zz-custom" },
            model.Tallies().Select(t => t.Label));
    }
}
