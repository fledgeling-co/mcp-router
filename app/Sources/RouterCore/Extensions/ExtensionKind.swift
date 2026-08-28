import Foundation

/// The three kinds of extension the router can hold besides an MCP server.
///
/// Measured on this machine on 2026-08-28, each kind is a **directory per entry** under a
/// directory Claude owns, and each entry says what it is in one file of its own:
///
/// | kind | Claude's location | the file that names it |
/// |---|---|---|
/// | skills | `~/.claude/skills/<name>/` | `SKILL.md` frontmatter |
/// | plugins | `~/.claude/plugins/cache/<marketplace>/<name>/<version>/` | `.claude-plugin/plugin.json` |
/// | marketplaces | `~/.claude/plugins/marketplaces/<name>/` | `.claude-plugin/marketplace.json` |
///
/// The router's own store is **flat per kind** — `<root>/<kind>/<name>/` — even though Claude's
/// plugin cache nests by marketplace and then by version. Reproducing that nesting here would be
/// porting a layout before anything has to interoperate with it; R30 owns moving entries out of
/// Claude and is where the two layouts have to meet.
public enum ExtensionKind: String, Sendable, CaseIterable {
    case skills
    case plugins
    case marketplaces

    /// The path, relative to one entry's own directory, of the file that says what the entry is.
    ///
    /// Every read of an entry goes through this file and nothing else. That is what makes
    /// ``ExtensionStoring/list(_:)`` a reading of the disk rather than of a registry: there is no
    /// index anywhere in the store, so there is nothing that can disagree with the bytes.
    public var descriptorPath: String {
        switch self {
        case .skills: "SKILL.md"
        case .plugins: ".claude-plugin/plugin.json"
        case .marketplaces: ".claude-plugin/marketplace.json"
        }
    }

    /// What one entry of this kind is called in a sentence — `no skill named "x"`, matching the
    /// `no server named "x"` the control API already answers with.
    public var singular: String {
        switch self {
        case .skills: "skill"
        case .plugins: "plugin"
        case .marketplaces: "marketplace"
        }
    }
}

/// What a name and a relative file path are allowed to be.
///
/// Both rules exist to keep a request from naming a path outside the store. `..`, an absolute
/// path, an empty segment and a separator smuggled through percent-encoding all have to be
/// refused **before** any directory is created, because a refusal after the first write is the
/// half-registered entry this item is asked to make impossible.
public enum ExtensionNaming {
    /// Long enough for every name measured on this machine (the longest is 34 characters) with
    /// room to spare, and short enough that a name cannot be used to push a path past a
    /// filesystem limit.
    public static let maximumNameLength = 128

    /// One path segment: ASCII letters, digits, `.`, `_` and `-`, and never `.` or `..` alone.
    ///
    /// `.claude-plugin` is a real segment in two of the three descriptor paths, so a leading dot
    /// has to be allowed here. It is *not* allowed in an entry name — see ``isWellFormedName(_:)``.
    public static func isWellFormedSegment(_ segment: String) -> Bool {
        guard !segment.isEmpty, segment != ".", segment != ".." else { return false }
        return segment.allSatisfy { character in
            character.isASCII
                && (character.isLetter || character.isNumber || character == "."
                    || character == "_" || character == "-")
        }
    }

    /// An entry's own name: a single well-formed segment that does not begin with a dot.
    ///
    /// The leading-dot refusal is load-bearing rather than tidy. The store keeps its removals at
    /// `<root>/.removed` and stages a write at `<root>/.staging`, both siblings of the three kind
    /// directories; an entry allowed to be called `.removed` could be written over the one place
    /// this item promises is recoverable.
    public static func isWellFormedName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= maximumNameLength, !name.hasPrefix(".") else {
            return false
        }
        return isWellFormedSegment(name)
    }

    /// A relative file path inside one entry: at least one segment, every segment well-formed.
    public static func isWellFormedRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !segments.isEmpty else { return false }
        return segments.allSatisfy { isWellFormedSegment(String($0)) }
    }
}
