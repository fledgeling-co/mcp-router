using MCPRouter.Shell.Model;
using MCPRouter.Shell.Model.Control;
using MCPRouter.Shell.Views;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.System;

namespace MCPRouter.Shell.Shell;

/// <summary>
/// The window every board is drawn inside.
///
/// It owns four things no board should have to solve again: the Mica base and the caption band,
/// the ten destinations and the command surface over them, the theme following the system live,
/// and the per-monitor DPI the window is re-laid out under.
/// </summary>
public sealed partial class ShellWindow : Window
{
    private readonly Dictionary<string, NavigationViewItem> _navItems = new();
    private readonly Dictionary<string, MenuFlyoutItem> _menuItems = new();

    private string _currentDestinationId = DestinationCatalog.Default.Id;
    private double _rasterizationScale;
    private bool _sidebarShown = true;
    private readonly ISkillsControlClient? _skillsClient;

    /// <param name="skillsClient">
    /// The skills board's read client. Null builds the live one against the loopback control
    /// port; App passes the Debug fixture client for <c>--fixture-skills</c>.
    /// </param>
    public ShellWindow(ISkillsControlClient? skillsClient = null)
    {
        _skillsClient = skillsClient;

        InitializeComponent();

        // §11 rule 3: Mica on the window backdrop, once, and never on a UI element. When the user
        // turns transparency off, or the machine is on battery saver, or the window is inactive,
        // Windows falls this back to SolidBackgroundFillColorBase itself - the app inherits that
        // rather than implementing it (§13).
        SystemBackdrop = new MicaBackdrop { Kind = MicaKind.Base };

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(DragRegion);

        BuildCommandSurface();
        BuildDestinations();
        RegisterPaneCycling();

        RootGrid.Loaded += OnRootLoaded;
        RootGrid.ActualThemeChanged += OnActualThemeChanged;
        // The app authors no inactive-window chrome.
        //
        // On macOS the traffic lights go to --tl-off when the window is not key, and DESIGN.md
        // §11 records that those four tokens have no Windows counterpart: Windows draws its
        // caption buttons itself and an app that colours them is painting chrome that is not its
        // own. The same argument reaches the title beside them, so it stays on
        // TextFillColorPrimaryBrush through a ThemeResource in XAML - which also means it follows
        // the theme without any code, and the brush lookup that used to run here (against
        // Application.Current.Resources, so under the APP's theme rather than the element's) is
        // gone with it. Mica's own inactive fallback is the platform's and is inherited.

        ShowDestination(DestinationCatalog.Default.Id);
    }

    // ------------------------------------------------------------------ observable state

    /// <summary>What the shell currently is, for the self-test to record.</summary>
    public ShellState State => new(
        _currentDestinationId,
        Title,
        BoardTitle.Text,
        RootGrid.ActualTheme.ToString(),
        _rasterizationScale,
        SystemBackdrop is MicaBackdrop,
        _navItems.Count,
        CommandCatalog.All.Count);

    internal FrameworkElement RootElement => RootGrid;

    /// <summary>
    /// Puts an opaque ground behind the window's content, or takes it away again.
    ///
    /// Only the self-test uses this. The shell draws transparent so the Mica base shows through,
    /// and RenderTargetBitmap cannot photograph Mica because it composites below XAML - so a
    /// capture taken without a ground has a transparent pane and unreadable labels in it. The
    /// ground is SolidBackgroundFillColorBase, which is Mica's own fallback rather than an
    /// invented colour: it is what Windows draws when transparency is off, and it is the ground
    /// DESIGN.md §12 states every Windows contrast ratio against.
    /// </summary>
    internal void SetCaptureGround(bool on) =>
        CaptureGround.Visibility = on ? Visibility.Visible : Visibility.Collapsed;

    // ------------------------------------------------------------------ the command surface

    private void BuildCommandSurface()
    {
        foreach (var (title, accessKey) in CommandCatalog.Menus)
        {
            var menu = new MenuBarItem { Title = title, AccessKey = accessKey };

            foreach (var command in CommandCatalog.InMenu(title))
            {
                if (command.SeparatorBefore) menu.Items.Add(new MenuFlyoutSeparator());

                var item = new MenuFlyoutItem
                {
                    Text = command.Label,
                    AccessKey = command.AccessKey,
                    IsEnabled = command.Availability.IsEnabled,
                    Tag = command.Id,
                };

                if (command.Accelerator is { } accelerator)
                {
                    item.KeyboardAccelerators.Add(ToKeyboardAccelerator(accelerator));
                }
                else if (command.Availability.Kind == AvailabilityKind.Unbuilt)
                {
                    // M14's pattern, one platform over: the menu says a command is not built
                    // rather than showing an item that is simply grey for no stated reason. The
                    // accelerator column is free on these, so the marker goes where a chord would
                    // have been.
                    item.KeyboardAcceleratorTextOverride = "Not built";
                }

                if (!command.Availability.IsEnabled)
                {
                    // §5 requires a discoverable reason. A disabled control takes no pointer
                    // input, so a tooltip on it never shows; the accessibility plane is where the
                    // reason can actually be reached, and it is also what WIN20's automation lane
                    // reads.
                    AutomationProperties.SetHelpText(item, command.Availability.Reason);
                }

                item.Click += OnCommandInvoked;
                menu.Items.Add(item);
                _menuItems[command.Id] = item;
            }

            Commands.Items.Add(menu);
        }
    }

