using System;
using System.Threading;
using System.Threading.Tasks;
using MCPRouter.Shell.Model.Servers;

namespace MCPRouter.Shell.Model.Pairing;

/// <summary>
/// The Windows pairing sheet's state: the code on screen, its window, and what this build can offer.
///
/// <para>Mirrors the Mac's <c>PairingSessionModel</c> (B3). The code is the router's: the sheet asks
/// for one on open and on reissue, and takes it back on close, so the router's pairing state is the
/// one record of what can be paired with. This model draws the code and keeps the clock; it does not
/// decide whether a code is live.</para>
/// </summary>
public sealed class PairingSessionModel
{
    private readonly ControlApiClient _client;
    private readonly bool _pairingAvailable;
    private readonly Func<DateTimeOffset> _clock;

    /// <summary>
    /// Bumped by every open, reissue and close. A router answer carries the generation it was asked
    /// under, and an answer whose generation has been overtaken is not shown. The router keeps one
    /// live code, so an answer that lost to a newer request names a code the router has replaced.
    /// </summary>
    private int _generation;

    /// <summary>The code the router minted and that is still inside its window. Null when none is on screen.</summary>
    private IssuedPairingCode? _live;

    public PairingSessionState CurrentState { get; private set; } = Closed();

    public bool IsOpen { get; private set; }

    /// <summary>Raised on every change, including each countdown tick, on the context the change happened on.</summary>
    public event EventHandler? StateChanged;

    /// <param name="client">The router boundary. Every call here goes through it.</param>
    /// <param name="pairingAvailable">
    /// False when this build has no way to pair. No request is made and the state says why, which is
    /// the Mac's no-endpoint rule: a code is only ever asked for when there is somewhere for a phone to pair with.
    /// </param>
    /// <param name="clock">The clock the countdown reads. Injected so expiry is driven, not waited for.</param>
    public PairingSessionModel(ControlApiClient client, bool pairingAvailable = true, Func<DateTimeOffset>? clock = null)
    {
        _client = client;
        _pairingAvailable = pairingAvailable;
        _clock = clock ?? (() => DateTimeOffset.UtcNow);
    }

    // ------------------------------------------------------------------ the sheet's lifetime

    /// <summary>Open the sheet and ask the router for a code.</summary>
    public Task OpenAsync(CancellationToken cancellation = default)
    {
        IsOpen = true;
        return RequestCodeAsync(cancellation);
    }

    /// <summary>Mint a fresh code, which is what the expired and refused states offer.</summary>
    public Task ReissueAsync(CancellationToken cancellation = default) => RequestCodeAsync(cancellation);

    /// <summary>
    /// Close the sheet and take the router's code back. A code left live on the router is pairable by
    /// a phone for as long as its window runs with nobody looking at it, so the revoke is sent here
    /// rather than left to expiry. An answer still in flight is handled where it arrives.
    /// </summary>
    public async Task CloseAsync(CancellationToken cancellation = default)
    {
        IsOpen = false;
        _generation++;
        var holdsCode = CurrentState.Phase is PairingPhase.Preparing or PairingPhase.AwaitingScanOrCode;
        _live = null;
        SetState(Closed());
        if (holdsCode) await RevokeQuietlyAsync(cancellation);
    }

    /// <summary>
    /// Advance the clock and expire the code if its window has closed. Driven by the view's one-second
    /// timer; kept callable so a test can move the clock without waiting five minutes.
    /// </summary>
    public void Tick()
    {
        if (CurrentState.Phase != PairingPhase.AwaitingScanOrCode || _live is null) return;

        var now = _clock();
        if (now >= _live.ExpiresAt)
        {
            _live = null;
            SetState(new PairingSessionState(PairingPhase.Expired, null, TimeSpan.Zero));
            return;
        }
        SetState(Awaiting(_live, _live.ExpiresAt - now));
    }

    // ------------------------------------------------------------------ asking the router

    private async Task RequestCodeAsync(CancellationToken cancellation)
    {
        _live = null;
        if (!_pairingAvailable)
        {
            SetState(Unavailable(failure: null));
            return;
        }

        var generation = ++_generation;
        SetState(new PairingSessionState(PairingPhase.Preparing, null, TimeSpan.Zero));

        // The router says whether its phone listener is bound before anything is minted. A code minted while
        // none is names a port nothing answers on, so the sheet asks first and shows pairing as off when it is.
        PairingState state;
        try
        {
            state = await _client.GetPairingStateAsync(cancellation);
        }
        catch (ControlApiException failure)
        {
            if (generation == _generation) SetState(Unavailable(failure));
            return;
        }

        if (generation != _generation) return;
        if (!state.Listener.Enabled)
        {
            SetState(Unavailable(failure: null));
            return;
        }

        IssuedPairingCode issued;
        try
        {
            issued = await _client.IssuePairingCodeAsync(cancellation);
        }
        catch (ControlApiException failure)
        {
            if (generation == _generation) SetState(Unavailable(failure));
            return;
        }

        if (generation != _generation)
        {
            // The sheet moved on while the router was minting. A code minted after the sheet closed has
            // no other owner, so this answer is the only thing that can take it back.
            if (!IsOpen) await RevokeQuietlyAsync(cancellation);
            return;
        }

        var now = _clock();
        if (now >= issued.ExpiresAt)
        {
            SetState(new PairingSessionState(PairingPhase.Expired, null, TimeSpan.Zero));
            return;
        }
        _live = issued;
        SetState(Awaiting(issued, issued.ExpiresAt - now));
    }

    private async Task RevokeQuietlyAsync(CancellationToken cancellation)
    {
        try
        {
            await _client.RevokePairingCodeAsync(cancellation);
        }
        catch (ControlApiException)
        {
            // A revoke that does not reach the router leaves a code the router's own five-minute
            // window still bounds, so nothing here retries it.
        }
    }

    // ------------------------------------------------------------------ states

    private static PairingSessionState Closed() => new(PairingPhase.Idle, null, TimeSpan.Zero);

    /// <summary>Unavailable with no failure means this build or the router has pairing off. A failure
    /// means the router refused or could not be reached, and carries its own wording.</summary>
    private static PairingSessionState Unavailable(ControlApiException? failure) =>
        new(PairingPhase.Unavailable, null, TimeSpan.Zero, Failure: failure);

    private static PairingSessionState Awaiting(IssuedPairingCode issued, TimeSpan remaining) =>
        new(PairingPhase.AwaitingScanOrCode, issued.Code, remaining);

    private void SetState(PairingSessionState state)
    {
        CurrentState = state;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    // ------------------------------------------------------------------ pairing outcomes

    public void CompletePairing(string deviceName)
    {
        CurrentState = new PairingSessionState(
            PairingPhase.Paired,
            CurrentState.PairingCode,
            CurrentState.RemainingTime,
            deviceName,
            null
        );
    }

    public void FailPairing(PairingRefusalReason reason)
    {
        CurrentState = new PairingSessionState(
            PairingPhase.Failed,
            CurrentState.PairingCode,
            CurrentState.RemainingTime,
            null,
            reason
        );
    }
}
