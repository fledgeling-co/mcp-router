import Foundation

// The wire shapes for skills and marketplaces, transcribed from `src/skills.ts`.
//
// **The one modelling decision everything else follows from.** A *plugin* is the unit that gets
// installed and versioned; a *skill* is one of the things a plugin contains, and a plugin can
// contain thirty of them. So a skill's version is its **plugin's** version, and every type here
// says `pluginVersion` rather than `version` — a field called `version` on a `Skill` reads as a
// property of the skill, and thirty rows would silently claim thirty independent versions that
// are really one.
//
// **What is absent, by construction.** There is no `runs`, `lastRun` or `eval` field anywhere in
// this file. A skill is markdown the *client* loads into an agent's context; it never traverses
// the router, so the process that would count an invocation never sees one, and no eval runner
// exists in this product. `DESIGN.md` §6 forbids displaying a figure the router does not observe,
// and the strongest form of that rule is a type with nowhere to put one.

/// Whether one skill is reachable from one client.
///
/// Three cases rather than a `Bool`, and the third is the whole of the Partial state: `unreadable`
/// means that client's skills directory could not be read, so whether the skill is there is
/// **unknown**. A boolean would collapse that into "absent", and the board would draw an empty slot
/// asserting the skill is not installed somewhere nobody managed to look.
public enum SkillPresence: String, Codable, Hashable, Sendable, CaseIterable {
    case present
    case absent
    case unreadable
}

/// What happened when the router looked in one client's skills directory.
public enum SkillClientStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case read
    case absent
    case unreadable
    /// The client has no skills mechanism at all. Not a failure, and not the same as `absent`.
    case unsupported
}

/// One of the six managed clients, as the router reports it.
///
/// The two clients with no skills mechanism are carried here rather than filtered out, so the
/// inspector can *say* they have none. A client the app never hears about is indistinguishable, on
/// screen, from a client whose skills the router failed to find — and those two want opposite words.
public struct SkillClient: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var supportsSkills: Bool
    public var root: String?
    public var status: SkillClientStatus
    /// Why the directory could not be read. Present only for `.unreadable`.
    public var reason: String?

    public init(
        id: String,
        displayName: String,
        supportsSkills: Bool,
        root: String? = nil,
        status: SkillClientStatus,
        reason: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.supportsSkills = supportsSkills
        self.root = root
        self.status = status
        self.reason = reason
    }
}

/// Where a skill came from.
///
/// A closed enum with associated values rather than a struct with optional fields, so a standalone
/// skill **has no version to render**. That is a structural guarantee: there is no `pluginVersion`
/// on the `.standalone` case for a careless `??  "1.0.0"` to fill in. A skill placed in a client's
/// directory by hand genuinely has no version anywhere on disk — `SKILL.md` frontmatter carries
/// `name` and `description` and nothing else.
public enum SkillSource: Hashable, Sendable {
    case plugin(PluginOrigin)
    case standalone(path: String)

    public var pluginOrigin: PluginOrigin? {
        if case let .plugin(origin) = self { return origin }
        return nil
    }

    public var isStandalone: Bool {
        if case .standalone = self { return true }
        return false
    }
}

public struct PluginOrigin: Codable, Hashable, Sendable {
    public var plugin: String
    public var marketplace: String
    /// The **plugin's** version, shared by every skill the plugin contains.
    public var pluginVersion: String
    public var installedAt: String?
    public var lastUpdated: String?
    public var commit: String?
    /// How many skills this plugin supplies, so a shared version can be explained rather than
    /// looking like a coincidence across thirty rows.
    public var siblingSkillCount: Int

    public init(
        plugin: String,
        marketplace: String,
        pluginVersion: String,
        installedAt: String? = nil,
        lastUpdated: String? = nil,
        commit: String? = nil,
        siblingSkillCount: Int = 1
    ) {
        self.plugin = plugin
        self.marketplace = marketplace
        self.pluginVersion = pluginVersion
        self.installedAt = installedAt
        self.lastUpdated = lastUpdated
        self.commit = commit
        self.siblingSkillCount = siblingSkillCount
    }
}

extension SkillSource: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, path
    }

    private enum Kind: String, Codable {
        case plugin, standalone
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A closed set on the wire is a closed set in Swift: an unrecognised `kind` fails decoding
        // rather than being guessed at by a `default` branch.
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .plugin:
            self = try .plugin(PluginOrigin(from: decoder))
        case .standalone:
            self = try .standalone(path: container.decode(String.self, forKey: .path))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .plugin(origin):
            try container.encode(Kind.plugin, forKey: .kind)
            try origin.encode(to: encoder)
        case let .standalone(path):
            try container.encode(Kind.standalone, forKey: .kind)
            try container.encode(path, forKey: .path)
        }
    }
}

