namespace MCPRouter.Checks.Model;

/// <summary>
/// Every sentence the Checks board says about a check.
///
/// One place, deliberately — the Mac's <c>CheckCopy</c> precedent (design of record for these
/// sentences per DESIGN.md §6's table): the naming discipline is testable only if the strings
/// live somewhere a test can read them. Ported verbatim except where this platform's facts differ,
/// and every departure is recorded at the string.
///
/// The rule the copy is built around: the unit is a *check* — something MCP Router performed and
/// can show you the input to. It is not a graded test of whether a capability does its job well.
/// A verdict therefore never appears without the statement it judges, and the aggregate is a tally
/// of segments rather than a single word.
/// </summary>
public static class CheckCopy
{
    // ------------------------------------------------------------------ statements

    /// <summary>What each check asserts, phrased as the thing being judged, present tense and
    /// specific. The Mac's wording, verbatim.</summary>
    public static string Statement(CheckId check) => check switch
    {
        CheckId.Indexes => "The router can start it and read its tool surface",
        CheckId.DeclaresTools => "It offers at least one tool",
        CheckId.Authorized => "Its credentials are current",
        CheckId.SurfaceApproved => "No tool description is waiting for review",
        CheckId.Operative => "It carries no placard",
        CheckId.CallsSucceed => "Its calls come back without error",
        CheckId.Reachable => "At least one client can load it",
        CheckId.Versioned => "It carries a version a result can be stamped against",
        CheckId.OriginUnchanged => "Its marketplace still resolves where the router first saw it",
        CheckId.UpdateWantsNoMore => "Any newer version held asks for nothing extra",
        CheckId.Described => "Its SKILL.md declares a description an agent can route on",
        _ => throw new ArgumentOutOfRangeException(nameof(check), check, "no statement for this check"),
    };

    // ------------------------------------------------------------------ reasons

    /// <summary>Named observations, never adjectives — each composed from a value the router
    /// actually sent, which is why the parameterised ones take parameters.</summary>
    public static string NeverIndexed => "The router has never started it, so its tool surface is unread.";

    public static string IndexFailed(string detail) => $"The router could not read its tool surface — {detail}";

    public static string NoToolsDeclared =>
        "It indexed without error and declared no tools, so it adds nothing to a session's tool list.";

    public static string ToolsUnknownUntilIndexed =>
        "Its tool surface has not been read, so how many tools it offers is unobserved.";

    public static string CredentialsMissing =>
        "It supports authorization and the router holds no current credentials for it.";

    public static string CredentialsNotApplicable =>
        "This transport carries no credentials, so there are none to be current.";

    public static string SurfaceHeld(int count, string seenAt)
    {
        var noun = count == 1 ? "description" : "descriptions";
        return $"{count} tool {noun} changed and are held for review, first seen {seenAt}.";
    }

    public static string Placarded(string reason) => $"It carries a placard — {reason}";

    /// <summary>The load-bearing one. Zero calls with zero errors is arithmetically a clean record
    /// and is not a confirmation: a check that reports success for something nobody has ever done
    /// is the same defect as a fabricated number. It reports <c>not observed</c>, and this is what
    /// it says.</summary>
    public static string NeverExercised =>
        "Never exercised — the router has recorded no calls to it, so whether its calls succeed "
        + "is unobserved.";

    public static string CallsFailed(int errors, int calls)
    {
        var noun = errors == 1 ? "call" : "calls";
        return $"{errors} of {calls} recorded {noun} came back with an error.";
    }

    // ------------------------------------------------------------------ skill reasons

    /// <summary>Every skills-capable client was read and none holds the skill.</summary>
    public static string NotLoadableAnywhere(int clientCount)
    {
        var noun = clientCount == 1 ? "client" : "clients";
        return $"Every one of the {clientCount} skills-capable {noun} was read, and none has it installed.";
    }

    /// <summary>A capable client could not be read, so whether the skill is there is unobserved.</summary>
    public static string ReachabilityUnknown(IReadOnlyList<string> clients)
    {
        var names = string.Join(", ", clients.Order(StringComparer.Ordinal));
        var verb = clients.Count == 1 ? "directory could not be read" : "directories could not be read";
        return $"It is installed in no client the router could read, and {names}'s skills {verb} — "
            + "so it may be installed exactly where nobody could look.";
    }

    public static string StandaloneUnversioned =>
        "It was placed in a client's directory by hand, so it has no version anywhere on disk and "
        + "no result about it can be stamped against one.";

