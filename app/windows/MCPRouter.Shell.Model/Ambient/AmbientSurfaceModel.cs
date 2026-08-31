using System;

namespace MCPRouter.Shell.Model.Ambient;

public sealed class AmbientSurfaceModel
{
    public AmbientRouterState State { get; private set; } = AmbientRouterState.AtRest;
    public int WaitingCount { get; private set; } = 0;
    public int ActiveCallCount { get; private set; } = 0;

    public void UpdateState(AmbientRouterState state, int waitingCount = 0, int activeCalls = 0)
    {
        State = state;
        WaitingCount = waitingCount;
        ActiveCallCount = activeCalls;
    }

    public AmbientStatusInfo GetStatusInfo()
    {
        return new AmbientStatusInfo(
            State: State,
            StatusText: AmbientPresentation.StateTitle(State),
            Subtitle: AmbientPresentation.StateDetail(State, WaitingCount, ActiveCallCount),
            WaitingCount: WaitingCount,
            ActiveCallCount: ActiveCallCount
        );
    }
}
