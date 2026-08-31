using System;

namespace MCPRouter.Shell.Model.Ambient;

public static class AmbientPresentation
{
    public const string FlyoutTitle = "MCP Router";

    public static string StateTitle(AmbientRouterState state)
    {
        return state switch
        {
            AmbientRouterState.AtRest => "Router ready",
            AmbientRouterState.Working => "Serving tool calls",
            AmbientRouterState.SomethingWaiting => "Decisions waiting",
            AmbientRouterState.CannotReachRouter => "Cannot reach router",
            _ => "Router"
        };
    }

    public static string StateDetail(AmbientRouterState state, int waitingCount, int activeCalls)
    {
        return state switch
        {
            AmbientRouterState.AtRest => "All systems quiet. No active calls or queued items.",
            AmbientRouterState.Working => activeCalls == 1
                ? "1 active tool call in flight."
                : $"{activeCalls} active tool calls in flight.",
            AmbientRouterState.SomethingWaiting => waitingCount == 1
                ? "1 item queued from your phone waiting for review."
                : $"{waitingCount} items queued from your phone waiting for review.",
            AmbientRouterState.CannotReachRouter => "The router daemon is not responding on 127.0.0.1:8879.",
            _ => string.Empty
        };
    }

    public static string TrayToolTip(AmbientRouterState state, int waitingCount)
    {
        return state switch
        {
            AmbientRouterState.AtRest => "MCP Router — Ready",
            AmbientRouterState.Working => "MCP Router — Working",
            AmbientRouterState.SomethingWaiting => $"MCP Router — {waitingCount} waiting",
            AmbientRouterState.CannotReachRouter => "MCP Router — Offline",
            _ => "MCP Router"
        };
    }
}
