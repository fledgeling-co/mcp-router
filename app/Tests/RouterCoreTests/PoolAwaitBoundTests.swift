import Foundation
import Testing
@testable import RouterCore

/// The standing constraint on `awaitEvent`: no call to `awaitReap` or `awaitSessionEnded` sits
/// outside one.
///
/// Its own file for the reason `PoolReapingTests` is its own file — `PoolTestSupport` reached the
/// 400-line limit — and the split pays for itself: the scan skips whichever file spells the needles
/// out, so moving it here puts `PoolTestSupport` back INSIDE the scanned set. A bare call added
/// beside `awaitEvent` is now read rather than excluded.
///
/// `awaitReap` and `awaitSessionEnded` cannot bound themselves: abandoning a wait needs a second
/// task, and a breaker that reports through `#require` needs the caller's source location to name
/// the line that gave up. Both belong out here, which leaves an accessor whose hazard lives in a
/// doc comment — and a doc comment is evidence for the moment somebody reads it.
///
/// The rule is **lexical containment**: a call is bounded when an `awaitEvent` opens a block it sits
/// inside. Two earlier formulations were taken apart, and both failed on the same thing — an
/// approximation standing in for Swift's own grammar.
///
/// - Counting wraps per function was the first cut, and the panel broke it: two `awaitEvent` blocks
///   and one bare call satisfy `calls <= wraps`.
/// - Walking outward by **indentation**, over lines classified as comments by their first three
///   characters, was the second, and a verifier broke it five ways with 22 planted call sites. A
///   comment naming the wrapper read as the wrapper; a `//` inside a string literal hid a real call;
///   a block comment, a tab and a `#if` at column 0 each produced a red on correct source.
///
/// So the scan holds exactly two models of Swift, and both are now the real thing rather than a
/// stand-in. `Delexer` implements Swift's comment and string-literal grammar — line, block, nested
/// block, single-line, multi-line, raw, escapes and interpolation — and blanks every one of them,
/// so anything left is code. `AwaitBoundScan` then reads **brace nesting**, which is what Swift
/// actually uses for block structure, so indentation, tabs and `#if` stop being able to say
/// anything. `PoolAwaitBoundControlTests` holds a control per production of both, red and green.
///
/// What it still cannot see, said rather than implied: a call reached through a stored function
/// reference or a bare `awaitReap(…)` with no receiver carries nothing to match; a call inside a
/// nested `func` within a wrap reports unbounded, because the walk stops at the enclosing `func`;
/// `#if` branches are read as though every branch compiles; and a bare call added to THIS file is
/// excluded along with the needles it is spelled with. A text scan buys durability, not proof —
/// what it does buy is that the next call site cannot quietly reopen the hole this item was
/// blocked on.
@Suite("The pool's unbounded awaits are called under a bound")
struct PoolAwaitBoundTests {
    @Test("every awaitReap and awaitSessionEnded call site sits inside awaitEvent")
    func unboundedAwaitsAreWrapped() throws {
        // The four trees the linter is pointed at, so a call site outside the test target is read
        // too. `app` whole would walk `.build`, which is thousands of files of dependency source.
        let root = try RepoTree.root()
        let trees = ["app/Sources", "app/Tests", "app/MCPRouter", "app/MCPRouterIOS"]
        // Excluded by PATH rather than by basename: this file is where the needles are spelled out,
        // and reading it would count this checker's own source as call sites. By name, a second
        // file of the same name anywhere in the tree would be skipped with it.
        let checker = URL(fileURLWithPath: #filePath).standardizedFileURL.path
        let files = trees
            .flatMap { RepoTree.swiftFiles(under: root.appendingPathComponent($0)) }
            .filter { $0.standardizedFileURL.path != checker }
        try #require(!files.isEmpty, "no sources were scanned, so this proves nothing")

        var seen = 0
        var offenders: [String] = []
        var unreadable: [String] = []
        for file in files {
            let read = try AwaitBoundScan.scan(String(contentsOf: file, encoding: .utf8))
            seen += read.sites.count
            offenders += read.sites.filter { !$0.bounded }
                .map { "\(file.lastPathComponent):\($0.line)" }
            if !read.readable { unreadable.append(file.lastPathComponent) }
        }
        // A file the lexer lost sync on yields no call sites, which is indistinguishable from a
        // clean file. Saying so is the difference between this gate missing something and this gate
        // reporting that it could not look.
        #expect(
            unreadable.isEmpty,
            """
            \(unreadable.joined(separator: ", ")) ended mid-comment or mid-literal, or left \
            unbalanced braces, so the scan of them proves nothing. A construct the delexer does not \
            know — a regex literal carrying `/*`, most likely — is the thing to look for.
            """
        )
        // The offending locations rather than the source they were found in. `#expect` displays the
        // expression it was handed, so passing `lines` to it printed the whole 13 KB file ahead of
        // the sentence that says what to do about it (`D-g3-o`).
        #expect(
            offenders.isEmpty,
            """
            \(offenders.joined(separator: ", ")) awaits a task the pool owns from outside any \
            `awaitEvent` block. Such an await runs as long as the arming — 600 000 ms in P6 — so a \
            regression there times the run out instead of naming a test.
            """
        )
        // A scan that reached nothing must not read as a scan that found nothing wrong. A floor
        // rather than an equality, and if a call site is deliberately removed the floor moves in
        // the same change — the same handling the parity floor gets.
        #expect(
            seen >= 5,
            """
            \(seen) call sites read, floor 5. Either the scan is not reaching the pool suites, or \
            a call site was removed on purpose and this floor belongs in that change.
            """
        )
    }
}

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

    private static func lastMeaningful(before end: Int, in code: [UInt8]) -> UInt8? {
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

    private enum Verdict { case bounded, function, keepWalking }

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
        if Self.declarations.contains(where: { wordIndex(of: $0, in: opener) != nil }) {
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
        if Self.escapes.contains(trailingClosureOwner(in: opener)) { return .function }
        guard let name = wordIndex(of: Self.wrapMarker, in: opener) else { return .keepWalking }
        // The wrapper is a free function. `analytics.awaitEvent("x") { … }` is somebody else's
        // method that happens to share the name, and it bounds nothing.
        if name > 0, opener[name - 1] == ScanByte.dot { return .keepWalking }
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

    /// Whether the word ending just before `index` is one no statement can end on, so the line
    /// break is a continuation. `if` on its own line above its condition is legal Swift, and without
    /// this the span starts below the `if` and the body reads as the wrapper's trailing closure.
    private static func continuesStatement(before index: Int, in code: [UInt8]) -> Bool {
        var end = index
        while end > 0, code[end - 1] <= ScanByte.space {
            end -= 1
        }
        var start = end
        while start > 0, ScanByte.isIdentifier(code[start - 1]) {
            start -= 1
        }
        return bodyKeywords.contains(Array(code[start ..< end]))
    }

    /// The word the statement begins with, past any prefix that introduces a statement without
    /// being one.
    ///
    /// A **statement label** is such a prefix, and it is legal on `if`, `while`, `for`, `switch`,
    /// `do` and `repeat`. Without this step `check: if awaitEvent(x) {` read `check`, the
    /// control-flow test above never fired, and an `if` body read as the wrapper's trailing
    /// closure — a MISS on a genuinely unbounded call, pinned by deleting the one token: identical
    /// source without the label reported correctly. A `case`/`default` clause is the same shape,
    /// introducing the statement after its colon rather than being one.
    private static func firstWord(of opener: [UInt8]) -> [UInt8] {
        var word = wordSpan(from: 0, in: opener)
        // Two is a bound rather than a search: Swift allows one label per statement and a `case`
        // clause cannot carry one.
        for _ in 0 ..< 2 {
            guard let after = statementPrefixEnd(after: word, in: opener) else { break }
            word = wordSpan(from: after, in: opener)
        }
        return Array(opener[word])
    }

    /// One past the `:` closing a prefix that introduces the statement rather than being it, or nil
    /// when `word` is the statement's own first word.
    private static func statementPrefixEnd(after word: Range<Int>, in opener: [UInt8]) -> Int? {
        guard !word.isEmpty else { return nil }
        if Self.caseClauses.contains(Array(opener[word])) {
            return clauseColon(from: word.upperBound, in: opener)
        }
        var probe = word.upperBound
        while probe < opener.count, opener[probe] == ScanByte.space {
            probe += 1
        }
        // A label is an identifier and then `:` with nothing between. `var x: Int = 1 {` puts a
        // second word there and `try await awaitEvent(…) {` has no colon at all, so neither is one.
        return probe < opener.count && opener[probe] == ScanByte.colon ? probe + 1 : nil
    }

    /// One past the `:` ending a `case` clause, counting brackets so `case (1, 2):` and
    /// `case .some(x):` end where they read as ending.
    private static func clauseColon(from index: Int, in opener: [UInt8]) -> Int? {
        var depth = 0
        for probe in index ..< opener.count {
            let byte = opener[probe]
            if byte == ScanByte.openParen || byte == ScanByte.openSquare { depth += 1 }
            if byte == ScanByte.closeParen || byte == ScanByte.closeSquare { depth -= 1 }
            if byte == ScanByte.colon, depth == 0 { return probe + 1 }
        }
        return nil
    }

    private static func wordSpan(from index: Int, in opener: [UInt8]) -> Range<Int> {
        var start = index
        while start < opener.count, opener[start] == ScanByte.space {
            start += 1
        }
        var end = start
        while end < opener.count, ScanByte.isIdentifier(opener[end]) {
            end += 1
        }
        return start ..< end
    }

    /// The root of the receiver chain of the call this `{` is a trailing closure of — `Task` for
    /// `Task {`, `Task.detached {` and `Task.detached(priority: .high) {`, `analytics` for
    /// `analytics.awaitEvent("x") {` — and empty when the brace opens something that is not a
    /// trailing closure at all.
    ///
    /// Read backwards from the brace, because that is where ownership is decided. A generic
    /// argument list and an argument list are both stepped over, so `Task<Never, Never>(…) {` is
    /// still `Task`.
    private static func trailingClosureOwner(in opener: [UInt8]) -> [UInt8] {
        var end = opener.count
        while end > 0, opener[end - 1] == ScanByte.space {
            end -= 1
        }
        end = groupStart(closingAt: end, in: opener, open: ScanByte.openParen, close: ScanByte.closeParen)
        end = groupStart(closingAt: end, in: opener, open: ScanByte.openAngle, close: ScanByte.closeAngle)
        var start = end
        while start > 0, ScanByte.isIdentifier(opener[start - 1]) || opener[start - 1] == ScanByte.dot {
            start -= 1
        }
        guard start < end else { return [] }
        return Array(opener[start ..< end].prefix { $0 != ScanByte.dot })
    }

    /// Where the group closing just before `end` opens, or `end` unchanged when nothing closes
    /// there.
    private static func groupStart(closingAt end: Int, in text: [UInt8], open: UInt8, close: UInt8)
        -> Int {
        guard end > 0, text[end - 1] == close else { return end }
        var depth = 0
        var index = end - 1
        while index >= 0 {
            if text[index] == close { depth += 1 }
            if text[index] == open {
                depth -= 1
                if depth == 0 { return index }
            }
            index -= 1
        }
        return end
    }

    private static func collapsed(_ text: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        for byte in text {
            let plain = byte <= ScanByte.space ? ScanByte.space : byte
            if plain == ScanByte.space, out.last == ScanByte.space { continue }
            out.append(plain)
        }
        return out
    }

    /// The statement text before the `{` at `index`.
    ///
    /// Back to the previous `{`, `}`, `;` **or line break** — Swift ends a statement at a newline
    /// too, and leaving that out let an `awaitEvent(` on an entirely separate earlier line bound a
    /// call it does not enclose. A newline inside unclosed brackets is a continuation rather than an
    /// end, which is what keeps a wrapped `awaitEvent(` opener readable, and a span that comes back
    /// empty keeps walking, which is what keeps a brace on its own line readable.
    private static func statement(endingAt index: Int, in code: [UInt8]) -> [UInt8] {
        var start = index - 1
        var brackets = 0
        var lastNonEmpty = index
        while start >= 0 {
            let byte = code[start]
            if ScanByte.isStatementBoundary(byte) { break }
            if byte == ScanByte.closeParen || byte == ScanByte.closeSquare { brackets += 1 }
            if byte == ScanByte.openParen || byte == ScanByte.openSquare { brackets -= 1 }
            if byte == ScanByte.newline, brackets <= 0, !continuesStatement(before: start, in: code) {
                if code[(start + 1) ..< lastNonEmpty].contains(where: { $0 > ScanByte.space }) {
                    return Array(code[(start + 1) ..< index])
                }
                lastNonEmpty = start
            }
            start -= 1
        }
        return Array(code[(start + 1) ..< index])
    }

    private static let declarations = ["func", "init", "deinit", "subscript"].map { Array($0.utf8) }
    private static let bodyKeywords = ["if", "while", "for", "switch", "guard", "catch", "repeat",
                                       "else", "do", "defer"].map { Array($0.utf8) }
    private static let caseClauses = ["case", "default"].map { Array($0.utf8) }
    private static let escapes = ["Task"].map { Array($0.utf8) }
    private static let wrapMarker = Array("awaitEvent".utf8)

    /// Where `needle` occurs as a whole word, or nil. Both sides are checked: without the left one
    /// `mock_awaitEvent(` is a wrap and `if myfunc {` is a declaration; without the right one
    /// `subscriptValue` is a declaration and `awaitEventually(` is a wrap.
    private static func wordIndex(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        return (0 ... haystack.count - needle.count).last {
            Array(haystack[$0 ..< $0 + needle.count]) == needle
                && ($0 == 0 || !ScanByte.isIdentifier(haystack[$0 - 1]))
                && ($0 + needle.count == haystack.count
                    || !ScanByte.isIdentifier(haystack[$0 + needle.count]))
        }
    }

    /// One past the `)` matching the `(` at `open`, or -1 if it is never closed.
    private static func matchingParen(from open: Int, in text: [UInt8]) -> Int {
        var depth = 0
        for index in open ..< text.count {
            if text[index] == ScanByte.openParen { depth += 1 }
            if text[index] == ScanByte.closeParen {
                depth -= 1
                if depth == 0 { return index + 1 }
            }
        }
        return -1
    }
}
