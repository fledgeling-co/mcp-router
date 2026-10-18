namespace MCPRouter.Shell.Model.Ambient;

public enum AmbientRouterState
{
    /// <summary>
    /// Nothing has read the router yet, and the surface says exactly that.
    /// </summary>
    /// <remarks>
    /// FIRST, so that <c>default(AmbientRouterState)</c> is this one. DEF-301: the default was
    /// <see cref="AtRest"/>, nothing ever called <c>UpdateState</c>, and the ambient surface
    /// therefore reported "Router ready" over a router that was not running. A default that means
    /// "not yet read" cannot be mistaken for a reading, and a surface that renders it says so.
    /// </remarks>
    Unknown,

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
