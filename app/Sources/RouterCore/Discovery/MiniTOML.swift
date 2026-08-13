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
        var document = Document(tables: [])
        var currentPath: [String] = []
        var currentPairs: [(key: String, value: Value)] = []
        var started = false

        func flush() {
            guard started else { return }
            document.tables.append((currentPath, currentPairs))
            currentPairs = []
        }

        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let number = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.contains("\"\"\"") || line.contains("'''") {
                throw TOMLProblem(
                    line: number,
                    detail: "multi-line strings are not supported by this reader, and skipping one "
                        + "could let its contents be read as table headers"
                )
            }

            if line.hasPrefix("[") {
                guard line.hasSuffix("]") else {
                    throw TOMLProblem(line: number, detail: "unterminated table header")
                }
                // `[[array of tables]]` is real TOML this reader does not handle, and guessing
                // would be worse than saying so.
                if line.hasPrefix("[[") {
                    throw TOMLProblem(
                        line: number,
                        detail: "arrays of tables are not supported by this reader"
                    )
                }
                flush()
                let inner = String(line.dropFirst().dropLast())
                currentPath = try parseDottedKey(inner, line: number)
                started = true
                continue
            }

            guard started else {
                // A key before any table header belongs to the root table, which this reader has no
                // use for; it is skipped rather than errored because every real config has some.
                continue
            }
            // Only the tables that matter are parsed for values. Everything else is passed over,
            // which is what makes a 24,000-line editor config readable without implementing TOML.
            guard isInteresting(currentPath) else { continue }
            guard let equals = line.firstIndex(of: "=") else {
                throw TOMLProblem(line: number, detail: "expected a key/value pair")
            }
            let key = try parseKey(
                String(line[line.startIndex ..< equals]).trimmingCharacters(in: .whitespaces),
                line: number
            )
            let value = try parseValue(
                String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces),
                line: number
            )
            currentPairs.append((key, value))
        }
        flush()
        return document
    }

    static let serverTableNames = ["mcp_servers", "mcpServers"]

    private static func isInteresting(_ path: [String]) -> Bool {
        guard let first = path.first else { return false }
        return serverTableNames.contains(first)
    }

    private static func parseDottedKey(_ text: String, line: Int) throws -> [String] {
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

    private static func parseKey(_ text: String, line: Int) throws -> String {
        guard !text.isEmpty else { throw TOMLProblem(line: line, detail: "empty key") }
        if text.hasPrefix("\"") || text.hasPrefix("'") {
            return try parseDottedKey(text, line: line).joined(separator: ".")
        }
        return text
    }
}
