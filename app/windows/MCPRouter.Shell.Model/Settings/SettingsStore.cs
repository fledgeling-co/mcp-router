using System;
using System.IO;
using System.Text.Json;

namespace MCPRouter.Shell.Model.Settings;

/// <summary>
/// Where the Windows shell's three settings live between launches.
///
/// DEF-087: <see cref="SettingsBoardModel"/> held them in memory and nothing else, so closing the
/// shell forgot every change a user made. A toggle that moves, updates a readout and survives
/// nothing is the inert-UI failure one layer past DEF-076's - the census can watch the model move
/// and has no way to see that the move was never written down.
///
/// The shape follows <c>MCPRouter.Checks.Model.CheckHistoryStore</c> rather than inventing a new
/// one: a JSON document under <c>%APPDATA%\MCPRouter</c>, the directory this app already keeps its
/// state in. Only the three toggles are written. The other fields of
/// <see cref="RouterSettingsState"/> - the endpoint, the router home, the idle reaper - are the
/// ROUTER's facts, read from the router's own configuration, and a copy of them here would be a
/// second source of truth that goes stale the first time the router is reconfigured.
/// </summary>
public sealed class SettingsStore
{
    public const string FileName = "shell-settings.json";
    public const string Schema = "mcprouter.shell-settings/1";

    /// <summary>
    /// The environment override, and it exists so a harness never writes over the operator's own
    /// file. <c>scripts/windows/uia/shell-lane.ps1</c> sets it before it launches the shell, the
    /// same way the WIN23 witness registers under a task name of its own: a lane that measured
    /// persistence by overwriting the settings of the person running it would break the thing it
    /// measures.
    /// </summary>
    public const string DirectoryVariable = "MCPROUTER_SHELL_STATE_DIR";

    private readonly string _filePath;

    /// <summary>Why the last read or write failed, when it did. Kept rather than swallowed: the
    /// board must be able to say "this could not be saved" rather than quietly showing a value
    /// that reached no disk.</summary>
    public string? LastError { get; private set; }

    public SettingsStore(string? directory = null)
    {
        var dir = string.IsNullOrWhiteSpace(directory) ? DefaultDirectory() : directory!;
        _filePath = Path.Combine(dir, FileName);
    }

    public string FilePath => _filePath;

    public static string DefaultDirectory()
    {
        var configured = Environment.GetEnvironmentVariable(DirectoryVariable);
        if (!string.IsNullOrWhiteSpace(configured))
        {
            return configured!;
        }

        var baseDirectory = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (string.IsNullOrEmpty(baseDirectory))
        {
            baseDirectory = Path.GetTempPath();
        }

        return Path.Combine(baseDirectory, "MCPRouter");
    }

    /// <summary>
    /// The stored toggles applied over <paramref name="seed"/>, or <paramref name="seed"/> itself
    /// when there is no readable file.
    /// </summary>
    /// <remarks>
    /// A key the document does not carry leaves the seed's value alone rather than defaulting to
    /// false. A store written by an older build is missing keys, not asserting them off, and
    /// reading absence as "the user turned this off" is how a setting silently flips on upgrade.
    /// </remarks>
    public RouterSettingsState Load(RouterSettingsState seed)
    {
        LastError = null;
        try
        {
            if (!File.Exists(_filePath))
            {
                return seed;
            }

            using var document = JsonDocument.Parse(File.ReadAllText(_filePath));
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                LastError = "the settings file does not hold a JSON object";
                return seed;
            }

            var state = seed;
            foreach (var key in SettingsPresentation.ToggleKeys)
            {
                if (document.RootElement.TryGetProperty(key, out var value)
                    && (value.ValueKind == JsonValueKind.True || value.ValueKind == JsonValueKind.False))
                {
                    state = SettingsPresentation.WithToggle(state, key, value.GetBoolean());
                }
            }
            return state;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            LastError = ex.Message;
            return seed;
        }
    }

    /// <summary>Writes the three toggles, and reports whether the write reached the disk.</summary>
    public bool Save(RouterSettingsState state)
    {
        LastError = null;
        try
        {
            var directory = Path.GetDirectoryName(_filePath);
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory!);
            }

            using var buffer = new MemoryStream();
            using (var writer = new Utf8JsonWriter(buffer, new JsonWriterOptions { Indented = true }))
            {
                writer.WriteStartObject();
                writer.WriteString("schema", Schema);
                foreach (var key in SettingsPresentation.ToggleKeys)
                {
                    writer.WriteBoolean(key, SettingsPresentation.ToggleValue(state, key));
                }
                writer.WriteString("savedAtUtc", DateTime.UtcNow.ToString("o"));
                writer.WriteEndObject();
            }

            File.WriteAllBytes(_filePath, buffer.ToArray());
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            LastError = ex.Message;
            return false;
        }
    }
}
