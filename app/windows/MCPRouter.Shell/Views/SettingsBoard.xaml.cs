using System;
using MCPRouter.Shell.Model.Settings;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace MCPRouter.Shell.Views;

/// <summary>
/// The Settings board. DEF-076: it rendered three of the seven sections WIN13 declares, and its
/// switches were unbound and unnamed.
///
/// The names and ids are stamped here rather than typed into the XAML because
/// <see cref="SettingsPresentation" /> is the one place the section list, the toggle keys and
/// their labels are declared, and the out-of-process UIA lane reads the same file. A string typed
/// into the view and again into the harness drifts, and then the lane measures a board that does
/// not exist.
/// </summary>
public sealed partial class SettingsBoard : UserControl
{
    private readonly SettingsBoardModel _model = new();

    public SettingsBoard()
    {
        InitializeComponent();

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
    }

    private void OnToggled(object sender, RoutedEventArgs e)
    {
        if (sender is not ToggleSwitch toggle || toggle.Tag is not string key) return;
        _model.UpdateToggle(key, toggle.IsOn);
        RenderState();
    }

    /// <summary>
    /// Re-renders the readout from the MODEL, never from the switches. That is the whole point of
    /// it: if a toggle stops writing through, the switch still moves and this line does not.
    /// </summary>
    private void RenderState()
    {
        StateSummaryText.Text = SettingsPresentation.StateSummary(_model.CurrentState);
    }

    /// <summary>Exposed for the in-process self-test; the model is otherwise private to the
    /// board.</summary>
    internal RouterSettingsState CurrentState => _model.CurrentState;
}
