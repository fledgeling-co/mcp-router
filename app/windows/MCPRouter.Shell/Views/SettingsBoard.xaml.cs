using System;
using System.Collections.Generic;
using MCPRouter.Shell.Live.Ambient;
using MCPRouter.Shell.Live.Lifecycle;
using MCPRouter.Shell.Model.Settings;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Windows.ApplicationModel.DataTransfer;

namespace MCPRouter.Shell.Views;

/// <summary>
/// The Settings board. DEF-076: it rendered three of the seven sections WIN13 declares, and its
/// switches were unbound and unnamed. DEF-087: the switches wrote to a model that nothing
/// persisted and nothing carried to the machine. DEF-088: the Copy button was named and had no
/// handler.
///
/// The names and ids are stamped here rather than typed into the XAML because
/// <see cref="SettingsPresentation" /> is the one place the section list, the toggle keys and
/// their labels are declared, and the out-of-process UIA lane reads the same file. A string typed
/// into the view and again into the harness drifts, and then the lane measures a board that does
/// not exist.
/// </summary>
public sealed partial class SettingsBoard : UserControl
{
    private readonly SettingsBoardModel _model;

    /// <summary>The reason line beside each switch, keyed the way the model keys the reasons.</summary>
    private readonly Dictionary<string, TextBlock> _reasonLines;

    public SettingsBoard()
    {
        InitializeComponent();

        // The store and the agent are constructed here rather than injected, because this board is
        // built by the shell's navigation and has no composition root to be handed them by. Both
        // are seams for the suites: SettingsBoardModel takes null for either and stays in memory,
        // which is what the unit tests use so they never touch %APPDATA% or schtasks.
        // The notification-area host is the APP's, not this board's: see App.NotificationIcon.
        // Null when this control is built outside a running shell, and then the switch says it has
        // no host rather than moving a boolean.
        _model = new SettingsBoardModel(
            new SettingsStore(),
            new LogonTaskLaunchAgent(),
            App.NotificationIcon is null ? null : new NotificationAreaAgent(App.NotificationIcon));

        _reasonLines = new Dictionary<string, TextBlock>(StringComparer.Ordinal)
        {
            ["LaunchAtLogin"] = LaunchAtLoginReasonText,
            ["RequireConfirmationOnDestructive"] = RequireConfirmationReasonText,
            ["ShowAmbientIcon"] = ShowAmbientIconReasonText,
        };

        EndpointText.Text = _model.CurrentState.Endpoint;
        HomeDirectoryText.Text = _model.CurrentState.HomeDirectory;
        IdleReaperText.Text = _model.CurrentState.IdleReaper;
        FilesHelpText.Text = SettingsPresentation.FilesHelp;

        HarnessesGovernanceText.Text = SettingsPresentation.Governance(SettingsSection.Harnesses) ?? "";
        AnalystGovernanceText.Text = SettingsPresentation.Governance(SettingsSection.SessionAnalyst) ?? "";
        UpdatesGovernanceText.Text = SettingsPresentation.Governance(SettingsSection.Updates) ?? "";

        BindToggle(LaunchAtLoginToggle);
        BindToggle(RequireConfirmationToggle);
        BindToggle(ShowAmbientIconToggle);

        RenderState();
    }

    private void BindToggle(ToggleSwitch toggle)
    {
        var key = (string)toggle.Tag;
        AutomationProperties.SetName(toggle, SettingsPresentation.ToggleLabel(key));
        AutomationProperties.SetAutomationId(toggle, SettingsPresentation.ToggleAutomationId(key));

        // Seeded from the model rather than from a literal in the markup, so that the switch and
        // the state it claims to show cannot start out disagreeing.
        toggle.IsOn = SettingsPresentation.ToggleValue(_model.CurrentState, key);

        // A switch that owns nothing on this build is DISABLED and carries the reason, rather than
        // moving a boolean nobody reads. That is DEF-087's rule and the only honest alternative to
        // wiring it to a stub that pretends.
        var reason = _model.UnavailableReason(key);
        toggle.IsEnabled = reason is null;
        if (_reasonLines.TryGetValue(key, out var line))
        {
            line.Text = reason ?? "";
            line.Visibility = reason is null ? Visibility.Collapsed : Visibility.Visible;
        }
    }

    private void OnToggled(object sender, RoutedEventArgs e)
    {
        if (sender is not ToggleSwitch toggle || toggle.Tag is not string key) return;
        _model.UpdateToggle(key, toggle.IsOn);

        // The switch follows the MODEL, not the gesture. UpdateToggle leaves the state untouched
        // when the machine refused the change, so a registration the task scheduler rejects snaps
        // the switch back rather than leaving it reporting a state nothing holds.
        var settled = SettingsPresentation.ToggleValue(_model.CurrentState, key);
        if (toggle.IsOn != settled)
        {
            toggle.IsOn = settled;
        }
        RenderState();
    }

    /// <summary>
    /// DEF-088. The one actuable control the original census found, and its Click was unhandled -
    /// which made it the control most likely to be mistaken for evidence that this board works.
    /// </summary>
    /// <remarks>
    /// <c>Flush()</c> matters: without it the package lives only as long as this process, and the
    /// endpoint a user copied disappears when they close the app. The out-of-process arm in
    /// <c>shell-lane.ps1</c> reads the clipboard from a different process, after seeding it with a
    /// sentinel first, so a clipboard that already held the endpoint cannot pass the arm.
    /// </remarks>
    private void OnCopyEndpointClicked(object sender, RoutedEventArgs e)
    {
        var package = new DataPackage { RequestedOperation = DataPackageOperation.Copy };
        package.SetText(_model.CurrentState.Endpoint);
        Clipboard.SetContent(package);
        Clipboard.Flush();
    }

    /// <summary>
    /// Re-renders the readout from the MODEL, never from the switches. That is the whole point of
    /// it: if a toggle stops writing through, the switch still moves and this line does not.
    /// </summary>
    private void RenderState()
    {
        StateSummaryText.Text = SettingsPresentation.StateSummary(_model.CurrentState);

        var durability = "Stored at " + (_model.StorePath ?? "nowhere - this session only")
            + " - sign-in state read from " + _model.LaunchAtLoginSource
            + ", notification-area state read from " + _model.AmbientIconSource + ".";
        if (_model.LastEffect is not null)
        {
            durability += " Last change: " + _model.LastEffect.Detail;
        }
        DurabilityText.Text = durability;
    }

    /// <summary>Exposed for the in-process self-test; the model is otherwise private to the
    /// board.</summary>
    internal RouterSettingsState CurrentState => _model.CurrentState;
}
