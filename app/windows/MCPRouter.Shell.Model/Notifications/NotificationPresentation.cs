using System;

namespace MCPRouter.Shell.Model.Notifications;

public static class NotificationPresentation
{
    public const string ReviewActionLabel = "Review…";
    public const string DismissActionLabel = "Dismiss";

    public const string ToastSafetyRule = "Toast actions open the review sheet; no toast action installs, approves or grants anything directly.";

    public static ToastNotificationPayload ForQueuedItem(string name, string device, string capabilityId)
    {
        return new ToastNotificationPayload(
            Title: $"{name} is waiting for review",
            Body: $"Queued from {device}. Nothing has been installed.",
            SourceDevice: device,
            CapabilityId: capabilityId,
            PrimaryAction: ToastActionKind.OpenReviewSheet
        );
    }
}
