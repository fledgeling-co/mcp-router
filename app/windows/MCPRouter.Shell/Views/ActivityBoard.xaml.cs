using System.Collections.Concurrent;
using System.Collections.ObjectModel;
using MCPRouter.Shell.Live;
using MCPRouter.Shell.Model;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Windows.Storage.Pickers;

namespace MCPRouter.Shell.Views;

/// <summary>
/// The Activity board: every tool call every harness made, as it happens.
///
/// Two halves, deliberately separated. Everything below the XAML is the wire library
/// (<c>MCPRouter.Shell.Live</c>) driving <see cref="ActivityModel"/> on the UI thread; this file
/// is only the presentation of it - the states of spec §4 as one exhaustive switch, the copy as
/// <see cref="ActivityCopy"/>'s own words, and the stream's lifetime scoped to the board's
/// presence: navigating away cancels the feed, returning starts it again.
///
/// The subscribe/backfill sequencing closes the gap a naive implementation has: the stream is
/// opened first, records that arrive before the <c>GET /usage</c> backfill lands are buffered,
/// the backfill then rebuilds the window, and the buffered records are prepended on top of it.
/// The model's de-duplication absorbs the overlap, so a call in the seam between the two halves
/// is on screen exactly once - never dropped, never doubled.
/// </summary>
public sealed partial class ActivityBoard : UserControl
{
    private const int SkeletonRowCount = 6;

    private readonly ActivityModel _model = new();
    private readonly DispatcherQueue _dispatcher;
    private readonly Window _owner;
    private readonly Action<string> _navigate;

    /// <summary>The rows the list is showing right now. Rebuilt structurally on backfill,
    /// filter and resume changes; incremented in place on ordinary live arrivals, so the
    /// reader's scroll position survives a log that updates under it.</summary>
    private readonly ObservableCollection<ActivityRowPresentation> _rows = new();

    /// <summary>The records behind those rows - what Export… hands to the file, so what the
    /// dialog says it writes ("the calls on screen") is exactly what it writes.</summary>
    private IReadOnlyList<CallRecord> _presentedRecords = Array.Empty<CallRecord>();

    private readonly ConcurrentQueue<CallRecord> _preBackfill = new();
    private UsageStreamClient? _client;
    private CancellationTokenSource? _feedCts;
    private bool _backfillApplied;
    private bool _backfillFailed;
    private bool _stopped;
    private int _pausedVisibleCount;
    private string _pillsSignature = "";

