namespace MCPRouter.Shell.Model.Ambient;

/// <summary>
/// What the ambient surface knows about the router, and the only thing the flyout, the pane
/// readout and the notification-area tip render from.
/// </summary>
/// <remarks>
/// It starts at <see cref="AmbientRouterState.Unknown"/> and it is <b>not</b> a state anything can
/// be driven to on purpose: it is where the model sits until something has read the router. That
/// is DEF-301's fix in one line - the surface used to open at <see cref="AmbientRouterState.AtRest"/>
/// with no reader in the build at all.
/// </remarks>
public sealed class AmbientSurfaceModel
{
    public AmbientRouterState State { get; private set; } = AmbientRouterState.Unknown;
    public int WaitingCount { get; private set; }
    public int ActiveCallCount { get; private set; }

    /// <summary>When a reading was last applied, or null while nothing has read the router.</summary>
    public DateTimeOffset? LastReadAt { get; private set; }

    /// <summary>Whether anything has ever read the router into this model.</summary>
    public bool HasReading => LastReadAt is not null;

    public void UpdateState(AmbientRouterState state, int waitingCount = 0, int activeCalls = 0)
        => Apply(new AmbientReading(state, waitingCount, activeCalls));

    /// <summary>
    /// Take a reading. Returns true when the rendered state actually moved, so a caller can
    /// refresh the notification-area tip only when there is something new to say.
    /// </summary>
    public bool Apply(AmbientReading reading, DateTimeOffset? readAt = null)
    {
        var changed = State != reading.State
            || WaitingCount != reading.WaitingCount
            || ActiveCallCount != reading.ActiveCallCount;

        State = reading.State;
        WaitingCount = reading.WaitingCount;
        ActiveCallCount = reading.ActiveCallCount;
        LastReadAt = readAt ?? DateTimeOffset.UtcNow;
        return changed;
    }

    public AmbientStatusInfo GetStatusInfo(string? endpoint = null)
    {
        return new AmbientStatusInfo(
            State: State,
            StatusText: AmbientPresentation.StateTitle(State),
            Subtitle: AmbientPresentation.StateDetail(State, WaitingCount, ActiveCallCount, endpoint),
            WaitingCount: WaitingCount,
            ActiveCallCount: ActiveCallCount
        );
    }
}
