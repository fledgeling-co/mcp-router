namespace MCPRouter.Shell.Model.Servers;

/// <summary>
/// Every user-visible sentence this board draws, named in one place so the words are testable
/// without a host — which is the difference between a copy rule and a copy hope.
///
/// <para>Where a sentence has a source elsewhere in the repository, it is quoted from that
/// source rather than respelled: DESIGN.md §6 asks for one wording per state across devices,
/// and the Mac owns several of these already.</para>
/// </summary>
public static class ServersCopy
{
    /// <summary>The board's purpose, in the design of record's own words — the sentence under
    /// the title (`design/mcp-router-console.html`, the servers board head).</summary>
    public const string BoardSentence =
        "Every MCP server your agents can reach. A jack lights the instant something calls it, " +
        "and goes dark when the reaper closes the child. Nothing here is running because it was declared.";

    /// <summary>Why <c>Reap idle</c> is drawn and dimmed. The measurement behind it is
    /// spec-WIN4 §3.4: the control path family holds no reap route, and PATCH's five writable
    /// fields contain no field whose write forces a reap.</summary>
    public const string ReapIdleReason =
        "The reaper runs on the router's own schedule, and the router serves no route that asks "
        + "it to run early.";

    /// <summary>The empty state, first run. The mock's headline and explanation, with one
    /// adjustment the carried adopt action forces: the mock's sentence sells adoption, and
    /// adoption has no control route on this platform (spec-WIN4 §6), so this says what adding
    /// by hand really does — the router indexes a declared server once, before it lands in the
    /// config, and every session is handed the same endpoint.</summary>
    public const string EmptyHeadline = "No servers adopted yet";
    public const string EmptySentence =
        "MCP Router has not taken over any harness configurations yet. A server added here is "
        + "indexed once, and every session is handed the same endpoint.";

    /// <summary>The mock's secondary action, promoted to the empty state's one action because
    /// the primary is carried. The trailing ellipsis is load-bearing (DESIGN.md §3 rule 4): it
    /// opens a further view and commits nothing itself.</summary>
    public const string EmptyAction = "Add one by hand…";

    /// <summary>The one action the disconnected surface offers that is real here, and the one
    /// that is not. The start action is quoted from the Mac's
    /// <c>ServersBoardModel.cannotStartRouterReason</c> — its own honest-disabled ruling, ported
    /// verbatim, because WIN23 owns router lifecycle on Windows and the reason stays true until
    /// it lands.</summary>
    public const string RetryLabel = "Try again";
    public const string StartRouterLabel = "Start the router";
    public const string CannotStartRouterReason =
        "MCP Router can't start the daemon itself yet. Start it the way you normally do and "
        + "this fills in on its own.";

    /// <summary>The stale banner. A refresh that did not complete is not evidence the router
    /// moved (DESIGN.md §9), so the last good reading stays and this says how old it is.</summary>
    public static string StaleLine(string answeredAt) =>
        $"The last refresh didn't complete — showing the reading from {answeredAt}.";

    /// <summary>The loading state's one quiet line.</summary>
    public const string LoadingLine = "Connecting to the router…";

    /// <summary>The harness column's own failure, drawn inside the lane — §5's partial state:
    /// say what arrived and what did not, with the reason.</summary>
    public static string HarnessUnavailable(string reason) => $"Harnesses unavailable: {reason}";

    /// <summary>The held band. The count and the server are the router's; the second line is
    /// the design of record's, because it states the rule that makes the band exist.</summary>
    public static string HeldBandHead(int count, string server)
    {
        var noun = count == 1 ? "tool" : "tools";
        return $"{count} {noun} on {server} changed their input schema";
    }

    public const string HeldBandBody =
        "Nothing calls a held tool until you have read the diff.";
    public const string ReviewChangesLabel = "Review changes…";

    /// <summary>The add-server dialog. The ellipsis lives on the button that opens it, never on
    /// the commit — the dialog's commit is a verb that does the thing.</summary>
    public const string AddDialogTitle = "Add server";
    public const string AddCommitLabel = "Add";
    public const string AddCancelLabel = "Cancel";
    public const string AddNameLabel = "Name";
    public const string AddCommandLabel = "Command";
    public const string AddArgsLabel = "Arguments";
    public const string AddArgsHelper = "One argument per line.";
    public const string AddUrlLabel = "URL";
    public const string AddUrlHelper = "For a server reached over HTTP or SSE, instead of a command.";
    public const string AddAnywayLabel = "Add it anyway";

    /// <summary>The topology line's endpoint word, as the design of record writes it.</summary>
    public const string TopologyEndpointWord = "1 endpoint";
}
