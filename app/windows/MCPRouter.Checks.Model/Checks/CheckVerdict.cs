namespace MCPRouter.Checks.Model;

/// <summary>
/// What one check concluded.
///
/// Ported from the Mac's <c>CheckVerdict</c> (app/Sources/MCPRouterKit/Checks/CheckModels.swift),
/// including the raw-value decision: these strings are what the history file on disk carries, so
/// they are the observation vocabulary rather than the engineering case names — a persisted
/// "verdict":"passed" would put a grading noun into the one artifact a curious user is most
/// likely to open when they want to know what actually ran.
///
/// Four cases rather than a bool. <see cref="NotObserved"/> means the router has not observed
/// enough to answer — a different sentence from "no", and rendering it as a failure would blame a
/// capability for the router's own silence. <see cref="NotApplicable"/> means the question does
/// not arise for this subject at all.
/// </summary>
public enum CheckVerdict
{
    Passed = 0,
    Failed = 1,
    Unknown = 2,
    NotApplicable = 3,
}

/// <summary>The word a verdict is shown as, and the word the history file stores.</summary>
public static class CheckVerdictWords
{
    public static string For(CheckVerdict verdict) => verdict switch
    {
        // Observation vocabulary, not grading vocabulary — the item's single most load-bearing
        // copy decision (CheckCopy.swift's tallyNoun). "passed"/"failed" are the words of a test
        // suite; using them would make a re-tabulation of data the router already served read as
        // a grade however carefully the subtitle is worded.
        CheckVerdict.Passed => "confirmed",
        CheckVerdict.Failed => "not met",
        CheckVerdict.Unknown => "not observed",
        CheckVerdict.NotApplicable => "not applicable",
        _ => throw new ArgumentOutOfRangeException(nameof(verdict), verdict, "no word for this verdict"),
    };

    /// <summary>The disk spelling, matching the Mac's raw values so the history file shape is
    /// shared between platforms. "passed" on disk would put the grading noun into the one
    /// artifact a curious user is most likely to open.</summary>
    public static string Disk(CheckVerdict verdict) => verdict switch
    {
        CheckVerdict.Passed => "confirmed",
        CheckVerdict.Failed => "notMet",
        CheckVerdict.Unknown => "notObserved",
        CheckVerdict.NotApplicable => "notApplicable",
        _ => throw new ArgumentOutOfRangeException(nameof(verdict), verdict, "no disk spelling for this verdict"),
    };
}
