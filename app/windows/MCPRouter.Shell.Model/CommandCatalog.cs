namespace MCPRouter.Shell.Model;

/// <summary>
/// The whole command surface, in one place, in the order it is drawn.
///
/// The MenuBar in <c>ShellWindow</c> is built from this list rather than authored in XAML, so the
/// gates measure the surface the app actually draws instead of a parallel list that can drift
/// from it.
///
/// Two menus the design of record carries do not appear here, and neither is a cut:
///
/// * The <b>app menu</b> - Windows has none. <c>About</c> moves to Help, <c>Settings</c> becomes
///   the navigation pane's own footer item (DESIGN.md §13), and <c>Exit</c> moves to File.
/// * The <b>Window menu</b> - Windows has none either. Minimise, maximise and close are the
///   system's caption buttons, and DESIGN.md §11 records that an app authoring that chrome is
///   painting something that is not its own.
///
/// Two commands are removed rather than moved:
///
/// * <c>Switch appearance</c> - on Windows the theme is the system's and the app follows it live.
///   An in-app override would make this app the authority on a setting Windows owns.
/// * <c>Trip selected breaker</c> - the breaker was retired with the lever under M16, which
///   DESIGN.md §1 records. The design of record's menu predates that retirement; carrying the
///   command across would ship a control for a mechanism this product no longer has.
/// </summary>
public static class CommandCatalog
{
    public const string MenuFile = "File";
    public const string MenuEdit = "Edit";
    public const string MenuView = "View";
    public const string MenuRouter = "Router";
    public const string MenuLibrary = "Library";
    public const string MenuHelp = "Help";

    /// <summary>The top-level menus, in order, with the access key each carries.</summary>
    public static IReadOnlyList<(string Title, string AccessKey)> Menus { get; } = new[]
    {
        (MenuFile, "F"),
        (MenuEdit, "E"),
        (MenuView, "V"),
        (MenuRouter, "R"),
        (MenuLibrary, "L"),
        (MenuHelp, "H"),
    };

    private static Availability Unbuilt(string item, string what) =>
        Availability.Unbuilt(item, $"{what} {item} builds it.");

    private static readonly List<AppCommand> Commands = BuildCommands();

    public static IReadOnlyList<AppCommand> All => Commands;

    public static IEnumerable<AppCommand> InMenu(string menu) =>
        Commands.Where(c => c.Menu == menu).OrderBy(c => c.Order);

    public static AppCommand ById(string id) =>
        Commands.FirstOrDefault(c => c.Id == id)
        ?? throw new ArgumentOutOfRangeException(nameof(id), id, "no such command");

    /// <summary>
    /// The command id a View menu item takes for a destination. One id per destination, so the
    /// completeness gate can hold "every destination is on the command surface" by construction
    /// rather than by a list somebody remembers to extend.
    /// </summary>
    public static string GoToCommandId(string destinationId) => $"view.goto.{destinationId}";

    /// <summary>
    /// The keys DESIGN.md §13 names that are behaviours rather than accelerators.
    /// </summary>
    public static IReadOnlyList<KeyboardBehaviour> Behaviours { get; } = new[]
    {
        new KeyboardBehaviour("Alt", "Reveals the access keys - the whole command set, per §11 rule 9"),
        new KeyboardBehaviour("F6", "Move to the next pane; Shift+F6 the previous"),
        new KeyboardBehaviour("Return", "Commits the view's one default action"),
        new KeyboardBehaviour("Esc", "Dismisses the dialog, then clears selection"),
        new KeyboardBehaviour("Space", "Toggles the selected row's Keep warm"),
    };

