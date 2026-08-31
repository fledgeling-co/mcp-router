using MCPRouter.Shell.Model.Settings;
using Xunit;

namespace MCPRouter.Shell.Tests;

public sealed class SettingsPresentationTests
{
    [Theory]
    [InlineData(SettingsSection.Router, "Router")]
    [InlineData(SettingsSection.Harnesses, "Harnesses")]
    [InlineData(SettingsSection.SessionAnalyst, "Session analyst")]
    [InlineData(SettingsSection.Updates, "Updates")]
    [InlineData(SettingsSection.Security, "Security")]
    [InlineData(SettingsSection.AmbientSurface, "Ambient surface")]
    [InlineData(SettingsSection.Advanced, "Advanced")]
    public void SectionTitles_MatchExpected(SettingsSection section, string expectedTitle)
    {
        Assert.Equal(expectedTitle, SettingsPresentation.SectionTitle(section));
    }

    [Fact]
    public void Governance_ReturnsHonestAbsencesForUnbuiltAreas()
    {
        Assert.NotNull(SettingsPresentation.Governance(SettingsSection.Harnesses));
        Assert.NotNull(SettingsPresentation.Governance(SettingsSection.SessionAnalyst));
        Assert.NotNull(SettingsPresentation.Governance(SettingsSection.Updates));

        Assert.Null(SettingsPresentation.Governance(SettingsSection.Router));
        Assert.Null(SettingsPresentation.Governance(SettingsSection.Security));
    }
}
