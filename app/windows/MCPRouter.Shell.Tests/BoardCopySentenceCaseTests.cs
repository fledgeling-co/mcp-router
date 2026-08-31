using MCPRouter.Checks.Model;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// §11 rule 2 over the board's own strings: sentence case everywhere, titles included — and the
/// §6 rule it enforces by construction, verb-first buttons. The Windows floor is stricter than
/// macOS here, and the check sentences were written for a platform whose menu bar capitalises;
/// this fixture is what stops those strings crossing in their old clothes.
/// </summary>
public sealed class BoardCopySentenceCaseTests
{
    public static IEnumerable<object[]> Strings()
    {
        foreach (var s in StringsOfBoard())
        {
            yield return new object[] { s };
        }
    }

    private static IEnumerable<string> StringsOfBoard()
    {
        yield return CheckCopy.RunAllLabel;
        yield return CheckCopy.RunStaleLabel;
        yield return CheckCopy.RunOneLabel;
        yield return CheckCopy.RetryLabel;
        yield return CheckCopy.RerunLabel("trawl");
        yield return CheckCopy.EmptyTitle;
        yield return CheckCopy.StaleWord;
        yield return CheckCopy.NotChecked;
        yield return CheckCopy.CouldNotRun;
        yield return CheckCopy.Unstampable;
        yield return CheckCopy.HistoryHeading;
        yield return CheckCopy.RouterNotRunningHeadline;
    }

    [Theory]
    [MemberData(nameof(Strings))]
    public void ShortLabelsAreSentenceCase(string label)
    {
        Assert.False(string.IsNullOrWhiteSpace(label));
        Assert.True(char.IsUpper(label[0]), $"'{label}' does not start with a capital");

        // Every word after the first is lower-case: no Title Case crept across from the design of
        // record's macOS menu strings.
        foreach (var word in label.Split(' ', StringSplitOptions.RemoveEmptyEntries).Skip(1))
        {
            var first = char.IsLetter(word[0]) ? word[0] : word.FirstOrDefault(char.IsLetter);
            if (first != default)
            {
                Assert.False(char.IsUpper(first), $"'{label}' capitalises a mid-label word - §11 rule 2");
            }
        }
    }

    [Fact]
    public void NoBoardStringIsAllCaps()
    {
        foreach (var label in StringsOfBoard())
        {
            var letters = label.Where(char.IsLetter).ToList();
            if (letters.Count < 3)
            {
                continue;
            }

            Assert.False(letters.All(char.IsUpper), $"'{label}' is all caps");
        }
    }
}
