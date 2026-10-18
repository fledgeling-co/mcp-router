using System;
using System.Collections.Generic;

namespace MCPRouter.Shell.Model.Settings;

/// <summary>
/// The Settings board's state, and - since DEF-087 - the two things it is answerable to outside
/// the process: a durable store, and an agent that carries one setting to the machine.
/// </summary>
/// <remarks>
/// The parameterless constructor is deliberately inert: no store, no agent, nothing on disk. A
/// model that read <c>%APPDATA%</c> the moment it was constructed would make every unit test a
/// measurement of the machine it happened to run on, and the suite would pass or fail on whether
/// somebody had used the app.
/// </remarks>
public sealed class SettingsBoardModel
{
    private readonly SettingsStore? _store;
    private readonly ILaunchAtLoginAgent? _launchAgent;
    private readonly INotificationAreaAgent? _iconAgent;

    public SettingsBoardModel()
    {
    }

    public SettingsBoardModel(
        SettingsStore? store,
        ILaunchAtLoginAgent? launchAgent = null,
        INotificationAreaAgent? iconAgent = null)
    {
        _store = store;
        _launchAgent = launchAgent;
        _iconAgent = iconAgent;

        if (_store is not null)
        {
            CurrentState = _store.Load(CurrentState);
            if (_store.LastError is not null)
            {
                LastEffect = new ToggleEffectResult(
                    ToggleEffectOutcome.Failed,
                    "the stored settings could not be read: " + _store.LastError);
            }
        }

        // The SCHEDULER, not the stored boolean. What a user wants to know when they open this
        // board is whether the machine will start the daemon, and the only thing that can answer
        // that is the machine. A stored `true` written before somebody deleted the task by hand
        // would otherwise render as a switch that is on over a task that does not exist.
        var registered = _launchAgent?.CurrentlyRegistered();
        if (registered.HasValue)
        {
            CurrentState = CurrentState with { LaunchAtLogin = registered.Value };
            LaunchAtLoginSource = "the Windows task scheduler";
        }
        else if (_launchAgent is not null)
        {
            LaunchAtLoginSource = "the stored settings - the task scheduler could not be read";
        }

        // The NOTIFICATION AREA, not the stored boolean, and for the same reason: DEF-101's fix
        // is only worth anything if the switch shows what the shell holds. An icon Explorer
        // dropped, or one a previous run left behind, is a fact about the machine and the board
        // reports it rather than its own memory.
        var placed = _iconAgent?.CurrentlyShown();
        if (placed.HasValue)
        {
            CurrentState = CurrentState with { ShowAmbientIcon = placed.Value };
            AmbientIconSource = "the Windows notification area";
        }
        else if (_iconAgent is not null)
        {
            AmbientIconSource = "the stored settings - the notification area could not be read";
        }
    }

    public SettingsSection ActiveSection { get; set; } = SettingsSection.Router;

    public RouterSettingsState CurrentState { get; set; } = new();

    /// <summary>Where the launch-at-sign-in switch's displayed value came from.</summary>
    public string LaunchAtLoginSource { get; private set; } = "this session only - no agent";

    /// <summary>Where the notification-area switch's displayed value came from.</summary>
    public string AmbientIconSource { get; private set; } = "this session only - no host";

    /// <summary>The outcome of the last toggle that tried to reach outside the process.</summary>
    public ToggleEffectResult? LastEffect { get; private set; }

    /// <summary>Whether the state has been written to a durable store at least once this session.</summary>
    public bool LastSaveSucceeded { get; private set; }

    public string? StorePath => _store?.FilePath;

    /// <summary>Why a key cannot act on this build, or null when it can.</summary>
    public string? UnavailableReason(string key)
    {
        if (key == "LaunchAtLogin")
        {
            return _launchAgent is null
                ? SettingsPresentation.NoLaunchAgentReason
                : _launchAgent.UnavailableReason;
        }
        if (key == "ShowAmbientIcon")
        {
            return _iconAgent is null
                ? SettingsPresentation.NoNotificationHostReason
                : _iconAgent.UnavailableReason;
        }
        return SettingsPresentation.ToggleUnavailableReason(key);
    }

    /// <summary>
    /// Move a setting, carry it to whatever owns it, and write it down.
    /// </summary>
    /// <remarks>
    /// ORDER IS THE POINT. The machine is asked first and the in-memory state follows only what
    /// the machine accepted, so a registration the scheduler refuses leaves the switch reporting
    /// the truth rather than the request. DEF-087 was the opposite arrangement carried to its
    /// conclusion: the boolean moved and nothing else was ever asked.
    /// </remarks>
    public void UpdateToggle(string key, bool value)
    {
        if (key == "LaunchAtLogin" && _launchAgent is not null)
        {
            var result = _launchAgent.Apply(value);
            LastEffect = result;
            if (!result.Applied)
            {
                return;
            }
        }

        if (key == "ShowAmbientIcon" && _iconAgent is not null)
        {
            var result = _iconAgent.Apply(value);
            LastEffect = result;
            if (!result.Applied)
            {
                return;
            }
        }

        CurrentState = SettingsPresentation.WithToggle(CurrentState, key, value);

        if (_store is not null)
        {
            LastSaveSucceeded = _store.Save(CurrentState);
            if (!LastSaveSucceeded && _store.LastError is not null)
            {
                LastEffect = new ToggleEffectResult(
                    ToggleEffectOutcome.Failed,
                    "the setting could not be written to " + _store.FilePath + ": " + _store.LastError);
            }
        }
    }
}
