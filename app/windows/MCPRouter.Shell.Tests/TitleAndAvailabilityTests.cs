using System.Text.RegularExpressions;
using MCPRouter.Shell.Model;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The title rule, and the disabled-with-a-reason rule. Both are guarantees this product already
/// makes, and both are easy to lose on a new platform without anything noticing.
/// </summary>
public sealed class TitleAndAvailabilityTests
{
    /// <summary>
    /// DESIGN.md §11 rule 7, and §3 rule 7 before it: "The window title says what you are looking
    /// at, not the app's name."
    /// </summary>
    [Fact]
    public void EveryDestinationsWindowTitleIsItsOwnName()
    {
        foreach (var destination in DestinationCatalog.All)
        {
            Assert.Equal(destination.Label, destination.WindowTitle);
        }
    }

    [Fact]
    public void NoDestinationProducesTheAppsNameAsATitle()
    {
        var offenders = DestinationCatalog.All
            .Where(d => d.WindowTitle.Contains("MCP Router", StringComparison.OrdinalIgnoreCase))
            .Select(d => d.Id)
            .ToList();
        Assert.True(offenders.Count == 0,
            "these destinations title the window with the app's name: " + string.Join(", ", offenders));
    }

    /// <summary>
    /// DESIGN.md §5's Disabled row - "dims in place with a discoverable reason" - and §11 rule 4's
    /// "never disappears". A command with nothing behind it stays on the surface and says so.
    /// </summary>
    [Fact]
    public void EveryUnavailableCommandCarriesAReason()
    {
        var silent = CommandCatalog.All
            .Where(c => !c.Availability.IsEnabled)
            .Where(c => string.IsNullOrWhiteSpace(c.Availability.Reason))
            .Select(c => c.Id)
            .ToList();
        Assert.True(silent.Count == 0,
            "these commands are disabled with no discoverable reason: " + string.Join(", ", silent));
    }

    /// <summary>
    /// And the reason has to point somewhere a reader can go. An id that is not in the
    /// orchestrator's table is a promise to nobody.
    /// </summary>
    [Fact]
    public void EveryUnbuiltCommandNamesAnItemThatExists()
    {
        var orchestrator = RepoRoot.Read("ORCHESTRATOR.md");
        var known = Regex.Matches(orchestrator, @"\bWIN\d{1,2}\b")
            .Select(m => m.Value)
            .ToHashSet(StringComparer.Ordinal);

        Assert.True(known.Count >= 20,
            $"only found {known.Count} WIN ids in ORCHESTRATOR.md - the parser is reading nothing");

        var dangling = CommandCatalog.All
            .Where(c => c.Availability.Kind == AvailabilityKind.Unbuilt)
            .Where(c => c.Availability.OwningItem is null || !known.Contains(c.Availability.OwningItem))
            .Select(c => $"{c.Id} -> {c.Availability.OwningItem ?? "(none)"}")
            .ToList();

        Assert.True(dangling.Count == 0,
            "these commands blame an item that is not in ORCHESTRATOR.md: " + string.Join("; ", dangling));
    }

    /// <summary>
    /// The shell can genuinely do these, and a shell that could do none of them would be a menu
    /// bar of forty disabled items - which is a different failure from an honest one.
    /// </summary>
    [Fact]
    public void TheShellsOwnCommandsAreLive()
    {
        string[] live =
        {
            "file.exit", "help.about", "view.toggleSidebar", "library.browseStore",
        };

        foreach (var id in live)
        {
            Assert.True(CommandCatalog.ById(id).Availability.IsEnabled, id);
        }

        foreach (var destination in DestinationCatalog.All)
        {
            var command = CommandCatalog.ById(CommandCatalog.GoToCommandId(destination.Id));
            Assert.True(command.Availability.IsEnabled,
                $"{destination.Label} must be navigable - every destination draws at least an empty state");
        }
    }

    /// <summary>
    /// The accelerator's spelling round-trips through DESIGN.md's own notation, so the parity gate
    /// is comparing values rather than two spellings of one chord.
    /// </summary>
    [Theory]
    [InlineData("Ctrl+N")]
    [InlineData("Ctrl+F")]
    [InlineData("Ctrl+1")]
    [InlineData("Del")]
    public void AcceleratorsRoundTripThroughTheDocumentsSpelling(string text)
    {
        Assert.True(Accelerator.TryParse(text, out var accelerator));
        Assert.Equal(text, accelerator.ToString());
    }

    [Theory]
    [InlineData("Alt")]
    [InlineData("F6")]
    [InlineData("Return")]
    [InlineData("Esc")]
    [InlineData("Space")]
    public void BehaviourKeysAreNotMistakenForChords(string text)
    {
        Assert.False(Accelerator.TryParse(text, out _),
            $"'{text}' is a behaviour in DESIGN.md §13, not a command accelerator");
    }
}
