using System;

namespace MCPRouter.Shell.Model.Settings;

public static class SettingsPresentation
{
    public const string Title = "Settings";

    public const string HarnessesGovernance = "Set from the command line, not here. Which harnesses this router fronts, whether a new stdio server is adopted, and whether a drifted configuration is reconciled are decided by mcp-router harnesses and mcp-router watch. The app reaches the router over one loopback channel and that channel serves no harness settings at all, so there is nothing here it could read or write.";

    public const string AnalystGovernance = "This build has no session analyst. Nothing reads your agent logs, no model is called on your behalf, and no finding is ever generated — so there is no model to pick, no schedule to set and nothing to be notified about yet. The pane is here because the window's areas are fixed; what would go in it is not built.";

    public const string UpdatesGovernance = "This build checks for nothing. It does not look for new versions of itself, and a capability you have installed stays the version you installed until you install another. There is no interval, no channel and no unattended-install rule, because there is no check to configure.";

    public const string FilesHelp = "Both files are the router's own. The app reads neither: it reaches the router over the loopback control API and nothing else, which is what lets the router be replaced underneath it.";

    public static string SectionTitle(SettingsSection section)
    {
        return section switch
        {
            SettingsSection.Router => "Router",
            SettingsSection.Harnesses => "Harnesses",
            SettingsSection.SessionAnalyst => "Session analyst",
            SettingsSection.Updates => "Updates",
            SettingsSection.Security => "Security",
            SettingsSection.AmbientSurface => "Ambient surface",
            SettingsSection.Advanced => "Advanced",
            _ => section.ToString()
        };
    }

    public static string? Governance(SettingsSection section)
    {
        return section switch
        {
            SettingsSection.Harnesses => HarnessesGovernance,
            SettingsSection.SessionAnalyst => AnalystGovernance,
            SettingsSection.Updates => UpdatesGovernance,
            _ => null
        };
    }
}
