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
            // NARROWED, DEF-102. It used to read "Require confirmation on destructive
            // operations", which promised a policy over a class of operations this build does not
            // have: the shell speaks four verbs to the router and exactly one of them destroys
            // anything, which is DELETE /servers/{name}. A label naming the class would still be
            // claiming the rest of it on the day the switch started working, so the label names
            // the operation it actually governs and grows when the class does.
            "RequireConfirmationOnDestructive" => "Confirm before removing a server",
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

    public static RouterSettingsState WithToggle(RouterSettingsState state, string key, bool value)
    {
        return key switch
        {
            "LaunchAtLogin" => state with { LaunchAtLogin = value },
            "ShowAmbientIcon" => state with { ShowAmbientIcon = value },
            "RequireConfirmationOnDestructive" => state with { RequireConfirmationOnDestructive = value },
            _ => state
        };
    }

    /// <summary>The automation id of the line that says why a switch cannot act.</summary>
    public static string ToggleReasonAutomationId(string key) => "settings.toggle." + key + ".reason";

    /// <summary>
    /// Why a switch on this build owns nothing, or null when it owns something.
    ///
    /// DEF-087's rule, and it is the reason this method exists rather than a stub effector for
    /// each key: a switch that moves and reaches nothing is the defect, and a switch that says it
    /// cannot act yet is honest. Both sentences here are statements about THIS BUILD, checked
    /// against the tree by <c>MCPRouter.Shell.Tests.SettingsUnavailabilityTests</c> - the day a
    /// notification-area icon or a confirmation-policy reader lands, that test fails and this
    /// sentence has to be removed rather than left standing over a working feature. Both landed:
    /// DEF-101 placed the icon, DEF-102 put the confirmation in front of the one destructive verb
    /// the shell can send, and both sentences came out on the day their feature arrived.
    /// </summary>
    public static string? ToggleUnavailableReason(string key)
    {
        return key switch
        {
            // EMPTY, and deliberately still here. It held two entries until DEF-101 and DEF-102
            // landed: ShowAmbientIcon over a build that drew no icon, and
            // RequireConfirmationOnDestructive over a build in which no operation asked it
            // anything. Both switches now own something outside this process - the shell's
            // notification area and the router's server list - so the sentences came out. The
            // method stays because it is where the next switch that outruns its implementation
            // says so, and because two keys whose owners are supplied at construction
            // (LaunchAtLogin, ShowAmbientIcon) answer through the BOARD MODEL rather than here.
            _ => null
        };
    }

    /// <summary>Why the notification-area switch cannot act when the board was built without a
    /// host - which is every construction outside the running shell, the unit suite included.</summary>
    public const string NoNotificationHostReason =
        "Unavailable: this board was built without a notification-area host, so nothing here can place or remove the icon.";

    /// <summary>Why launch-at-sign-in cannot act when the board was built without an agent.</summary>
    public const string NoLaunchAgentReason =
        "Unavailable: this board was built without a logon-task agent, so nothing here can register or remove the sign-in task.";

    /// <summary>The switches this build can genuinely act on.</summary>
    public static IEnumerable<string> ActuableToggleKeys =>
        ToggleKeys.Where(key => ToggleUnavailableReason(key) is null);

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
