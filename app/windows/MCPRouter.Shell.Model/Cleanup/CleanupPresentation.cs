using System;
using System.Collections.Generic;
using System.Linq;

namespace MCPRouter.Shell.Model.Cleanup;

/// <summary>
/// The Cleanup pane's decisions: who is a candidate, how much the router actually knows,
/// and every sentence the pane says about either.
/// </summary>
public static class CleanupPresentation
{
    public const string Title = "Cleanup";
    public const string BoardDescription = "Capabilities that are installed and unused. Nothing is removed automatically and nothing is called rubbish — a server nobody has called might be worthless, or might be the one that matters twice a year.";
    public const string CardExplainer = "Under the router an unused server costs a few kilobytes of cached schema and nothing else — no process, no memory, no start-up. The reason to remove one is that its tools are cluttering the model's list, or that you no longer trust it. Both are your call, and neither is disk space.";

    public const string NeverCalled = "The router has recorded no calls to it over the window below.";
    public const string OffersNothing = "It starts and indexes cleanly, and declares no tools, so it adds nothing to a session.";
    public const string InstalledNowhere = "Every skills-capable client was read, and none of them has it installed.";

    public const string EmptyTitle = "Everything here has been used";
    public const string EmptyDetail = "Every server has served calls and every skill is installed in a client the router can read. Nothing is being proposed.";

    public const string Footer = "These sit in every session's tool list, where a model reads them. Nothing here claims a memory saving: MCP Router never runs the world in which every server is resident, so it has no figure to subtract from. Nothing is removed unless you remove it, and what you remove is not counted.";

    public static string FailedToIndex(string detail) => $"The router could not start it or read its tools — {detail}";

    public static CandidacyResult EvaluateServer(CleanupServerItem server)
    {
        if (!string.IsNullOrWhiteSpace(server.IndexError))
        {
            return new CandidacyResult(CandidacyState.Candidate, FailedToIndex(server.IndexError));
        }
        if (server.NeverUsed)
        {
            return new CandidacyResult(CandidacyState.Candidate, NeverCalled);
        }
        if (server.IndexedAt != null && server.Tools == 0)
        {
            return new CandidacyResult(CandidacyState.Candidate, OffersNothing);
        }
        return new CandidacyResult(CandidacyState.NotACandidate, string.Empty);
    }

    public static CandidacyResult EvaluateSkill(CleanupSkillItem skill, IReadOnlyList<CleanupSkillClient> clients)
    {
        var capable = clients.Where(c => c.SupportsSkills).ToList();
        var unreadable = capable.Where(c => c.IsUnreadable).ToList();
        if (unreadable.Count > 0)
        {
            var names = string.Join(", ", unreadable.Select(c => c.DisplayName).OrderBy(n => n));
            return new CandidacyResult(CandidacyState.HeldOut, $"{names}'s skills directory could not be read, so whether this is installed there is unknown.");
        }
        if (capable.Count == 0)
        {
            return new CandidacyResult(CandidacyState.NotACandidate, string.Empty);
        }
        bool installedSomewhere = capable.Any(c => c.HasSkill || (skill.Presence.TryGetValue(c.Id, out var pres) && pres));
        return installedSomewhere
            ? new CandidacyResult(CandidacyState.NotACandidate, string.Empty)
            : new CandidacyResult(CandidacyState.Candidate, InstalledNowhere);
    }

    public static string Subtitle(int days)
    {
        return $"Capabilities MCP Router has never seen used, judged over the calls it has recorded across the past {days} days. It proposes; you decide.";
    }

    public static string WeakWindowBanner(int days)
    {
        return $"Call history covers only the past {days} days. Everything below reads as never-used because there is almost nothing recorded yet, not because it is unused. Give it a few days before acting on this.";
    }

    // ---------------------------------------------------------------- removing (DEF-302)
    //
    // This board carries the second destructive control in the product, and it now goes down the
    // same path as the first: DELETE /servers/{name} through ControlApiClient, gated by
    // "Confirm before removing a server" read at the moment of the press. The copy below has to
    // agree with what that call actually does, which is where this board was previously wrong in
    // the most dangerous possible direction.
    //
    // DEF-400. The action row used to end with "Removing is undoable for 30 days." Nothing in the
    // product implements an undo, and the router's DELETE branch drops the entry from servers.json
    // and reloads. A false reassurance under a destructive button is worse than no sentence at
    // all: it is the sentence that makes somebody press it.
    public const string RemoveLabel = "Remove selected…";
    public const string RemoveDisabledReason =
        "Tick a server above, and this removes it from the router.";
    public const string RemoveCommitLabel = "Remove permanently";
    public const string RemoveIrreversibleNote =
        "Removing is not undoable. The router drops the server from its list and every attached "
        + "agent loses its tools; its call history is kept, and adding it again means entering its "
        + "command afresh.";

    public static string RemoveCancelLabel(int count) => count == 1 ? "Keep it" : "Keep them";

    public static string RemoveDialogTitle(IReadOnlyList<string> names) =>
        names.Count == 1 ? $"Remove {names[0]}?" : $"Remove {names.Count} servers?";

    public static string RemoveDialogBody(IReadOnlyList<string> names)
    {
        var subject = names.Count == 1 ? names[0] : string.Join(", ", names);
        return $"{subject} — {RemoveIrreversibleNote}";
    }

    public static string Kept(IReadOnlyList<string> names) =>
        names.Count == 1
            ? $"{names[0]} was kept."
            : $"{names.Count} servers were kept.";

    public static string Removed(IReadOnlyList<string> names) =>
        names.Count == 1
            ? $"Removed {names[0]}."
            : $"Removed {names.Count} servers: {string.Join(", ", names)}.";

    public static string RemovedWithoutAsking(IReadOnlyList<string> names) =>
        names.Count == 1
            ? $"Removed {names[0]} without asking — confirmation is off in Settings."
            : $"Removed {names.Count} servers without asking — confirmation is off in Settings: "
              + string.Join(", ", names) + ".";

    public static string RemoveFailed(string name, string detail) =>
        $"{name} was not removed: {detail}";

    /// <summary>The board could not reach the router at all, so it has no rows and proposes
    /// nothing. Said out loud rather than drawn as an empty list, which would read as "everything
    /// here has been used".</summary>
    public static string Unreachable(string detail) =>
        $"The router did not answer, so this board has nothing to propose — {detail}";

    public const string LoadingLine = "Asking the router what it has and what has called it…";

    public static string BadgeNote(int neverUsedCount)
    {
        var noun = neverUsedCount == 1 ? "server" : "servers";
        return $"The sidebar badge counts the {neverUsedCount} {noun} nobody has called. This list also includes servers that failed to index or declared no tools.";
    }
}
