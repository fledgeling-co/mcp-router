using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using MCPRouter.Shell.Model.Cleanup;
using MCPRouter.Shell.Model.Registry;
using MCPRouter.Shell.Model.Servers;
using MCPRouter.Shell.Model.Settings;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace MCPRouter.Shell.Views;

/// <summary>
/// The Cleanup board: the servers the router lists that nothing has called, and the one
/// destructive control this board carries.
///
/// <para><b>DEF-302.</b> Until this change the board drew five invented rows from
/// <c>CleanupBoardModel.PopulateSampleData</c> and its Remove button's whole body was the comment
/// <c>// Removal dialog logic</c>. It rendered, carried an accessible name, passed contrast and
/// accepted a click — the inert-UI shape every presence check ever written passes. Both halves are
/// gone: the rows come from the router's own <c>GET /servers</c>, and Remove goes down the same
/// path the Servers board's does — <see cref="ControlApiClient.RemoveServerAsync"/>, gated by
/// <c>RequireConfirmationOnDestructive</c> read at the moment of the press.</para>
///
/// <para><b>The setting is read at the press, not cached at construction</b>, for the reason
/// <c>ServersBoard.RemoveSelectedAsync</c> gives: a board built before the operator turned the
/// switch ON would otherwise keep not asking, and that is the dangerous direction. The two boards
/// read the same store, so an operator who turned the switch on has covered both Removes in the
/// product rather than the one that happened to work.</para>
///
/// <para><b>What proves it worked is not this process.</b> The confirmation is a gate: declining
/// returns before the client is called at all. The lane's arms
/// <c>cleanup.requireConfirmation.baseline / .effect / .accepted / .silence</c> in
/// scripts/windows/uia/shell-lane.ps1 read the ROUTER's own server list over the control API from
/// a separate process, because the app's account of having asked is not evidence that it obeyed
/// the answer.</para>
/// </summary>
public sealed partial class CleanupBoard : UserControl
{
    /// <summary>The Servers board's cadence, for the same reason: the router publishes no feed
    /// this client consumes, so a timed poll is the authority for every row.</summary>
    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(5);

    private readonly CleanupBoardModel _model = new();
    private readonly ControlApiClient _client = new(new Uri(ControlEndpoint.BaseUrl() + "/"));

    private DispatcherTimer? _pollTimer;
    private bool _pollInFlight;
    private bool _removalInFlight;

    /// <summary>What the board last drew, as a string. A poll that reads the same servers back
    /// redraws nothing.</summary>
    /// <remarks>
    /// Not an optimisation. Rebuilding the row tree every five seconds tears down and re-creates
    /// every element an assistive client may be holding, so focus, checkbox state and any
    /// in-flight UIA walk are discarded on a cadence, whether or not anything changed. The lane's
    /// destination sweep reads this process's accessibility tree out of process, and the shell was
    /// observed dying mid-walk twice while this board polled behind it. A redraw is now an event -
    /// the reading moved - rather than a clock tick.
    /// </remarks>
    private string _drawn = string.Empty;

    public CleanupBoard()
    {
        InitializeComponent();

        AutomationProperties.SetName(this, "Cleanup");

        ScopeNote.Text = CleanupBoardModel.SkillsNotEnumerated;
        IrreversibleNote.Text = CleanupPresentation.RemoveIrreversibleNote;

        RemoveSelectedButton.Content = CleanupPresentation.RemoveLabel;
        AutomationProperties.SetAutomationId(RemoveSelectedButton, "cleanup.action.removeSelected");
        AutomationProperties.SetName(RemoveSelectedButton, CleanupPresentation.RemoveLabel);
        AutomationProperties.SetAutomationId(RemoveOutcomeText, "cleanup.state.removeOutcome");
        AutomationProperties.SetAutomationId(StatusLine, "cleanup.state.status");

        // The window selector is a flyout over the two windows the design names. Choosing one
        // re-derives the rows at once, and the heading moves with it, so the button and the list
        // cannot describe different windows.
        var windowFlyout = new MenuFlyout();
        foreach (var days in CleanupBoardModel.QuietWindowChoices)
        {
            var item = new MenuFlyoutItem { Text = CleanupBoardModel.WindowCaption(days), Tag = days };
            item.Click += OnQuietWindowChosen;
            windowFlyout.Items.Add(item);
        }
        WindowSelectorButton.Flyout = windowFlyout;
        AutomationProperties.SetAutomationId(WindowSelectorButton, "cleanup.action.window");
        AutomationProperties.SetHelpText(WindowSelectorButton, WindowSelectorHelp);
        ToolTipService.SetToolTip(WindowSelectorButton, WindowSelectorHelp);
        UpdateWindowUI();

        RenderRows();
    }

    private const string WindowSelectorHelp =
        "Chooses how long a server must be quiet before the board proposes it for removal.";