    private static KeyboardAccelerator ToKeyboardAccelerator(Model.Accelerator accelerator)
    {
        var modifiers = VirtualKeyModifiers.None;
        if (accelerator.Ctrl) modifiers |= VirtualKeyModifiers.Control;
        if (accelerator.Shift) modifiers |= VirtualKeyModifiers.Shift;
        if (accelerator.Alt) modifiers |= VirtualKeyModifiers.Menu;

        return new KeyboardAccelerator { Key = ToVirtualKey(accelerator.Key), Modifiers = modifiers };
    }

    private static VirtualKey ToVirtualKey(string key)
    {
        if (key.Equals("DEL", StringComparison.OrdinalIgnoreCase)) return VirtualKey.Delete;
        if (key.Length == 1 && char.IsAsciiLetterUpper(key[0]))
            return VirtualKey.A + (key[0] - 'A');
        if (key.Length == 1 && char.IsAsciiDigit(key[0]))
            return VirtualKey.Number0 + (key[0] - '0');

        throw new ArgumentOutOfRangeException(nameof(key), key, "no virtual key for this accelerator");
    }

    private void OnCommandInvoked(object sender, RoutedEventArgs e)
    {
        if (sender is not MenuFlyoutItem { Tag: string id }) return;
        Invoke(id);
    }

    internal void Invoke(string commandId)
    {
        // Every destination's View item is "go to that destination", so navigation is one branch
        // rather than ten.
        const string goToPrefix = "view.goto.";
        if (commandId.StartsWith(goToPrefix, StringComparison.Ordinal))
        {
            SelectDestination(commandId[goToPrefix.Length..]);
            return;
        }

        switch (commandId)
        {
            case "file.exit":
                Close();
                break;

            case "view.toggleSidebar":
                _sidebarShown = !_sidebarShown;
                Nav.IsPaneOpen = _sidebarShown;
                break;

            case "library.browseStore":
                SelectDestination("discover");
                break;

            case "library.runChecks":
                // WIN8: the command navigates to the board and runs all. The board may still be
                // composing when the call arrives, so it is deferred to its own Loaded path.
                SelectDestination("checks");
                if (BoardHost.Content is ChecksBoard board)
                {
                    _ = board.RunAllFromCommandAsync();
                }

                break;

            case "help.about":
                ShowAbout();
                break;

            default:
                // Everything else is Unbuilt and its menu item is disabled, so this is
                // unreachable through the UI. It is here rather than absent because a silent
                // default would make a future wiring mistake look like a working command.
                StartupLog.Write($"command '{commandId}' has no handler and should not have been invokable");
                break;
        }
    }

    private async void ShowAbout()
    {
        var dialog = new ContentDialog
        {
            XamlRoot = RootGrid.XamlRoot,
            Title = "About MCP Router",
            Content = "The Windows client's shell. Nine boards and Settings; each board is drawn "
                      + "by its own item and says so until it is.",
            // §11 rule 4: in a dialog the "do it" button leads and the safe action is rightmost -
            // the reverse of macOS. A one-button dialog has only the safe action, so it takes the
            // close position and no accent fill is spent.
            CloseButtonText = "Close",
        };

        await dialog.ShowAsync();
    }

    // ------------------------------------------------------------------ the destinations

    private void BuildDestinations()
    {
        string? lastGroup = null;

        foreach (var destination in DestinationCatalog.Boards)
        {
            if (destination.Group is { } group && group != lastGroup)
            {
                // Sentence case, secondary colour - §11 rule 2 and §3 rule 2 before it. The
                // header is the design of record's own word, not a re-invented one.
                Nav.MenuItems.Add(new NavigationViewItemHeader { Content = group });
                lastGroup = group;
            }

            var item = new NavigationViewItem
            {
                Content = destination.Label,
                Tag = destination.Id,
                Icon = new SymbolIcon(Enum.Parse<Symbol>(destination.Symbol)),
            };

            AutomationProperties.SetName(item, destination.Label);
            ToolTipService.SetToolTip(item, destination.WillShow);

            Nav.MenuItems.Add(item);
            _navItems[destination.Id] = item;
        }

        // Settings is the NavigationView's own pane-footer item rather than a row in the list.
        // DESIGN.md §13: "the navigation view carries an optional entry point for app settings as
        // its own item at the foot of the pane, which is where a Windows user looks."
        //
        // It is wired in Nav.Loaded rather than here. SettingsItem is created by the control's
        // template, which has not been applied while this constructor runs, so it is null at this
        // point - and a null here meant SelectDestination("settings") found nothing to select and
        // returned silently, leaving whichever board was showing. The self-test caught it: the
        // Settings capture came back titled "Insights".
        Nav.Loaded += OnNavLoaded;
    }

