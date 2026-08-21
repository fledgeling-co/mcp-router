import Foundation

enum ScanByte {
    static let newline = UInt8(ascii: "\n")
    static let space = UInt8(ascii: " ")
    static let dot = UInt8(ascii: ".")
    static let openParen = UInt8(ascii: "(")
    static let closeParen = UInt8(ascii: ")")
    static let openBrace = UInt8(ascii: "{")
    static let closeBrace = UInt8(ascii: "}")
    static let quote = UInt8(ascii: "\"")
    static let hash = UInt8(ascii: "#")
    static let slash = UInt8(ascii: "/")
    static let star = UInt8(ascii: "*")
    static let backslash = UInt8(ascii: "\\")
    static let semicolon = UInt8(ascii: ";")
    static let colon = UInt8(ascii: ":")

    static let tab = UInt8(ascii: "\t")
    static let carriageReturn = UInt8(ascii: "\r")
    static let openSquare = UInt8(ascii: "[")
    static let closeSquare = UInt8(ascii: "]")

    static func isStatementBoundary(_ byte: UInt8) -> Bool {
        byte == openBrace || byte == closeBrace || byte == semicolon
    }

    /// Whitespace that may sit between a multi-line literal's delimiter and its line break. `\r`
    /// is in the set because a CRLF file otherwise reads `\"\"\"` as three single-line literals and
    /// scans the whole string body as code — a desync that leaves `endedCleanly` true.
    static func isLineFiller(_ byte: UInt8) -> Bool {
        byte == space || byte == tab || byte == carriageReturn
    }

    /// What Swift will let an identifier be made of, for the purpose of a word boundary. ASCII
    /// only, because the delexer has already blanked everything above it.
    static func isIdentifier(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "_")
            || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
            || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
            || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
    }
}

/// Swift's comment and string-literal grammar, applied so that whatever is left is code.
///
/// Every comment byte and every byte inside a literal becomes a space, newlines stay where they
/// are, and bytes above ASCII are blanked too — so the output has the same length and the same line
/// breaks as the input, and one offset means the same thing in both.
///
/// The grammar it implements, one production per control in `PoolAwaitBoundControlTests`: line
/// comment, block comment, **nested** block comment, single-line literal, multi-line literal, raw
/// literal at any hash count, escape, and interpolation — which is code inside a literal, and
/// whose nested literals are the shape that used to put a hand-rolled scan out of step for the rest
/// of the file.
struct Delexer {
    private enum Mode { case code, lineComment, blockComment, string }
    private struct Literal { let hashes: Int; let multiline: Bool }

    private let src: [UInt8]
    private var out: [UInt8] = []
    private var mode = Mode.code
    private var blockDepth = 0
    private var literals: [Literal] = []
    private var interpolations: [Int] = []
    private var index = 0

    init(_ source: String) {
        src = Array(source.utf8)
        out.reserveCapacity(src.count)
    }

    /// Whether the source ran out while a comment or a literal was still open. A well-formed Swift
    /// file ends in code, so anything else means the lexer lost sync and the read cannot be trusted.
    var endedCleanly: Bool {
        // A line comment at EOF with no trailing newline is legal Swift and ends the file in
        // `.lineComment`, so it is a clean end too. Reported by an out-of-family lane as a false red
        // on correct source, which is the direction this gate must not fail in.
        (mode == .code || mode == .lineComment)
            && blockDepth == 0 && literals.isEmpty && interpolations.isEmpty
    }

    mutating func run() -> [UInt8] {
        while index < src.count {
            if src[index] == ScanByte.newline {
                takeNewline()
            } else {
                switch mode {
                case .code: stepCode()
                case .lineComment: blank(1)
                case .blockComment: stepBlockComment()
                case .string: stepString()
                }
            }
        }
        return out
    }

    private mutating func takeNewline() {
        if mode == .lineComment { mode = .code }
        // An unterminated single-line literal cannot occur in source that compiles; ending it at
        // the line break bounds the damage if one ever reaches here anyway.
        if mode == .string, literals.last?.multiline == false {
            literals.removeLast()
            mode = .code
        }
        out.append(ScanByte.newline)
        index += 1
    }

    private mutating func stepCode() {
        let byte = src[index]
        if !interpolations.isEmpty, byte == ScanByte.openParen || byte == ScanByte.closeParen {
            stepInterpolation(byte)
            return
        }
        if byte == ScanByte.slash, peek(1) == ScanByte.slash {
            mode = .lineComment
            blank(2)
            return
        }
        if byte == ScanByte.slash, peek(1) == ScanByte.star {
            mode = .blockComment
            blockDepth = 1
            blank(2)
            return
        }
        if byte == ScanByte.hash || byte == ScanByte.quote, openLiteral() { return }
        keep()
    }

