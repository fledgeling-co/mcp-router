using MCPRouter.Checks.Model;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace MCPRouter.Shell.Views;

/// <summary>
/// The Checks board: stored, version-stamped results, and the refusal to carry a green tick
/// forward (spec-WIN8).
///
/// The surface is built in code rather than bound, for the reason the shell's command surface
/// is: the board's rows, notices and detail are decisions the model has already made, and
/// building them here keeps the automation plane's names next to the words they name. Every
/// interactive element carries an <c>AutomationId</c> whose subject matches the on-screen
/// vocabulary, so WIN20's plane can measure the surface against itself.
///
/// Like every window on this floor, this control decides nothing about a verdict: the model
/// reconciles the store against the live versions, and this file draws what that reconciliation
/// concluded.
/// </summary>
public sealed partial class ChecksBoard : UserControl
{
    /// <summary>The shared column widths of the header and every row, so the table is one
    /// table.</summary>
    private static readonly GridLength[] ColumnWidths =
    [
        new GridLength(2, GridUnitType.Star),   // capability
        new GridLength(140),                    // version (Consolas)
        new GridLength(130),                    // result
        new GridLength(2, GridUnitType.Star),   // checks
        new GridLength(110),                    // ran (Consolas)
        new GridLength(1, GridUnitType.Auto),   // the per-row action
    ];

    private readonly ChecksBoardModel _model;
    private readonly ControlClient _client;
    private bool _busy;
    private bool _rebuildingList;
    private string? _selectedSubjectId;

    public ChecksBoard()
    {
        InitializeComponent();

        HeadSubtitle.Text = CheckCopy.BoardSubtitle;
        FooterText.Text = CheckCopy.BoardFooter;
        EmptyTitle.Text = CheckCopy.EmptyTitle;
        EmptyDetail.Text = CheckCopy.EmptyDetail;
        RetryButton.Content = CheckCopy.RetryLabel;
        RunAllButton.Content = CheckCopy.RunAllLabel;
        RunStaleButton.Content = CheckCopy.RunStaleLabel;

        _client = new ControlClient();
        _model = new ChecksBoardModel(_client, new CheckHistoryStore(CheckHistoryStore.DefaultDirectory()));

        BuildHeader();
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        await RefreshAsync();
    }

    /// <summary>The read path, real: one loopback fetch, then the reconciliation. What this
    /// draws on a machine with no router is the disconnected state, which is an honest reading
    /// of that machine (spec-WIN8 §7 gap 1).</summary>
    private async Task RefreshAsync()
    {
        SetBusyUi(true);
        try
        {
            await _model.LoadAsync();
        }
        finally
        {
            SetBusyUi(false);
        }

        Render();
    }

    // ------------------------------------------------------------------ the runs

    private async void OnRunAllClick(object sender, RoutedEventArgs e) =>
        await RunRowsAsync(_model.Rows.ToArray());

    private async void OnRunStaleClick(object sender, RoutedEventArgs e) =>
        await RunRowsAsync(_model.Rows.Where(r => r.Result.IsStale).ToArray());

    private async void OnRetryClick(object sender, RoutedEventArgs e) =>
        await RefreshAsync();

    private async void OnRowRunClick(object sender, RoutedEventArgs e)
    {
        if (_busy || _model.RunningSubject is not null)
        {
            return;
        }

        if (((FrameworkElement)sender).DataContext is ChecksBoardModel.Row row)
        {
            await RunRowsAsync([row]);
        }
    }

    private async void OnNoticeRerunClick(object sender, RoutedEventArgs e)
    {
        if (_busy || ((FrameworkElement)sender).DataContext is not ChecksBoardModel.Row row)
        {
            return;
        }

        await RunRowsAsync([row]);
    }

    /// <summary>The one run loop. It iterates so the board can re-render between subjects - the
    /// progress line and each fresh row appear as they happen, which is the honest running
    /// signal for a run shaped like this one: a fetch and a derivation per subject.</summary>
    private async Task RunRowsAsync(IReadOnlyList<ChecksBoardModel.Row> rows)
    {
        if (_busy)
        {
            return;
        }

        _busy = true;
        try
        {
            foreach (var row in rows)
            {
                await _model.RunAsync(row);
                Render();
            }
        }
        finally
        {
            _busy = false;
        }

        Render();
    }