    public ActivityBoard(Destination destination, Window owner, Action<string> navigate)
    {
        InitializeComponent();
        _dispatcher = DispatcherQueue.GetForCurrentThread();
        _owner = owner;
        _navigate = navigate;

        // The board's words, from the one place the tests read them. XAML cannot bind a const,
        // so the constructor hands them out; a paraphrase typed here would be a sentence the
        // sentence-case and §6 sweeps never see.
        MissionText.Text = ActivityCopy.Mission;
        FootText.Text = ActivityCopy.Foot;
        LoadingStatusText.Text = ActivityCopy.LoadingStatus;
        EmptyTitleText.Text = ActivityCopy.EmptyTitle;
        EmptyDetailText.Text = ActivityCopy.EmptyDetail;
        OfflineTitleText.Text = ActivityCopy.OfflineTitle;
        OfflineDetailText.Text = ActivityCopy.OfflineDetail;
        FilteredTitleText.Text = ActivityCopy.FilteredTitle;
        FilteredDetailText.Text = ActivityCopy.FilteredDetail(_model.Records.Count);

        HeaderTime.Text = ActivityCopy.Columns[0];
        HeaderHarness.Text = ActivityCopy.Columns[1];
        HeaderTool.Text = ActivityCopy.Columns[2];
        HeaderDuration.Text = ActivityCopy.Columns[3];
        HeaderResult.Text = ActivityCopy.Columns[4];

        EmptyGlyph.Glyph = SymbolGlyph(destination.Symbol);
        OfflineGlyph.Glyph = SymbolGlyph("Refresh");
        FilteredGlyph.Glyph = SymbolGlyph("Filter");

        EmptyActionButton.Content = ActivityCopy.EmptyAction;
        EmptyActionButton.AccessKey = "S";
        ReconnectButton.Content = ActivityCopy.ReconnectLabel;
        ReconnectButton.AccessKey = "R";
        ClearFiltersButton.Content = ActivityCopy.ClearFiltersLabel;
        ClearFiltersButton.AccessKey = "C";

        ReconnectingBanner.Message =
            $"{ActivityCopy.PartialReconnectingTitle} {ActivityCopy.NewestSentence(null)}";
        DisconnectedBanner.Message = $"{ActivityCopy.DisconnectedTitle} {ActivityCopy.DisconnectedDetail(null)}";
        var reconnectNow = new Button
        {
            Content = ActivityCopy.ReconnectNowLabel,
        };
        reconnectNow.AccessKey = "N";
        reconnectNow.Click += OnReconnectClicked;
        AutomationProperties.SetName(reconnectNow, ActivityCopy.ReconnectNowLabel);
        DisconnectedBanner.ActionButton = reconnectNow;

        BuildSkeleton();
        BuildFilters();

        // The full automation name goes on the container (a ListViewItem), because the row
        // itself is a Grid whose own name would be one more stop in the tree - the spec's row
        // label is one value a screen reader reads whole.
        RowsList.ContainerContentChanging += OnRowContainerChanging;
        RowsList.ItemsSource = _rows;

        Unloaded += OnUnloaded;

        StartFeed();
    }

    /// <summary>The Segoe Fluent codepoint behind a <see cref="Symbol"/> value - the same
    /// conversion BoardPlaceholder makes, so a symbol is never spelled twice.</summary>
    private static string SymbolGlyph(string symbolName) =>
        char.ConvertFromUtf32((int)Enum.Parse<Symbol>(symbolName));

    // ------------------------------------------------------------------ the feed

    private void StartFeed()
    {
        StopFeed();
        _stopped = false;
        _feedCts = new CancellationTokenSource();
        var token = _feedCts.Token;

        // A client being replaced keeps its socket pool until the process lets it go rather
        // than being disposed under a request in flight; the board's lifetime is the window's,
        // so the pool outlives it by no more than the window does.
        _client = new UsageStreamClient();
        _backfillApplied = false;
        _backfillFailed = false;
        _preBackfill.Clear();

        _ = RunFeedAsync(token);
        _ = RunBackfillAsync(token);
    }

    private void StopFeed()
    {
        _stopped = true;
        _feedCts?.Cancel();
    }

