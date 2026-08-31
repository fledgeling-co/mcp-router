using MCPRouter.Shell.Model;
using MCPRouter.Shell.Model.Control;
using MCPRouter.Shell.Model.Skills;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace MCPRouter.Shell.Views;

/// <summary>
/// The Skills board: a table of every skill the router knows, the harness slots that say where
/// each one is live, and the held-for-review state that is a security guarantee rather than
/// decoration.
///
/// The board is read-only (spec-WIN6 §2.2), and its live reads answer 404 on today's router
/// (spec-WIN6 §2.1), so a real launch reaches loading, offline and failed; the populated board
/// draws from the Debug fixture lane. Every control is named from the on-screen vocabulary, so
/// the automation plane can measure it.
///
/// Fragments are built by string concatenation rather than interpolation on purpose: the XAML is
/// full of braces, and an interpolation hole inside them is a bug that only shows as broken
/// markup at runtime.
/// </summary>
public sealed partial class SkillsBoard : UserControl
{
    private enum Tab
    {
        Installed,
        Marketplaces,
        Updates,
    }

    private const string Win16Reason =
        "The capability document panel arrives with WIN16; the new version's added permissions "
        + "are named here until then.";

    private const string Win7Reason =
        "Marketplaces are the Discover board's; WIN7 builds the add-marketplace sheet.";

    private const string ScanReason =
        "The scan is the router's to run, and its skills routes have not shipped.";

    private const string FragmentNs = "xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"";

    private readonly ISkillsControlClient _client;
    private readonly Action<string> _navigate;
    private readonly Dictionary<Tab, RadioButton> _tabs = new();
    private Tab _selectedTab = Tab.Installed;
    private Skill? _selectedSkill;
    private SkillsBoardSnapshot _snapshot = SkillsBoardSnapshot.Loading;
    private bool _refreshing;
    private Button? _updateAllButton;

    public SkillsBoard(ISkillsControlClient client, Action<string> navigate)
    {
        InitializeComponent();

        _client = client;
        _navigate = navigate;

        BuildHeadActions();
        BuildTabs();

        AutomationProperties.SetName(this, "Skills board");
        AutomationProperties.SetAutomationId(this, "skills.board");
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e) => await RefreshAsync();

    // ------------------------------------------------------------------ the reads

    private async Task RefreshAsync()
    {
        if (_refreshing) return;
        _refreshing = true;
        _selectedSkill = null;

        Render(SkillsBoardSnapshot.Loading);

        SkillsResponse? skills = null;
        SkillsControlError? skillsError = null;
        MarketplacesResponse? marketplaces = null;
        SkillsControlError? marketplacesError = null;

        // Both reads run; one failing never discards the other's result - §5's Partial row.
        var skillsTask = _client.SkillsAsync();
        var marketplacesTask = _client.MarketplacesAsync();
        try
        {
            skills = await skillsTask;
        }
        catch (SkillsControlException exception)
        {
            skillsError = exception.Error;
        }
        try
        {
            marketplaces = await marketplacesTask;
        }
        catch (SkillsControlException exception)
        {
            marketplacesError = exception.Error;
        }
        if (skills is null && skillsError is null)
        {
            // A client that neither answered nor threw a typed error is broken; a board that
            // swallowed that would look exactly like an empty library.
            StartupLog.Write("skills board: client produced neither response nor typed error");
            skillsError = new SkillsControlError.Transport("the read produced nothing");
        }

        _snapshot = SkillsBoardSnapshot.FromResults(skills, skillsError, marketplaces, marketplacesError);
        Render(_snapshot);
        _refreshing = false;
    }

    // ------------------------------------------------------------------ the head

    private void BuildHeadActions()
    {
        var doctor = new Button { Content = "Run doctor" };
        AutomationProperties.SetName(doctor, "Run doctor");
        AutomationProperties.SetAutomationId(doctor, "skills.head.runDoctor");
        doctor.Click += (_, _) => _navigate("checks");
        ToolTipService.SetToolTip(doctor, "Opens the Checks board, where doctor reports.");

        var addMarketplace = new Button
        {
            Content = SkillPresentation.MarketplacesAction,
            IsEnabled = false,
        };
        AutomationProperties.SetName(addMarketplace, SkillPresentation.MarketplacesAction);
        AutomationProperties.SetAutomationId(addMarketplace, "skills.head.addMarketplace");
        AutomationProperties.SetHelpText(addMarketplace, Win7Reason);

        var updateAll = new Button { Content = "Update all · 0", IsEnabled = false };
        AutomationProperties.SetName(updateAll, "Update all");
        AutomationProperties.SetAutomationId(updateAll, "skills.head.updateAll");
        AutomationProperties.SetHelpText(updateAll, SkillPresentation.WritesNotYetAvailable);
        _updateAllButton = updateAll;

        HeadActions.Children.Add(doctor);
        HeadActions.Children.Add(addMarketplace);
        HeadActions.Children.Add(updateAll);
    }

    private void UpdateHead()
    {
        SubtitleText.Text = _snapshot.State == SkillsBoardState.Populated
            ? SkillPresentation.Subtitle(_snapshot.Skills!.SkillList)
            : "";

        if (_updateAllButton is { } updateAll)
        {
            // The count is real and the action is not available: the board is read-only. The
            // count stays visible so the set it names is not a mystery behind the disabled
            // control (§5 Disabled: dims in place, never disappears).
            updateAll.Content = $"Update all · {_snapshot.UpdateAllCount}";
        }
    }

    // ------------------------------------------------------------------ the tabs

    private void BuildTabs()
    {
        var host = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };

