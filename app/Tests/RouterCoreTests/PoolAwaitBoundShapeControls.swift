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
                "func awaitEvent(_ what: String, _ body: () async -> Void) async throws {",
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
        ),
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
            "a call at file scope has no enclosing block and reports",
            ["await p.awaitReap(a)"],
            calls: [1], unbounded: [1]
        )
    ]
}
