import Foundation

/// Finds calls to the pool's two unbounded awaits, and says of each whether an `awaitEvent` block
/// lexically encloses it.
///
/// Separated from the suite so the controls can drive it on constructed source: a classifier only
/// reachable through a filesystem walk can be held to whatever happens to be in the tree, which is
/// how five defects survived two reviews.
enum AwaitBoundScan {
    struct Site: Equatable {
        /// 1-based, to match what a compiler or an editor would say.
        let line: Int
        let bounded: Bool
    }

    /// Spelled without the leading dot and matched with one required, so a definition
    /// (`func awaitReap`) is never read as a call.
    private static let names = [Array("awaitReap".utf8), Array("awaitSessionEnded".utf8)]

    static func sites(in source: String) -> [Site] {
        scan(source).sites
    }

    /// A file read, and whether the read is trustworthy.
    ///
    /// `readable` is false when delexing ends mid-comment or mid-literal, or when the braces left
    /// behind do not balance. Both mean the lexer lost sync — a Swift 5.7 regex literal containing
    /// `/*` would do it — and a scan that has lost sync reports **no** call sites rather than the
    /// wrong ones, which is a silent miss. Reporting the file as unreadable turns that whole class
    /// into a named red instead.
    static func scan(_ source: String) -> (sites: [Site], readable: Bool) {
        var delexer = Delexer(source)
        let code = delexer.run()
        let sites = callOffsets(in: code).map {
            Site(line: line(at: $0, in: code), bounded: isBounded(callAt: $0, in: code))
        }
        return (sites, delexer.endedCleanly && bracesBalance(in: code))
    }

    private static func bracesBalance(in code: [UInt8]) -> Bool {
        var depth = 0
        for byte in code {
            if byte == ScanByte.openBrace { depth += 1 }
            if byte == ScanByte.closeBrace { depth -= 1 }
            if depth < 0 { return false }
        }
        return depth == 0
    }

    private static func line(at offset: Int, in code: [UInt8]) -> Int {
        code[..<offset].reduce(1) { $1 == ScanByte.newline ? $0 + 1 : $0 }
    }

    /// Every `.awaitReap(` / `.awaitSessionEnded(` in the delexed text, tolerant of whitespace
    /// either side of the name — including a newline, which the previous line-at-a-time regex could
    /// not cross and said so.
    private static func callOffsets(in code: [UInt8]) -> [Int] {
        var found: [Int] = []
        var index = 0
        while index < code.count {
            if code[index] == ScanByte.dot, let end = callEnd(at: index, in: code) {
                found.append(index)
                index = end
            } else {
                index += 1
            }
        }
        return found
    }

    private static func callEnd(at start: Int, in code: [UInt8]) -> Int? {
        var index = skipSpace(from: start + 1, in: code)
        guard let name = names.first(where: { matches($0, at: index, in: code) }) else { return nil }
        // The byte after the name must be whitespace or `(`, so `.awaitReaper(` is not this call.
        index = skipSpace(from: index + name.count, in: code)
        guard index < code.count, code[index] == ScanByte.openParen else { return nil }
        // `pool.awaitReap(_:epoch:)` is a reference to the method, not a call of it, and awaits
        // nothing — an argument list ending in `:` is the shape no call can have. This reads the
        // delexed text, so it rests on a literal leaving `ScanByte.elided` behind rather than
        // whitespace: while literals blanked to spaces, `awaitReap(name: "own")` ended in `:` too
        // and the call was discarded, reporting no site at all.
        let close = matchingParen(from: index, in: code)
        guard close < 0 || lastMeaningful(before: close - 1, in: code) != ScanByte.colon
        else { return nil }
        return index + 1
    }

    static func lastMeaningful(before end: Int, in code: [UInt8]) -> UInt8? {
        var index = end - 1
        while index >= 0, code[index] <= ScanByte.space {
            index -= 1
        }
        return index >= 0 ? code[index] : nil
    }

    private static func matches(_ name: [UInt8], at index: Int, in code: [UInt8]) -> Bool {
        guard index + name.count <= code.count else { return false }
        return Array(code[index ..< index + name.count]) == name
    }

    private static func skipSpace(from index: Int, in code: [UInt8]) -> Int {
        var index = index
        while index < code.count, code[index] <= ScanByte.space {
            index += 1
        }
        return index
    }

