using System.Text.Json.Serialization;

namespace MCPRouter.Shell.Model.Skills;

/// <summary>The kinds the router's extension store holds, by the word its wire uses.</summary>
[JsonConverter(typeof(WireEnumConverter<StoredExtensionKind>))]
public enum StoredExtensionKind
{
    Skills,
    Plugins,
    Marketplaces,
}

/// <summary>
/// One entry the router's update check compared. <see cref="Changelog"/> is present only on an entry that offers a
/// newer version, and only where the router could read the changelog of that version.
/// </summary>
public sealed record ExtensionUpdateEntry(
    [property: JsonPropertyName("kind")] StoredExtensionKind Kind,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("state")] string State,
    [property: JsonPropertyName("installed")] string? Installed,
    [property: JsonPropertyName("available")] string? Available,
    [property: JsonPropertyName("hasUpdate")] bool HasUpdate,
    [property: JsonPropertyName("reason")] string Reason,
    [property: JsonPropertyName("changelog")] SkillChangelog? Changelog);

/// <summary>The whole update check, as <c>GET /extensions/updates</c> answers it.</summary>
public sealed record ExtensionUpdatesResponse(
    [property: JsonPropertyName("entries")] ExtensionUpdateEntry[]? Entries,
    [property: JsonPropertyName("unreadable")] string[]? Unreadable)
{
    public IReadOnlyList<ExtensionUpdateEntry> EntryList => Entries ?? Array.Empty<ExtensionUpdateEntry>();
}

/// <summary>What a promotion answered: the version now installed, and the reference an undo is given.</summary>
public sealed record PromotionAck(
    [property: JsonPropertyName("promoted")] string Promoted,
    [property: JsonPropertyName("kind")] StoredExtensionKind Kind,
    [property: JsonPropertyName("pluginVersion")] string PluginVersion,
    [property: JsonPropertyName("replaced")] string? Replaced,
    [property: JsonPropertyName("restore")] string Restore);

/// <summary>What an undo answered: the version put back, and the promoted version it withdrew.</summary>
public sealed record UndoAck(
    [property: JsonPropertyName("restored")] string Restored,
    [property: JsonPropertyName("kind")] StoredExtensionKind Kind,
    [property: JsonPropertyName("version")] string? Version,
    [property: JsonPropertyName("withdrawn")] string Withdrawn);

/// <summary>What a keep answered: the held version the router recorded.</summary>
public sealed record KeepAck(
    [property: JsonPropertyName("kept")] string Kept,
    [property: JsonPropertyName("kind")] StoredExtensionKind Kind,
    [property: JsonPropertyName("pluginVersion")] string PluginVersion);
