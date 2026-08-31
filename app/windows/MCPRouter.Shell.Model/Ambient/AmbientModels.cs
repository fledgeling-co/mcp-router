using System;

namespace MCPRouter.Shell.Model.Ambient;

public enum AmbientRouterState
{
    AtRest,
    Working,
    SomethingWaiting,
    CannotReachRouter
}

public sealed record AmbientStatusInfo(
    AmbientRouterState State,
    string StatusText,
    string Subtitle,
    int WaitingCount,
    int ActiveCallCount
);
