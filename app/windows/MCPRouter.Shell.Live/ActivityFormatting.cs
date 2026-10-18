using System.Globalization;

namespace MCPRouter.Shell.Live;

/// <summary>
/// The words and shapes the board draws that come from a record rather than from a sentence:
/// duration units in the design of record's own, the local time-of-day, the paste-string tool
/// name, and the harness display name.
/// </summary>
public static class ActivityFormatting
{
    /// <summary>
    /// A duration as the design of record writes it: <c>612 ms</c>, <c>1.94 s</c>, <c>30.0 s</c>.
    ///
    /// The router measures in whole milliseconds, so this is presentation, never
    /// re-measurement: below one second the milliseconds stand as they arrived, one to ten
    /// seconds carries two decimals, and ten and above carries one - exactly the mock's own
    /// three shapes (spec-WIN5 §3.9).
    /// </summary>
    public static string Duration(CallRecord record) => Duration(record.Ms, record.ResultKind);

    public static string Duration(int ms, CallResultKind kind = CallResultKind.Failed)
    {
        // A held call has no duration yet - the design of record writes the em dash, and the
        // classification never fires on this wire today (spec-WIN5 §3.2), but the shape is
        // kept so the day the wire carries a held call the column does not invent a number.
        if (kind == CallResultKind.Held) return "—";
        if (ms < 1000) return $"{ms.ToString(CultureInfo.InvariantCulture)} ms";
        // The tier follows the ROUNDED seconds, not the raw count: 9 999 ms is "10.0 s",
        // because a column that wrote "9.99 s" beside one that wrote "10.0 s" would be
        // printing its own rounding as a measurement.
        var seconds = Math.Round(ms / 1000.0, 1);
        return (seconds < 10
                ? (ms / 1000.0).ToString("0.00", CultureInfo.InvariantCulture)
                : seconds.ToString("0.0", CultureInfo.InvariantCulture)) + " s";
    }

    /// <summary>The local time-of-day, in the column's own width. The wire's timestamp is ISO
    /// UTC; the board draws the reader's clock, because "which of my agents did that at
    /// 18:24" is answered in the reader's 18:24.</summary>
    public static string TimeOfDay(string ts)
    {
        // The round trip the wire actually promises: ISO 8601 with an offset or Z. A timestamp
        // this cannot parse is drawn as it arrived rather than as a fabricated 00:00:00 - a
        // wrong-looking time is honest, a plausible-looking wrong time is not.
        if (!DateTimeOffset.TryParse(ts, CultureInfo.InvariantCulture, DateTimeStyles.None, out var when))
        {
            return ts;
        }

        return when.LocalDateTime.ToString("HH:mm:ss", CultureInfo.InvariantCulture);
    }

    /// <summary>The harness display name: the product name where one is known, the executable
    /// name itself where not, and the one word for a record the router could not attribute.
    ///
    /// The dictionary names what was DISCOVERED; it never puts a harness on the board. A
    /// client the machine runs that is not in this table renders as itself and loses
    /// nothing.</summary>
    public static string HarnessName(string? client) => client switch
    {
        null or "" => "Unattributed",
        "claude" => "Claude Code",
        "codex" => "Codex",
        "cursor" => "Cursor",
        "gemini" => "Gemini CLI",
        "grok" => "Grok",
        "antigravity" => "Antigravity",
        "droid" => "Droid",
        "opencode" => "OpenCode",
        _ => client,
    };

    /// <summary>The row's Result word. One word per state, beside the mark, never hue alone
    /// (DESIGN.md §12: success against critical is 1.00:1 dark on Windows).</summary>
    public static string ResultWord(CallRecord record) => ResultWord(record.ResultKind);

    public static string ResultWord(CallResultKind kind) => kind switch
    {
        CallResultKind.Ok => "ok",
        CallResultKind.Timeout => "timeout",
        CallResultKind.Held => "held",
        _ => "failed",
    };

    /// <summary>The row's full value for a screen reader: outcome first, because it is the
    /// thing a listener most needs and the thing colour alone would otherwise carry. The
    /// Mac row's label shape, over the fields this wire carries.</summary>
    public static string AccessibilityLabel(CallRecord record)
    {
        var parts = new List<string>
        {
            ResultWord(record),
            record.NamespacedTool,
            $"on {record.Server}",
            ActivityFormatting.HarnessName(record.Client),
            Duration(record),
        };
        if (record.Cold) parts.Add("cold - this call is what started the server");
        if (!string.IsNullOrEmpty(record.Err)) parts.Add(record.Err);
        return string.Join(", ", parts);
    }
}
