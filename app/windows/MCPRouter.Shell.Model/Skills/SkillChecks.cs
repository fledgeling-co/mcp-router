using MCPRouter.Checks.Model;

namespace MCPRouter.Shell.Model.Skills;

/// <summary>
/// The five checks MCP Router can genuinely perform against a skill, ported from the Mac's
/// <c>SkillChecks</c> (<c>app/Sources/MCPRouterKit/Checks/SkillChecks.swift</c>).
///
/// A skill is never executed by the router. It is markdown the <i>client</i> loads into an agent's
/// context, so nothing here reports how a skill behaved when an agent used it. Everything is
/// structural: reachability, versioning, provenance, and what a held version asks for.
///
/// Every function is a pure function of the wire shapes <c>GET /skills</c> serves, so a function
/// with only a <see cref="Skill"/> to read cannot invent an observation.
/// </summary>
public static class SkillChecks
{
    /// <summary>The five, in the order the inspector renders them.</summary>
    public static IReadOnlyList<CheckResult> All(Skill skill, IReadOnlyList<SkillClient> clients) =>
    [
        Reachable(skill, clients),
        Versioned(skill),
        OriginUnchanged(skill),
        UpdateWantsNoMore(skill),
        Described(skill),
    ];

    /// <summary>At least one client can load it.
    ///
    /// An absent presence key is not evidence of absence: the presence map is not exhaustive, so a
    /// client whose directory could not be read may have no key at all. Treating a missing key as
    /// "not installed there" would declare a skill loadable by nobody on the strength of a lookup
    /// that never happened.</summary>
    public static CheckResult Reachable(Skill skill, IReadOnlyList<SkillClient> clients)
    {
        var capable = clients.Where(c => c.SupportsSkills).ToList();

        if (capable.Any(c => PresenceOf(skill, c.Id) == SkillPresence.Present))
        {
            return new CheckResult(CheckId.Reachable, CheckVerdict.Passed, null);
        }

        var unreadable = capable
            .Where(c => c.Status == SkillClientStatus.Unreadable
                        || PresenceOf(skill, c.Id) == SkillPresence.Unreadable)
            .ToList();
        if (unreadable.Count > 0)
        {
            return new CheckResult(
                CheckId.Reachable,
                CheckVerdict.Unknown,
                CheckCopy.ReachabilityUnknown(unreadable.Select(c => c.DisplayName).ToList()));
        }

        return new CheckResult(
            CheckId.Reachable,
            CheckVerdict.Failed,
            CheckCopy.NotLoadableAnywhere(capable.Count));
    }

    /// <summary>It carries a version a result can be stamped against. A standalone skill has no
    /// version anywhere in <see cref="SkillSource"/>, so this is the reason its history is empty.</summary>
    public static CheckResult Versioned(Skill skill) =>
        skill.Source is SkillSource.PluginOrigin
            ? new CheckResult(CheckId.Versioned, CheckVerdict.Passed, null)
            : new CheckResult(CheckId.Versioned, CheckVerdict.Failed, CheckCopy.StandaloneUnversioned);

    /// <summary>Its marketplace still resolves where the router first saw it. Not applicable to a
    /// standalone skill, which has no marketplace for an origin to move from.</summary>
    public static CheckResult OriginUnchanged(Skill skill)
    {
        if (skill.Source is not SkillSource.PluginOrigin)
        {
            return new CheckResult(CheckId.OriginUnchanged, CheckVerdict.NotApplicable, CheckCopy.StandaloneNoOrigin);
        }

        if (skill.Provenance is not { } provenance)
        {
            return new CheckResult(CheckId.OriginUnchanged, CheckVerdict.Passed, null);
        }

        return new CheckResult(
            CheckId.OriginUnchanged,
            CheckVerdict.Failed,
            CheckCopy.OriginMoved(provenance.FirstSeenSource, provenance.CurrentSource, provenance.FirstSeenAt));
    }

    /// <summary>Any newer version held asks for nothing extra. Not applicable when none is held,
    /// which is most skills: reporting a confirmation for them would pass a question nobody asked.</summary>
    public static CheckResult UpdateWantsNoMore(Skill skill)
    {
        if (skill.Held is not { } held)
        {
            return new CheckResult(CheckId.UpdateWantsNoMore, CheckVerdict.NotApplicable, CheckCopy.NoVersionHeld);
        }

        if (!held.WantsMore)
        {
            return new CheckResult(CheckId.UpdateWantsNoMore, CheckVerdict.Passed, null);
        }

        return new CheckResult(
            CheckId.UpdateWantsNoMore,
            CheckVerdict.Failed,
            CheckCopy.HeldVersionWantsMore(held.PluginVersion, held.AddedCapabilities));
    }

    /// <summary>Its <c>SKILL.md</c> declares a description an agent can route on. Binary: a skill whose
    /// directory could not be read is not in the response at all, so there is no unobserved state to show.</summary>
    public static CheckResult Described(Skill skill) =>
        string.IsNullOrWhiteSpace(skill.Description)
            ? new CheckResult(CheckId.Described, CheckVerdict.Failed, CheckCopy.NoDescription)
            : new CheckResult(CheckId.Described, CheckVerdict.Passed, null);

    /// <summary>The presence a client was read as, or null when the map has no key for it. Null is not
    /// <see cref="SkillPresence.Present"/>: that is the enum's zero value, so a defaulted lookup would
    /// report a skill present in a client nobody read.</summary>
    private static SkillPresence? PresenceOf(Skill skill, string clientId) =>
        skill.Presence.TryGetValue(clientId, out var presence) ? presence : null;
}
