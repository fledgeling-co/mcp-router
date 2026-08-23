import Foundation

/// A two-part badge, parsed from its URL and re-drawn rather than loaded.
///
/// **The reason this is a type and not an image.** A shields.io badge is a remote PNG or SVG, and
/// fetching one tells `img.shields.io` which capability the person at the machine is reading, at
/// the moment they are deciding whether to install it. That is a request the product will not
/// make, so the badge is parsed into what it *says* and the app draws it.
///
/// **There is no colour on this type, and that is the structural half of an acceptance line.** The
/// brief asks that "the shield colours are the token values rather than the badge's own"; a `tone`
/// with two cases cannot carry `#4c1`, so a view has nothing to reach for except a `ColorToken`.
/// The published greens and blues fail the contrast floor under white text at badge type size,
/// which is what `--shield-good` exists for.
public struct Shield: Equatable, Sendable {
    /// The left cell — what the badge is about. `marketplace`, `checks`, `licence`.
    public var key: String
    /// The right cell — what it says. `fledgeling`, `12 of 12`, `MIT`.
    public var value: String
    /// Which of the app's two fills the value cell takes. Never the badge's own colour.
    public var tone: Tone

    public enum Tone: String, Equatable, Sendable, CaseIterable {
        /// A green-family badge — the "this is fine" reading. Draws in `--shield-good`.
        case good
        /// Everything else. Draws in `--accent-ink`.
        case neutral
    }

    public init(key: String, value: String, tone: Tone) {
        self.key = key
        self.value = value
        self.tone = tone
    }

    /// The hosts this recognises. Both spellings appear in the wild.
    static let hosts: Set<String> = ["img.shields.io", "shields.io", "www.shields.io"]

    /// The colour names and hexes shields.io publishes for its green family.
    ///
    /// Read as a **tone** and then discarded, so no badge colour survives parsing. A badge naming a
    /// colour outside this set is not refused — it is neutral, which is a reading of the badge
    /// rather than a rejection of it.
    static let greenNames: Set<String> = ["brightgreen", "green", "success", "4c1", "97ca00"]

    /// Whether a badge colour reads as green-family. `#` is stripped, so `#4c1` and `4c1` agree.
    static func tone(forColour colour: String) -> Tone {
        let lowered = colour.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return greenNames.contains(lowered) ? .good : .neutral
    }

    /// Parses a shields.io badge URL, or returns nil if this is not one.
    ///
    /// The shape is `/badge/<label>-<message>-<colour>` with shields.io's own escaping: `--` is a
    /// literal hyphen, `__` a literal underscore, and a lone `_` a space. The query string is read
    /// for nothing at all — `?style=`, `&logo=` and `&link=` are discarded, and discarding
    /// `&link=` is also what stops a badge smuggling a second destination past the link rule in
    /// `MarkdownInline`.
    ///
    /// A `/static/v1?label=…&message=…&color=…` badge is the other published spelling and is
    /// deliberately **not** parsed: it appears in no document the mock draws, and per
    /// `spec-M19.md` §2's first assumption an unhandled construct stays visible as its own text
    /// rather than being half-supported.
    public static func parse(_ reference: String) -> Shield? {
        guard let components = URLComponents(string: reference),
              let host = components.host?.lowercased(),
              hosts.contains(host)
        else { return nil }

        // `URLComponents.path` is already percent-decoded, which matters: a badge writes `%20` for
        // the space in `12 of 12`, and reading the raw string would put the escape on screen.
        let segments = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard segments.count == 2, segments[0] == "badge" else { return nil }

        let fields = splitOnSingleHyphens(String(segments[1]))
        guard fields.count == 3 else { return nil }
        return Shield(
            key: unescape(fields[0]),
            value: unescape(fields[1]),
            tone: tone(forColour: fields[2])
        )
    }

    /// Splits on hyphens that are not part of a `--` escape.
    ///
    /// Written as a scan rather than a regular expression because the rule is positional: `--` is
    /// one literal hyphen and does not separate, so `a--b-c-green` is `a-b`, `c`, `green`. A
    /// `split(separator:)` on `-` gets that wrong in a way that silently mislabels a badge.
    static func splitOnSingleHyphens(_ text: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "-" {
                if next < text.endIndex, text[next] == "-" {
                    current.append("--")
                    index = text.index(after: next)
                    continue
                }
                fields.append(current)
                current = ""
                index = next
                continue
            }
            current.append(character)
            index = next
        }
        fields.append(current)
        return fields
    }

    /// Applies shields.io's escaping to one field.
    ///
    /// Ordered so an escape cannot be re-read: `__` and `--` become placeholders no badge can
    /// write, then a lone `_` becomes a space, then the placeholders resolve. Doing it in the
    /// obvious order turns `a__b` into `a b` with the underscore lost.
    static func unescape(_ field: String) -> String {
        let underscore = "\u{0}U\u{0}"
        let hyphen = "\u{0}H\u{0}"
        return field
            .replacingOccurrences(of: "__", with: underscore)
            .replacingOccurrences(of: "--", with: hyphen)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: underscore, with: "_")
            .replacingOccurrences(of: hyphen, with: "-")
    }
}