    private void SetBusyUi(bool busy)
    {
        RunAllButton.IsEnabled = !busy;
        RunStaleButton.IsEnabled = !busy && _model.Invalidations.Count > 0;
    }

    // ------------------------------------------------------------------ rendering

    /// <summary>Draws the board as the model now is: the state the §5 matrix names, then the
    /// notices, the table and the detail inside the loaded state.</summary>
    private void Render()
    {
        HeadTitle.Text = "Checks";

        // The two head actions, with their discoverable reasons (§5's disabled row).
        RunAllButton.IsEnabled = !_busy;
        RunStaleButton.IsEnabled = !_busy && _model.Invalidations.Count > 0;
        AutomationProperties.SetHelpText(
            RunStaleButton,
            RunStaleButton.IsEnabled ? string.Empty : CheckCopy.RunStaleDisabledReason);

        ProgressText.Text = _model.RunningSubject is null
            ? string.Empty
            : CheckCopy.RunningNow(_model.RunningSubject, _model.RunningIndex, _model.RunningTotal);
        ProgressText.Visibility = _model.RunningSubject is null ? Visibility.Collapsed : Visibility.Visible;

        var hasRows = _model.Rows.Count > 0;
        LoadingPanel.Visibility = _model.State == ChecksBoardModel.LoadState.Loading ? Visibility.Visible : Visibility.Collapsed;
        EmptyPanel.Visibility = _model.State == ChecksBoardModel.LoadState.Loaded && !hasRows ? Visibility.Visible : Visibility.Collapsed;
        DisconnectedPanel.Visibility = _model.State is ChecksBoardModel.LoadState.Failed ? Visibility.Visible : Visibility.Collapsed;
        LoadedPanel.Visibility = _model.State is ChecksBoardModel.LoadState.Loaded or ChecksBoardModel.LoadState.Stale
            ? Visibility.Visible
            : Visibility.Collapsed;

        if (DisconnectedPanel.Visibility == Visibility.Visible)
        {
            DisconnectedHeadline.Text = _model.Error?.Headline ?? CheckCopy.RouterNotRunningHeadline;
            DisconnectedAdvice.Text = _model.Error?.Advice ?? CheckCopy.RouterNotRunningAdvice;
        }

        if (LoadedPanel.Visibility != Visibility.Visible)
        {
            return;
        }

        RenderErrorBar();
        RenderPartialNote();
        RenderHistoryErrorBar();
        RenderInvalidations();
        RebuildRows();
        RenderDetail();
    }

    private void RenderErrorBar()
    {
        if (_model.State == ChecksBoardModel.LoadState.Stale && _model.Error is { } error)
        {
            ErrorBar.Title = error.Headline;
            ErrorBar.Message = error.Advice;
            ErrorBar.IsOpen = true;
        }
        else
        {
            ErrorBar.IsOpen = false;
        }
    }

    private void RenderPartialNote()
    {
        if (_model.SkillsAbsentReasons.Count > 0)
        {
            PartialNote.Title = "Skills could not be read";
            PartialNote.Message = CheckCopy.SkillsUnreadable(_model.SkillsAbsentReasons[0]);
            PartialNote.IsOpen = true;
        }
        else
        {
            PartialNote.IsOpen = false;
        }
    }

    private void RenderHistoryErrorBar()
    {
        if (_model.HistoryError is { } error)
        {
            HistoryErrorBar.Title = "Stored history could not be read";
            HistoryErrorBar.Message = CheckCopy.HistoryUnreadable(error);
            HistoryErrorBar.IsOpen = true;
        }
        else
        {
            HistoryErrorBar.IsOpen = false;
        }
    }

