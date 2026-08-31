using System;

namespace MCPRouter.Shell.Model.Settings;

public sealed class SettingsBoardModel
{
    public SettingsSection ActiveSection { get; set; } = SettingsSection.Router;
    public RouterSettingsState CurrentState { get; set; } = new();

    public void UpdateToggle(string key, bool value)
    {
        CurrentState = key switch
        {
            "LaunchAtLogin" => CurrentState with { LaunchAtLogin = value },
            "ShowAmbientIcon" => CurrentState with { ShowAmbientIcon = value },
            "RequireConfirmationOnDestructive" => CurrentState with { RequireConfirmationOnDestructive = value },
            _ => CurrentState
        };
    }
}
