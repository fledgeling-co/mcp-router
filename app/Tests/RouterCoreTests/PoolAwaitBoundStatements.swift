import Foundation

/// Family C's machinery — Swift's statement and trailing-closure grammar, approximated.
///
/// Split from `PoolAwaitBoundScan.swift` because that file passed SwiftLint's 400-line
/// `file_length` default, and the seam is the one that matters: everything here is the layer
/// `AwaitBoundControl` names as having **no closed population**. `Delexer` implements a grammar and
/// the brace walk reads Swift's own block structure; this file guesses which call a brace belongs
/// to, from paren matching and five keyword lists. Every defect a reader has found in the rebuilt
/// scanner has been in this layer.
///
/// Members are internal rather than private because `private` does not cross a file boundary, and
/// the split is a length constraint rather than an interface decision.
extension AwaitBoundScan {
    /// Whether what sits just before `index` is something no statement can end on, so the line
    /// break is a continuation. `if` on its own line above its condition is legal Swift, and without
    /// this the span starts below the `if` and the body reads as the wrapper's trailing closure.
    ///
    /// A trailing `.` is the same case, and an out-of-family lane found it: `analytics.` ⏎
    /// `awaitEvent("x") { … }` put the span below the receiver, so somebody else's method read as
    /// the free wrapper and a genuinely unbounded call passed.
    static func continuesStatement(before index: Int, in code: [UInt8]) -> Bool {
        var end = index
        while end > 0, code[end - 1] <= ScanByte.space {
            end -= 1
        }
        if end > 0, code[end - 1] == ScanByte.dot { return true }
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
    static func firstWord(of opener: [UInt8]) -> [UInt8] {
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
    static func statementPrefixEnd(after word: Range<Int>, in opener: [UInt8]) -> Int? {
        guard !word.isEmpty else { return nil }
        if caseClauses.contains(Array(opener[word])) {
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
    static func clauseColon(from index: Int, in opener: [UInt8]) -> Int? {
        var depth = 0
        for probe in index ..< opener.count {
            let byte = opener[probe]
            if byte == ScanByte.openParen || byte == ScanByte.openSquare { depth += 1 }
            if byte == ScanByte.closeParen || byte == ScanByte.closeSquare { depth -= 1 }
            if byte == ScanByte.colon, depth == 0 { return probe + 1 }
        }
        return nil
    }

    static func wordSpan(from index: Int, in opener: [UInt8]) -> Range<Int> {
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

    /// The dot-separated components of the call this `{` is a closure of — `[Task]` for `Task {`,
    /// `[Task, detached]` for `Task.detached(priority: .high) {`, `[_Concurrency, Task]` for the
    /// module-qualified spelling, `[analytics, awaitEvent]` for `analytics.awaitEvent("x") {` — and
    /// empty when the brace opens something that is not a closure argument at all.
    ///
    /// Every component, not the root: an out-of-family lane broke a root-only reading with
    /// `_Concurrency.Task { … }`, which is `Task` wearing its module name and escapes exactly as
    /// hard.
    ///
    /// Two positions the brace can hold, and **both** are read, because either one being `Task` is
    /// enough for the closure to outlive the wait. The brace TRAILS a call — `Task.detached {` — or
    /// it sits inside an argument list the opener never closes — `Task.detached(operation: {`. An
    /// out-of-family lane broke a trailing-only reading with the second, and reading only the second
    /// misses `keep(Task { … })`, where the brace trails `Task` inside somebody else's list.
    static func closureOwner(in opener: [UInt8]) -> [[UInt8]] {
        var trailing = opener.count
        while trailing > 0, opener[trailing - 1] == ScanByte.space {
            trailing -= 1
        }
        trailing = groupStart(closingAt: trailing, in: opener,
                              open: ScanByte.openParen, close: ScanByte.closeParen)
        trailing = groupStart(closingAt: trailing, in: opener,
                              open: ScanByte.openAngle, close: ScanByte.closeAngle)
        return [trailing, openArgumentList(in: opener)].flatMap { chainComponents(endingAt: $0, in: opener) }
    }

    /// The dot-separated identifier chain ending at `end`, or nothing when there is none there.
    static func chainComponents(endingAt end: Int, in opener: [UInt8]) -> [[UInt8]] {
        guard end >= 0 else { return [] }
        var start = end
        while start > 0, ScanByte.isIdentifier(opener[start - 1]) || opener[start - 1] == ScanByte.dot {
            start -= 1
        }
        guard start < end else { return [] }
        return opener[start ..< end].split(separator: ScanByte.dot).map(Array.init)
    }

    /// The innermost `(` the opener never closes, or -1 when every one of them closes. That `(`
    /// belongs to the call whose argument list the brace is sitting inside.
    static func openArgumentList(in opener: [UInt8]) -> Int {
        var stack: [Int] = []
        for index in opener.indices {
            if opener[index] == ScanByte.openParen { stack.append(index) }
            if opener[index] == ScanByte.closeParen, !stack.isEmpty { stack.removeLast() }
        }
        return stack.last ?? -1
    }

    /// Where the group closing just before `end` opens, or `end` unchanged when nothing closes
    /// there.
    static func groupStart(
        closingAt end: Int, in text: [UInt8], open: UInt8, close: UInt8
    ) -> Int {
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

    static func collapsed(_ text: [UInt8]) -> [UInt8] {
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
    static func statement(endingAt index: Int, in code: [UInt8]) -> [UInt8] {
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

    /// Where `needle` occurs as a whole word that is not a member spelling, or nil. A declaration
    /// keyword after a `.` is somebody's member — `awaitEvent(.init("x")) { … }` is a correct wrap
    /// whose argument names `init`, and reading that as a declaration reddened it. The wrapper's own
    /// marker has been checked this way since a lane wrote out `analytics.awaitEvent`.
    static func unqualifiedIndex(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        // The LAST unqualified occurrence, not "the last occurrence, if unqualified" — an opener
        // may carry both spellings and only the qualified one would be seen.
        wordIndices(of: needle, in: haystack).last { !isQualified(at: $0, in: haystack) }
    }

    /// Whether the word at `at` is somebody's member — the nearest byte before it that is not
    /// whitespace is a `.`. Whitespace is skipped because `collapsed` turns a line break after the
    /// receiver's dot into a space, which a byte-before test reads as no dot at all.
    static func isQualified(at index: Int, in text: [UInt8]) -> Bool {
        lastMeaningful(before: index, in: text) == ScanByte.dot
    }

    /// Where `needle` occurs as a whole word, or nil. Both sides are checked: without the left one
    /// `mock_awaitEvent(` is a wrap and `if myfunc {` is a declaration; without the right one
    /// `subscriptValue` is a declaration and `awaitEventually(` is a wrap.
    static func wordIndex(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        wordIndices(of: needle, in: haystack).last
    }

    /// Every whole-word occurrence of `needle`, in order.
    static func wordIndices(of needle: [UInt8], in haystack: [UInt8]) -> [Int] {
        guard needle.count <= haystack.count else { return [] }
        return (0 ... haystack.count - needle.count).filter {
            Array(haystack[$0 ..< $0 + needle.count]) == needle
                && ($0 == 0 || !ScanByte.isIdentifier(haystack[$0 - 1]))
                && ($0 + needle.count == haystack.count
                    || !ScanByte.isIdentifier(haystack[$0 + needle.count]))
        }
    }

    /// One past the `)` matching the `(` at `open`, or -1 if it is never closed.
    static func matchingParen(from open: Int, in text: [UInt8]) -> Int {
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
