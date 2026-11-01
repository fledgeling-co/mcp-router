namespace MCPRouter.Shell.Model.Skills;

/// <summary>The kinds the router's extension store holds, by the word its wire uses.</summary>
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
    StoredExtensionKind Kind,
    string Name,
    string State,
    string? Installed,
    string? Available,
    bool HasUpdate,
    string Reason,
    SkillChangelog? Changelog);

/// <summary>The whole update check, as <c>GET /extensions/updates</c> answers it.</summary>
public sealed record ExtensionUpdatesResponse(ExtensionUpdateEntry[]? Entries, string[]? Unreadable)
{
    public IReadOnlyList<ExtensionUpdateEntry> EntryList => Entries ?? Array.Empty<ExtensionUpdateEntry>();
}

/// <summary>What a promotion answered: the version now installed, and the reference an undo is given.</summary>
public sealed record PromotionAck(
    string Promoted,
    StoredExtensionKind Kind,
    string PluginVersion,
    string? Replaced,
    string Restore);

/// <summary>What an undo answered: the version put back, and the promoted version it withdrew.</summary>
public sealed record UndoAck(
    string Restored,
    StoredExtensionKind Kind,
    string? Version,
    string Withdrawn);

/// <summary>What a keep answered: the held version the router recorded.</summary>
public sealed record KeepAck(
    string Kept,
    StoredExtensionKind Kind,
    string PluginVersion);
