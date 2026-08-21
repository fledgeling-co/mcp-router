import Testing

/// Controls for `AwaitBoundScan`: one per production for the two grammars it implements, and one per
/// shape somebody wrote down for the layer it approximates.
///
/// The scanner has been defeated twice — by a review panel and then by a verifier who planted 22
/// call sites and got five wrong answers in both directions. Both times the controls were built by
/// hand, run once, and thrown away, so nothing in the tree exercised the classifier and the next
/// reader had only the prose to go on. These stay.
///
/// **What the count covers, family by family — because 64 is not one population.** An earlier
/// version of this comment claimed the set was complete, on the argument that the scanner now holds
/// two grammars rather than an approximation of them. That argument is sound for two of the three
/// families and does not reach the third, and a single number standing across all three read wider
/// than it was.
///
/// - **Family A, the lexical grammar — 19 controls, closed.** Line comment, block comment, nested
///   block comment, single-line literal, multi-line literal, raw literal, escape, interpolation, and
///   a literal nested inside an interpolation. The population is a citable production list, one
///   control per production, plus the three shapes a verifier planted, which are instances of the
///   first two.
/// - **Family B, block structure — 12 controls, closed.** The enclosing block on the call's own
///   line, several levels out, with a wrapped opener, a sibling block already closed, a `func` whose
///   own signature carries the needle, two wraps and a bare call, two calls in one wrap, file scope,
///   and the three layouts that used to decide the answer and no longer can: `#if` at column 0,
///   tabs, and no indentation. The population is brace nesting, which is what Swift uses.
/// - **Family C, Swift's statement and trailing-closure grammar — 33 controls, OPEN.**
///   `verdict`, `statement`, `firstWord` and `continuesStatement`, plus five hand-written keyword
///   lists. Nothing here implements a grammar; each control is a shape somebody wrote down, and the
///   set of shapes somebody might write is exactly the open population the other two families
///   escape. The count is a floor on coverage and not a bound on the space.
///
/// The split is where the defects are, which is why stating it matters. The scanner has been broken
/// by a panel once and by a verifier three times, and every defect of the third round was in Family
/// C: a statement label reading as a wrap, a labelled string-literal argument producing no call site
/// at all, and `Task` inside a string interpolation reddening a correct wrap.
///
/// **What the mutation matrix proves, stated separately for the same reason.** Every control has
/// been seen to fail under at least one single-mechanism mutation, so no mechanism in the code as
/// written is decorative. That is mutation adequacy of the implementation. It is a different claim
/// from covering the grammar the implementation *should* have, and in Family C the two come apart.
///
/// Each control names the direction it holds — the calls the scan must see, and which of them must
/// report. A control that only asserted "no red" would pass on a scan that sees nothing at all,
/// which is the failure the verifier actually found.
///
/// This file is deliberately **not** excluded from the scan, unlike `PoolAwaitBoundTests`. Every
/// needle here sits inside a literal, so a scan that reads it as code is a scan whose literal
/// handling is broken — and the standing-constraint test then reds naming this file, which is a
/// true report rather than a false one.
struct AwaitBoundControl {
    let what: String
    let source: String
    /// 1-based lines where a call site must be found.
    let calls: [Int]
    /// The subset of `calls` that must be reported as outside any `awaitEvent` block.
    let unbounded: [Int]

    init(_ what: String, _ lines: [String], calls: [Int], unbounded: [Int]) {
        self.what = what
        source = lines.joined(separator: "\n")
        self.calls = calls
        self.unbounded = unbounded
    }

    /// Three quotes, spelled as escapes so a fixture can hold a multi-line literal without this
    /// file opening one.
    static let triple = "\"\"\""

    static let all = AwaitBoundLexicalControls.all
        + AwaitBoundShapeControls.all
        + AwaitBoundSpellingControls.all
        + AwaitBoundStatementControls.all
}

