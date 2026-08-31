using MCPRouter.Checks.Model;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// The six checks, against fixture servers, including every load-bearing case the Mac's
/// ServerChecks established: zero calls is never a confirmation, a failed index suspends
/// "declares tools" to not-observed, stdio authorization is not-applicable rather than a pass,
/// and every verdict travels with the statement it judges.
/// </summary>
public sealed class CheckEngineTests
{
    private static ServerRecord Server(Func<ServerRecord, ServerRecord>? mutate = null)
    {
        var server = new ServerRecord
        {
            Name = "obscura",
            Transport = "stdio",
            Hash = "3f9a1c88b2e04d17",
            Tools = 4,
            IndexedAt = "2026-08-30T10:00:00Z",
            Auth = new AuthRecord { Supported = true, Authorized = true },
            Usage = new UsageRecord { Calls = 4, Errors = 0 },
        };
        server = mutate?.Invoke(server) ?? server;
        return server;
    }

    [Fact]
    public void AHealthyIndexedServerConfirmsAllSix()
    {
        var server = Server(static s => s with
        {
            PendingChange = null,
        });

        var results = ServerChecks.All(server);

        Assert.Equal(6, results.Count);
        Assert.All(results, r => Assert.Equal(CheckVerdict.Passed, r.Verdict));
    }

    [Fact]
    public void ZeroCallsIsNotObservedNeverConfirmed()
    {
        // The load-bearing one: a clean record nobody has exercised is not evidence of success.
        var result = ServerChecks.CallsSucceed(Server(static s => s with
        {
            Usage = new UsageRecord { Calls = 0, Errors = 0 },
        }));

        Assert.Equal(CheckVerdict.Unknown, result.Verdict);
        Assert.Equal(CheckCopy.NeverExercised, result.Reason);
    }

    [Fact]
    public void RecordedErrorsAreNotMetWithTheCounts()
    {
        var result = ServerChecks.CallsSucceed(Server(static s => s with
        {
            Usage = new UsageRecord { Calls = 12, Errors = 3 },
        }));

        Assert.Equal(CheckVerdict.Failed, result.Verdict);
        Assert.Equal(CheckCopy.CallsFailed(3, 12), result.Reason);
    }

    [Fact]
    public void AFailingIndexSuspendsDeclaresToolsToNotObserved()
    {
        // Stale last-week's tool count must not read as a present fact.
        var result = ServerChecks.DeclaresTools(Server(static s => s with
        {
            Tools = 4,
            IndexError = "[-32603] Internal error",
        }));

        Assert.Equal(CheckVerdict.Unknown, result.Verdict);
    }

    [Fact]
    public void AFailingIndexIsNotMetForIndexesItself()
    {
        var result = ServerChecks.Indexes(Server(static s => s with
        {
            IndexError = "[-32603] Internal error",
        }));

        Assert.Equal(CheckVerdict.Failed, result.Verdict);
        Assert.Equal(CheckCopy.IndexFailed("[-32603] Internal error"), result.Reason);
    }

    [Fact]
    public void NeverIndexedIsNotObservedNotFailed()
    {
        var results = ServerChecks.All(Server(static s => s with
        {
            IndexedAt = null,
            Tools = 0,
        }));

        Assert.Equal(CheckVerdict.Unknown, results.First(r => r.Check == CheckId.Indexes).Verdict);
        Assert.Equal(CheckVerdict.Unknown, results.First(r => r.Check == CheckId.DeclaresTools).Verdict);
    }

    [Fact]
    public void StdioAuthorizationIsNotApplicable()
    {
        var result = ServerChecks.Authorized(Server(static s => s with
        {
            Auth = new AuthRecord { Supported = false, Authorized = true },
        }));

        Assert.Equal(CheckVerdict.NotApplicable, result.Verdict);
        Assert.Equal(CheckCopy.CredentialsNotApplicable, result.Reason);
    }

    [Fact]
    public void SupportedButUnauthorizedIsNotMet()
    {
        var result = ServerChecks.Authorized(Server(static s => s with
        {
            Auth = new AuthRecord { Supported = true, Authorized = false },
        }));

        Assert.Equal(CheckVerdict.Failed, result.Verdict);
        Assert.Equal(CheckCopy.CredentialsMissing, result.Reason);
    }

    [Fact]
    public void AHeldSurfaceChangeIsNotMetWithTheCount()
    {
        var result = ServerChecks.SurfaceApproved(Server(static s => s with
        {
            PendingChange = new PendingChangeRecord("2026-08-30T09:00:00Z", 2),
        }));

        Assert.Equal(CheckVerdict.Failed, result.Verdict);
        Assert.Equal(CheckCopy.SurfaceHeld(2, "2026-08-30T09:00:00Z"), result.Reason);
    }

    [Fact]
    public void APlacardIsNotMetWithItsReason()
    {
        var result = ServerChecks.Operative(Server(static s => s with
        {
            Placard = new PlacardRecord("upstream is moving hosts", null, null),
        }));

        Assert.Equal(CheckVerdict.Failed, result.Verdict);
        Assert.Equal(CheckCopy.Placarded("upstream is moving hosts"), result.Reason);
    }

    [Fact]
    public void EveryVerdictTravelsWithAStatementAndEveryFailureWithAReason()
    {
        foreach (var result in ServerChecks.All(Server(static s => s with
                     {
                         IndexedAt = null,
                         Auth = new AuthRecord { Supported = false, Authorized = true },
                     })))
        {
            Assert.False(string.IsNullOrWhiteSpace(result.Statement), $"{result.Check} has no statement");
            if (result.Verdict != CheckVerdict.Passed)
            {
                Assert.False(string.IsNullOrWhiteSpace(result.Reason), $"{result.Check} failed without a reason");
            }
        }
    }

    [Fact]
    public void EveryCheckNamesTheInputItWasComputedFrom()
    {
        var server = Server(static s => s with
        {
            PendingChange = new PendingChangeRecord("2026-08-30T09:00:00Z", 1),
            Usage = new UsageRecord { Calls = 5, Errors = 1 },
        });

        foreach (var check in new[]
                 {
                     CheckId.Indexes, CheckId.DeclaresTools, CheckId.Authorized,
                     CheckId.SurfaceApproved, CheckId.Operative, CheckId.CallsSucceed,
                 })
        {
            var input = ServerChecks.Input(check, server);
            Assert.False(string.IsNullOrWhiteSpace(input), $"{check} renders no input");
            Assert.DoesNotContain("not a server check", input, StringComparison.Ordinal);
        }
    }
}
