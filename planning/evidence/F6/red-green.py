#!/usr/bin/env python3
"""F6 — one mutation at a time, and which assertions notice.

A test that has never failed is not known to work. Each mutation below edits the
IMPLEMENTATION and names the tests it is supposed to kill; the tests are never touched,
because a mutation that edits a test proves nothing. A mutation that leaves the suite green
is a decoration exposed, and is reported SURVIVED.

    python3 planning/evidence/F6/red-green.py [--only ID]

Exit 0 when every mutation was caught by the test it names, 1 otherwise.
"""
from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
APP = ROOT / "app"
SRC = APP / "Sources" / "RouterCore"
FILTER = (
    "SemanticVersionTests|MarketplaceCatalogueTests|ExtensionFreshnessTests"
    "|ExtensionFreshnessScanTests|ControlUpdateRoutesTests"
)

MUTATIONS = [
    (
        "M1", "Extensions/SemanticVersion.swift",
        "guard let left = parse(lhs), let right = parse(rhs) else { return nil }",
        "guard let left = parse(lhs), let right = parse(rhs) else { return .orderedAscending }",
        ["S3", "F4"],
        "two unorderable versions are declared ascending, so a SHA is always behind",
    ),
    (
        "M2", "Extensions/ExtensionFreshness.swift",
        "        case .orderedAscending:\n            return .updateAvailable(installed: installed, available: available)\n"
        "        case .orderedDescending:\n            return .catalogueBehind(installed: installed, available: available)",
        "        case .orderedAscending:\n            return .catalogueBehind(installed: installed, available: available)\n"
        "        case .orderedDescending:\n            return .updateAvailable(installed: installed, available: available)",
        ["F1", "F3", "G1"],
        "the direction is inverted, so a stale catalogue reads as an available update",
    ),
    (
        "M3", "Extensions/ExtensionFreshness.swift",
        "    public var hasUpdate: Bool {\n        if case .updateAvailable = self { return true }\n        return false\n    }",
        "    public var hasUpdate: Bool {\n        if case .updateAvailable = self { return true }\n"
        "        if case .catalogueBehind = self { return true }\n        return false\n    }",
        ["F3", "F12"],
        "catalogueBehind is counted as an update — the downgrade-as-update bug",
    ),
    (
        "M4", "Extensions/ExtensionFreshness.swift",
        "        guard let available = offer.version else {\n            return .catalogueDeclaresNoVersion(installed: installedVersion)\n        }\n"
        "        guard let installed = installedVersion else { return .installedDeclaresNoVersion }\n"
        "        if installed == available { return .current(installed) }",
        "        if installedVersion == offer.version { return .current(installedVersion ?? \"\") }\n"
        "        guard let available = offer.version else {\n            return .catalogueDeclaresNoVersion(installed: installedVersion)\n        }\n"
        "        guard let installed = installedVersion else { return .installedDeclaresNoVersion }",
        ["F9"],
        "the equality check runs first, so two ABSENT versions read as two equal ones",
    ),
    (
        "M5", "Control/ControlExtensions.swift",
        '        if rest == "/updates" { return nil }\n',
        "",
        ["U4"],
        "the :kind match reclaims /extensions/updates, so a DELETE on it answers 404",
    ),
    (
        "M6", "Extensions/ExtensionFreshnessScan.swift",
        "            let age = (raw ?? 0) < 0 ? nil : raw",
        "            let age = raw",
        ["G10", "U7"],
        "a negative age is reported as a number, so a future-stamped catalogue is fresh forever",
    ),
    (
        "M7", "Extensions/ExtensionFreshness.swift",
        "        case .installedDeclaresNoVersion, .catalogueDeclaresNoVersion, .notOffered, .noCatalogue:\n            false\n        }\n    }\n\n    /// The slug",
        "        case .installedDeclaresNoVersion, .catalogueDeclaresNoVersion, .notOffered, .noCatalogue:\n            true\n        }\n    }\n\n    /// The slug",
        ["F12", "G2"],
        "everything counts as compared, so `0 updates` no longer distinguishes a read from a silence",
    ),
    (
        "M8", "Extensions/MarketplaceCatalogue.swift",
        "                name: name, version: (version?.isEmpty ?? true) ? nil : version",
        "                name: name, version: version",
        ["C1"],
        'an empty-string version is kept, so it compares unequal to everything',
    ),
    (
        "M9", "Extensions/ExtensionDescriptor.swift",
        '            if key == "version", !value.isEmpty { version = value }\n',
        "",
        ["G1"],
        "a skill's declared version is never read, so every versioned skill reads as silent",
    ),
    (
        "M10", "Extensions/ExtensionFreshnessScan.swift",
        "                problem: problem,\n                ageProblem: ageProblem",
        "                problem: problem ?? ageProblem,\n                ageProblem: ageProblem",
        ["G10", "U7"],
        "an unmeasurable AGE suppresses every comparison against a catalogue that reads fine",
    ),
]


def run_suite() -> str:
    result = subprocess.run(
        ["swift", "test", "--filter", FILTER],
        cwd=APP, capture_output=True, text=True,
    )
    return result.stdout + result.stderr


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    arguments = parser.parse_args()

    print(f"# F6 red-green — {len(MUTATIONS)} mutations, filter {FILTER}")
    baseline = run_suite()
    if "Test run with" not in baseline or "passed after" not in baseline.split("Test run with")[-1]:
        print("BASELINE NOT GREEN — nothing below means anything")
        print(baseline[-3000:])
        return 1
    print("baseline: green\n")

    failures = 0
    for mid, relative, find, replace, expect, why in MUTATIONS:
        if arguments.only and arguments.only != mid:
            continue
        path = SRC / relative
        original = path.read_text()
        if find not in original:
            print(f"{mid}  NOT APPLICABLE  {relative} — the text this mutates is gone")
            failures += 1
            continue
        path.write_text(original.replace(find, replace, 1))
        try:
            output = run_suite()
        finally:
            path.write_text(original)
        red = sorted({
            token for token in expect
            if any(
                line.strip().startswith("✘") or "issue" in line or "failed" in line
                for line in output.splitlines()
                if f'"{token} ' in line or f"'{token} " in line
            )
        })
        caught = set(red) == set(expect)
        status = "RED" if caught else ("PARTIAL" if red else "SURVIVED")
        if not caught:
            failures += 1
        print(f"{mid}  {status:9s} expected {expect} · went red {red}")
        print(f"     {why}")
    print(f"\n{'every mutation was caught' if failures == 0 else f'{failures} not caught'}")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
