namespace MCPRouter.Checks.Model;

/// <summary>
/// The six checks MCP Router can genuinely perform against a declared server.
///
/// Ported from the Mac's <c>ServerChecks</c>. Every one is a pure function of a field the control
/// API already serves — nothing here calls a tool, sends a fixture or grades a reply, because no
/// runner in this product can. That is the whole honesty position of this surface, and it is
/// enforced by the signatures: a function with only a <see cref="ServerRecord"/> to read cannot
/// invent an observation.
///
/// <see cref="CheckVerdict.Unknown"/> is a first-class answer and three of these return it. The
/// defect this file exists to avoid is reporting a confirmation for a question nobody asked — a
/// check that says "yes" because its input was never gathered is the same failure as a fabricated
/// number, and it is the more dangerous of the two because it looks like evidence.
/// </summary>
public static class ServerChecks
{
    /// <summary>The six, in the order the detail renders them.</summary>
    public static IReadOnlyList<CheckResult> All(ServerRecord server) =>
    [
        Indexes(server),
        DeclaresTools(server),
        Authorized(server),
        SurfaceApproved(server),
        Operative(server),
        CallsSucceed(server),
    ];

    /// <summary>The router can start it and read its tool surface.</summary>
    public static CheckResult Indexes(ServerRecord server)
    {
        if (!string.IsNullOrEmpty(server.IndexError))
        {
            return new CheckResult(CheckId.Indexes, CheckVerdict.Failed, CheckCopy.IndexFailed(server.IndexError));
        }

        if (server.IndexedAt is null)
        {
            return new CheckResult(CheckId.Indexes, CheckVerdict.Unknown, CheckCopy.NeverIndexed);
        }

        return new CheckResult(CheckId.Indexes, CheckVerdict.Passed, null);
    }

    /// <summary>It offers at least one tool.
    ///
    /// Not observed whenever the index is failing, whatever <c>tools</c> holds. A server that
    /// indexed cleanly last week and now fails still carries last week's count, and reporting a
    /// confirmation from it would be asserting a present fact from a stale reading.</summary>
    public static CheckResult DeclaresTools(ServerRecord server)
    {
        if (!string.IsNullOrEmpty(server.IndexError) || server.IndexedAt is null)
        {
            return new CheckResult(CheckId.DeclaresTools, CheckVerdict.Unknown, CheckCopy.ToolsUnknownUntilIndexed);
        }

        if (server.Tools <= 0)
        {
            return new CheckResult(CheckId.DeclaresTools, CheckVerdict.Failed, CheckCopy.NoToolsDeclared);
        }

        return new CheckResult(CheckId.DeclaresTools, CheckVerdict.Passed, null);
    }

    /// <summary>Its credentials are current.
    ///
    /// Not applicable rather than a pass when the transport carries no credentials: "there are
    /// none to be current" and "the ones it has are current" are different statements, and only
    /// one of them is true of a stdio server.</summary>
    public static CheckResult Authorized(ServerRecord server)
    {
        if (!server.Auth.Supported)
        {
            return new CheckResult(CheckId.Authorized, CheckVerdict.NotApplicable, CheckCopy.CredentialsNotApplicable);
        }

        if (!server.Auth.Authorized)
        {
            return new CheckResult(CheckId.Authorized, CheckVerdict.Failed, CheckCopy.CredentialsMissing);
        }

        return new CheckResult(CheckId.Authorized, CheckVerdict.Passed, null);
    }

    /// <summary>No tool description is waiting for review.</summary>
    public static CheckResult SurfaceApproved(ServerRecord server)
    {
        if (server.PendingChange is not { } pending)
        {
            return new CheckResult(CheckId.SurfaceApproved, CheckVerdict.Passed, null);
        }

        return new CheckResult(
            CheckId.SurfaceApproved,
            CheckVerdict.Failed,
            CheckCopy.SurfaceHeld(pending.Count, pending.SeenAt));
    }

    /// <summary>It carries no placard.</summary>
    public static CheckResult Operative(ServerRecord server)
    {
        if (server.Placard is not { } placard)
        {
            return new CheckResult(CheckId.Operative, CheckVerdict.Passed, null);
        }

        return new CheckResult(CheckId.Operative, CheckVerdict.Failed, CheckCopy.Placarded(placard.Reason));
    }

    /// <summary>Its calls come back without error.
    ///
    /// The load-bearing one. Zero calls with zero errors is arithmetically a clean record and is
    /// NOT a confirmation — nobody has ever exercised this server, so whether its calls succeed is
    /// unobserved. Reporting success for something nobody has done is the same defect as a
    /// fabricated number.
    ///
    /// Reads <c>usage.calls</c>, the recorded window that <c>POST /usage/reset</c> clears and
    /// that every sentence on this board is scoped to — never the process-lifetime tally. A server
    /// whose history was reset must read as never exercised, because over the window being
    /// described it is.</summary>
    public static CheckResult CallsSucceed(ServerRecord server)
    {
        if (server.Usage.Calls <= 0)
        {
            return new CheckResult(CheckId.CallsSucceed, CheckVerdict.Unknown, CheckCopy.NeverExercised);
        }

        if (server.Usage.Errors <= 0)
        {
            return new CheckResult(CheckId.CallsSucceed, CheckVerdict.Passed, null);
        }

        return new CheckResult(
            CheckId.CallsSucceed,
            CheckVerdict.Failed,
            CheckCopy.CallsFailed(server.Usage.Errors, server.Usage.Calls));
    }

    /// <summary>
    /// The field and value each check was computed from.
    ///
    /// The footer promises a check is "something MCP Router performed and can show you the input
    /// to". That promise is only verifiable by the reader if the input is on screen, and without
    /// it a derived row is indistinguishable from a grade — which is the single strongest objection
    /// this surface faces. So the input is rendered — the exchange that failed, not a count — and
    /// this is where it comes from.
    /// </summary>
    public static string Input(CheckId check, ServerRecord server) => check switch
    {
        CheckId.Indexes => $"indexedAt = {server.IndexedAt ?? "nil"} · indexError = {server.IndexError ?? "nil"}",
        CheckId.DeclaresTools => $"tools = {server.Tools} · indexError = {server.IndexError ?? "nil"}",
        CheckId.Authorized => $"auth.supported = {server.Auth.Supported.ToString().ToLowerInvariant()} · auth.authorized = {server.Auth.Authorized.ToString().ToLowerInvariant()}",
        CheckId.SurfaceApproved => server.PendingChange is { } pending
            ? $"pendingChange = {pending.Count} held"
            : "pendingChange = nil",
        CheckId.Operative => $"placard = {server.Placard?.Reason ?? "nil"}",
        CheckId.CallsSucceed => $"usage.calls = {server.Usage.Calls} · usage.errors = {server.Usage.Errors}",
        _ => throw new ArgumentOutOfRangeException(nameof(check), check, "not a server check"),
    };
}
