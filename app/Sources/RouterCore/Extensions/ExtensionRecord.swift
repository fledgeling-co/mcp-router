import Foundation

/// One file handed to the store, as a relative path and its bytes.
///
/// An ordered array of these rather than a keyed map, and not only to satisfy
/// `scripts/lint/no-wire-codable.sh`: the order files arrive in is the order they are written, so
/// a failed write can be reported against a position rather than against whichever key a
/// dictionary happened to yield first.
public struct ExtensionFile: Sendable, Hashable {
    public let path: String
    public let text: String

    public init(path: String, text: String) {
        self.path = path
        self.text = text
    }
}

/// One entry as it exists on disk right now.
///
/// Every member is a reading rather than a record: `title` and `description` come from the entry's
/// own descriptor file, and `files` and `bytes` come from walking the entry's directory. Nothing
/// here is remembered from the request that added it, which is what makes a `GET` after a change
/// made behind the router's back report the change (`DESIGN.md` §6).
public struct ExtensionRecord: Sendable, Hashable {
    public let name: String
    /// The name the descriptor gives itself, which is not always the directory it sits in.
    public let title: String?
    public let description: String?
    public let files: Int
    public let bytes: Int
    /// Why this entry could not be read as its kind, or `nil` when it read cleanly.
    ///
    /// An entry with a problem is still **listed**. Dropping it would report a store with a broken
    /// entry as a store with one fewer entry, and the count is the number this route exists to
    /// answer.
    public let problem: String?

    public init(
        name: String,
        title: String? = nil,
        description: String? = nil,
        files: Int = 0,
        bytes: Int = 0,
        problem: String? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.files = files
        self.bytes = bytes
        self.problem = problem
    }
}

/// Every entry of one kind, plus whether the reading could be taken at all.
///
/// `unreadable` is separate from an empty `records` on purpose, and it is the same distinction
/// `GET /harnesses` draws: a store nobody has written to yet and a store the router could not open
/// are both "no rows", and only one of them is a count.
public struct ExtensionListing: Sendable {
    public let kind: ExtensionKind
    public let root: String
    public let records: [ExtensionRecord]
    public let unreadable: String?

    public init(
        kind: ExtensionKind, root: String, records: [ExtensionRecord], unreadable: String? = nil
    ) {
        self.kind = kind
        self.root = root
        self.records = records
        self.unreadable = unreadable
    }
}

/// A refusal, carrying the status the control API answers with and a stable slug beside the
/// sentence.
///
/// The slug is what a caller branches on. The sentence is what a person reads, and it names the
/// offending path or descriptor rather than saying that something was wrong.
public struct ExtensionRefusal: Sendable, Hashable {
    public let status: Int
    public let reason: String
    public let message: String

    public init(status: Int, reason: String, message: String) {
        self.status = status
        self.reason = reason
        self.message = message
    }
}

public enum ExtensionWriteOutcome: Sendable {
    case added(ExtensionRecord)
    case refused(ExtensionRefusal)
}

public enum ExtensionRemoveOutcome: Sendable {
    /// The directory the entry's bytes are now at. Nothing is deleted, so this path is the whole
    /// of what makes a removal reversible, and it is on the wire rather than in a log.
    case removed(String)
    case refused(ExtensionRefusal)
}

/// Holding skills, plugins and marketplaces the way the config file holds servers.
///
/// A port rather than a direct call, for the reason every other port in this directory is one: the
/// interesting states — an unreadable directory, an entry whose descriptor rotted after it was
/// added, a write that fails halfway — are states a developer's own machine will not enter on
/// request, and the in-process differential oracle has no store at all.
public protocol ExtensionStoring: Sendable {
    func list(_ kind: ExtensionKind) -> ExtensionListing
    func read(_ kind: ExtensionKind, name: String) -> ExtensionRecord?
    func add(_ kind: ExtensionKind, name: String, files: [ExtensionFile]) -> ExtensionWriteOutcome
    func remove(_ kind: ExtensionKind, name: String) -> ExtensionRemoveOutcome
}