    private async Task RunFeedAsync(CancellationToken cancellationToken)
    {
        try
        {
            await foreach (var e in _client!.EventsAsync(cancellationToken))
            {
                switch (e)
                {
                    case StreamEvent.Phase phase:
                        OnPhase(phase.Value);
                        break;
                    case StreamEvent.Record record:
                        OnRecord(record.Value);
                        break;
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Walking away is not a failure; it is the board leaving the screen.
        }
    }

    private async Task RunBackfillAsync(CancellationToken cancellationToken)
    {
        try
        {
            var snapshot = await _client!.SnapshotAsync(cancellationToken);
            _dispatcher.TryEnqueue(() =>
            {
                if (_stopped) return;
                _model.Load(snapshot.Records);
                while (_preBackfill.TryDequeue(out var buffered))
                {
                    _model.Prepend(buffered);
                }

                _backfillApplied = true;
                Render();
            });
        }
        catch (OperationCanceledException)
        {
            // The board left the screen mid-read.
        }
        catch (Exception)
        {
            // The router did not answer the backfill. The stream's own ladder keeps trying and
            // its phases draw what is true meanwhile; when the stream reaches Live, the backfill
            // is retried from there rather than here, because a retry loop in this catch would
            // hammer a router that is merely slow to bind its port.
            _dispatcher.TryEnqueue(() =>
            {
                if (_stopped) return;
                _backfillFailed = true;
                Render();
            });
        }
    }

    private void OnPhase(StreamPhase phase)
    {
        _dispatcher.TryEnqueue(() =>
        {
            if (_stopped) return;
            _model.Phase = phase;
            if (phase == StreamPhase.Live && !_backfillApplied)
            {
                // The stream is up but the history never landed (or landed before this client
                // existed). One more backfill against a router that is demonstrably answering.
                if (_feedCts is { } cts) _ = RunBackfillAsync(cts.Token);
            }

            Render();
        });
    }

    private void OnRecord(CallRecord record)
    {
        if (!_backfillApplied)
        {
            // Held until the backfill lands; the model's dedup then absorbs the overlap. This
            // queue is the reason a call in the seam is neither lost nor doubled.
            _preBackfill.Enqueue(record);
            return;
        }

        _dispatcher.TryEnqueue(() =>
        {
            if (_stopped) return;
            if (!_model.Prepend(record)) return;

            if (_model.Paused)
            {
                // §3.3: the view is frozen, but the sentence about the pause stays current -
                // it is a count of what was actually held, and it grows as records land.
                PausedNote.Text = ActivityCopy.CallsArrivedWhilePaused(_model.RecordsWhilePaused);
                PausedNote.Visibility = Visibility.Visible;
                return;
            }

            Render();
        });
    }

    private void OnUnloaded(object sender, RoutedEventArgs e) => StopFeed();

    // ------------------------------------------------------------------ the head

    private void OnPauseClicked(object sender, RoutedEventArgs e)
    {
        var nowPaused = !_model.Paused;
        if (nowPaused)
        {
            // The slice on screen at the moment of pausing is the slice that stays - captured
            // before the flag flips, so the rows below are exactly what the reader was reading.
            _pausedVisibleCount = _model.VisibleRows().Count;
            _model.SetPaused(true);
        }
        else
        {
            _model.SetPaused(false);
        }

        // One control, both words: the label and the automation name flip together (§3.3).
        var label = nowPaused ? ActivityCopy.ResumeLabel : ActivityCopy.PauseLabel;
        PauseButton.Label = label;
        AutomationProperties.SetName(PauseButton, label);
        PauseButton.Icon = new SymbolIcon(nowPaused ? Symbol.Play : Symbol.Pause);
        Render();
    }

    private async void OnExportClicked(object sender, RoutedEventArgs e)
    {
        try
        {
            await ShowExportAsync();
        }
        catch (Exception ex)
        {
            StartupLog.Write($"activity export failed: {ex}");
        }
    }

    private async Task ShowExportAsync()
    {
        if (XamlRoot is null) return;

        var jsonRadio = new RadioButton
        {
            Content = ActivityCopy.ExportJson,
            GroupName = "activityExportFormat",
            IsChecked = true,
        };
        var csvRadio = new RadioButton
        {
            Content = ActivityExportCsvName(),
            GroupName = "activityExportFormat",
        };
        var content = new StackPanel { Spacing = 12 };
        content.Children.Add(new TextBlock
        {
            Text = ActivityCopy.ExportDialogDetail,
            TextWrapping = TextWrapping.Wrap,
        });
        content.Children.Add(jsonRadio);
        content.Children.Add(csvRadio);

        // §11 rule 4: the "do it" button leads and the safe action is rightmost - the reverse
        // of the Mac order. Primary is leftmost and takes the accent fill; Close sits right.
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = ActivityCopy.ExportDialogTitle,
            Content = content,
            PrimaryButtonText = ActivityCopy.ExportConfirm,
            CloseButtonText = ActivityCopy.ExportCancel,
            DefaultButton = ContentDialogButton.Primary,
        };

        var result = await dialog.ShowAsync();
        if (result != ContentDialogResult.Primary) return;
        await WriteExportAsync(jsonRadio.IsChecked == true);
    }

    private static string ActivityExportCsvName() => ActivityCopy.ExportCsv;

    private async Task WriteExportAsync(bool json)
    {
        // The ellipsis convention promises a further view before anything is written, and the
        // dialog's promise is the visible slice: these are the records behind the rows on
        // screen, in the order shown, window-capped (§3.5).
        var records = _presentedRecords;

        var picker = new FileSavePicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
            SuggestedFileName = $"activity-{DateTimeOffset.Now:yyyyMMdd-HHmmss}",
        };
        if (json)
        {
            picker.FileTypeChoices.Add(ActivityCopy.ExportJson, new List<string> { ".jsonl" });
        }
        else
        {
            picker.FileTypeChoices.Add(ActivityCopy.ExportCsv, new List<string> { ".csv" });
        }

        // An unpackaged WinUI 3 app must hand the picker its owner's HWND or the picker throws.
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(_owner);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

        var file = await picker.PickSaveFileAsync();
        if (file is null) return;

        var text = json ? ActivityExport.ToJsonLines(records) : ActivityExport.ToCsv(records);
        await Windows.Storage.FileIO.WriteTextAsync(file, text);
    }