        foreach (var tab in new[] { Tab.Installed, Tab.Marketplaces, Tab.Updates })
        {
            var button = new RadioButton
            {
                GroupName = "SkillsTabs",
                MinWidth = 0,
                MinHeight = 0,
                Padding = new Thickness(12, 5, 12, 5),
            };
            AutomationProperties.SetAutomationId(button, $"skills.tab.{tab.ToString().ToLowerInvariant()}");
            var captured = tab;
            button.Checked += (_, _) =>
            {
                _selectedTab = captured;
                Render();
            };
            _tabs[tab] = button;
            host.Children.Add(button);
        }

        _tabs[Tab.Installed].IsChecked = true;
        TabsHost.Content = host;
    }

    private void UpdateTabs()
    {
        _tabs[Tab.Installed].Content = $"Installed · {_snapshot.InstalledCount}";
        _tabs[Tab.Marketplaces].Content = $"Marketplaces · {_snapshot.MarketplacesCount}";
        _tabs[Tab.Updates].Content = $"Updates · {_snapshot.Updated.Count}";
        AutomationProperties.SetName(_tabs[Tab.Installed], $"Installed · {_snapshot.InstalledCount}");
        AutomationProperties.SetName(_tabs[Tab.Marketplaces], $"Marketplaces · {_snapshot.MarketplacesCount}");
        AutomationProperties.SetName(_tabs[Tab.Updates], $"Updates · {_snapshot.Updated.Count}");
    }

    // ------------------------------------------------------------------ the render switch

    private void Render() => Render(_snapshot);

    /// <summary>Exhaustive over the load state: a new state stops the build rather than drawing blank.</summary>
    private void Render(SkillsBoardSnapshot snapshot)
    {
        UpdateHead();
        UpdateTabs();
        BannersHost.Children.Clear();

        switch (snapshot.State)
        {
            case SkillsBoardState.Loading:
                ContentHost.Content = Skeleton();
                break;

            case SkillsBoardState.Empty:
                ContentHost.Content = EmptyState();
                break;

            case SkillsBoardState.Offline:
            case SkillsBoardState.Failed:
                ContentHost.Content = ErrorState(snapshot.Error!);
                break;

            case SkillsBoardState.Populated:
                AddHeldBanners(snapshot);
                AddPartialNotes(snapshot);
                ContentHost.Content = _selectedTab switch
                {
                    Tab.Installed => InstalledView(snapshot),
                    Tab.Marketplaces => MarketplacesView(snapshot),
                    _ => UpdatesView(snapshot),
                };
                break;

            default:
                throw new ArgumentOutOfRangeException(nameof(snapshot), snapshot.State, "unhandled board state");
        }
    }

    private void AddHeldBanners(SkillsBoardSnapshot snapshot)
    {
        foreach (var skill in snapshot.HeldForReview)
        {
            var title = SkillPresentation.HeldBannerTitle(skill);
            var body = SkillPresentation.HeldBannerBody(skill);
            if (title.Length == 0) continue;

            var seeWhatChanged = new Button { Content = "See what changed…", IsEnabled = false };
            AutomationProperties.SetName(seeWhatChanged, "See what changed…");
            AutomationProperties.SetAutomationId(seeWhatChanged, $"skills.held.seeWhatChanged.{skill.Name}");
            AutomationProperties.SetHelpText(seeWhatChanged, Win16Reason);

            var banner = (Border)LoadUi(
                "<Border " + FragmentNs + " Background=\"{ThemeResource CardBackgroundFillColorDefaultBrush}\""
                + " BorderBrush=\"{ThemeResource ControlStrokeColorDefaultBrush}\" BorderThickness=\"1\""
                + " CornerRadius=\"4\" Padding=\"12\">"
                + "  <Grid ColumnSpacing=\"12\">"
                + "    <Grid.ColumnDefinitions>"
                + "      <ColumnDefinition Width=\"*\" />"
                + "      <ColumnDefinition Width=\"Auto\" />"
                + "    </Grid.ColumnDefinitions>"
                + "    <StackPanel Grid.Column=\"0\" Spacing=\"2\">"
                + "      <TextBlock x:Name=\"HeldTitle\" TextWrapping=\"Wrap\""
                + "                 Style=\"{StaticResource BodyStrongTextBlockStyle}\""
                + "                 Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
                + "      <TextBlock x:Name=\"HeldBody\" TextWrapping=\"Wrap\""
                + "                 Style=\"{StaticResource BodyTextBlockStyle}\""
                + "                 Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
                + "    </StackPanel>"
                + "  </Grid>"
                + "</Border>");

            ((TextBlock)banner.FindName("HeldTitle")!).Text = title;
            ((TextBlock)banner.FindName("HeldBody")!).Text = body;

            var buttonHost = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                VerticalAlignment = VerticalAlignment.Center,
            };
            buttonHost.Children.Add(seeWhatChanged);
            var grid = (Grid)banner.Child;
            grid.Children.Add(buttonHost);
            Grid.SetColumn(buttonHost, 1);

            AutomationProperties.SetName(banner, $"{title}. {body}");
            AutomationProperties.SetAutomationId(banner, $"skills.held.{skill.Name}");
            BannersHost.Children.Add(banner);
        }
    }

    private void AddPartialNotes(SkillsBoardSnapshot snapshot)
    {
        foreach (var note in new[] { snapshot.PartialNote, snapshot.MarketplaceListNote })
        {
            if (note is not { } text) continue;

            var noteCard = LoadUi(
                "<Border " + FragmentNs + " Padding=\"12,8,12,8\">"
                + "  <TextBlock x:Name=\"Note\" TextWrapping=\"Wrap\""
                + "             Style=\"{StaticResource CaptionTextBlockStyle}\""
                + "             Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
                + "</Border>");
            ((TextBlock)noteCard.FindName("Note")!).Text = text;
            AutomationProperties.SetName(noteCard, text);
            AutomationProperties.SetAutomationId(noteCard, "skills.partial." + BannersHost.Children.Count);
            BannersHost.Children.Add(noteCard);
        }
    }

    // ------------------------------------------------------------------ the installed tab

    private FrameworkElement InstalledView(SkillsBoardSnapshot snapshot)
    {
        var slotClients = snapshot.Skills!.SlotClients;

        var table = new Grid { ColumnSpacing = 12 };
        table.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        for (var column = 0; column < 5; column++)
        {
            table.ColumnDefinitions.Add(column == 0
                ? new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }
                : new ColumnDefinition { Width = new GridLength(140) });
        }

        // The header row, from the mock's own vocabulary.
        var headers = new[] { "Skill", "Marketplace", "Version", "Installed into", "Auto-update" };
        for (var column = 0; column < headers.Length; column++)
        {
            var header = SecondaryCaption();
            header.Text = headers[column];
            header.VerticalAlignment = VerticalAlignment.Center;
            AutomationProperties.SetName(header, headers[column]);
            AutomationProperties.SetAutomationId(header, $"skills.header.{headers[column]}");
            Grid.SetColumn(header, column);
            table.Children.Add(header);
        }

        var row = 1;
        foreach (var skill in snapshot.Skills.SkillList)
        {
            var rowElement = SkillRow(skill, slotClients, isSelected: _selectedSkill?.Path == skill.Path);
            var captured = skill;
            ((Button)rowElement).Click += (_, _) =>
            {
                _selectedSkill = _selectedSkill?.Path == captured.Path ? null : captured;
                Render();
            };
            table.RowDefinitions.Add(new RowDefinition { Height = new GridLength(52) });
            Grid.SetRow(rowElement, row);
            Grid.SetColumnSpan(rowElement, headers.Length);
            table.Children.Add(rowElement);
            row++;
        }

        var stack = new StackPanel { Spacing = 8 };
        stack.Children.Add(table);
        stack.Children.Add(SlotsLegend(slotClients));
        stack.Children.Add(FooterText(SkillPresentation.ObservationFooter, "skills.footer.observation"));

        var host = new Grid { ColumnSpacing = 16 };
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        host.Children.Add(stack);

        if (_selectedSkill is { } selected)
        {
            var inspector = Inspector(selected, snapshot);
            Grid.SetColumn(inspector, 1);
            host.Children.Add(inspector);
        }

        return new ScrollViewer { Content = host, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private Button SkillRow(Skill skill, IReadOnlyList<SkillClient> slotClients, bool isSelected)
    {
        var version = SkillPresentation.Version(skill);
        var selectedBrush = isSelected ? "SubtleFillColorSecondaryBrush" : "Transparent";

        // One slot chip per client the router reports, in the router's order. On shows the
        // letters on a card; off dims them; unknown draws a dash - and the automation name says
        // which is which, so the meaning never rests on the look (§11 rule 12).
        var chips = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 4,
            VerticalAlignment = VerticalAlignment.Center,
        };
        foreach (var client in slotClients)
        {
            var state = SkillPresentation.Slot(skill, client);
            var letter = state == SkillPresentation.SlotState.Unknown ? "–" : SkillPresentation.SlotLabel(client);
            var chip = (Border)LoadUi(
                "<Border " + FragmentNs + " Width=\"30\" Height=\"22\" CornerRadius=\"4\" BorderThickness=\"1\""
                + " BorderBrush=\"{ThemeResource ControlStrokeColorDefaultBrush}\""
                + " Background=\"{ThemeResource "
                + (state == SkillPresentation.SlotState.On ? "CardBackgroundFillColorDefaultBrush" : "Transparent")
                + "}\">"
                + "  <TextBlock Text=\"" + Escape(letter) + "\" FontFamily=\"Consolas\" FontSize=\"11\""
                + "             HorizontalAlignment=\"Center\" VerticalAlignment=\"Center\""
                + "             Foreground=\"{ThemeResource "
                + (state switch
                {
                    SkillPresentation.SlotState.On => "TextFillColorPrimaryBrush",
                    SkillPresentation.SlotState.Off => "TextFillColorDisabledBrush",
                    _ => "TextFillColorTertiaryBrush",
                })
                + "}\" />"
                + "</Border>");
            AutomationProperties.SetName(chip, SkillPresentation.SlotAutomationName(skill, client));
            AutomationProperties.SetAutomationId(chip, $"skills.slot.{skill.Name}.{client.Id}");
            ToolTipService.SetToolTip(chip, SkillPresentation.SlotAutomationName(skill, client));
            chips.Children.Add(chip);
        }

        var rowButton = (Button)LoadUi(
            "<Button " + FragmentNs + " HorizontalAlignment=\"Stretch\" HorizontalContentAlignment=\"Stretch\""
            + " Background=\"{ThemeResource " + selectedBrush + "}\""
            + " BorderThickness=\"0\" Padding=\"8,4,8,4\" CornerRadius=\"4\">"
            + "  <Grid ColumnSpacing=\"12\">"
            + "    <Grid.ColumnDefinitions>"
            + "      <ColumnDefinition Width=\"*\" />"
            + "      <ColumnDefinition Width=\"130\" />"
            + "      <ColumnDefinition Width=\"100\" />"
            + "      <ColumnDefinition Width=\"Auto\" />"
            + "      <ColumnDefinition Width=\"80\" />"
            + "    </Grid.ColumnDefinitions>"
            + "    <StackPanel Grid.Column=\"0\" VerticalAlignment=\"Center\">"
            + "      <TextBlock x:Name=\"SkillName\" TextTrimming=\"CharacterEllipsis\" FontWeight=\"SemiBold\""
            + "                 Style=\"{StaticResource BodyTextBlockStyle}\""
            + "                 Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
            + "      <TextBlock x:Name=\"SourceLine\" TextTrimming=\"CharacterEllipsis\""
            + "                 Style=\"{StaticResource CaptionTextBlockStyle}\""
            + "                 Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
            + "      <TextBlock x:Name=\"ProvenanceLine\" TextTrimming=\"CharacterEllipsis\" Visibility=\"Collapsed\""
            + "                 Style=\"{StaticResource CaptionTextBlockStyle}\""
            + "                 Foreground=\"{ThemeResource SystemFillColorCautionBrush}\" />"
            + "    </StackPanel>"
            + "    <TextBlock Grid.Column=\"1\" x:Name=\"MarketplaceCell\" TextTrimming=\"CharacterEllipsis\""
            + "               VerticalAlignment=\"Center\""
            + "               Style=\"{StaticResource BodyTextBlockStyle}\""
            + "               Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
            + "    <TextBlock Grid.Column=\"2\" x:Name=\"VersionCell\" TextTrimming=\"CharacterEllipsis\""
            + "               VerticalAlignment=\"Center\" FontFamily=\"Consolas\""
            + "               Style=\"{StaticResource BodyTextBlockStyle}\""
            + "               Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
            + "    <ContentControl Grid.Column=\"3\" x:Name=\"SlotsCell\" IsTabStop=\"False\""
            + "                    VerticalAlignment=\"Center\" HorizontalContentAlignment=\"Left\" />"
            + "    <TextBlock Grid.Column=\"4\" x:Name=\"AutoUpdateCell\" VerticalAlignment=\"Center\""
            + "               HorizontalAlignment=\"Left\" Padding=\"6,2,6,2\" CornerRadius=\"4\""
            + "               Background=\"{ThemeResource SubtleFillColorSecondaryBrush}\""
            + "               Style=\"{StaticResource CaptionTextBlockStyle}\""
            + "               Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
            + "  </Grid>"
            + "</Button>");

        ((TextBlock)rowButton.FindName("SkillName")!).Text = skill.Name;
        ((TextBlock)rowButton.FindName("SourceLine")!).Text = SkillPresentation.SourceLine(skill);
        ((TextBlock)rowButton.FindName("MarketplaceCell")!).Text =
            skill.Source.AsPlugin?.Marketplace ?? "local";
        ((TextBlock)rowButton.FindName("VersionCell")!).Text = version.Text;
        // A standalone skill's "unversioned" is a statement, not a reading: it takes the body
        // face, not the instrument face (the Mac's rule, §2's face discipline).
        if (!version.IsInstrument)
        {
            var versionCell = (TextBlock)rowButton.FindName("VersionCell")!;
            versionCell.FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI");
        }
        ((TextBlock)rowButton.FindName("AutoUpdateCell")!).Text =
            SkillPresentation.AutoUpdateCell(skill, _snapshot.Marketplaces ?? Array.Empty<Marketplace>());
        ((ContentControl)rowButton.FindName("SlotsCell")!).Content = chips;

        if (SkillPresentation.ProvenanceLine(skill) is { } provenanceLine)
        {
            var provenanceCell = (TextBlock)rowButton.FindName("ProvenanceLine")!;
            provenanceCell.Text = provenanceLine;
            provenanceCell.Visibility = Visibility.Visible;
        }

        AutomationProperties.SetName(rowButton,
            $"{skill.Name}, {SkillPresentation.SourceLine(skill)}, version {version.Text}");
        AutomationProperties.SetAutomationId(rowButton, $"skills.row.{skill.Name}");
        ToolTipService.SetToolTip(rowButton, skill.Source.AsPlugin is { } origin
            ? $"{skill.Path}\n{origin.Plugin} {origin.PluginVersion} from {origin.Marketplace}"
            : skill.Path);

        return rowButton;
    }

    private TextBlock SlotsLegend(IReadOnlyList<SkillClient> slotClients)
    {
        var legend = string.Join(" · ",
            slotClients.Select(c => $"{SkillPresentation.SlotLabel(c)} {c.DisplayName}"));
        return FooterText(
            $"{legend}. A slot is filled when the skill's directory is actually present under "
            + "that harness, not when a manifest claims it.",
            "skills.footer.slots");
    }

    private TextBlock FooterText(string text, string automationId)
    {
        var footer = SecondaryCaption();
        footer.Text = text;
        footer.TextWrapping = TextWrapping.Wrap;
        AutomationProperties.SetName(footer, text);
        AutomationProperties.SetAutomationId(footer, automationId);
        return footer;
    }

    /// <summary>
    /// A secondary caption, loaded as a fragment so its Style and Foreground stay ThemeResources
    /// (WinUI has no SetResourceReference, and a dictionary fetch in code would freeze one
    /// appearance's brush into the element).
    /// </summary>
    private TextBlock SecondaryCaption() => (TextBlock)LoadUi(
        "<TextBlock " + FragmentNs
        + " Style=\"{StaticResource CaptionTextBlockStyle}\""
        + " Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />");

    // ------------------------------------------------------------------ the inspector

    private FrameworkElement Inspector(Skill skill, SkillsBoardSnapshot snapshot)
    {
        var version = SkillPresentation.Version(skill);
        var origin = skill.Source.AsPlugin;
        var sentences = SkillPresentation.ClientSentences(skill, snapshot.Skills!);

        var switchRows = new StackPanel { Spacing = 8 };
        foreach (var client in snapshot.Skills!.SlotClients)
        {
            switchRows.Children.Add(InspectorSwitchRow(skill, client));
        }

        var inspector = (Border)LoadUi(
            "<Border " + FragmentNs + " Width=\"320\" VerticalAlignment=\"Stretch\""
            + " Background=\"{ThemeResource CardBackgroundFillColorDefaultBrush}\""
            + " BorderBrush=\"{ThemeResource ControlStrokeColorDefaultBrush}\" BorderThickness=\"1\""
            + " CornerRadius=\"4\" Padding=\"16\">"
            + "  <ScrollViewer VerticalScrollBarVisibility=\"Auto\">"
            + "    <StackPanel Spacing=\"10\">"
            + "      <Grid ColumnSpacing=\"8\">"
            + "        <Grid.ColumnDefinitions>"
            + "          <ColumnDefinition Width=\"*\" />"
            + "          <ColumnDefinition Width=\"Auto\" />"
            + "        </Grid.ColumnDefinitions>"
            + "        <TextBlock x:Name=\"InspectorName\" TextWrapping=\"Wrap\" FontFamily=\"Consolas\""
            + "                   Style=\"{StaticResource BodyStrongTextBlockStyle}\""
            + "                   Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
            + "        <Border Grid.Column=\"1\" CornerRadius=\"4\" Padding=\"6,2,6,2\""
            + "                Background=\"{ThemeResource SubtleFillColorSecondaryBrush}\""
            + "                VerticalAlignment=\"Center\">"
            + "          <TextBlock x:Name=\"InspectorVersion\" FontFamily=\"Consolas\""
            + "                     Style=\"{StaticResource CaptionTextBlockStyle}\""
            + "                     Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
            + "        </Border>"
            + "      </Grid>"
            + "      <TextBlock x:Name=\"InspectorDescription\" TextWrapping=\"Wrap\""
            + "                 Style=\"{StaticResource CaptionTextBlockStyle}\""
            + "                 Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
            + "      <TextBlock Text=\"Installed into\" Style=\"{StaticResource BodyStrongTextBlockStyle}\""
            + "                 Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
            + "      <ContentControl x:Name=\"SwitchRows\" IsTabStop=\"False\" HorizontalContentAlignment=\"Left\" />"
            + "      <TextBlock x:Name=\"ClientSentences\" TextWrapping=\"Wrap\""
            + "                 Style=\"{StaticResource CaptionTextBlockStyle}\""
            + "                 Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
            + "      <TextBlock Text=\"Provenance\" Style=\"{StaticResource BodyStrongTextBlockStyle}\""
            + "                 Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
            + "      <TextBlock x:Name=\"ProvenanceLines\" TextWrapping=\"Wrap\" FontFamily=\"Consolas\""
            + "                 Style=\"{StaticResource CaptionTextBlockStyle}\""
            + "                 Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
            + "      <TextBlock Text=\"Why there is no “use, by version”\" TextWrapping=\"Wrap\""
            + "                 Style=\"{StaticResource BodyStrongTextBlockStyle}\""
            + "                 Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
            + "      <TextBlock TextWrapping=\"Wrap\""
            + "                 Style=\"{StaticResource CaptionTextBlockStyle}\""
            + "                 Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
            + "      <TextBlock TextWrapping=\"Wrap\""
            + "                 Style=\"{StaticResource CaptionTextBlockStyle}\""
            + "                 Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
            + "    </StackPanel>"
            + "  </ScrollViewer>"
            + "</Border>");

        var body = (StackPanel)((ScrollViewer)inspector.Child).Content;
        // The two trailing caption blocks carry the fixed sentences by value, not markup, so the
        // copy lives in one place (SkillPresentation) and the markup carries none of it.
        var observationIndex = body.Children.Count - 2;
        ((TextBlock)body.Children[observationIndex]).Text = SkillPresentation.ObservationFooter;
        ((TextBlock)body.Children[observationIndex + 1]).Text = SkillPresentation.CapabilityDerivation;

        ((TextBlock)inspector.FindName("InspectorName")!).Text = skill.Name;
        ((TextBlock)inspector.FindName("InspectorVersion")!).Text = version.Text;
        ((TextBlock)inspector.FindName("InspectorDescription")!).Text =
            skill.Description ?? "No description was supplied.";
        ((ContentControl)inspector.FindName("SwitchRows")!).Content = switchRows;
        ((TextBlock)inspector.FindName("ClientSentences")!).Text = string.Join("\n", sentences);

        var provenanceLines = new List<string>();
        if (origin is { } pluginOrigin)
        {
            provenanceLines.Add($"Marketplace  {pluginOrigin.Marketplace}");
            provenanceLines.Add($"Plugin       {pluginOrigin.Plugin}");
            provenanceLines.Add(
                $"Version      {pluginOrigin.PluginVersion} (the plugin's, shared by "
                + $"{pluginOrigin.SiblingSkillCount} "
                + $"{(pluginOrigin.SiblingSkillCount == 1 ? "skill" : "skills")})");
            if (pluginOrigin.Commit is { } commit) provenanceLines.Add($"Commit       {commit}");
            if (pluginOrigin.InstalledAt is { } installedAt) provenanceLines.Add($"Installed    {installedAt}");
            if (pluginOrigin.LastUpdated is { } lastUpdated) provenanceLines.Add($"Last updated {lastUpdated}");
        }
        else
        {
            provenanceLines.Add(
                "Standalone - not from a marketplace, and with no version to pin anything to.");
        }
        if (skill.Provenance is { } provenance)
        {
            provenanceLines.Add(
                $"Owner changed - the router first saw {provenance.FirstSeenSource}, "
                + $"now {provenance.CurrentSource}.");
        }
        ((TextBlock)inspector.FindName("ProvenanceLines")!).Text = string.Join("\n", provenanceLines);

        AutomationProperties.SetName(inspector, $"Skill inspector: {skill.Name}");
        AutomationProperties.SetAutomationId(inspector, "skills.inspector");
        return inspector;
    }

    private FrameworkElement InspectorSwitchRow(Skill skill, SkillClient client)
    {
        var state = SkillPresentation.Slot(skill, client);
        var isOn = state == SkillPresentation.SlotState.On;
        var help = state == SkillPresentation.SlotState.Unknown
            ? $"{client.DisplayName} could not be read, so this is unknown. "
              + SkillPresentation.WritesNotYetAvailable
            : SkillPresentation.WritesNotYetAvailable;

        var row = (Grid)LoadUi(
            "<Grid " + FragmentNs + " ColumnSpacing=\"8\">"
            + "  <Grid.ColumnDefinitions>"
            + "    <ColumnDefinition Width=\"*\" />"
            + "    <ColumnDefinition Width=\"Auto\" />"
            + "  </Grid.ColumnDefinitions>"
            + "  <StackPanel Grid.Column=\"0\" VerticalAlignment=\"Center\">"
            + "    <TextBlock x:Name=\"ClientName\" TextTrimming=\"CharacterEllipsis\""
            + "               Style=\"{StaticResource BodyTextBlockStyle}\""
            + "               Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
            + "    <TextBlock x:Name=\"ClientPath\" TextTrimming=\"CharacterEllipsis\""
            + "               Style=\"{StaticResource CaptionTextBlockStyle}\""
            + "               Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
            + "  </StackPanel>"
            + "  <ToggleSwitch Grid.Column=\"1\" x:Name=\"InstallSwitch\" IsEnabled=\"False\""
            + "                OnContent=\"On\" OffContent=\"Off\""
            + "                AutomationProperties.Name=\"Install into " + Escape(client.DisplayName) + "\" />"
            + "</Grid>");

        ((TextBlock)row.FindName("ClientName")!).Text = client.DisplayName;
        ((TextBlock)row.FindName("ClientPath")!).Text = client.Root ?? "no skills directory reported";
        var toggle = (ToggleSwitch)row.FindName("InstallSwitch")!;
        toggle.IsOn = isOn;
        // A disabled control dims in place; the help text is the discoverable reason (§5), and
        // the switch keeps its On/Off content (§11 rule 6). The state it shows is the router's
        // reading, so a slot the router could not read shows OFF but says unknown.
        AutomationProperties.SetHelpText(toggle, help);
        AutomationProperties.SetAutomationId(toggle, $"skills.inspector.switch.{client.Id}");
        AutomationProperties.SetHelpText(row, help);
        return row;
    }

    // ------------------------------------------------------------------ the marketplaces tab

    private FrameworkElement MarketplacesView(SkillsBoardSnapshot snapshot)
    {
        var marketplaces = snapshot.Marketplaces ?? Array.Empty<Marketplace>();
        var host = new StackPanel
        {
            Spacing = 8,
            MaxWidth = 720,
            HorizontalAlignment = HorizontalAlignment.Left,
        };

        foreach (var marketplace in marketplaces)
        {
            var moved = snapshot.Skills!.SkillList
                .Where(s => s.Source.AsPlugin?.Marketplace == marketplace.Name && s.Provenance is not null)
                .ToList();

            var browse = new Button { Content = "Browse in the store…" };
            AutomationProperties.SetName(browse, "Browse in the store…");
            AutomationProperties.SetAutomationId(browse, $"skills.marketplace.browse.{marketplace.Name}");
            browse.Click += (_, _) => _navigate("discover");

            var updateNow = new Button { Content = "Update now", IsEnabled = false };
            AutomationProperties.SetName(updateNow, "Update now");
            AutomationProperties.SetAutomationId(updateNow, $"skills.marketplace.updateNow.{marketplace.Name}");
            AutomationProperties.SetHelpText(updateNow, SkillPresentation.WritesNotYetAvailable);

            var remove = new Button { Content = "Remove…", IsEnabled = false };
            AutomationProperties.SetName(remove, "Remove…");
            AutomationProperties.SetAutomationId(remove, $"skills.marketplace.remove.{marketplace.Name}");
            AutomationProperties.SetHelpText(remove, SkillPresentation.RemoveReason(marketplace));

            var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            buttons.Children.Add(browse);
            buttons.Children.Add(updateNow);
            buttons.Children.Add(remove);

            var card = (Border)LoadUi(
                "<Border " + FragmentNs
                + " Background=\"{ThemeResource CardBackgroundFillColorDefaultBrush}\""
                + " BorderBrush=\"{ThemeResource ControlStrokeColorDefaultBrush}\" BorderThickness=\"1\""
                + " CornerRadius=\"4\" Padding=\"16\">"
                + "  <StackPanel Spacing=\"6\">"
                + "    <TextBlock x:Name=\"MarketplaceName\" TextWrapping=\"Wrap\""
                + "               Style=\"{StaticResource BodyStrongTextBlockStyle}\""
                + "               Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
                + "    <TextBlock x:Name=\"MarketplaceSource\" TextWrapping=\"Wrap\" FontFamily=\"Consolas\""
                + "               Style=\"{StaticResource CaptionTextBlockStyle}\""
                + "               Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
                + "    <TextBlock x:Name=\"SupplyLine\""
                + "               Style=\"{StaticResource CaptionTextBlockStyle}\""
                + "               Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
                + "    <TextBlock x:Name=\"AutoUpdateLine\" TextWrapping=\"Wrap\""
                + "               Style=\"{StaticResource CaptionTextBlockStyle}\""
                + "               Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
                + "    <TextBlock x:Name=\"MovedLine\" TextWrapping=\"Wrap\" Visibility=\"Collapsed\""
                + "               Style=\"{StaticResource CaptionTextBlockStyle}\""
                + "               Foreground=\"{ThemeResource SystemFillColorCautionBrush}\" />"
                + "  </StackPanel>"
                + "</Border>");

            ((TextBlock)card.FindName("MarketplaceName")!).Text = marketplace.Name;
            ((TextBlock)card.FindName("MarketplaceSource")!).Text = marketplace.Source.Label;
            ((TextBlock)card.FindName("SupplyLine")!).Text = SkillPresentation.SupplyLine(marketplace);
            ((TextBlock)card.FindName("AutoUpdateLine")!).Text =
                $"{SkillPresentation.AutoUpdateLine(marketplace)}. "
                + SkillPresentation.AutoUpdateReason(marketplace);

            if (moved.Count > 0)
            {
                var movedLine = (TextBlock)card.FindName("MovedLine")!;
                movedLine.Text =
                    "Owner changed since install - the router first saw "
                    + $"{moved[0].Provenance!.FirstSeenSource}. "
                    + "Updates are paused until you say that transfer was expected.";
                movedLine.Visibility = Visibility.Visible;
            }

            ((StackPanel)card.Child).Children.Add(buttons);
            AutomationProperties.SetName(card,
                $"{marketplace.Name}. {SkillPresentation.SupplyLine(marketplace)}.");
            AutomationProperties.SetAutomationId(card, $"skills.marketplace.{marketplace.Name}");
            host.Children.Add(card);
        }

        if (marketplaces.Count == 0)
        {
            host.Children.Add(FooterText(
                "No marketplaces are followed. Adding one is the Discover board's action, and "
                + "it arrives with WIN7.",
                "skills.marketplaces.none"));
        }

        return new ScrollViewer { Content = host, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    // ------------------------------------------------------------------ the updates tab

    private FrameworkElement UpdatesView(SkillsBoardSnapshot snapshot)
    {
        var host = new Grid { ColumnSpacing = 12 };
        host.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });

        var headers = new[] { "Skill", "Installed", "Available", "What changed", "" };
        for (var column = 0; column < headers.Length; column++)
        {
            if (headers[column].Length == 0) continue;
            var header = SecondaryCaption();
            header.Text = headers[column];
            header.VerticalAlignment = VerticalAlignment.Center;
            AutomationProperties.SetName(header, headers[column]);
            AutomationProperties.SetAutomationId(header, $"skills.updates.header.{headers[column]}");
            Grid.SetColumn(header, column);
            host.Children.Add(header);
        }

        var row = 1;
        foreach (var skill in snapshot.Updated)
        {
            var held = skill.Held!;
            var origin = skill.Source.AsPlugin;
            var installedVersion = origin?.PluginVersion ?? "unversioned";
            var wantsMore = held.WantsMore;

            var rowGrid = (Grid)LoadUi(
                "<Grid " + FragmentNs + " Height=\"40\" ColumnSpacing=\"12\">"
                + "  <TextBlock Grid.Column=\"0\" x:Name=\"UpdateName\" TextTrimming=\"CharacterEllipsis\""
                + "             VerticalAlignment=\"Center\" FontWeight=\"SemiBold\""
                + "             Style=\"{StaticResource BodyTextBlockStyle}\""
                + "             Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
                + "  <TextBlock Grid.Column=\"1\" x:Name=\"InstalledVersion\" VerticalAlignment=\"Center\""
                + "             FontFamily=\"Consolas\" Style=\"{StaticResource BodyTextBlockStyle}\""
                + "             Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
                + "  <TextBlock Grid.Column=\"2\" x:Name=\"AvailableVersion\" VerticalAlignment=\"Center\""
                + "             FontFamily=\"Consolas\" Style=\"{StaticResource BodyTextBlockStyle}\""
                + "             Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
                + "  <StackPanel Grid.Column=\"3\" Orientation=\"Horizontal\" Spacing=\"6\" VerticalAlignment=\"Center\">"
                + "    <Ellipse Width=\"8\" Height=\"8\" Fill=\"{ThemeResource "
                + (wantsMore ? "SystemFillColorCautionBrush" : "SystemFillColorSuccessBrush") + "}\" />"
                + "    <TextBlock x:Name=\"WhatChanged\" TextTrimming=\"CharacterEllipsis\""
                + "               VerticalAlignment=\"Center\""
                + "               Style=\"{StaticResource BodyTextBlockStyle}\""
                + "               Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
                + "  </StackPanel>"
                + "  <Border Grid.Column=\"4\" CornerRadius=\"4\" Padding=\"8,2,8,2\" VerticalAlignment=\"Center\""
                + "          HorizontalAlignment=\"Left\" Background=\"{ThemeResource "
                + (wantsMore ? "SubtleFillColorSecondaryBrush" : "SubtleFillColorSecondaryBrush") + "}\">"
                + "    <TextBlock x:Name=\"Disposition\" VerticalAlignment=\"Center\""
                + "               Style=\"{StaticResource CaptionTextBlockStyle}\""
                + "               Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
                + "  </Border>"
                + "</Grid>");

            ((TextBlock)rowGrid.FindName("UpdateName")!).Text = skill.Name;
            ((TextBlock)rowGrid.FindName("InstalledVersion")!).Text = installedVersion;
            ((TextBlock)rowGrid.FindName("AvailableVersion")!).Text = held.PluginVersion;
            ((TextBlock)rowGrid.FindName("WhatChanged")!).Text = SkillPresentation.WhatChanged(skill);
            ((TextBlock)rowGrid.FindName("Disposition")!).Text = SkillPresentation.Disposition(skill);

            // The dot is colour on a §2 indicator hue; the word beside it is the only carrier
            // some readers have, and §6 makes it mandatory rather than decorative.
            AutomationProperties.SetName(rowGrid,
                $"{skill.Name}: installed {installedVersion}, available {held.PluginVersion}. "
                + $"{SkillPresentation.WhatChanged(skill)}. {SkillPresentation.Disposition(skill)}.");
            AutomationProperties.SetAutomationId(rowGrid, $"skills.update.{skill.Name}");

            host.RowDefinitions.Add(new RowDefinition { Height = new GridLength(40) });
            Grid.SetRow(rowGrid, row);
            host.Children.Add(rowGrid);
            row++;
        }

        var stack = new StackPanel { Spacing = 8 };
        stack.Children.Add(host);
        stack.Children.Add(FooterText(
            "A new version lands as a shadow copy first. It promotes itself only when its "
            + "capability set is unchanged; anything that asks for more than the version before "
            + "it waits for you.",
            "skills.footer.updates"));

        return new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    // ------------------------------------------------------------------ the load states

    private FrameworkElement Skeleton()
    {
        var stack = new StackPanel { Spacing = 8 };
        // Skeleton rows at the real row height, never a spinner over a blank pane (§5 Loading).
        for (var row = 0; row < 6; row++)
        {
            stack.Children.Add(LoadUi(
                "<Border " + FragmentNs + " Height=\"52\" CornerRadius=\"4\""
                + " Background=\"{ThemeResource SubtleFillColorSecondaryBrush}\" />"));
        }
        AutomationProperties.SetName(stack, "Loading skills");
        AutomationProperties.SetAutomationId(stack, "skills.loading");
        return stack;
    }

    private FrameworkElement EmptyState()
    {
        var addMarketplace = new Button
        {
            Content = "Add a marketplace…",
            IsEnabled = false,
        };
        AutomationProperties.SetName(addMarketplace, "Add a marketplace…");
        AutomationProperties.SetAutomationId(addMarketplace, "skills.empty.addMarketplace");
        AutomationProperties.SetHelpText(addMarketplace, Win7Reason);

        var scanLocal = new Button { Content = SkillPresentation.ScanLocalAction, IsEnabled = false };
        AutomationProperties.SetName(scanLocal, SkillPresentation.ScanLocalAction);
        AutomationProperties.SetAutomationId(scanLocal, "skills.empty.scanLocal");
        AutomationProperties.SetHelpText(scanLocal, ScanReason);

        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        actions.Children.Add(addMarketplace);
        actions.Children.Add(scanLocal);

        var card = (Border)LoadUi(
            "<Border " + FragmentNs + " MaxWidth=\"520\" Padding=\"32\""
            + " HorizontalAlignment=\"Center\" VerticalAlignment=\"Center\""
            + " Background=\"{ThemeResource CardBackgroundFillColorDefaultBrush}\""
            + " BorderBrush=\"{ThemeResource ControlStrokeColorDefaultBrush}\" BorderThickness=\"1\""
            + " CornerRadius=\"4\">"
            + "  <StackPanel Spacing=\"12\">"
            + "    <FontIcon FontFamily=\"{ThemeResource SymbolThemeFontFamily}\" Glyph=\"&#xE8F1;\""
            + "              FontSize=\"28\" HorizontalAlignment=\"Left\""
            + "              Foreground=\"{ThemeResource TextFillColorTertiaryBrush}\" />"
            + "    <TextBlock x:Name=\"EmptyTitle\" TextWrapping=\"Wrap\""
            + "               Style=\"{StaticResource SubtitleTextBlockStyle}\""
            + "               Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
            + "    <TextBlock x:Name=\"EmptyDetail\" TextWrapping=\"Wrap\""
            + "               Style=\"{StaticResource BodyTextBlockStyle}\""
            + "               Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
            + "  </StackPanel>"
            + "</Border>");

        ((TextBlock)card.FindName("EmptyTitle")!).Text = SkillPresentation.EmptyTitle;
        ((TextBlock)card.FindName("EmptyDetail")!).Text = SkillPresentation.EmptyDetail;
        ((StackPanel)card.Child).Children.Add(actions);

        AutomationProperties.SetName(card,
            $"{SkillPresentation.EmptyTitle}. {SkillPresentation.EmptyDetail}");
        AutomationProperties.SetAutomationId(card, "skills.empty");

        return card;
    }

    private FrameworkElement ErrorState(SkillsControlError error)
    {
        var retry = new Button { Content = "Retry" };
        AutomationProperties.SetName(retry, "Retry");
        AutomationProperties.SetAutomationId(retry, "skills.error.retry");
        retry.Click += (_, _) => _ = RefreshAsync();

        var card = (Border)LoadUi(
            "<Border " + FragmentNs + " MaxWidth=\"560\" Padding=\"32\""
            + " HorizontalAlignment=\"Center\" VerticalAlignment=\"Center\""
            + " Background=\"{ThemeResource CardBackgroundFillColorDefaultBrush}\""
            + " BorderBrush=\"{ThemeResource ControlStrokeColorDefaultBrush}\" BorderThickness=\"1\""
            + " CornerRadius=\"4\">"
            + "  <StackPanel Spacing=\"10\">"
            + "    <FontIcon FontFamily=\"{ThemeResource SymbolThemeFontFamily}\" Glyph=\"&#xE783;\""
            + "              FontSize=\"28\" HorizontalAlignment=\"Left\""
            + "              Foreground=\"{ThemeResource TextFillColorTertiaryBrush}\" />"
            + "    <TextBlock x:Name=\"ErrorHeadline\" TextWrapping=\"Wrap\""
            + "               Style=\"{StaticResource BodyStrongTextBlockStyle}\""
            + "               Foreground=\"{ThemeResource TextFillColorPrimaryBrush}\" />"
            + "    <TextBlock x:Name=\"ErrorAdvice\" TextWrapping=\"Wrap\""
            + "               Style=\"{StaticResource BodyTextBlockStyle}\""
            + "               Foreground=\"{ThemeResource TextFillColorSecondaryBrush}\" />"
            + "  </StackPanel>"
            + "</Border>");

        ((TextBlock)card.FindName("ErrorHeadline")!).Text = error.Headline;
        ((TextBlock)card.FindName("ErrorAdvice")!).Text = error.Advice;
        ((StackPanel)card.Child).Children.Add(retry);

        AutomationProperties.SetName(card, $"{error.Headline}. {error.Advice}");
        AutomationProperties.SetAutomationId(card, "skills.error");

        return card;
    }

    // ------------------------------------------------------------------ helpers

    /// <summary>
    /// Loads a XAML fragment. Fragments are how code-built elements keep ThemeResource behaviour:
    /// a brush fetched from a resource dictionary in code is one appearance's value, while a
    /// ThemeResource in markup re-resolves when the theme changes - which the shell follows live,
    /// and the self-test forces both ways.
    /// </summary>
    private static FrameworkElement LoadUi(string xaml) =>
        (FrameworkElement)Microsoft.UI.Xaml.Markup.XamlReader.Load(xaml);

    private static string Escape(string text) =>
        text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");
}
