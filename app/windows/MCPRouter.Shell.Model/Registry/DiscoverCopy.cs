namespace MCPRouter.Shell.Model.Registry;

/// <summary>
/// Every user-facing string the Discover board draws, keyed by surface × state.
///
/// The Mac's <c>DiscoverCopy</c> is the source this file takes shared sentences from verbatim
/// (DESIGN.md §6: one name per state across platforms, taken from one source rather than spelled
/// twice) — the band titles and notes, the partial and empty states, the units, the trending
/// refusal and the capability statement. Where Windows differs, the difference is the platform,
/// not a paraphrase: the router is <b>local</b> here, so the phone's "isn't running on your Mac"
/// becomes "isn't running on this PC", and "queue for your Mac" becomes the local Add.
///
/// The catalog exists so the completeness and casing gates walk an enumerable set rather than
/// hope about a XAML tree: <see cref="All" /> is the population every string gate runs over, and
/// a string the board adds without a key here is a string no gate reads.
/// </summary>
public static class DiscoverCopy
{
    // ----------------------------------------------------------------- the board chrome

    public const string BoardTitle = "Discover";

    public const string SearchPlaceholder = "Search the server registries";
    public const string SearchAccessibilityLabel = SearchPlaceholder;

    public const string PublisherAll = "All publishers";
    public const string PublisherOfficial = "Official registry";
    public const string PublisherSmithery = "Smithery";
    /// <summary>The one quiet sentence saying what the filter scopes, drawn beside it (§6 helper
    /// text) — the same disclosure discipline as the window's applies-to note.</summary>
    public const string PublisherNote =
        "Filters both bands by provenance, read from each row's id rather than its source label.";
    public const string PublisherEmptyHeadline = "No entries in this publisher filter.";
    public const string PublisherEmptyBody =
        "This search returned entries from another publisher. Choose all publishers to see them.";

    public const string WindowLabel = "Window";
    /// <summary>The design system's applies-to note: the asymmetry is stated on the control
    /// itself rather than left to be discovered.</summary>
    public const string WindowAppliesTo =
        "The window filters recently changed. Most used is an all-time total and has no window.";

    public const string WindowAnyTime = "Any time";
    public const string WindowNinety = "90 days";
    public const string WindowThirty = "30 days";
    public const string WindowSeven = "7 days";

    public const string RetryAction = "Try again";
    public const string ClearSearchAction = "Clear search";
    public const string ShowAnyTimeAction = "Any time";

    // ----------------------------------------------------------------- bands

    public const string BandMostUsed = "Most used";
    public const string BandMostUsedNote =
        "Sessions started on Smithery, all-time, of the results shown. The only popularity figure "
        + "either index publishes — the official registry publishes none, so entries it alone "
        + "carries are absent from this band rather than ranked at zero.";

    public const string BandRecentlyChanged = "Recently changed";
    public const string BandRecentlyChangedNote =
        "The most recently changed of the results shown. The official registry reports when an "
        + "entry was last edited; Smithery reports when it was created. They are different stamps "
        + "under one field, so this orders them without claiming they mean the same thing.";

    // ----------------------------------------------------------------- units (the figure carries unit + index)

    /// <summary>"sessions on Smithery" — never "installs", never "downloads". Smithery publishes
    /// sessions started, and the unit names both the quantity and who published it.</summary>
    public const string UnitSessions = "{count} sessions on Smithery";
    public const string UnitStars = "{count} stars on GitHub";

    public const string NoteShowingFirst = "Showing the first {count} matches. Narrow the search to see others.";
    public const string NoteSlowSearch =
        "Searching both registries. This can take a while the first time — star counts are "
        + "fetched one repository at a time and cached for a day.";

