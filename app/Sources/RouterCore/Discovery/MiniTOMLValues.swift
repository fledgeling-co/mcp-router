import Foundation

/// Value parsing for ``MiniTOML`` — the scalar, string and array forms this reader accepts.
///
/// In its own file so the scanner and the value grammar stay separately readable.
extension MiniTOML {
    static func parseValue(_ text: String, line: Int) throws -> Value {
        // Trailing comments are only stripped outside a string, so a `#` inside a value survives.
        let trimmed = stripComment(text)
        guard !trimmed.isEmpty else { throw TOMLProblem(line: line, detail: "missing value") }

        if trimmed == "true" { return .boolean(true) }
        if trimmed == "false" { return .boolean(false) }

        if let quoted = try quotedValue(trimmed, line: line) { return quoted }
        if trimmed.hasPrefix("[") { return try arrayValue(trimmed, line: line) }
        if let integer = Int(trimmed.replacingOccurrences(of: "_", with: "")) {
            return .integer(integer)
        }
        throw TOMLProblem(line: line, detail: "unsupported value \(trimmed)")
    }

    private static func quotedValue(_ trimmed: String, line: Int) throws -> Value? {
        if trimmed.hasPrefix("\"") {
            return try .string(parseBasicString(trimmed, line: line))
        }
        if trimmed.hasPrefix("'") {
            guard trimmed.count >= 2, trimmed.hasSuffix("'") else {
                throw TOMLProblem(line: line, detail: "unterminated literal string")
            }
            return .string(String(trimmed.dropFirst().dropLast()))
        }
        return nil
    }

    private static func arrayValue(_ trimmed: String, line: Int) throws -> Value {
        guard trimmed.hasSuffix("]") else {
            throw TOMLProblem(
                line: line,
                detail: "an array spanning several lines is not supported by this reader"
            )
        }
        let inner = String(trimmed.dropFirst().dropLast())
        return try .array(splitArray(inner, line: line).map { try parseValue($0, line: line) })
    }

    private static func stripComment(_ text: String) -> String {
        var result = ""
        var inQuotes = false
        var quote: Character = "\""
        var escaped = false
        for character in text {
            if inQuotes {
                result.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\", quote == "\"" {
                    escaped = true
                } else if character == quote {
                    inQuotes = false
                }
                continue
            }
            if character == "\"" || character == "'" {
                inQuotes = true
                quote = character
                result.append(character)
                continue
            }
            if character == "#" { break }
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// The escapes a TOML basic string may carry. Anything else is an error rather than a guess.
    private static func escapeCharacter(_ character: Character) -> Character? {
        switch character {
        case "n": "\n"
        case "t": "\t"
        case "r": "\r"
        case "\"": "\""
        case "\\": "\\"
        default: nil
        }
    }

    private static func parseBasicString(_ text: String, line: Int) throws -> String {
        var result = ""
        var index = text.index(after: text.startIndex)
        var closed = false
        while index < text.endIndex {
            let character = text[index]
            if character == "\\" {
                index = text.index(after: index)
                guard index < text.endIndex
                else { throw TOMLProblem(line: line, detail: "unterminated escape") }
                guard let decoded = escapeCharacter(text[index]) else {
                    throw TOMLProblem(line: line, detail: "unsupported escape \\\(text[index])")
                }
                result.append(decoded)
            } else if character == "\"" {
                closed = true
                index = text.index(after: index)
                break
            } else {
                result.append(character)
            }
            index = text.index(after: index)
        }
        guard closed else { throw TOMLProblem(line: line, detail: "unterminated string") }
        return result
    }

    private static func splitArray(_ text: String, line: Int) throws -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var quote: Character = "\""
        var depth = 0
        for character in text {
            if inQuotes {
                current.append(character)
                if character == quote { inQuotes = false }
                continue
            }
            switch character {
            case "\"", "'":
                inQuotes = true
                quote = character
                current.append(character)
            case "[":
                depth += 1
                current.append(character)
            case "]":
                depth -= 1
                current.append(character)
            case "," where depth == 0:
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default:
                current.append(character)
            }
        }
        if inQuotes { throw TOMLProblem(line: line, detail: "unterminated string in array") }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { parts.append(last) }
        return parts.filter { !$0.isEmpty }
    }
}
