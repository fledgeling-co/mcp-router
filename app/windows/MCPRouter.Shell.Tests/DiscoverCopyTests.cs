using System.Reflection;
using System.Text.RegularExpressions;
using MCPRouter.Shell.Model.Registry;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// Gates over the copy catalog as a whole — the enumerable set of every string this board draws.
/// §11 rule 2 (sentence case everywhere, no menu-case carve-out), §6 (one name per state), and
/// the brief's own conditional as a test: no rate, delta or percentage can be rendered anywhere
/// on this surface, because nothing in it could produce one.
/// </summary>
public sealed class DiscoverCopyTests
{
    /// <summary>Every string constant DiscoverCopy declares. The catalog is the source of every
    /// string the board draws; a constant added here is gated automatically.</summary>
    private static IEnumerable<(string Name, string Value)> AllStrings() =>
        typeof(DiscoverCopy)
            .GetFields(BindingFlags.Public | BindingFlags.Static)
            .Where(f => f.FieldType == typeof(string) && f.GetRawConstantValue() is string)
            .Select(f => (f.Name, Value: (string)f.GetRawConstantValue()!))
            .Where(pair => pair.Value.Length > 0);

    private static readonly HashSet<string> ProperNouns = new(StringComparer.Ordinal)
    {
        // The same allowlist SentenceCaseTests holds the shell to, plus the index and product
        // names this board's shared sentences carry.
        "MCP", "Router", "URL", "File", "Explorer", "iPhone", "Windows",
        "Official", "Smithery", "GitHub", "PC",
        // "Most" only as the first word of the band name, the same narrow scope as "Router".
        "Most",
        // The capitalised stand-in the template substitution uses, so it never reads as a
        // spurious mid-sentence capital itself.
        "Placeholder",
    };

    /// <summary>Strings that are deliberately lowercase fragments appended into, or drawn under,
    /// a larger sentence — the design of record draws each exactly so: "installed" is a quiet
    /// fact on a row, the date verbs precede the day, the suffix trails the provenance sentence,
    /// and the two nouns are substituted into the requirement summary. A fragment allowed here is
    /// a decision, not an omission.</summary>
    private static readonly HashSet<string> LowercaseFragments = new(StringComparer.Ordinal)
    {
        nameof(DiscoverCopy.RowInstalled),
        nameof(DiscoverCopy.RowArchived),
        nameof(DiscoverCopy.DateUpdatedVerb),
        nameof(DiscoverCopy.DateAddedVerb),
        nameof(DiscoverCopy.ProvenanceVerifiedSuffix),
        nameof(DiscoverCopy.RequirementValueSingular),
        nameof(DiscoverCopy.RequirementValuePlural),
    };

    [Fact]
    public void CatalogIsNotEmpty()
    {
        // A gate over zero strings gates nothing: if the catalog's shape changes, this fails
        // rather than passing quietly.
        Assert.True(AllStrings().Count() >= 60, $"the copy catalog holds only {AllStrings().Count()} strings");
    }

    [Theory]
    [MemberData(nameof(EnumerateAll))]
    public void CasingFollowsTheDeclaredShape(string name, string value)
    {
        // Placeholders are typed to what the real substitution is, because the drawn string's
        // grammar depends on it: counts and windows are numerals, a failure reason is a full
        // sentence of its own, and a name is a capitalised word.
        var prose = Regex.Replace(value, @"\{count\}|\{window\}|\{secrets\}", "9");
        prose = Regex.Replace(prose, @"\{reason\}|\{warning\}", "Placeholder.");
        prose = Regex.Replace(prose, @"\{\w+\}", "Placeholder");

        if (LowercaseFragments.Contains(name))
        {
            var fragment = prose.TrimStart(',', ' ');
            Assert.True(char.IsLower(fragment[0]),
                $"{name}: '{value}' is declared a lowercase fragment and is not one");
            return;
        }
        // Multi-sentence strings are judged per sentence: a capital at a sentence boundary is a
        // start, not a violation.
        var sentences = Regex.Split(prose, @"(?<=[.!?])\s+").Where(s => s.Trim().Length > 0);
        foreach (var sentence in sentences)
        {
            var words = Regex.Split(sentence, @"[\s/·]+")
                .Select(w => w.Trim('…', '.', ',', '?', '!', '(', ')', ':', ';', '"', '\'', '“', '”', '\''))
                .Where(w => w.Length > 0)
                .ToList();

            Assert.True(words.Count > 0, $"{name} has an empty sentence: '{value}'");
            Assert.True(char.IsUpper(words[0][0]) || char.IsAsciiDigit(words[0][0]),
                $"{name}: '{value}' does not start '{sentence}' with a capital");

            foreach (var word in words.Skip(1))
            {
                if (!char.IsUpper(word[0])) continue;
                Assert.True(ProperNouns.Contains(word),
                    $"{name}: '{value}' capitalises '{word}' mid-sentence - §11 rule 2 is sentence case everywhere");
            }
        }
    }

    public static IEnumerable<object[]> EnumerateAll() =>
        AllStrings().Select(pair => new object[] { pair.Name, pair.Value });

    [Fact]
    public void NoRateDeltaOrPercentageAppearsAnywhere()
    {
        // The brief: a trending row carries a window AND a signed delta, or it is not drawn as
        // trending. This board draws no trending rows — nothing keeps history — so there is no
        // legitimate percentage anywhere in it, and one appearing in the catalog would mean the
        // surface can render a claim no measurement produced.
        foreach (var (name, value) in AllStrings())
        {
            Assert.DoesNotContain("%", value, StringComparison.Ordinal);
            Assert.DoesNotContain("−", value, StringComparison.Ordinal);
        }
    }

    [Fact]
    public void TrendingRefusalMatchesTheDesignOfRecordVerbatim()
    {
        // DESIGN.md §6 names this sentence as the design of record for the state, carried from
        // RegistryPresentation+Notes.swift. One name per state across platforms: if the Mac's
        // sentence ever moves, this gate turns red rather than letting the platforms drift.
        Assert.Equal(
            "No trend or velocity figure is shown. Measuring one needs a history of these indexes "
            + "over time, which the router does not keep yet.",
            DiscoverCopy.TrendingNote);
    }

    [Fact]
    public void NoInstallAffordanceExistsOutsideTheDetailDialog()
    {
        // The security property, stated in the copy layer: nothing outside the dialog's action
        // labels may say "Add …" — a row string promising an install is the affordance the board
        // is shaped to refuse. The AddAction / Statement / Requirement families are the dialog's.
        foreach (var (name, value) in AllStrings())
        {
            var isDialogCopy = name.StartsWith("AddAction", StringComparison.Ordinal)
                || name.StartsWith("Statement", StringComparison.Ordinal)
                || name.StartsWith("Requirement", StringComparison.Ordinal);
            if (isDialogCopy) continue;
            Assert.False(value.Contains("Add ", StringComparison.Ordinal),
                $"{name} promises an install from outside the detail dialog: '{value}'");
        }
    }

    [Fact]
    public void ReasonTextCoversEveryFailureReason()
    {
        foreach (var reason in Enum.GetValues<DiscoverCopy.FailureReason>())
        {
            Assert.False(string.IsNullOrEmpty(DiscoverCopy.ReasonText(reason)));
        }
    }
}
