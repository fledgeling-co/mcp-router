using Xunit;
using MCPRouter.Shell.Model.Diagnostics;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// DEF-085's fix, in the half that needs no display.
///
/// The lane that matters is scripts/windows/win-shell-unhandled-witness.ps1, which runs the real
/// shell and reads the line out of a file another process wrote. These tests do the thing that
/// lane cannot: they pin the marker the lane greps for, and they pin the two behaviours a guarded
/// callback has to have - the exception does not escape, and the failure is reported once - so a
/// change that quietly turned the guard into a swallow would fail here as well as there.
/// </summary>
public class DispatcherGuardTests
{
    [Fact]
    public void GuardedCallbackReportsAndDoesNotThrow()
    {
        var reported = new List<string>();
        var guarded = DispatcherGuard.Guard(
            "TestSite", () => throw new InvalidOperationException("the callback failed"), reported.Add);

        guarded();

        Assert.Single(reported);
        Assert.Contains("unhandled: [dispatcher site=TestSite]", reported[0]);
        Assert.Contains("the callback failed", reported[0]);
        Assert.Contains("System.InvalidOperationException", reported[0]);
    }

    [Fact]
    public void GuardedCallbackReportsNothingWhenTheWorkSucceeds()
    {
        var reported = new List<string>();
        var ran = false;

        DispatcherGuard.Guard("TestSite", () => ran = true, reported.Add)();

        Assert.True(ran);
        Assert.Empty(reported);
    }

    [Fact]
    public async Task GuardedAsyncCallbackReportsAndDoesNotThrow()
    {
        var reported = new List<string>();
        var guarded = DispatcherGuard.GuardAsync(
            "AsyncSite",
            async () =>
            {
                await Task.Yield();
                throw new TimeoutException("the awaited callback failed");
            },
            reported.Add);

        await guarded();

        Assert.Single(reported);
        Assert.Contains("unhandled: [dispatcher site=AsyncSite]", reported[0]);
        Assert.Contains("the awaited callback failed", reported[0]);
    }

    [Fact]
    public void TheMarkerIsTheOneTheWitnessLaneGrepsFor()
    {
        // The lane's EFFECT.dispatcher arm matches `unhandled:\s*\[dispatcher`. If this constant
        // moves, the arm stops matching and would report a working guard as a dead one - which is
        // the inversion DEF-079 is about. Pinned here so the rename is caught in a test rather
        // than by a lane on a machine with a display.
        Assert.Equal("unhandled: [dispatcher", DispatcherGuard.Marker);
        Assert.StartsWith("unhandled: ", DispatcherGuard.Format("S", new Exception("x")));
    }

    [Fact]
    public void ASinkThatThrowsDoesNotReplaceTheFailureItWasHanded()
    {
        var guarded = DispatcherGuard.Guard(
            "TestSite",
            () => throw new InvalidOperationException("the callback failed"),
            _ => throw new IOException("the log is locked"));

        // No exception: a logging fault is not worth the window, and the original is already lost.
        guarded();
    }
}