    private void RenderInvalidations()
    {
        InvalidationList.Children.Clear();

        foreach (var notice in _model.Invalidations)
        {
            var row = _model.Rows.FirstOrDefault(r => r.SubjectId == notice.SubjectId);

            var rerun = new Button { Content = CheckCopy.RerunLabel(notice.Name) };
            rerun.DataContext = row;
            rerun.Click += OnNoticeRerunClick;
            AutomationProperties.SetAutomationId(rerun, $"Checks.Invalidation.{notice.SubjectId}.Rerun");
            AutomationProperties.SetName(rerun, CheckCopy.RerunLabel(notice.Name));

            var bar = new InfoBar
            {
                Severity = InfoBarSeverity.Warning,
                IsClosable = false,
                IsOpen = true,
                Message = CheckCopy.Invalidated(notice.Name, notice.StoredStamp, notice.LiveStamp),
                ActionButton = rerun,
            };
            AutomationProperties.SetAutomationId(bar, $"Checks.Invalidation.{notice.SubjectId}");
            AutomationProperties.SetName(bar, $"Result dropped: {notice.Name}");

            InvalidationList.Children.Add(bar);
        }
    }

    // ------------------------------------------------------------------ the table

    private void BuildHeader()
    {
        HeaderRow.Children.Clear();
        HeaderRow.ColumnDefinitions.Clear();
        for (var i = 0; i < ColumnWidths.Length; i++)
        {
            HeaderRow.ColumnDefinitions.Add(new ColumnDefinition { Width = ColumnWidths[i] });
        }

        string[] headers = ["Capability", "Version", "Result", "Checks", "Ran", string.Empty];
        for (var i = 0; i < headers.Length; i++)
        {
            var cell = new TextBlock
            {
                Text = headers[i],
                Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"],
                Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
                VerticalAlignment = VerticalAlignment.Center,
            };
            if (headers[i].Length > 0)
            {
                AutomationProperties.SetAutomationId(cell, $"Checks.ColumnHeader.{headers[i]}");
                AutomationProperties.SetName(cell, headers[i]);
            }

            Grid.SetColumn(cell, i);
            HeaderRow.Children.Add(cell);
        }

        // The instrument voice: stamps and timestamps are Consolas (§12).
        AutomationProperties.SetAutomationId(HeaderRow, "Checks.TableHeader");
    }

    private void RebuildRows()
    {
        _rebuildingList = true;
        RowsList.Items.Clear();

        foreach (var row in _model.Rows)
        {
            RowsList.Items.Add(BuildRow(row));
        }

        // Restore the selection the board had before the rebuild, if it survived.
        if (_selectedSubjectId is { } wanted)
        {
            var index = 0;
            var found = -1;
            foreach (var candidate in _model.Rows)
            {
                if (candidate.SubjectId == wanted)
                {
                    found = index;
                    break;
                }

                index++;
            }

            if (found >= 0)
            {
                RowsList.SelectedIndex = found;
            }
        }

        _rebuildingList = false;
    }

