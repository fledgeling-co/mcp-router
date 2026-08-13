import Foundation

/// One tool's shape, as the diff reports it.
///
/// `description` is the raw member: `nil` is absent, `.null` is an explicit JSON null, and the two
/// are different because the reference compares them with `!==`. `schema` is the stringified input
/// schema, and it is absent on a removal — the reference only records the old description there.
public struct ToolShape: Sendable, Hashable {
    public let description: JSONValue?
    public let schema: String?

    public init(description: JSONValue?, schema: String?) {
        self.description = description
        self.schema = schema
    }
}

public struct ToolChange: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case added
        case removed
        case changed
    }

    public let kind: Kind
    public let name: JSONValue?
    public let before: ToolShape?
    public let after: ToolShape?
    /// Codepoints a reader cannot see but a model can read. Named, never silently kept. `nil` when
    /// there are none, matching the reference's omitted key.
    public let invisible: [String]?
}

/// What changed between an approved surface and a pending one, tool by tool.
public enum DiffTools {
    /// The exact codepoints the reference's regular expression matches.
    ///
    /// Extracted from the compiled reference rather than transcribed from its source, where they
    /// appear as the invisible characters themselves. Note the gap: `U+2065`–`U+2069` are **not**
    /// here, so `U+2066 LEFT-TO-RIGHT ISOLATE` is not reported. A more thorough detector would be a
    /// divergence, and R4 would read it as a regression — widening this set is a real item, and it
    /// belongs after the parity gate rather than inside the port.
    static let invisibleRanges: [ClosedRange<UInt16>] = [
        0x00AD ... 0x00AD, // SOFT HYPHEN
        0x180E ... 0x180E, // MONGOLIAN VOWEL SEPARATOR
        0x200B ... 0x200F, // ZERO WIDTH SPACE through RIGHT-TO-LEFT MARK
        0x202A ... 0x202E, // LEFT-TO-RIGHT EMBEDDING through RIGHT-TO-LEFT OVERRIDE
        0x2060 ... 0x2064, // WORD JOINER through INVISIBLE PLUS
        0x206A ... 0x206F, // INHIBIT SYMMETRIC SWAPPING through NOMINAL DIGIT SHAPES
        0xFEFF ... 0xFEFF // ZERO WIDTH NO-BREAK SPACE
    ]

    /// Every invisible codepoint in the text, deduplicated by **first occurrence** and formatted
    /// `U+XXXX`. `nil` rather than an empty array when there are none, because the reference omits
    /// the key entirely.
    ///
    /// Scans UTF-16 code units directly. Every range above is inside the BMP, so no surrogate pair
    /// can fall in one, and scanning units avoids a trip through `String` that would normalise the
    /// very text being inspected.
    static func invisibleIn(_ text: JSONValue?) -> [String]? {
        guard case let .string(value)? = text else { return nil }
        var seen: [UInt16] = []
        for unit in value.units where invisibleRanges.contains(where: { $0.contains(unit) }) {
            if !seen.contains(unit) { seen.append(unit) }
        }
        guard !seen.isEmpty else { return nil }
        return seen.map { "U+" + String(format: "%04X", $0) }
    }

    /// The diff.
    ///
    /// Three orderings are the reference's and are preserved: added and changed tools come first in
    /// `after` order, removals follow in `before` order, and a duplicate name collapses to **the
    /// last tool at the first name's position** — which is what building a `Map` from an array
    /// does.
    public static func diff(before: [CachedTool], after: [CachedTool]) -> [ToolChange] {
        let old = byName(before)
        let new = byName(after)
        var out: [ToolChange] = []

        for (name, tool) in new {
            let nextShape = shape(of: tool)
            guard let previous = old.first(where: { $0.name == name })?.tool else {
                out.append(
                    ToolChange(
                        kind: .added,
                        name: name,
                        before: nil,
                        after: nextShape,
                        // Only the NEW description is inspected. A tool that is being removed, or
                        // whose old description carried an invisible codepoint, is not reported —
                        // what matters is what is about to be served.
                        invisible: invisibleIn(tool.rawMember("description"))
                    )
                )
                continue
            }
            let previousShape = shape(of: previous)
            if previousShape != nextShape {
                out.append(
                    ToolChange(
                        kind: .changed,
                        name: name,
                        before: previousShape,
                        after: nextShape,
                        invisible: invisibleIn(tool.rawMember("description"))
                    )
                )
            }
        }

        for (name, tool) in old where !new.contains(where: { $0.name == name }) {
            out.append(
                ToolChange(
                    kind: .removed,
                    name: name,
                    // A removal records the old description and **no schema**.
                    before: ToolShape(description: tool.rawMember("description"), schema: nil),
                    after: nil,
                    invisible: nil
                )
            )
        }
        return out
    }

    private static func shape(of tool: CachedTool) -> ToolShape {
        ToolShape(
            description: tool.rawMember("description"),
            schema: JSStringify.compact(tool.inputSchemaValue ?? .object([]))
        )
    }

    /// `new Map(tools.map(t => [t.name, t]))` — insertion order, last value at the first key's
    /// position.
    private static func byName(_ tools: [CachedTool]) -> [(name: JSONValue?, tool: CachedTool)] {
        var out: [(name: JSONValue?, tool: CachedTool)] = []
        for tool in tools {
            let key = tool.rawMember("name")
            if let index = out.firstIndex(where: { $0.name == key }) {
                out[index].tool = tool
            } else {
                out.append((key, tool))
            }
        }
        return out
    }
}
