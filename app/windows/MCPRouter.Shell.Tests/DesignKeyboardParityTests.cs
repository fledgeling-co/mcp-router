using System.Text.RegularExpressions;
using MCPRouter.Shell.Model;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// DESIGN.md §13's keyboard table, read as the set of bindings this app must hold, in both
/// directions.
///
/// This is the Windows twin of the Mac's <c>MenuCommandTests.designSectionEightParses</c>, and it
/// is built for the same reason: the board digits were once the one part of the accelerator map
/// that lived only in a switch statement, so the gate covered every chord in the app except the
/// seven a user presses most.
///
/// §13's table carries two kinds of row and this fixture keeps them apart rather than dropping
/// the ones that are not chords. <c>Ctrl+N</c> is an accelerator on a command; <c>Alt</c>,
/// <c>F6</c>, <c>Return</c>, <c>Esc</c> and <c>Space</c> are behaviours. A row that is neither
/// bound nor declared is a row this app has lost, and that is what fails here.
/// </summary>
public sealed class DesignKeyboardParityTests
{
    private static readonly IReadOnlyList<(string Key, string Behaviour)> TableRows = ParseTable();

    private static IReadOnlyList<(string Key, string Behaviour)> ParseTable()
    {
        var design = RepoRoot.Read("DESIGN.md");

        var start = design.IndexOf("### The Windows keyboard", StringComparison.Ordinal);
        Assert.True(start >= 0, "DESIGN.md no longer carries a '### The Windows keyboard' section");

        // The table is the first one after that heading; it ends at the blank line after it.
        var section = design[start..];
        var rows = new List<(string, string)>();
        var seenHeader = false;

        foreach (var raw in section.Split('\n'))
        {
            var line = raw.TrimEnd('\r').Trim();
            if (!line.StartsWith('|'))
            {
                if (seenHeader && rows.Count > 0) break;   // the table has ended
                continue;
            }

            if (line.StartsWith("|---", StringComparison.Ordinal)) { seenHeader = true; continue; }

            var cells = line.Trim('|').Split('|').Select(c => c.Trim()).ToArray();
            if (cells.Length < 2) continue;
            if (cells[0] == "Key") continue;              // the header row

            var key = cells[0].Trim('`', ' ');
            if (key.Length == 0) continue;
            rows.Add((key, cells[1]));
        }

        Assert.True(rows.Count >= 10,
            $"parsed only {rows.Count} rows out of §13's keyboard table - the parser has lost the table");
        return rows;
    }

    /// <summary>Every chord row in §13 is bound to exactly one command.</summary>
    [Fact]
    public void EveryChordInTheTableIsBoundToExactlyOneCommand()
    {
        var missing = new List<string>();
        var duplicated = new List<string>();

        foreach (var (key, _) in TableRows)
        {
            if (!Accelerator.TryParse(key, out var accelerator)) continue;   // a behaviour row

            var bound = CommandCatalog.All
                .Where(c => c.Accelerator == accelerator)
                .ToList();

            if (bound.Count == 0) missing.Add(key);
            else if (bound.Count > 1) duplicated.Add($"{key} -> {string.Join(", ", bound.Select(b => b.Id))}");
        }

        Assert.True(missing.Count == 0, "DESIGN.md §13 binds chords this app does not: " + string.Join(", ", missing));
        Assert.True(duplicated.Count == 0, "one chord is on more than one command: " + string.Join("; ", duplicated));
    }

    /// <summary>
    /// The other direction. A chord the app binds that §13 does not carry is the app writing its
    /// own spec, which is the failure this half exists to catch - see spec-WIN3 §3.3 on Ctrl+5
    /// and Ctrl+9.
    /// </summary>
    [Fact]
    public void EveryChordTheAppBindsIsARowInTheTable()
    {
        var tableChords = TableRows
            .Where(r => Accelerator.TryParse(r.Key, out _))
            .Select(r => { Accelerator.TryParse(r.Key, out var a); return a; })
            .ToHashSet();

        var unauthorised = CommandCatalog.All
            .Where(c => c.Accelerator is not null && !tableChords.Contains(c.Accelerator.Value))
            .Select(c => $"{c.Id} binds {c.Accelerator}")
            .ToList();

        Assert.True(unauthorised.Count == 0,
            "these chords are bound but are not rows in DESIGN.md §13: " + string.Join("; ", unauthorised));
    }

    /// <summary>Every non-chord row is a declared behaviour, so no row is silently dropped.</summary>
    [Fact]
    public void EveryBehaviourRowInTheTableIsDeclared()
    {
        var declared = CommandCatalog.Behaviours.Select(b => b.Key).ToHashSet(StringComparer.OrdinalIgnoreCase);

        var undeclared = TableRows
            .Where(r => !Accelerator.TryParse(r.Key, out _))
            .Select(r => r.Key)
            .Where(k => !declared.Contains(k))
            .ToList();

        Assert.True(undeclared.Count == 0,
            "§13 names these keys and the shell declares no behaviour for them: " + string.Join(", ", undeclared));
    }

    /// <summary>
    /// And the reverse: a declared behaviour with no row is a key the app has invented.
    /// </summary>
    [Fact]
    public void EveryDeclaredBehaviourIsARowInTheTable()
    {
        var tableKeys = TableRows.Select(r => r.Key).ToHashSet(StringComparer.OrdinalIgnoreCase);

        var invented = CommandCatalog.Behaviours
            .Select(b => b.Key)
            .Where(k => !tableKeys.Contains(k))
            .ToList();

        Assert.True(invented.Count == 0,
            "the shell declares behaviours DESIGN.md §13 does not name: " + string.Join(", ", invented));
    }

    /// <summary>
    /// The board digits, named individually. This is the row the Mac's gate was widened to cover
    /// after it turned out to be the one part of the map nothing watched.
    /// </summary>
    [Theory]
    [InlineData("1", "discover")]
    [InlineData("2", "skills")]
    [InlineData("3", "servers")]
    [InlineData("4", "activity")]
    [InlineData("6", "checks")]
    [InlineData("7", "cleanup")]
    [InlineData("8", "inbox")]
    public void BoardDigitsGoWhereTheTableSaysTheyGo(string digit, string destinationId)
    {
        var destination = DestinationCatalog.ById(destinationId);
        Assert.Equal(Accelerator.Control(digit), destination.Accelerator);
    }

    /// <summary>
    /// Ctrl+5 and Ctrl+9 are unbound, deliberately, and this test is the record of that decision
    /// rather than an accident nobody noticed. spec-WIN3 §3.3 routes the question to WIN21.
    /// </summary>
    [Theory]
    [InlineData("harnesses")]
    [InlineData("insights")]
    public void HarnessesAndInsightsTakeNoChordAndAreStillReachable(string destinationId)
    {
        var destination = DestinationCatalog.ById(destinationId);
        Assert.Null(destination.Accelerator);

        // §11 rule 9 forbids a command reachable only by a chord, not one reachable by no chord.
        var viewItem = CommandCatalog.ById(CommandCatalog.GoToCommandId(destinationId));
        Assert.Equal(CommandCatalog.MenuView, viewItem.Menu);
        Assert.False(string.IsNullOrWhiteSpace(viewItem.AccessKey));
    }
}
