using System.Text.RegularExpressions;
using MCPRouter.Checks.Model;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The board's words. DESIGN.md §6's table names the check sentences design of record; this
/// fixture holds the port to them and holds the product's refusal — no model-graded score
/// anywhere — where it can actually bite: over every user-facing string this board owns.
/// </summary>
public sealed class CheckCopyTests
{
    /// <summary>Every sentence the board can render, collected from the one place they live.</summary>
    private static IReadOnlyList<string> AllStrings()
    {
        var strings = new List<string>
        {
            CheckCopy.BoardSubtitle,
            CheckCopy.BoardFooter,
            CheckCopy.RunAllLabel,
            CheckCopy.RunStaleLabel,
            CheckCopy.RunOneLabel,
            CheckCopy.RunStaleDisabledReason,
            CheckCopy.StaleWord,
            CheckCopy.StaleDetail(12, "1.4.2"),
            CheckCopy.NoRunMark,
            CheckCopy.NotChecked,
            CheckCopy.NotCheckedDetail(6),
            CheckCopy.CouldNotRun,
            CheckCopy.Invalidated("trawl", "1.4.2", "1.5.0"),
            CheckCopy.RerunLabel("trawl"),
            CheckCopy.LastCompleteRun("trawl", "1.4.2"),
            CheckCopy.NoStoredRun("trawl"),
            CheckCopy.HistoryHeading,
            CheckCopy.HistoryRow("1.4.2", 12, 12, "4 h ago"),
            CheckCopy.Unstampable,
            CheckCopy.UnstampableDetail,
            CheckCopy.EmptyTitle,
            CheckCopy.EmptyDetail,
            CheckCopy.SkillsUnreadable("the router answered 404 for /skills"),
            CheckCopy.RetryLabel,
            CheckCopy.RunningNow("trawl", 2, 6),
            CheckCopy.CheckingLabel,
            CheckCopy.TallyAllConfirmed(6),
            CheckCopy.TallySegments(ServerChecks.All(new ServerRecord
            {
                Name = "obscura",
                IndexedAt = "2026-08-30T10:00:00Z",
                Tools = 4,
                Auth = new AuthRecord { Supported = true, Authorized = false },
                Usage = new UsageRecord { Calls = 12, Errors = 3 },
            })),
        };

        for (var check = 0; check < 6; check++)
        {
            strings.Add(CheckCopy.Statement((CheckId)check));
        }

        strings.Add(CheckCopy.NeverIndexed);
        strings.Add(CheckCopy.IndexFailed("[-32603] Internal error"));
        strings.Add(CheckCopy.NoToolsDeclared);
        strings.Add(CheckCopy.ToolsUnknownUntilIndexed);
        strings.Add(CheckCopy.CredentialsMissing);
        strings.Add(CheckCopy.CredentialsNotApplicable);
        strings.Add(CheckCopy.SurfaceHeld(2, "2026-08-30T09:00:00Z"));
        strings.Add(CheckCopy.Placarded("upstream is moving hosts"));
        strings.Add(CheckCopy.NeverExercised);
        strings.Add(CheckCopy.CallsFailed(3, 12));

        foreach (var kind in Enum.GetValues<ControlApiError.ControlErrorKind>())
        {
            var error = kind switch
            {
                ControlApiError.ControlErrorKind.RouterNotRunning => ControlApiError.RouterNotRunning(),
                ControlApiError.ControlErrorKind.Unauthorized => ControlApiError.Unauthorized(),
                ControlApiError.ControlErrorKind.MalformedResponse => ControlApiError.Malformed("detail"),
                ControlApiError.ControlErrorKind.Server => ControlApiError.ServerError(422, "could not start", "retry with ?force=1"),
                ControlApiError.ControlErrorKind.Transport => ControlApiError.Transport("timed out"),
                _ => throw new ArgumentOutOfRangeException(nameof(kind)),
            };
            strings.Add(error.Headline);
            strings.Add(error.Advice);
        }

        return strings;
    }

    [Fact]
    public void TheDenialIsPermanentCarriageOnTheBoard()
    {
        Assert.Contains("No model-graded evaluation exists in this product", CheckCopy.BoardSubtitle, StringComparison.Ordinal);
        Assert.Contains("stamped to the version each was run against", CheckCopy.BoardSubtitle, StringComparison.Ordinal);
    }

    [Fact]
    public void TheFooterNamesWhatACheckIsNot()
    {
        Assert.Contains("It is not a graded test", CheckCopy.BoardFooter, StringComparison.Ordinal);
        Assert.Contains("Skills are never executed by the router", CheckCopy.BoardFooter, StringComparison.Ordinal);
    }