    /// <summary>The design of record's named sentence for the trending refusal
    /// (<c>RegistryPresentation+Notes.swift</c> <c>trendingNote</c>), carried verbatim. Stated
    /// once, always: the brief's rule — a trending row carries a window and a signed delta, or it
    /// is not drawn as trending — resolves to "not drawn" for every row this data can produce,
    /// and the surface says why rather than leaving a band-shaped silence.</summary>
    public const string TrendingNote =
        "No trend or velocity figure is shown. Measuring one needs a history of these indexes "
        + "over time, which the router does not keep yet.";

    /// <summary>The ranking disclosure, taken from the Mac's <c>rankingNote</c>. Drawn whenever
    /// results are shown, because the merged rank is the order rows arrive in and its bias toward
    /// the one commercial index that publishes a count is structural.</summary>
    public const string RankingNote =
        "Best match is the router's own order: most sessions on Smithery first, then GitHub "
        + "stars, then date. Only Smithery publishes a session count, so entries that appear only "
        + "in the official registry sort below entries that have one.";

    // ----------------------------------------------------------------- provenance and row facts

    /// <summary>The provenance sentence, by what the evidence (the id prefix) establishes.</summary>
    public const string ProvenanceBoth = "In the official registry and on Smithery";
    public const string ProvenanceOfficial = "In the official registry";
    public const string ProvenanceSmithery = "On Smithery";
    public const string ProvenanceVerifiedSuffix = ", verified by Smithery";

    public const string DateUpdatedVerb = "updated";
    public const string DateAddedVerb = "added";

    public const string RowInstalled = "installed";
    public const string RowArchived = "repository archived";

    // ----------------------------------------------------------------- the board's states

    public const string LoadingHeadline = "Searching the server registries.";

    public const string EmptyNoQueryHeadline = "Nothing came back from either index.";
    public const string EmptyNoQueryBody = "Both registries answered and neither listed anything.";

    public const string EmptyQueryHeadline = "No server matches “{query}”.";
    public const string EmptyQueryBody =
        "Search covers the official MCP registry and Smithery. Try a shorter word, or clear the "
        + "search to browse the bands.";

    public const string PartialOfficialDownHeadline = "Showing Smithery only.";
    public const string PartialOfficialDownBody =
        "The official registry didn't answer, so anything it alone lists is missing.";

    public const string PartialSmitheryDownHeadline = "Showing the official registry only.";
    public const string PartialSmitheryDownBody =
        "Smithery didn't answer, so anything it alone lists is missing — including the session "
        + "counts Most used ranks on.";

    public const string PartialGitHubLimitedHeadline = "Repository details are incomplete.";
    public const string PartialGitHubLimitedBody =
        "GitHub limits how often it can be asked, so stars and archive status are missing for "
        + "some entries. Everything else is complete.";

    /// <summary>A warning matching no known class renders verbatim under a generic heading rather
    /// than being dropped — a degraded surface that loses the explanation for its own degradation
    /// is worse than one that shows an unpolished sentence.</summary>
    public const string PartialUnrecognisedHeadline = "The search reported a problem.";
    public const string PartialUnrecognisedBody = "{warning}";

    public const string BandEmptyMostUsedHeadline = "No result here has a session count.";
    public const string BandEmptyMostUsedBody =
        "Only Smithery publishes one, so entries the official registry alone carries are absent "
        + "from this band rather than ranked at zero.";

    public const string BandEmptyRecentlyChangedWindowedHeadline =
        "Nothing in these results changed in the last {window} days.";
    public const string BandEmptyRecentlyChangedWindowedBody = "Widen the window to see more.";

    public const string BandEmptyRecentlyChangedAnyTimeHeadline = "No result here carries a change date.";
    public const string BandEmptyRecentlyChangedAnyTimeBody =
        "Neither index reported when these entries were last changed.";

    /// <summary>The router is local on Windows — WIN23 owns starting it — so the pane says what
    /// is true here rather than borrowing the phone's "open MCP Router on your Mac".</summary>
    public const string OfflineHeadline = "The router isn't running on this PC.";
    public const string OfflineBody =
        "Discover reads the registries through it, so nothing can be searched until it starts. "
        + "Start MCP Router, then try again.";

