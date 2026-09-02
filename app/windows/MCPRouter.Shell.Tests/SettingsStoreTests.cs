using System;
using System.IO;
using System.Text.Json;
using MCPRouter.Shell.Model.Settings;
using Xunit;

namespace MCPRouter.Shell.Tests;

/// <summary>
/// DEF-087, at the rung a unit suite can reach: that the board's state is written to a file and
/// read back, and that a toggle asks whatever owns it before it moves.
/// </summary>
/// <remarks>
/// WHAT THIS SUITE CANNOT ESTABLISH, stated here rather than left to be inferred from a green: it
/// writes a temp directory and drives a fake agent, so it says nothing about the Windows task
/// scheduler and nothing about the shell surviving a restart. Both are measured out of process by
/// <c>scripts/windows/uia/shell-lane.ps1</c>, whose recorders are Get-ScheduledTask and a read of
/// the settings file by the harness rather than by the app.
/// </remarks>
public sealed class SettingsStoreTests : IDisposable
{
    private readonly string _directory;

    public SettingsStoreTests()
    {
        _directory = Path.Combine(Path.GetTempPath(), "mcprouter-settings-" + Guid.NewGuid().ToString("N"));
    }

    public void Dispose()
    {
        try
        {
            if (Directory.Exists(_directory))
            {
                Directory.Delete(_directory, recursive: true);
            }
        }
        catch (IOException)
        {
        }
    }

    [Fact]
    public void Save_ThenLoad_ReturnsTheToggles()
    {
        var store = new SettingsStore(_directory);
        var written = store.Save(new RouterSettingsState(
            LaunchAtLogin: false, ShowAmbientIcon: false, RequireConfirmationOnDestructive: true));

        Assert.True(written);
        Assert.True(File.Exists(store.FilePath));

        var read = new SettingsStore(_directory).Load(new RouterSettingsState());
        Assert.False(read.LaunchAtLogin);
        Assert.False(read.ShowAmbientIcon);
        Assert.True(read.RequireConfirmationOnDestructive);
    }

    [Fact]
    public void Load_WithNoFile_ReturnsTheSeedUntouched()
    {
        var seed = new RouterSettingsState(LaunchAtLogin: false);
        var read = new SettingsStore(_directory).Load(seed);
        Assert.Equal(seed, read);
    }

    [Fact]
    public void Load_WithAMissingKey_LeavesThatSettingAlone()
    {
        // A store written by an older build carries fewer keys. Reading absence as `false` is how
        // a setting silently flips itself off on upgrade, so the seed's value has to survive.
        Directory.CreateDirectory(_directory);
        File.WriteAllText(
            Path.Combine(_directory, SettingsStore.FileName),
            "{\"schema\":\"" + SettingsStore.Schema + "\",\"LaunchAtLogin\":false}");

        var read = new SettingsStore(_directory).Load(new RouterSettingsState());
        Assert.False(read.LaunchAtLogin);
        Assert.True(read.ShowAmbientIcon);
        Assert.True(read.RequireConfirmationOnDestructive);
    }

    [Fact]
    public void Load_OverUnreadableJson_ReportsTheErrorRatherThanClaimingDefaults()
    {
        Directory.CreateDirectory(_directory);
        File.WriteAllText(Path.Combine(_directory, SettingsStore.FileName), "{ not json");

        var store = new SettingsStore(_directory);
        var read = store.Load(new RouterSettingsState(LaunchAtLogin: false));

        Assert.False(read.LaunchAtLogin);
        Assert.NotNull(store.LastError);
    }

    [Fact]
    public void Save_WritesEveryDeclaredToggleKey()
    {
        var store = new SettingsStore(_directory);
        store.Save(new RouterSettingsState());

        using var document = JsonDocument.Parse(File.ReadAllText(store.FilePath));
        foreach (var key in SettingsPresentation.ToggleKeys)
        {
            Assert.True(document.RootElement.TryGetProperty(key, out _),
                "the store dropped the declared toggle key " + key);
        }
    }

    [Fact]
    public void DefaultDirectory_HonoursTheHarnessOverride()
    {
        // The override is why the lane can measure persistence without writing over the settings
        // of the person running it.
        var previous = Environment.GetEnvironmentVariable(SettingsStore.DirectoryVariable);
        try
        {
            Environment.SetEnvironmentVariable(SettingsStore.DirectoryVariable, _directory);
            Assert.Equal(_directory, SettingsStore.DefaultDirectory());
        }
        finally
        {
            Environment.SetEnvironmentVariable(SettingsStore.DirectoryVariable, previous);
        }
    }
}

/// <summary>An agent that records what it was asked to do and answers what it was told to.</summary>
internal sealed class FakeLaunchAtLoginAgent : ILaunchAtLoginAgent
{
    private readonly bool? _registered;
    private readonly ToggleEffectResult _result;

    public FakeLaunchAtLoginAgent(
        bool? registered = false,
        ToggleEffectResult? result = null,
        string? unavailableReason = null)
    {
        _registered = registered;
        _result = result ?? new ToggleEffectResult(ToggleEffectOutcome.Applied, "fake");
        UnavailableReason = unavailableReason;
    }

