#!/usr/bin/env python3
"""The one end-to-end arm: revert the product, rebuild it, re-photograph it, watch red.

WHY ONE, AND WHY IT IS NOT THE SAME AS THE OTHER EIGHTEEN
--------------------------------------------------------
The glass suite's 18 cases are armed against RECORDINGS: feed a mutated AX dump to the
predicate and it goes red, which proves the predicate bites. It does not prove the
chain that produced the recording bites. A predicate can be perfect while the capture
step photographs the wrong window, or a stale one, or the same window twice under two
surface ids — the campaign found that last one already, between SURF-001 and SURF-003.

So this reverts a real honesty guardrail in the Mac app's own source, rebuilds the app
with xcodebuild, relaunches it backgrounded, re-photographs it through the same
window-scoped path the campaign uses, and asserts the suite goes red on evidence
produced by the mutated BUILD. Then it restores everything and proves green again.

WHAT IT TOUCHES, AND HOW IT PUTS IT BACK
----------------------------------------
The capture script overwrites every Mac AX dump and PNG. The campaign's own cases cite
specific SHAs, so this backs up `evidence/ax` and `evidence/shots` before it runs and
restores them afterwards — the recorded evidence stays byte-identical to what the notes
describe, and the arming run's own artifacts are kept separately under
`evidence/arm-pipeline/` so the red is inspectable rather than merely asserted.

    python3 arm-pipeline.py
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "planning" / "test-campaign"
BIN = D / "bin"
SRC = ROOT / "app" / "Sources" / "MCPRouterKit" / "Checks" / "CheckCopy.swift"
KEEP = D / "evidence" / "arm-pipeline"
OUT = D / "evidence" / "runs" / "arm-pipeline.json"

# Both halves of the Checks pane's honesty guardrail, reverted together. The anchor is
# the whole three-line literal, because each asserted sentence spans a `+` concatenation
# in the source and a per-line anchor would be matching half a claim.
MUTATIONS = [
    (
        '        "A check is something MCP Router performed and can show you the input to. '
        'It is not a graded "\n'
        '            + "test of whether a capability does its job well. Skills are never '
        'executed by the "\n'
        '            + "router, so nothing here reports how one behaved when an agent used it."',

        '        "A check is something MCP Router performed and can show you the input to. '
        'It grades how "\n'
        '            + "well a capability does its job. Skills are executed by the "\n'
        '            + "router, so this reports how one behaved when an agent used it."',
    ),
]

# The two cases whose predicate reads that copy off the rebuilt window.
EXPECT_RED = {"CASE-0014", "CASE-0106"}


def sh(cmd: list[str], cwd: Path, label: str) -> tuple[int, str]:
    print(f"    $ {' '.join(cmd[:4])}{' …' if len(cmd) > 4 else ''}")
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=3600)
    if p.returncode != 0:
        print(f"      {label} exit={p.returncode}")
    return p.returncode, p.stdout + p.stderr


def glass() -> tuple[int, set[str], str]:
    p = subprocess.run([sys.executable, str(BIN / "glass-assert.py")],
                       cwd=ROOT, capture_output=True, text=True)
    out = p.stdout + p.stderr
    red = {l.split()[1] for l in out.splitlines() if l.startswith("  FAIL ")}
    tally = next((l for l in out.splitlines() if l.startswith("checked=")), "")
    return p.returncode, red, tally


def main() -> int:
    ax, shots = D / "evidence" / "ax", D / "evidence" / "shots"
    bak = D / "evidence" / "_pipeline-backup"
    if bak.exists():
        shutil.rmtree(bak)
    bak.mkdir(parents=True)
    shutil.copytree(ax, bak / "ax")
    shutil.copytree(shots, bak / "shots")
    print(f"backed up {len(list(ax.iterdir()))} AX dumps and "
          f"{len(list(shots.rglob('*.png')))} images to {bak.relative_to(D)}")

    original = SRC.read_text()
    record: dict = {"source": str(SRC.relative_to(ROOT)), "expectRed": sorted(EXPECT_RED)}
    try:
        text = original
        for old, new in MUTATIONS:
            if text.count(old) != 1:
                print(f"REFUSED — anchor appears {text.count(old)} times, need 1:\n{old[:80]}")
                return 1
            text = text.replace(old, new, 1)
        SRC.write_text(text)
        print("\nreverted both halves of the Checks honesty guardrail in CheckCopy.swift")

        rc, out = sh(["make", "build-mac"], ROOT, "build")
        if rc != 0:
            record["buildFailed"] = out[-1500:]
            print("REFUSED — the mutated app did not build, so a red would be a compile "
                  "error rather than a caught defect.")
            return 1
        print("    built")

        rc, out = sh(["bash", str(BIN / "capture-mac-glass.sh")], ROOT, "capture")
        focus_held = "focus unchanged" in out
        record["mutatedCapture"] = {"exit": rc, "focusHeld": focus_held,
                                     "tail": out[-700:]}
        print(f"    recaptured (focus unchanged: {focus_held})")

        grc, red, tally = glass()
        record["mutated"] = {"exit": grc, "red": sorted(red), "tally": tally}
        print(f"\n  MUTATED BUILD: {tally}  red={sorted(red)}")

        if KEEP.exists():
            shutil.rmtree(KEEP)
        KEEP.mkdir(parents=True)
        for name in ("SURF-006.window.txt", "SURF-006.title.txt"):
            if (ax / name).exists():
                shutil.copy(ax / name, KEEP / f"mutated.{name}")
        if (shots / "SURF-006.build.png").exists():
            shutil.copy(shots / "SURF-006.build.png", KEEP / "mutated.SURF-006.build.png")

        got = red & EXPECT_RED
        ok = grc != 0 and got == EXPECT_RED
    finally:
        SRC.write_text(original)
        shutil.rmtree(ax)
        shutil.rmtree(shots)
        shutil.copytree(bak / "ax", ax)
        shutil.copytree(bak / "shots", shots)
        shutil.rmtree(bak)
        print("\nrestored source and every recorded artifact")
        rc, out = sh(["make", "build-mac"], ROOT, "rebuild")
        print(f"    rebuilt clean (exit {rc})")

    grc2, red2, tally2 = glass()
    record["restored"] = {"exit": grc2, "red": sorted(red2), "tally": tally2}
    print(f"  RESTORED:      {tally2}  red={sorted(red2) or 'none'}")

    verdict = ok and grc2 == 0
    record["armed"] = verdict
    OUT.write_text(json.dumps(record, indent=1) + "\n")
    tail = ("goes red on a mutated build and green again on the real one" if verdict
            else "did not behave as an armed pipeline must")
    print(f"\n{'ARMED' if verdict else 'REFUSED'} — the pipeline {tail}.")
    print(f"kept the mutated build's own artifacts under {KEEP.relative_to(D)}")
    print(f"wrote {OUT.relative_to(D)}")
    return 0 if verdict else 1


if __name__ == "__main__":
    raise SystemExit(main())
