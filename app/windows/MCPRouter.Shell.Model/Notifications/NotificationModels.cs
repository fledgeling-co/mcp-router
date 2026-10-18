using System;

namespace MCPRouter.Shell.Model.Notifications;

public enum ToastActionKind
{
    OpenReviewSheet,
    Dismiss
}

public sealed record ToastNotificationPayload(
    string Title,
    string Body,
    string SourceDevice,
    string CapabilityId,
    ToastActionKind PrimaryAction = ToastActionKind.OpenReviewSheet
);
