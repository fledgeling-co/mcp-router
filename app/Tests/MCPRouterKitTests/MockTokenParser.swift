import Foundation

/// Reads the two machine-readable token blocks out of `design/mcp-router-console.html`.
///
/// The mock is the conversion source for M15–M22, and it carries its values in two places that
/// parse without a CSS engine: a `<!-- mac-craft:metrics -->` comment of `name value tier` rows,
/// and a family of custom-property blocks — one per appearance context — in which every colour in
/// the file lives. `DesignDocParser` does the same job for `DESIGN.md`; this is its sibling, and
/// the two coexist deliberately because which document is authoritative is M21's open decision.
///
/// Nothing here compares anything. Parsing and judging are separate on purpose: a parser that
/// knows what it hopes to find is a parser that can be talked into finding it.
enum MockTokenParser {
    // MARK: - Appearance contexts

    /// The six contexts the mock authors, named by the selector that opens each one.
    ///
    /// Six rather than two, and the last two are the ones a conversion drops. `M21`'s brief states
    /// the reason: a single scheme-agnostic `prefers-contrast` block paints dark ink on a graphite
    /// ground in whichever of the two appearances it was not written for, so increased contrast is
    /// authored per appearance and the parser has to keep them apart.
    enum Appearance: String, CaseIterable, Sendable, Comparable {
        /// `:root` — the base block. The mock is light-first, so this is light.
        case light
        /// `@media (prefers-color-scheme: dark) :root`
        case dark
        /// `.is-light` — the in-mock appearance switch, light side.
        case lightOverride
        /// `.is-dark` — the in-mock appearance switch, dark side.
        case darkOverride
        /// `@media (prefers-contrast: more) and (prefers-color-scheme: light) :root`
        case lightContrast
        /// `@media (prefers-contrast: more) and (prefers-color-scheme: dark) :root`
        case darkContrast

        static func < (a: Appearance, b: Appearance) -> Bool {
            a.rawValue < b.rawValue
        }

        /// Whether this context describes the dark appearance, for pairing against a Swift token's
        /// dark half.
        var isDark: Bool {
            switch self {
            case .dark, .darkOverride, .darkContrast: true
            case .light, .lightOverride, .lightContrast: false
            }
        }
    }

    // MARK: - Parsed shapes

    /// A row of the `mac-craft:metrics` comment: `name value tier`.
    struct MetricRow: Equatable, Sendable {
        let name: String
        let rawValue: String
        let tier: String
        /// The value read as a length in points, when it is one.
        let points: Double?
        /// The value read as a colour, when it is one.
        let color: ColorValue?
    }

    /// A colour, canonicalised so `#FFF`, `#ffffff` and `rgba(255,255,255,1)` compare equal.
    struct ColorValue: Equatable, Sendable, CustomStringConvertible {
        /// Six upper-case hex digits, `#`-prefixed.
        let hex: String
        /// Alpha as a fraction. 1.0 when the source states none.
        let alpha: Double

        var description: String { alpha == 1.0 ? hex : "\(hex)@\(String(format: "%.4g", alpha))" }

        /// Equality to four decimal places on alpha, because `0.075` and `7.5%` are the same value
        /// written twice and a binary comparison of two decimal conversions is not reliable.
        static func == (a: ColorValue, b: ColorValue) -> Bool {
            a.hex == b.hex && abs(a.alpha - b.alpha) < 0.0001
        }
    }

    /// One custom property as the mock declares it in one appearance context.
    struct Declaration: Equatable, Sendable {
        let name: String
        let appearance: Appearance
        let rawValue: String
        /// The value read as a colour, when the whole value is one.
        let color: ColorValue?
        /// The value read as a length in points, when the whole value is one.
        let points: Double?

        /// An embedded asset — `url("data:image/webp;base64,…")`. The mock's second top-level
        /// `:root` block is fourteen of them.
        var isAsset: Bool { rawValue.hasPrefix("url(") }

        /// A value that is neither a single colour, a single length nor an asset — a shadow list,
        /// a keyword.
        ///
        /// Recorded rather than skipped. A parser that drops what it cannot type is a parser whose
        /// silence and whose agreement look identical, which is the failure this whole item exists
        /// to close.
        var isComposite: Bool { color == nil && points == nil && !isAsset }
    }

    /// A colour literal found outside every token block.
    struct StrayLiteral: Equatable, Sendable {
        let line: Int
        let text: String
        let context: String
    }

    // MARK: - Errors

    enum ParseError: Error, CustomStringConvertible {
        case mockNotFound(startingFrom: String)
        case metricsCommentMissing
        case metricsCommentUnterminated
        case appearanceBlockMissing(Appearance)
        case unterminatedBlock(Appearance)
        case malformedMetricRow(String)