    private void UpdateWindowUI()
    {
        WindowSelectorButton.Content = CleanupBoardModel.WindowCaption(_model.SelectedDaysWindow);
        QuietSectionHeading.Text = CleanupBoardModel.QuietHeading(_model.SelectedDaysWindow);
    }

    private void OnQuietWindowChosen(object sender, RoutedEventArgs e)
    {
        if (sender is not MenuFlyoutItem { Tag: int days }) return;

        _model.SetQuietWindow(days);
        UpdateWindowUI();
        RenderRows();
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _pollTimer = new DispatcherTimer { Interval = PollInterval };
        _pollTimer.Tick += (_, _) => _ = PollAsync();
        _pollTimer.Start();
        _ = PollAsync();
    }

    private void OnUnloaded(object sender, RoutedEventArgs e) => _pollTimer?.Stop();

    /// <summary>
    /// One reading of the router, turned into rows.
    /// </summary>
    /// <remarks>
    /// A poll is skipped while a removal is in flight. The alternative is a refresh landing
    /// between the confirmation and the DELETE, clearing the selection the operator confirmed and
    /// leaving the outcome line describing a list that has already moved.
    /// </remarks>
    private async Task PollAsync()
    {
        if (_pollInFlight || _removalInFlight) return;
        _pollInFlight = true;
        try
        {
            var envelope = await _client.GetServersAsync();
            _model.Adopt(envelope, DateTimeOffset.Now);
        }
        catch (ControlApiException ex)
        {
            _model.Fail(CleanupPresentation.Unreachable(ex.UserFacingDescription));
        }
        finally
        {
            _pollInFlight = false;
        }

        RenderRows();
    }

    private void RenderRows()
    {
        var signature = Signature();
        if (signature == _drawn) return;
        _drawn = signature;

        NeverCalledContainer.Children.Clear();
        QuietContainer.Children.Clear();

        // Loading and unreachable are said out loud. An empty list drawn silently over a router
        // that never answered reads as "nothing to propose", which is a claim this board has no
        // reading for.
        if (_model.IsLoading)
        {
            StatusLine.Text = CleanupPresentation.LoadingLine;
            StatusLine.Visibility = Visibility.Visible;
        }
        else if (_model.ErrorMessage is { Length: > 0 } message)
        {
            StatusLine.Text = message;
            StatusLine.Visibility = Visibility.Visible;
        }
        else
        {
            StatusLine.Visibility = Visibility.Collapsed;
        }
        AutomationProperties.SetName(StatusLine, StatusLine.Text);

        var haveReading = !_model.IsLoading && _model.ErrorMessage is null;
        if (haveReading && _model.TotalCandidates == 0)
        {
            IdealView.Visibility = Visibility.Collapsed;
            EmptyView.Visibility = Visibility.Visible;
            return;
        }

        IdealView.Visibility = Visibility.Visible;
        EmptyView.Visibility = Visibility.Collapsed;

        foreach (var row in _model.NeverCalledRows)
        {
            NeverCalledContainer.Children.Add(CreateRowElement(row));
        }

        foreach (var row in _model.QuietRows)
        {
            QuietContainer.Children.Add(CreateRowElement(row));
        }

        UpdateSelectionUI();
    }