    /// A run of `#` followed by a quote opens a literal; a `#` followed by anything else is an
    /// attribute or a macro and stays code.
    private mutating func openLiteral() -> Bool {
        var probe = index
        var hashes = 0
        while probe < src.count, src[probe] == ScanByte.hash {
            hashes += 1
            probe += 1
        }
        guard probe < src.count, src[probe] == ScanByte.quote else { return false }
        let multiline = opensMultiline(at: probe)
        literals.append(Literal(hashes: hashes, multiline: multiline))
        mode = .string
        blank(hashes + (multiline ? 3 : 1))
        return true
    }

    /// Three quotes open a multi-line literal only when the content starts on the next line, which
    /// is Swift's rule and not a refinement of it. Without the newline test, `#""""#` — a raw
    /// literal holding two quote characters — reads as a multi-line opener that never closes, and
    /// the rest of the file is blanked as literal content. `PrimitiveBodyTests.swift:140` is that
    /// line, and the readability check is what turned a silent miss into a named red.
    private func opensMultiline(at probe: Int) -> Bool {
        guard probe + 2 < src.count,
              src[probe + 1] == ScanByte.quote,
              src[probe + 2] == ScanByte.quote else { return false }
        var index = probe + 3
        while index < src.count, ScanByte.isLineFiller(src[index]) {
            index += 1
        }
        return index < src.count && src[index] == ScanByte.newline
    }

    /// Interpolated text is code and is kept as code; only the two delimiters are blanked. The
    /// depth count is what tells the closing delimiter from a `)` belonging to a call inside it.
    private mutating func stepInterpolation(_ byte: UInt8) {
        if byte == ScanByte.openParen {
            interpolations[interpolations.count - 1] += 1
            keep()
            return
        }
        interpolations[interpolations.count - 1] -= 1
        if interpolations[interpolations.count - 1] == 0 {
            interpolations.removeLast()
            mode = .string
            blank(1)
        } else {
            keep()
        }
    }

    private mutating func stepBlockComment() {
        if src[index] == ScanByte.slash, peek(1) == ScanByte.star {
            blockDepth += 1
            blank(2)
            return
        }
        if src[index] == ScanByte.star, peek(1) == ScanByte.slash {
            blockDepth -= 1
            if blockDepth == 0 { mode = .code }
            blank(2)
            return
        }
        blank(1)
    }

    private mutating func stepString() {
        guard let literal = literals.last else {
            mode = .code
            return
        }
        if src[index] == ScanByte.backslash, stepEscape(literal) { return }
        if src[index] == ScanByte.quote, stepClose(literal) { return }
        blank(1)
    }

    /// `\` plus this literal's own hash count either opens an interpolation or escapes one
    /// character. In a raw literal a lone `\` is content, which is why the hashes have to match.
    private mutating func stepEscape(_ literal: Literal) -> Bool {
        var probe = index + 1
        var hashes = 0
        while probe < src.count, src[probe] == ScanByte.hash, hashes < literal.hashes {
            hashes += 1
            probe += 1
        }
        guard hashes == literal.hashes, probe < src.count else { return false }
        if src[probe] == ScanByte.openParen {
            interpolations.append(1)
            mode = .code
            blank(probe + 1 - index)
            return true
        }
        // A line continuation escapes the newline itself, and the newline has to stay where it is.
        blank(probe - index + (src[probe] == ScanByte.newline ? 0 : 1))
        return true
    }

    private mutating func stepClose(_ literal: Literal) -> Bool {
        let quotes = literal.multiline ? 3 : 1
        guard index + quotes <= src.count else { return false }
        guard (0 ..< quotes).allSatisfy({ src[index + $0] == ScanByte.quote }) else { return false }
        var probe = index + quotes
        var hashes = 0
        while probe < src.count, src[probe] == ScanByte.hash, hashes < literal.hashes {
            hashes += 1
            probe += 1
        }
        guard hashes == literal.hashes else { return false }
        literals.removeLast()
        mode = .code
        blank(probe - index)
        return true
    }

    private func peek(_ ahead: Int) -> UInt8? {
        index + ahead < src.count ? src[index + ahead] : nil
    }

    private mutating func blank(_ count: Int) {
        let bounded = min(count, src.count - index)
        out.append(contentsOf: repeatElement(ScanByte.space, count: bounded))
        index += bounded
    }

    /// Above ASCII is blanked rather than copied, so an offset into the output is a character count
    /// as well as a byte count and nothing downstream has to know the difference.
    private mutating func keep() {
        out.append(src[index] < 0x80 ? src[index] : ScanByte.space)
        index += 1
    }
}
