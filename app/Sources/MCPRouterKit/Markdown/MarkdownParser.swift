import Foundation

/// What a document is allowed to cost before it stops being rendered in full.
///
/// Not a security boundary — nothing here executes, so a large document is a slow sheet rather
/// than an exploit — but a denial of the surface is still a way for a marketplace document to make
/// the app useless, and `DiscoverDetailSheet.swift` already caps its description string for
/// exactly this reason. Every cap is stated rather than implicit, and a document that hits one is
/// **told about it** in the block stream rather than being quietly shortened.
public struct MarkdownLimits: Equatable, Sendable {
    /// The most blocks one document may produce.
    public var blocks: Int
    /// The most lines one document may be read from.
    public var lines: Int
    /// The longest a single line may be before it is truncated.
    public var lineLength: Int
    /// The most rows one table may carry, header excluded.
    public var tableRows: Int
    /// The most columns one table may carry.
    public var tableColumns: Int

    public init(
        blocks: Int = 600,
        lines: Int = 6000,
        lineLength: Int = 4000,
        tableRows: Int = 400,
        tableColumns: Int = 24
    ) {
        self.blocks = blocks
        self.lines = lines
        self.lineLength = lineLength
        self.tableRows = tableRows
        self.tableColumns = tableColumns
    }

    public static let standard = MarkdownLimits()
}

/// Turns GitHub-flavoured Markdown into typed blocks.
///
/// **Why there is a parser here at all**, since the platform ships one: `AttributedString(markdown:)`
/// covers the inline runs and renders neither a table nor a fenced code block, and the mock draws
/// both. So the structural half is here and the inline half stays on the system parser — which is
/// what `spec-M19.md` §3.6 settles and tells the planner not to re-open.
///
/// It is line-based rather than a full CommonMark implementation, and the boundary is stated: it
/// recognises the kinds `design/mcp-router-console.html`'s `sh-readme` sheet draws, and anything
/// else becomes `MarkdownBlock.plainText`, visible as its own source. `spec-M19.md` §2's first
/// assumption is that rule — a block that fell back can be seen and reported; a block that was
/// dropped cannot.
///
/// Nothing in here reaches the network, the filesystem or a process. It is a pure function from a
/// string to values, which is what makes the whole of it testable without a running app.
public enum MarkdownParser {
    public static func blocks(
        from source: String,
        limits: MarkdownLimits = .standard
    ) -> [MarkdownBlock] {
        var lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.count > limits.lineLength ? String($0.prefix(limits.lineLength)) : $0 }

        var truncated = false
        if lines.count > limits.lines {
            lines = Array(lines.prefix(limits.lines))
            truncated = true
        }

        var blocks: [MarkdownBlock] = []
        var index = 0
        while index < lines.count, blocks.count < limits.blocks {
            let consumed = block(from: lines, at: index, limits: limits, into: &blocks)
            // A reader that does not advance is an infinite loop, and the arms below each advance
            // on every path. This is the guard that makes that a property rather than a hope.
            index += max(consumed, 1)
        }

