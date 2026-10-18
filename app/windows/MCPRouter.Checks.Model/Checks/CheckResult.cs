namespace MCPRouter.Checks.Model;

/// <summary>
/// One check's outcome: the verdict, the reason for anything that is not a confirmation, and the
/// statement the verdict judges.
///
/// A verdict never appears without the statement it judges — the statement travels on the result
/// itself, so no call site that has the one can render it without the other.
/// <paramref name="Reason"/> is present for everything that is not <see cref="CheckVerdict.Passed"/>,
/// and it names the observation that produced the verdict rather than restating the verdict as an
/// adjective: "never exercised" is a reason; "failed" is not.
/// </summary>
public sealed record CheckResult(CheckId Check, CheckVerdict Verdict, string? Reason)
{
    /// <summary>The statement this result judges, from <see cref="CheckCopy"/>.</summary>
    public string Statement => CheckCopy.Statement(Check);

    /// <summary>The word this verdict is shown as.</summary>
    public string VerdictWord => CheckVerdictWords.For(Verdict);

    /// <summary>Whether this verdict is one a human should look at.</summary>
    public bool WantsAttention => Verdict == CheckVerdict.Failed;
}