    // ------------------------------------------------------------------ the filters

    private void BuildFilters()
    {
        for (var i = 0; i < ActivityCopy.Filters.Length; i++)
        {
            var word = ActivityCopy.Filters[i];
            var item = new SelectorBarItem { Text = word };
            AutomationProperties.SetAutomationId(item, $"activity.filter.{Slug(word)}");
            FilterBar.Items.Add(item);
        }

        FilterBar.Items[0].IsSelected = true; // one-of-n: the first word is All
        _model.Filter = ResultFilter.All;
    }

    private void OnFilterChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args)
    {
        if (sender.SelectedItem is not SelectorBarItem selected) return;
        var index = sender.Items.IndexOf(selected);
        if (index < 0) return;
        // The Filters array and the ResultFilter enum are in the same order by construction;
        // both are the spec's four words, so the cast is the whole mapping.
        _model.Filter = (ResultFilter)index;
        Render();
    }

    private void OnClearFiltersClicked(object sender, RoutedEventArgs e)
    {
        _model.Filter = ResultFilter.All;
        FilterBar.Items[0].IsSelected = true;
        RebuildTallies();
        foreach (var child in TallyPanel.Children.OfType<ToggleButton>())
        {
            child.IsChecked = true; // the handler re-includes the harness in the model
        }

        Render();
    }

    private void OnSeeHarnessesClicked(object sender, RoutedEventArgs e) => _navigate("harnesses");

    private void OnReconnectClicked(object sender, RoutedEventArgs e) => StartFeed();

    // ------------------------------------------------------------------ the tallies

    /// <summary>
    /// Rebuilds the harness pills, or updates their faces in place.
    ///
    /// The pills are rebuilt only when the set of harness keys changes - otherwise each face
    /// (word · count) is updated on the existing button, because a rebuild drops whatever
    /// keyboard focus was on a pill mid-visit. §3.1: the list is discovered from the window;
    /// a harness with no record behind it has no pill, and the counts are the model's own.
    /// </summary>
    private void RebuildTallies()
    {
        if (_model.Paused) return; // frozen with the view (§3.3)

        var tallies = _model.Tallies();
        var signature = string.Join("|", tallies.Select(t => t.Key));
        if (signature == _pillsSignature)
        {
            for (var i = 0; i < tallies.Count && i < TallyPanel.Children.Count; i++)
            {
                if (TallyPanel.Children[i] is ToggleButton pill)
                {
                    var vm = HarnessTallyVm.From(tallies[i], _model.IsHarnessIncluded(tallies[i].Key));
                    pill.Content = vm.Face;
                    AutomationProperties.SetName(pill, vm.Face);
                }
            }

            return;
        }

        _pillsSignature = signature;
        TallyPanel.Children.Clear();
        foreach (var tally in tallies)
        {
            var key = tally.Key;
            var pill = new ToggleButton
            {
                IsChecked = _model.IsHarnessIncluded(key),
            };
            pill.Checked += (_, _) =>
            {
                _model.SetHarnessIncluded(key, true);
                Render();
            };
            pill.Unchecked += (_, _) =>
            {
                _model.SetHarnessIncluded(key, false);
                Render();
            };

            AutomationProperties.SetAutomationId(pill, $"activity.harness.{Slug(tally.Label)}");
            RebuildTalliesFace(pill, tally);
            TallyPanel.Children.Add(pill);
        }
    }

    private static void RebuildTalliesFace(ToggleButton pill, HarnessTally tally)
    {
        var vm = HarnessTallyVm.From(tally, pill.IsChecked == true);
        pill.Content = vm.Face;
        // The automation name is the face - the words actually on screen - not the key the
        // model groups by (WIN20's plane reads what a sighted reader reads).
        AutomationProperties.SetName(pill, vm.Face);
    }

    // ------------------------------------------------------------------ the render

    private void Render()
    {
        var phase = _model.Phase;
        var paused = _model.Paused;
        var visible = paused ? _pausedVisibleCount : _model.VisibleRows().Count;
        var total = _model.Records.Count;

        StatusLine.Text = ActivityCopy.Subtitle(visible, ActivityCopy.FeedLabel(phase, paused));
        var filtered = visible != total;
        FilteredCountText.Text = ActivityCopy.FilteredCount(visible, total);
        FilteredCountText.Visibility = filtered ? Visibility.Visible : Visibility.Collapsed;
        if (!paused)
        {
            PausedNote.Text = ActivityCopy.CallsArrivedWhilePaused(_model.RecordsWhilePaused);
            PausedNote.Visibility = _model.RecordsWhilePaused > 0
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        // The banners speak only once the board has a history; before that the full-pane state
        // below is the whole truth, and a banner repeating it on top would say it twice.
        var banners = _backfillApplied;
        ReconnectingBanner.IsOpen = banners && phase == StreamPhase.Reconnecting;
        if (banners)
        {
            ReconnectingBanner.Message =
                $"{ActivityCopy.PartialReconnectingTitle} {ActivityCopy.NewestSentence(_model.NewestTs())}";
            DisconnectedBanner.Message =
                $"{ActivityCopy.DisconnectedTitle} {ActivityCopy.DisconnectedDetail(_model.NewestTs())}";
        }

        DisconnectedBanner.IsOpen = banners && phase == StreamPhase.Disconnected;

        RebuildTallies();

        // ---- the state, as one exhaustive switch (spec §4)
        var filteredToNothing = total > 0 && visible == 0;
        if (filteredToNothing)
        {
            // The held filter is satisfiable by nothing on this wire (§3.2), so it draws its
            // own honest sentence rather than the generic one.
            var held = _model.Filter == ResultFilter.Held;
            FilteredTitleText.Text = held ? ActivityCopy.HeldNothingTitle : ActivityCopy.FilteredTitle;
            FilteredDetailText.Text = held
                ? ActivityCopy.HeldNothingDetail
                : ActivityCopy.FilteredDetail(total);
            ShowState(FilteredPane);
        }
        else if (total == 0)
        {
            if (_backfillApplied)
            {
                // The history endpoint answered and holds nothing yet. Live means exactly the
                // mock's empty state; a dropped feed over no history keeps the empty pane (the
                // data half of what is true) and lets the banner carry the feed half.
                ShowState(phase == StreamPhase.Reconnecting ? LoadingPane : EmptyPane);
            }
            else if (_backfillFailed || phase == StreamPhase.Disconnected)
            {
                ShowState(OfflinePane);
            }
            else
            {
                ShowState(LoadingPane);
            }
        }
        else
        {
            ShowState(RowsHost);
            ApplyRows();
        }
    }

    private void ShowState(UIElement state)
    {
        RowsHost.Visibility = ReferenceEquals(state, RowsHost) ? Visibility.Visible : Visibility.Collapsed;
        LoadingPane.Visibility = ReferenceEquals(state, LoadingPane) ? Visibility.Visible : Visibility.Collapsed;
        EmptyPane.Visibility = ReferenceEquals(state, EmptyPane) ? Visibility.Visible : Visibility.Collapsed;
        OfflinePane.Visibility = ReferenceEquals(state, OfflinePane) ? Visibility.Visible : Visibility.Collapsed;
        FilteredPane.Visibility = ReferenceEquals(state, FilteredPane) ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>
    /// Brings the rows collection to the window as it now stands.
    ///
    /// Two fast paths keep a log that updates every second from replaying itself: one arrival
    /// inserts at the head, and one arrival at the cap both inserts at the head and drops the
    /// oldest. Everything else - backfill, resume, any filter change - is a structural rebuild.
    /// Reassigning the ItemsSource wholesale on every event would scroll the reader back to the
    /// top, which is how a log becomes a surface nobody can read.
    /// </summary>
    private void ApplyRows()
    {
        var records = _model.VisibleRows();
        _presentedRecords = records;

        if (_rows.Count == records.Count - 1
            && (_rows.Count == 0 || !ReferenceEquals(_rows[0].Row, records[0])))
        {
            _rows.Insert(0, new ActivityRowPresentation(ActivityRowVm.From(records[0])));
            return;
        }

        if (_rows.Count == records.Count
            && records.Count > 1
            && !ReferenceEquals(_rows[0].Row, records[0])
            && ReferenceEquals(_rows[1].Row, records[1]))
        {
            // At the cap: the newest arrived and the oldest rotated out - the router's own ring
            // behaviour, mirrored in the view rather than re-fetched.
            _rows.Insert(0, new ActivityRowPresentation(ActivityRowVm.From(records[0])));
            _rows.RemoveAt(_rows.Count - 1);
            return;
        }

        _rows.Clear();
        foreach (var record in records)
        {
            _rows.Add(new ActivityRowPresentation(ActivityRowVm.From(record)));
        }
    }

    private void OnRowContainerChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.Item is ActivityRowPresentation presentation)
        {
            AutomationProperties.SetName(args.ItemContainer, presentation.AutomationName);
        }
    }

    /// <summary>The loading state's skeleton: six rows at the true row geometry, bars where the
    /// instrument columns will be. No data, no spinner - the shape of what is coming (§4).</summary>
    private void BuildSkeleton()
    {
        uint[] widths = [76, 108, 240, 64];
        for (var row = 0; row < SkeletonRowCount; row++)
        {
            var line = new Grid { Height = 32, ColumnSpacing = 12 };
            for (var column = 0; column < widths.Length; column++)
            {
                line.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(widths[column]) });
                var bar = new Microsoft.UI.Xaml.Shapes.Rectangle
                {
                    Height = 12,
                    RadiusX = 4,
                    RadiusY = 4,
                    VerticalAlignment = VerticalAlignment.Center,
                    Fill = Application.Current.Resources.TryGetValue(
                        "ControlStrokeColorDefaultBrush", out var fill)
                        ? (Microsoft.UI.Xaml.Media.Brush)fill
                        : null,
                };
                line.Children.Add(bar);
                Grid.SetColumn(bar, column);
            }

            SkeletonRows.Children.Add(line);
        }
    }

    private static string Slug(string word) =>
        word.Length == 0
            ? "unattributed"
            : new string(word.Select(c => char.IsAsciiLetterOrDigit(c) ? char.ToLowerInvariant(c) : '-').ToArray());
}