    private UIElement CreateRowElement(CleanupRow row)
    {
        var grid = new Grid { Padding = new Thickness(16, 12, 16, 12) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(200) }); // Name + Checkbox
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(100) }); // Kind
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(80) });  // Tools
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(120) }); // Installed
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }); // Why it might matter

        var checkStack = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var checkBox = new CheckBox
        {
            IsChecked = row.IsSelected,
            VerticalAlignment = VerticalAlignment.Center
        };
        AutomationProperties.SetName(checkBox, $"Select {row.Name}");
        // Addressable by name from outside the process, the way the Servers board's rows are: a
        // lane that has to find a row by its accessible name is one rename away from measuring
        // nothing, and a UIA name search returns the first match anywhere in the tree.
        AutomationProperties.SetAutomationId(checkBox, "cleanup.row." + row.Id);
        checkBox.Checked += (_, _) => { _model.SetSelection(row.Id, true); _drawn = Signature(); UpdateSelectionUI(); };
        checkBox.Unchecked += (_, _) => { _model.SetSelection(row.Id, false); _drawn = Signature(); UpdateSelectionUI(); };

        checkStack.Children.Add(checkBox);
        checkStack.Children.Add(new TextBlock
        {
            Text = row.Name,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center
        });
        Grid.SetColumn(checkStack, 0);
        grid.Children.Add(checkStack);

        var kindText = new TextBlock
        {
            Text = row.Kind == CleanupKind.Server ? "MCP server" : "Skill",
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(kindText, 1);
        grid.Children.Add(kindText);

        var toolsText = new TextBlock
        {
            Text = row.ToolCount.HasValue ? row.ToolCount.Value.ToString() : "—",
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"),
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(toolsText, 2);
        grid.Children.Add(toolsText);

        var installedText = new TextBlock
        {
            Text = row.InstalledDate,
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(installedText, 3);
        grid.Children.Add(installedText);

        var reasonText = new TextBlock
        {
            Text = row.WhyItMightStillMatter,
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            TextWrapping = TextWrapping.Wrap,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(reasonText, 4);
        grid.Children.Add(reasonText);

        // The per-row secondary button is gone with the sample data that gave it its labels. It
        // carried "Sign in instead", "Keep" and "Remove…" and had no Click handler at all — three
        // more inert affordances of exactly the shape DEF-302 is about, and nothing on this build
        // implements any of the three verbs per row. The row's facts stay; the false affordance
        // does not.
        return grid;
    }

    /// <summary>Everything the drawn tree depends on, in one string.</summary>
    private string Signature()
    {
        var parts = new List<string>
        {
            _model.IsLoading ? "loading" : "read",
            _model.ErrorMessage ?? string.Empty,
        };
        foreach (var row in _model.NeverCalledRows) parts.Add(Line("never", row));
        foreach (var row in _model.QuietRows) parts.Add(Line("quiet", row));
        return string.Join("\n", parts);

        // Every field a row draws, joined with a separator none of them can contain.
        static string Line(string band, CleanupRow row) => string.Join(
            "\u001f", band, row.Id, row.ToolCount?.ToString() ?? "-", row.InstalledDate,
            row.WhyItMightStillMatter, row.IsSelected ? "on" : "off");
    }

    private void UpdateSelectionUI()
    {
        int count = _model.SelectedCount;
        SelectedCountText.Text = $"{count} selected";
        RemoveSelectedButton.IsEnabled = count > 0 && !_removalInFlight;

        var reason = count > 0
            ? $"Removes {count} selected server(s) from the router. {CleanupPresentation.RemoveIrreversibleNote}"
            : CleanupPresentation.RemoveDisabledReason;
        AutomationProperties.SetHelpText(RemoveSelectedButton, reason);
        ToolTipService.SetToolTip(RemoveSelectedButton, reason);
    }

    private void OnRemoveSelectedClicked(object sender, RoutedEventArgs e) => _ = RemoveSelectedAsync();

    /// <summary>
    /// The destructive path. The second reader of <c>RequireConfirmationOnDestructive</c> in the
    /// build, and the reason the setting's promise is now true across the product rather than on
    /// one board.
    /// </summary>
    private async Task RemoveSelectedAsync()
    {
        if (_removalInFlight) return;

        var selected = _model.GetSelectedRows();
        if (selected.Count == 0) return;
        var names = selected.Select(r => r.Id).ToList();

        // Read at the moment of the action, off the file the Settings board writes.
        var confirmationRequired = new SettingsStore()
            .Load(new RouterSettingsState())
            .RequireConfirmationOnDestructive;

        if (confirmationRequired)
        {
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = CleanupPresentation.RemoveDialogTitle(names),
                Content = new TextBlock
                {
                    Text = CleanupPresentation.RemoveDialogBody(names),
                    TextWrapping = TextWrapping.Wrap,
                    MaxWidth = 380,
                },
                PrimaryButtonText = CleanupPresentation.RemoveCommitLabel,
                CloseButtonText = CleanupPresentation.RemoveCancelLabel(names.Count),
                DefaultButton = ContentDialogButton.Close,
            };
            // The gate returns BEFORE the client is called at all. Nothing below this point runs
            // on a decline, which is what makes it a gate rather than a report.
            if (await dialog.ShowAsync() != ContentDialogResult.Primary)
            {
                ShowRemoveOutcome(CleanupPresentation.Kept(names));
                return;
            }
        }

        _removalInFlight = true;
        UpdateSelectionUI();
        var removed = new List<string>();
        var failures = new List<string>();
        try
        {
            foreach (var name in names)
            {
                try
                {
                    await _client.RemoveServerAsync(name);
                    removed.Add(name);
                }
                catch (ControlApiException ex)
                {
                    // One refusal does not cancel the rest, and it is not folded into the success
                    // line either: what went and what did not are two facts.
                    failures.Add(CleanupPresentation.RemoveFailed(name, ex.UserFacingDescription));
                }
            }
        }
        finally
        {
            _removalInFlight = false;
        }

        var lines = new List<string>();
        if (removed.Count > 0)
        {
            lines.Add(confirmationRequired
                ? CleanupPresentation.Removed(removed)
                : CleanupPresentation.RemovedWithoutAsking(removed));
        }
        lines.AddRange(failures);
        ShowRemoveOutcome(string.Join(" ", lines));

        foreach (var name in removed) _model.SetSelection(name, false);
        await PollAsync();
    }

    private void ShowRemoveOutcome(string line)
    {
        RemoveOutcomeText.Text = line;
        RemoveOutcomeText.Visibility = Visibility.Visible;
        AutomationProperties.SetName(RemoveOutcomeText, line);
    }

    private void OnKeepAllClicked(object sender, RoutedEventArgs e)
    {
        _model.MarkAllAsKeep();
        RenderRows();
    }
}