/// Controls for `AwaitBoundScan`. What the count covers, family by family — and which family has no
/// closed population — is on `AwaitBoundControl` above.
@Suite("The await-bound scanner, held to a control per production it reads")
struct PoolAwaitBoundControlTests {
    @Test("every control classifies as it says, in both directions")
    func controlsClassifyAsStated() {
        for control in AwaitBoundControl.all {
            let sites = AwaitBoundScan.sites(in: control.source)
            #expect(
                sites.map(\.line) == control.calls,
                "\(control.what): call sites read as \(sites.map(\.line)), expected \(control.calls)"
            )
            #expect(
                sites.filter { !$0.bounded }.map(\.line) == control.unbounded,
                """
                \(control.what): reported \(sites.filter { !$0.bounded }.map(\.line)) as unbounded, \
                expected \(control.unbounded)
                """
            )
        }
    }

    /// A source the lexer loses sync on must be reported as unread, not as clean. A scan that has
    /// lost sync finds no call sites, which is indistinguishable from a file that had none — the
    /// silent miss this whole gate exists to not be.
    @Test("losing sync is reported rather than read as a clean file")
    func lostSyncIsReported() {
        for control in AwaitBoundControl.all {
            #expect(
                AwaitBoundScan.scan(control.source).readable,
                "\(control.what): a well-formed fixture was reported unreadable"
            )
        }
        let broken = [
            ("an unterminated block comment", "func f() {\n    /* never closed\n}"),
            ("an unterminated multi-line literal", "func f() {\n    let s = " + triple + "\n  text\n"),
            ("unbalanced braces", "func f() {\n")
        ]
        for (what, source) in broken {
            #expect(!AwaitBoundScan.scan(source).readable, "\(what) was read as a clean file")
        }
    }

    private let triple = AwaitBoundControl.triple

    /// The invariant every line number in a failure message rests on: delexing replaces bytes, it
    /// never adds or removes any, and it never moves a line break. Asserted over every fixture
    /// rather than argued in a comment, because an offset that means two different things in the
    /// input and the output would misname the file and line the gate exists to name.
    @Test("delexing preserves length and every line break")
    func delexingIsPositionPreserving() {
        for control in AwaitBoundControl.all {
            var delexer = Delexer(control.source)
            let code = delexer.run()
            let source = Array(control.source.utf8)
            #expect(code.count == source.count, "\(control.what): length changed")
            let before = source.indices.filter { source[$0] == ScanByte.newline }
            let after = code.indices.filter { code[$0] == ScanByte.newline }
            #expect(before == after, "\(control.what): line breaks moved")
        }
    }
}