    /// <summary>A standalone skill has no marketplace, so an unmoved origin is not something that can be true of it.</summary>
    public static string StandaloneNoOrigin =>
        "It was placed in a client's directory by hand rather than supplied by a marketplace, so "
        + "there is no origin for it to have moved from.";

    public static string NoVersionHeld =>
        "No newer version of its plugin is being held, so there is nothing waiting to ask for more.";

    public static string OriginMoved(string firstSeen, string current, string at) =>
        $"The router first saw it at {firstSeen} and it now resolves to {current}, first observed {at}.";

    public static string HeldVersionWantsMore(string version, IEnumerable<string> capabilities)
    {
        var list = string.Join(", ", capabilities.Order(StringComparer.Ordinal));
        return $"Version {version} is held and asks for {list}.";
    }

    public static string NoDescription =>
        "Its SKILL.md declares no description, so an agent has nothing to route on when choosing it.";

    // ------------------------------------------------------------------ the board

    /// <summary>Permanent, and present even while loading and while disconnected — it is a
    /// statement about the product rather than about the data, so a pane that omitted it in any
    /// state would be the moment a user forms their first impression of what this board claims.
    /// Design of record (DESIGN.md §6's table), verbatim.</summary>
    public static string BoardSubtitle =>
        "The checks MCP Router runs itself, stamped to the version each was run against. "
        + "No model-graded evaluation exists in this product.";

    /// <summary>Design of record (DESIGN.md §6's table), verbatim.</summary>
    public static string BoardFooter =>
        "A check is something MCP Router performed and can show you the input to. It is not a graded "
        + "test of whether a capability does its job well. Skills are never executed by the "
        + "router, so nothing here reports how one behaved when an agent used it.";

    /// <summary>The two head actions. Verb-first, and true of what actually happens: for a server
    /// the call is <c>POST /servers/:name/reindex</c>, which re-performs the handshake, and the
    /// derivation runs over a fresh reading. "Run" here names re-running the checks, and carries
    /// no claim of executing the capability.</summary>
    public static string RunAllLabel => "Run all";
    public static string RunStaleLabel => "Run the stale suite";
    public static string RunOneLabel => "Run";

    /// <summary>Why the stale-suite action is dim when nothing is stale — §5's disabled row, a
    /// discoverable reason rather than a grey button.</summary>
    public static string RunStaleDisabledReason =>
        "Nothing is stale — every stored result was gathered against the version that is live.";

    // ------------------------------------------------------------------ row states

    /// <summary>The Result cell of a row whose stored stamp no longer matches the live version.
    /// The one word the whole item exists to make possible.</summary>
    public static string StaleWord => "Stale";

    /// <summary>The Checks column of a stale row: what the dropped result was, and the version it
    /// belongs to — so the row says what it is missing rather than looking empty.</summary>
    public static string StaleDetail(int checkCount, string storedStamp) =>
        $"{checkCount} checks · last result was for {storedStamp}";

    /// <summary>Where the Ran column of a stale row points: nowhere. The dropped run's time is the
    /// dropped run's, not this row's.</summary>
    public static string NoRunMark => "—";

    public static string NotChecked => "Not checked";

    /// <summary>The Checks column of a row nothing has been recorded against.</summary>
    public static string NotCheckedDetail(int checkCount) => $"{checkCount} checks have not been run.";

    public static string CouldNotRun => "Could not run";

    // ------------------------------------------------------------------ invalidation

    /// <summary>The notice that names what was dropped and why. The mock's sentence, verbatim in
    /// shape: capability, the move, and the refusal of the carried-forward tick.</summary>
    public static string Invalidated(string name, string storedStamp, string liveStamp) =>
        $"{name} moved from {storedStamp} to {liveStamp} since it was last checked, so its result "
        + "was dropped rather than shown against the new code.";

    /// <summary>The action the notice offers.</summary>
    public static string RerunLabel(string name) => $"Re-run {name}";

    // ------------------------------------------------------------------ the detail

    /// <summary>The detail's heading for a stored run: capability, the version it ran against,
    /// and what the run is. The mock's idiom ("trawl · 1.4.2 · the last complete run") — the
    /// version is IN the heading, so a dropped run can be inspected without ever being presented
    /// against the version that replaced it.</summary>
    public static string LastCompleteRun(string name, string stamp) =>
        $"{name} · {stamp} · the last complete run";

