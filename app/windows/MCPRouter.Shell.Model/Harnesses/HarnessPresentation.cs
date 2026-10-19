using System;
using System.Globalization;

namespace MCPRouter.Shell.Model.Harnesses;

public static class HarnessPresentation
{
    public const string Title = "Harnesses";
    public const string BoardDescription = "Which AI tools on this PC actually route through here. Pointing a harness at the endpoint is the easy half; the half that saves anything is noticing it still spawns its own copies.";

    public const string EmptyTitle = "No AI harnesses found";
    public const string EmptyBody = "Nothing on this PC looks like an agent CLI or editor that speaks MCP. If one is installed somewhere unusual, the router reads the standard configuration paths only.";
    public const string ScopeNote = "Global configuration only — a server declared inside one project is not read here.";
    public const string NoConfigNote = "No config file at this path.";

    /// <summary>The reading a wire state word names. The wire admits only the four words mapped here
    /// (<see cref="MCPRouter.Shell.Model.Servers.HarnessStateWire"/>), so a miss is a programming error rather than data.</summary>
    public static HarnessReading ReadingOf(string state) => state switch
    {
        "not-wired" => HarnessReading.NotRouted,
        "wired-http" => HarnessReading.RoutedOverHTTP,
        "wired-shim" => HarnessReading.RoutedViaShim,
        "wired-with-duplicates" => HarnessReading.RoutedWithDirectServers,
        _ => throw new ArgumentOutOfRangeException(nameof(state), state, "not a harness state the router sends"),
    };

    public static string StateLabel(HarnessReading state)
    {
        return state switch
        {
            HarnessReading.NotRouted => "Not routed",
            HarnessReading.RoutedOverHTTP => "Routed (HTTP)",
            HarnessReading.RoutedViaShim => "Routed (stdio shim)",
            HarnessReading.RoutedWithDirectServers => "Double-running",
            _ => state.ToString()
        };
    }

    public static string DoubleRunningWarning(int count)
    {
        var noun = count == 1 ? "server" : "servers";
        return $"{count} {noun} declared directly here that this router already fronts.";
    }

    /// <summary>The time the reading was taken, in this machine's clock. The router stamps it in UTC.</summary>
    public static string ReadAtNote(string readAt) => $"Read at {ShownAt(readAt)}.";

    /// <summary>
    /// The row's file could not be read. Its counts are the empty report, which is the same bytes a
    /// clean unwired harness produces, so the note says so rather than letting zero stand for a
    /// measurement.
    /// </summary>
    public static string UnreadableNote(string reason) =>
        $"This file couldn't be read ({reason}), so its counts are empty, not zero. Nothing about this harness is measured.";

    /// <summary>
    /// A read failed after an earlier one answered. The earlier rows stay, and the note says what
    /// they are: the reading from that time, under a failure this read hit.
    /// </summary>
    public static string StaleNote(string readAt, string headline) =>
        $"{headline}. Showing the reading from {ShownAt(readAt)}; the rows may no longer match the files.";

    private static string ShownAt(string readAt) =>
        DateTimeOffset.TryParse(readAt, CultureInfo.InvariantCulture, DateTimeStyles.None, out var at)
            ? at.ToLocalTime().ToString("HH:mm:ss", CultureInfo.InvariantCulture)
            : readAt;
}
