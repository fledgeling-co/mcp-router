using System;
using System.Collections.Generic;

namespace MCPRouter.Shell.Model.Cleanup;

public enum CleanupKind
{
    Server,
    Skill
}

public enum CandidacyState
{
    Candidate,
    NotACandidate,
    HeldOut
}

public sealed record CandidacyResult(CandidacyState State, string Reason);

public sealed record CleanupServerItem(
    string Id,
    string Name,
    string? IndexError,
    bool NeverUsed,
    int? Tools,
    DateTimeOffset? IndexedAt,
    string? FirstSeenAt,
    int LifetimeCalls = 0
);

public sealed record CleanupSkillClient(
    string Id,
    string DisplayName,
    bool SupportsSkills,
    bool IsUnreadable,
    bool HasSkill
);

public sealed record CleanupSkillItem(
    string Id,
    string Name,
    string? Marketplace,
    string? Version,
    Dictionary<string, bool> Presence,
    string? FirstSeenAt,
    int LifetimeCalls = 0
);

public sealed record CleanupRow(
    string Id,
    string Name,
    CleanupKind Kind,
    int? ToolCount,
    string InstalledDate,
    string WhyItMightStillMatter,
    string SecondaryActionLabel,
    bool IsSelected = false
);
