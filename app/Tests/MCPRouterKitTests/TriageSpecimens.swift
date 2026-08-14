import Foundation
@testable import MCPRouterKit

/// The entries the Triage suites are asserted against, held in one namespace.
///
/// Separate from the suites for the reason `DiscoverSpecimens` and `CheckFixtures` are separate:
/// two suites over the same seven capability outcomes would otherwise each carry their own
/// `entry(...)`, and two builders that drift make the same assertion mean two different things
/// depending on which file it lives in.
///
/// The set is chosen to span **every one of `CapabilityPlate`'s seven outcomes**, including the two
/// a five-row table would have dropped — the remote install whose URL will not parse, and the
/// Smithery-hosted credential — because those are the two the summary's colour rule turns on.
enum TriageSpecimens {
    static func entry(
        id: String,
        displayName: String? = nil,
        source: RegistryEntry.Source = .official,
        archived: Bool? = nil,
        install: RegistryInstall?
    ) -> RegistryEntry {
        RegistryEntry(
            id: id,
            name: id,
            displayName: displayName ?? id,
            description: "A specimen entry",
            source: source,
            repository: nil,
            version: nil,
            updatedAt: nil,
            useCount: nil,
            verified: nil,
            iconURL: nil,
            stars: nil,
            forks: nil,
            pushedAt: nil,
            archived: archived,
            install: install,
            installed: false
        )
    }

    /// Runs a program on the user's Mac. The one unambiguous attention case.
    static let stdio = entry(
        id: "official:stdio",
        displayName: "obsidian-github-mcp",
        install: RegistryInstall(
            type: .stdio,
            command: "npx",
            args: ["-y", "obsidian-github-mcp"],
            url: nil,
            requires: nil
        )
    )

    /// Remote, host parses, no secret. Nothing runs locally and nothing wants a decision.
    static let remote = entry(
        id: "official:remote",
        displayName: "Weather",
        install: RegistryInstall(
            type: .http,
            command: nil,
            args: nil,
            url: "https://mcp.example.com/weather",
            requires: nil
        )
    )

    /// Remote whose URL will not parse to a host. The clause has to say so rather than render an
    /// empty segment on the one line that states where the user's tool arguments go.
    static let remoteUnknownHost = entry(
        id: "official:no-host",
        displayName: "Somewhere",
        install: RegistryInstall(
            type: .sse,
            command: nil,
            args: nil,
            url: "not a url at all",
            requires: nil
        )
    )

    /// A secret on a host that is **not** Smithery's. Here the credential clause carries real
    /// signal, because nothing about this host makes it a foregone conclusion.
    static let credentialElsewhere = entry(
        id: "official:credential",
        displayName: "Linear",
        install: RegistryInstall(
            type: .http,
            command: nil,
            args: nil,
            url: "https://mcp.linear.app/sse",
            requires: [RegistryRequirement(
                name: "Authorization",
                description: "Bearer <key>",
                isSecret: true
            )]
        )
    )

    /// A secret on a Smithery host. **Every** Smithery entry declares one, so within that subset
    /// the clause distinguishes nothing — and Smithery is a majority of the corpus.
    static let credentialSmithery = entry(
        id: "smithery:github",
        displayName: "GitHub",
        source: .both,
        install: RegistryInstall(
            type: .http,
            command: nil,
            args: nil,
            url: "https://server.smithery.ai/github/mcp",
            requires: [RegistryRequirement(
                name: "Authorization",
                description: "Bearer <key>",
                isSecret: true
            )]
        )
    )

    /// Archived, and remote so the archive clause is the only one that could want attention.
    static let archived = entry(
        id: "official:archived",
        displayName: "Abandoned",
        archived: true,
        install: RegistryInstall(
            type: .http,
            command: nil,
            args: nil,
            url: "https://mcp.example.com/abandoned",
            requires: nil
        )
    )

    /// Neither index says how this runs. Not selectable: there is nothing for the Mac to review.
    static let noInstall = entry(
        id: "official:bare",
        displayName: "bare",
        install: nil
    )

    /// Everything, in the order the buckets will see it.
    static let all: [RegistryEntry] = [
        stdio,
        remote,
        remoteUnknownHost,
        credentialElsewhere,
        credentialSmithery,
        archived,
        noInstall
    ]

    static func response(
        _ entries: [RegistryEntry] = all,
        warnings: [String] = []
    ) -> RegistrySearchResponse {
        RegistrySearchResponse(
            results: entries,
            sources: RegistrySources(official: entries.count, smithery: 0, merged: entries.count),
            warnings: warnings
        )
    }
}
