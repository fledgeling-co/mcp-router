import Foundation

/// What version a capability is at, and **who established it**.
///
/// The provenance is in the case rather than in a comment beside the string, for the reason
/// ``ClientProcessName`` gives one directory over: a reader can then tell a reading from a naming
/// claim without trusting any prose, and a later `switch` cannot lose the distinction by accident.
///
/// It matters here because the three cases are not three degrees of confidence in one answer —
/// they are three different answers. `declared` is a number the entry gives itself. `derived` is
/// not a version at all: it is a digest, and it pins evidence to *these bytes* rather than to a
/// name. `unknown` credits nothing.
///
/// **Measured on this machine, 2026-08-29: 13 of 22 skills under `~/.claude/skills` declare
/// `version:` in their frontmatter and nine do not**, while all 127 records in
/// `plugins/installed_plugins.json` carry one. So `derived` is the ordinary case for a hand-written
/// skill rather than a fallback that rarely fires, which is why it is a case here and not a `nil`.
public enum CapabilityVersion: Sendable, Hashable {
    /// Read out of the entry's own descriptor. `from` is the file it was read from, so the claim
    /// can be re-taken rather than believed.
    case declared(String, from: String)
    /// No version is declared anywhere in the entry. The digest is `ExtensionStamp`'s, truncated
    /// for display, and it changes when any byte does.
    case derived(digest: String)
    /// Nothing established it — an unreadable descriptor, or a capability the store does not hold.
    case unknown(reason: String)

    /// What a surface prints. A digest is prefixed so it can never be mistaken for a semver.
    public var display: String {
        switch self {
        case let .declared(version, _): version
        case let .derived(digest): "bytes:\(digest)"
        case .unknown: "not established"
        }
    }

    /// The word a wire member carries beside ``display``, so a consumer branches on the provenance
    /// rather than on the shape of the string.
    public var source: String {
        switch self {
        case .declared: "declared"
        case .derived: "derived"
        case .unknown: "unknown"
        }
    }

    /// Whether evidence may be pinned to this at all. False for ``unknown`` — and a caller that
    /// ignores it is crediting runs to a version nothing established.
    public var isPinnable: Bool {
        if case .unknown = self { return false }
        return true
    }

    /// Why nothing may be pinned, in the words a surface can show. Nil when something may.
    public var unpinnableReason: String? {
        if case let .unknown(reason) = self { return reason }
        return nil
    }
}

/// Reading a capability's current version off the store, and nothing else.
///
/// **It reads the entry that is there now.** That is the whole of what a filesystem can answer, and
/// it is why ``VersionAtRun`` exists: the version a capability is at today is not the version it was
/// at when a run happened last month, and only the boundary set can say whether the two coincide.
public enum CapabilityVersionReading {
    /// The digest prefix length. Twelve hex characters — 48 bits, enough that two entries on one
    /// machine colliding is not a thing that happens, and short enough to sit in a table column.
    public static let digestPrefixLength = 12

    /// The version of one entry of the router's own store.
    ///
    /// - Parameter descriptor: the entry's descriptor text, already read.
    /// - Parameter digest: the entry's tree digest, or nil when the tree could not be measured.
    public static func read(
        _ kind: ExtensionKind, descriptor: String?, digest: String?, path: String
    ) -> CapabilityVersion {
        if let descriptor, let declared = declaredVersion(kind, in: descriptor) {
            return .declared(declared, from: path)
        }
        if let digest, !digest.isEmpty {
            return .derived(digest: String(digest.prefix(digestPrefixLength)))
        }
        if descriptor == nil {
            return .unknown(reason: "\(path) is missing or is not UTF-8")
        }
        return .unknown(reason: "\(path) declares no version and its bytes could not be measured")
    }

    /// The declared version, by the rule the kind's own descriptor format uses.
    ///
    /// Two formats, because the two files are two formats: a skill's `SKILL.md` carries YAML
    /// frontmatter and a plugin's or marketplace's descriptor is JSON. Neither is guessed at from
    /// the other — a `version:` line found anywhere in a JSON file would be a match inside a string
    /// literal, and a `"version":` found in prose would be a match inside a code fence.
    static func declaredVersion(_ kind: ExtensionKind, in descriptor: String) -> String? {
        switch kind {
        case .skills: frontmatterVersion(descriptor)
        case .plugins, .marketplaces: jsonVersion(descriptor)
        }
    }

    /// `version:` inside the leading `---` fenced block, and nowhere else.
    ///
    /// Scoped to the frontmatter deliberately. Every SKILL.md in this repository's own plugin tree
    /// is a document *about* versions among other things, and a scan of the whole file matches a
    /// sentence rather than a declaration.
    private static func frontmatterVersion(_ text: String) -> String? {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }
        lines.removeFirst()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { return nil }
            guard trimmed.hasPrefix("version:") else { continue }
            let value = trimmed.dropFirst("version:".count)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// The top-level `version` member of a descriptor that is JSON.
    ///
    /// Parsed with this repository's own parser rather than matched with a regular expression: a
    /// nested `"version"` under some other member is not this file's version, and only a parse can
    /// tell the two apart.
    private static func jsonVersion(_ text: String) -> String? {
        guard let parsed = try? JSONParser.parse(text),
              let version = parsed.member("version")?.asString?.string,
              !version.isEmpty
        else { return nil }
        return version
    }
}
