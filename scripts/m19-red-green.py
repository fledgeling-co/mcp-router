#!/usr/bin/env python3
"""M19's red-green pass — one mutation, one named test, and the exit code is not the evidence.

A test that has never failed is not known to work (SWIFT_PRACTICES.md §7). Each arm names the ONE
test it is supposed to kill and runs that test alone, because *the suite went red* is evidence that
one property is covered and never that the suite covers the change. Four things have to hold before
an arm counts as bitten, and each of them was a way the earlier version of this file reported a
guard as proven when it was not:

  1. **The named test runs at all.** A filter that selects nothing exits 0, so `swift test` reports
     a typo as a clean run. Every run below asserts `1 test in 1 suite`.
  2. **It passes on the unmutated tree.** This is the presence control: an arm that reddens a test
     which was already red measures nothing, and a green baseline is what makes the red mean the
     mutation.
  3. **The mutated run records an issue against that test by name**, read out of the run's own
     output. The name is checked rather than the count, so an ARMS row that drifts away from the
     test it claims is a failure here instead of a pass somewhere else.
  4. **Nothing trapped.** A process killed by `Fatal error:` exits non-zero with no assertion having
     fired, so a crash and a caught defect are identical to an exit-code reader. A2 used to mutate
     a range to `(1 ... 0)` and redden by trapping on it; seven arms sat on a recorded issue and
     that one sat on a crash, and this file reported all eight the same way.

An arm whose mutation does not compile is reported as such rather than counted, for the same reason:
a build that never ran the guard proves nothing about it.

The tests themselves are never edited — a mutation that edits a test proves nothing.
"""
from __future__ import annotations  # `X | None` is evaluated at def time on 3.9; gates run under /usr/bin/python3

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# (id, suite, test function, the test's own display name, file, find, replace)
#
# The display name is the string `swift test` prints, so it is the thing the run's output is matched
# against. Keeping it here rather than paraphrasing the guard is what makes a renamed test a red arm
# instead of a silent pass — the old table's A1 named a guard no test was called.
ARMS = [
    ("A1", "CapabilityDocumentFixtureTests", "everyKindIsCovered",
     "the read me carries every block kind the mock draws",
     "app/Sources/MCPRouterKit/Control/Authored/capability-documents/trawl/README.md",
     "|---|---|---|", "|xxx|xxx|xxx|"),

    # Narrows the drawable heading levels by one. `### Flags worth knowing` in the fixture read me
    # then has no role on the ladder, so it falls back — which is the property this test names, and
    # it is reached by parsing rather than by trapping.
    ("A2", "CapabilityDocumentFixtureTests", "nothingFallsBack",
     "no block in any tab falls back to raw text",
     "app/Sources/MCPRouterKit/Markdown/MarkdownParser.swift",
     "guard (1 ... 3).contains(level) else { return .undrawableLevel }",
     "guard (1 ... 2).contains(level) else { return .undrawableLevel }"),

    ("A3", "MarkdownSecurityTests", "otherSchemesStripped",
     "every other scheme is stripped, and the words stay",
     "app/Sources/MCPRouterKit/Markdown/MarkdownInline.swift",
     'url.scheme?.lowercased() == "https"', "url.scheme != nil"),

    ("A4", "MarkdownSecurityTests", "outsidePackageRefused",
     "every route out of the package is refused, each with its own reason",
     "app/Sources/MCPRouterKit/Markdown/PackageImageResolver.swift",
     "guard candidateParts.count > baseParts.count,\n              Array(candidateParts.prefix(baseParts.count)) == baseParts\n        else {\n            return .failure(.escapesPackage)\n        }",
     "if false { return .failure(.escapesPackage) }"),

    ("A5", "MarkdownSecurityTests", "shieldCarriesNoColour",
     "a parsed shield carries no colour from the badge",
     "app/Sources/MCPRouterKit/Markdown/Shield.swift",
     "return greenNames.contains(lowered) ? .good : .neutral",
     "return lowered.isEmpty ? .good : .neutral"),

    ("A6", "CapabilityDocumentSheetTests", "shieldFillsAreTokens",
     "a shield's fill is one of the app's own two text-safe fills, never the badge's",
     "app/Sources/MCPRouterUI/Document/ShieldView.swift",
     "case .good: .shieldGood", "case .good: .live"),

    ("A7", "CapabilityDocumentSheetTests", "noFabricatedActions",
     "the panel fabricates no action, and the seam a caller uses is the only way in",
     "app/Sources/MCPRouterUI/Document/CapabilityDocumentSheet.swift",
     'Button("Close") { dismiss?() }', 'Button("Install…") { dismiss?() }'),

    ("A8", "MarkdownParserTests", "raggedTable",
     "a ragged table is padded and truncated to its header's width",
     "app/Sources/MCPRouterKit/Markdown/MarkdownParser+Tables.swift",
     "while row.count < columns {\n                row.append(MarkdownInline(literal: \"\"))\n            }", ""),

    # A2's guard is an absence check, and an absence check needs a presence control that is itself
    # alive. This is that control: it turns the only construction of `MarkdownBlock.plainText` back
    # into a paragraph, which is the state the item shipped in and which made A2's guard unfailable.
    ("A9", "MarkdownParserTests", "fourthLevelFallsBackVisibly",
     "a fourth heading level falls back to plain text rather than being drawn or dropped",
     "app/Sources/MCPRouterKit/Markdown/MarkdownParser.swift",
     "blocks.append(.plainText(trimmed))",
     "blocks.append(.paragraph(MarkdownInline(markdown: trimmed)))"),
]