/// Family A — Swift's comment and string-literal grammar, one control per production, plus the
/// three shapes a verifier planted that are instances of the first two.
enum AwaitBoundLexicalControls {
    static let all: [AwaitBoundControl] = [
        AwaitBoundControl(
            "a trailing line comment naming the wrapper is not the wrapper",
            ["func f() async throws {", #"    await p.awaitReap(a) // TODO: wrap in awaitEvent("x")"#, "}"],
            calls: [2], unbounded: [2]
        ),
        AwaitBoundControl(
            "a block comment naming the wrapper is not the wrapper",
            ["func f() async throws {", "    await p.awaitReap(a) /* awaitEvent( */", "}"],
            calls: [2], unbounded: [2]
        ),
        AwaitBoundControl(
            "a URL ending in the wrapper's name is not the wrapper",
            ["func f() async throws {", "    await p.awaitReap(a) // see https://x/awaitEvent(", "}"],
            calls: [2], unbounded: [2]
        ),
        AwaitBoundControl(
            "a `//` inside a literal does not hide the call after it",
            ["func f() async throws {", #"    let u = "http://x"; await p.awaitReap(a)"#, "}"],
            calls: [2], unbounded: [2]
        ),
        AwaitBoundControl(
            "doc prose naming both the wrapper and the call is prose",
            ["/// Wrap it in awaitEvent( before calling p.awaitReap(a).", "func f() async throws {}"],
            calls: [], unbounded: []
        ),
        AwaitBoundControl(
            "a needle inside a single-line literal is not a call, and the next line still is",
            [
                "func f() async throws {",
                #"    let s = "await p.awaitReap(a)""#,
                "    await p.awaitSessionEnded(b)",
                "}"
            ],
            calls: [3], unbounded: [3]
        ),
        AwaitBoundControl(
            "a needle inside a multi-line literal is not a call, and the line count survives it",
            [
                "func f() async throws {",
                "    let s = " + AwaitBoundControl.triple,
                "    await p.awaitReap(a)",
                "    " + AwaitBoundControl.triple,
                "    await p.awaitSessionEnded(b)",
                "}"
            ],
            calls: [5], unbounded: [5]
        ),
        AwaitBoundControl(
            "a needle inside a raw literal carrying quotes is not a call",
            [
                "func f() async throws {",
                ##"    let s = #"say "await p.awaitReap(a)" now"#"##,
                "    await p.awaitSessionEnded(b)",
                "}"
            ],
            calls: [3], unbounded: [3]
        ),
        AwaitBoundControl(
            "a wrapped call inside a block comment is not a call",
            [
                "func f() async throws {",
                "    /*",
                #"    try await awaitEvent("x") { await p.awaitReap(a) }"#,
                "    */",
                "    _ = 1",
                "}"
            ],
            calls: [], unbounded: []
        ),
        AwaitBoundControl(
            "a nested block comment closes once, not at its inner terminator",
            [
                "func f() async throws {",
                "    /* outer /* inner */ await p.awaitReap(a) */",
                "    await p.awaitSessionEnded(b)",
                "}"
            ],
            calls: [3], unbounded: [3]
        ),
        AwaitBoundControl(
            "code after a block comment closes mid-line is code",
            ["func f() async throws {", "    /* note */ await p.awaitReap(a)", "}"],
            calls: [2], unbounded: [2]
        ),
        AwaitBoundControl(
            "a literal nested inside an interpolation does not put the scan out of step",
            [
                "func f() async throws {",
                ##"    let s = "\(d[".awaitReap(b)"]) x""##,
                "    await p.awaitReap(a)",
                "}"
            ],
            calls: [3], unbounded: [3]
        ),
        AwaitBoundControl(
            "a non-ASCII identifier is blanked in place, so nothing after it moves",
            [
                "func f() async throws {",
                "    let caf\u{00E9} = 1",
                "    await p.awaitReap(caf\u{00E9})",
                "}"
            ],
            calls: [3], unbounded: [3]
        ),
        AwaitBoundControl(
            "an escaped quote does not end the literal it sits in",
            [
                "func f() async throws {",
                ##"    let s = "a \" .awaitReap(b)""##,
                "    await p.awaitSessionEnded(c)",
                "}"
            ],
            calls: [3], unbounded: [3]
        ),
        AwaitBoundControl(
            "a raw literal holding two quotes is not a multi-line opener",
            [
                "func f() async throws {",
                ###"    let s = #""""#"###,
                "    await p.awaitSessionEnded(b)",
                "}"
            ],
            calls: [3], unbounded: [3]
        ),
        AwaitBoundControl(
            "trailing spaces before the line break still open a multi-line literal",
            [
                "func f() async throws {",
                "    let s = " + AwaitBoundControl.triple + "  ",
                "    await p.awaitReap(a)",
                "    " + AwaitBoundControl.triple,
                "    await p.awaitSessionEnded(b)",
                "}"
            ],
            calls: [5], unbounded: [5]
        ),
        AwaitBoundControl(
            "a CRLF file's multi-line literal is still a literal",
            [
                "func f() async throws {\r",
                "    let s = " + AwaitBoundControl.triple + "\r",
                "    await p.awaitReap(a)\r",
                "    " + AwaitBoundControl.triple + "\r",
                "    await p.awaitSessionEnded(b)\r",
                "}"
            ],
            calls: [5], unbounded: [5]
        ),
        AwaitBoundControl(
            "a file ending in a line comment with no trailing newline is a whole file",
            ["func f() async throws {", "    await p.awaitReap(a)", "} // done"],
            calls: [2], unbounded: [2]
        ),
        AwaitBoundControl(
            "a brace inside a literal is not block structure",
            [
                "func f() async throws {",
                #"    try await awaitEvent("x") {"#,
                #"        let s = "}""#,
                "        await p.awaitReap(a)",
                "    }",
                "}"
            ],
            calls: [4], unbounded: []
        )
    ]
}
