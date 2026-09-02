using System;

namespace MCPRouter.Shell.Model.Settings;

/// <summary>What happened when a toggle was asked to reach the machine.</summary>
public enum ToggleEffectOutcome
{
    /// <summary>The machine now holds what the switch says.</summary>
    Applied,

    /// <summary>Nothing on this build owns this setting, so nothing was attempted.</summary>
    Unavailable,

    /// <summary>Something owns it, it was attempted, and it did not take.</summary>
    Failed
}

/// <summary>The result of asking a setting to reach outside the process.</summary>
/// <remarks>
/// <see cref="Detail"/> is shown to the operator rather than logged, because the failure this
/// whole item is about is a switch that reports success it did not have. A switch that says why
/// it could not act is honest; one that moves silently is the defect.
/// </remarks>
public sealed record ToggleEffectResult(ToggleEffectOutcome Outcome, string Detail)
{
    public bool Applied => Outcome == ToggleEffectOutcome.Applied;

    public static ToggleEffectResult Unavailable(string detail) =>
        new(ToggleEffectOutcome.Unavailable, detail);
}

/// <summary>
/// The thing "Launch router daemon at sign-in" actually owns.
///
/// Declared in the model project and implemented in <c>MCPRouter.Shell.Live</c>, because the
/// implementation drives <c>schtasks.exe</c> and the model must stay runnable in a suite that
/// must not mutate the machine. The interface is what the board depends on; a test hands it a
/// fake and reads the argv, and the out-of-process lane reads the Windows task scheduler.
/// </summary>
public interface ILaunchAtLoginAgent
{
    /// <summary>Whether this build can register anything at all, and why not when it cannot.</summary>
    /// <remarks>
    /// Null when the setting is available. A non-null sentence is shown beside the switch and the
    /// switch is disabled: DEF-087's rule is that a control which cannot act says so rather than
    /// moving a boolean.
    /// </remarks>
    string? UnavailableReason { get; }

    /// <summary>What the MACHINE holds right now, or null when that cannot be read.</summary>
    /// <remarks>
    /// The board seeds the switch from this rather than from the stored boolean, so the switch
    /// shows the scheduler's answer and not the app's memory of what it once asked for. Null is
    /// distinct from false on purpose - "the scheduler could not be asked" and "the scheduler says
    /// no" are different facts and the caller must not merge them.
    /// </remarks>
    bool? CurrentlyRegistered();

    /// <summary>Register when true, unregister when false.</summary>
    ToggleEffectResult Apply(bool enabled);
}
