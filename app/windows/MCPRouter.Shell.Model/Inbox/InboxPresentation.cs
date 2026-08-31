using System;
using System.Collections.Generic;

namespace MCPRouter.Shell.Model.Inbox;

public static class InboxPresentation
{
    public const string Title = "Inbox";
    public const string BoardDescription = "Everything waiting on a decision from you: what your phone queued, and what the session analyst noticed. Nothing here has been installed — the phone queues, it never installs.";
    public const string PairingButton = "Pair iPhone…";

    public const string EmptyTitle = "Nothing waiting";
    public const string EmptyDetail = "Things you send from your phone land here. The phone can queue and nothing else — a lost or unlocked phone still cannot install code on this PC.";

    public const string NoPhonePairedTitle = "No phone paired";
    public const string NoPhonePairedDetail = "Pair your iPhone to queue servers and skills from Discover while away from your PC.";

    public const string ReviewSectionTitle = "What it would be able to do";
    public const string ApproveAndInstall = "Approve and install";
    public const string NotForMe = "Not for me";

    public static string Subtitle(int waiting, string? device)
    {
        string left = waiting > 0 ? $"{waiting} waiting" : "Nothing waiting";
        if (string.IsNullOrWhiteSpace(device))
        {
            return $"{left} · no phone paired";
        }
        return waiting > 0 ? $"{waiting} waiting from {device}" : $"{left} · paired with {device}";
    }

    public static string TabLabel(DecisionState state, int count)
    {
        return state switch
        {
            DecisionState.Undecided => $"Undecided · {count}",
            DecisionState.Approved => $"Approved · {count}",
            DecisionState.NotForMe => $"Not for me · {count}",
            _ => count.ToString()
        };
    }
}