    private void OnNavLoaded(object sender, RoutedEventArgs e)
    {
        if (Nav.SettingsItem is not NavigationViewItem settingsItem) return;

        var settings = DestinationCatalog.ById(DestinationCatalog.SettingsId);
        settingsItem.Content = settings.Label;
        settingsItem.Tag = DestinationCatalog.SettingsId;
        AutomationProperties.SetName(settingsItem, settings.Label);
        ToolTipService.SetToolTip(settingsItem, settings.WillShow);
        _navItems[DestinationCatalog.SettingsId] = settingsItem;
    }

    private void OnDestinationChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        var id = args.IsSettingsSelected
            ? DestinationCatalog.SettingsId
            : (args.SelectedItem as NavigationViewItem)?.Tag as string;

        if (id is null) return;
        ShowDestination(id);
    }

    /// <summary>Selects a destination as a user would, through the navigation view.</summary>
    public void SelectDestination(string destinationId)
    {
        // Settings is asked for by identity rather than looked up, because the pane-footer item
        // only exists once the control's template has been applied. A dictionary miss here used
        // to leave the previous board showing while reporting success.
        if (destinationId == DestinationCatalog.SettingsId)
        {
            if (Nav.SettingsItem is null)
            {
                throw new InvalidOperationException(
                    "the navigation view has no settings item yet - the template has not been applied");
            }

            Nav.SelectedItem = Nav.SettingsItem;
            ShowDestination(destinationId);
            return;
        }

        if (!_navItems.TryGetValue(destinationId, out var item))
        {
            throw new ArgumentOutOfRangeException(
                nameof(destinationId), destinationId, "no navigation item for this destination");
        }

        Nav.SelectedItem = item;
        ShowDestination(destinationId);
    }

    private void ShowDestination(string destinationId)
    {
        var destination = DestinationCatalog.ById(destinationId);
        _currentDestinationId = destinationId;

        // Built boards mount their views; unbuilt destinations keep their placeholder.
        BoardHost.Content = destinationId switch
        {
            "servers" => new ServersBoard(),
            "skills" => new SkillsBoard(
                _skillsClient ?? new LiveSkillsControlClient(),
                SelectDestination),
            "checks" => new ChecksBoard(),
            "activity" => new ActivityBoard(destination, this, SelectDestination),
            "discover" => new DiscoverBoard(),
            "inbox" => new InboxBoard(),
            _ => new BoardPlaceholder(destination),
        };

        // §11 rule 7: the window title says what you are looking at, not the app's name. Both the
        // band and the window itself, so the taskbar agrees with the chrome.
        BoardTitle.Text = destination.WindowTitle;
        Title = destination.WindowTitle;
    }

    // ------------------------------------------------------------------ panes and the keyboard

    private void RegisterPaneCycling()
    {
        // §13: "F6 cycles panes sidebar -> table -> inspector, which is §8's tab order read
        // through the Windows key for it; Tab moves within a pane." The shell has two panes so
        // far; a board that adds an inspector extends this list rather than re-registering F6.
        RootGrid.KeyboardAccelerators.Add(new KeyboardAccelerator
        {
            Key = VirtualKey.F6,
            Modifiers = VirtualKeyModifiers.None,
            ScopeOwner = RootGrid,
        });
        RootGrid.KeyboardAccelerators[^1].Invoked += (_, e) => { CyclePane(forward: true); e.Handled = true; };

        RootGrid.KeyboardAccelerators.Add(new KeyboardAccelerator
        {
            Key = VirtualKey.F6,
            Modifiers = VirtualKeyModifiers.Shift,
            ScopeOwner = RootGrid,
        });
        RootGrid.KeyboardAccelerators[^1].Invoked += (_, e) => { CyclePane(forward: false); e.Handled = true; };
    }

    private void CyclePane(bool forward)
    {
        var contentHasFocus = FocusManager.GetFocusedElement(RootGrid.XamlRoot) is DependencyObject focused
                              && IsInsideBoardHost(focused);

        var target = contentHasFocus == forward
            ? (Control?)_navItems.GetValueOrDefault(_currentDestinationId)
            : BoardHost;

        target?.Focus(FocusState.Programmatic);
    }

    private bool IsInsideBoardHost(DependencyObject node)
    {
        for (var current = node; current is not null; current = VisualTreeHelper.GetParent(current))
        {
            if (ReferenceEquals(current, BoardHost)) return true;
        }
        return false;
    }

    // ------------------------------------------------------------------ theme, DPI, caption band

    private void OnRootLoaded(object sender, RoutedEventArgs e)
    {
        ApplyCaptionColours();
        ReserveCaptionButtonWidth();

        if (RootGrid.XamlRoot is { } xamlRoot)
        {
            _rasterizationScale = xamlRoot.RasterizationScale;
            xamlRoot.Changed += OnXamlRootChanged;
            StartupLog.Write($"loaded at rasterization scale {_rasterizationScale}");
        }

        if (App.SelfTestDirectory is { } directory) _ = RunSelfTestAsync(directory);
    }

    private async Task RunSelfTestAsync(string directory)
    {
        int code;
        try
        {
            code = await new SelfTestDriver(this, directory).RunAsync();
            StartupLog.Write($"selftest finished with {code}");
        }
        catch (Exception ex)
        {
            // A self-test that dies without a code is indistinguishable from one that passed and
            // exited, so the exception becomes the exit code rather than a silent stop.
            StartupLog.Write($"selftest threw: {ex}");
            code = 71;
        }

        Environment.Exit(code);
    }

    private void OnXamlRootChanged(XamlRoot sender, XamlRootChangedEventArgs args)
    {
        // A per-monitor DPI change arrives here as a new rasterization scale. XAML re-lays the
        // tree out itself - the manifest's PerMonitorV2 is what stops Windows bitmap-stretching
        // the window instead - so the shell's job is to re-derive the one measurement it took in
        // physical pixels: the width the system's caption buttons occupy.
        if (Math.Abs(sender.RasterizationScale - _rasterizationScale) > 0.001)
        {
            StartupLog.Write($"rasterization scale {_rasterizationScale} -> {sender.RasterizationScale}");
            _rasterizationScale = sender.RasterizationScale;
        }

        ReserveCaptionButtonWidth();
    }

    private void OnActualThemeChanged(FrameworkElement sender, object args)
    {
        // Every brush in this window is a theme resource, so the content re-resolves itself. The
        // caption buttons are not XAML and do not: they are the AppWindow's, and their colours
        // have to be re-applied or the band keeps the outgoing appearance's foreground.
        StartupLog.Write($"actual theme -> {RootGrid.ActualTheme}");
        ApplyCaptionColours();
    }

    private void ApplyCaptionColours()
    {
        // Transparent, so the Mica base shows through the caption band rather than a painted
        // strip sitting on top of it. The foreground is left to the system: DESIGN.md §11 rule 12
        // makes the accent the user's, and the same argument applies to caption glyphs - an app
        // that hard-codes them ships one appearance's colour in both.
        var titleBar = AppWindow.TitleBar;
        titleBar.ButtonBackgroundColor = Microsoft.UI.Colors.Transparent;
        titleBar.ButtonInactiveBackgroundColor = Microsoft.UI.Colors.Transparent;
    }

    private void ReserveCaptionButtonWidth()
    {
        // The caption buttons are the system's and their width is not ours to assume: it differs
        // between Windows builds and it is reported in physical pixels, so it has to be divided
        // by the current rasterization scale to become a XAML margin.
        var scale = _rasterizationScale > 0 ? _rasterizationScale : 1.0;
        var inset = AppWindow.TitleBar.RightInset / scale;
        DragRegion.Margin = new Thickness(0, 0, inset, 0);
    }
}

/// <summary>
/// What the shell is, at a moment, as values a test or a self-test can compare.
/// </summary>
/// <param name="DestinationId">Which of the ten is selected.</param>
/// <param name="WindowTitle">What the window (and so the taskbar) is called.</param>
/// <param name="BandTitle">What the caption band draws.</param>
/// <param name="ActualTheme">The theme resolved from the system, never set by the app.</param>
/// <param name="RasterizationScale">The DPI scale this window is currently laid out under.</param>
/// <param name="HasMica">Whether the window's backdrop is Mica.</param>
/// <param name="DestinationCount">How many destinations the pane holds.</param>
/// <param name="CommandCount">How many commands the command surface holds.</param>
public sealed record ShellState(
    string DestinationId,
    string WindowTitle,
    string BandTitle,
    string ActualTheme,
    double RasterizationScale,
    bool HasMica,
    int DestinationCount,
    int CommandCount);
