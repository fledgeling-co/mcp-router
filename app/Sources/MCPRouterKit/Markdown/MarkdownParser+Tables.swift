import Foundation

/// The table half of the block parser.
///
/// Its own file because `AttributedString(markdown:)` rendering no table at all is half the
/// reason this parser exists — the other half is the fenced code block — so the code that reads
/// one is worth finding without scrolling through the rest.
extension MarkdownParser {
    // MARK: - Tables

    /// Reads a GFM table when the two lines at `index` are a header and a delimiter row.
    ///
    /// Returns nil when they are not, so the caller falls through to a paragraph — a line
    /// containing a pipe is not a table, and treating it as one is how prose ends up in a grid.
    static func readTable(
        _ lines: [String],
        from index: Int,
        limits: MarkdownLimits,
        into blocks: inout [MarkdownBlock]
    ) -> Int? {
        guard index + 1 < lines.count else { return nil }
        let headerCells = tableCells(lines[index])
        guard headerCells.count >= 2 else { return nil }
        guard let alignments = delimiterAlignments(lines[index + 1]),
              alignments.count == headerCells.count
        else { return nil }

        let columns = min(headerCells.count, limits.tableColumns)
        var rows: [[MarkdownInline]] = []
        var cursor = index + 2
        while cursor < lines.count, rows.count < limits.tableRows {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("|") else { break }
            let cells = tableCells(lines[cursor])
            guard !cells.isEmpty else { break }
            // **Padded and truncated to the header's width at parse time.** A ragged table is
            // exactly what a marketplace document produces, and a view that indexes a short row is
            // a crash the document chose. The shape is fixed here, once.
            var row = cells.prefix(columns).map { MarkdownInline(markdown: $0) }
            while row.count < columns {
                row.append(MarkdownInline(literal: ""))
            }
            rows.append(Array(row))
            cursor += 1
        }

        blocks.append(.table(MarkdownTable(
            header: Array(headerCells.prefix(columns).map { MarkdownInline(markdown: $0) }),
            alignments: Array(alignments.prefix(columns)),
            rows: rows
        )))
        return cursor - index
    }

    /// Splits one table line into its cells, dropping the leading and trailing pipes.
    ///
    /// An escaped `\|` is a literal pipe inside a cell rather than a separator — the spelling every
    /// README uses to put a pipe in a code span.
    static func tableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return [] }
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|"), !trimmed.hasSuffix("\\|") { trimmed.removeLast() }

        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in trimmed {
            if escaped {
                current.append(character == "|" ? "|" : "\\\(character)")
                escaped = false
                continue
            }
            if character == "\\" { escaped = true; continue }
            if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            current.append(character)
        }
        if escaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    /// Reads `|---|:--:|---:|` into one alignment per column, or nil when the line is not one.
    static func delimiterAlignments(_ line: String) -> [MarkdownTable.Alignment]? {
        let cells = tableCells(line)
        guard !cells.isEmpty else { return nil }
        var alignments: [MarkdownTable.Alignment] = []
        for cell in cells {
            let body = cell.trimmingCharacters(in: .whitespaces)
            let leading = body.hasPrefix(":")
            let trailing = body.hasSuffix(":")
            let dashes = body.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard dashes.count >= 1, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            alignments.append(leading && trailing ? .center : (trailing ? .trailing : .leading))
        }
        return alignments
    }
}
