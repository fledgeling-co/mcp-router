using System.Text.Json;

namespace MCPRouter.Shell.Model.Ambient;

/// <summary>
/// One reading of the router, taken from outside this application's own memory.
/// </summary>
/// <remarks>
/// DEF-301 is the reason this type exists. <see cref="AmbientSurfaceModel"/> initialised to
/// <see cref="AmbientRouterState.AtRest"/> and nothing in the build ever called
/// <c>UpdateState</c>, so the ambient surface said "Router ready" whatever the router was doing -
/// including when it was not running at all. A reading carries where it came from, so a state on
/// screen can always be traced to something that was read.
/// </remarks>
/// <param name="State">The state the surface is to render.</param>
/// <param name="WaitingCount">Upstreams the router says are waiting for a sign-in decision.</param>
/// <param name="ActiveCallCount">Tool calls the router says are in flight.</param>
public sealed record AmbientReading(
    AmbientRouterState State,
    int WaitingCount = 0,
    int ActiveCallCount = 0)
{
    /// <summary>The reading taken when the router could not be reached at all.</summary>
    public static AmbientReading Unreachable { get; } = new(AmbientRouterState.CannotReachRouter);
}

/// <summary>Whatever can answer "what is the router doing", for the surface to render.</summary>
public interface IAmbientRouterReader
{
    /// <summary>
    /// Read the router. Never throws: a router that cannot be reached is a state this surface has
    /// a wording for, not an error for the caller to handle.
    /// </summary>
    Task<AmbientReading> ReadAsync(CancellationToken cancellation = default);
}

/// <summary>
/// The router's own <c>/status</c> document, turned into a reading.
/// </summary>
/// <remarks>
/// Kept apart from the HTTP call so the mapping can be exercised over documents the router really
/// answers with, rather than only over a running router. The shapes are
/// <c>src/router.ts</c>'s <c>/status</c>: <c>children[].inFlight</c> is the pool's own count of
/// calls it is serving, and <c>pendingAuth</c> is its list of upstreams waiting for the operator
/// to sign in.
/// </remarks>
public static class AmbientStatusMapping
{
    /// <summary>
    /// Map a <c>/status</c> body to a reading. Returns <see cref="AmbientReading.Unreachable"/>
    /// for a body this version cannot read: an answer that cannot be understood is not evidence
    /// the router is idle.
    /// </summary>
    public static AmbientReading FromStatusJson(string body)
    {
        int inFlight;
        int pending;
        try
        {
            using var document = JsonDocument.Parse(body);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return AmbientReading.Unreachable;

            inFlight = 0;
            if (root.TryGetProperty("children", out var children)
                && children.ValueKind == JsonValueKind.Array)
            {
                foreach (var child in children.EnumerateArray())
                {
                    if (child.ValueKind == JsonValueKind.Object
                        && child.TryGetProperty("inFlight", out var value)
                        && value.TryGetInt32(out var count)
                        && count > 0)
                    {
                        inFlight += count;
                    }
                }
            }

            pending = 0;
            if (root.TryGetProperty("pendingAuth", out var waiting)
                && waiting.ValueKind == JsonValueKind.Array)
            {
                pending = waiting.GetArrayLength();
            }
        }
        catch (JsonException)
        {
            return AmbientReading.Unreachable;
        }

        // A decision the operator has to take outranks work the router is doing on its own: the
        // waiting upstream is the thing that will not finish without them.
        if (pending > 0) return new AmbientReading(AmbientRouterState.SomethingWaiting, pending, inFlight);
        if (inFlight > 0) return new AmbientReading(AmbientRouterState.Working, 0, inFlight);
        return new AmbientReading(AmbientRouterState.AtRest);
    }
}
