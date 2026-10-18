using System;

namespace MCPRouter.Shell.Model.Settings;

/// <summary>
/// The thing "Show status in notification area" actually owns.
///
/// Declared here and implemented in <c>MCPRouter.Shell.Live</c>, for the reason
/// <see cref="ILaunchAtLoginAgent"/> is split the same way: the implementation calls
/// <c>Shell_NotifyIcon</c> and owns a window, and the model must stay runnable in a suite that
/// must not touch the shell's notification area.
/// </summary>
/// <remarks>
/// DEF-101 was this setting with nothing behind it: no <c>NotifyIcon</c>, no
/// <c>Shell_NotifyIcon</c> and no tray host anywhere in the build, so the switch moved a boolean
/// and the notification area never heard about it. The interface exists so that the board depends
/// on something that can be absent - a board built without a host says so rather than pretending -
/// and so that what proves the setting is a reader OUTSIDE this process: the shell's own
/// notification area, asked for the icon's rectangle by a different program.
/// </remarks>
public interface INotificationAreaAgent
{
    /// <summary>Whether this build can place an icon at all, and why not when it cannot.</summary>
    string? UnavailableReason { get; }

    /// <summary>
    /// Whether an icon is in the notification area right now, or null when that cannot be read.
    /// </summary>
    /// <remarks>
    /// Null is distinct from false, exactly as it is on <see cref="ILaunchAtLoginAgent"/>: "the
    /// shell could not be asked" and "the shell says no icon" are different facts and a board
    /// that merged them would show a switch over a state nothing holds.
    /// </remarks>
    bool? CurrentlyShown();

    /// <summary>Place the icon when true, remove it when false.</summary>
    ToggleEffectResult Apply(bool shown);
}
