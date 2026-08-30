using MCPRouter.Shell.Model;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// DESIGN.md §11 rule 9's second limb: "every command on that surface carries an access key, so
/// Alt enumerates the whole command set without a pointer".
///
/// An access key that collides with another in the same scope is worse than none - Windows picks
/// one of them and the other becomes unreachable by keyboard while still looking reachable.
/// </summary>
public sealed class AccessKeyTests
{
    [Fact]
    public void EveryMenuTitleCarriesAnAccessKey()
    {
        var missing = CommandCatalog.Menus
            .Where(m => string.IsNullOrWhiteSpace(m.AccessKey))
            .Select(m => m.Title)
            .ToList();
        Assert.True(missing.Count == 0, "menus with no access key: " + string.Join(", ", missing));
    }

    [Fact]
    public void MenuTitleAccessKeysAreUnique()
    {
        var collisions = CommandCatalog.Menus
            .GroupBy(m => m.AccessKey, StringComparer.OrdinalIgnoreCase)
            .Where(g => g.Count() > 1)
            .Select(g => $"{g.Key}: {string.Join(", ", g.Select(m => m.Title))}")
            .ToList();
        Assert.True(collisions.Count == 0, "colliding menu access keys: " + string.Join("; ", collisions));
    }

    [Fact]
    public void EveryCommandCarriesAnAccessKey()
    {
        var missing = CommandCatalog.All
            .Where(c => string.IsNullOrWhiteSpace(c.AccessKey))
            .Select(c => c.Id)
            .ToList();
        Assert.True(missing.Count == 0, "commands with no access key: " + string.Join(", ", missing));
    }

    [Fact]
    public void AccessKeysAreUniqueWithinEachMenu()
    {
        var collisions = new List<string>();

        foreach (var (menu, _) in CommandCatalog.Menus)
        {
            var groups = CommandCatalog.InMenu(menu)
                .GroupBy(c => c.AccessKey, StringComparer.OrdinalIgnoreCase)
                .Where(g => g.Count() > 1);

            collisions.AddRange(groups.Select(g =>
                $"{menu}/{g.Key}: {string.Join(", ", g.Select(c => c.Id))}"));
        }

        Assert.True(collisions.Count == 0, "colliding access keys: " + string.Join("; ", collisions));
    }

    /// <summary>
    /// An access key that is not a character of its own label leaves nothing for Windows to
    /// underline, so the keytip and the label stop agreeing with each other.
    /// </summary>
    [Fact]
    public void EveryAccessKeyAppearsInItsOwnLabel()
    {
        var strays = CommandCatalog.All
            .Where(c => c.Label.IndexOf(c.AccessKey, StringComparison.OrdinalIgnoreCase) < 0)
            .Select(c => $"{c.Id}: '{c.AccessKey}' is not in '{c.Label}'")
            .ToList();
        Assert.True(strays.Count == 0, string.Join("; ", strays));

        var menuStrays = CommandCatalog.Menus
            .Where(m => m.Title.IndexOf(m.AccessKey, StringComparison.OrdinalIgnoreCase) < 0)
            .Select(m => $"{m.Title}: '{m.AccessKey}'")
            .ToList();
        Assert.True(menuStrays.Count == 0, string.Join("; ", menuStrays));
    }
}