    [Fact]
    public void TheOnlyGradedWordAnywhereIsTheDenialItself()
    {
        // The refusal names the thing it refuses, so "graded" appears — exactly twice, in the two
        // sentences whose job is the refusal. Every other occurrence would be the vocabulary
        // creeping back in through a side door.
        var offenders = AllStrings()
            .Where(s => !ReferenceEquals(s, CheckCopy.BoardSubtitle) && !ReferenceEquals(s, CheckCopy.BoardFooter))
            .Where(s => s.Contains("graded", StringComparison.OrdinalIgnoreCase)
                        || s.Contains("grade ", StringComparison.OrdinalIgnoreCase))
            .ToList();

        Assert.True(offenders.Count == 0,
            "grading vocabulary outside the refusal sentences: " + string.Join(" | ", offenders));
    }

    [Fact]
    public void NoStringShowsAScoreOrAPercentage()
    {
        // The denial sentence names "model-graded evaluation" to refuse it; that naming is not a
        // score. What must never appear is a score figure or a percentage — tallies are counts.
        var offenders = AllStrings()
            .Where(s => s.Contains('%') || Regex.IsMatch(s, @"\bscore\b", RegexOptions.IgnoreCase))
            .ToList();

        Assert.True(offenders.Count == 0, "score or percentage figures: " + string.Join(" | ", offenders));
    }

    [Fact]
    public void TheVerdictVocabularyIsTheObservationSet()
    {
        // "passed"/"failed" are the words of a test suite; the board speaks observations. The
        // disk spellings (notMet, notObserved) are identifiers, not rendered words, and stay
        // engineering names.
        var rendered = new[] { CheckVerdict.Passed, CheckVerdict.Failed, CheckVerdict.Unknown, CheckVerdict.NotApplicable }
            .Select(CheckVerdictWords.For)
            .ToList();

        Assert.Equal(new[] { "confirmed", "not met", "not observed", "not applicable" }, rendered);
    }

    [Fact]
    public void NoRenderedStringCarriesAGradingVerbAsAState()
    {
        // The rendered verdict words and state words are fixed; a bare "failed" or "passed" as a
        // state word would be the grading vocabulary the board exists to refuse. ("not met"
        // contains neither.)
        foreach (var word in new[] { CheckCopy.StaleWord, CheckCopy.NotChecked, CheckCopy.CouldNotRun })
        {
            Assert.DoesNotContain("passed", word, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("failed", word, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public void EveryStatementIsASpecificSentence()
    {
        for (var check = 0; check < 6; check++)
        {
            var statement = CheckCopy.Statement((CheckId)check);
            Assert.Matches(@"^[A-Z].*", statement);
            Assert.False(statement.EndsWith('.'), $"{(CheckId)check}'s statement should be a fragment judged, not a full-stop sentence");
        }
    }

    [Fact]
    public void TheInvalidationNoticeNamesTheMoveAndTheRefusal()
    {
        var notice = CheckCopy.Invalidated("trawl", "1.4.2", "1.5.0");
        Assert.Contains("trawl", notice, StringComparison.Ordinal);
        Assert.Contains("1.4.2", notice, StringComparison.Ordinal);
        Assert.Contains("1.5.0", notice, StringComparison.Ordinal);
        Assert.Contains("dropped rather than shown against the new code", notice, StringComparison.Ordinal);
    }

    [Fact]
    public void ButtonsAreVerbFirst()
    {
        // §6: buttons name the action. "Run all", "Run the stale suite", "Run", "Retry" and the
        // notice's "Re-run <name>" all lead with the verb.
        Assert.StartsWith("Run", CheckCopy.RunAllLabel, StringComparison.Ordinal);
        Assert.StartsWith("Run", CheckCopy.RunStaleLabel, StringComparison.Ordinal);
        Assert.StartsWith("Run", CheckCopy.RunOneLabel, StringComparison.Ordinal);
        Assert.StartsWith("Retry", CheckCopy.RetryLabel, StringComparison.Ordinal);
        Assert.StartsWith("Re-run", CheckCopy.RerunLabel("trawl"), StringComparison.Ordinal);
    }

    [Fact]
    public void TheTwoHeadActionsAreDistinctAndTheStaleOneNamesItsScope()
    {
        Assert.NotEqual(CheckCopy.RunAllLabel, CheckCopy.RunStaleLabel);
        Assert.Contains("stale", CheckCopy.RunStaleLabel, StringComparison.Ordinal);
    }
}