    public string? UnavailableReason { get; }

    public int Applications { get; private set; }

    public bool? LastRequest { get; private set; }

    public bool? CurrentlyRegistered() => _registered;

    public ToggleEffectResult Apply(bool enabled)
    {
        Applications++;
        LastRequest = enabled;
        return _result;
    }
}

public sealed class SettingsBoardModelEffectTests : IDisposable
{
    private readonly string _directory =
        Path.Combine(Path.GetTempPath(), "mcprouter-settings-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        try
        {
            if (Directory.Exists(_directory))
            {
                Directory.Delete(_directory, recursive: true);
            }
        }
        catch (IOException)
        {
        }
    }

    [Fact]
    public void LaunchAtLogin_IsSeededFromTheMachineAndNotFromTheStore()
    {
        new SettingsStore(_directory).Save(new RouterSettingsState(LaunchAtLogin: true));

        var model = new SettingsBoardModel(
            new SettingsStore(_directory), new FakeLaunchAtLoginAgent(registered: false));

        Assert.False(model.CurrentState.LaunchAtLogin);
        Assert.Equal("the Windows task scheduler", model.LaunchAtLoginSource);
    }

    [Fact]
    public void UpdateToggle_AsksTheAgentBeforeItMovesTheState()
    {
        var agent = new FakeLaunchAtLoginAgent(registered: false);
        var model = new SettingsBoardModel(new SettingsStore(_directory), agent);

        model.UpdateToggle("LaunchAtLogin", true);

        Assert.Equal(1, agent.Applications);
        Assert.True(agent.LastRequest);
        Assert.True(model.CurrentState.LaunchAtLogin);
    }

    [Fact]
    public void UpdateToggle_LeavesTheStateAloneWhenTheMachineRefuses()
    {
        // The failure this guards is a switch reporting a state nothing holds. A refused
        // registration must leave the model - and therefore the switch and the readout - saying
        // what the machine actually says.
        var agent = new FakeLaunchAtLoginAgent(
            registered: false,
            result: new ToggleEffectResult(ToggleEffectOutcome.Failed, "the scheduler refused"));
        var model = new SettingsBoardModel(new SettingsStore(_directory), agent);

        model.UpdateToggle("LaunchAtLogin", true);

        Assert.False(model.CurrentState.LaunchAtLogin);
        Assert.NotNull(model.LastEffect);
        Assert.Equal(ToggleEffectOutcome.Failed, model.LastEffect!.Outcome);
    }

    [Fact]
    public void UpdateToggle_WritesThroughToTheStore()
    {
        var model = new SettingsBoardModel(new SettingsStore(_directory));
        model.UpdateToggle("ShowAmbientIcon", false);

        Assert.True(model.LastSaveSucceeded);
        Assert.False(new SettingsStore(_directory).Load(new RouterSettingsState()).ShowAmbientIcon);
    }

    [Fact]
    public void ParameterlessModel_TouchesNothingOnDisk()
    {
        // The seam the rest of the suite depends on: a model built with no store reads no file, so
        // a unit run is never a measurement of the machine it happens to be on.
        var model = new SettingsBoardModel();
        Assert.Null(model.StorePath);
        model.UpdateToggle("LaunchAtLogin", false);
        Assert.False(model.LastSaveSucceeded);
    }
}

public sealed class SettingsUnavailabilityTests
{
    /// <summary>
    /// The two switches this build cannot honour say so, and the sentence names the defect that
    /// carries what they need. DEF-087's rule: a switch that moves and reaches nothing is the
    /// defect; a switch that states it cannot act is honest.
    /// </summary>
    [Theory]
    [InlineData("ShowAmbientIcon", "DEF-101")]
    [InlineData("RequireConfirmationOnDestructive", "DEF-102")]
    public void UnownedToggles_CarryAReasonNamingTheirDefect(string key, string defect)
    {
        var reason = SettingsPresentation.ToggleUnavailableReason(key);
        Assert.NotNull(reason);
        Assert.StartsWith("Unavailable:", reason);
        Assert.Contains(defect, reason);
    }

    [Fact]
    public void LaunchAtLogin_IsNotDeclaredUnavailable_BecauseItOwnsTheLogonTask()
    {
        Assert.Null(SettingsPresentation.ToggleUnavailableReason("LaunchAtLogin"));
        Assert.Contains("LaunchAtLogin", SettingsPresentation.ActuableToggleKeys);
    }

    [Fact]
    public void EveryDeclaredKeyRoundTripsThroughWithToggle()
    {
        foreach (var key in SettingsPresentation.ToggleKeys)
        {
            var off = SettingsPresentation.WithToggle(new RouterSettingsState(), key, false);
            Assert.False(SettingsPresentation.ToggleValue(off, key));
            var on = SettingsPresentation.WithToggle(off, key, true);
            Assert.True(SettingsPresentation.ToggleValue(on, key));
        }
    }
}
