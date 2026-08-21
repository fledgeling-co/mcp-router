import Foundation

/// Family B — block structure: where the enclosing block sits relative to the call, and the three
/// layouts that used to decide the answer and no longer can.
enum AwaitBoundShapeControls {
    static let all: [AwaitBoundControl] = [
        AwaitBoundControl(
            "a bare call in a function body reports",
            ["func f() async throws {", "    await p.awaitReap(a)", "}"],
            calls: [2], unbounded: [2]
        ),
        AwaitBoundControl(
            "a wrap on the call's own line bounds it",
            ["func f() async throws {", #"    try await awaitEvent("x") { await p.awaitReap(a) }"#, "}"],
            calls: [2], unbounded: []
        ),
        AwaitBoundControl(
            "a wrap several blocks out bounds it",
            [
                "func f() async throws {",
                #"    try await awaitEvent("x") {"#,
                "        if true {",
                "            do {",
                "                await p.awaitReap(a)",
                "            }",
                "        }",
                "    }",
                "}"
            ],
            calls: [5], unbounded: []
        ),
        AwaitBoundControl(
            "a wrap whose arguments span lines is still the opener",
            [
                "func f() async throws {",
                "    try await awaitEvent(",
                #"        "x""#,
                "    ) {",
                "        await p.awaitReap(a)",
                "    }",
                "}"
            ],
            calls: [5], unbounded: []
        ),
        AwaitBoundControl(
            "a space between the wrapper and its paren is the same wrapper",
            ["func f() async throws {", #"    try await awaitEvent ("x") { await p.awaitReap(a) }"#, "}"],
            calls: [2], unbounded: []
        ),
        AwaitBoundControl(
            "a function whose own signature carries the needle does not wrap its body",
            [
                "func awaitEvent(_ what: String, _ body: () async -> Void) {",
                "    await p.awaitReap(a)",
                "}"
            ],
            calls: [2], unbounded: [2]
        ),
        AwaitBoundControl(
            "two wraps and a bare call is the arithmetic the first scan passed",
            [
                "func f() async throws {",
                #"    try await awaitEvent("x") { await p.awaitReap(a) }"#,
                #"    try await awaitEvent("y") { await p.awaitReap(b) }"#,
                "    await p.awaitReap(c)",
                "}"
            ],
            calls: [2, 3, 4], unbounded: [4]
        ),
        AwaitBoundControl(
            "two calls in one wrap are both bounded, and neither has to be split out",
            [
                "func f() async throws {",
                #"    try await awaitEvent("x") {"#,
                "        await p.awaitReap(a)",
                "        await p.awaitSessionEnded(b)",
                "    }",
                "}"
            ],
            calls: [3, 4], unbounded: []
        ),
        AwaitBoundControl(
            "a call after a sibling wrap has closed is outside it",
            [
                "func f() async throws {",
                #"    try await awaitEvent("x") {"#,
                "        await p.awaitSessionEnded(a)",
                "    }",
                "    await p.awaitSessionEnded(b)",
                "}"
            ],
            calls: [3, 5], unbounded: [5]
        ),
        AwaitBoundControl(
            "a `#if` at column 0 does not unbound the wrap inside it",
            [
                "func f() async throws {",
                "#if DEBUG",
                #"    try await awaitEvent("x") {"#,
                "        await p.awaitReap(a)",
                "    }",
                "#endif",
                "}"
            ],
            calls: [4], unbounded: []
        ),
        AwaitBoundControl(
            "a tab-indented wrapped call is bounded",
            [
                "func f() async throws {",
                "\ttry await awaitEvent(\"x\") {",
                "\t\tawait p.awaitReap(a)",
                "\t}",
                "}"
            ],
            calls: [3], unbounded: []
        ),
        AwaitBoundControl(
            "no indentation at all is bounded",
            [
                "func f() async throws {",
                #"try await awaitEvent("x") {"#,
                "await p.awaitReap(a)",
                "}",
                "}"
            ],
            calls: [3], unbounded: []
        )
    ]
}

/// Family C — Swift's statement and trailing-closure grammar: how a call may be spelled, what only
/// looks like one, and which call a brace belongs to. Split from Family B because SwiftLint's
/// `type_body_length` warns at 250 lines by default, and the seam is a real one: these turn on the
/// call's own shape rather than on the block that encloses it.
///
/// This family's population is **open** — every control is a shape somebody wrote down, not a
/// production of a grammar the scanner implements. `AwaitBoundControl` says so where the count is
/// claimed, and `AwaitBoundStatementControls` carries the rest of the family.
enum AwaitBoundSpellingControls {
    static let all: [AwaitBoundControl] = [
        AwaitBoundControl(
            "a space before the call's paren is the same call",
            ["func f() async throws {", "    await p.awaitReap (a)", "}"],
            calls: [2], unbounded: [2]
        ),
        AwaitBoundControl(
            "a line break between the name and its paren is the same call",
            ["func f() async throws {", "    await p.awaitReap", "        (a)", "}"],
            calls: [2], unbounded: [2]
        ),
        AwaitBoundControl(
            "a longer identifier that starts with the needle is not the needle",
            ["func f() async throws {", "    await p.awaitReaper(a)", "}"],
            calls: [], unbounded: []
        ),
        AwaitBoundControl(
            "a definition is not a call, because a call needs the dot",
            ["func awaitReap(_ name: String) async {", "    await other()", "}"],
            calls: [], unbounded: []
        ),
        AwaitBoundControl(
            "a wrapper named on an earlier statement does not bound a later block",
            [
                "func f() async throws {",
                #"    log(awaitEvent(named: "x"))"#,
                "    if true {",
                "        await p.awaitReap(a)",
                "    }",
                "}"
            ],
            calls: [4], unbounded: [4]
        ),
        AwaitBoundControl(
            "a trailing closure belongs to the call whose arguments close last",
            [
                "func f() async throws {",
                #"    withTimeout(awaitEvent("x")) {"#,
                "        await p.awaitReap(a)",
                "    }",
                "}"
            ],
            calls: [3], unbounded: [3]
        ),
        AwaitBoundControl(
            "a `guard` whose condition names the wrapper does not bound its else block",
            [
                "func f() async throws {",
                #"    guard awaitEvent("x") != nil else {"#,
                "        await p.awaitReap(a)",
                "        return",
                "    }",
                "}"
            ],
            calls: [3], unbounded: [3]
        ),
        AwaitBoundControl(
            "a longer identifier ending in the wrapper's name is not the wrapper",
            [
                "func f() async throws {",
                #"    mock_awaitEvent("x") {"#,
                "        await p.awaitReap(a)",
                "    }",
                "}"
            ],
            calls: [3], unbounded: [3]
        ),
        AwaitBoundControl(
            "an identifier ending in `func` does not terminate the walk",
            [
                "func f() async throws {",
                #"    try await awaitEvent("x") {"#,
                "        let myfunc = true",
                "        if myfunc {",
                "            await p.awaitReap(a)",
                "        }",
                "    }",
                "}"
            ],
            calls: [5], unbounded: []
        ),
        AwaitBoundControl(
            "a brace on its own line still belongs to the opener above it",
            [
                "func f() async throws {",
                #"    try await awaitEvent("x")"#,
                "    {",
                "        await p.awaitReap(a)",
                "    }",
                "}"
            ],
            calls: [4], unbounded: []
        ),
        AwaitBoundControl(
            "an `if` whose condition names the wrapper opens a body, not a wrap",
            [
                "func f() async throws {",
                "    if awaitEvent(ready) {",
                "        await p.awaitReap(a)",
                "    }",
                "}"
            ],
            calls: [3], unbounded: [3]
        ),
        AwaitBoundControl(
            "a `for` whose sequence names the wrapper opens a body, not a wrap",
            [
                "func f() async throws {",
                "    for id in awaitEvent(batch) {",
                "        await p.awaitReap(id)",
                "    }",
                "}"
            ],
            calls: [3], unbounded: [3]
        ),
        AwaitBoundControl(
            "a closure passed as an ordinary argument to the wrapper still bounds",
            [
                "func f() async throws {",
                #"    try await awaitEvent("x", {"#,
                "        await p.awaitReap(a)",
                "    })",
                "}"
            ],
            calls: [3], unbounded: []
        ),
        AwaitBoundControl(
            "an `if` on the line above its condition still opens a body",
            [
                "func f() async throws {",
                "    if",
                #"        awaitEvent("ready") {"#,
                "        await p.awaitReap(a)",
                "    }",
                "}"
            ],
            calls: [4], unbounded: [4]
        ),
        AwaitBoundControl(
            "an `if` further down its own statement still opens a body",
            [
                "func f() async throws {",
                "    let x = 1",
                "    if awaitEvent(x) {",
                "        await p.awaitReap(a)",
                "    }",
                "}"
            ],
            calls: [4], unbounded: [4]
        ),
        AwaitBoundControl(
            "a closure handed to `Task` outlives the wrap it sits in",
            [
                "func f() async throws {",
                #"    try await awaitEvent("x") {"#,
                "        Task.detached {",
                "            await p.awaitReap(a)",
                "        }",
                "    }",
                "}"
            ],
            calls: [4], unbounded: [4]
        ),
        AwaitBoundControl(
            "somebody else's method of the same name is not the wrapper",
            [
                "func f() async throws {",
                #"    analytics.awaitEvent("x") {"#,
                "        await p.awaitReap(a)",
                "    }",
                "}"
            ],
            calls: [3], unbounded: [3]
        ),
        AwaitBoundControl(
            "an `init` inside a wrap runs when the type does, so it is not wrapped",
            [
                "func f() async throws {",
                #"    try await awaitEvent("x") {"#,
                "        struct S {",
                "            init() {",
                "                await p.awaitReap(a)",
                "            }",
                "        }",
                "    }",
                "}"
            ],
            calls: [5], unbounded: [5]
        ),
        AwaitBoundControl(
            "an identifier starting with a declaration keyword does not terminate the walk",
            [
                "func f() async throws {",
                #"    try await awaitEvent("x") {"#,
                "        if subscriptValue {",
                "            await p.awaitReap(a)",
                "        }",
                "    }",
                "}"
            ],
            calls: [4], unbounded: []
        ),
        AwaitBoundControl(
            "a tab between the dot and the name is the same call",
            ["func f() async throws {", "    await p.\tawaitReap(a)", "}"],
            calls: [2], unbounded: [2]
        ),
        AwaitBoundControl(
            "an unapplied method reference awaits nothing and is not a call",
            ["func f() async throws {", "    let g = p.awaitReap(_:epoch:)", "    _ = g", "}"],
            calls: [], unbounded: []
        ),
        AwaitBoundControl(
            "a call at file scope has no enclosing block and reports",
            ["await p.awaitReap(a)"],
            calls: [1], unbounded: [1]
        )
    ]
}
