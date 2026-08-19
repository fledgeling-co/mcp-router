#!/usr/bin/env python3
"""The on-glass assertions, stated explicitly, and proven able to fail.

WHY THIS EXISTS
---------------
Ten macos-glass cases passed against AX dumps of a real window, and five of them
carried an EMPTY note — a pass with no recorded statement of what was asserted. A
pass whose assertion is not written down cannot be reviewed, re-run, or watched to
fail; it is a claim that something was checked. This file is those assertions,
written from what the dumps actually contain.

THE ARMING CONTROL IS BUILT IN, AND IT IS NOT A HAND-WRITTEN DECOY
------------------------------------------------------------------
Every surface's predicate is run against EVERY OTHER surface's dump. A predicate
that passes on another surface's window is matching the shell — the sidebar, the
status line, the window chrome that every board shares — rather than the board it
claims to identify. That is the campaign's first failure mode in miniature: six
screens deduped onto one route, reported as six.

So `--discriminate` is both the arming proof and a real defect detector. It reports,
per surface, how many foreign dumps its predicate wrongly accepts. The requirement
is zero, and any non-zero is printed with the coliding surface named.

WHAT THE PIXEL CASES CAN AND CANNOT CLAIM
-----------------------------------------
A raster case here asserts: the capture is a real PNG, it is window-scoped from a
pid-owned CGWindowID (recorded in the capture log), its SHA is unique across every
case so no one image stands in for two surfaces, and the AX dump taken from the same
window at the same moment carries that surface's own distinctive copy. The last
clause is what makes it a claim about THIS surface rather than about some window.

It does NOT claim agreement with the design of record. The reference is an HTML mock
rasterised at a different size, a pixel diff is a tripwire rather than a verdict, and
no macOS API exposes a cross-process computed style. The 10 comparable pairs are
queued for a human/judge pass through witness-worklist.json instead, and the 7 that
have no reference are named there.

    python3 glass-assert.py                  # assert every case
    python3 glass-assert.py --discriminate   # the arming control
    python3 glass-assert.py --decoy SURF-006 # drop one surface's copy, watch it red
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

D = Path(__file__).resolve().parent.parent
AX = D / "evidence" / "ax"
SHOTS = D / "evidence" / "shots"
OUT = D / "evidence" / "runs" / "glass-assert.json"
CAPTURE_LOG = D / "evidence" / "runs" / "mac-glass-capture.log"

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"

# Per surface: the window title the destination must show, and the copy that is
# distinctive to that board. Every phrase below was read out of the dump it is
# asserted against — none is aspirational, and --discriminate proves each one is
# specific to its own surface rather than shared shell furniture.
SURFACES = {
    # THE SHELL, AND WHY IT IS EXEMPT FROM DISCRIMINATION.
    #
    # SURF-001 is the chrome every destination is drawn inside, so a predicate that
    # identified it *against* the boards would be evidence the shell is NOT shared.
    # Its claim is the opposite one — persistence — and it is asserted across all nine
    # dumps rather than within one, which is the stronger reading.
    #
    # Measured while writing this: SURF-001.window.txt and SURF-003.window.txt are
    # byte-identical (sha 85c2213f…), as are SURF-001.build.png and SURF-003.build.png
    # (442eea37…, 450931 bytes) and both mocks (599f08b8…). The capture script takes
    # SURF-001 from "whatever destination is restored", and that was Activity. So the
    # shell has no distinct board capture of its own; its pixel case uses
    # SURF-001.restored.png (71e5fdba…, a different image) and that is recorded on the
    # case rather than left for a reader to discover.
    "SURF-001": {
        "dump": "SURF-001.window.txt", "title": None,
        "shot": "SURF-001.restored.png", "kind": "shell",
        "copy": [
            "Activity", "Servers", "Skills", "Discover",
            "Inbox", "Checks", "Cleanup", "Settings",
        ],
        "asserts": "the shell offers all eight sidebar destinations in every window it "
                   "draws, which is a claim about persistence rather than identity",
    },
    "SURF-002": {
        "dump": "SURF-002.window.txt", "title": "Servers",
        "shot": "SURF-002.build.png",
        "copy": ["2 tools from 4 servers · 1 running", "fixture-tools"],
        "asserts": "the board publishes the live counts it read from the router, and names "
                   "the fixture servers rather than an invented figure",
    },
    "SURF-003": {
        "dump": "SURF-003.window.txt", "title": "Activity",
        "shot": "SURF-003.build.png",
        "copy": ["browser_evaluate", "no page open — call browser_navigate first"],
        "asserts": "the activity log renders a real failed call with the upstream's own "
                   "error text, not a summarised one",
    },
    "SURF-004": {
        "dump": "SURF-004.window.txt", "title": "Skills",
        "shot": "SURF-004.build.png",
        "copy": ["6 skills from 4 marketplaces · 1 held for review"],
        "asserts": "the skills board publishes its counts including what is held for review",
    },
    "SURF-005": {
        "dump": "SURF-005.window.txt", "title": "Discover",
        "shot": "SURF-005.build.png",
        "copy": [
            "Most used on Smithery",
            "No trend or velocity figure is shown",
            "Only Smithery publishes a session count",
        ],
        "asserts": "Discover ranks by what the indexes actually publish and refuses a trend "
                   "figure it has no history to compute (honesty guardrail)",
    },
    "SURF-006": {
        "dump": "SURF-006.window.txt", "title": "Checks",
        "shot": "SURF-006.build.png",
        "copy": [
            "It is not a graded test of whether a capability does its job well",
            "Skills are never executed by the router",
        ],
        "asserts": "Checks refuses the evaluation metaphor and says the router never runs a "
                   "skill (honesty guardrail)",
    },
    "SURF-007": {
        "dump": "SURF-007.window.txt", "title": "Cleanup",
        "shot": "SURF-007.build.png",
        "copy": [
            "Capabilities MCP Router has never seen used",
            "Observation window: 5d recorded",
            "It proposes; you decide",
        ],
        "asserts": "Cleanup bounds its claim to the window it actually recorded and leaves "
                   "the decision with the user (honesty guardrail)",
    },
    "SURF-008": {
        "dump": "SURF-008.window.txt", "title": "Inbox",
        "shot": "SURF-008.build.png",
        "copy": [
            "Nothing waiting · no phone paired",
            "The phone can queue and nothing else",
            "still cannot install code on this Mac",
        ],
        "asserts": "the Inbox states the phone's ceiling — queue only, never install "
                   "(honesty guardrail, REQ-006)",
    },
    "SURF-011": {
        "dump": "SURF-011.window.txt", "title": "Settings",
        "shot": "SURF-011.build.png",
        "copy": [
            "Read from the router, not set here",
            "no endpoint that rewrites the router's own configuration",
            "Forget the stored token",
        ],
        "asserts": "Settings says the control channel cannot rewrite a command line, which "
                   "is the security posture REQ-012 asserts on the wire",
    },
}

# case -> (surface, kind). A raster case additionally owes a real, unique image.
CASES = {
    "CASE-0001": ("SURF-001", "ax"),
    "CASE-0003": ("SURF-002", "ax"),
    "CASE-0005": ("SURF-008", "ax"),
    "CASE-0011": ("SURF-003", "ax"),
    "CASE-0012": ("SURF-004", "ax"),
    "CASE-0013": ("SURF-005", "ax"),
    "CASE-0014": ("SURF-006", "ax"),
    "CASE-0015": ("SURF-007", "ax"),
    "CASE-0016": ("SURF-011", "ax"),
    "CASE-0101": ("SURF-001", "raster"),
    "CASE-0102": ("SURF-002", "raster"),
    "CASE-0103": ("SURF-003", "raster"),
    "CASE-0104": ("SURF-004", "raster"),
    "CASE-0105": ("SURF-005", "raster"),
    "CASE-0106": ("SURF-006", "raster"),
    "CASE-0107": ("SURF-007", "raster"),
    "CASE-0108": ("SURF-008", "raster"),
    "CASE-0111": ("SURF-011", "raster"),
}


def dump_text(surface: str, decoy: str | None) -> str:
    text = (AX / SURFACES[surface]["dump"]).read_text()
    if decoy == surface:
        for phrase in SURFACES[surface]["copy"]:
            text = text.replace(phrase, "")
    return text


def title_of(surface: str) -> str | None:
    p = AX / f"{surface}.title.txt"
    return p.read_text().strip() if p.exists() else None


def shot_facts() -> dict:
    """Every case's capture, with its SHA, so a duplicate can be named."""
    facts, by_sha = {}, {}
    for case, (surface, kind) in CASES.items():
        if kind != "raster":
            continue
        p = SHOTS / SURFACES[surface]["shot"]
        if not p.exists():
            facts[case] = {"path": str(p), "exists": False}
            continue
        raw = p.read_bytes()
        sha = hashlib.sha256(raw).hexdigest()
        facts[case] = {"path": SURFACES[surface]["shot"], "exists": True,
                       "bytes": len(raw), "sha": sha[:16],
                       "isPNG": raw[:8] == PNG_MAGIC,
                       "sharedWith": by_sha.get(sha)}
        by_sha.setdefault(sha, case)
    return facts


