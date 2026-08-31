using System.Text.Json;
using System.Text.Json.Serialization;

namespace MCPRouter.Shell.Model.Skills;

/// <summary>
/// The wire shapes for skills and marketplaces, transcribed from the Mac fleet's M4 models
/// (<c>app/Sources/MCPRouterKit/Control/SkillModels.swift</c>), which are themselves transcribed
/// from the router's skills types.
///
/// The one modelling decision everything else follows from, carried unchanged: a <b>plugin</b> is
/// the unit that gets installed and versioned; a <b>skill</b> is one of the things a plugin
/// contains. So a skill's version is its <b>plugin's</b> version, and every type here says
/// <c>plugin_version</c> rather than <c>version</c>.
///
/// What is absent, by construction: there is no <c>runs</c>, <c>last_run</c> or <c>eval</c>
/// field anywhere in this file. A skill is markdown the client loads into an agent's context; it
/// never traverses the router. DESIGN.md §6 forbids displaying a figure the router does not
/// observe, and the strongest form of that rule is a type with nowhere to put one.
/// </summary>
public enum SkillPresence
{
    Present,
    Absent,
    /// <summary>That client's skills directory could not be read, so whether the skill is there is unknown.</summary>
    Unreadable,
}

/// <summary>What happened when the router looked in one client's skills directory.</summary>
public enum SkillClientStatus
{
    Read,
    Absent,
    Unreadable,
    /// <summary>The client has no skills mechanism at all. Not a failure, and not the same as absent.</summary>
    Unsupported,
}

/// <summary>
/// Enum names as the wire spells them: camelCase, which for these single-word members is the
/// wire's lowercase ("present", "read", "unsupported").
/// </summary>
internal sealed class WireEnumConverter<T> : JsonStringEnumConverter<T>
    where T : struct, Enum
{
    public WireEnumConverter()
        : base(JsonNamingPolicy.CamelCase)
    {
    }
}

/// <summary>
/// One of the managed clients, as the router reports it.
///
/// The clients with no skills mechanism are carried here rather than filtered out, so the
/// inspector can <i>say</i> they have none. A client the app never hears about is
/// indistinguishable, on screen, from a client whose skills the router failed to find - and those
/// two want opposite words.
/// </summary>
public sealed record SkillClient(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("display_name")] string DisplayName,
    [property: JsonPropertyName("supports_skills")] bool SupportsSkills,
    [property: JsonPropertyName("root")] string? Root,
    [property: JsonPropertyName("status")]
    [property: JsonConverter(typeof(WireEnumConverter<SkillClientStatus>))] SkillClientStatus Status,
    [property: JsonPropertyName("reason")] string? Reason);

/// <summary>
/// Where a skill came from.
///
/// A closed discriminated union rather than a struct with optional fields, so a standalone skill
/// <b>has no version to render</b>. That is a structural guarantee: there is no plugin version on
/// the standalone case for a careless <c>?? "1.0.0"</c> to fill in. A skill placed in a client's
/// directory by hand genuinely has no version anywhere on disk.
/// </summary>
[JsonConverter(typeof(SkillSource.SkillSourceConverter))]
public abstract record SkillSource
{
    public sealed record PluginOrigin(
        [property: JsonPropertyName("plugin")] string Plugin,
        [property: JsonPropertyName("marketplace")] string Marketplace,
        // The plugin's version, shared by every skill the plugin contains.
        [property: JsonPropertyName("plugin_version")] string PluginVersion,
        [property: JsonPropertyName("installed_at")] string? InstalledAt,
        [property: JsonPropertyName("last_updated")] string? LastUpdated,
        [property: JsonPropertyName("commit")] string? Commit,
        // How many skills this plugin supplies, so a shared version can be explained rather than
        // looking like a coincidence across thirty rows.
        [property: JsonPropertyName("sibling_skill_count")] int SiblingSkillCount)
        : SkillSource;

    public sealed record Standalone(
        [property: JsonPropertyName("path")] string Path)
        : SkillSource;

    public PluginOrigin? AsPlugin =>
        this is PluginOrigin origin ? origin : null;

    public bool IsStandalone => this is Standalone;

