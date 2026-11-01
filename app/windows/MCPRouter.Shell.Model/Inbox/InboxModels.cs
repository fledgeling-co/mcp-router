using System;
using System.Collections.Generic;

namespace MCPRouter.Shell.Model.Inbox;

public enum DecisionState
{
    Undecided,
    Approved,
    NotForMe
}

public enum InboxOriginKind
{
    Phone,
    SessionAnalyst
}

public sealed record InboxCapabilityLine(string Text, bool IsWarning);

public sealed record InboxItem(
    string Id,
    string Name,
    InboxOriginKind OriginKind,
    string OriginLabel,
    string ArrivedAgo,
    string Lede,
    IReadOnlyList<InboxCapabilityLine> CapabilityLines,
    DecisionState State = DecisionState.Undecided,
    int? ToolCount = null,
    string? HistoryContext = null,
    string? ReviewDigest = null,
    bool CanApprove = true
);
