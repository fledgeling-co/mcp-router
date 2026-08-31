namespace MCPRouter.Shell.Live;

/// <summary>
/// One rendered row of the log, formatted once when the view refreshes. Plain data, no UI
/// types - the WinUI template binds to it, and the headless tests can hold it to the same
/// formatting the screen gets.
/// </summary>
public sealed record ActivityRowVm(
    string Key,
    string TimeText,
    string HarnessText,
    string ToolText,
    string DurationText,
    string ResultWord,
    CallResultKind ResultKind,
    string ToolTipText,
    string AutomationName)
{
    public static ActivityRowVm From(CallRecord record) => new(
        Key: record.Id,
        TimeText: ActivityFormatting.TimeOfDay(record.Ts),
        HarnessText: ActivityFormatting.HarnessName(record.Client),
        ToolText: record.NamespacedTool,
        DurationText: ActivityFormatting.Duration(record),
        ResultWord: ActivityFormatting.ResultWord(record),
        ResultKind: record.ResultKind,
        ToolTipText: record.NamespacedTool,
        AutomationName: ActivityFormatting.AccessibilityLabel(record));
}

/// <summary>One toggle in the per-harness tally: the word and the count on its face.</summary>
public sealed record HarnessTallyVm(string Key, string Label, int Calls, bool IsOn)
{
    public static HarnessTallyVm From(HarnessTally tally, bool isOn) =>
        new(tally.Key, tally.Label, tally.Calls, isOn);

    /// <summary>The face of the button: the mock's own shape - "Claude Code · 948".</summary>
    public string Face => $"{Label} · {Calls.ToString(System.Globalization.CultureInfo.InvariantCulture)}";
}
