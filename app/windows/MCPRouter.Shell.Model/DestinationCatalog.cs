namespace MCPRouter.Shell.Model;

/// <summary>
/// The ten destinations, in the design of record's order and grouping.
/// </summary>
public static class DestinationCatalog
{
    public const string SettingsId = "settings";

    /// <summary>The four pane headers, in order, as the design of record spells them.</summary>
    public static IReadOnlyList<string> Groups { get; } =
        new[] { "Store", "Routing", "Maintenance", "Attention" };

    public static IReadOnlyList<Destination> All { get; } = new[]
    {
        new Destination(
            "discover", "Discover", "Store", "Shop",
            Model.Accelerator.Control("1"), "D",
            "The store: a featured band over collection rails, never one flat list.",
            "WIN7"),

        new Destination(
            "skills", "Skills", "Store", "Library",
            Model.Accelerator.Control("2"), "S",
            "Every skill the router knows, and which harness has each one loaded.",
            "WIN6"),

        new Destination(
            "servers", "Servers", "Routing", "Globe",
            Model.Accelerator.Control("3"), "V",
            "The Signal Path over the declared servers, and what is plugged in right now.",
            "WIN4"),

        new Destination(
            "activity", "Activity", "Routing", "List",
            Model.Accelerator.Control("4"), "A",
            "A live log of every call the router has routed, with its arguments and its result.",
            "WIN5"),

        // No chord. DESIGN.md §13 binds Ctrl+1-4 and Ctrl+6-8 and states why Ctrl+5 and Ctrl+9
        // are absent. The reason has expired on Windows - this shell does open both boards - but
        // granting a chord the design authority does not carry is a build editing its own spec.
        // spec-WIN3 §3.3 routes the question to WIN21, and the board stays reachable by the pane,
        // by the View menu and by Alt + V + H, so §11 rule 9's guarantee is untouched.
        new Destination(
            "harnesses", "Harnesses", "Routing", "Link",
            null, "H",
            "Every harness on the machine, how each one reaches the router, and what it duplicates.",
            "WIN14"),

        new Destination(
            "checks", "Checks", "Maintenance", "Accept",
            Model.Accelerator.Control("6"), "C",
            "What the router checked for itself, stamped to the version each check ran against.",
            "WIN8"),

        new Destination(
            "cleanup", "Cleanup", "Maintenance", "Delete",
            Model.Accelerator.Control("7"), "L",
            "What has gone unused, over a window it states, with why each row might still matter.",
            "WIN9"),

        new Destination(
            "inbox", "Inbox", "Attention", "Mail",
            Model.Accelerator.Control("8"), "I",
            "What the phone queued for review here. The phone queues; it never installs.",
            "WIN10"),

        // Ctrl+9 absent for the same reason as Ctrl+5. See the note above.
        new Destination(
            "insights", "Insights", "Attention", "Zoom",
            null, "N",
            "What the router observed about itself, and never a figure without its denominator.",
            "WIN15"),

        // Settings is the NavigationView's own pane-footer item rather than a board row, and it
        // takes no chord. DESIGN.md §13: "Windows publishes no settings accelerator, and it does
        // not need one: the navigation view carries an optional entry point for app settings as
        // its own item at the foot of the pane, which is where a Windows user looks."
        new Destination(
            SettingsId, "Settings", null, "Setting",
            null, "T",
            "Seven panes of what this app may do to the machine, and how often it re-reads it.",
            "WIN13"),
    };

    public static IReadOnlyList<Destination> Boards { get; } =
        All.Where(d => d.Id != SettingsId).ToList();

    public static Destination ById(string id) =>
        All.FirstOrDefault(d => d.Id == id)
        ?? throw new ArgumentOutOfRangeException(nameof(id), id, "no such destination");

    public static Destination Default => ById("servers");
}
