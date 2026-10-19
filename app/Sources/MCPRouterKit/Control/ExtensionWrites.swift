import Foundation

// The write shapes for the router's extension store: promote and keep under an entry, and undo a promotion.
//
// Each is thin on purpose. A write's reply names what the router did, and the board reads only the
// members it draws. The board repaints from its own `GET /skills` after a write, so the reply is never
// the picture of the board. That keeps a control from reporting its own success.

/// The kinds the router's extension store holds, by the path segment its routes use.
public enum StoredExtensionKind: String, Codable, Hashable, Sendable, CaseIterable {
    case skills
    case plugins
    case marketplaces
}

public extension PluginOrigin {
    /// The name the router holds a plugin under: `<plugin>@<marketplace>`, which is Claude's own key for it.
    /// A bare plugin name is ambiguous, because one name can be supplied by two marketplaces at once.
    var storeName: String { "\(plugin)@\(marketplace)" }
}

/// One file of an entry, as the store takes it.
public struct ExtensionFileBody: Codable, Hashable, Sendable {
    public var path: String
    public var text: String

    public init(path: String, text: String) {
        self.path = path
        self.text = text
    }
}

/// What a promotion answered: the version now installed, and the reference an undo needs.
public struct PromotionAck: Codable, Hashable, Sendable {
    public var promoted: String
    public var kind: StoredExtensionKind
    public var pluginVersion: String
    /// The version the promotion replaced, or nil when the replaced entry declared none.
    public var replaced: String?
    /// The reference an undo is given to find the copy this promotion replaced.
    public var restore: String
}

/// What an undo answered: the version put back, and the promoted version it withdrew.
public struct UndoAck: Codable, Hashable, Sendable {
    public var restored: String
    public var kind: StoredExtensionKind
    /// The version now installed. Nil when the restored entry declares none.
    public var version: String?
    public var withdrawn: String
}

/// What a keep answered: the held version the router recorded.
public struct KeepAck: Codable, Hashable, Sendable {
    public var kept: String
    public var kind: StoredExtensionKind
    public var pluginVersion: String
}