        var description: String {
            switch self {
            case let .mockNotFound(from):
                "design/mcp-router-console.html not found walking up from \(from)"
            case .metricsCommentMissing:
                "the mock has no <!-- mac-craft:metrics --> comment — the metric half of the token layer has no source"
            case .metricsCommentUnterminated:
                "the mac-craft:metrics comment is never closed"
            case let .appearanceBlockMissing(a):
                "the mock declares no \(a.rawValue) block — an appearance context the parser expects has gone"
            case let .unterminatedBlock(a):
                "the \(a.rawValue) block is never closed"
            case let .malformedMetricRow(row):
                "a metrics row is not 'name value tier': \(row)"
            }
        }
    }

    // MARK: - Locating the mock

    /// Walks up from this source file to the repository root and returns the mock.
    ///
    /// Throws rather than returning nil, for `DesignDocParser`'s reason: a check that cannot find
    /// the document it compares against must fail loudly, because a skip and a pass are the same
    /// exit code.
    static func mockURL(from filePath: String = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let candidate = dir
                .appendingPathComponent("design")
                .appendingPathComponent("mcp-router-console.html")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        throw ParseError.mockNotFound(startingFrom: filePath)
    }

    static func mockText(from filePath: String = #filePath) throws -> String {
        try String(contentsOf: mockURL(from: filePath), encoding: .utf8)
    }

    // MARK: - Value normalisation

    /// `#FFF`, `#ffffff` and `#FFFFFFCC` all become six upper-case digits plus an alpha fraction.
    ///
    /// Returns nil when the string is not *entirely* a colour. That strictness is the point: a
    /// shadow value contains a colour, and treating it as one would compare a drop shadow against
    /// a fill.
    static func color(of raw: String) -> ColorValue? {
        let s = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
            .trimmingCharacters(in: .whitespaces)

        if s.hasPrefix("#") {
            let digits = String(s.dropFirst())
            guard digits.allSatisfy(\.isHexDigit) else { return nil }
            switch digits.count {
            case 3:
                return ColorValue(hex: "#" + digits.uppercased().map { "\($0)\($0)" }.joined(), alpha: 1.0)
            case 6:
                return ColorValue(hex: "#" + digits.uppercased(), alpha: 1.0)
            case 8:
                let hex = String(digits.prefix(6)).uppercased()
                let a = Int(String(digits.suffix(2)), radix: 16).map { Double($0) / 255.0 } ?? 1.0
                return ColorValue(hex: "#" + hex, alpha: a)
            default:
                return nil
            }
        }

        let lower = s.lowercased()
        guard lower.hasPrefix("rgb(") || lower.hasPrefix("rgba(") else { return nil }
        guard lower.hasSuffix(")") else { return nil }
        let open = lower.firstIndex(of: "(")!
        let inner = lower[lower.index(after: open) ..< lower.index(before: lower.endIndex)]
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        var channels: [Int] = []
        for p in parts.prefix(3) {
            guard let v = Int(p), (0 ... 255).contains(v) else { return nil }
            channels.append(v)
        }
        var alpha = 1.0
        if parts.count == 4 {
            guard let a = Double(parts[3]) else { return nil }
            alpha = a
        }
        let hex = "#" + channels.map { String(format: "%02X", $0) }.joined()
        return ColorValue(hex: hex, alpha: alpha)
    }

    /// A value that is entirely a length in `px`, as points. Nil for anything else.
    ///
    /// `px` in the mock and `pt` in SwiftUI are the same number here: the mock is authored at
    /// 1× against macOS point geometry, which is why `titlebar 33px` and `Titlebar | 33pt` are the
    /// same row. That equivalence is an assumption of the conversion, stated here rather than
    /// buried in a comparison.
    static func points(of raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
            .trimmingCharacters(in: .whitespaces)
        guard s.hasSuffix("px") else { return nil }
        return Double(s.dropLast(2))
    }

    // MARK: - The metrics comment

    /// The `name value tier` rows of the `mac-craft:metrics` comment, in document order.
    static func metricRows(in text: String) throws -> [MetricRow] {
        let lines = text.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: {
            $0.contains("<!-- mac-craft:metrics")
        }) else { throw ParseError.metricsCommentMissing }

