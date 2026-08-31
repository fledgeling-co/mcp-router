using MCPRouter.Shell.Model;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// DESIGN.md §11 rule 9 - the rule this whole item exists to answer.
///
/// "Every command the app can perform is reachable from one enumerable in-window surface … and
/// every command on that surface carries an access key, so Alt enumerates the whole command set
/// without a pointer. A command reachable only by a chord, a right-click or a gesture is a
/// defect."
/// </summary>
public sealed class CommandSurfaceCompletenessTests
{
    [Fact]
    public void EveryCommandSitsOnAKnownMenu()
    {
        var menus = CommandCatalog.Menus.Select(m => m.Title).ToHashSet();
        var strays = CommandCatalog.All.Where(c => !menus.Contains(c.Menu)).Select(c => c.Id).ToList();
        Assert.True(strays.Count == 0, "commands on no declared menu: " + string.Join(", ", strays));
    }

    [Fact]
    public void EveryCommandAppearsExactlyOnce()
    {
        var duplicated = CommandCatalog.All
            .GroupBy(c => c.Id)
            .Where(g => g.Count() > 1)
            .Select(g => g.Key)
            .ToList();
        Assert.True(duplicated.Count == 0, "duplicated command ids: " + string.Join(", ", duplicated));
    }

    /// <summary>The rule's own sentence, as a check: no command is reachable only by a chord.</summary>
    [Fact]
    public void NoCommandIsReachableOnlyByAChord()
    {
        // Every command in the catalogue is on the menu bar by construction - the MenuBar is
        // built from this list. So the check that carries weight is the inverse: a command that
        // holds a chord and no menu placement would be reachable only by the chord.
        var chordOnly = CommandCatalog.All
            .Where(c => c.Accelerator is not null && string.IsNullOrWhiteSpace(c.Menu))
            .Select(c => c.Id)
            .ToList();
        Assert.True(chordOnly.Count == 0, "chord-only commands: " + string.Join(", ", chordOnly));
    }

    /// <summary>
    /// Navigating to a destination is a command, so every destination is on the surface. Without
    /// this, a board could be reachable by the navigation pane alone - a pointer-only path, which
    /// is what rule 9 refuses.
    /// </summary>
    [Fact]
    public void EveryDestinationIsOnTheCommandSurface()
    {
        foreach (var destination in DestinationCatalog.All)
        {
            var id = CommandCatalog.GoToCommandId(destination.Id);
            var command = CommandCatalog.All.SingleOrDefault(c => c.Id == id);
            Assert.True(command is not null, $"{destination.Label} has no View menu item");
            Assert.Equal(CommandCatalog.MenuView, command!.Menu);
            Assert.Equal(destination.Label, command.Label);
            Assert.Equal(destination.Accelerator, command.Accelerator);
        }
    }

    /// <summary>
    /// Two commands the design of record carries and this platform does not. Written as a test so
    /// the removals stay decisions rather than becoming omissions somebody restores by accident.
    /// </summary>
    [Fact]
    public void TheTwoRemovedCommandsStayRemoved()
    {
        Assert.DoesNotContain(CommandCatalog.All, c =>
            c.Label.Contains("appearance", StringComparison.OrdinalIgnoreCase));

        Assert.DoesNotContain(CommandCatalog.All, c =>
            c.Label.Contains("breaker", StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// The app menu and the Window menu do not cross, and their contents are redistributed rather
    /// than dropped. Exit, About and Settings are the three that had to land somewhere.
    /// </summary>
    [Fact]
    public void TheAppMenusContentsLandedSomewhere()
    {
        Assert.Equal(CommandCatalog.MenuFile, CommandCatalog.ById("file.exit").Menu);
        Assert.Equal(CommandCatalog.MenuHelp, CommandCatalog.ById("help.about").Menu);

        var settings = CommandCatalog.ById(
            CommandCatalog.GoToCommandId(DestinationCatalog.SettingsId));
        Assert.Equal(CommandCatalog.MenuView, settings.Menu);

        Assert.DoesNotContain(CommandCatalog.Menus, m => m.Title == "Window");
        Assert.DoesNotContain(CommandCatalog.Menus, m => m.Title == "MCP Router");
    }
}
