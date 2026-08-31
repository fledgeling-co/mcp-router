using MCPRouter.Shell.Model.Servers;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace MCPRouter.Shell.Views;

/// <summary>
/// The Servers board: the Signal Path over the declared servers, and what is plugged in right
/// now.
///
/// <para>Everything user-visible here traces to the router through <see cref="ControlApiClient"/>;
/// the model half (<c>MCPRouter.Shell.Model/Servers/</c>) is pure and headless-tested. This class
/// owns only what a view owns: the poll clock, the countdown tick, and turning readings into
/// elements. Its states — loading, loaded, empty, stale, disconnected, the harness lane's
/// partial, and the add dialog's refusals — are spec-WIN4 §4's matrix.</para>
///
/// <para><b>Brushes resolve under the element's theme, never the app's.</b> Every code-built
/// Foreground goes through <see cref="ThemeBrush"/>, which reads the theme dictionary matching
/// this element's <c>ActualTheme</c>. A lookup against <c>Application.Current.Resources</c>
/// would resolve under the APP's theme — the exact defect the shell removed once already: the
/// self-test forces Light and Dark on the root element, and an app-scoped lookup paints one
/// appearance's ink in the other.</para>
/// </summary>
public sealed partial class ServersBoard : UserControl
{
    /// <summary>The Mac tracker's cadence. The router publishes no state feed this client
    /// consumes; a timed poll is the authority for every field (spec-WIN4 §3.7).</summary>
    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(5);

    /// <summary>Countdowns tick between polls from the last answered envelope — interpolation
    /// between two router facts, never a derived figure.</summary>
    private static readonly TimeSpan TickInterval = TimeSpan.FromSeconds(1);

    // DESIGN.md §12 "Signal Path geometry (Windows)": the macOS table read as effective pixels,
    // one for one. A dimension changed here without a change there is a board drifting from its
    // own design authority.
    private const double JackMinimumWidth = 132;
    private const double JackLaneHeight = 44;
    private const double JackGap = 9;
    private const double PlugDiameter = 16;
    private const double PlugRing = 3;
    private const double SignalPathPadding = 12;
    private const int ClientPort = 8879;

    private readonly ControlApiClient _client = new();

    /// <summary>The jack word labels and the row state cells that a tick re-renders, so a
    /// countdown update costs two TextBlocks rather than a rebuilt tree — and so focus and
    /// tooltips survive the tick.</summary>
    private readonly List<(TextBlock Label, ServerRow Server)> _jackWords = [];
    private readonly List<(TextBlock Cell, ServerRow Server)> _stateCells = [];

    private DispatcherTimer? _pollTimer;
    private DispatcherTimer? _tickTimer;
    private bool _pollInFlight;

    /// <summary>The last poll that answered, and when. A failing poll after this keeps the
    /// reading on screen under the stale banner — a refresh that did not complete is not
    /// evidence the router moved (DESIGN.md §9).</summary>
    private ServersEnvelope? _lastAnswered;
    private DateTimeOffset? _lastAnsweredAt;
    private HarnessesEnvelope? _lastHarnesses;
    private ControlApiException? _lastError;
    private ControlApiException? _lastHarnessError;

    private int? LastIdleMs => _lastAnswered?.IdleMs;

    public ServersBoard()
    {
        InitializeComponent();

        AutomationProperties.SetName(this, "Servers");
        BuildLegend();

        ActualThemeChanged += (_, _) =>
        {
            // The legend's brushes were resolved under the outgoing theme; rebuild it, and let
            // Render re-resolve everything the tree already carries.
            BuildLegend();
            Render();
        };

        // The jack field packs to the width the LANE actually receives — not the board's: the
        // rail's fixed columns take a third of the card, and packing against the board's width
        // lays cells smaller than the jack's own minimum, where the neighbouring cell clips it.
        // The lane's width does not exist until layout does, so a size change re-packs.
        JackGrid.SizeChanged += (_, _) =>
        {
            if (_lastAnswered is not null) RenderJacks(_lastAnswered);
        };
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _pollTimer = new DispatcherTimer { Interval = PollInterval };
        _pollTimer.Tick += (_, _) => _ = PollAsync();
        _pollTimer.Start();

        _tickTimer = new DispatcherTimer { Interval = TickInterval };
        _tickTimer.Tick += (_, _) => TickCountdowns();
        _tickTimer.Start();

        _ = PollAsync();
    }

