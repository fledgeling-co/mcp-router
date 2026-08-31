namespace MCPRouter.Checks.Model;

/// <summary>
/// The Ran column's voice. Timestamps are instrument data (§12's Consolas cells carry counts,
/// stamps and durations), and "4 h ago" is the form the design of record uses — relative so the
/// column answers "how stale could this be" without a calendar.
/// </summary>
public static class RelativeTime
{
    public static string Ago(DateTimeOffset from, DateTimeOffset now)
    {
        var delta = now - from;
        if (delta < TimeSpan.Zero)
        {
            delta = TimeSpan.Zero;
        }

        return delta.TotalMinutes < 1 ? "just now"
            : delta.TotalHours < 1 ? $"{(int)delta.TotalMinutes} min ago"
            : delta.TotalDays < 1 ? $"{(int)delta.TotalHours} h ago"
            : delta.TotalDays < 7 ? $"{(int)delta.TotalDays} d ago"
            : from.ToString("yyyy-MM-dd");
    }
}
