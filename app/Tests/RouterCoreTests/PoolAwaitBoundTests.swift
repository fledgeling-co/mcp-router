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
        for file in files {
            let sites = try AwaitBoundScan.sites(in: String(contentsOf: file, encoding: .utf8))
            seen += sites.count
            offenders += sites.filter { !$0.bounded }.map { "\(file.lastPathComponent):\($0.line)" }
        }
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
        var delexer = Delexer(source)
        let code = delexer.run()
        return callOffsets(in: code).map {
            Site(line: line(at: $0, in: code), bounded: isBounded(callAt: $0, in: code))
        }
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
        return index + 1
    }

    private static func matches(_ name: [UInt8], at index: Int, in code: [UInt8]) -> Bool {
        guard index + name.count <= code.count else { return false }
        return Array(code[index ..< index + name.count]) == name
    }

    private static func skipSpace(from index: Int, in code: [UInt8]) -> Int {
        var index = index
        while index < code.count, code[index] == ScanByte.space || code[index] == ScanByte.newline {
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

    /// The statement the `{` at `index` terminates — back to the previous `{`, `}` or `;`. A span
    /// rather than a line is what lets an `awaitEvent(` whose arguments wrap be seen as the opener
    /// it is, and the reason no indentation is consulted anywhere.
    ///
    /// `func ` is tested first and it is load-bearing: a function whose own signature contains the
    /// needle — `func awaitEvent(…) {` — would otherwise read as a wrap around its own body, which
    /// is how a bare call planted beside `awaitEvent` first got through.
    private static func verdict(forBlockOpenedAt index: Int, in code: [UInt8]) -> Verdict {
        var start = index - 1
        while start >= 0, !ScanByte.isStatementBoundary(code[start]) {
            start -= 1
        }
        let opener = Array(code[(start + 1) ..< index])
        if contains(Self.funcMarker, in: opener) { return .function }
        // Whitespace removed for the wrapper test alone, so `awaitEvent (` and an opener whose
        // arguments wrap onto their own lines are both the wrapper they look like.
        if contains(Self.wrapMarker, in: opener.filter { $0 > ScanByte.space }) { return .bounded }
        return .keepWalking
    }

    private static let funcMarker = Array("func ".utf8)
    private static let wrapMarker = Array("awaitEvent(".utf8)

    private static func contains(_ needle: [UInt8], in haystack: [UInt8]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        return (0 ... haystack.count - needle.count).contains {
            Array(haystack[$0 ..< $0 + needle.count]) == needle
        }
    }
}