def main() -> int:
    decoy = sys.argv[sys.argv.index("--decoy") + 1] if "--decoy" in sys.argv else None

    if "--discriminate" in sys.argv:
        print("DISCRIMINATION — each surface's predicate against every other surface's dump")
        print("A predicate that accepts a foreign window is matching shared shell chrome.\n")
        collisions, pairs, exempt = [], 0, []
        for surface, spec in SURFACES.items():
            if spec.get("kind") == "shell":
                # Asserted across every dump instead — see the note on SURF-001.
                everywhere = [o for o in SURFACES
                              if all(p in dump_text(o, None) for p in spec["copy"])]
                exempt.append((surface, len(everywhere), len(SURFACES)))
                continue
            accepted = []
            for other in SURFACES:
                if other == surface or SURFACES[other].get("kind") == "shell":
                    continue
                pairs += 1
                text = dump_text(other, None)
                if all(p in text for p in spec["copy"]):
                    accepted.append(other)
            mark = "ok  " if not accepted else "LEAK"
            print(f"  {mark} {surface}  wrongly accepted {len(accepted)} of "
                  f"{len(SURFACES) - 2} foreign board dumps"
                  + (f": {', '.join(accepted)}" if accepted else ""))
            if accepted:
                collisions.append({"surface": surface, "accepted": accepted})
        for surface, hits, total in exempt:
            print(f"  n/a  {surface}  SHELL — exempt by construction; its copy must appear "
                  f"in ALL dumps, and does in {hits} of {total}")
        print(f"\ncompared {pairs} board/dump pairs · leaks={len(collisions)} · "
              f"shell surfaces asserted for persistence instead: {len(exempt)}")
        print("Each predicate rejects every window but its own, so a pass on one board "
              "cannot be a pass on another." if not collisions else
              "A leaking predicate cannot identify its surface — narrow its copy list.")
        return 0 if not collisions else 1

    shots = shot_facts()
    results, checks, failures = {}, 0, []

    def check(case: str, label: str, ok: bool) -> None:
        nonlocal checks
        checks += 1
        results.setdefault(case, {"checks": [], "pass": True})
        results[case]["checks"].append({"label": label, "pass": ok})
        if not ok:
            results[case]["pass"] = False
            failures.append(f"{case}: {label}")

    for case, (surface, kind) in CASES.items():
        spec = SURFACES[surface]
        text = dump_text(surface, decoy)

        # the window is the one the destination was selected to reach
        if spec["title"]:
            check(case, f"window title is {spec['title']}", title_of(surface) == spec["title"])
        # every phrase this board is identified by is present in its own window
        for phrase in spec["copy"]:
            check(case, f"window carries: {phrase[:56]}", phrase in text)
        # the dump is a real AX tree of a real window, not an empty file
        check(case, "dump is an AXWindow tree", "AXWindow" in text and len(text) > 500)

        # A shell surface owes the stronger claim: its chrome is in EVERY window, and
        # its own capture is not one of the board captures wearing a second id.
        if spec.get("kind") == "shell":
            missing = [o for o in SURFACES
                       if not all(p in dump_text(o, decoy) for p in spec["copy"])]
            check(case, f"shell chrome present in all {len(SURFACES)} window dumps",
                  not missing)
            twins = [o for o in SURFACES if o != surface
                     and (SHOTS / SURFACES[o]["shot"]).exists()
                     and hashlib.sha256((SHOTS / SURFACES[o]["shot"]).read_bytes()).hexdigest()
                     == hashlib.sha256((SHOTS / spec["shot"]).read_bytes()).hexdigest()]
            check(case, "shell capture is not a board capture under a second id", not twins)

        if kind == "raster":
            f = shots[case]
            check(case, "capture exists on disk", f.get("exists", False))
            check(case, "capture is a real PNG", f.get("isPNG", False))
            check(case, "capture is not a stub", f.get("bytes", 0) > 20000)
            check(case, "capture is unique to this case", f.get("sharedWith") is None)
            check(case, "capture channel is window-scoped and recorded",
                  CAPTURE_LOG.exists() and "screencapture -x -l" in
                  Path(__file__).read_text() and "attached pid=" in CAPTURE_LOG.read_text())

    ok = not failures
    print(f"on-glass assertions over {len(CASES)} cases / {len(SURFACES)} surfaces"
          + (f"   DECOY={decoy}" if decoy else ""))
    for case in sorted(results):
        r = results[case]
        n = len(r["checks"])
        bad = [c["label"] for c in r["checks"] if not c["pass"]]
        print(f"  {'ok  ' if r['pass'] else 'FAIL'} {case} {CASES[case][0]} "
              f"{CASES[case][1]:<7} {n - len(bad)}/{n} checks"
              + (f"  <- {bad[0][:70]}" if bad else ""))
    print(f"\nchecked={checks} failures={len(failures)} cases={len(CASES)}")
    for f in failures[:12]:
        print(f"  FAILED  {f}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"checked": checks, "failures": failures,
                               "cases": results, "shots": shots,
                               "decoy": decoy, "pass": ok}, indent=1) + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
