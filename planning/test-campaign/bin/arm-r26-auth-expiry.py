#!/usr/bin/env python3
"""R26 — watch every load-bearing assertion fail, then restore the tree byte for byte.

A green suite says the assertions ran. It does not say any of them *can* go red, and this
repository has found five unfailable oracles in one merged item. So each arm below plants one
defect the corresponding assertion exists to catch, requires the named tests to FAIL, and restores
the file with its sha256 compared against the value taken before the edit.

Two of the arms are not source mutations at all. `wiring` deletes the one line in
`RouterServiceDispatch` that hands the daemon its monitor — the class of defect that has shipped
twice here with a green unit suite — and requires the SOCKET lane to go red while the unit suite
stays green, which is the only way to show the lane is not decoration. `spawn` makes the fixture's
stdio server warm, so the process-table reading the lane pairs its absence claims against is shown
to be capable of reporting a non-zero count.

A presence control runs first and is required GREEN over a NON-ZERO test count: an arm harness
whose filter selects nothing would otherwise report every arm as caught.

    python3 planning/test-campaign/bin/arm-r26-auth-expiry.py            # every arm
    python3 planning/test-campaign/bin/arm-r26-auth-expiry.py --only vacuity

Exit 0 when every arm bit, 1 when one survived, 2 when the environment could not run the check,
3 when the presence control was not green.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import pathlib
import re
import subprocess
import sys

# NOT `.resolve()`. `.worktrees` is a symlink, so this directory answers to two names, and
# `swift-frontend` resolves a relative `-module-cache-path` against $PWD — a cache filled under
# one spelling and read under the other segfaults with a message naming no symlink. `abspath`
# keeps whichever spelling the caller used, which is the one `make` pins. See
# `scripts/worktree-preflight.sh`.
ROOT = pathlib.Path(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..")))
APP = ROOT / "app"
LANE = ROOT / "scripts" / "acceptance" / "r26-auth-expiry.sh"

SRC = {
    "record": APP / "Sources/RouterCore/AuthExpiry/AuthExpiryRecord.swift",
    "policy": APP / "Sources/RouterCore/AuthExpiry/AuthExpiryPolicy.swift",
    "monitor": APP / "Sources/RouterCore/AuthExpiry/AuthExpiryMonitor.swift",
    "routes": APP / "Sources/RouterCore/Control/ControlAuthExpiry.swift",
    "dispatch": APP / "Sources/RouterCore/Service/RouterServiceDispatch.swift",
}

# name -> (file key, find, replace, expected-red tests, plane)
ARMS = [
    (
        "vacuity",
        "record",
        "        guard let expiresAtMs else { return .unknown }",
        "        guard let expiresAtMs else { return .valid }",
        ["E5", "E17", "E21"],
        "unit",
    ),
    (
        "clamp",
        "policy",
        """            guard value >= floor else {
                refusals.append(AuthExpiryRefusal(
                    scope: "global", key: key, value: value,
                    reason: "below the floor of \\(floor)"
                ))
                return
            }
            field = value""",
        """            field = max(value, floor)""",
        ["E1", "E2", "E22"],
        "unit",
    ),
    (
        "escalation",
        "monitor",
        "        if prior.kind != notice.kind { return true }\n",
        "",
        ["E13"],
        "unit",
    ),
    (
        "recovery",
        "monitor",
        """            guard let notice = AuthExpiryNotice.about(record, verb: verb) else {
                delivered[record.server] = nil
                continue
            }""",
        """            guard let notice = AuthExpiryNotice.about(record, verb: verb) else {
                continue
            }""",
        ["E15"],
        "unit",
    ),
    (
        "reading-consumes",
        "routes",
        "        let report = await expiry.report(manifest: deps.manifest, nowMilliseconds: now)",
        """        _ = await expiry.claim(manifest: deps.manifest, nowMilliseconds: now)
        let report = await expiry.report(manifest: deps.manifest, nowMilliseconds: now)""",
        ["E24"],
        "unit",
    ),
    (
        "moved-expiry",
        "monitor",
        "        if prior.expiresAtMs != notice.expiresAtMs { return true }\n",
        "",
        ["E14"],
        "unit",
    ),
    ("wiring", "dispatch", "            authExpiry: authExpiry,\n", "", [], "lane"),
    ("spawn", None, None, None, [], "lane-fixture"),
]


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(cmd, **kw):
    return subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True, **kw)


def unit(filter_: str = "AuthExpiry"):
    """Run the R26 suites. Returns (passed_count, failed_names)."""
    out = run(["swift", "test", "--package-path", "app", "--filter", filter_])
    text = out.stdout + out.stderr
    passed = len(re.findall(r"Test \"(E\d+)[^\"]*\" passed", text))
    failed = re.findall(r"Test \"(E\d+)[^\"]*\" (?:failed|recorded an issue)", text)
    return passed, sorted(set(failed)), text


def build_cli():
    return run(["make", "build-cli-debug"]).returncode


def lane():
    out = run(["bash", str(LANE)])
    return out.returncode, out.stdout + out.stderr


def presence_control() -> int:
    print("presence control — nothing planted, the suites must be green over a non-zero count")
    passed, failed, _ = unit()
    print(f"  {passed} passed, {len(failed)} failed")
    if passed == 0:
        print("  PRESENCE CONTROL FAILED: the filter selected no tests, so no arm below means anything")
        return 3
    if failed:
        print(f"  PRESENCE CONTROL FAILED: the unmutated tree is already red: {failed}")
        return 3
    return 0


def apply_arm(path: pathlib.Path, find: str, replace: str) -> str:
    text = path.read_text()
    if text.count(find) != 1:
        raise SystemExit(
            f"NOT APPLICABLE: the search text appears {text.count(find)} times in {path.name}. "
            "The source moved and this arm applied nothing — which is how a mutation harness rots."
        )
    path.write_text(text.replace(find, replace))
    return text


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", action="append", default=[])
    args = parser.parse_args()

    if not LANE.exists():
        print(f"environment: no lane at {LANE}")
        return 2

    control = presence_control()
    if control:
        return control

    arms = [a for a in ARMS if not args.only or a[0] in args.only]
    caught, survived = [], []

    for name, key, find, replace, expect, plane in arms:
        print(f"\narm {name} ({plane})")
        path = SRC[key] if key else None
        before = sha(path) if path else None
        original = apply_arm(path, find, replace) if path else None
        try:
            if plane == "unit":
                _, failed, _ = unit()
                missing = [e for e in expect if e not in failed]
                if missing:
                    print(f"  SURVIVED: {missing} stayed green under the planted defect")
                    survived.append(name)
                else:
                    print(f"  RED: {failed}")
                    caught.append(name)
            elif plane == "lane":
                # The unit suite must stay GREEN here. That contrast is the whole claim: a
                # dependency the daemon never supplies is invisible to every test that builds
                # its own.
                _, failed, _ = unit()
                if build_cli() != 0:
                    print("  environment: the CLI would not build under this arm")
                    survived.append(name)
                    continue
                code, text = lane()
                red = code != 0 and "no auth expiry monitor" in text
                if red and not failed:
                    print("  RED: the lane failed with 503s while the unit suite stayed green")
                    caught.append(name)
                else:
                    print(f"  SURVIVED: lane exit {code}, unit failures {failed}")
                    survived.append(name)
            else:  # lane-fixture
                if build_cli() != 0:
                    print("  environment: the CLI would not build")
                    return 2
                text = LANE.read_text()
                find_f = '"r26-local":    { "command": "/usr/bin/python3", "args": ["$HOME_DIR/r26-local.py"] }'
                if text.count(find_f) != 1:
                    print("  NOT APPLICABLE: the fixture line moved")
                    survived.append(name)
                    continue
                lane_before = sha(LANE)
                LANE.write_text(text.replace(
                    find_f,
                    find_f[:-2] + ', "warm": true }'
                ))
                try:
                    code, out = lane()
                    red = "FAIL children running the stdio server's own script" in out \
                        or "FAIL child processes of the daemon" in out
                    if red:
                        print("  RED: the process-table readings reported a non-zero count")
                        caught.append(name)
                    else:
                        print(f"  SURVIVED: lane exit {code} with a warmed stdio upstream")
                        survived.append(name)
                finally:
                    LANE.write_text(text)
                    assert sha(LANE) == lane_before, "the lane was not restored byte-identically"
        finally:
            if path is not None:
                path.write_text(original)
                assert sha(path) == before, f"{path} was not restored byte-identically"

    if build_cli() != 0:
        print("\nwarning: the restored tree would not build — investigate before trusting the above")
        return 2

    print(f"\n{len(caught)} of {len(arms)} arms bit; survived: {survived or 'none'}")
    return 1 if survived else 0


if __name__ == "__main__":
    sys.exit(main())