        var rows: [MetricRow] = []
        var closed = false
        for line in lines[(start + 1)...] {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("-->") { closed = true; break }
            if t.isEmpty { continue }
            let fields = t.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count == 3 else { throw ParseError.malformedMetricRow(t) }
            rows.append(MetricRow(
                name: fields[0],
                rawValue: fields[1],
                tier: fields[2],
                points: points(of: fields[1]),
                color: color(of: fields[1])
            ))
        }
        guard closed else { throw ParseError.metricsCommentUnterminated }
        return rows
    }

    // MARK: - The custom-property blocks

    /// The selector that opens each appearance context.
    ///
    /// Matched on the selector rather than on a line number, so re-ordering the stylesheet cannot
    /// silently repoint a context at another block — the mistake `DesignDocParser` records having
    /// made with positional columns.
    ///
    /// `light` is deliberately **not** in this table. It is not one block: the mock has two
    /// top-level `:root` rules — the palette at the top of the stylesheet and a second one 700
    /// lines down holding fourteen embedded WebP assets — and a parser that took the first match
    /// would silently ignore everything in the second. A colour added there would be invisible to
    /// a check reporting that it had read every context, which is the shape of blindness this item
    /// exists to remove. Every top-level `:root` is the light context.
    private static let contextSelectors: [(selector: String, appearance: Appearance)] = [
        ("@media (prefers-contrast: more) and (prefers-color-scheme: light)", .lightContrast),
        ("@media (prefers-contrast: more) and (prefers-color-scheme: dark)", .darkContrast),
        ("@media (prefers-color-scheme: dark)", .dark),
        (".is-light", .lightOverride),
        (".is-dark", .darkOverride)
    ]

    /// One block the scanner walked: which context it declares into, and the lines it spans.
    struct Block: Equatable, Sendable {
        let appearance: Appearance
        /// The selector as written, for a message that names what was read.
        let selector: String
        /// 1-indexed, inclusive.
        let lines: ClosedRange<Int>
    }

    /// Every token block in the file, found by walking brace depth rather than by matching one
    /// opener at a time.
    ///
    /// Returns them all, including a repeat of the same context: two top-level `:root` rules are
    /// two blocks that both declare into `light`, and merging them at this level would hide the
    /// second from any check that counts blocks.
    static func blocks(in text: String) throws -> [Block] {
        let lines = text.components(separatedBy: .newlines)
        var out: [Block] = []
        var depth = 0
        // The context a `{` at depth 0 or 1 opened, and the depth it opened at.
        var open: (appearance: Appearance, selector: String, start: Int, depth: Int)?
        var mediaContext: (appearance: Appearance, depth: Int)?

        for (index, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            let opens = t.filter { $0 == "{" }.count
            let closes = t.filter { $0 == "}" }.count

            if opens > 0, open == nil {
                let selector = String(t.prefix(while: { $0 != "{" })).trimmingCharacters(in: .whitespaces)
                if selector == ":root" {
                    // Inside one of the two increased-contrast media queries, `:root` declares into
                    // that context; at the top level it declares into light.
                    let appearance = mediaContext?.appearance ?? .light
                    open = (appearance, selector, index + 1, depth)
                } else if let match = contextSelectors.first(where: { $0.selector == selector }) {
                    // A media query is a wrapper: the `:root` inside it is the block that declares.
                    // A class selector is the block itself. Matched on equality rather than prefix,
                    // so a descendant rule such as `.is-dark .jack` is not mistaken for the
                    // appearance block it is scoped by.
                    if selector.hasPrefix("@media") {
                        mediaContext = (match.appearance, depth)
                    } else {
                        open = (match.appearance, selector, index + 1, depth)
                    }
                }
            }

            depth += opens
            depth -= closes

            if let current = open, depth <= current.depth {
                out.append(Block(
                    appearance: current.appearance, selector: current.selector,
                    lines: current.start ... (index + 1)
                ))
                open = nil
            }
            if let media = mediaContext, depth <= media.depth { mediaContext = nil }
        }

        guard open == nil else { throw ParseError.unterminatedBlock(out.last?.appearance ?? .light) }

        for appearance in Appearance.allCases where !out.contains(where: { $0.appearance == appearance }) {
            throw ParseError.appearanceBlockMissing(appearance)
        }
        return out
    }

    /// Every `--name: value` declaration in every appearance context, in document order.
    ///
    /// A context that is absent throws rather than yielding an empty dictionary. An empty result
    /// and a passing comparison are the same thing to a differ, and the mock losing its increased
    /// contrast blocks is exactly the kind of change that has to be loud.
    static func declarations(in text: String) throws -> [Declaration] {
        let lines = text.components(separatedBy: .newlines)
        var out: [Declaration] = []
        for block in try blocks(in: text) {
            for number in block.lines {
                guard number - 1 < lines.count else { continue }
                let t = lines[number - 1].trimmingCharacters(in: .whitespaces)
                if let decl = declaration(in: t, appearance: block.appearance) { out.append(decl) }
            }
        }
        return out
    }

    /// One `--name:value;` line, or nil when the line declares nothing.
    private static func declaration(in line: String, appearance: Appearance) -> Declaration? {
        guard line.hasPrefix("--"), let colon = line.firstIndex(of: ":") else { return nil }
        let name = String(line[line.startIndex ..< colon]).trimmingCharacters(in: .whitespaces)
        var value = String(line[line.index(after: colon)...])
        if let semi = value.lastIndex(of: ";") { value = String(value[value.startIndex ..< semi]) }
        value = value.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !value.isEmpty else { return nil }
        return Declaration(
            name: name,
            appearance: appearance,
            rawValue: value,
            color: color(of: value),
            points: points(of: value)
        )
    }

    /// Every declaration, keyed by name then appearance.
    static func declarationsByName(in text: String) throws -> [String: [Appearance: Declaration]] {
        var out: [String: [Appearance: Declaration]] = [:]
        for d in try declarations(in: text) {
            out[d.name, default: [:]][d.appearance] = d
        }
        return out
    }

    // MARK: - The mock's own zero-literals property

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
        let lines = text.components(separatedBy: .newlines)
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
