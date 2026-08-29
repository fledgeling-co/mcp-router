import Foundation

/// A named selection over the extensions this router holds, plus the upstreams it wants served.
///
/// **A selection, not a copy.** The names here are looked up in R28's store and in the live
/// upstream map on every read; nothing about an entry is remembered on the profile. A profile
/// naming a skill the store does not hold is not an error and is not silently dropped — it is
/// reported as `missing` by the projection, which is the state `spec-F8.md` §1.2 says is the
/// ordinary one on a machine whose store is empty.
///
/// The four member arrays are kept in the order they were written rather than sorted, for the
/// reason `ExtensionFile` is an ordered array: a refusal can then name a position.
public struct ProfileRecord: Sendable, Hashable {
    public let name: String
    public let title: String?
    public let servers: [String]
    public let skills: [String]
    public let plugins: [String]
    public let marketplaces: [String]

    public init(
        name: String,
        title: String? = nil,
        servers: [String] = [],
        skills: [String] = [],
        plugins: [String] = [],
        marketplaces: [String] = []
    ) {
        self.name = name
        self.title = title
        self.servers = servers
        self.skills = skills
        self.plugins = plugins
        self.marketplaces = marketplaces
    }

    /// The entry names this profile selects for one extension kind.
    public func names(for kind: ExtensionKind) -> [String] {
        switch kind {
        case .skills: skills
        case .plugins: plugins
        case .marketplaces: marketplaces
        }
    }

    /// How many names this profile carries in total, across the three kinds and the servers.
    ///
    /// A count of what was *asked for*. It is not a count of what exists, and the projection is
    /// where those two are compared — a profile is allowed to be larger than the store.
    public var selectionCount: Int {
        servers.count + skills.count + plugins.count + marketplaces.count
    }
}

/// One profile as it is listed, with whether its file could be read at all.
///
/// `unreadable` is separate from a `record` of `nil` for the reason ``ExtensionListing`` keeps the
/// two apart: a profile whose file rotted and a profile that does not exist are different problems
/// with different fixes, and only one of them is a count.
public struct ProfileListingRow: Sendable, Hashable {
    public let name: String
    public let record: ProfileRecord?
    public let problem: String?

    public init(name: String, record: ProfileRecord?, problem: String? = nil) {
        self.name = name
        self.record = record
        self.problem = problem
    }
}

/// Every profile on the router's disk, plus whether the directory could be opened.
public struct ProfileListing: Sendable {
    public let root: String
    public let rows: [ProfileListingRow]
    public let unreadable: String?

    public init(root: String, rows: [ProfileListingRow], unreadable: String? = nil) {
        self.root = root
        self.rows = rows
        self.unreadable = unreadable
    }
}

public enum ProfileWriteOutcome: Sendable {
    case written(ProfileRecord)
    case refused(ExtensionRefusal)
}

public enum ProfileRemoveOutcome: Sendable {
    /// Where the profile's bytes are now. Nothing is deleted, which is the whole of what
    /// reversible means here — the same contract `DELETE /extensions/:kind/:name` answers with.
    case removed(String)
    case refused(ExtensionRefusal)
}

/// Holding named profiles the way ``ExtensionStoring`` holds entries.
///
/// A port rather than a direct call for the reason ``ExtensionStoring`` is one: `ControlDiff` — the
/// in-process differential oracle — supplies none, and the routes must answer 503 saying the
/// capability is absent rather than an empty list, which a router holding no profiles would be
/// indistinguishable from.
public protocol ProfileStoring: Sendable {
    func list() -> ProfileListing
    func read(name: String) -> ProfileListingRow?
    func write(_ record: ProfileRecord) -> ProfileWriteOutcome
    func remove(name: String) -> ProfileRemoveOutcome
}
