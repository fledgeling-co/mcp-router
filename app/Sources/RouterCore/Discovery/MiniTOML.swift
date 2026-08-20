import Foundation

/// Why a TOML file could not be read.
public struct TOMLProblem: Error, Sendable, Equatable, CustomStringConvertible {
    public let line: Int
    public let detail: String

    public var description: String { "line \(line): \(detail)" }
}

/// A deliberately narrow TOML reader — not a TOML implementation.
///
/// It scans line-wise for table headers and deep-parses only the tables under `mcp_servers` or
/// `mcpServers`, which is all this product needs and all it is willing to guess about. The two
/// client CLIs spell the same table differently — `[mcp_servers.docker-mcp]` against
/// `[mcpServers."docker-mcp"]` — so both are read.
///
/// Anything it does not understand is a **named error citing the line**, never a skip. A reader
/// that silently ignores syntax it cannot parse produces a config that looks empty, which is the
/// same defect class as the trap this whole item exists to close. A multi-line string delimiter is
/// the specific case worth naming: skipping past one would let its contents be mistaken for table
/// headers.
public enum MiniTOML {
    public enum Value: Sendable, Hashable {
        case string(String)
        case integer(Int)
        case boolean(Bool)
        case array([Value])

        public var json: JSONValue {
            switch self {
            case let .string(text): .string(JSString(text))
            case let .integer(number): .number(Double(number))
            case let .boolean(flag): .bool(flag)
            case let .array(values): .array(values.map(\.json))
            }
        }
    }

    /// Every table in the document, keyed by its dotted path, in the order they appeared.
    public struct Document: Sendable {
        public var tables: [(path: [String], pairs: [(key: String, value: Value)])]

        public func table(matching path: [String]) -> [(key: String, value: Value)]? {
            tables.first { $0.path == path }?.pairs
        }

        /// Immediate child names of a table path — the server names under `mcp_servers`.
        public func childNames(of prefix: [String]) -> [String] {
            var seen: [String] = []
            for table in tables {
                guard table.path.count == prefix.count + 1,
                      Array(table.path.prefix(prefix.count)) == prefix else { continue }
                let name = table.path[prefix.count]
                if !seen.contains(name) { seen.append(name) }
            }
            return seen
        }
    }

