import Foundation

// The shapes `/registry/search` serves.
//
// Split out of `Models.swift` because the registry is the one part of the wire that is not the
// router's own data: it is what two third-party indexes said, merged, with a locally-computed
// `installed` flag added per result. Keeping it in its own file makes that boundary visible, and
// keeps the file holding the router's own shapes readable.

// MARK: - Registry search

/// A header a registry entry says it needs. Values are never carried — the user supplies them.
public struct RegistryRequirement: Codable, Hashable, Sendable {
    public var name: String
    public var description: String?
    public var isSecret: Bool?
}

/// How to run an entry, when either index says. Absent when neither does.
public struct RegistryInstall: Codable, Hashable, Sendable {
    public var type: ServerTransport
    public var command: String?
    public var args: [String]?
    public var url: String?
    public var requires: [RegistryRequirement]?
}

public struct RegistryEntry: Codable, Hashable, Sendable, Identifiable {
    /// Which index (or both) produced this entry. Closed on the wire, closed here.
    public enum Source: String, Codable, Hashable, Sendable, CaseIterable {
        case official
        case smithery
        case both
    }

    public var id: String
    public var name: String
    public var displayName: String
    public var description: String
    public var source: Source
    public var repository: String?
    public var version: String?
    public var updatedAt: String?
    /// Smithery only: sessions started. The only popularity figure either index publishes, which is
    /// why nothing else numeric appears here — there is nothing else measured to show.
    public var useCount: Int?
    public var verified: Bool?
    public var iconURL: String?
    public var stars: Int?
    public var forks: Int?
    public var pushedAt: String?
    public var archived: Bool?
    public var install: RegistryInstall?
    /// Added by the router, not by either index: whether this is already declared locally.
    public var installed: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, name, displayName, description, source, repository, version, updatedAt
        case useCount, verified, stars, forks, pushedAt, archived, install, installed
        case iconURL = "iconUrl"
    }
}

public struct RegistrySources: Codable, Hashable, Sendable {
    public var official: Int
    public var smithery: Int
    public var merged: Int
}

public struct RegistrySearchResponse: Codable, Hashable, Sendable {
    public var results: [RegistryEntry]
    public var sources: RegistrySources
    public var warnings: [String]
}
