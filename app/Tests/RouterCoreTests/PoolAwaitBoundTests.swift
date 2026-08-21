import Foundation
import Testing
@testable import RouterCore

/// The standing constraint on `awaitEvent`.
///
/// Its own file for the reason `PoolReapingTests` is its own file — `PoolTestSupport` reached the
/// 400-line limit — and the split pays for itself: the scan skips whichever file spells the needles
/// out, so moving it here puts `PoolTestSupport` back INSIDE the scanned set. A bare call added
/// beside `awaitEvent` is now read rather than excluded.
/// The bound above is worth what its being used is worth, so its being used is asserted.
///
/// `awaitReap` and `awaitSessionEnded` cannot bound themselves: abandoning a wait needs a second
/// task, and a breaker that reports through `#require` needs the caller's source location to name
/// the line that gave up. Both belong out here, which leaves an accessor whose hazard lives in a
/// doc comment — and a doc comment is evidence for the moment somebody reads it. That is the
/// argument `StandingConstraintsTests` already makes for turning a remembered `grep` into an
/// assertion, arriving in the file that needs it.
///
/// The rule is **lexical containment**: a call is bounded when an `awaitEvent` opens a block it sits
/// inside, found by walking outward from the call to the enclosing `func`. Counting wraps per
/// function was the first cut and the panel took it apart — a function holding two `awaitEvent`
/// blocks and one bare call satisfies `calls <= wraps` and passes. Structure answers what
/// arithmetic could not, and it also stops the gate asking for two calls in one block to be split,
/// which the counting version did.
///
/// What it still cannot see, said rather than implied: a call reached through a stored function
/// reference carries no `.awaitReap(` to match, a string literal containing the needle counts as a
/// call, and a bare call added to THIS file is excluded along with the needles it is spelled with.
/// A text scan buys durability, not proof — what it does buy is that the next call site cannot
/// quietly reopen the hole this item was blocked on.
@Suite("The pool's unbounded awaits are called under a bound")
struct PoolAwaitBoundTests {
    /// Spelled with the leading dot so a definition (`func awaitReap`) is not read as a call, and
    /// tolerant of the space in `.awaitReap (`, which is the same call and would otherwise walk
    /// straight through. A newline between the name and its paren still evades it.
    private static let unbounded = [#"\.awaitReap\s*\("#, #"\.awaitSessionEnded\s*\("#]

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
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where isCall(line) {
                seen += 1
                #expect(
                    isBounded(at: index, in: lines),
                    """
                    \(file.lastPathComponent):\(index + 1) awaits a task the pool owns from outside \
                    any `awaitEvent` block. Such an await runs as long as the \
                    arming — 600 000 ms in P6 — so a regression there times the run out instead \
                    of naming a test.
                    """
                )
            }
        }
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

    /// A comment naming an accessor is prose, not a call site — reading one as a call is a red
    /// nobody can act on, and this gate must not be able to report a failure that is not there.
    private func isCall(_ line: String) -> Bool {
        guard !isComment(line) else { return false }
        // A trailing comment is not code either. `foo() // .awaitReap(` read as a call site was a
        // false red the panel wrote out, and a false red is what this gate exists to not be.
        let code = line.components(separatedBy: "//").first ?? line
        return Self.unbounded.contains { code.range(of: $0, options: .regularExpression) != nil }
    }

    private func isComment(_ line: String) -> Bool {
        let body = line.trimmingCharacters(in: .whitespaces)
        return body.hasPrefix("//") || body.hasPrefix("*") || body.hasPrefix("/*")
    }

    /// Whether the call at `index` is lexically inside an `awaitEvent` block.
    ///
    /// Three shapes, and two of them were false reds an out-of-family reviewer wrote out as repros.
    /// The wrap can be on the call's **own** line (`awaitEvent("x") { await pool.awaitReap(…) }`),
    /// which a search that only looks upward never sees. It can be **several levels out**, with an
    /// `if` or a `do` in between, so the nearest enclosing brace is not the answer and the walk has
    /// to keep stepping outward. And it ends at the enclosing `func`, which is where a bare call's
    /// search terminates — the `func` line is never collected, because a function whose own
    /// signature contains the needle would otherwise read as a wrap. That last one was found by
    /// planting a bare call beside `awaitEvent` itself, and grok reached it independently.
    private func isBounded(at index: Int, in lines: [String]) -> Bool {
        if lines[index].contains("awaitEvent(") { return true }
        var depth = indent(of: lines[index]) ?? 0
        var probe = index - 1
        while probe >= 0 {
            let line = lines[probe]
            guard let outer = indent(of: line), outer < depth, !isComment(line) else {
                probe -= 1
                continue
            }
            if line.contains("func ") { return false }
            if opener(endingAt: probe, in: lines).contains("awaitEvent(") { return true }
            depth = outer // an `if`, `do` or `for` — step out a level and keep looking
            probe -= 1
        }
        return false
    }

    /// The opener statement ending at `index`. A tail like `) {` is the END of one rather than the
    /// whole of it, so the walk carries on above it — otherwise an `awaitEvent` whose arguments span
    /// lines would read as an unwrapped call, a red nobody could act on in the gate whose subject is
    /// reds nobody can act on.
    private func opener(endingAt index: Int, in lines: [String]) -> String {
        let outer = indent(of: lines[index])
        var text = ""
        var probe = index
        while probe >= 0 {
            let line = lines[probe]
            if line.contains("func ") { return text }
            text += line
            let tail = line.trimmingCharacters(in: .whitespaces).hasPrefix(")")
            if indent(of: line) == outer, !tail { break }
            probe -= 1
        }
        return text
    }

    /// Blank lines carry no depth, so they neither open nor close anything here.
    private func indent(of line: String) -> Int? {
        let body = line.drop { $0 == " " }
        return body.isEmpty ? nil : line.count - body.count
    }
}