    /// Walk outward from the call by brace balance, and read the statement each enclosing `{`
    /// terminates. Brace nesting is Swift's own block structure, so a `#if` at column 0, a tab and a
    /// wrapped brace all stop being able to change the answer.
    private static func isBounded(callAt offset: Int, in code: [UInt8]) -> Bool {
        var depth = 0
        var index = offset - 1
        while index >= 0 {
            if code[index] == ScanByte.closeBrace {
                depth += 1
            } else if code[index] == ScanByte.openBrace {
                if depth > 0 {
                    depth -= 1
                } else {
                    switch verdict(forBlockOpenedAt: index, in: code) {
                    case .bounded: return true
                    case .function: return false
                    case .keepWalking: break
                    }
                }
            }
            index -= 1
        }
        return false
    }

    enum Verdict { case bounded, function, keepWalking }

    /// The statement the `{` at `index` terminates, and what it makes of the block.
    ///
    /// `func ` is tested first and it is load-bearing: a function whose own signature contains the
    /// needle — `func awaitEvent(…) {` — would otherwise read as a wrap around its own body, which
    /// is how a bare call planted beside `awaitEvent` first got through. Both markers are matched
    /// on a **word boundary**, because `if myfunc {` contains `func ` and `mock_awaitEvent(`
    /// contains `awaitEvent(` — an out-of-family reviewer wrote both out, one in each direction.
    private static func verdict(forBlockOpenedAt index: Int, in code: [UInt8]) -> Verdict {
        // Whitespace runs collapse to one space rather than vanishing: removing it altogether
        // welds `try await awaitEvent(` into one word and destroys the boundary being tested for.
        let opener = collapsed(statement(endingAt: index, in: code))
        // A declaration's body is never a wrap, whatever its signature says. `func` was the first
        // of these and the others are its siblings: an `init` inside a wrapped block runs whenever
        // the type is instantiated, which is the same hazard.
        if Self.declarations.contains(where: { unqualifiedIndex(of: $0, in: opener) != nil }) {
            return .function
        }
        // A control-flow body is a body, not a trailing closure. `if flags.awaitEvent(x) {` has
        // exactly the shape the ownership test below accepts, because a condition has no closing
        // paren of its own — an out-of-family lane wrote out five of these.
        if Self.bodyKeywords.contains(firstWord(of: opener)) { return .keepWalking }
        // A closure handed to `Task` outlives the block it was written in, so being inside one is
        // not being inside the wait. Lexical containment and execution bound part company here, and
        // this is the one place the scan can tell. Read from the call that RECEIVES the brace, not
        // from the opener as a whole: searching the whole statement reddened a correct wrap whose
        // message interpolated `Task.currentPriority`, because an interpolation is code and the
        // word was there. Swapping `Task` for `Clock` in that same line pinned it.
        if closureOwner(in: opener).contains(where: { Self.escapes.contains($0) }) {
            return .function
        }
        guard let name = wordIndex(of: Self.wrapMarker, in: opener) else { return .keepWalking }
        // The wrapper is a free function. `analytics.awaitEvent("x") { … }` is somebody else's
        // method that happens to share the name, and it bounds nothing. Read past whitespace: a
        // lane broke a byte-before test with the receiver's dot at the end of a line, which
        // `collapsed` turns into a space.
        if isQualified(at: name, in: opener) { return .keepWalking }
        var paren = name + Self.wrapMarker.count
        if paren < opener.count, opener[paren] == ScanByte.space { paren += 1 }
        guard paren < opener.count, opener[paren] == ScanByte.openParen else { return .keepWalking }
        // The trailing closure belongs to the call whose arguments close LAST. Without this,
        // `withTimeout(awaitEvent("x")) { … }` reads as an `awaitEvent` block and a genuinely
        // unbounded await inside it passes — as does `guard awaitEvent(…) != nil else { … }`.
        let after = matchingParen(from: paren, in: opener)
        // Never closing means the brace sits INSIDE the argument list, which is the non-trailing
        // spelling `awaitEvent("x", { … })` — bounded, and one formatting choice from the blessed
        // form, so reading it as a red is the false fire this gate exists to not be.
        if after < 0 { return .bounded }
        return opener[after...].allSatisfy { $0 == ScanByte.space } ? .bounded : .keepWalking
    }

    static let declarations = ["func", "init", "deinit", "subscript"].map { Array($0.utf8) }
    static let bodyKeywords = ["if", "while", "for", "switch", "guard", "catch", "repeat",
                               "else", "do", "defer"].map { Array($0.utf8) }
    static let caseClauses = ["case", "default"].map { Array($0.utf8) }
    static let escapes = ["Task"].map { Array($0.utf8) }
    static let wrapMarker = Array("awaitEvent".utf8)
}
