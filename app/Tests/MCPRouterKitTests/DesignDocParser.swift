import Foundation

/// Reads the token tables out of `DESIGN.md` so a test can compare them against the code.
///
/// The parser is **per-table and heading-driven** rather than applying one column rule to
/// everything, because §2's tables genuinely differ in shape — the label-tier table has four
/// columns (the third is a measured contrast ratio, which is documentation rather than a token),
/// while the grounds and colour tables have three.
///
/// Every cell is normalised before it is compared. Each normalisation below exists because of a
/// specific construct in the real document, not defensively:
///
/// - **Markdown emphasis is stripped from every cell.** The `Body` row is written `| **Body** |
///   **13** | **16** | Semibold |` — the emphasis is on the numbers as well as the name, so
///   stripping it only from names would fail on the size column.
/// - **Shorthand hex is expanded.** The document writes `#FFF`; the code stores `#FFFFFF`. They
///   are the same colour and must not read as drift.
/// - **Percentages become fractions.** `@7.5%` is `0.075`.
/// - **Header and separator rows are skipped explicitly**, not by accident of parsing.
///
/// The point of all of this is that an edit to `DESIGN.md`'s prose, spacing or typography cannot
/// produce a false failure, while a change to a value always produces a real one.
enum DesignDocParser {
    struct ColorRow: Equatable {
        let name: String
        let hex: String
        let opacity: Double
        let lightHex: String
        let lightOpacity: Double
    }

    struct TypeRow: Equatable {
        let role: String
        let size: Double
        let lineHeight: Double
        let emphasis: String
    }

    struct MetricRow: Equatable {
        let element: String
        let leadingScalar: Double?
    }

    // MARK: - Locating the document

    /// Walks up from this source file to the repository root and returns `DESIGN.md`.
    ///
    /// Throws rather than returning nil: a parity test that cannot find the document it is meant
    /// to compare against must fail loudly. Silently skipping is how a gate starts lying.
    static func designDocURL(from filePath: String = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let candidate = dir.appendingPathComponent("DESIGN.md")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        throw ParseError.documentNotFound(startingFrom: filePath)
    }

    enum ParseError: Error, CustomStringConvertible {
        case documentNotFound(startingFrom: String)
        case sectionNotFound(String)
        case unparsableCell(row: String, cell: String)
        case duplicateHeader(String)
        case headerMissing(String)
        case columnMissing(String, String)
        case rowTooShort(row: String, want: String)

        var description: String {
            switch self {
            case let .documentNotFound(from):
                "DESIGN.md not found walking up from \(from)"
            case let .sectionNotFound(heading):
                "DESIGN.md section not found: \(heading)"
            case let .unparsableCell(row, cell):
                "could not parse cell '\(cell)' in row: \(row)"
            case let .duplicateHeader(name):
                "DESIGN.md table has two '\(name)' columns — which one is the value is undefined"
            case let .headerMissing(heading):
                "a token row appeared under '\(heading)' before any header row"
            case let .columnMissing(name, heading):
                "DESIGN.md table under '\(heading)' has no '\(name)' column"
            case let .rowTooShort(row, want):
                "row has no cell for '\(want)': \(row)"
            }
        }
    }

    // MARK: - Normalisation

