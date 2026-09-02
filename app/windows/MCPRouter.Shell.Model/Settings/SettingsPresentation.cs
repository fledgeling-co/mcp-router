using System;
using System.Collections.Generic;
using System.Linq;

namespace MCPRouter.Shell.Model.Settings;

public static class SettingsPresentation
{
    public const string Title = "Settings";

    public const string HarnessesGovernance = "Set from the command line, not here. Which harnesses this router fronts, whether a new stdio server is adopted, and whether a drifted configuration is reconciled are decided by mcp-router harnesses and mcp-router watch. The app reaches the router over one loopback channel and that channel serves no harness settings at all, so there is nothing here it could read or write.";

    public const string AnalystGovernance = "This build has no session analyst. Nothing reads your agent logs, no model is called on your behalf, and no finding is ever generated — so there is no model to pick, no schedule to set and nothing to be notified about yet. The pane is here because the window's areas are fixed; what would go in it is not built.";

    public const string UpdatesGovernance = "This build checks for nothing. It does not look for new versions of itself, and a capability you have installed stays the version you installed until you install another. There is no interval, no channel and no unattended-install rule, because there is no check to configure.";

    public const string FilesHelp = "Both files are the router's own. The app reads neither: it reaches the router over the loopback control API and nothing else, which is what lets the router be replaced underneath it.";

    /// <summary>
    /// The order the board renders the seven sections in. Held here rather than typed into the
    /// XAML so that a test and the view cannot disagree about how many there are: DEF-076 was a
    /// board that declared three sections against a ledger row claiming seven, and nothing in the
    /// build could tell the two numbers apart.
    /// </summary>
    public static readonly IReadOnlyList<SettingsSection> SectionOrder = new[]
    {
        SettingsSection.Router,
        SettingsSection.Harnesses,
        SettingsSection.SessionAnalyst,
        SettingsSection.Updates,
        SettingsSection.Security,
        SettingsSection.AmbientSurface,
        SettingsSection.Advanced,
    };

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

    /// <summary>
    /// The automation id the view stamps on a section's container, and the id the out-of-process
    /// UIA lane addresses it by. Ids rather than names because the shell's menu bar already
    /// carries a "Router" and a "Help", and a name search returns the first match anywhere in
    /// the tree.
    /// </summary>
    public static string SectionAutomationId(SettingsSection section)
        => "settings.section." + section.ToString().ToLowerInvariant();

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

    /// <summary>The three settings this build can actually change, in board order.</summary>
    public static readonly IReadOnlyList<string> ToggleKeys = new[]
    {
        "LaunchAtLogin",
        "RequireConfirmationOnDestructive",
        "ShowAmbientIcon",
    };

    public static string ToggleAutomationId(string key) => "settings.toggle." + key;

    /// <summary>The row label a toggle carries, and the accessible name it publishes.</summary>
    public static string ToggleLabel(string key)
    {
        return key switch
        {
            "LaunchAtLogin" => "Launch router daemon at sign-in",
            "ShowAmbientIcon" => "Show status in notification area",
            "RequireConfirmationOnDestructive" => "Require confirmation on destructive operations",
            _ => key
        };
    }

    public static bool ToggleValue(RouterSettingsState state, string key)
    {
        return key switch
        {
            "LaunchAtLogin" => state.LaunchAtLogin,
            "ShowAmbientIcon" => state.ShowAmbientIcon,
            "RequireConfirmationOnDestructive" => state.RequireConfirmationOnDestructive,
            _ => false
        };
    }

    /// <summary>
    /// A rendering of the whole toggle state as one line, so that flipping a switch has a visible
    /// effect OUTSIDE the switch that was flipped. A toggle that moves and changes nothing else
    /// passes every presence check ever written; this readout is what an out-of-process reader
    /// can watch to tell a bound control from an inert one.
    /// </summary>
    public static string StateSummary(RouterSettingsState state)
        => string.Join(" · ", ToggleKeys.Select(
            key => key + "=" + (ToggleValue(state, key) ? "on" : "off")));
}
