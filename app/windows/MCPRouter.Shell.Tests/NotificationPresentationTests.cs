using MCPRouter.Shell.Model.Notifications;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class NotificationPresentationTests
{
    [Fact]
    public void ForQueuedItem_CreatesSafePayloadWithReviewAction()
    {
        var payload = NotificationPresentation.ForQueuedItem("postgres-mcp", "Luke's iPhone", "postgres-mcp");

        Assert.Equal("postgres-mcp is waiting for review", payload.Title);
        Assert.Contains("Nothing has been installed", payload.Body);
        Assert.Equal(ToastActionKind.OpenReviewSheet, payload.PrimaryAction);
    }

    [Fact]
    public void ToastSafetyRule_AssertsNoDirectInstall()
    {
        Assert.Contains("no toast action installs", NotificationPresentation.ToastSafetyRule);
    }
}