    /// <summary>
    /// Decodes the wire's kind-tagged shape: <c>{"kind":"plugin", ...origin}</c> or
    /// <c>{"kind":"standalone","path":...}</c>. A closed set on the wire is a closed set here: an
    /// unrecognised <c>kind</c> fails decoding rather than being guessed at by a default branch.
    /// </summary>
    internal sealed class SkillSourceConverter : JsonConverter<SkillSource>
    {
        public override SkillSource? Read(
            ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            using var document = JsonDocument.ParseValue(ref reader);
            var element = document.RootElement;

            var kind = element.TryGetProperty("kind", out var kindElement)
                ? kindElement.GetString()
                : throw new JsonException("a skill source carries no kind");

            return kind switch
            {
                "plugin" => element.Deserialize<PluginOrigin>(options)
                    ?? throw new JsonException("a plugin skill source decoded to nothing"),
                "standalone" => element.Deserialize<Standalone>(options)
                    ?? throw new JsonException("a standalone skill source decoded to nothing"),
                _ => throw new JsonException($"unknown skill source kind '{kind}'"),
            };
        }

        public override void Write(
            Utf8JsonWriter writer, SkillSource value, JsonSerializerOptions options)
        {
            if (value is PluginOrigin origin)
            {
                JsonSerializer.Serialize(writer, origin, options);
                return;
            }
            JsonSerializer.Serialize(writer, (Standalone)value, options);
        }
    }
}

/// <summary>
/// A newer version of a skill's plugin, sitting beside the installed one and not yet promoted.
///
/// <see cref="AddedCapabilities"/> empty means the new version wants no more than the old one.
/// That is the whole of the brief's trust rule: a version that asks for more waits for a human,
/// and one that asks for the same does not. <b>This is a security guarantee, not a display
/// property</b> - the held state and the update-all count are both derived from it, and the tests
/// hold both derivations to it.
/// </summary>
public sealed record HeldVersion(
    [property: JsonPropertyName("plugin_version")] string PluginVersion,
    [property: JsonPropertyName("added_capabilities")] string[] AddedCapabilities,
    // How many skills promoting this plugin would move at once.
    [property: JsonPropertyName("affected_skill_count")] int AffectedSkillCount)
{
    /// <summary>Whether this version may promote without asking.</summary>
    public bool WantsMore => AddedCapabilities.Length > 0;
}

/// <summary>
/// A marketplace that now resolves somewhere other than where the router first saw it.
///
/// <c>first_seen_source</c> is the router's own first observation, <b>not</b> the install date,
/// and the copy that renders it says so.
/// </summary>
public sealed record SkillProvenance(
    [property: JsonPropertyName("first_seen_source")] string FirstSeenSource,
    [property: JsonPropertyName("current_source")] string CurrentSource,
    [property: JsonPropertyName("first_seen_at")] string FirstSeenAt);

/// <summary>
/// One skill, wherever it is reachable from.
///
/// Identified by <c>path</c> - the resolved real path - rather than by name. Clients hold skills
/// by symlink into a shared library, so one skill reachable from four clients is one row with
/// four slots lit; keying on the name would split it into four, and would merge two unrelated
/// skills that happen to share a directory name.
/// </summary>
public sealed record Skill(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("description")] string? Description,
    [property: JsonPropertyName("path")] string Path,
    [property: JsonPropertyName("source")] SkillSource Source,
    [property: JsonPropertyName("presence")]
    [property: JsonConverter(typeof(PresenceMapConverter))] IReadOnlyDictionary<string, SkillPresence> Presence,
    [property: JsonPropertyName("held")] HeldVersion? Held = null,
    [property: JsonPropertyName("provenance")] SkillProvenance? Provenance = null)
{
    /// <summary>Whether a human should look at this skill: a held version that wants more, or a moved owner.</summary>
    public bool NeedsAttention =>
        Provenance is not null || (Held?.WantsMore ?? false);

}

/// <summary>Decodes the <c>{"client-id": "present"|"absent"|"unreadable"}</c> map.</summary>
internal sealed class PresenceMapConverter : JsonConverter<IReadOnlyDictionary<string, SkillPresence>>
{
    public override IReadOnlyDictionary<string, SkillPresence> Read(
        ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        using var document = JsonDocument.ParseValue(ref reader);
        var result = new Dictionary<string, SkillPresence>();
        foreach (var property in document.RootElement.EnumerateObject())
        {
            result[property.Name] = property.Value.GetString() switch
            {
                "present" => SkillPresence.Present,
                "absent" => SkillPresence.Absent,
                "unreadable" => SkillPresence.Unreadable,
                _ => throw new JsonException(
                    $"unknown presence '{property.Value.GetString()}' for client '{property.Name}'"),
            };
        }
        return result;
    }

