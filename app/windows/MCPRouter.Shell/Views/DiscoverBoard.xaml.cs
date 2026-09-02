using MCPRouter.Shell.Model.Registry;
using MCPRouter.Shell.Shell;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace MCPRouter.Shell.Views;

/// <summary>
/// The Windows Discover board: two bands over <c>GET /registry/search</c>, never one ranked
/// list; no install affordance on a row; a degraded registry drawn as itself.
///
/// This file draws answers and decides nothing. Every decision - which state the board is in,
/// what a row's date means, whether a figure may draw at all - comes from
/// <c>MCPRouter.Shell.Model.Registry</c>, which is gated headless; the parts that must not leak
/// into a view (the sanitiser, the state resolution, the trending refusal) cannot be reached
/// from here except through it. Every static string is assigned from <see cref="DiscoverCopy" />
/// so the gated catalog is the single source.
/// </summary>
public sealed partial class DiscoverBoard : UserControl
{
    private readonly DiscoverBoardModel _model;
    private readonly DispatcherQueueTimer _debounce;
    private PublisherFilter _publisherFilter = PublisherFilter.All;
    private RecencyWindow _window = RecencyWindow.AnyTime;
    private bool _renderingFilters;
    private bool _emptyActionClearsSearch;

    public DiscoverBoard()
    {
        InitializeComponent();

        _model = new DiscoverBoardModel(new RegistryClient());
        _debounce = DispatcherQueue.GetForCurrentThread().CreateTimer();
        _debounce.Interval = TimeSpan.FromMilliseconds(400);
        _debounce.IsRepeating = false;
        // Guarded: a Tick handler is `async void`, so a throw inside SearchAsync would fault a
        // task nobody awaits and surface - if at all - only when a collection runs its finalizer.
        // DEF-085's guard reports it at the moment it happens instead.
        var guardedSearch = GuardedDispatch.GuardedAsync("DiscoverBoard.DebounceTick", SearchAsync);
        _debounce.Tick += async (_, _) => await guardedSearch();

        BuildFilterItems();
        AssignStaticCopy();
        SkeletonRows.ItemsSource = Enumerable.Range(0, 6);

        SearchBox.TextChanged += OnSearchTextChanged;
        SearchBox.QuerySubmitted += OnQuerySubmitted;

        Loaded += async (_, _) => await SearchAsync();
    }

    // ------------------------------------------------------------------ static chrome

    private void AssignStaticCopy()
    {
        SearchBox.PlaceholderText = DiscoverCopy.SearchPlaceholder;
        AutomationProperties.SetName(SearchBox, DiscoverCopy.SearchAccessibilityLabel);
        WindowNote.Text = DiscoverCopy.WindowAppliesTo;
        LoadingHeadlineText.Text = DiscoverCopy.LoadingHeadline;
        SlowSearchNote.Text = DiscoverCopy.NoteSlowSearch;
        OfflineHeadlineText.Text = DiscoverCopy.OfflineHeadline;
        OfflineBodyText.Text = DiscoverCopy.OfflineBody;
        OfflineRetryButton.Content = DiscoverCopy.RetryAction;
        FailedHeadlineText.Text = DiscoverCopy.InstallFailedHeadline;
        FailedRetryButton.Content = DiscoverCopy.RetryAction;
        PartialRetryButton.Content = DiscoverCopy.RetryAction;
        RecentBandTitle.Text = DiscoverCopy.BandRecentlyChanged;
        RecentBandNote.Text = DiscoverCopy.BandRecentlyChangedNote;
        UsedBandTitle.Text = DiscoverCopy.BandMostUsed;
        UsedBandNote.Text = DiscoverCopy.BandMostUsedNote;
        RankingNoteText.Text = DiscoverCopy.RankingNote;
        TrendingNoteText.Text = DiscoverCopy.TrendingNote;
        StaleHeadlineText.Text = DiscoverCopy.StaleBannerHeadline;
    }