    private void OnUnloaded(object sender, RoutedEventArgs e)
    {
        _pollTimer?.Stop();
        _tickTimer?.Stop();
    }

    // ------------------------------------------------------------------ theme-safe brushes

    /// <summary>Resolves a theme resource's brush under THIS element's <c>ActualTheme</c>, from
    /// the theme dictionaries the Fluent resources merged at the app level. Falls back to the
    /// app-level key when a dictionary does not carry it, so a renamed key is loud, not silent.</summary>
    private Brush ThemeBrush(string key)
    {
        var theme = ActualTheme == ElementTheme.Light ? "Light" : "Dark";
        foreach (var merged in Application.Current.Resources.MergedDictionaries)
        {
            if (merged.ThemeDictionaries.TryGetValue(theme, out var themed)
                && themed is ResourceDictionary dictionary
                && dictionary.TryGetValue(key, out var value))
            {
                return (Brush)value;
            }
        }

        return (Brush)Application.Current.Resources[key];
    }

    // ------------------------------------------------------------------ the poll

    private async Task PollAsync()
    {
        if (_pollInFlight) return;
        _pollInFlight = true;
        try
        {
            // The two reads fail independently — a router whose harness inventory is absent
            // answers the servers read and 503s the harness read, and that is the partial
            // state, not a broken board.
            await Task.WhenAll(PollServersAsync(), PollHarnessesAsync());
        }
        finally
        {
            _pollInFlight = false;
        }
    }

    private async Task PollServersAsync()
    {
        try
        {
            var envelope = await _client.GetServersAsync();
            _lastAnswered = envelope;
            _lastAnsweredAt = DateTimeOffset.Now;
            _lastError = null;
        }
        catch (ControlApiException ex)
        {
            _lastError = ex;
        }

        Render();
    }

    private async Task PollHarnessesAsync()
    {
        try
        {
            _lastHarnesses = await _client.GetHarnessesAsync();
            _lastHarnessError = null;
        }
        catch (ControlApiException ex)
        {
            _lastHarnesses = null;
            _lastHarnessError = ex;
        }
    }

    // ------------------------------------------------------------------ rendering

    /// <summary>
    /// The one method that turns state into visibility, so two states cannot be drawn at once
    /// by two code paths drifting. spec-WIN4 §4 is its truth table.
    /// </summary>
    private void Render()
    {
        var loading = _lastAnswered is null && _lastError is null;
        var failed = _lastAnswered is null && _lastError is not null;
        var empty = _lastAnswered is not null && _lastAnswered.Servers.Count == 0;
        var stale = _lastAnswered is not null && _lastError is not null;

        LoadingPanel.Visibility = loading ? Visibility.Visible : Visibility.Collapsed;
        DisconnectedPanel.Visibility = failed ? Visibility.Visible : Visibility.Collapsed;
        EmptyPanel.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        ContentPanel.Visibility = _lastAnswered is not null && !empty ? Visibility.Visible : Visibility.Collapsed;
        StaleBanner.Visibility = stale ? Visibility.Visible : Visibility.Collapsed;
        AddButton.IsEnabled = _lastAnswered is not null;

        if (failed)
        {
            var error = _lastError!;
            ErrorHeadline.Text = error.Headline;
            ErrorAdvice.Text = error.Advice;
            ErrorEndpoint.Text = $"127.0.0.1:{ClientPort} — {error.Detail}";

            // §5: the disabled start action dims in place with a discoverable reason, and the
            // accessibility plane is where a reason survives a disabled control.
            AutomationProperties.SetName(DisconnectedPanel,
                $"{error.Headline}. {error.Advice} {ServersCopy.StartRouterLabel} is unavailable: "
                + ServersCopy.CannotStartRouterReason);
            AutomationProperties.SetHelpText(StartButton, ServersCopy.CannotStartRouterReason);
            ToolTipService.SetToolTip(StartButton, ServersCopy.CannotStartRouterReason);
        }

        if (stale)
        {
            StaleText.Text = ServersCopy.StaleLine(
                _lastAnsweredAt?.ToLocalTime().ToString("HH:mm:ss") ?? "an earlier poll");
        }

        if (_lastAnswered is { } envelope && !empty)
        {
            RenderSignalPath(envelope);
            RenderHeldBand(envelope);
            RenderTable(envelope);

            var callout = ServersBoardModel.DormantCallout(envelope);
            DormantCallout.Text = callout ?? "";
            DormantCallout.Visibility = callout is null ? Visibility.Collapsed : Visibility.Visible;
        }
    }

