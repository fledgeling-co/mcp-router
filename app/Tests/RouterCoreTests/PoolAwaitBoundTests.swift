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
/// So two of the scan's three layers are the real thing rather than a stand-in. `Delexer`
/// implements Swift's comment and string-literal grammar — line, block, nested block, single-line,
/// multi-line, raw, escapes and interpolation — replacing every comment byte with a space and every
/// literal byte with `ScanByte.elided`, so anything left is code and a value still reads as a value.
/// `AwaitBoundScan` then reads **brace nesting**, which is what Swift actually uses for block
/// structure, so indentation, tabs and `#if` stop being able to say anything.
///
/// **The third layer is still an approximation, and it fails in both directions.** Deciding which
/// call a brace belongs to — `verdict`, `statement`, `firstWord`, and five keyword lists — is a
/// stand-in for Swift's statement and trailing-closure grammar. A previous version of this file
/// said that residue "fails toward a red on correct source rather than toward a miss". That was
/// true of the three unreachable shapes it named and false as a statement about the layer: a
/// verifier then measured two misses and one false fire here in one pass, each pinned by a
/// one-token control. Which way it fails is not predictable from the layer, so a shape found here
/// is a defect until it is measured, not an inconvenience.
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
