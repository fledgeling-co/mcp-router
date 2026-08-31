using System.Globalization;
using System.Text;
using System.Text.Json;

namespace MCPRouter.Shell.Live;

/// <summary>
/// The two export shapes the Export… dialog offers, built from the records the board is showing.
///
/// This lives in the wire library rather than the view, for the reason the whole library does: an
/// export that escapes a comma or a quote wrongly writes a file nobody can reload, and that is
/// checkable headless. The visible slice arrives already filtered and window-capped, so what the
/// dialog says it writes - the calls on screen, in the order shown (spec-WIN5 §3.5) - is exactly
/// what these methods are handed.
/// </summary>
public static class ActivityExport
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        // The wire's own naming, so an exported line is the record as the router carried it.
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    private static readonly string[] CsvHeader =
        ["Time", "Harness", "Tool", "Duration (ms)", "Result", "Error"];

    /// <summary>
    /// One JSON object per line. The record as the wire carried it, plus the three values the
    /// board derives for it - the de-duplication <c>id</c>, the <c>namespacedTool</c> paste-string
    /// and the <c>resultKind</c> word - so a file written here reads back without the board.
    /// </summary>
    public static string ToJsonLines(IReadOnlyList<CallRecord> records)
    {
        var builder = new StringBuilder();
        foreach (var record in records)
        {
            builder.Append(JsonSerializer.Serialize(record, JsonOptions));
            builder.Append('\n');
        }

        return builder.ToString();
    }

    /// <summary>
    /// CSV over the same columns the board draws, plus the raw millisecond duration - the unit
    /// the router measures in, kept unrounded so the file carries the measurement and the screen
    /// carries the presentation. RFC 4180 quoting: a field containing a comma, a quote or a line
    /// break is quoted, and a quote inside it is doubled.
    /// </summary>
    public static string ToCsv(IReadOnlyList<CallRecord> records)
    {
        var builder = new StringBuilder();
        AppendCsvRow(builder, CsvHeader);
        foreach (var record in records)
        {
            AppendCsvRow(builder,
            [
                ActivityFormatting.TimeOfDay(record.Ts),
                ActivityFormatting.HarnessName(record.Client),
                record.NamespacedTool,
                record.Ms.ToString(CultureInfo.InvariantCulture),
                ActivityFormatting.ResultWord(record),
                record.Err ?? string.Empty,
            ]);
        }

        return builder.ToString();
    }

    private static void AppendCsvRow(StringBuilder builder, IReadOnlyList<string> cells)
    {
        for (var i = 0; i < cells.Count; i++)
        {
            if (i > 0) builder.Append(',');
            var cell = cells[i];
            var quote = cell.Contains('"') || cell.Contains(',') || cell.Contains('\n')
                || cell.Contains('\r');
            if (quote)
            {
                builder.Append('"').Append(cell.Replace("\"", "\"\"")).Append('"');
            }
            else
            {
                builder.Append(cell);
            }
        }

        builder.Append("\r\n");
    }
}
