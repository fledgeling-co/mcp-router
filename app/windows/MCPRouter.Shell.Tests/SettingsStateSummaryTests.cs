using MCPRouter.Shell.Model.Settings;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The state readout DEF-076's fix is proved by. Its whole job is to render from the model, so a
/// toggle that stops writing through leaves it unmoved - which is what the out-of-process UIA
/// lane watches.
/// </summary>
public sealed class SettingsStateSummaryTests
{
    [Fact]
    public void Summary_NamesEveryToggleKeyAndItsValue()
    {
        var model = new SettingsBoardModel();
        var summary = SettingsPresentation.StateSummary(model.CurrentState);

        foreach (var key in SettingsPresentation.ToggleKeys)
        {
            Assert.Contains(key + "=on", summary);
        }
    }

    [Fact]
    public void Summary_MovesWhenAToggleMoves()
    {
        var model = new SettingsBoardModel();
        var before = SettingsPresentation.StateSummary(model.CurrentState);

        model.UpdateToggle("LaunchAtLogin", false);
        var after = SettingsPresentation.StateSummary(model.CurrentState);

        Assert.NotEqual(before, after);
        Assert.Contains("LaunchAtLogin=off", after);
        Assert.Contains("ShowAmbientIcon=on", after);
    }

    [Fact]
    public void ToggleLabels_AreDistinctAndNonEmpty()
    {
        var labels = SettingsPresentation.ToggleKeys
            .Select(SettingsPresentation.ToggleLabel)
            .ToList();

        Assert.All(labels, label => Assert.False(string.IsNullOrWhiteSpace(label)));
        Assert.Equal(labels.Count, labels.Distinct().Count());
    }

    [Fact]
    public void SectionAutomationIds_AreDistinct()
    {
        var ids = SettingsPresentation.SectionOrder
            .Select(SettingsPresentation.SectionAutomationId)
            .ToList();

        Assert.Equal(7, ids.Count);
        Assert.Equal(ids.Count, ids.Distinct().Count());
    }
}
