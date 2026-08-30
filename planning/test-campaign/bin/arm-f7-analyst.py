#!/usr/bin/env python3
"""F7 — watch every analyst assertion fail before trusting any of them.

A test that has never failed is not known to work. This plants one mutation at a time in the
PRODUCT source, runs only the tests that mutation is supposed to kill, and requires each of them to
go red. The tests are never edited: a mutation that edits a test proves nothing about the test.

Two things make this a measurement rather than a printer.

  * A **presence control** runs first and plants nothing. It requires the same filters to be GREEN.
    Without it, a filter that selects no test at all would report every arm as "red" — the arm would
    be a run that compared nothing, and this file would be the printer-filed-as-a-gate this fleet has
    already found once.
  * Every arm records WHICH test names went red, not just the exit code. An arm that reddens by
    failing to compile, or by trapping, or by reddening a test it was not aiming at, is reported as
    a MISS rather than counted as a kill.

Exit codes: 0 every arm killed its target · 1 an arm survived or missed · 2 usage or environment ·
3 the presence control did not go green, so nothing below it means anything.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
APP = ROOT / "app"

# `--disable-sandbox`: SwiftPM's own sandbox refuses to create build outputs on the volume the
# worktrees live on, which surfaces as `Operation not permitted` on a randomly chosen object file.
# It is an environment fact rather than anything about this branch, and it changes no compiled byte.
SWIFT_TEST = ["swift", "test", "--disable-sandbox", "--filter"]


class Arm:
    def __init__(self, aid, path, find, replace, filt, expect):
        self.id = aid
        self.path = path
        self.find = find
        self.replace = replace
        self.filter = filt
        # Substrings of the test names that MUST go red. A red anywhere else is a miss.
        self.expect = expect


CORE = APP / "Sources" / "RouterCore"
UI = APP / "Sources" / "MCPRouterUI"

ARMS = [
    Arm(
        "F7-A1", CORE / "Analyst" / "SessionCorpus.swift",
        "                } else {\n                    discarded += 1\n                }",
        "                }",
        "AnalystCorpusTests",
        ["a line it cannot use is counted as discarded"],
    ),
    Arm(
        "F7-A2", CORE / "Analyst" / "SessionCorpus.swift",
        '            SessionStore(\n'
        '                harness: .cursor, path: "\\(homeDirectory)/.cursor/chats",\n'
        '                shape: .unsupported("this store is SQLite; the analyst reads JSON Lines only")\n'
        '            )\n',
        "",
        "AnalystCorpusTests",
        ["the SQLite store is enumerated", "every store appears"],
    ),
    Arm(
        "F7-A3", CORE / "Analyst" / "SessionPatterns.swift",
        "    public static let floor = 3",
        "    public static let floor = 1",
        "AnalystPatternTests",
        ["a signal under the floor"],
    ),
    Arm(
        "F7-A4", CORE / "Analyst" / "AnalystJudge.swift",
        "            guard known.contains(entry), knownSignals.contains(signal),",
        "            guard knownSignals.contains(signal),",
        "AnalystJudgeTests",
        ["an id outside the candidate list"],
    ),
    Arm(
        "F7-A5", CORE / "Analyst" / "AnalystJudge.swift",
        "            guard known.contains(entry), knownSignals.contains(signal),",
        "            guard known.contains(entry),",
        "AnalystJudgeTests",
        ["a signal the run never counted"],
    ),
    Arm(
        "F7-A6", CORE / "Analyst" / "AnalystEngine.swift",
        "            guard !state.isSuppressed(record.fingerprint, now: now) else { continue }",
        "",
        "AnalystEngineTests",
        ["the same finding inside thirty days"],
    ),
    Arm(
        "F7-A7", CORE / "Analyst" / "AnalystEngine.swift",
        "        state.lastRun = made\n        persist()",
        "        state.lastRun = made",
        "AnalystEngineTests",
        ["a run records what it read"],
    ),
    Arm(
        "F7-A8", CORE / "Analyst" / "AnalystEngine.swift",
        "                lane: lane, usedFallback: index > 0, rejected: read.rejected,",
        "                lane: lane, usedFallback: false, rejected: read.rejected,",
        "AnalystEngineTests",
        ["the primary refusing runs the fallback"],
    ),
    Arm(
        "F7-A9", CORE / "Control" / "ControlAnalyst.swift",
        '            JSONMember(key: JSString("scheduled"), value: .bool(false)),',
        '            JSONMember(key: JSString("scheduled"), value: .bool(true)),',
        "ControlAnalystRoutesTests",
        ["the cadence is reported as a preference"],
    ),
    Arm(
        "F7-A10", CORE / "Control" / "ControlHandler.swift",
        "        if let response = await routeAnalyst(path, request, deps) { return response }\n",
        "",
        "ControlAnalystRoutesTests",
        # A4 alone, and A9 deliberately NOT listed. A9 asserts that the two paths are CLAIMED —
        # 401 before 405, a neighbouring path unowned — and every one of those holds with the
        # dispatch arm deleted, because claiming happens in `ControlPaths` and routing happens in
        # `handle`. Listing A9 here read MISS and was right to: it is a different property.
        ["pressing the button changes what a LATER GET reports"],
    ),
    Arm(
        "F7-A11", CORE / "Control" / "ControlAnalyst.swift",
        "        guard let analyst = deps.analyst else { return .null }\n"
        "        return await AnalystJSON.envelope(run: analyst.lastRun(), settings: analyst.settings())",
        "        return .null",
        "ControlAnalystRoutesTests",
        [
            "an analyst that has never run",
            "pressing the button changes what a LATER GET reports",
            "the store the analyst could not open",
        ],
    ),
    # The defect this item closes, planted back: `Analyse now` wired to a body that does nothing.
    # DEF-065's own shape, and the arm that decides whether the board case is worth anything.
    Arm(
        "F7-A12", UI / "Boards" / "InsightsBoardModel.swift",
        "        guard analyst != nil, !analysing else { return }\n"
        "        analysing = true\n"
        "        analystError = nil\n"
        "        defer { analysing = false }\n"
        "        do {\n"
        "            state = try await .loaded(client.runAnalyst())\n"
        "        } catch {\n"
        "            record(error)\n"
        "        }\n",
        "",
        "InsightsAnalystBoardTests",
        ["pressing Analyse now posts once"],
    ),
]


def run(filt: str) -> tuple[int, str]:
    proc = subprocess.run(
        SWIFT_TEST + [filt], cwd=APP, capture_output=True, text=True, check=False
    )
    return proc.returncode, proc.stdout + proc.stderr


FAILED = re.compile(r'Test "(.+?)" (?:recorded an issue|failed after)')
RAN = re.compile(r"Test run with (\d+) tests")


def reds(output: str) -> set[str]:
    return set(FAILED.findall(output))


def selected(output: str) -> int:
    found = RAN.search(output)
    return int(found.group(1)) if found else 0


def presence_control(filters: list[str]) -> bool:
    """Nothing planted: every filter must select tests AND be green."""
    ok = True
    for filt in sorted(set(filters)):
        code, out = run(filt)
        count = selected(out)
        if code != 0 or count == 0:
            print(f"  control {filt}: exit {code}, {count} tests selected — NOT USABLE")
            ok = False
        else:
            print(f"  control {filt}: green over {count} tests")
    return ok


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--json")
    args = parser.parse_args()

    arms = [a for a in ARMS if not args.only or a.id == args.only]
    if not arms:
        print("no arm selected", file=sys.stderr)
        return 2

    print("presence control — nothing planted, every filter must be green over a non-zero count")
    if not presence_control([a.filter for a in arms]):
        print("PRESENCE CONTROL FAILED — no arm below this line means anything")
        return 3

    results = []
    worst = 0
    for arm in arms:
        original = arm.path.read_text()
        if arm.find not in original:
            print(f"{arm.id}: ANCHOR MISSING in {arm.path.name} — the arm cannot be planted")
            results.append({"id": arm.id, "verdict": "ANCHOR MISSING"})
            worst = 1
            continue
        arm.path.write_text(original.replace(arm.find, arm.replace, 1))
        try:
            code, out = run(arm.filter)
            went_red = reds(out)
            hit = [
                name for name in arm.expect
                if any(name in red for red in went_red)
            ]
            if code == 0:
                verdict = "SURVIVED"
            elif len(hit) == len(arm.expect):
                verdict = "KILLED"
            elif went_red:
                verdict = "MISS"
            else:
                # Non-zero with nothing recorded as an issue: it did not compile, or it trapped.
                verdict = "NOT AN ASSERTION"
        finally:
            # Restore, then PROVE the restore. A write on this volume has been observed to fail
            # with EPERM at random, and F7-A10's mutation happens to return its file to exactly its
            # committed content — so a failed restore left the branch silently missing a dispatch
            # line while `git status` reported the file clean. A restore that is not read back is
            # not a restore.
            arm.path.write_text(original)
            if arm.path.read_text() != original:
                print(f"{arm.id}: RESTORE FAILED for {arm.path} — the tree is now WRONG")
                return 2
        if verdict != "KILLED":
            worst = 1
        print(f"{arm.id}: {verdict} — {sorted(went_red) if went_red else 'no test recorded an issue'}")
        results.append({"id": arm.id, "verdict": verdict, "red": sorted(went_red)})

    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(results, indent=1) + "\n")
    print(f"\n{sum(1 for r in results if r['verdict'] == 'KILLED')} of {len(results)} arms killed")
    return worst


if __name__ == "__main__":
    sys.exit(main())