    /// Strips markdown emphasis, inline code backticks and non-breaking spaces.
    static func normalise(_ cell: String) -> String {
        var s = cell.replacingOccurrences(of: "\u{00A0}", with: " ")
        s = s.replacingOccurrences(of: "`", with: "")
        // Remove **bold**, *italic* and _italic_ markers wherever they appear in the cell.
        for marker in ["**", "*", "__", "_"] {
            s = s.replacingOccurrences(of: marker, with: "")
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// `#FFF` and `#FFFFFF` are the same colour; canonicalise to six upper-case digits.
    ///
    /// Extracts the hex **by syntax** rather than by taking the first space-delimited token,
    /// because the label-tier rows carry the alpha in the same cell as the colour and the spacing
    /// between them is not meaningful: `#FFF @7.5%` and `#FFF@7.5%` are the same value, and a
    /// parser that split on whitespace would fail the second one — a false failure caused by an
    /// edit that changed nothing.
    static func canonicalHex(_ raw: String) -> String? {
        let s = normalise(raw).uppercased()
        guard let hash = s.firstIndex(of: "#") else { return nil }
        var digits = ""
        for ch in s[s.index(after: hash)...] {
            guard ch.isHexDigit, digits.count < 6 else { break }
            digits.append(ch)
        }
        switch digits.count {
        case 3: return "#" + digits.map { "\($0)\($0)" }.joined()
        case 6: return "#" + digits
        default: return nil
        }
    }

    /// The alpha written alongside a colour, as a fraction. Nil when the cell states none, which
    /// means fully opaque. Whitespace around the `@` is not significant.
    static func opacity(in raw: String) -> Double? {
        let s = normalise(raw)
        guard let at = s.firstIndex(of: "@") else { return nil }
        var number = ""
        for ch in s[s.index(after: at)...] {
            if ch.isNumber || ch == "." { number.append(ch) } else if ch == " ", number.isEmpty {
                continue
            } else {
                break
            }
        }
        guard let value = Double(number) else { return nil }
        return value / 100.0
    }

    /// The first number appearing in a cell, or nil when the cell does not begin with one.
    static func leadingScalar(_ raw: String) -> Double? {
        let s = normalise(raw)
        var digits = ""
        for ch in s {
            if ch.isNumber || (ch == "." && !digits.isEmpty) {
                digits.append(ch)
            } else if digits.isEmpty {
                return nil // the cell starts with prose, not a value
            } else {
                break
            }
        }
        return Double(digits)
    }

    /// Splits a markdown table row into normalised cells, or nil for a separator row.
    ///
    /// **Interior empty cells are preserved.** An earlier version filtered every empty cell out
    /// after splitting, which silently shifted the index of every column to its right — so one
    /// blank cell anywhere in a row made the parser read its neighbour's value and report it as the
    /// token's own. That is the same class of defect as the silent-empty read this repo already
    /// records in `SWIFT_PRACTICES.md` §2: a failure mode that looks like data rather than an
    /// error. Only the empty fields either side of the leading and trailing pipes are dropped,
    /// because those are punctuation rather than columns.
    static func cells(of line: String) -> [String]? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|") else { return nil }
        var parts = t.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        parts.removeFirst() // always empty: the field before the leading pipe
        if t.hasSuffix("|"), !parts.isEmpty { parts.removeLast() }
        let normalised = parts.map { normalise($0) }
        guard !normalised.isEmpty else { return nil }
        // A separator row is only dashes and colons. An empty cell satisfies that vacuously, so a
        // row of nothing but empties is treated as structure too — which is what it is.
        if normalised.allSatisfy({ $0.allSatisfy { c in c == "-" || c == ":" } }) { return nil }
        return normalised
    }

    /// Maps a header row's column names to their indices, lower-cased.
    ///
    /// Duplicates throw rather than resolving to one of them: `| Token | Dark | Dark |` is a
    /// document bug, and picking either column silently would make the check pass while comparing
    /// the wrong thing.
    static func headerIndices(_ header: [String]) throws -> [String: Int] {
        var map: [String: Int] = [:]
        for (i, name) in header.enumerated() {
            let key = name.lowercased()
            guard key.isEmpty == false else { continue }
            if map[key] != nil { throw ParseError.duplicateHeader(key) }
            map[key] = i
        }
        return map
    }

    // MARK: - Extraction

    /// The lines of the table that follows the given `###` sub-heading inside §2.
    private static func tableLines(in text: String, under heading: String) throws -> [String] {
        let lines = text.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("### " + heading.lowercased())
        }) else {
            throw ParseError.sectionNotFound(heading)
        }
        var out: [String] = []
        var seenTable = false
        for line in lines[(start + 1)...] {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") { break } // next heading ends the section
            if t.hasPrefix("|") { seenTable = true; out.append(line); continue }
            if seenTable, t.isEmpty { continue } // a blank line may separate two tables
            if seenTable, !t.hasPrefix("|"), !out.isEmpty { continue }
        }
        return out
    }

    /// Colour tokens: every row across §2 whose first cell is a `--name` token.
    ///
    /// Columns are resolved **by header name, per table**, never by position. The tables under §2
    /// do not share a shape — the label-tier and colour tables carry a measured-contrast column
    /// that the grounds table does not — and an earlier version read `c[1]` unconditionally with a
    /// comment noting that any further column "is ignored by position". That is precisely what made
    /// adding a Light column unsafe: it would have been read by nobody and drifted unwatched, which
    /// is the one failure the parity suite exists to prevent.
    static func colorRows(in text: String) throws -> [ColorRow] {
        var rows: [ColorRow] = []
        for heading in ["Grounds and lines", "Label tiers", "Colour"] {
            var columns: [String: Int]?
            for line in try tableLines(in: text, under: heading) {
                guard let c = cells(of: line) else { continue }

                // A row that does not name a token is a header — take its column map and move on.
                guard c.first?.hasPrefix("--") == true else {
                    columns = try headerIndices(c)
                    continue
                }
                guard let columns else { throw ParseError.headerMissing(heading) }

                func cell(_ name: String) throws -> String {
                    guard let i = columns[name] else { throw ParseError.columnMissing(name, heading) }
                    guard i < c.count else { throw ParseError.rowTooShort(row: line, want: name) }
                    return c[i]
                }

                let dark = try cell("dark")
                let light = try cell("light")
                guard let darkHex = canonicalHex(dark) else {
                    throw ParseError.unparsableCell(row: line, cell: dark)
                }
                guard let lightHex = canonicalHex(light) else {
                    throw ParseError.unparsableCell(row: line, cell: light)
                }
                rows.append(ColorRow(
                    name: c[0],
                    hex: darkHex,
                    opacity: opacity(in: dark) ?? 1.0,
                    lightHex: lightHex,
                    lightOpacity: opacity(in: light) ?? 1.0
                ))
            }
        }
        return rows
    }

    /// The eight type roles. First cell is a plain role name, not a `--token`.
    ///
    /// Rows are selected **structurally** — a data row is one whose size and line-height columns
    /// parse as numbers — rather than by checking the role against `TypeToken`. Filtering by the
    /// code's own cases would make this parser blind in exactly the direction it exists to check:
    /// delete a role from the enum and the parser would stop returning that documented row, so the
    /// document-to-code assertion would pass by seeing nothing. The header row is skipped by the
    /// same structural rule, since `Size` does not parse as a number.
    static func typeRows(in text: String) throws -> [TypeRow] {
        var rows: [TypeRow] = []
        for line in try tableLines(in: text, under: "Type") {
            guard let c = cells(of: line), c.count >= 4 else { continue }
            guard let size = Double(c[1]), let lh = Double(c[2]) else { continue }
            rows.append(TypeRow(role: c[0], size: size, lineHeight: lh, emphasis: c[3]))
        }
        return rows
    }

    /// Chrome geometry. `leadingScalar` is nil for rows whose value is prose.
    static func metricRows(in text: String) throws -> [MetricRow] {
        var rows: [MetricRow] = []
        for line in try tableLines(in: text, under: "Chrome geometry") {
            guard let c = cells(of: line), c.count >= 2 else { continue }
            if c[0] == "Element" { continue }
            rows.append(MetricRow(element: c[0], leadingScalar: leadingScalar(c[1])))
        }
        return rows
    }
}