    /// <summary>The detail's heading when nothing has been recorded.</summary>
    public static string NoStoredRun(string name) => $"{name} · no stored run";

    /// <summary>The history list's heading. It names the rule as well as the section: every row
    /// under it is labelled with the version it was gathered against.</summary>
    public static string HistoryHeading => "Across versions";

    /// <summary>A history row: version, tally, when. Counts, never percentages — the suite's
    /// denominator can move, so the counts are what compare (the mock's own reason).</summary>
    public static string HistoryRow(string stamp, int confirmed, int total, string ago) =>
        $"{stamp} · {confirmed} of {total} confirmed · {ago}";

    /// <summary>History for a subject that cannot be stamped is not merely empty; it is
    /// structurally impossible, and the detail says which.</summary>
    public static string Unstampable => "No version to stamp against";

    public static string UnstampableDetail =>
        "These checks can run and be shown, and nothing is stored: there is no version here for a "
        + "later reading to be measured against, so a stored result could never be known to be out "
        + "of date.";

    // ------------------------------------------------------------------ the tally

    /// <summary>The Checks column of a current row with nothing to look at: the full count.</summary>
    public static string TallyAllConfirmed(int total) => $"{total} of {total} confirmed";

    /// <summary>The Checks column segments for a current row, in verdict order, omitting empty
    /// segments. "4 confirmed · 2 not met" is a description of what was observed, which the data
    /// supports; "passed" alone would be a claim about the whole subject that no check here
    /// supports.</summary>
    public static string TallySegments(IReadOnlyList<CheckResult> results)
    {
        IEnumerable<CheckVerdict> order = [CheckVerdict.Passed, CheckVerdict.Failed, CheckVerdict.Unknown, CheckVerdict.NotApplicable];
        var segments = new List<string>();
        foreach (var verdict in order)
        {
            var count = results.Count(r => r.Verdict == verdict);
            if (count > 0)
            {
                segments.Add($"{count} {CheckVerdictWords.For(verdict)}");
            }
        }

        return string.Join(" · ", segments);
    }

    // ------------------------------------------------------------------ empty / disconnected

    /// <summary>The empty state. The Mac's sentence, worded for what this board checks — skills
    /// return with their endpoint (spec-WIN8 §3.6).</summary>
    public static string EmptyTitle => "Nothing to check yet";

    public static string EmptyDetail =>
        "MCP Router checks the servers it can see. Declare a server and its checks appear here.";

    /// <summary>The partial state: what arrived, what did not, and the reason (§5's Partial row).
    /// The wording is composed from the named absence, so a router that grows the endpoint
    /// silently changes this sentence by making it unreachable.</summary>
    public static string SkillsUnreadable(string reason) =>
        $"Skills could not be read — {reason} No skill is checked here; the server checks are unaffected.";

    /// <summary>The retry action, offered by the disconnected and error states. Starting the
    /// router is not offered: its Windows lifecycle is WIN23's (spec-WIN8 §3.7).</summary>
    public static string RetryLabel => "Retry";

    /// <summary>Said when the store itself could not be read: the rows cannot claim "never
    /// checked" silently, because a cache failure is a different claim from never having run.
    /// The Mac's sentence, with the error composed in.</summary>
    public static string HistoryUnreadable(string error) =>
        $"The stored history could not be read ({error}), so earlier runs are not shown. This is a "
        + "problem with the stored file, not with the checks.";

    /// <summary>The disconnected state's headline — ported verbatim from the Mac's
    /// <c>ControlAPIError.routerNotRunning</c> (§6: one name per state, one source).</summary>
    public static string RouterNotRunningHeadline => "The router isn't running";

    /// <summary>The advice under it — the Mac's sentence. It stays true of starting the router by
    /// whatever means WIN23 lands.</summary>
    public static string RouterNotRunningAdvice =>
        "Nothing is listening on the control port, so there is nothing to show yet. "
        + "Starting it takes a moment and your servers stay exactly as you left them.";

    // ------------------------------------------------------------------ running

    /// <summary>The head's progress line while a run is in flight: which subject, and how far
    /// through the set. Honest about the shape of a run — one fetch and a derivation per subject,
    /// not a streaming suite log.</summary>
    public static string RunningNow(string name, int index, int total) =>
        $"Checking {name} — check {index} of {total}";

    public static string CheckingLabel => "Checking…";
}
