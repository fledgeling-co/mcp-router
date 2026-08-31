using System;

namespace MCPRouter.Shell.Model.CapabilityDocument;

public static class CapabilityDocumentPresentation
{
    public const string Title = "Capability Document";
    public const string UpdateGateHeadline = "Update held for review";
    public const string UpdateGateExplanation = "A new version never applies live: it lands as a shadow copy, evals re-run against it, and it promotes itself only if the capability diff is empty. This one gained new capabilities, so it stopped for your review.";

    public const string ApproveUpdate = "Approve and promote";
    public const string DeclineUpdate = "Keep current version";

    public static string TabTitle(CapabilityDocumentTab tab)
    {
        return tab switch
        {
            CapabilityDocumentTab.Capabilities => "Capabilities",
            CapabilityDocumentTab.Changelog => "Changelog",
            CapabilityDocumentTab.FlagsWorthKnowing => "Flags worth knowing",
            _ => tab.ToString()
        };
    }
}
