import Foundation
@testable import MCPRouterKit

/// The mock's own `literals_outside = 0` property, and the scanning that measures it.
///
/// Split out of `MockTokenParser.swift` because that file had grown past the 400 lines SwiftLint
/// allows. The seam is real rather than arbitrary: everything here answers one question — is there
/// a colour written anywhere in the mock outside its token blocks — and nothing else in the parser
/// asks it. The two run-scanners stay `private` beside the only caller they have.
extension MockTokenParser {
    /// A colour literal found outside every token block.
    struct StrayLiteral: Equatable, Sendable {
        let line: Int
        let text: String
        let context: String
    }

    /// The line ranges the token blocks occupy, so a scan can exclude them by position.
    ///
    /// Computed from the same walk `declarations(in:)` uses rather than hardcoded, because a
    /// hardcoded range silently stops covering the block it names the moment the file is edited.
    static func tokenBlockRanges(in text: String) throws -> [ClosedRange<Int>] {
        let lines = text.components(separatedBy: .newlines)
        guard let metricsStart = lines.firstIndex(where: { $0.contains("<!-- mac-craft:metrics") })
        else { throw ParseError.metricsCommentMissing }
        guard let metricsEnd = lines[metricsStart...].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("-->")
        }) else { throw ParseError.metricsCommentUnterminated }

        return try [(metricsStart + 1) ... (metricsEnd + 1)] + (blocks(in: text).map(\.lines))
    }

    /// Colour literals outside every token block — the mock's own `literals_outside=0` claim,
    /// measured rather than quoted.
    ///
    /// This is the mock side of the token layer's trustworthiness. If a colour can be written
    /// straight into a rule, then the `:root` family is not the whole palette and comparing
    /// against it compares against a subset while reporting a whole.
    static func strayColorLiterals(in text: String) throws -> [StrayLiteral] {
        let ranges = try tokenBlockRanges(in: text)
        let lines = blankingBlockComments(in: text).components(separatedBy: .newlines)
        var out: [StrayLiteral] = []

        for (index, line) in lines.enumerated() {
            let number = index + 1
            if ranges.contains(where: { $0.contains(number) }) { continue }
            for match in hexRuns(in: line) {
                out.append(StrayLiteral(
                    line: number, text: match,
                    context: line.trimmingCharacters(in: .whitespaces)
                ))
            }
            for match in functionalColorRuns(in: line) {
                out.append(StrayLiteral(
                    line: number, text: match,
                    context: line.trimmingCharacters(in: .whitespaces)
                ))
            }
        }
        return out
    }

    /// The same text with every `/* … */` span blanked to spaces, newlines preserved.
    ///
    /// The guard above asks whether a colour is written *into a rule* — its own words, and the
    /// reason it exists: a colour reachable from a rule means the `:root` family is not the whole
    /// palette. A block comment is not a rule and paints nothing, so a measurement recorded beside
    /// the fix it justifies is evidence rather than a stray literal. M31 wrote three such values
    /// into a comment explaining a white-on-white defect, and the guard read them as the defect.
    ///
    /// Blanking spans rather than dropping whole lines is what keeps that narrow: `color: #fff;
    /// /* was #eee */` still reports the declaration and not the note. Line numbers and columns
    /// survive because only the comment's own characters become spaces.
    ///
    /// This does not reach the `<!-- mac-craft:metrics -->` block, which is an HTML comment read
    /// deliberately by `metricRows(in:)` and excluded here by `tokenBlockRanges(in:)` already.
    /// The two channels stay separate: that one is parsed, this one is skipped.
    static func blankingBlockComments(in text: String) -> String {
        var out = Array(text)
        var index = text.startIndex
        var depth = 0
        var openedAt: String.Index?
        while index < text.endIndex {
            let next = text.index(after: index)
            if next < text.endIndex, depth == 0, text[index] == "/", text[next] == "*" {
                depth = 1
                openedAt = index
                index = text.index(after: next)
                continue
            }
            if next < text.endIndex, depth == 1, text[index] == "*", text[next] == "/" {
                let end = text.index(after: next)
                blank(&out, in: text, from: openedAt ?? index, to: end)
                depth = 0
                openedAt = nil
                index = end
                continue
            }
            index = next
        }
        // An unterminated comment blanks to the end rather than throwing: this scanner reports
        // findings and a malformed mock is the metrics parser's error to raise, not this one's.
        if depth == 1, let start = openedAt {
            blank(&out, in: text, from: start, to: text.endIndex)
        }
        return String(out)
    }

    /// Replace one span with spaces, keeping newlines so every line number is unchanged.
    private static func blank(
        _ out: inout [Character],
        in text: String,
        from start: String.Index,
        to end: String.Index
    ) {
        let offset = text.distance(from: text.startIndex, to: start)
        let length = text.distance(from: start, to: end)
        for position in offset ..< (offset + length) where out[position] != "\n" {
            out[position] = " "
        }
    }

    /// `#RGB`, `#RRGGBB` and `#RRGGBBAA` runs — and nothing else beginning with `#`.
    ///
    /// An SVG sprite reference is `href="#i-arrow-r"`, and a fragment id is not a colour. Requiring
    /// the whole run after the hash to be 3, 6 or 8 hex digits and to end at a non-word character
    /// separates the two without an allowlist of ids that would go stale.
    private static func hexRuns(in line: String) -> [String] {
        var out: [String] = []
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            guard chars[i] == "#" else { i += 1; continue }
            var j = i + 1
            var digits = ""
            while j < chars.count, chars[j].isHexDigit {
                digits.append(chars[j]); j += 1
            }
            let boundedByWord = j < chars
                .count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "-" || chars[j] == "_")
            if !boundedByWord, [3, 6, 8].contains(digits.count) { out.append("#" + digits) }
            i = max(j, i + 1)
        }
        return out
    }

    /// `rgb(...)` / `rgba(...)` runs whose first argument is numeric.
    ///
    /// `rgba(var(--x))` is not a literal; a literal has numbers in it.
    private static func functionalColorRuns(in line: String) -> [String] {
        var out: [String] = []
        var search = line[...]
        while let open = search.range(of: "rgba(") ?? search.range(of: "rgb(") {
            let after = search[open.upperBound...]
            if let close = after.firstIndex(of: ")") {
                let args = after[after.startIndex ..< close]
                if args.first?.isNumber == true { out.append(String(search[open.lowerBound ... close])) }
                search = after[after.index(after: close)...]
            } else {
                break
            }
        }
        return out
    }
}
