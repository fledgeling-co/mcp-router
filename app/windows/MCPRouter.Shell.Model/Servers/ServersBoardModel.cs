namespace MCPRouter.Shell.Model.Servers;

/// <summary>What the last poll attempt left the board holding.</summary>
public enum BoardLoad
{
    /// <summary>No poll has answered yet.</summary>
    Loading,

    /// <summary>The last poll answered.</summary>
    Loaded,

    /// <summary>An earlier poll answered; the latest did not. The reading stays — a refresh that
    /// did not complete is not evidence the router moved — and present-tense claims freeze.</summary>
    Stale,

    /// <summary>No poll has ever answered. The disconnected surface.</summary>
    Failed,
}

/// <summary>
/// Which dot the Signal Path's harness column draws, from the harness row's own state word.
/// Colour never carries this alone — every dot sits beside the harness's display name and its
/// own state word, which on Windows is the only channel some users have (§12's 1.00:1 finding).
/// </summary>
public enum DotTone
{
    /// <summary>Wired to the router: <c>wired-http</c> or <c>wired-shim</c>.</summary>
    Lit,

    /// <summary>Wired but duplicating entries: <c>wired-with-duplicates</c> — a thing a person
    /// should look at.</summary>
    Caution,

    /// <summary>Not wired: <c>not-wired</c>. A socket rather than a failure.</summary>
    Off,

    /// <summary>The harness's config exists and could not be read. Unreadable is the member a
    /// consumer reads first, and every other member of such a row is the empty report.</summary>
    Critical,
}

/// <summary>
/// The Servers board's readings, derived in one place so no two views of the same envelope can
/// disagree.
///
/// <para>Holds no server data and performs no I/O — everything is a pure function of an envelope
/// the client answered with, or of the failure it answered with instead. The router's order is
/// kept rather than sorted: it is the order the config declares, which is the order the user
/// wrote, and a list that reorders itself as servers start and stop is a list nobody can point
/// at.</para>
/// </summary>
public static class ServersBoardModel
{
    /// <summary>The topology line's three counts: declared harnesses, the one endpoint, declared
    /// upstreams — every figure from an envelope, never a constant. Counts of one stay
    /// grammatical: "1 harness", "1 upstream".</summary>
    public static string Topology(int harnessCount, ServersEnvelope envelope)
    {
        var upstreams = envelope.Servers.Count;
        return $"{harnessCount} {(harnessCount == 1 ? "harness" : "harnesses")}"
             + " → 1 endpoint → "
             + $"{upstreams} {(upstreams == 1 ? "upstream" : "upstreams")}";
    }

    /// <summary>Servers whose child is up and idle: the hub's `<n> at rest` line. A running
    /// server with calls in flight is awake, not at rest, and the jack's lit plug already says
    /// so.</summary>
    public static int AtRestCount(ServersEnvelope envelope) =>
        envelope.Servers.Count(s => s.IsRunning && s.InFlight == 0);

    /// <summary>The servers whose held tool-surface changes summon the band. A disabled server
    /// summons nobody — switching a server off must not leave a band demanding a decision
    /// nothing can act on (the Mac's needs-attention term, D11).</summary>
    public static IReadOnlyList<ServerRow> HeldRows(ServersEnvelope envelope) =>
        envelope.Servers.Where(s => s.PendingChange is not null && !s.Disabled).ToList();

    /// <summary>How the hub and the lane agree about the router's address: the port the router
    /// answered on, never the constant a client dials by default. §2's LoopbackAddress rule.</summary>
    public static string Endpoint(ServersEnvelope envelope) => $":{envelope.Port}";

    /// <summary>The explanatory sentence under the table, with a real count, drawn only when
    /// there is something to explain. The mock's fixture-specific "Four more upstreams" becomes
    /// the reading itself, singular included.</summary>
    public static string? DormantCallout(ServersEnvelope envelope)
    {
        var dormant = envelope.Servers.Count(s => JackPresentation.ForServer(s) == JackState.Dormant);
        if (dormant == 0) return null;

        return dormant == 1
            ? "1 upstream is dormant and costs nothing but its cached tool schema. Under the "
              + "router an unused server has no process, no memory and no start-up time, so "
              + "leaving it declared is usually right."
            : $"{dormant} upstreams are dormant and cost nothing but their cached tool schema. "
              + "Under the router an unused server has no process, no memory and no start-up "
              + "time, so leaving it declared is usually right.";
    }

    /// <summary>Which dot a harness row draws — <see cref="DotTone"/> for the mapping, and
    /// unreadable outranks everything because a row whose config could not be read must not
    /// present its empty report as a clean "not wired".</summary>
    public static DotTone HarnessDot(HarnessRow harness) =>
        harness.Unreadable is not null ? DotTone.Critical
        : harness.State == "wired-with-duplicates" ? DotTone.Caution
        : harness.State is "wired-http" or "wired-shim" ? DotTone.Lit
        : DotTone.Off;

    /// <summary>The harness row's own word, beside its name — hue never carries this alone.</summary>
    public static string HarnessWord(HarnessRow harness) =>
        harness.Unreadable is not null ? "unreadable"
        : harness.State switch
        {
            "wired-http" => "wired",
            "wired-shim" => "wired via shim",
            "wired-with-duplicates" => $"{harness.DuplicateCount} duplicates",
            _ => "not wired",
        };
}
