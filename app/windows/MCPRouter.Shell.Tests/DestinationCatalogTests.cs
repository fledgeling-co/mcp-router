using System.Text.RegularExpressions;
using MCPRouter.Shell.Model;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The information architecture is the design of record's, and this fixture reads it out of the
/// design of record rather than trusting a retyped copy.
///
/// That is the whole point of the directive - parity of feature, Windows in look. A board list
/// that drifted from the Mac's would be a second product wearing the same name, and the drift
/// would be invisible to every other gate here.
/// </summary>
public sealed class DestinationCatalogTests
{
    private const string Mock = "design/mcp-router-console.html";

    private static (IReadOnlyList<string> Groups, IReadOnlyList<(string Id, string Label)> Boards) ParseSidebar()
    {
        var html = RepoRoot.Read(Mock);

        var start = html.IndexOf("<nav class=\"sidebar\"", StringComparison.Ordinal);
        Assert.True(start >= 0, $"{Mock} no longer carries a sidebar nav - the parser is reading nothing");
        var end = html.IndexOf("</nav>", start, StringComparison.Ordinal);
        Assert.True(end > start, $"{Mock}'s sidebar nav is unterminated");
        var nav = html[start..end];

        var groups = Regex.Matches(nav, "<div class=\"side-section\">([^<]+)</div>")
            .Select(m => m.Groups[1].Value.Trim())
            .ToList();

        var boards = Regex.Matches(
                nav,
                "data-board=\"(?<id>[^\"]+)\".*?<span class=\"lbl\">(?<label>[^<]+)</span>",
                RegexOptions.Singleline)
            .Select(m => (m.Groups["id"].Value.Trim(), m.Groups["label"].Value.Trim()))
            .ToList();

        Assert.True(groups.Count > 0, "parsed no group headers out of the design of record's sidebar");
        Assert.True(boards.Count > 0, "parsed no board rows out of the design of record's sidebar");
        return (groups, boards);
    }

    [Fact]
    public void TheNineBoardsAreTheDesignOfRecordsNineBoards()
    {
        var (_, boards) = ParseSidebar();

        Assert.Equal(
            boards.Select(b => b.Id).ToList(),
            DestinationCatalog.Boards.Select(d => d.Id).ToList());
    }

    [Fact]
    public void EveryBoardLabelIsTheDesignOfRecordsLabel()
    {
        var (_, boards) = ParseSidebar();

        foreach (var (id, label) in boards)
        {
            Assert.Equal(label, DestinationCatalog.ById(id).Label);
        }
    }

    [Fact]
    public void TheFourGroupHeadersAreTheDesignOfRecordsHeaders()
    {
        var (groups, _) = ParseSidebar();
        Assert.Equal(groups, DestinationCatalog.Groups.ToList());
    }

    [Fact]
    public void EveryBoardSitsUnderTheGroupTheDesignOfRecordPutsItIn()
    {
        var html = RepoRoot.Read(Mock);
        var start = html.IndexOf("<nav class=\"sidebar\"", StringComparison.Ordinal);
        var end = html.IndexOf("</nav>", start, StringComparison.Ordinal);
        var nav = html[start..end];

        // Walk the sidebar in order, carrying the last header seen.
        var expected = new Dictionary<string, string>();
        string? current = null;
        foreach (Match m in Regex.Matches(
                     nav,
                     "<div class=\"side-section\">(?<group>[^<]+)</div>|data-board=\"(?<id>[^\"]+)\"",
                     RegexOptions.Singleline))
        {
            if (m.Groups["group"].Success) current = m.Groups["group"].Value.Trim();
            else if (current is not null) expected[m.Groups["id"].Value.Trim()] = current;
        }

        foreach (var (id, group) in expected)
        {
            Assert.Equal(group, DestinationCatalog.ById(id).Group);
        }
    }

    /// <summary>
    /// Settings is the tenth destination and is not a board row. DESIGN.md §13: the navigation
    /// view carries it "as its own item at the foot of the pane, which is where a Windows user
    /// looks".
    /// </summary>
    [Fact]
    public void SettingsIsTheTenthDestinationAndSitsInNoGroup()
    {
        Assert.Equal(10, DestinationCatalog.All.Count);
        Assert.Equal(9, DestinationCatalog.Boards.Count);

        var settings = DestinationCatalog.ById(DestinationCatalog.SettingsId);
        Assert.Null(settings.Group);
        Assert.Same(DestinationCatalog.All[^1], settings);
    }

    /// <summary>
    /// Every destination draws something. The brief's own words: "a board with nothing behind it
    /// yet says so rather than rendering blank".
    /// </summary>
    [Fact]
    public void EveryDestinationCarriesBothSentencesItsPlaceholderDraws()
    {
        foreach (var destination in DestinationCatalog.All)
        {
            Assert.False(string.IsNullOrWhiteSpace(destination.WillShow), destination.Id);
            Assert.False(string.IsNullOrWhiteSpace(destination.BuiltBy), destination.Id);
            Assert.Contains(destination.BuiltBy, destination.NotBuiltYet, StringComparison.Ordinal);
        }
    }
}
