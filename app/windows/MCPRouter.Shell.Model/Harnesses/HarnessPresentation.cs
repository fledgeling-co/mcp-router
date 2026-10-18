using System;

namespace MCPRouter.Shell.Model.Harnesses;

public static class HarnessPresentation
{
    public const string Title = "Harnesses";
    public const string BoardDescription = "Which AI tools on this PC actually route through here. Pointing a harness at the endpoint is the easy half; the half that saves anything is noticing it still spawns its own copies.";

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
}
