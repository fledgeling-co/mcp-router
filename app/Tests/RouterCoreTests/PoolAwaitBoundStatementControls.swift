import Foundation

/// Family C, continued — Swift's statement grammar: the prefixes that introduce a statement without
/// being one, and the call the brace actually belongs to.
///
/// A separate enum from `AwaitBoundSpellingControls` for the 250-line type-body limit, and the same
/// family: its population is open, and `AwaitBoundControl` says so where the count is claimed.
///
/// Every control here was written from a defect a reader found by construction rather than from
/// reading the code, and each carries the **one token** that pins it: delete the label, swap the
/// literal for an identifier, or swap `Task` for `Clock`, and the scan changes its answer.
enum AwaitBoundStatementControls {
    static let all: [AwaitBoundControl] = [
        AwaitBoundControl(
            "a statement label does not turn a control-flow body into a wrap",
            [
                "func f() async throws {",
                "    check: if awaitEvent(x) {",
                "        await p.awaitReap(a)",
                "    }",
                "}"
            ],
            calls: [3], unbounded: [3]
        ),
        AwaitBoundControl(
            "a labelled loop is a body too, and the label is the only difference",
            [
                "func f() async throws {",
                "    outer: while awaitEvent(x) {",
                "        await p.awaitReap(a)",
                "    }",
                "}"
            ],
            calls: [3], unbounded: [3]
        ),
        AwaitBoundControl(
            "a label on a real wrap still bounds, so skipping the label costs no green",
            [
                "func f() async throws {",
                #"    lbl: try await awaitEvent("x") {"#,
                "        await p.awaitReap(a)",
                "    }",
                "}"
            ],
            calls: [3], unbounded: []
        ),
        AwaitBoundControl(
            "a `case` clause introduces the statement after it, so an `if` body is still a body",
            [
                "func f() async throws {",
                "    switch k {",
                "    case .a: if awaitEvent(x) {",
                "        await p.awaitReap(a)",
                "    }",
                "    }",
                "}"
            ],
            calls: [4], unbounded: [4]
        ),
        AwaitBoundControl(
            "a `case` clause does not stop the wrap after it bounding",
            [
                "func f() async throws {",
                "    switch k {",
                #"    case .a: try await awaitEvent("x") {"#,
                "        await p.awaitReap(a)",
                "    }",
                "    }",
                "}"
            ],
            calls: [4], unbounded: []
        ),
        AwaitBoundControl(
            "a labelled string-literal argument is a call, not a method reference",
            ["func f() async throws {", #"    await p.awaitReap(name: "own")"#, "}"],
            calls: [2], unbounded: [2]
        ),
        AwaitBoundControl(
            "the same call with an identifier in place of the literal reads the same",
            ["func f() async throws {", "    await p.awaitReap(name: own)", "}"],
            calls: [2], unbounded: [2]
        ),
        AwaitBoundControl(
            "a labelled argument spelled entirely above ASCII is a call, the same miss's other door",
            ["func f() async throws {", "    await p.awaitReap(name: \u{540D}\u{524D})", "}"],
            calls: [2], unbounded: [2]
        ),
        AwaitBoundControl(
            "a wrapper naming `Task` in its own message is still the wrapper",
            [
                "func f() async throws {",
                #"    try await awaitEvent("reap at \(Task.currentPriority)") {"#,
                "        await p.awaitReap(a)",
                "    }",
                "}"
            ],
            calls: [3], unbounded: []
        ),
        AwaitBoundControl(
            "`Task` spelled with its generic arguments still escapes the wrap",
            [
                "func f() async throws {",
                #"    try await awaitEvent("x") {"#,
                "        Task<Never, Never> {",
                "            await p.awaitReap(a)",
                "        }",
                "    }",
                "}"
            ],
            calls: [4], unbounded: [4]
        ),
        AwaitBoundControl(
            "`Task.detached` with an argument list still escapes the wrap",
            [
                "func f() async throws {",
                #"    try await awaitEvent("x") {"#,
                "        Task.detached(priority: .high) {",
                "            await p.awaitReap(a)",
                "        }",
                "    }",
                "}"
            ],
            calls: [4], unbounded: [4]
        )
    ]
}