RUN_LINE = re.compile(r"Test run with (\d+) tests? in (\d+) suites? (passed|failed)")
TRAP = re.compile(r"Fatal error|Crashed by signal|Trace/BPT trap|Segmentation fault")


def run(filt: str) -> tuple[int, str]:
    result = subprocess.run(
        ["swift", "test", "--filter", filt], cwd=ROOT / "app", capture_output=True, text=True
    )
    return result.returncode, result.stdout + result.stderr


def selected_one(output: str) -> bool:
    """Whether the run executed exactly the one test the filter names."""
    match = RUN_LINE.search(output)
    return bool(match) and match.group(1) == "1" and match.group(2) == "1"


def outcome(output: str) -> str | None:
    match = RUN_LINE.search(output)
    return match.group(3) if match else None


baseline_cache: dict[str, tuple[bool, str]] = {}
unproven: list[str] = []

for aid, suite, func, display, rel, find, repl in ARMS:
    filt = f"{suite}/{func}"
    path = ROOT / rel

    # 1 & 2 — the control. Cached: every baseline runs against the same unmutated tree.
    if filt not in baseline_cache:
        code, out = run(filt)
        if not selected_one(out):
            baseline_cache[filt] = (False, "the filter selected no test, or more than one")
        elif outcome(out) != "passed":
            baseline_cache[filt] = (False, "the test is already red before any mutation")
        else:
            baseline_cache[filt] = (True, "")
    ok, why = baseline_cache[filt]
    if not ok:
        print(f"{aid}  NO CONTROL — {filt}: {why}")
        unproven.append(aid)
        continue

    original = path.read_text()
    if find not in original:
        print(f"{aid}  COULD NOT ARM — the text it mutates is not in {rel}")
        unproven.append(aid)
        continue

    path.write_text(original.replace(find, repl, 1))
    try:
        code, out = run(filt)
    finally:
        path.write_text(original)

    # 4 — a trap first, because a trapped process also exits non-zero.
    if TRAP.search(out):
        print(f"{aid}  CRASHED   — the mutation trapped the process, so no assertion fired: {display}")
        unproven.append(aid)
        continue
    if not selected_one(out):
        compiled = re.search(r"\.swift:\d+:\d+: error:", out)
        reason = "the mutation did not compile" if compiled else "the run did not report one test"
        print(f"{aid}  NO RUN    — {reason}: {filt}")
        unproven.append(aid)
        continue
    if outcome(out) == "passed":
        print(f"{aid}  SURVIVED  — {display}")
        unproven.append(aid)
        continue

    # 3 — the named test, by name, out of the run's own output.
    if f'Test "{display}" failed' not in out:
        print(f"{aid}  WRONG TEST — the run went red but not through \"{display}\"")
        unproven.append(aid)
        continue

    print(f'{aid}  red       — "{display}" recorded an issue')

print()
if unproven:
    print(f"m19-redgreen: {len(unproven)} arm(s) proved nothing: {', '.join(unproven)}")
    sys.exit(1)
print(f"m19-redgreen: all {len(ARMS)} arms bit, each through the test it names, and every file was restored")
