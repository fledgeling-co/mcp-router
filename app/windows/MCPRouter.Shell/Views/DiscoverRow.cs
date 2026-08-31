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
        };
    }

    private static string? SecondaryFor(RegistryEntry entry)
    {
        // The archived warning outranks the secondary name; the name appears only where it
        // differs from the display name, which is the case a reader needs to see.
        if (RegistryPresentation.ArchivedNoteFor(entry) is { } archived) return archived;
        var name = RegistryText.Sanitize(entry.Name, cap: 60);
        return name != RegistryText.Sanitize(entry.DisplayName, cap: 60) ? name : null;
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
