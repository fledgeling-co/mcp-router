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

        /// Whether this context is one of the two `prefers-contrast: more` blocks.
        ///
        /// The second axis of the pairing. Without it, a Swift token that re-solves for increased
        /// contrast is compared against its base value in the contexts where it overrides, so the
        /// nine tokens that carry the accessibility half of the palette could never be `matched`
        /// however correct they were.
        var isIncreasedContrast: Bool {
            switch self {
            case .lightContrast, .darkContrast: true
            case .light, .dark, .lightOverride, .darkOverride: false
            }
        }
    }

    // MARK: - Parsed shapes

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
                "the mock has no <!-- mac-craft:metrics --> comment — the metric half of the "
                    + "token layer has no source"
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
        return s.hasPrefix("#") ? hexColor(String(s.dropFirst())) : functionalColor(s.lowercased())
    }

    /// `#RGB`, `#RRGGBB` or `#RRGGBBAA`, with the digits already stripped of their `#`.
    private static func hexColor(_ digits: String) -> ColorValue? {
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        switch digits.count {
        case 3:
            let doubled = digits.uppercased().map { "\($0)\($0)" }.joined()
            return ColorValue(hex: "#" + doubled, alpha: 1.0)
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

    /// `rgb(r, g, b)` or `rgba(r, g, b, a)`, lowercased.
    private static func functionalColor(_ lower: String) -> ColorValue? {
        guard lower.hasPrefix("rgb(") || lower.hasPrefix("rgba(") else { return nil }
        guard lower.hasSuffix(")"), let open = lower.firstIndex(of: "(") else { return nil }
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

    // MARK: - The metrics comment

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
    /// A `{` that has been seen and not yet closed, with what it opened and where.
    ///
    /// A named type rather than a four-member tuple: SwiftLint caps a tuple at two, and the cap is
    /// right here — `(Appearance, String, Int, Int)` reads as two integers whose meanings you have
    /// to go and look up.
    private struct OpenBlock {
        var appearance: Appearance
        var selector: String
        var start: Int
        var depth: Int
    }

    static func blocks(in text: String) throws -> [Block] {
        let lines = text.components(separatedBy: .newlines)
        var out: [Block] = []
        var depth = 0
        // The context a `{` at depth 0 or 1 opened, and the depth it opened at.
        var open: OpenBlock?
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
                    open = OpenBlock(
                        appearance: appearance,
                        selector: selector,
                        start: index + 1,
                        depth: depth
                    )
                } else if let match = contextSelectors.first(where: { $0.selector == selector }) {
                    // A media query is a wrapper: the `:root` inside it is the block that declares.
                    // A class selector is the block itself. Matched on equality rather than prefix,
                    // so a descendant rule such as `.is-dark .jack` is not mistaken for the
                    // appearance block it is scoped by.
                    if selector.hasPrefix("@media") {
                        mediaContext = (match.appearance, depth)
                    } else {
                        open = OpenBlock(
                            appearance: match.appearance, selector: selector,
                            start: index + 1, depth: depth
                        )
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
}
