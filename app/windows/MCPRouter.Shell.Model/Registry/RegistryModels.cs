namespace MCPRouter.Shell.Model.Registry;

/// <summary>
/// The shapes <c>GET /registry/search</c> serves (<c>src/control.ts:856</c>, built by
/// <c>src/registry.ts</c>).
///
/// The registry is the one part of the wire that is not the router's own data: it is what two
/// third-party indexes said, merged, with a locally-computed <c>Installed</c> flag added per
/// result. Fields the client does not yet use are still read as raw elements where they would be
/// lost otherwise, but nothing here invents a field the wire does not carry — and nothing on this
/// surface may invent a value the wire does not carry either (spec-WIN7 §2).
/// </summary>
public sealed class RegistrySearchResponse
{
    public List<RegistryEntry> Results { get; init; } = new();
    public RegistrySources Sources { get; init; } = new();
    public List<string> Warnings { get; init; } = new();
}

public sealed class RegistrySources
{
    public int Official { get; init; }
    public int Smithery { get; init; }
    public int Merged { get; init; }
}

public sealed class RegistryEntry
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public string DisplayName { get; init; } = "";
    public string Description { get; init; } = "";
    /// <summary>Which index (or both) produced this entry. Closed on the wire, closed here.</summary>
    public string Source { get; init; } = "";
    public string? Repository { get; init; }
    public string? Version { get; init; }
    public string? UpdatedAt { get; init; }
    /// <summary>Smithery only: sessions started. The only popularity figure either index publishes.</summary>
    public int? UseCount { get; init; }
    public bool? Verified { get; init; }
    public string? IconUrl { get; init; }
    public int? Stars { get; init; }
    public int? Forks { get; init; }
    public string? PushedAt { get; init; }
    public bool? Archived { get; init; }
    public RegistryInstall? Install { get; init; }
    /// <summary>Added by the router, not by either index: whether this is already declared locally.</summary>
    public bool? Installed { get; init; }

    /// <summary>Returns a copy with <see cref="Installed" /> set, for the in-place mark after a
    /// successful add. No refetch on purpose: the search is non-deterministic between calls, so
    /// re-reading it at the moment the user acted would reorder the board under them (the Mac
    /// board model's <c>markInstalled</c>, same reason).</summary>
    public RegistryEntry AsInstalled() => new()
    {
        Id = Id,
        Name = Name,
        DisplayName = DisplayName,
        Description = Description,
        Source = Source,
        Repository = Repository,
        Version = Version,
        UpdatedAt = UpdatedAt,
        UseCount = UseCount,
        Verified = Verified,
        IconUrl = IconUrl,
        Stars = Stars,
        Forks = Forks,
        PushedAt = PushedAt,
        Archived = Archived,
        Install = Install,
        Installed = true,
    };
}

public sealed class RegistryInstall
{
    /// <summary>"stdio" | "http" | "sse". Kept as the raw string so an unknown future value
    /// surfaces as itself rather than throwing on deserialize.</summary>
    public string Type { get; init; } = "";
    public string? Command { get; init; }
    public List<string>? Args { get; init; }
    public string? Url { get; init; }
    public List<RegistryRequirement>? Requires { get; init; }
}

public sealed class RegistryRequirement
{
    public string Name { get; init; } = "";
    public string? Description { get; init; }
    public bool? IsSecret { get; init; }
}

/// <summary>The body <c>POST /servers</c> accepts. <c>Force</c> is deliberately absent: adopting
/// an existing declaration from a registry row would let a list entry replace the command line of
/// a server the user already trusts (the Mac's <c>RegistryCapability.declaration</c> guarantee,
/// held structurally here rather than by discipline).</summary>
public sealed class NewServer
{
    public string Name { get; init; } = "";
    public string? Type { get; init; }
    public string? Command { get; init; }
    public List<string>? Args { get; init; }
    public string? Url { get; init; }
    public Dictionary<string, string>? Headers { get; init; }
    public Dictionary<string, string>? Env { get; init; }
}