    private static List<AppCommand> BuildCommands()
    {
        var list = new List<AppCommand>();
        int order;

        // ------------------------------------------------------------------ File
        order = 0;
        list.Add(new("file.newServer", MenuFile, "New server…", "N",
            Accelerator.Control("N"),
            Unbuilt("WIN4", "Declaring a server needs the Servers board and the control client;"),
            order++));
        list.Add(new("file.addMarketplace", MenuFile, "Add marketplace…", "M",
            null,
            Unbuilt("WIN7", "Marketplaces are the Discover board's;"),
            order++));
        list.Add(new("file.import", MenuFile, "Import from harness…", "I",
            null,
            Unbuilt("WIN14", "Reading another tool's configuration is the Harnesses board's;"),
            order++, SeparatorBefore: true));
        list.Add(new("file.export", MenuFile, "Export configuration…", "E",
            null,
            Unbuilt("WIN13", "Export is a Settings surface;"),
            order++));
        list.Add(new("file.pairPhone", MenuFile, "Pair iPhone…", "P",
            null,
            Unbuilt("WIN12", "Pairing is its own item;"),
            order++, SeparatorBefore: true));
        list.Add(new("file.exit", MenuFile, "Exit", "X",
            null, Availability.Available, order++, SeparatorBefore: true));

        // ------------------------------------------------------------------ Edit
        //
        // No clipboard accelerators are granted here. DESIGN.md §13 grants a chord only where its
        // table carries one, and it records the principle for the case that looks like an
        // omission: "Ctrl+A inside a list is the platform's own control accelerator and is
        // inherited rather than granted". Ctrl+C, Ctrl+V, Ctrl+X and Ctrl+Z are the same shape -
        // a text box or list gets them from Windows, and the app declaring them would put a
        // binding in the parity gate that §13's table does not carry.
        order = 0;
        list.Add(new("edit.undo", MenuEdit, "Undo", "U",
            null,
            Unbuilt("WIN10", "Nothing in the shell is reversible yet;"),
            order++));
        list.Add(new("edit.redo", MenuEdit, "Redo", "R",
            null,
            Unbuilt("WIN10", "Nothing in the shell is reversible yet;"),
            order++));
        list.Add(new("edit.cut", MenuEdit, "Cut", "T",
            null,
            Unbuilt("WIN4", "The shell has no editable field;"),
            order++, SeparatorBefore: true));
        list.Add(new("edit.copy", MenuEdit, "Copy", "C",
            null,
            Unbuilt("WIN4", "The shell has no selectable content;"),
            order++));
        list.Add(new("edit.copyEndpoint", MenuEdit, "Copy endpoint URL", "E",
            null,
            Unbuilt("WIN13", "The endpoint is a value the router reports, and no control client exists here;"),
            order++));
        list.Add(new("edit.paste", MenuEdit, "Paste", "P",
            null,
            Unbuilt("WIN4", "The shell has no editable field;"),
            order++));
        list.Add(new("edit.find", MenuEdit, "Find", "F",
            Accelerator.Control("F"),
            Unbuilt("WIN4", "The search field arrives with the first board that has something to search;"),
            order++, SeparatorBefore: true));

        // ------------------------------------------------------------------ View
        order = 0;
        foreach (var destination in DestinationCatalog.Boards)
        {
            list.Add(new(GoToCommandId(destination.Id), MenuView, destination.Label,
                destination.AccessKey, destination.Accelerator, Availability.Available, order++));
        }

        var settings = DestinationCatalog.ById(DestinationCatalog.SettingsId);
        list.Add(new(GoToCommandId(settings.Id), MenuView, settings.Label, settings.AccessKey,
            settings.Accelerator, Availability.Available, order++, SeparatorBefore: true));

        list.Add(new("view.toggleSidebar", MenuView, "Show sidebar", "B",
            null, Availability.Available, order++, SeparatorBefore: true));
        list.Add(new("view.toggleInspector", MenuView, "Show inspector", "P",
            null,
            Unbuilt("WIN4", "The inspector belongs to a board with rows to inspect;"),
            order++));

        // ------------------------------------------------------------------ Router
        order = 0;
        list.Add(new("router.reindex", MenuRouter, "Re-index manifest", "R",
            null,
            Unbuilt("WIN4", "Indexing is a router call, and no control client exists here;"),
            order++));
        list.Add(new("router.restart", MenuRouter, "Restart router", "S",
            null,
            Unbuilt("WIN23", "The router's lifecycle on Windows is unsettled;"),
            order++));
        list.Add(new("router.wakeServer", MenuRouter, "Wake selected server", "W",
            null,
            Unbuilt("WIN4", "Waking needs a selected server, which needs the Servers board;"),
            order++, SeparatorBefore: true));
        list.Add(new("router.removeServer", MenuRouter, "Remove selected server", "M",
            Accelerator.Bare("Del"),
            Unbuilt("WIN4", "Removal needs a selected server, which needs the Servers board;"),
            order++));
        list.Add(new("router.reapChildren", MenuRouter, "Reap idle children", "C",
            null,
            Unbuilt("WIN23", "Child processes are the router's, and its Windows lifecycle is unsettled;"),
            order++));
        list.Add(new("router.reviewHeld", MenuRouter, "Review held changes…", "H",
            null,
            Unbuilt("WIN10", "Held changes are reviewed on the Inbox board;"),
            order++, SeparatorBefore: true));
        list.Add(new("router.showLog", MenuRouter, "Show router log in File Explorer", "L",
            null,
            Unbuilt("WIN23", "The log's location on Windows is part of the router's lifecycle;"),
            order++));
        list.Add(new("router.stop", MenuRouter, "Stop router", "O",
            null,
            Unbuilt("WIN23", "Stopping the router is part of its Windows lifecycle;"),
            order++, SeparatorBefore: true));

        // ------------------------------------------------------------------ Library
        order = 0;
        list.Add(new("library.updateSkills", MenuLibrary, "Update all skills", "U",
            null,
            Unbuilt("WIN6", "The Skills board reads, but its writes wait on the router's skills routes;"),
            order++));
        list.Add(new("library.runDoctor", MenuLibrary, "Run doctor", "D",
            null,
            Unbuilt("WIN8", "Doctor reports onto the Checks board;"),
            order++));
        list.Add(new("library.browseStore", MenuLibrary, "Browse the store…", "B",
            null, Availability.Available, order++, SeparatorBefore: true));
        list.Add(new("library.addMarketplace", MenuLibrary, "Add marketplace…", "M",
            null,
            Unbuilt("WIN7", "Marketplaces are the Discover board's;"),
            order++));
        list.Add(new("library.runChecks", MenuLibrary, "Run all checks", "C",
            null,
            // WIN8: the board is here, and the command navigates to it and runs all.
            Availability.Available,
            order++, SeparatorBefore: true));
        list.Add(new("library.exportLibrary", MenuLibrary, "Export library…", "E",
            null,
            Unbuilt("WIN6", "Export waits on the same router skills routes as the board's writes;"),
            order++));

        // ------------------------------------------------------------------ Help
        order = 0;
        list.Add(new("help.search", MenuHelp, "Search", "S",
            null,
            Unbuilt("WIN4", "There is nothing to search until a board holds data;"),
            order++));
        list.Add(new("help.help", MenuHelp, "MCP Router help", "H",
            null,
            Unbuilt("WIN19", "Help ships with the packaged app;"),
            order++, SeparatorBefore: true));
        list.Add(new("help.whatIsMcp", MenuHelp, "What is MCP?", "W",
            null,
            Unbuilt("WIN19", "The explainer ships with the packaged app;"),
            order++));
        list.Add(new("help.reportIssue", MenuHelp, "Report an issue…", "R",
            null,
            Unbuilt("WIN19", "Issue reporting ships with the packaged app;"),
            order++));
        list.Add(new("help.about", MenuHelp, "About MCP Router", "A",
            null, Availability.Available, order++, SeparatorBefore: true));

        return list;
    }
}
