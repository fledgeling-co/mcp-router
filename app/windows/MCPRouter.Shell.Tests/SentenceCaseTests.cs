using System.Text.RegularExpressions;
using MCPRouter.Shell.Model;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// DESIGN.md §11 rule 2 - "Sentence case everywhere, titles and menu items included. Windows
/// publishes one casing rule and states no exception to it, so §6's macOS menu-bar carve-out does
/// not cross."
///
/// This is the one rule where Windows is stricter than macOS, and it is the easiest to lose:
/// every menu string in the design of record is Title Case, because on macOS it is required to
/// be. A Windows surface built by copying those strings ships the wrong casing on every item.
/// </summary>
public sealed class SentenceCaseTests
{
    /// <summary>
    /// Words allowed to keep a capital in the middle of a label. Deliberately short and explicit:
    /// a generous allowlist would let Title Case back in one word at a time.
    /// </summary>
    private static readonly HashSet<string> ProperNouns = new(StringComparer.Ordinal)
    {
        "MCP",       // the protocol
        "Router",    // only as the second word of the product name
        "URL",
        "File",      // "File Explorer", the Windows shell's own name
        "Explorer",
        "iPhone",
        "Windows",
    };

    public static IEnumerable<object[]> AllLabels()
    {
        foreach (var (title, _) in CommandCatalog.Menus) yield return new object[] { "menu title", title };
        foreach (var command in CommandCatalog.All) yield return new object[] { command.Id, command.Label };
        foreach (var destination in DestinationCatalog.All) yield return new object[] { destination.Id, destination.Label };
        foreach (var group in DestinationCatalog.Groups) yield return new object[] { "group header", group };
    }

    [Theory]
    [MemberData(nameof(AllLabels))]
    public void LabelsAreSentenceCase(string owner, string label)
    {
        Assert.False(string.IsNullOrWhiteSpace(label), $"{owner} has an empty label");

        var words = Regex.Split(label, @"[\s/]+")
            .Select(w => w.Trim('…', '.', ',', '?', '!', '(', ')', ':', ';', '"', '\''))
            .Where(w => w.Length > 0)
            .ToList();

        Assert.True(char.IsUpper(words[0][0]) || ProperNouns.Contains(words[0]),
            $"{owner}: '{label}' does not start with a capital");

        foreach (var word in words.Skip(1))
        {
            if (!char.IsUpper(word[0])) continue;
            Assert.True(ProperNouns.Contains(word),
                $"{owner}: '{label}' capitalises '{word}' mid-label - §11 rule 2 is sentence case, " +
                "and §6's macOS menu carve-out does not cross to Windows");
        }
    }

    /// <summary>
    /// Tracked uppercase is the loudest web tell and §3 rule 2 says to remove it rather than fix
    /// its tracking. The rule survives the platform change; only the section number moves.
    /// </summary>
    [Theory]
    [MemberData(nameof(AllLabels))]
    public void NoLabelIsAllCaps(string owner, string label)
    {
        var letters = label.Where(char.IsLetter).ToList();
        if (letters.Count < 3) return;                       // "MCP" alone is a proper noun
        if (ProperNouns.Contains(label)) return;

        Assert.False(letters.All(char.IsUpper), $"{owner}: '{label}' is all caps");
    }

    /// <summary>
    /// The design of record's own menu strings are Title Case, correctly, because macOS requires
    /// it. This test proves the Windows catalogue did not simply copy them.
    /// </summary>
    [Fact]
    public void TheMacsTitleCaseStringsDidNotCrossVerbatim()
    {
        string[] macStrings =
        {
            "New Server…", "Add Marketplace…", "Import from Harness…", "Export Configuration…",
            "Pair iPhone…", "Re-index Manifest", "Restart Router", "Wake Selected Server",
            "Reap Idle Children", "Review Held Changes…", "Update All Skills", "Run Doctor",
            "Run All Checks", "Export Library…", "Report an Issue…", "About MCP Router",
        };

        // Two of these are identical in both casings, because every word in them is either the
        // first word or a proper noun. They are listed as exceptions so the coincidence is
        // visible rather than absent - a reader who finds "About MCP Router" in both files should
        // be able to see that it was checked and allowed, not overlooked.
        string[] identicalInBothCasings = { "About MCP Router", "Pair iPhone…" };

        var crossed = CommandCatalog.All
            .Select(c => c.Label)
            .Where(l => macStrings.Contains(l, StringComparer.Ordinal))
            .Where(l => !identicalInBothCasings.Contains(l, StringComparer.Ordinal))
            .ToList();

        Assert.True(crossed.Count == 0,
            "these labels are the macOS Title Case strings verbatim: " + string.Join(", ", crossed));
    }
}
