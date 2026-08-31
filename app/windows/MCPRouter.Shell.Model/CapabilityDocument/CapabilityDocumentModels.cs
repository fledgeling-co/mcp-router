using System;
using System.Collections.Generic;

namespace MCPRouter.Shell.Model.CapabilityDocument;

public enum CapabilityDocumentTab
{
    Capabilities,
    Changelog,
    FlagsWorthKnowing
}

public sealed record CapabilityDiffItem(
    string Name,
    string Description,
    bool IsAdded,
    bool IsElevated
);

public sealed record CapabilityDocument(
    string CapabilityId,
    string DisplayName,
    string InstalledVersion,
    string CandidateVersion,
    bool IsUpdateHeld,
    IReadOnlyList<CapabilityDiffItem> CapabilityDeltas,
    string ChangelogText,
    IReadOnlyList<string> FlagsWorthKnowing
);