    public static func parse(_ text: String) throws -> Document {
        var scan = Scan(lines: text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        var document = Document(tables: [])

        while let (number, line) = scan.next() {
            if line.isEmpty || line.hasPrefix("#") { continue }
            try refuseMultiLineString(line, number: number)

            if line.hasPrefix("[") {
                try scan.openTable(line, number: number, into: &document)
                continue
            }
            // A key before any table header belongs to the root table, which this reader has no
            // use for; it is skipped rather than errored because every real config has some.
            guard scan.started else { continue }
            // Only the tables that matter are parsed for values. Everything else is passed over,
            // which is what makes a 24,000-line editor config readable without implementing TOML.
            guard isInteresting(scan.currentPath) else { continue }
            try scan.readPair(line, number: number)
        }
        scan.flush(into: &document)
        return document
    }

    static func refuseMultiLineString(_ line: String, number: Int) throws {
        guard line.contains(basicStringDelimiter) || line.contains(literalStringDelimiter) else { return }
        throw TOMLProblem(
            line: number,
            detail: "multi-line strings are not supported by this reader, and skipping one "
                + "could let its contents be read as table headers"
        )
    }

    static let basicStringDelimiter = String(repeating: "\"", count: 3)
    static let literalStringDelimiter = String(repeating: "'", count: 3)

    /// The line cursor plus the table being filled.
    ///
    /// A struct rather than five `var`s in `parse` because reading a value may consume **more than
    /// one line** — a TOML array is allowed to span them, and grok writes its `args` that way — so
    /// the cursor has to be reachable from the code that parses a pair.
    private struct Scan {
        let lines: [String]
        var index = 0
        var currentPath: [String] = []
        var currentPairs: [(key: String, value: Value)] = []
        var started = false

        mutating func next() -> (number: Int, line: String)? {
            guard index < lines.count else { return nil }
            defer { index += 1 }
            return (index + 1, lines[index].trimmingCharacters(in: .whitespaces))
        }

        mutating func flush(into document: inout Document) {
            guard started else { return }
            document.tables.append((currentPath, currentPairs))
            currentPairs = []
        }

        /// `[[array of tables]]` is real TOML this reader does not handle **where it would change
        /// what a server is**, and guessing there would be worse than saying so. Elsewhere it is
        /// an ordinary uninteresting section, and refusing the whole file for it loses every
        /// server in it.
        ///
        /// Measured 2026-08-21: `~/.grok/config.toml` opens with `[[marketplace.sources]]` at line
        /// 8 and declares `[mcp_servers.router]` at line 26. Under the blanket refusal this reader
        /// reported the file unreadable, R7 read that as "no entries", and the plan it derived
        /// offered to ADD a router entry to a harness already wired via HTTP. A reader that fails
        /// on an unrelated section produces a confident wrong answer about the section it can read.
        mutating func openTable(_ line: String, number: Int, into document: inout Document) throws {
            guard line.hasSuffix("]") else {
                throw TOMLProblem(line: number, detail: "unterminated table header")
            }
            let isArrayOfTables = line.hasPrefix("[[")
            guard !isArrayOfTables || line.hasSuffix("]]") else {
                throw TOMLProblem(line: number, detail: "unterminated array-of-tables header")
            }
            flush(into: &document)
            let inner = isArrayOfTables
                ? String(line.dropFirst(2).dropLast(2))
                : String(line.dropFirst().dropLast())
            currentPath = try MiniTOML.parseDottedKey(inner, line: number)
            if isArrayOfTables, MiniTOML.isInteresting(currentPath) {
                throw TOMLProblem(
                    line: number,
                    detail: "arrays of tables are not supported by this reader, and a server "
                        + "declared as one would be read as a single table"
                )
            }
            started = true
        }

        mutating func readPair(_ line: String, number: Int) throws {
            guard let equals = line.firstIndex(of: "=") else {
                throw TOMLProblem(line: number, detail: "expected a key/value pair")
            }
            let key = try MiniTOML.parseKey(
                String(line[line.startIndex ..< equals]).trimmingCharacters(in: .whitespaces),
                line: number
            )
            let text = try joinContinuation(
                String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces),
                number: number
            )
            try currentPairs.append((key, MiniTOML.parseValue(text, line: number)))
        }

        /// A value whose brackets do not balance on its own line continues onto the next ones.
        ///
        /// Measured 2026-08-21: `[mcp_servers.proctor]` in `~/.grok/config.toml` writes its `args`
        /// one element per line. The reader refused the whole file for it, so R7 could state
        /// nothing at all about a harness that is wired and carrying a duplicate. Lines are joined
        /// with a space and handed to the ordinary value parser, so the grammar is unchanged and
        /// only the supply of text is.
        ///
        /// It stops at an unbalanced end of file rather than running off it, and every consumed
        /// line still passes the multi-line-string refusal.
        private mutating func joinContinuation(_ first: String, number: Int) throws -> String {
            guard first.hasPrefix("["), MiniTOML.bracketDepth(first) > 0 else { return first }
            var joined = first
            while MiniTOML.bracketDepth(joined) > 0 {
                guard index < lines.count else {
                    throw TOMLProblem(
                        line: number, detail: "an array opened here and the file ended before it closed"
                    )
                }
                let continuation = lines[index].trimmingCharacters(in: .whitespaces)
                index += 1
                try MiniTOML.refuseMultiLineString(continuation, number: index)
                joined += " " + continuation
            }
            return joined
        }
    }

    /// Open brackets minus closed ones, counting only those outside a quoted string.
    static func bracketDepth(_ text: String) -> Int {
        var depth = 0
        var inQuotes = false
        var quote: Character = "\""
        var escaped = false
        for character in text {
            if inQuotes {
                if escaped {
                    escaped = false
                } else if character == "\\", quote == "\"" {
                    escaped = true
                } else if character == quote {
                    inQuotes = false
                }
                continue
            }
            switch character {
            case "\"", "'":
                inQuotes = true
                quote = character
            case "[": depth += 1
            case "]": depth -= 1
            case "#": return depth
            default: break
            }
        }
        return depth
    }

    static let serverTableNames = ["mcp_servers", "mcpServers"]

    static func isInteresting(_ path: [String]) -> Bool {
        guard let first = path.first else { return false }
        return serverTableNames.contains(first)
    }

    static func parseDottedKey(_ text: String, line: Int) throws -> [String] {
        var segments: [String] = []
        var current = ""
        var inQuotes = false
        var quote: Character = "\""
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if inQuotes {
                if character == quote {
                    inQuotes = false
                } else {
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                inQuotes = true
                quote = character
            } else if character == "." {
                segments.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
            index = text.index(after: index)
        }
        if inQuotes { throw TOMLProblem(line: line, detail: "unterminated quoted key") }
        segments.append(current.trimmingCharacters(in: .whitespaces))
        let cleaned = segments.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { throw TOMLProblem(line: line, detail: "empty table header") }
        return cleaned
    }

    static func parseKey(_ text: String, line: Int) throws -> String {
        guard !text.isEmpty else { throw TOMLProblem(line: line, detail: "empty key") }
        if text.hasPrefix("\"") || text.hasPrefix("'") {
            return try parseDottedKey(text, line: line).joined(separator: ".")
        }
        return text
    }
}
