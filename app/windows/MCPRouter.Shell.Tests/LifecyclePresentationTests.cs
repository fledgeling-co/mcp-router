using MCPRouter.Shell.Model.Lifecycle;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class LifecyclePresentationTests
{
    [Theory]
    [InlineData(DaemonSupervisionKind.LogonTask, "Scheduled Task at user logon")]
    [InlineData(DaemonSupervisionKind.StartupShortcut, "Windows Startup folder shortcut")]
    [InlineData(DaemonSupervisionKind.InAppSupervised, "Supervised directly by Windows Shell process")]
    public void ModeDescription_ProvidesClearText(DaemonSupervisionKind mode, string snippet)
    {
        Assert.Contains(snippet, LifecyclePresentation.ModeDescription(mode));
    }

    [Fact]
    public void UserSessionRequirement_StatesOAuthAndHarnessReasons()
    {
        Assert.Contains("user session", LifecyclePresentation.UserSessionRequirement);
        Assert.Contains("OAuth", LifecyclePresentation.UserSessionRequirement);
    }
}
