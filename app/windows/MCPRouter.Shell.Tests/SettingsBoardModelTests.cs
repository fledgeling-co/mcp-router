using MCPRouter.Shell.Model.Settings;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class SettingsBoardModelTests
{
    [Fact]
    public void DefaultSettings_HaveSafeDefaults()
    {
        var model = new SettingsBoardModel();
        Assert.True(model.CurrentState.RequireConfirmationOnDestructive);
        Assert.True(model.CurrentState.LaunchAtLogin);
        Assert.True(model.CurrentState.ShowAmbientIcon);
        Assert.Equal("http://127.0.0.1:8879", model.CurrentState.Endpoint);
    }

    [Fact]
    public void UpdateToggle_ModifiesState()
    {
        var model = new SettingsBoardModel();
        model.UpdateToggle("LaunchAtLogin", false);
        Assert.False(model.CurrentState.LaunchAtLogin);

        model.UpdateToggle("ShowAmbientIcon", false);
        Assert.False(model.CurrentState.ShowAmbientIcon);
    }
}