    private void BuildFilterItems()
    {
        _renderingFilters = true;

        foreach (PublisherFilter filter in Enum.GetValues<PublisherFilter>())
        {
            PublisherCombo.Items.Add(new ComboBoxItem { Content = filter.Label(), Tag = filter });
        }
        PublisherCombo.SelectedIndex = 0;
        AutomationProperties.SetName(PublisherCombo, DiscoverCopy.PublisherAll);
        ToolTipService.SetToolTip(PublisherCombo, DiscoverCopy.PublisherNote);

        foreach (RecencyWindow window in Enum.GetValues<RecencyWindow>())
        {
            WindowFilter.Items.Add(new ComboBoxItem { Content = window.Label(), Tag = window });
        }
        WindowFilter.SelectedIndex = 0;
        AutomationProperties.SetName(WindowFilter, DiscoverCopy.WindowLabel);
        ToolTipService.SetToolTip(WindowFilter, DiscoverCopy.WindowAppliesTo);

        _renderingFilters = false;
    }

    // ------------------------------------------------------------------ the search

    private void OnSearchTextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args) =>
        _debounce.Start();

    private void OnQuerySubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args)
    {
        // Return in the field searches now, cancelling the pending debounce rather than merely
        // running beside it - otherwise two searches go out and the slower one wins.
        _debounce.Stop();
        _ = SearchAsync();
    }

    private void OnRetryClicked(object sender, RoutedEventArgs e) => _ = SearchAsync();

    private void OnEmptyActionClicked(object sender, RoutedEventArgs e)
    {
        if (_emptyActionClearsSearch)
        {
            SearchBox.Text = "";
        }
        _debounce.Stop();
        _ = SearchAsync();
    }

    private async Task SearchAsync()
    {
        Render(new DiscoverOutcome(null, RegistryPresentation.ListStateKind.Loading, null, null, IsStale: false));
        var outcome = await _model.SearchAsync(SearchBox.Text);
        Render(outcome);
    }

    // ------------------------------------------------------------------ filters

    private void OnPublisherChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_renderingFilters || PublisherCombo.SelectedItem is not ComboBoxItem { Tag: PublisherFilter filter }) return;
        _publisherFilter = filter;
        RenderBands();
    }

    private void OnWindowChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_renderingFilters || WindowFilter.SelectedItem is not ComboBoxItem { Tag: RecencyWindow window }) return;
        _window = window;
        RenderBands();
    }

    // ------------------------------------------------------------------ rendering

    private void Render(DiscoverOutcome outcome)
    {
        var response = outcome.Response;

        LoadingPane.Visibility = outcome.Kind == RegistryPresentation.ListStateKind.Loading ? Visibility.Visible : Visibility.Collapsed;
        OfflinePane.Visibility = outcome.Kind == RegistryPresentation.ListStateKind.Offline ? Visibility.Visible : Visibility.Collapsed;
        FailedPane.Visibility = outcome.Kind == RegistryPresentation.ListStateKind.Failed && !outcome.IsStale ? Visibility.Visible : Visibility.Collapsed;
        PartialPane.Visibility = Visibility.Collapsed;
        StaleBanner.Visibility = outcome.IsStale ? Visibility.Visible : Visibility.Collapsed;
        BandsPane.Visibility = Visibility.Collapsed;
        NotesPane.Visibility = Visibility.Collapsed;
        EmptyPane.Visibility = Visibility.Collapsed;
        StaleReasonText.Text = outcome.Reason is { } reason ? DiscoverCopy.ReasonText(reason) : outcome.RouterDetail ?? "";

        if (outcome.Kind == RegistryPresentation.ListStateKind.Failed && !outcome.IsStale)
        {
            FailedReasonText.Text = outcome.Reason is { } failedReason
                ? DiscoverCopy.ReasonText(failedReason)
                : DiscoverCopy.ReasonText(DiscoverCopy.FailureReason.Transport);
            return;
        }

        if (response is null) return; // loading or offline: nothing else to draw

        SubtitleText.Text = RegistryPresentation.Subtitle(response);

        if (outcome.Kind is RegistryPresentation.ListStateKind.EmptyNoQuery or RegistryPresentation.ListStateKind.EmptyQuery)
        {
            var message = RegistryPresentation.EmptyMessageFor(response, SearchBox.Text)!;
            EmptyHeadline.Text = message.Headline;
            EmptyBodyText.Text = message.Body;
            _emptyActionClearsSearch = message.ClearsSearch;
            if (message.Action is { } action)
            {
                EmptyAction.Content = action;
                EmptyAction.Visibility = Visibility.Visible;
            }
            else
            {
                EmptyAction.Visibility = Visibility.Collapsed;
            }
            EmptyPane.Visibility = Visibility.Visible;
            return;
        }

        if (outcome.Kind == RegistryPresentation.ListStateKind.Partial && response.Results.Count == 0)
        {
            // The brief's named worst state: a degraded search that returned nothing draws the
            // degradation, never the empty state - a short list from a rate limit and a short
            // list from a thin catalogue look identical otherwise.
            var (headline, body) = PartialCopy(response);
            PartialHeadline.Text = headline;
            PartialBodyText.Text = body;
            PartialPane.Visibility = Visibility.Visible;
            return;
        }

        BandsPane.Visibility = Visibility.Visible;
        RenderBands();

        if (outcome.Kind == RegistryPresentation.ListStateKind.Partial)
        {
            var (headline, body) = PartialCopy(response);
            PartialHeadline.Text = headline;
            PartialBodyText.Text = body;
            PartialPane.Visibility = Visibility.Visible;
        }

        NotesPane.Visibility = Visibility.Visible;
    }

    private static (string Headline, string Body) PartialCopy(RegistrySearchResponse response)
    {
        var headline = DiscoverCopy.PartialUnrecognisedHeadline;
        var body = "";
        var first = true;
        foreach (var warning in response.Warnings)
        {
            var (warningHeadline, warningBody) = RegistryPresentation.Expand(warning);
            if (first)
            {
                headline = warningHeadline;
                body = warningBody;
                first = false;
            }
            else
            {
                body = $"{body} {warningBody}";
            }
        }

        return (headline, body);
    }

    private void RenderBands()
    {
        if (_model.LastResponse is not { } response) return;

        var scoped = _publisherFilter.Apply(response.Results);

        var recent = DiscoverBands.Members(DiscoverBand.RecentlyChanged, scoped, _window);
        var used = DiscoverBands.Members(DiscoverBand.MostUsed, scoped, _window);

        RenderBand(RecentList, RecentEmptyText, recent, DiscoverBand.RecentlyChanged);
        RenderBand(UsedList, UsedEmptyText, used, DiscoverBand.MostUsed);
    }

    private void RenderBand(ListView list, TextBlock emptyText, IReadOnlyList<RegistryEntry> members, DiscoverBand band)
    {
        list.Items.Clear();

        if (members.Count > 0)
        {
            emptyText.Visibility = Visibility.Collapsed;
            foreach (var entry in members)
            {
                list.Items.Add(DiscoverRow.From(entry));
            }

            return;
        }

        // A band empty while the list is not is its own state with its own copy - never the
        // whole-board empty, and never a bare blank under a header.
        var response = _model.LastResponse!;
        var scoped = _publisherFilter.Apply(response.Results);
        var kind = DiscoverBands.EmptyWithinResults(band, scoped, _window);

        if (kind == RegistryPresentation.BandEmptyKind.None && scoped.Count == 0 && response.Results.Count > 0)
        {
            // The publisher filter emptied this band: say so rather than rendering a blank.
            emptyText.Text = $"{DiscoverCopy.PublisherEmptyHeadline} {DiscoverCopy.PublisherEmptyBody}";
        }
        else
        {
            var message = RegistryPresentation.BandEmptyMessage(kind, _window.Days() ?? 0);
            emptyText.Text = message is null ? "" : $"{message.Headline} {message.Body}";
        }

        emptyText.Visibility = Visibility.Visible;
    }

    // ------------------------------------------------------------------ the detail

    private void OnRowClicked(object sender, ItemClickEventArgs e)
    {
        // The row's only action: open the detail. Installation is available only from there -
        // which is why this is the sole gesture a row carries.
        if (e.ClickedItem is DiscoverRow row)
        {
            _ = ShowDetailAsync(row.Entry);
        }
    }

    private async Task ShowDetailAsync(RegistryEntry entry)
    {
        var dialog = new DiscoverDetailDialog(_model, entry, Root.XamlRoot, OnInstalled);
        await dialog.ShowAsync();
    }

    private void OnInstalled(string entryId)
    {
        _model.MarkInstalled(entryId);
        RenderBands();
    }
}