        if blocks.count >= limits.blocks || truncated {
            blocks.append(.paragraph(MarkdownInline(
                literal: "This document is longer than the viewer shows. The rest is not rendered."
            )))
        }
        return blocks
    }

    // MARK: - One block

    /// Reads one block starting at `index`, appends it, and returns how many lines it took.
    private static func block(
        from lines: [String],
        at index: Int,
        limits: MarkdownLimits,
        into blocks: inout [MarkdownBlock]
    ) -> Int {
        let line = lines[index]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty { return 1 }

        if let fence = fenceMarker(trimmed) {
            return readFence(lines, from: index, marker: fence, into: &blocks)
        }
        if isThematicBreak(trimmed) {
            blocks.append(.rule)
            return 1
        }
        if let heading = heading(trimmed) {
            blocks.append(heading)
            return 1
        }
        if trimmed.hasPrefix(">") {
            return readQuote(lines, from: index, limits: limits, into: &blocks)
        }
        if let table = readTable(lines, from: index, limits: limits, into: &blocks) {
            return table
        }
        if listMarker(trimmed) != nil {
            return readList(lines, from: index, into: &blocks)
        }
        return readParagraph(lines, from: index, into: &blocks)
    }

    // MARK: - Headings and rules

    /// An ATX heading at level 1, 2 or 3.
    ///
    /// Four hashes or more returns nil and lands in a paragraph as its own text. `DESIGN.md`'s type
    /// ladder has three heading roles above body and the mock draws exactly those three, so a
    /// fourth level has nothing to render as — and inventing one would be a size off the ladder.
    static func heading(_ trimmed: String) -> MarkdownBlock? {
        var level = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index] == "#", level < 4 {
            level += 1
            index = trimmed.index(after: index)
        }
        guard (1 ... 3).contains(level) else { return nil }
        // A space after the hashes is required by CommonMark, and requiring it is what keeps a
        // `#hashtag` at the start of a line from becoming a heading.
        guard index < trimmed.endIndex, trimmed[index] == " " else { return nil }
        let content = trimmed[index...].trimmingCharacters(in: .whitespaces)
        // A closing run of hashes is decoration, not content.
        let text = String(content.reversed().drop { $0 == "#" }.reversed())
            .trimmingCharacters(in: .whitespaces)
        return .heading(level: level, content: MarkdownInline(markdown: text))
    }

    /// `---`, `***` or `___`, three or more, nothing else on the line.
    static func isThematicBreak(_ trimmed: String) -> Bool {
        for marker: Character in ["-", "*", "_"] {
            let stripped = trimmed.filter { !$0.isWhitespace }
            if stripped.count >= 3, stripped.allSatisfy({ $0 == marker }) { return true }
        }
        return false
    }

    // MARK: - Fenced code

    /// The fence marker a line opens, or nil. Both ``` and ~~~ are GFM fences.
    static func fenceMarker(_ trimmed: String) -> String? {
        for marker in ["```", "~~~"] where trimmed.hasPrefix(marker) {
            return marker
        }
        return nil
    }

    /// Reads a fence to its closing marker, or to the end of the document.
    ///
    /// **An unclosed fence swallows the rest of the document, and that is correct** — it is what
    /// every Markdown renderer does, and the alternative is guessing where the author meant it to
    /// end. What the viewer must not do is lose the text, and it does not: the remainder renders as
    /// code.
    private static func readFence(
        _ lines: [String],
        from index: Int,
        marker: String,
        into blocks: inout [MarkdownBlock]
    ) -> Int {
        let opener = lines[index].trimmingCharacters(in: .whitespaces)
        let info = String(opener.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        // The fence character, taken from the marker rather than force-unwrapped out of it. Both
        // markers are three identical characters, so an empty one is unreachable — and a crash on
        // an unreachable branch is still a crash a document could go looking for.
        let fenceCharacter: Character = marker.hasPrefix("`") ? "`" : "~"
        var body: [String] = []
        var cursor = index + 1
        while cursor < lines.count {
            let candidate = lines[cursor].trimmingCharacters(in: .whitespaces)
            if candidate.hasPrefix(marker), candidate.allSatisfy({ $0 == fenceCharacter }) {
                cursor += 1
                blocks.append(.codeFence(
                    language: info.isEmpty ? nil : info,
                    code: body.joined(separator: "\n")
                ))
                return cursor - index
            }
            body.append(lines[cursor])
            cursor += 1
        }
        blocks.append(.codeFence(language: info.isEmpty ? nil : info, code: body.joined(separator: "\n")))
        return cursor - index
    }

    // MARK: - Quotes

    /// Reads consecutive `>` lines and parses their contents as blocks in their own right.
    private static func readQuote(
        _ lines: [String],
        from index: Int,
        limits: MarkdownLimits,
        into blocks: inout [MarkdownBlock]
    ) -> Int {
        var inner: [String] = []
        var cursor = index
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            var content = String(trimmed.dropFirst())
            if content.hasPrefix(" ") { content.removeFirst() }
            inner.append(content)
            cursor += 1
        }
        // Qualified, because the `inout blocks` parameter shadows the static entry point.
        let inside = MarkdownParser.blocks(from: inner.joined(separator: "\n"), limits: limits)
        blocks.append(.blockquote(inside))
        return cursor - index
    }

    // MARK: - Lists

    /// What a list line opens with. A named value rather than a tuple, so the three fields read at
    /// the call site instead of being positions.
    struct ListMarker: Equatable {
        var isOrdered: Bool
        /// The number an ordered item declares. Unread for a bullet.
        var number: Int
        /// The item's own text, marker removed.
        var rest: String
    }

    /// The marker a list line opens with: a bullet, or the number an ordered item declares.
    static func listMarker(_ trimmed: String) -> ListMarker? {
        for bullet: Character in ["-", "*", "+"] where trimmed.hasPrefix("\(bullet) ") {
            return ListMarker(isOrdered: false, number: 0, rest: String(trimmed.dropFirst(2)))
        }
        // `12. text` — digits, a dot or a bracket, then a space. The space is required, so `1.4.2`
        // at the start of a changelog line is not a list.
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let after = trimmed.dropFirst(digits.count)
        guard let delimiter = after.first, delimiter == "." || delimiter == ")" else { return nil }
        let rest = after.dropFirst()
        guard rest.hasPrefix(" ") else { return nil }
        return ListMarker(isOrdered: true, number: Int(digits) ?? 1, rest: String(rest.dropFirst()))
    }

    /// Reads a run of items of one kind. A change of kind ends the list and starts another.
    ///
    /// A continuation line — an indented line under an item, which is how a nested list arrives —
    /// is appended to the item's own text rather than dropped, so nothing disappears at a nesting
    /// level this renderer does not draw.
    private static func readList(
        _ lines: [String],
        from index: Int,
        into blocks: inout [MarkdownBlock]
    ) -> Int {
        guard let first = listMarker(lines[index].trimmingCharacters(in: .whitespaces)) else { return 1 }
        var items: [String] = []
        var cursor = index
        while cursor < lines.count {
            let raw = lines[cursor]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            let isIndented = raw.hasPrefix(" ") || raw.hasPrefix("\t")
            // **Indentation is tested before the marker is.** A nested `  - nested` trims to a
            // valid bullet, so a marker-first read turns a second level into a sibling at the
            // first — which is not a rendering this draws and is not what the document says.
            if !isIndented, let marker = listMarker(trimmed) {
                guard marker.isOrdered == first.isOrdered else { break }
                items.append(marker.rest)
                cursor += 1
                continue
            }
            // A continuation only counts when it is indented; an unindented line is the next block.
            guard isIndented, !items.isEmpty else { break }
            items[items.count - 1] += " " + trimmed
            cursor += 1
        }
        blocks.append(.list(MarkdownList(
            isOrdered: first.isOrdered,
            start: first.isOrdered ? max(first.number, 0) : 1,
            items: items.map { MarkdownInline(markdown: $0) }
        )))
        return cursor - index
    }
}
