import Foundation

// The wire shapes of `GET /extensions/updates`: the update check the router runs over its own store.
//
// The check reads only what the router holds. An entry outside the store is not in this list,
// and that does not mean it is current. `changelog` is present on an entry the router
// compared against a newer offer, and is nil on every other entry, which is what an absent
// member means.

/// One entry the update check compared.
public struct ExtensionUpdateEntry: Codable, Hashable, Sendable, Identifiable {
    public var kind: StoredExtensionKind
    /// The name the router holds the entry under: `<plugin>@<marketplace>` for a plugin.
    public var name: String
    /// The verdict's closed state, e.g. `update-available` or `current`. Kept as the router's word.
    public var state: String
    public var installed: String?
    public var available: String?
    public var hasUpdate: Bool
    /// What a person reads beside the row. It names the two versions rather than saying something was wrong.
    public var reason: String
    public var changelog: ExtensionChangelog?

    public var id: String { "\(kind.rawValue)/\(name)" }

    public init(
        kind: StoredExtensionKind,
        name: String,
        state: String,
        installed: String? = nil,
        available: String? = nil,
        hasUpdate: Bool,
        reason: String,
        changelog: ExtensionChangelog? = nil
    ) {
        self.kind = kind
        self.name = name
        self.state = state
        self.installed = installed
        self.available = available
        self.hasUpdate = hasUpdate
        self.reason = reason
        self.changelog = changelog
    }
}

/// The changelog of the version an entry offers. `text` is nil wherever the router did not send it.
/// `note` says which case it was: none published, not in the cache, over the cap, or outside the cache.
public struct ExtensionChangelog: Codable, Hashable, Sendable {
    public var text: String?
    public var note: String

    public init(text: String?, note: String) {
        self.text = text
        self.note = note
    }
}

/// The whole update check. `unreadable` names a kind directory the router could not read, which is not an
/// empty store.
public struct ExtensionUpdatesResponse: Codable, Hashable, Sendable {
    public var entries: [ExtensionUpdateEntry]
    public var unreadable: [String]

    public init(entries: [ExtensionUpdateEntry] = [], unreadable: [String] = []) {
        self.entries = entries
        self.unreadable = unreadable
    }

    /// The entries that have a newer version to offer, in the router's order.
    public var offered: [ExtensionUpdateEntry] { entries.filter(\.hasUpdate) }
}
