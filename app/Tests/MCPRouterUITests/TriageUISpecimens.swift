#if os(macOS)
    import Foundation
    @testable import MCPRouterKit

    /// The Triage entries this target asserts against.
    ///
    /// **A deliberate sibling of `MCPRouterKitTests.TriageSpecimens`, not a shared type.** The two
    /// test targets do not import each other, and the alternative — a shared support target, or
    /// specimens shipped inside `MCPRouterKit` — would put test fixtures in the product binary,
    /// which is exactly what the Phase D critic made `RecordingControlAPIClient` move out of.
    /// `DiscoverSurfaceIOSTests` carries its own builder for the same reason.
    ///
    /// It is deliberately **narrower** than the kit's: this target asserts model behaviour, so it
    /// needs one selectable entry, one more to make a batch, and one with no descriptor. The seven
    /// capability outcomes are the kit's to enumerate, and enumerating them twice would create the
    /// drift the single derivation exists to prevent.
    enum TriageSpecimens {
        static func entry(
            id: String,
            displayName: String? = nil,
            install: RegistryInstall?
        ) -> RegistryEntry {
            RegistryEntry(
                id: id,
                name: id,
                displayName: displayName ?? id,
                description: "A specimen entry",
                source: .official,
                repository: nil,
                version: nil,
                updatedAt: nil,
                useCount: nil,
                verified: nil,
                iconURL: nil,
                stars: nil,
                forks: nil,
                pushedAt: nil,
                archived: nil,
                install: install,
                installed: false
            )
        }

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

        /// Neither index says how this runs, so there is nothing for the Mac to review.
        static let noInstall = entry(id: "official:bare", displayName: "bare", install: nil)

        static let all: [RegistryEntry] = [stdio, remote, noInstall]

        static func response(
            _ entries: [RegistryEntry] = all,
            warnings: [String] = []
        ) -> RegistrySearchResponse {
            RegistrySearchResponse(
                results: entries,
                sources: RegistrySources(
                    official: entries.count,
                    smithery: 0,
                    merged: entries.count
                ),
                warnings: warnings
            )
        }
    }
#endif
