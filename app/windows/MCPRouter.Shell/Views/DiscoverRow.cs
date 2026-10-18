using MCPRouter.Shell.Model.Registry;

namespace MCPRouter.Shell.Views;

/// <summary>
/// One row of either band, as the DataTemplate reads it: every field already formatted and
/// sanitised by <see cref="RegistryPresentation" />, and a Visibility the template can bind
/// directly. Nothing here decides - absent cells are absent, and the figure arrives carrying its
/// unit and its index or not at all.
/// </summary>
public sealed class DiscoverRow
{
    public required RegistryEntry Entry { get; init; }
    public required string DisplayName { get; init; }
    public required string Monogram { get; init; }
    public required Microsoft.UI.Xaml.Visibility HasSecondary { get; init; }
    public required string? Secondary { get; init; }
    public required Microsoft.UI.Xaml.Visibility HasFigure { get; init; }
    public required string FigureText { get; init; }
    public required Microsoft.UI.Xaml.Visibility HasInstalled { get; init; }
    public required string InstalledText { get; init; }
    public required Microsoft.UI.Xaml.Visibility HasDate { get; init; }
    public required string DateText { get; init; }
    public required Microsoft.UI.Xaml.Visibility HasProvenance { get; init; }
    public required string ProvenanceText { get; init; }
    public required string AccessibleName { get; init; }

    /// <summary>
    /// A stable address for this row on the automation plane, distinct from every other row's in
    /// the same band. DEF-084: without it a lane can only take "whichever list item was not a
    /// navigation label", which is a description of how a row was picked rather than of which row
    /// it was.
    /// </summary>
    public required string AutomationId { get; init; }

    public static DiscoverRow From(RegistryEntry entry)
    {
        var secondary = SecondaryFor(entry);
        var figure = RegistryPresentation.FigureFor(entry);
        var date = RegistryPresentation.DateCellFor(entry);
        var provenance = RegistryPresentation.ProvenanceSentenceFor(entry);
        var visible = Microsoft.UI.Xaml.Visibility.Visible;
        var collapsed = Microsoft.UI.Xaml.Visibility.Collapsed;

        return new DiscoverRow
        {
            Entry = entry,
            DisplayName = RegistryText.Sanitize(entry.DisplayName, cap: 80),
            Monogram = RegistryText.Monogram(entry.DisplayName),
            Secondary = secondary,
            HasSecondary = secondary is null ? collapsed : visible,
            FigureText = figure?.Text ?? "",
            HasFigure = figure is null ? collapsed : visible,
            InstalledText = DiscoverCopy.RowInstalled,
            HasInstalled = (entry.Installed ?? false) ? visible : collapsed,
            DateText = date?.Text ?? "",
            HasDate = date is null ? collapsed : visible,
            ProvenanceText = provenance ?? "",
            HasProvenance = provenance is null ? collapsed : visible,
            AccessibleName = AccessibleNameFor(entry),
            AutomationId = AutomationIdFor(entry),
        };
    }

    /// <summary>
    /// DEF-084. A ListViewItem whose item is not a UIElement and carries no
    /// AutomationProperties.Name falls back to ToString() on the item, so every row in the store
    /// published "MCPRouter.Shell.Views.DiscoverRow" - the same constant for all of them, read
    /// aloud by Narrator and useless to any assertion by name. The board sets the container's
    /// name explicitly in OnRowContainerChanging; this override is the floor under that, so a row
    /// realised by a path that never raises ContainerContentChanging still announces the
    /// capability rather than the class.
    /// </summary>
    public override string ToString() => AccessibleName;

    private static string? SecondaryFor(RegistryEntry entry)
    {
        // The archived warning outranks the secondary name; the name appears only where it
        // differs from the display name, which is the case a reader needs to see.
        if (RegistryPresentation.ArchivedNoteFor(entry) is { } archived) return archived;
        var name = RegistryText.Sanitize(entry.Name, cap: 60);
        return name != RegistryText.Sanitize(entry.DisplayName, cap: 60) ? name : null;
    }

    /// <summary>The row's automation id, derived from the entry's own registry id so that it is
    /// the same across two runs against the same registry and different for two different
    /// entries. The display name is not used: two indexes can publish the same display name for
    /// different packages, and an id that collides addresses the wrong row silently.</summary>
    private static string AutomationIdFor(RegistryEntry entry)
    {
        var key = entry.Id;
        if (string.IsNullOrWhiteSpace(key)) key = entry.Name;
        if (string.IsNullOrWhiteSpace(key)) key = entry.DisplayName;

        var slug = new string(key.Trim()
            .Select(c => char.IsLetterOrDigit(c) ? char.ToLowerInvariant(c) : '.')
            .ToArray());
        while (slug.Contains("..")) slug = slug.Replace("..", ".");
        slug = slug.Trim('.');
        return slug.Length == 0 ? "discover.row.unidentified" : "discover.row." + slug;
    }

    /// <summary>One stop, not five: the row announces as one sentence, so a screen-reader user is
    /// not sent swiping through cells (the Mac row accessibility label, same discipline).</summary>
    private static string AccessibleNameFor(RegistryEntry entry)
    {
        var parts = new List<string> { RegistryText.Sanitize(entry.DisplayName, cap: 80) };
        if (RegistryPresentation.FigureFor(entry) is { } figure) parts.Add(figure.Text);
        if (RegistryPresentation.DateCellFor(entry) is { } date) parts.Add(date.Text);
        if (RegistryPresentation.ArchivedNoteFor(entry) is { } archived) parts.Add(archived);
        if (RegistryPresentation.ProvenanceSentenceFor(entry) is { } provenance) parts.Add(provenance);
        if (entry.Installed ?? false) parts.Add("Already installed");
        return string.Join(", ", parts);
    }
}
