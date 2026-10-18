using Xunit;

namespace MCPRouter.Shell.Live.Tests;

/// <summary>
/// The words the board draws that come from a record: the design of record's duration units,
/// the local time-of-day, the paste-string tool name, the result vocabulary, and the row a
/// screen reader is handed.
/// </summary>
public sealed class ActivityFormattingTests
{
    [Theory]
    [InlineData(0, "0 ms")]
    [InlineData(612, "612 ms")]
    [InlineData(999, "999 ms")]
    [InlineData(1000, "1.00 s")]
    [InlineData(1940, "1.94 s")]
    [InlineData(9999, "10.0 s")]
    [InlineData(10_000, "10.0 s")]
    [InlineData(30_000, "30.0 s")]
    public void Durations_render_in_the_design_of_record_s_units(int ms, string expected)
    {
        Assert.Equal(expected, ActivityFormatting.Duration(ms));
    }

    [Fact]
    public void A_held_call_has_no_duration_yet()
    {
        Assert.Equal("—", ActivityFormatting.Duration(0, CallResultKind.Held));
    }

    [Fact]
    public void The_time_of_day_is_the_reader_s_clock()
    {
        // 10:48:29Z on a machine running UTC+10 in August (AEST, no DST) is 20:48:29 local.
        // Asserted as a mapping rather than a literal so the test survives a machine whose
        // zone differs: the VALUE is local, whatever local is.
        var utc = "2026-08-31T10:48:29.720Z";
        var expected = DateTimeOffset.Parse(utc).LocalDateTime.ToString("HH:mm:ss");

        Assert.Equal(expected, ActivityFormatting.TimeOfDay(utc));
    }

    [Fact]
    public void A_timestamp_that_cannot_be_parsed_is_drawn_as_it_arrived()
    {
        Assert.Equal("not-a-timestamp", ActivityFormatting.TimeOfDay("not-a-timestamp"));
    }

    [Theory]
    [InlineData("claude", "Claude Code")]
    [InlineData("codex", "Codex")]
    [InlineData("cursor", "Cursor")]
    [InlineData("gemini", "Gemini CLI")]
    [InlineData("grok", "Grok")]
    [InlineData("node", "node")]
    [InlineData(null, "Unattributed")]
    [InlineData("", "Unattributed")]
    public void Harness_names_name_what_was_discovered(string? client, string expected)
    {
        Assert.Equal(expected, ActivityFormatting.HarnessName(client));
    }

    [Fact]
    public void The_tool_name_is_the_paste_string()
    {
        var record = new CallRecord("2026-08-31T10:00:00Z", "obscura", "browser_navigate", true, 100, false);

        Assert.Equal("obscura__browser_navigate", record.NamespacedTool);
    }

    [Theory]
    [InlineData(true, null, "ok")]
    [InlineData(false, "The request timed out", "timeout")]
    [InlineData(false, "upstream exited (timeout after 60000ms)", "timeout")]
    [InlineData(false, "unknown upstream server \"x\"", "failed")]
    [InlineData(false, null, "failed")]
    public void Result_words_classify_what_the_wire_carries(bool ok, string? err, string expected)
    {
        var record = new CallRecord("2026-08-31T10:00:00Z", "s", "t", ok, 100, false, Err: err);

        Assert.Equal(expected, ActivityFormatting.ResultWord(record));
    }

    [Fact]
    public void The_held_word_exists_in_the_vocabulary_even_though_nothing_produces_it()
    {
        // No field on this wire classifies a call as held (spec-WIN5 §3.2). The word is part
        // of the board's vocabulary because the design of record names it, and this pins the
        // word it would draw, so the day the wire carries a held call the column cannot
        // invent a different one.
        Assert.Equal("held", ActivityFormatting.ResultWord(CallResultKind.Held));
        Assert.Equal(CallResultKind.Ok, new CallRecord(
            "2026-08-31T10:00:00Z", "s", "t", true, 0, false).ResultKind);
    }

    [Fact]
    public void The_screen_reader_s_row_leads_with_the_outcome()
    {
        var record = new CallRecord(
            "2026-08-31T10:00:00Z", "docker-mcp", "list-containers", false, 30_000, Cold: true,
            Pid: 4242, Client: "claude", Err: "The request timed out");

        var label = ActivityFormatting.AccessibilityLabel(record);

        Assert.StartsWith("timeout", label);
        Assert.Contains("docker-mcp__list-containers", label);
        Assert.Contains("Claude Code", label);
        Assert.Contains("30.0 s", label);
        Assert.Contains("cold", label);
        Assert.Contains("The request timed out", label);
    }
}