    public const string StaleBannerHeadline = "Showing the last good reading.";
    public const string StaleBannerBody = "{reason} The reading above is from the last search that completed.";

    // ----------------------------------------------------------------- the detail dialog

    public const string DetailCloseAction = "Close";

    public const string StatementStdioHeadline = "Runs a program on this PC";
    public const string StatementStdioBody =
        "It runs as you, which means it can read and write the files you can and open the "
        + "connections you can. Nothing declares what it will actually do, and that cannot be "
        + "checked before it runs.";

    public const string StatementRemoteHeadline = "Connects to {host}";
    public const string StatementRemoteNoHostHeadline = "Connects to a remote server";
    public const string StatementRemoteBody =
        "Nothing runs on this PC. Whatever you send it goes to that host, and what it does with "
        + "it is not declared here.";

    public const string StatementNoInstallHeadline = "Neither index says how to run this";
    public const string StatementNoInstallBody =
        "The entry exists in the catalogue but carries no command and no address, so there is "
        + "nothing to add.";

    /// <summary>The one quiet sentence saying where the statement came from, so it is not
    /// mistaken for something the entry's author declared and stands behind.</summary>
    public const string StatementDerivationNote =
        "Read from the entry's install instructions, not from anything its author declared. No "
        + "registry format carries a capability list, so this describes how it starts and not "
        + "what it goes on to do.";

    public const string RequirementSummaryNoSecrets = "Asks for {count} {noun} before it can start.";
    public const string RequirementSummaryAllSecret = "Asks for {count} {noun} before it can start, all of them secret.";
    public const string RequirementSummarySomeSecret = "Asks for {count} {noun} before it can start, {secrets} of them secret.";
    public const string RequirementValueSingular = "value";
    public const string RequirementValuePlural = "values";

    /// <summary>Where a typed value ends up, stated plainly and unflatteringly — the app stores
    /// nothing, but the router writes it into its own config, and a sentence implying a keychain
    /// would be false.</summary>
    public const string SecretDestination =
        "Held only while this dialog is open, then sent to the router with the declaration. This "
        + "app does not store it.";

    public const string AddActionFormat = "Add {name}";
    public const string AddActionRevealsFormat = "Add {name}…";
    public const string AddActionInstalling = "Adding…";
    public const string AddActionAdded = "Added";
    public const string AddedDisabledReasonFormat = "Already declared as “{name}”.";
    public const string NoInstallDisabledReason =
        "Neither index says how to run this, so there is nothing to add.";
    public const string MissingOneReasonFormat = "{names} has no value yet, and an empty one would be stored as a blank credential.";
    public const string MissingManyReasonFormat = "{names} have no values yet, and empty ones would be stored as blank credentials.";

    public const string InstallFailedHeadline = "The router refused the addition.";
    public const string InstallFailedBody = "{reason} Nothing was changed on your PC.";
    public const string InstallUnauthorizedBody =
        "The router did not accept this app's control token. Nothing was changed on your PC.";

    // ----------------------------------------------------------------- the enum over states

    /// <summary>The closed set of renderings for a search failure. The router's message body is
    /// free text written for a developer and can carry whatever a third-party index returned, so
    /// it is never interpolated into a sentence the user is asked to trust.</summary>
    public enum FailureReason
    {
        Unauthorized,
        MalformedResponse,
        RouterRefused,
        Transport,
    }

    public static string ReasonText(FailureReason reason) => reason switch
    {
        FailureReason.Unauthorized => "This app isn't authorised to search through the router",
        FailureReason.MalformedResponse => "The router sent a response this version doesn't understand",
        FailureReason.RouterRefused => "The router couldn't complete the search",
        FailureReason.Transport => "Couldn't reach the router",
        _ => throw new ArgumentOutOfRangeException(nameof(reason), reason, "unknown failure reason"),
    };
}
