using MCPRouter.Shell.Model.Registry;

namespace MCPRouter.Shell.Model.Ambient;

public static class AmbientPresentation
{
    public const string FlyoutTitle = "MCP Router";

    public static string StateTitle(AmbientRouterState state)
    {
        return state switch
        {
            AmbientRouterState.Unknown => "Reading the router",
            AmbientRouterState.AtRest => "Router ready",
            AmbientRouterState.Working => "Serving tool calls",
            AmbientRouterState.SomethingWaiting => "Decisions waiting",
            AmbientRouterState.CannotReachRouter => "Cannot reach router",
            _ => "Router"
        };
    }

    /// <param name="endpoint">
    /// The control endpoint this app is actually polling, for the sentence that names it. Null
    /// resolves it the way the rest of the app does. It used to be the literal
    /// <c>127.0.0.1:8879</c>, which named a port the client might never have called - the same
    /// defect the Servers board's <c>ClientPort</c> comment records.
    /// </param>
    public static string StateDetail(
        AmbientRouterState state, int waitingCount, int activeCalls, string? endpoint = null)
    {
        return state switch
        {
            AmbientRouterState.Unknown =>
                "Nothing has read the router yet.",
            AmbientRouterState.AtRest =>
                "All systems quiet. No active calls or queued items.",
            AmbientRouterState.Working => activeCalls == 1
                ? "1 active tool call in flight."
                : $"{activeCalls} active tool calls in flight.",
            // WORDED FROM WHAT IS COUNTED. The router's /status reports `pendingAuth`: upstreams
            // it cannot use until the operator signs in. The old sentence said "queued from your
            // phone waiting for review", which named a queue nothing in this build reads - a
            // second claim of the same kind DEF-301 is about.
            AmbientRouterState.SomethingWaiting => waitingCount == 1
                ? "1 server is waiting for you to sign in."
                : $"{waitingCount} servers are waiting for you to sign in.",
            AmbientRouterState.CannotReachRouter =>
                $"The router daemon is not responding on {endpoint ?? Endpoint()}.",
            _ => string.Empty
        };
    }

    private static string Endpoint()
    {
        try
        {
            return $"{ControlEndpoint.Host}:{ControlEndpoint.Port()}";
        }
        catch (Exception)
        {
            return $"{ControlEndpoint.Host}:{ControlEndpoint.DefaultPort}";
        }
    }

    public static string TrayToolTip(AmbientRouterState state, int waitingCount)
    {
        return state switch
        {
            AmbientRouterState.Unknown => "MCP Router",
            AmbientRouterState.AtRest => "MCP Router — Ready",
            AmbientRouterState.Working => "MCP Router — Working",
            AmbientRouterState.SomethingWaiting => $"MCP Router — {waitingCount} waiting",
            AmbientRouterState.CannotReachRouter => "MCP Router — Offline",
            _ => "MCP Router"
        };
    }
}