    public override void Write(
        Utf8JsonWriter writer,
        IReadOnlyDictionary<string, SkillPresence> value,
        JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        foreach (var (client, presence) in value)
        {
            writer.WritePropertyName(client);
            writer.WriteStringValue(presence switch
            {
                SkillPresence.Present => "present",
                SkillPresence.Absent => "absent",
                SkillPresence.Unreadable => "unreadable",
                _ => throw new JsonException("unhandled presence"),
            });
        }
        writer.WriteEndObject();
    }
}

public sealed record SkillsResponse(
    [property: JsonPropertyName("skills")] Skill[]? Skills,
    [property: JsonPropertyName("clients")] SkillClient[]? Clients)
{
    public IReadOnlyList<Skill> SkillList => Skills ?? Array.Empty<Skill>();
    public IReadOnlyList<SkillClient> ClientList => Clients ?? Array.Empty<SkillClient>();

    /// <summary>The clients that have a skills mechanism, in the router's order - which is the slot order.</summary>
    public IReadOnlyList<SkillClient> SlotClients =>
        ClientList.Where(c => c.SupportsSkills).ToList();

    /// <summary>The clients the router reports as having no skills mechanism at all.</summary>
    public IReadOnlyList<SkillClient> UnsupportedClients =>
        ClientList.Where(c => !c.SupportsSkills).ToList();
}

[JsonConverter(typeof(MarketplaceSource.MarketplaceSourceConverter))]
public abstract record MarketplaceSource
{
    public sealed record GitHub(
        [property: JsonPropertyName("repo")] string Repo)
        : MarketplaceSource;

    public sealed record Directory(
        [property: JsonPropertyName("path")] string Path)
        : MarketplaceSource;

    /// <summary>How the source reads on screen. Instrument face, because it is an address rather than prose.</summary>
    public string Label => this switch
    {
        GitHub repo => $"github: {repo.Repo}",
        Directory directory => $"directory: {directory.Path}",
        _ => throw new InvalidOperationException("unhandled marketplace source"),
    };

    /// <summary>A local directory has nothing to fetch, so auto-update means nothing for it.</summary>
    public bool IsLocalDirectory => this is Directory;

    /// <summary>Decodes the wire's kind-tagged shape, closed like <see cref="SkillSource"/>.</summary>
    internal sealed class MarketplaceSourceConverter : JsonConverter<MarketplaceSource>
    {
        public override MarketplaceSource? Read(
            ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            using var document = JsonDocument.ParseValue(ref reader);
            var element = document.RootElement;

            var kind = element.TryGetProperty("kind", out var kindElement)
                ? kindElement.GetString()
                : throw new JsonException("a marketplace source carries no kind");

            return kind switch
            {
                "github" => element.Deserialize<GitHub>(options)
                    ?? throw new JsonException("a github marketplace source decoded to nothing"),
                "directory" => element.Deserialize<Directory>(options)
                    ?? throw new JsonException("a directory marketplace source decoded to nothing"),
                _ => throw new JsonException($"unknown marketplace source kind '{kind}'"),
            };
        }

        public override void Write(
            Utf8JsonWriter writer, MarketplaceSource value, JsonSerializerOptions options)
        {
            switch (value)
            {
                case GitHub repo:
                    JsonSerializer.Serialize(writer, repo, options);
                    break;
                case Directory directory:
                    JsonSerializer.Serialize(writer, directory, options);
                    break;
            }
        }
    }
}

public sealed record Marketplace(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("source")] MarketplaceSource Source,
    [property: JsonPropertyName("auto_update")] bool AutoUpdate,
    [property: JsonPropertyName("installed_plugin_count")] int InstalledPluginCount,
    [property: JsonPropertyName("supplied_skill_count")] int SuppliedSkillCount);

public sealed record MarketplacesResponse(
    [property: JsonPropertyName("marketplaces")] Marketplace[]? Marketplaces)
{
    public IReadOnlyList<Marketplace> MarketplaceList =>
        Marketplaces ?? Array.Empty<Marketplace>();
}
