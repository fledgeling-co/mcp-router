import Foundation
@testable import MCPRouterKit

/// The inputs `DiscoverHonestyTests` measures against, and the file-scanning it needs to measure
/// the views as well as the values.
///
/// Separate from the suite because neither is a test: these are the specimens and the instrument.
/// Keeping them here also keeps the suite readable as a list of claims rather than as a wall of
/// fixture literals.
enum DiscoverSpecimens {
    /// Entries spanning what the wire actually produces: a Smithery entry with a count and no
    /// repository data, an official entry with GitHub enrichment and no count, and one carrying
    /// neither.
    static let entries: [RegistryEntry] = [
        RegistryEntry(
            id: "smithery:github",
            name: "github",
            displayName: "GitHub",
            description: "Manage repos, issues and PRs",
            source: .both,
            repository: "https://github.com/",
            version: nil,
            updatedAt: "2025-11-19T07:26:28.312Z",
            useCount: 2984,
            verified: false,
            iconURL: nil,
            stars: nil,
            forks: nil,
            pushedAt: nil,
            archived: nil,
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
            ),
            installed: false
        ),
        RegistryEntry(
            id: "official:obsidian",
            name: "ai.smithery/obsidian",
            displayName: "obsidian-github-mcp",
            description: "Search a GitHub-hosted Obsidian vault",
            source: .official,
            repository: "https://github.com/Hint-Services/obsidian-github-mcp",
            version: "0.4.0",
            updatedAt: "2025-09-14T15:20:36.371442Z",
            useCount: nil,
            verified: nil,
            iconURL: nil,
            stars: 9,
            forks: 7,
            pushedAt: "2025-11-28T13:53:01Z",
            archived: false,
            install: RegistryInstall(
                type: .stdio,
                command: "npx",
                args: ["-y", "obsidian-github-mcp"],
                url: nil,
                requires: nil
            ),
            installed: false
        ),
        RegistryEntry(
            id: "official:bare",
            name: "bare",
            displayName: "bare",
            description: "Neither index says much",
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
            archived: true,
            install: nil,
            installed: true
        )
    ]

    /// Every substitution any template can take, filled with a value that would be visible if it
    /// leaked somewhere it should not.
    static let substitutions: [DiscoverCopy.Token: String] = [
        .mac: "Luke's MacBook Pro",
        .count: "2,984",
        .query: "github",
        .window: "30",
        .name: "GitHub",
        .reason: DiscoverFailureReason.transport.text,
        .warning: "something the router said",
        .host: "server.smithery.ai"
    ]

    /// Everything the feature can put in front of a person: the copy manifest, resolved; every
    /// failure reason; every window label; every plate line; and every data-derived string.
    static func everyRenderableString() -> [String] {
        var strings: [String] = []

        for key in DiscoverCopy.Key.allCases {
            let entry = DiscoverCopy.entry(key).resolved(substitutions)
            strings.append(contentsOf: [entry.headline, entry.actionLabel].compactMap(\.self))
            strings.append(entry.body)
        }
        strings.append(contentsOf: DiscoverFailureReason.allCases.map(\.text))
        strings.append(contentsOf: RecencyWindow.allCases.map(\.label))
        strings.append(PairingCopy.neverInstalls)

        for entry in entries {
            strings.append(contentsOf: [
                DiscoverPresentation.useCountText(entry),
                DiscoverPresentation.starsText(entry),
                DiscoverPresentation.changedText(entry),
                DiscoverPresentation.lastCommitText(entry),
                CapabilityPlate.invocation(install: entry.install)
            ].compactMap(\.self))
            strings.append(contentsOf: CapabilityPlate
                .lines(install: entry.install, archived: entry.archived)
                .map(\.text))
        }
        strings.append(contentsOf: [
            DiscoverPresentation.truncationText(shown: 30, limit: 30),
            DiscoverPresentation.truncationText(shown: 3, limit: 30)
        ].compactMap(\.self))

        return strings
    }

    // MARK: - The source scan

    enum ScanError: Error { case rootNotFound, nothingScanned }

    /// The repo root, found by walking up from this file — the same way the design-token tests find
    /// `DESIGN.md`, and a hard failure rather than a skip when it is missing.
    static func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("DESIGN.md").path
            ) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        throw ScanError.rootNotFound
    }

    static func swiftFiles(under relativePath: String) throws -> [(name: String, source: String)] {
        let root = try repoRoot().appendingPathComponent(relativePath)
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            throw ScanError.nothingScanned
        }
        var files: [(String, String)] = []
        for case let path as String in walker where path.hasSuffix(".swift") {
            let url = root.appendingPathComponent(path)
            try files.append((path, String(contentsOf: url, encoding: .utf8)))
        }
        // A scan that scanned nothing must not read as a pass.
        guard !files.isEmpty else { throw ScanError.nothingScanned }
        return files
    }

    /// Remove comments and string literals, so a rule cannot be tripped by prose that mentions the
    /// thing it forbids — the doc comments in these files discuss `useCount` at length — and,
    /// more importantly, cannot be evaded by a value hidden in an interpolation.
    static func stripped(_ source: String) -> String {
        var out = ""
        for line in source.components(separatedBy: .newlines) {
            let withoutComment = line.components(separatedBy: "//").first ?? ""
            var inString = false
            var kept = ""
            for character in withoutComment {
                if character == "\"" { inString.toggle(); continue }
                if !inString { kept.append(character) }
            }
            out += kept + "\n"
        }
        return out
    }
}