/// A newer version of a skill's plugin, sitting beside the installed one and not yet promoted.
///
/// `addedCapabilities` empty means the new version wants no more than the old one. That is the
/// whole of the brief's trust rule: trust decays per version, so a version that asks for more waits
/// for a human and one that asks for the same does not.
public struct HeldVersion: Codable, Hashable, Sendable {
    public var pluginVersion: String
    public var addedCapabilities: [String]
    /// How many skills promoting this plugin would move at once.
    public var affectedSkillCount: Int

    public init(pluginVersion: String, addedCapabilities: [String] = [], affectedSkillCount: Int = 1) {
        self.pluginVersion = pluginVersion
        self.addedCapabilities = addedCapabilities
        self.affectedSkillCount = affectedSkillCount
    }

    /// Whether this version may promote without asking.
    public var wantsMore: Bool { !addedCapabilities.isEmpty }
}

/// A marketplace that now resolves somewhere other than where the router first saw it.
///
/// `firstSeenAt` is the router's own first observation, **not** the install date, and the copy that
/// renders it says so. The client's own files record a commit but never an owner, so "changed since
/// you installed it" is not computable from them; reporting the router's first sighting is what can
/// actually be stood behind.
public struct SkillProvenance: Codable, Hashable, Sendable {
    public var firstSeenSource: String
    public var currentSource: String
    public var firstSeenAt: String

    public init(firstSeenSource: String, currentSource: String, firstSeenAt: String) {
        self.firstSeenSource = firstSeenSource
        self.currentSource = currentSource
        self.firstSeenAt = firstSeenAt
    }
}

/// One skill, wherever it is reachable from.
///
/// Identified by `path` — the resolved real path — rather than by name. Clients hold skills by
/// symlink into a shared library, so one skill reachable from four clients is one row with four
/// slots lit; keying on the name would split it into four, and would merge two unrelated skills
/// that happen to share a directory name.
public struct Skill: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var description: String?
    public var path: String
    public var source: SkillSource
    public var presence: [String: SkillPresence]
    public var held: HeldVersion?
    public var provenance: SkillProvenance?

    public var id: String { path }

    public init(
        name: String,
        description: String? = nil,
        path: String,
        source: SkillSource,
        presence: [String: SkillPresence] = [:],
        held: HeldVersion? = nil,
        provenance: SkillProvenance? = nil
    ) {
        self.name = name
        self.description = description
        self.path = path
        self.source = source
        self.presence = presence
        self.held = held
        self.provenance = provenance
    }

    /// Whether a human should look at this skill: a held version that wants more, or a moved owner.
    public var needsAttention: Bool {
        provenance != nil || (held?.wantsMore ?? false)
    }
}

public struct SkillsResponse: Codable, Hashable, Sendable {
    public var skills: [Skill]
    public var clients: [SkillClient]

    public init(skills: [Skill] = [], clients: [SkillClient] = []) {
        self.skills = skills
        self.clients = clients
    }

    /// The clients that have a skills mechanism, in the router's order — which is the slot order.
    public var slotClients: [SkillClient] { clients.filter(\.supportsSkills) }

    /// The clients the router reports as having no skills mechanism at all.
    public var unsupportedClients: [SkillClient] { clients.filter { !$0.supportsSkills } }
}

public enum MarketplaceSource: Hashable, Sendable {
    case github(repo: String)
    case directory(path: String)

    /// How the source reads on screen. Monospace, because it is an address rather than prose.
    public var label: String {
        switch self {
        case let .github(repo): "github: \(repo)"
        case let .directory(path): "directory: \(path)"
        }
    }

    /// A local directory has nothing to fetch, so auto-update means nothing for it.
    public var isLocalDirectory: Bool {
        if case .directory = self { return true }
        return false
    }
}

extension MarketplaceSource: Codable {
    private enum CodingKeys: String, CodingKey { case kind, repo, path }
    private enum Kind: String, Codable { case github, directory }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .github: self = try .github(repo: container.decode(String.self, forKey: .repo))
        case .directory: self = try .directory(path: container.decode(String.self, forKey: .path))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .github(repo):
            try container.encode(Kind.github, forKey: .kind)
            try container.encode(repo, forKey: .repo)
        case let .directory(path):
            try container.encode(Kind.directory, forKey: .kind)
            try container.encode(path, forKey: .path)
        }
    }
}

public struct Marketplace: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var source: MarketplaceSource
    public var autoUpdate: Bool
    public var installedPluginCount: Int
    public var suppliedSkillCount: Int

    public var id: String { name }

    public init(
        name: String,
        source: MarketplaceSource,
        autoUpdate: Bool = false,
        installedPluginCount: Int = 0,
        suppliedSkillCount: Int = 0
    ) {
        self.name = name
        self.source = source
        self.autoUpdate = autoUpdate
        self.installedPluginCount = installedPluginCount
        self.suppliedSkillCount = suppliedSkillCount
    }
}

public struct MarketplacesResponse: Codable, Hashable, Sendable {
    public var marketplaces: [Marketplace]

    public init(marketplaces: [Marketplace] = []) {
        self.marketplaces = marketplaces
    }
}