    private ListBoxItem BuildRow(ChecksBoardModel.Row row)
    {
        var grid = new Grid { Margin = new Thickness(12, 6, 12, 6) };
        foreach (var width in ColumnWidths)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = width });
        }

        // Capability: the name, and under it what the row is about (its transport).
        var nameStack = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        var name = new TextBlock
        {
            Text = row.Name,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Style = (Style)Application.Current.Resources["BodyTextBlockStyle"],
        };
        var kind = new TextBlock
        {
            Text = row.Detail,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
            Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        };
        AutomationProperties.SetAutomationId(name, $"Checks.Row.{row.SubjectId}.Capability");
        nameStack.Children.Add(name);
        nameStack.Children.Add(kind);
        Grid.SetColumn(nameStack, 0);
        grid.Children.Add(nameStack);

        // Version: the live stamp, in the instrument voice.
        var version = Monospace(row.LiveStamp?.Value ?? CheckCopy.NoRunMark);
        AutomationProperties.SetAutomationId(version, $"Checks.Row.{row.SubjectId}.Version");
        Grid.SetColumn(version, 1);
        grid.Children.Add(version);

        // Result: the word, with its hue beside it - never the hue alone (§12). An ordinary
        // reading draws no mark at all, for the Mac's reason: a confirmation is not a running
        // process, so the success hue is not spent on it.
        var resultStack = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            VerticalAlignment = VerticalAlignment.Center,
        };
        if (row.Result.Tone is ChecksBoardModel.RowResult.RowTone.Critical
            or ChecksBoardModel.RowResult.RowTone.Caution)
        {
            resultStack.Children.Add(new Ellipse
            {
                Width = 8,
                Height = 8,
                VerticalAlignment = VerticalAlignment.Center,
                Fill = ToneBrush(row.Result.Tone),
            });
        }

        var resultWord = new TextBlock
        {
            Text = row.Result.Word,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = row.Result.Tone == ChecksBoardModel.RowResult.RowTone.Critical
                ? (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"]
                : (Brush)Application.Current.Resources["TextFillColorPrimaryBrush"],
        };
        AutomationProperties.SetAutomationId(resultWord, $"Checks.Row.{row.SubjectId}.Result");
        resultStack.Children.Add(resultWord);
        Grid.SetColumn(resultStack, 2);
        grid.Children.Add(resultStack);

        // Checks: the tally segments, the stale pointer, or the could-not-run reason.
        var checks = new TextBlock
        {
            Text = row.Result.Detail ?? string.Empty,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        };
        AutomationProperties.SetAutomationId(checks, $"Checks.Row.{row.SubjectId}.Checks");
        Grid.SetColumn(checks, 3);
        grid.Children.Add(checks);

        // Ran: when the stored run happened, or the mark that says nothing is stored.
        var ran = Monospace(row.Ran);
        ran.Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
        AutomationProperties.SetAutomationId(ran, $"Checks.Row.{row.SubjectId}.Ran");
        Grid.SetColumn(ran, 4);
        grid.Children.Add(ran);

        // The per-row action.
        var runButton = new Button
        {
            Content = CheckCopy.RunOneLabel,
            MinWidth = 64,
            DataContext = row,
            IsEnabled = !_busy,
        };
        runButton.Click += OnRowRunClick;
        AutomationProperties.SetAutomationId(runButton, $"Checks.Row.{row.SubjectId}.Run");
        AutomationProperties.SetName(runButton, $"{CheckCopy.RunOneLabel} {row.Name}");
        Grid.SetColumn(runButton, 5);
        grid.Children.Add(runButton);

        var item = new ListBoxItem
        {
            Content = grid,
            MinHeight = 44,
            VerticalContentAlignment = VerticalAlignment.Center,
        };
        // The plane reads the row by its name - the capability's own word - and finds each cell
        // under the row's id (the WIN20 contract: names matching the on-screen vocabulary).
        AutomationProperties.SetAutomationId(item, $"Checks.Row.{row.SubjectId}");
        AutomationProperties.SetName(item, row.Name);
        return item;
    }

    private TextBlock Monospace(string text) => new()
    {
        Text = text,
        FontFamily = new FontFamily("Consolas"),
        VerticalAlignment = VerticalAlignment.Center,
        TextTrimming = TextTrimming.CharacterEllipsis,
    };

    private Brush ToneBrush(ChecksBoardModel.RowResult.RowTone tone) => tone switch
    {
        ChecksBoardModel.RowResult.RowTone.Critical => (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"],
        ChecksBoardModel.RowResult.RowTone.Caution => (Brush)Application.Current.Resources["SystemFillColorCautionBrush"],
        _ => (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
    };

    // ------------------------------------------------------------------ the detail

    private void OnRowSelected(object sender, SelectionChangedEventArgs e)
    {
        if (_rebuildingList)
        {
            return;
        }

        if (RowsList.SelectedIndex >= 0 && RowsList.SelectedIndex < _model.Rows.Count)
        {
            _selectedSubjectId = _model.Rows[RowsList.SelectedIndex].SubjectId;
        }

        RenderDetail();
    }

    /// <summary>
    /// The selected capability's last complete run, the six checks with their verdicts, the
    /// failing exchanges, and the version-labelled history.
    ///
    /// The heading names the version the run belongs to - so a dropped run can be inspected
    /// without ever being presented against the version that replaced it.
    /// </summary>
    private void RenderDetail()
    {
        DetailPanel.Children.Clear();

        var row = _model.Rows.FirstOrDefault(r => r.SubjectId == _selectedSubjectId);
        if (row is null)
        {
            DetailCard.Visibility = Visibility.Collapsed;
            return;
        }

        DetailCard.Visibility = Visibility.Visible;

        var shownRun = row.Result.Run ?? row.History.FirstOrDefault();
        var heading = new TextBlock
        {
            Text = shownRun is null ? CheckCopy.NoStoredRun(row.Name) : CheckCopy.LastCompleteRun(row.Name, shownRun.Stamp),
            Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"],
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        AutomationProperties.SetAutomationId(heading, "Checks.Detail.Heading");
        DetailPanel.Children.Add(heading);

        if (shownRun is null)
        {
            var nothing = new TextBlock
            {
                Text = row.Result.Detail ?? CheckCopy.NotCheckedDetail(6),
                Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
                TextWrapping = TextWrapping.Wrap,
            };
            DetailPanel.Children.Add(nothing);
            return;
        }

        var results = _model.StoredResults(row);
        foreach (var result in results)
        {
            DetailPanel.Children.Add(BuildCheckLine(result, row));
        }

        DetailPanel.Children.Add(new TextBlock
        {
            Text = CheckCopy.HistoryHeading,
            Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"],
            Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            Margin = new Thickness(0, 8, 0, 0),
        });

        var history = new StackPanel { Spacing = 4 };
        AutomationProperties.SetAutomationId(history, "Checks.HistoryList");
        AutomationProperties.SetName(history, CheckCopy.HistoryHeading);
        foreach (var run in row.History)
        {
            var confirmed = run.Results.Count(r => r.VerdictValue == CheckVerdict.Passed);
            var line = Monospace(CheckCopy.HistoryRow(
                run.Stamp,
                confirmed,
                run.Results.Count,
                RelativeTime.Ago(run.RanAt, DateTimeOffset.Now)));
            line.Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
            AutomationProperties.SetAutomationId(line, $"Checks.HistoryRow.{run.Stamp}");
            history.Children.Add(line);
        }

        if (row.History.Count == 0)
        {
            history.Children.Add(new TextBlock
            {
                Text = CheckCopy.UnstampableDetail,
                Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
                TextWrapping = TextWrapping.Wrap,
            });
        }

        DetailPanel.Children.Add(history);
    }

    /// <summary>One check's reading: the statement it judges, the word, and for everything that
    /// is not a confirmation, the exchange - the reason and the input it was computed from.
    /// The brief's refusal: a failing check opens to the exchange that failed, not to a
    /// count.</summary>
    private StackPanel BuildCheckLine(CheckResult result, ChecksBoardModel.Row row)
    {
        var line = new StackPanel { Spacing = 2 };
        AutomationProperties.SetAutomationId(line, $"Checks.Check.{CheckIdWords.For(result.Check)}");
        AutomationProperties.SetName(line, $"{result.Statement}: {result.VerdictWord}");

        var head = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        head.Children.Add(new FontIcon
        {
            Glyph = result.Verdict switch
            {
                CheckVerdict.Passed => "\uE73E",       // check mark
                CheckVerdict.Failed => "\uE711",       // cancel
                CheckVerdict.Unknown => "\uE823",      // recent / clock: not yet observed
                _ => "\uE738",                          // remove / minus: the question does not arise
            },
            FontFamily = (FontFamily)Application.Current.Resources["SymbolThemeFontFamily"],
            FontSize = 14,
            Foreground = result.Verdict == CheckVerdict.Failed
                ? (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"]
                : (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        });
        head.Children.Add(new TextBlock
        {
            Text = result.Statement,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
        });
        head.Children.Add(new TextBlock
        {
            Text = result.VerdictWord,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = result.Verdict == CheckVerdict.Failed
                ? (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"]
                : (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        });
        line.Children.Add(head);

        if (result.Reason is { } reason)
        {
            line.Children.Add(new TextBlock
            {
                Text = reason,
                Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(22, 0, 0, 0),
            });
        }

        // The input side of the exchange. It exists only for a current row - the live record is
        // the current version's, and printing its field values beside a superseded run's
        // evidence would be exactly the presentation the version rule forbids.
        if (_model.Input(result, row) is { } input)
        {
            var inputLine = Monospace(input);
            inputLine.Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
            inputLine.TextWrapping = TextWrapping.Wrap;
            inputLine.Margin = new Thickness(22, 0, 0, 0);
            line.Children.Add(inputLine);
        }

        return line;
    }

    /// <summary>Run all, from the command surface (Library → Run all checks). The shell navigates
    /// here and then calls in.</summary>
    public async Task RunAllFromCommandAsync()
    {
        await RefreshAsync();
        await RunRowsAsync(_model.Rows.ToArray());
    }
}
