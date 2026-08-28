import Foundation

/// What an entry's descriptor file says about it, or why it could not be read as one.
///
/// One rule, read twice. ``ExtensionStoring/add(_:name:files:)`` applies it to the bytes in the
/// request before anything is written, and ``ExtensionStoring/list(_:)`` applies it to the bytes on
/// disk on every read. A second, laxer rule on the read side is how a store starts reporting
/// entries it would refuse to accept today.
public enum ExtensionDescriptor {
    public struct Reading: Sendable, Hashable {
        public let title: String
        public let description: String?
    }

    public enum Outcome: Sendable, Hashable {
        case read(Reading)
        /// The sentence a refusal or a listed problem carries. It names the file and what was
        /// wrong with it, because "malformed" on its own tells the reader nothing to act on.
        case unreadable(String)
    }

    public static func read(_ kind: ExtensionKind, text: String) -> Outcome {
        switch kind {
        case .skills: readFrontmatter(text, file: kind.descriptorPath)
        case .plugins: readJSON(text, file: kind.descriptorPath, requiringPlugins: false)
        case .marketplaces: readJSON(text, file: kind.descriptorPath, requiringPlugins: true)
        }
    }

    // MARK: - SKILL.md

    /// The YAML frontmatter a skill carries: a `---` line, `key: value` lines, a closing `---`.
    ///
    /// Deliberately not a YAML parser. The frontmatter this reads is the one Claude's own skills
    /// carry — measured on 23 of them on 2026-08-28, every one is a flat block of `key: value`
    /// with `name` and `description` present — and a general parser would accept nested shapes
    /// this store has nowhere to put. A key it does not recognise is ignored rather than refused,
    /// so a skill carrying extra frontmatter is held rather than rejected.
    private static func readFrontmatter(_ text: String, file: String) -> Outcome {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)[...]
        guard let first = lines.first, first.trimmed == "---" else {
            return .unreadable("\(file) does not open with a --- frontmatter block")
        }
        lines = lines.dropFirst()
        var title: String?
        var description: String?
        var closed = false
        for line in lines {
            if line.trimmed == "---" {
                closed = true
                break
            }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex ..< separator]).trimmed
            let value = String(line[line.index(after: separator)...]).trimmed
            if key == "name", !value.isEmpty { title = value }
            if key == "description", !value.isEmpty { description = value }
        }
        guard closed else {
            return .unreadable("\(file)'s frontmatter block is never closed by a second ---")
        }
        guard let title else {
            return .unreadable("\(file)'s frontmatter carries no name")
        }
        return .read(Reading(title: title, description: description))
    }

    // MARK: - plugin.json and marketplace.json

    /// `JSONParser`, never `JSONSerialization` — the same constraint every other reader in this
    /// router works under, and `scripts/lint/no-wire-codable.sh` enforces it over this directory.
    private static func readJSON(
        _ text: String, file: String, requiringPlugins: Bool
    ) -> Outcome {
        guard let parsed = try? JSONParser.parse(text) else {
            return .unreadable("\(file) is not valid JSON")
        }
        guard case .object = parsed else {
            return .unreadable("\(file) is not a JSON object")
        }
        guard let title = parsed.member("name")?.asString?.string, !title.isEmpty else {
            return .unreadable("\(file) carries no name")
        }
        if requiringPlugins, parsed.member("plugins")?.asArray == nil {
            return .unreadable("\(file) carries no plugins array")
        }
        let description = parsed.member("description")?.asString?.string
        return .read(Reading(
            title: title,
            description: (description?.isEmpty ?? true) ? nil : description
        ))
    }
}

extension StringProtocol {
    /// Whitespace-trimmed, for the frontmatter scan. Named rather than repeated at four call
    /// sites, where one of them forgetting it is a silent divergence in what counts as a key.
    var trimmed: String {
        trimmingCharacters(in: .whitespaces)
    }
}