    private void RenderSignalPath(ServersEnvelope envelope)
    {
        EndpointText.Text = ServersBoardModel.Endpoint(envelope);
        AtRestText.Text = $"{ServersBoardModel.AtRestCount(envelope)} at rest";
        TopologyText.Text = ServersBoardModel.Topology(_lastHarnesses?.Harnesses.Count ?? 0, envelope);
        ToolTipService.SetToolTip(TopologyText, TopologyText.Text);
        AutomationProperties.SetName(SignalPathCard,
            $"Signal path. {TopologyText.Text}. {AtRestText.Text}");

        RenderHarnesses();
        RenderJacks(envelope);
    }

    private void RenderHarnesses()
    {
        HarnessesPanel.Children.Clear();

        if (_lastHarnesses is null)
        {
            // The partial state: say what arrived and what did not, with the reason — the
            // harness lane's own, not the board's.
            var reason = _lastHarnessError?.Detail ?? "no reading yet";
            var text = new TextBlock
            {
                Text = ServersCopy.HarnessUnavailable(reason),
                Foreground = ThemeBrush("TextFillColorSecondaryBrush"),
                FontSize = 12,
                TextWrapping = TextWrapping.Wrap,
            };
            AutomationProperties.SetName(HarnessesPanel, text.Text);
            HarnessesPanel.Children.Add(text);
            PartialBanner.Visibility = Visibility.Visible;
            PartialText.Text = ServersCopy.HarnessUnavailable(reason);
            return;
        }

        PartialBanner.Visibility = Visibility.Collapsed;

        HarnessesPanel.Children.Add(new TextBlock
        {
            Text = "Harnesses",
            Foreground = ThemeBrush("TextFillColorSecondaryBrush"),
            FontSize = 12,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        });

        foreach (var harness in _lastHarnesses.Harnesses)
        {
            var word = ServersBoardModel.HarnessWord(harness);
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };

            var dot = new Ellipse { Width = 8, Height = 8, VerticalAlignment = VerticalAlignment.Center };
            ApplyDotTone(dot, ServersBoardModel.HarnessDot(harness));

            var label = new TextBlock
            {
                Text = harness.DisplayName,
                Foreground = ThemeBrush("TextFillColorSecondaryBrush"),
                FontSize = 12,
                VerticalAlignment = VerticalAlignment.Center,
                TextTrimming = TextTrimming.CharacterEllipsis,
            };
            var stateWord = new TextBlock
            {
                Text = word,
                Foreground = ThemeBrush("TextFillColorTertiaryBrush"),
                FontSize = 12,
                VerticalAlignment = VerticalAlignment.Center,
            };

            row.Children.Add(dot);
            row.Children.Add(label);
            row.Children.Add(stateWord);
            AutomationProperties.SetName(row, $"{harness.DisplayName}, {word}");
            ToolTipService.SetToolTip(row, harness.State);
            HarnessesPanel.Children.Add(row);
        }
    }

    private void RenderJacks(ServersEnvelope envelope)
    {
        JackGrid.Children.Clear();
        JackGrid.RowDefinitions.Clear();
        JackGrid.ColumnDefinitions.Clear();
        _jackWords.Clear();

        // The field packs to the width available — never a fixed column count (§12's restatement
        // of §2's auto-fill invariant). The arithmetic runs at the LANE's width, which is the
        // width a jack cell actually has to fit; until the lane has one, one column is the safe
        // reading and the SizeChanged re-pack corrects it.
        var lane = JackGrid.ActualWidth;
        var columns = double.IsNaN(lane) || lane <= 0
            ? 1
            : Math.Max(1, (int)((lane + JackGap) / (JackMinimumWidth + JackGap)));
        for (var c = 0; c < columns; c++)
        {
            JackGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        }

        var jackIndex = 0;
        foreach (var server in envelope.Servers)
        {
            var row = jackIndex / columns;
            var column = jackIndex % columns;
            var condition = JackCondition.ForServer(server, LastIdleMs);

            while (JackGrid.RowDefinitions.Count <= row)
            {
                JackGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(JackLaneHeight) });
            }

            var jack = new Button
            {
                Style = (Style)Resources["JackButtonStyle"],
                MinWidth = JackMinimumWidth,
                Height = JackLaneHeight,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
            };
            Grid.SetRow(jack, row);
            Grid.SetColumn(jack, column);

            var content = new Grid { ColumnSpacing = JackGap };
            content.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            var plugRing = new Ellipse
            {
                Width = PlugDiameter + 2 * PlugRing,
                Height = PlugDiameter + 2 * PlugRing,
                StrokeThickness = PlugRing,
            };
            var plug = new Ellipse { Width = PlugDiameter, Height = PlugDiameter };
            ApplyPlugTone(plug, plugRing, condition.State);
            Grid.SetColumn(plugRing, 0);
            content.Children.Add(plugRing);
            content.Children.Add(plug);

            var label = new StackPanel { Spacing = 0, MinWidth = 0 };
            var name = new TextBlock
            {
                Text = server.Name,
                FontSize = 12,
                Foreground = ThemeBrush("TextFillColorPrimaryBrush"),
                TextTrimming = TextTrimming.CharacterEllipsis,
            };
            var word = new TextBlock
            {
                Text = condition.Word,
                FontSize = 11,
                FontFamily = new FontFamily("Consolas"),
                Foreground = ThemeBrush("TextFillColorSecondaryBrush"),
                TextTrimming = TextTrimming.CharacterEllipsis,
            };
            label.Children.Add(name);
            label.Children.Add(word);
            Grid.SetColumn(label, 1);
            content.Children.Add(label);

            jack.Content = content;
            jack.Click += (_, _) => SelectRow(server.Name);
            AutomationProperties.SetName(jack, $"{server.Name}, {condition.Word}");
            ToolTipService.SetToolTip(jack, $"{server.Name}: {condition.Word}");
            JackGrid.Children.Add(jack);

            // The tick re-renders this label from the SAME envelope the state came from; only
            // the clock moved, never the state.
            _jackWords.Add((word, server));
            jackIndex++;
        }

        AutomationProperties.SetName(JackGrid, "Upstream servers");
    }

    private void RenderHeldBand(ServersEnvelope envelope)
    {
        var held = ServersBoardModel.HeldRows(envelope);
        if (held.Count == 0)
        {
            HeldBand.Visibility = Visibility.Collapsed;
            return;
        }

        var first = held[0];
        var count = held.Sum(s => s.PendingChange?.Count ?? 0);
        var serverWord = held.Count == 1 ? first.Name : $"{held.Count} servers";
        HeldBandTitle.Text = ServersCopy.HeldBandHead(count, serverWord);
        HeldBand.Visibility = Visibility.Visible;
        AutomationProperties.SetName(HeldBand, $"{HeldBandTitle.Text}. {ServersCopy.HeldBandBody}");
    }

    private void RenderTable(ServersEnvelope envelope)
    {
        ServerTable.Children.Clear();
        _stateCells.Clear();
        var now = DateTimeOffset.Now;

        foreach (var server in envelope.Servers)
        {
            var (row, stateCell) = BuildRow(server, now);
            ServerTable.Children.Add(row);
            _stateCells.Add((stateCell, server));
        }

        AutomationProperties.SetName(ServerTable, "All servers");
    }

    private (Button Row, TextBlock StateCell) BuildRow(ServerRow server, DateTimeOffset now)
    {
        var row = new Button
        {
            Style = (Style)Resources["ServerRowStyle"],
            MinHeight = 56,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Tag = server.Name,
        };

        var grid = new Grid { ColumnSpacing = 12 };
        for (var i = 0; i < 6; i++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition());
        }

        var nameCell = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            VerticalAlignment = VerticalAlignment.Center,
        };
        var dot = new Ellipse { Width = 8, Height = 8, VerticalAlignment = VerticalAlignment.Center };
        ApplyDotTone(dot, DotToneFor(server));
        var name = new TextBlock
        {
            Text = server.Name,
            FontSize = 14,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Foreground = ThemeBrush(server.Disabled ? "TextFillColorSecondaryBrush" : "TextFillColorPrimaryBrush"),
        };
        nameCell.Children.Add(dot);
        nameCell.Children.Add(name);
        Grid.SetColumn(nameCell, 0);

        var transport = new TextBlock
        {
            Text = server.Transport,
            FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = ThemeBrush("TextFillColorSecondaryBrush"),
        };
        Grid.SetColumn(transport, 1);

        var tools = new TextBlock
        {
            Text = server.Disabled ? "—" : server.Tools.ToString(),
            FontSize = 12,
            FontFamily = new FontFamily("Consolas"),
            TextAlignment = TextAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = ThemeBrush("TextFillColorSecondaryBrush"),
        };
        Grid.SetColumn(tools, 2);

        var state = new TextBlock
        {
            Text = JackPresentation.StateCell(server, LastIdleMs),
            FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Foreground = ThemeBrush(server.Disabled ? "TextFillColorSecondaryBrush" : "TextFillColorPrimaryBrush"),
        };
        Grid.SetColumn(state, 3);

        var calls = new TextBlock
        {
            Text = server.Usage.Calls.ToString(),
            FontSize = 12,
            FontFamily = new FontFamily("Consolas"),
            TextAlignment = TextAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = ThemeBrush("TextFillColorSecondaryBrush"),
        };
        Grid.SetColumn(calls, 4);

        var lastCall = new TextBlock
        {
            Text = JackPresentation.RelativeLastCall(server, now),
            FontSize = 12,
            FontFamily = new FontFamily("Consolas"),
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Foreground = ThemeBrush("TextFillColorSecondaryBrush"),
        };
        Grid.SetColumn(lastCall, 5);

        grid.Children.Add(nameCell);
        grid.Children.Add(transport);
        grid.Children.Add(tools);
        grid.Children.Add(state);
        grid.Children.Add(calls);
        grid.Children.Add(lastCall);

        row.Content = grid;
        AutomationProperties.SetName(row, $"{server.Name}, {JackPresentation.StateCell(server, LastIdleMs)}");
        if (server.Placard is { } placard)
        {
            ToolTipService.SetToolTip(row, placard.Reason);
        }
        return (row, state);
    }

    private static DotTone DotToneFor(ServerRow server)
    {
        var state = JackPresentation.ForServer(server);
        return state switch
        {
            JackState.Live => DotTone.Lit,
            JackState.Tripped => DotTone.Critical,
            JackState.Held or JackState.NeedsSignIn => DotTone.Caution,
            _ => DotTone.Off,
        };
    }

    private void ApplyDotTone(Ellipse dot, DotTone tone)
    {
        dot.Style = tone switch
        {
            DotTone.Lit => (Style)Resources["LiveDotStyle"],
            DotTone.Caution => (Style)Resources["CautionDotStyle"],
            DotTone.Critical => (Style)Resources["CriticalDotStyle"],
            _ => (Style)Resources["OffDotStyle"],
        };
    }

    /// <summary>
    /// The plug and its ring, from §12's restatement: the state's own indicator hue on the fill,
    /// the same hue's published …Background token as the halo, and — never — the accent, which
    /// is the user's (§13's settled debt). At rest the socket takes the authored off tokens.
    /// </summary>
    private void ApplyPlugTone(Ellipse plug, Ellipse ring, JackState state)
    {
        switch (state)
        {
            case JackState.Live:
                plug.Fill = ThemeBrush("SystemFillColorSuccessBrush");
                ring.Stroke = ThemeBrush("SystemFillColorSuccessBackgroundBrush");
                break;
            case JackState.Tripped:
                plug.Fill = ThemeBrush("SystemFillColorCriticalBrush");
                ring.Stroke = ThemeBrush("SystemFillColorCriticalBackgroundBrush");
                break;
            case JackState.Held:
            case JackState.NeedsSignIn:
                plug.Fill = ThemeBrush("SystemFillColorCautionBrush");
                ring.Stroke = ThemeBrush("SystemFillColorCautionBackgroundBrush");
                break;
            default:
                plug.Fill = ThemeBrush("TextFillColorDisabledBrush");
                ring.Stroke = ThemeBrush("ControlStrokeColorDefaultBrush");
                break;
        }

        // The 167ms direct entrance on fill and ring (§13's motion table) is left to the
        // platform's own state transitions rather than an authored storyboard: a plug lighting
        // is a state change the control template animates, not a one-off effect this view
        // choreographs.
    }

    private void TickCountdowns()
    {
        // Interpolation between two router facts: the envelope's horizon and each server's idle
        // seconds, re-read against a moved clock. Only the words change — the state does not,
        // because the poll is the authority on that.
        if (_lastAnswered is null) return;

        foreach (var (label, server) in _jackWords)
        {
            label.Text = JackCondition.ForServer(server, LastIdleMs).Word;
        }

        if (_lastError is null)
        {
            foreach (var (cell, server) in _stateCells)
            {
                cell.Text = JackPresentation.StateCell(server, LastIdleMs);
            }
        }
    }

    // ------------------------------------------------------------------ actions

    private void OnRetryClicked(object sender, RoutedEventArgs e) => _ = PollAsync();

    private void OnReapIdleClicked(object sender, RoutedEventArgs e)
    {
        // Measured, the router serves no verb this can call: spec-WIN4 §3.4 records the paths
        // and PATCH fields read to reach that. The button is wired and stays disabled for the
        // day the verb lands.
    }

    private void OnAddServerClicked(object sender, RoutedEventArgs e) => _ = ShowAddDialogAsync();

    /// <summary>
    /// The add dialog: a name and either a command line or a URL, exactly the members
    /// <see cref="NewServerBody"/> carries. The router's refusals render against the form, and
    /// the hint is what turns "Add it anyway" on — never inferred from a status code. The
    /// dialog's primary button drives the whole submission: it cancels the close until the
    /// router answers, so a refusal keeps the form and a success closes it.
    /// </summary>
    private async Task ShowAddDialogAsync()
    {
        var nameBox = new TextBox { PlaceholderText = "name", Header = ServersCopy.AddNameLabel };
        var commandBox = new TextBox { PlaceholderText = "command", Header = ServersCopy.AddCommandLabel };
        var argsBox = new TextBox
        {
            PlaceholderText = "args",
            Header = ServersCopy.AddArgsLabel,
            AcceptsReturn = true,
            Height = 90,
            TextWrapping = TextWrapping.Wrap,
        };
        var urlBox = new TextBox { PlaceholderText = "https://", Header = ServersCopy.AddUrlLabel };
        var errorText = new TextBlock
        {
            FontSize = 12,
            Foreground = ThemeBrush("SystemFillColorCriticalBrush"),
            TextWrapping = TextWrapping.Wrap,
            Visibility = Visibility.Collapsed,
        };

        var panel = new StackPanel { Spacing = 10, MinWidth = 380 };
        panel.Children.Add(nameBox);
        panel.Children.Add(commandBox);
        panel.Children.Add(new TextBlock
        {
            Text = ServersCopy.AddArgsHelper,
            FontSize = 12,
            Foreground = ThemeBrush("TextFillColorSecondaryBrush"),
        });
        panel.Children.Add(argsBox);
        panel.Children.Add(new TextBlock
        {
            Text = ServersCopy.AddUrlHelper,
            FontSize = 12,
            Foreground = ThemeBrush("TextFillColorSecondaryBrush"),
        });
        panel.Children.Add(urlBox);
        panel.Children.Add(errorText);

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = ServersCopy.AddDialogTitle,
            PrimaryButtonText = ServersCopy.AddCommitLabel,
            CloseButtonText = ServersCopy.AddCancelLabel,
            Content = panel,
        };

        dialog.PrimaryButtonClick += async (button, eventArgs) =>
        {
            var url = urlBox.Text.Trim();
            var splitArgs = argsBox.Text
                .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            var body = url.Length > 0
                ? new NewServerBody { Name = nameBox.Text.Trim(), Url = url }
                : new NewServerBody { Name = nameBox.Text.Trim(), Command = commandBox.Text.Trim(), Args = splitArgs };
            var force = dialog.Tag is ForceAdd;

            if (body.Name.Length == 0)
            {
                eventArgs.Cancel = true;
                errorText.Text = "The router answers 400 for an empty name: name is required.";
                errorText.Visibility = Visibility.Visible;
                return;
            }

            // Cancel the close until the router answers: a refusal keeps the form, a success
            // hides the dialog and the next poll brings the server in — never an optimistic row.
            eventArgs.Cancel = true;
            try
            {
                await _client.AddServerAsync(body, force);
                errorText.Visibility = Visibility.Collapsed;
                dialog.Hide();
                _ = PollAsync();
            }
            catch (ControlApiException ex)
            {
                errorText.Text = ex.UserFacingDescription;
                errorText.Visibility = Visibility.Visible;
                // Only the router's own hint opens the force path. Never inferred from a status
                // code — that sentence is the router's advice, not this dialog's guess.
                if (ex.Hint is not null && ex.Hint.Contains("force=1", StringComparison.Ordinal))
                {
                    dialog.Tag = new ForceAdd();
                    dialog.PrimaryButtonText = ServersCopy.AddAnywayLabel;
                }
            }
        };

        await dialog.ShowAsync();
    }

    private async void OnReviewChangesClicked(object sender, RoutedEventArgs e)
    {
        if (_lastAnswered is null) return;
        var held = ServersBoardModel.HeldRows(_lastAnswered);
        if (held.Count == 0) return;

        var server = held[0];
        var panel = new StackPanel { Spacing = 8, MinWidth = 360 };
        try
        {
            var changes = await _client.GetChangesAsync(server.Name);
            foreach (var change in changes.Changes)
            {
                panel.Children.Add(new TextBlock
                {
                    Text = change.Kind switch
                    {
                        "added" => $"Added {change.Name}",
                        "removed" => $"Removed {change.Name}",
                        _ => $"Changed {change.Name}",
                    },
                    FontSize = 14,
                    Foreground = ThemeBrush("TextFillColorPrimaryBrush"),
                    TextWrapping = TextWrapping.Wrap,
                });
                if (change.After?.Description is { Length: > 0 } description)
                {
                    panel.Children.Add(new TextBlock
                    {
                        Text = description,
                        FontSize = 12,
                        FontFamily = new FontFamily("Consolas"),
                        Foreground = ThemeBrush("TextFillColorSecondaryBrush"),
                        TextWrapping = TextWrapping.Wrap,
                    });
                }
                if (change.Invisible is { Count: > 0 })
                {
                    panel.Children.Add(new TextBlock
                    {
                        Text = $"Invisible codepoints the router named: {string.Join(", ", change.Invisible)}",
                        FontSize = 12,
                        FontFamily = new FontFamily("Consolas"),
                        Foreground = ThemeBrush("SystemFillColorCautionBrush"),
                        TextWrapping = TextWrapping.Wrap,
                    });
                }
            }
        }
        catch (ControlApiException ex)
        {
            panel.Children.Add(new TextBlock
            {
                Text = ex.UserFacingDescription,
                FontSize = 12,
                Foreground = ThemeBrush("TextFillColorSecondaryBrush"),
                TextWrapping = TextWrapping.Wrap,
            });
        }

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"Held changes on {server.Name}",
            Content = panel,
            CloseButtonText = "Close",
        };
        await dialog.ShowAsync();
    }

    private void SelectRow(string serverName)
    {
        foreach (var child in ServerTable.Children)
        {
            if (child is Button { Tag: string name } row && name == serverName)
            {
                row.StartBringIntoView();
                row.Focus(FocusState.Programmatic);
                return;
            }
        }
    }

    private void BuildLegend()
    {
        LegendPanel.Children.Clear();

        foreach (var (word, style) in new (string, string)[]
        {
            ("awake", "LiveDotStyle"),
            ("dormant", "OffDotStyle"),
            ("held", "CautionDotStyle"),
            ("tripped", "CriticalDotStyle"),
        })
        {
            var item = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
            var dot = new Ellipse { Width = 8, Height = 8, VerticalAlignment = VerticalAlignment.Center };
            dot.Style = (Style)Resources[style];
            var label = new TextBlock
            {
                Text = word,
                FontSize = 12,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = ThemeBrush("TextFillColorSecondaryBrush"),
            };
            item.Children.Add(dot);
            item.Children.Add(label);
            LegendPanel.Children.Add(item);
        }
    }

    /// <summary>Marks that the add dialog's next commit should send <c>?force=1</c>. A type
    /// rather than a bool in <see cref="ContentDialog.Tag"/>, so "no tag" and "unforced" cannot
    /// be confused with "forced by a previous refusal".</summary>
    private sealed record ForceAdd;
}
