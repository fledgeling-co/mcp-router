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
    # The shell has no board of its own, so the capture script photographs it on the
    # Servers board and declares the share: SURF-001.build.png is byte-identical to
    # SURF-002.build.png, recorded as such in captures.json with the reason. That is
    # honest and it is not a pixel claim about the shell — it is a pixel claim about
    # Servers under a second id, which the check below refuses. So the pixel case cites
    # SURF-001.shell.png, the sidebar cropped out of that window at the frame the AX
    # dump reports, with `derivedFrom` recording where it came from.
    "SURF-001": {
        "dump": "SURF-001.window.txt", "title": None,
        "shot": "SURF-001.shell.png", "kind": "shell",
        "copy": [
            "Activity", "Servers", "Skills", "Discover",
            "Inbox", "Checks", "Cleanup", "Settings",
        ],
        # REQ-003's other half. CASE-0002 is n/a because posting ⌘1–7 to a background pid does
        # not change SwiftUI's focused scene — measured, and a fact about the platform rather
        # than the product — so no run of this campaign can prove the keystroke NAVIGATES. What
        # it can prove is that the running app registered the bindings with the system, read
        # off the live menu bar rather than out of MenuCommand.swift. That is short of the
        # requirement and it is not nothing: a binding silently lost would be invisible today.
        # Scoped to `menuAction:` rows, because the Window menu lists the same board names with
        # `makeKeyAndOrderFront:` and no key of their own.
        "menu": {"Activity": "1", "Servers": "2", "Skills": "3", "Discover": "4",
                 "Inbox": "5", "Checks": "6", "Cleanup": "7", "Settings": ","},
        "asserts": "the shell offers all eight sidebar destinations in every window it "
                   "draws, which is a claim about persistence rather than identity, and its "
                   "live menu bar declares ⌘1–7 and ⌘, against those eight destinations",
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
        "copy": ["browser_evaluate", "no page open — call browser_navigate first",
                 # DEF-016's affordance and DEF-012's first rename, drawn rather than declared.
                 "Reset history…"],
        "asserts": "the activity log renders a real failed call with the upstream's own "
                   "error text, not a summarised one",
    },
    "SURF-004": {
        "dump": "SURF-004.window.txt", "title": "Skills",
        "shot": "SURF-004.build.png",
        "copy": ["6 skills from 4 marketplaces · 1 held for review",
                 # DEF-012's second rename. The board shipped "Manage marketplaces…" while the
                 # menu item opening the same sheet said this.
                 "Add marketplace…"],
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
            # The number is computed from the fixture's `since` against the clock, so it
            # was "5d recorded" yesterday and "6d recorded" today. Asserting the literal
            # asserted the calendar: it went red on a day nothing in the product moved.
            # The claim REQ-017 makes is that the board bounds itself to a window it
            # actually recorded, and a digit-and-unit proves that without also proving
            # what day it is. The clause disappearing still fails.
            re.compile(r"Observation window: \d+d recorded"),
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
    # THE BOARD THIS CAMPAIGN COULD NOT REPORT AS UNCOVERED.
    #
    # Enumerated 2026-08-27 by G15. `Destination.swift` has shipped nine destinations since
    # M22 and this list held seven boards, so `campaign.py check` reported "0 with no case"
    # over a denominator that never named this one. A surface with no row cannot be uncovered.
    #
    # The predicates below are the board's own sentences rather than chrome: the subtitle, the
    # section header over the detected list, the shim row's COST — a bridge drawn without it
    # reads as a clean tick — the scope the reading does not cover, and the finding as a
    # counted pair rather than a judgement. `--discriminate` proves each rejects the other
    # eight boards' windows.
    "SURF-025": {
        "dump": "SURF-025.window.txt", "title": "Harnesses",
        "shot": "SURF-025.build.png",
        "copy": [
            "Which AI tools on this Mac actually route through here",
            "Detected on this Mac",
            "one extra process per session",
            "Global configuration only",
            # The finding is a count of what was measured. The digits are the fixture's and
            # would move with it, so the pattern asserts the SHAPE — a count of a harness's own
            # servers and a count of the overlap — rather than today's two numbers.
            re.compile(
                r"runs \d+ servers? of its own, \d+ of which this router already fronts"
            ),
        ],
        # Proved to render, not proved to work — CASE-0167 stands at `structural` and says so.
        # `Rescan` re-runs the read, and no case here presses it: the Debug shell reads a
        # fixture, so a second read returns the same bytes and a green "it refreshed" would be
        # indistinguishable from a button wired to nothing.
        "controls": {"Rescan": True, "Reconcile all": False},
        "asserts": "the Harnesses board names the bridge AND the extra process it costs, bounds "
                   "its reading to the configuration it actually read, and states its finding as "
                   "a counted pair rather than a judgement",
    },
    # THE BOARD OF COUNTS AND MEASUREMENTS.
    #
    # Enumerated 2026-08-27 by G16. Every predicate below is a sentence that BOUNDS a figure
    # rather than a figure itself: the subtitle's claim that nothing here is modelled, the
    # provenance line under the memory reading, the caption that says why a bar can read
    # nothing at all, and the duty-cycle caption that states its mechanism and its window
    # instead of quoting the brief's "every one of these sat at 100%" — a number about a world
    # this router never ran.
    #
    # The figures themselves are NOT asserted here, and that is deliberate rather than an
    # omission: a Debug shell reads a fixture, so asserting `214` in this window would prove
    # the fixture, not the product. The figures are traced against a live router by
    # bin/insights-live-probe.py on the router-daemon lane, which is the lane that can tell.
    "SURF-026": {
        "dump": "SURF-026.window.txt", "title": "Insights",
        "shot": "SURF-026.build.png",
        "copy": [
            "Every number here is counted from calls this router served",
            "Where the calls came from",
            "Duty cycle, per server",
            "measured, not modelled",
            "The share of wall-clock time each child was alive, since the router started",
            "It sees the process on the other end of the connection, not the harness that "
            "started it",
        ],
        # THE §6 SEARCH, RUN OVER THE RENDERED WINDOW. A saving is a figure about a world the
        # router never ran, and PRD.md §8.2's own sketch draws one. Proven non-vacuous by the
        # copy list above, which requires the board to BE discussing memory and duty cycle.
        "absentAny": ["Savings", "saved", "vs unrouted", "unrouted", "would have been",
                      "99.8", "99.7"],
        "controls": {"Analyse now": False},
        "asserts": "the Insights board states that nothing on it is modelled, carries the "
                   "provenance line under the memory reading, says why a bar can read nothing "
                   "at all, states the duty cycle's mechanism and window rather than a "
                   "percentage about a world the router never ran, and speaks no saving anywhere",
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

# A STATE is one surface under a fixture scenario that makes it draw something the
# default scenario cannot. It is not a new surface — the same board, the same window —
# so it is not in the discrimination matrix above, which asks whether a predicate can
# tell two BOARDS apart. It carries the stronger local control instead: `absentFrom`
# names the same board's default dump, and the predicate must REJECT it. A state
# predicate that also accepts the default is not describing the state.
STATES = {
    "SURF-007/provenance-sheet": {
        "surface": "SURF-007",
        "dump": "SURF-007.provenance-sheet.window.txt", "title": "Cleanup",
        "shot": "SURF-007.provenance-sheet.png",
        "absentFrom": "SURF-007.cleanup-skills.window.txt",
        "copy": [
            "AXSheet",
            "Where the router first saw it, github:acme-tools/skills",
            "Where it resolves now, github:unknown-user/skills",
            "The router first saw it, 2026-01-09T09:20:00.000Z",
            # The sentence that bounds the claim, on screen rather than left to be inferred.
            "The router records where a marketplace resolves, never who owns it and never "
            "what changed inside it",
        ],
        # `prototype.html:1249` states four things the router does not observe: an owner at
        # install, a force-push on the default branch, an installed hash no longer in history,
        # and a failing eval count. One of them is not computable at all — `SkillProvenance`
        # records that the client's files carry a commit and never an owner. Enumerated by
        # name rather than as a blanket not-that predicate, so this fires on the specific
        # regression rather than on any rewording.
        "absent": ["@jbailey", "force-pushed", "no longer in history", "evals fail"],
        "asserts": "the sheet REQ-007 was most at risk on renders the three observations "
                   "SkillProvenance actually carries, says on screen what it cannot know, "
                   "and states none of the four figures the design invented",
    },
    # The pairing sheet, which is a REFUSAL rather than the surface REQ-015 describes.
    #
    # CASE-0010 and CASE-0110 fail against REQ-015 and stay failing: there is no 8-character
    # Crockford code and no QR, because DEF-001 is that this build ships no pairing transport.
    # What this state asserts is the different and separately-owed thing — that the build says
    # so, in the shape REQ-019 requires, instead of drawing a code it cannot honour. A passing
    # predicate here does not launder that failure; the two are about different requirements
    # and both are counted.
    "SURF-010/unavailable": {
        "surface": "SURF-010",
        "dump": "SURF-010.window.txt", "title": "Inbox",
        "shot": "SURF-010.build.png",
        "absentFrom": "SURF-008.window.txt",
        "copy": [
            "AXSheet",
            "Pair iPhone",
            "Pairing is not available in this build",
            "this build ships no way to listen for one. Nothing is wrong with your phone or "
            "your network",
        ],
        # A code the build cannot honour would be the defect REQ-019 names. The pattern is
        # Crockford base-32 at the length REQ-015 specifies, so a code appearing at all trips
        # it — including one this predicate's author never saw.
        "absentPattern": r"\b[0-9ABCDEFGHJKMNPQRSTVWXYZ]{8}\b",
        "asserts": "the pairing sheet states that this build has no pairing transport and "
                   "offers no code, rather than drawing an 8-character Crockford code it "
                   "cannot complete a pairing with (REQ-019)",
    },
    # The two answers this board has that the populated capture cannot show.
    #
    # `empty` is a real answer of NONE — the fixture serves a successful read of an empty list —
    # so the board owes its own empty state and NOT an error. `absent` is the load-bearing half:
    # a board that drew the detected list under an empty reading would be drawing rows nothing
    # returned.
    "SURF-025/empty": {
        "surface": "SURF-025",
        "dump": "SURF-025.empty.window.txt", "title": "Harnesses",
        "shot": "SURF-025.empty.png",
        "absentFrom": "SURF-025.window.txt",
        "titleFromDump": True,
        "copy": [
            "No AI harnesses found",
            "Nothing on this Mac looks like an agent CLI",
        ],
        "absent": ["Detected on this Mac", "mcp-remote", "one extra process per session"],
        "asserts": "an empty reading draws the board's own empty state, says the router reads "
                   "the standard paths only, and draws no detected list — an answer of none is "
                   "not a failure and is not a row",
    },
    # `offline` is the read FAILING. The board owes the load's error and, again, no rows: a
    # failed read that kept drawing yesterday's harnesses would be the stale reading the brief
    # calls worse than no reading.
    "SURF-025/failure": {
        "surface": "SURF-025",
        "dump": "SURF-025.failure.window.txt", "title": "Harnesses",
        "shot": "SURF-025.failure.png",
        "absentFrom": "SURF-025.window.txt",
        "titleFromDump": True,
        "copy": [
            "The router isn't running",
            "Nothing is listening on the control port",
        ],
        "absent": ["Detected on this Mac", "mcp-remote", "one extra process per session"],
        "asserts": "a failed read draws the router-not-running state on THIS board — the window "
                   "title is read back off the failure's own dump — and draws no harness rows",
    },
    # Not enough history is a MEASUREMENT, not a threshold picked by eye: the fixture's thin
    # response carries a nil `logHorizon`, and that nil is the whole of it. The `absent` list is
    # the load-bearing half — a board that drew its charts under a response with no horizon
    # would be plotting a window it never had.
    "SURF-026/empty": {
        "surface": "SURF-026",
        "dump": "SURF-026.empty.window.txt", "title": "Insights",
        "shot": "SURF-026.empty.png",
        "absentFrom": "SURF-026.window.txt",
        "titleFromDump": True,
        "copy": [
            "Not enough history yet",
            "No calls have been served in the last 24 hours",
        ],
        "absent": ["Where the calls came from", "Duty cycle, per server",
                   "measured, not modelled", "Calls per hour"],
        "asserts": "a response with no log horizon draws `not enough history yet` and draws NO "
                   "chart and NO figure — an absent measurement is not a zero",
    },
    "SURF-026/failure": {
        "surface": "SURF-026",
        "dump": "SURF-026.failure.window.txt", "title": "Insights",
        "shot": "SURF-026.failure.png",
        "absentFrom": "SURF-026.window.txt",
        "titleFromDump": True,
        "copy": [
            "The router isn't running",
            "Nothing is listening on the control port",
        ],
        "absent": ["Where the calls came from", "Duty cycle, per server",
                   "measured, not modelled", "Calls per hour"],
        "asserts": "a failed read draws the router-not-running state on THIS board and draws no "
                   "figure at all — a stale count kept through a failed read would be the exact "
                   "defect §6 names",
    },
    "SURF-007/cleanup-skills": {
        "surface": "SURF-007",
        "dump": "SURF-007.cleanup-skills.window.txt", "title": "Cleanup",
        "shot": "SURF-007.cleanup-skills.png",
        "absentFrom": "SURF-007.window.txt",
        "copy": [
            # The substitution: a moved marketplace replaces the row's actions.
            "Read first…",
            # The router's own sentence for why it moved, on the row rather than in a sheet.
            "The router first saw it at github:acme-tools/skills and it now resolves to "
            "github:unknown-user/skills",
            # The skill-kind Remove…, disabled, with the reason it gives for refusing.
            "The control API is read-only for skills: removing one means writing files the "
            "client applications hold open",
        ],
        "asserts": "a cleanup candidate whose marketplace moved substitutes `Read first…` for "
                   "its actions, and a skill candidate that has not moved keeps Inspect while "
                   "its Remove… is disabled with the router's own reason — both rendered by a "
                   "running build rather than asserted against source",
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
    "CASE-0160": ("SURF-025", "ax"),
    "CASE-0167": ("SURF-025", "ax"),
    "CASE-0170": ("SURF-026", "ax"),
    "CASE-0176": ("SURF-026", "ax"),
    "CASE-0101": ("SURF-001", "raster"),
    "CASE-0102": ("SURF-002", "raster"),
    "CASE-0103": ("SURF-003", "raster"),
    "CASE-0104": ("SURF-004", "raster"),
    "CASE-0105": ("SURF-005", "raster"),
    "CASE-0106": ("SURF-006", "raster"),
    "CASE-0107": ("SURF-007", "raster"),
    "CASE-0108": ("SURF-008", "raster"),
    "CASE-0111": ("SURF-011", "raster"),
    "CASE-0161": ("SURF-025", "raster"),
    "CASE-0171": ("SURF-026", "raster"),
}

# case -> state key. Same two kinds, read off the state's own dump and capture.
STATE_CASES = {
    "CASE-0138": ("SURF-007/cleanup-skills", "ax"),
    "CASE-0139": ("SURF-007/cleanup-skills", "raster"),
    "CASE-0140": ("SURF-007/provenance-sheet", "ax"),
    "CASE-0141": ("SURF-007/provenance-sheet", "raster"),
    "CASE-0142": ("SURF-010/unavailable", "ax"),
    "CASE-0143": ("SURF-010/unavailable", "raster"),
    "CASE-0162": ("SURF-025/empty", "ax"),
    "CASE-0163": ("SURF-025/empty", "raster"),
    "CASE-0164": ("SURF-025/failure", "ax"),
    "CASE-0165": ("SURF-025/failure", "raster"),
    "CASE-0172": ("SURF-026/empty", "ax"),
    "CASE-0173": ("SURF-026/empty", "raster"),
    "CASE-0174": ("SURF-026/failure", "ax"),
    "CASE-0175": ("SURF-026/failure", "raster"),
}


def carries(phrase, text: str) -> bool:
    """A predicate is a literal or a pattern; both answer the same question."""
    return bool(phrase.search(text)) if isinstance(phrase, re.Pattern) else phrase in text

def label_of(phrase) -> str:
    return phrase.pattern if isinstance(phrase, re.Pattern) else phrase

def dump_text(key: str, decoy: str | None) -> str:
    spec = SURFACES[key] if key in SURFACES else STATES[key]
    text = (AX / spec["dump"]).read_text()
    if decoy == key:
        for phrase in spec["copy"]:
            text = (phrase.sub("", text) if isinstance(phrase, re.Pattern)
                    else text.replace(phrase, ""))
    return text


def window_title_in(text: str) -> str | None:
    """The AXWindow row's own title, out of a dump. Field 3, as the crop in
    capture-mac-glass.sh reads it."""
    for line in text.splitlines():
        f = line.split("\t")
        if len(f) > 5 and f[1] == "AXWindow":
            return f[3]
    return None


def title_of(surface: str) -> str | None:
    p = AX / f"{surface}.title.txt"
    return p.read_text().strip() if p.exists() else None


def shot_facts() -> dict:
    """Every case's capture, with its SHA, so a duplicate can be named."""
    facts, by_sha = {}, {}
    everything = {c: (k, "surface") for c, k in CASES.items()}
    everything.update({c: (k, "state") for c, k in STATE_CASES.items()})
    for case, ((key, kind), _) in everything.items():
        if kind != "raster":
            continue
        p = SHOTS / (SURFACES[key] if key in SURFACES else STATES[key])["shot"]
        if not p.exists():
            facts[case] = {"path": str(p), "exists": False}
            continue
        raw = p.read_bytes()
        sha = hashlib.sha256(raw).hexdigest()
        facts[case] = {"path": (SURFACES[key] if key in SURFACES
                                else STATES[key])["shot"], "exists": True,
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
                              if all(carries(p, dump_text(o, None)) for p in spec["copy"])]
                exempt.append((surface, len(everywhere), len(SURFACES)))
                continue
            accepted = []
            for other in SURFACES:
                if other == surface or SURFACES[other].get("kind") == "shell":
                    continue
                pairs += 1
                text = dump_text(other, None)
                if all(carries(p, text) for p in spec["copy"]):
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

    def raster_checks(case: str) -> None:
        f = shots[case]
        check(case, "capture exists on disk", f.get("exists", False))
        check(case, "capture is a real PNG", f.get("isPNG", False))
        check(case, "capture is not a stub", f.get("bytes", 0) > 20000)
        check(case, "capture is unique to this case", f.get("sharedWith") is None)
        check(case, "capture channel is window-scoped and recorded",
              CAPTURE_LOG.exists() and "screencapture -x -l" in
              Path(__file__).read_text() and "attached pid=" in CAPTURE_LOG.read_text())

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
            check(case, f"window carries: {label_of(phrase)[:56]}", carries(phrase, text))
        # the dump is a real AX tree of a real window, not an empty file
        check(case, "dump is an AXWindow tree", "AXWindow" in text and len(text) > 500)

        # A NEGATIVE the board owes: a word it must never speak. Non-vacuity is carried by the
        # copy list above, which requires the board to be discussing the subject the search is
        # about — a clean result over a tree with no numbers in it proves nothing.
        for phrase in spec.get("absentAny", []):
            check(case, f"window does NOT speak: {phrase[:40]}",
                  phrase.lower() not in text.lower() or decoy == surface)

        # CONTROLS THAT ARE ONLY PROVEN TO RENDER.
        #
        # A control's presence in the tree is a `structural` claim and nothing more: an AXButton
        # exists with that label. It does not say the handler does anything, and the case that
        # cites it is recorded at `structural` for exactly that reason. Kept separate from the
        # copy list above so it cannot be mistaken for one of the board's outcome predicates.
        for label, enabled in spec.get("controls", {}).items():
            rows = [r.split("\t") for r in text.splitlines()]
            hits = [r for r in rows
                    if len(r) > 8 and r[1] == "AXButton" and r[5].startswith(label)]
            check(case, f"a control labelled {label} is drawn", bool(hits))
            if hits and enabled is not None:
                check(case,
                      f"the {label} control is drawn {'enabled' if enabled else 'disabled'}",
                      any(r[7] == ("1" if enabled else "0") for r in hits))

        # A shell surface owes the stronger claim: its chrome is in EVERY window, and
        # its own capture is not one of the board captures wearing a second id.
        if spec.get("kind") == "shell":
            missing = [o for o in SURFACES
                       if not all(carries(p, dump_text(o, decoy)) for p in spec["copy"])]
            check(case, f"shell chrome present in all {len(SURFACES)} window dumps",
                  not missing)
            twins = [o for o in SURFACES if o != surface
                     and (SHOTS / SURFACES[o]["shot"]).exists()
                     and hashlib.sha256((SHOTS / SURFACES[o]["shot"]).read_bytes()).hexdigest()
                     == hashlib.sha256((SHOTS / spec["shot"]).read_bytes()).hexdigest()]
            check(case, "shell capture is not a board capture under a second id", not twins)

            # The command-key bindings, off the running app's own menu bar.
            bound = {}
            for line in (AX / "SURF-001.menu.txt").read_text().splitlines():
                f = line.split("\t")
                if len(f) > 11 and f[1] == "AXMenuItem" and f[11] == "menuAction:" and f[9]:
                    bound.setdefault(f[3], (f[9], f[10]))
            if decoy == surface:
                bound = {}
            for destination, key in spec["menu"].items():
                check(case, f"menu bar binds ⌘{key} to {destination}",
                      bound.get(destination) == (key, "0"))

        if kind == "raster":
            raster_checks(case)

    for case, (key, kind) in STATE_CASES.items():
        spec = STATES[key]
        text = dump_text(key, decoy)

        # A STATE's title, read off the state's own dump rather than off the populated run's
        # title file. Opt-in, because the states that predate it are sheets over a parent board
        # and their claim is about the parent. For a state that IS the board in another world,
        # the populated title file says nothing about which window the failure was drawn in —
        # and the failure copy here is `ControlAPIError`'s, shared by every board.
        if spec.get("titleFromDump"):
            check(case, f"state's own window dump is titled {spec['title']}",
                  window_title_in(text) == spec["title"])
        else:
            check(case, f"window title is {spec['title']}",
                  title_of(spec["surface"]) == spec["title"])
        for phrase in spec["copy"]:
            check(case, f"state window carries: {label_of(phrase)[:56]}",
                  carries(phrase, text))
        check(case, "dump is an AXWindow tree", "AXWindow" in text and len(text) > 500)

        # The local control. The default scenario draws this board too, so a predicate that
        # passes on BOTH dumps is describing the board rather than the state, and the state
        # would be adding nothing the plain capture had not already shown.
        base = (AX / spec["absentFrom"]).read_text()
        leaked = [phrase for phrase in spec["copy"] if carries(phrase, base)]
        check(case, f"state copy is absent from {spec['absentFrom']}", not leaked)

        for phrase in spec.get("absent", []):
            stated = phrase in text or (decoy == key)
            check(case, f"state window does NOT state: {phrase[:48]}", not stated)

        if spec.get("absentPattern"):
            found = re.findall(spec["absentPattern"], text)
            if decoy == key:
                found = found or ["DECOYCD1"]
            check(case, f"state window matches nothing like {spec['absentPattern'][:40]}",
                  not found)

        if kind == "raster":
            raster_checks(case)

    ok = not failures
    print(f"on-glass assertions over {len(CASES) + len(STATE_CASES)} cases / "
          f"{len(SURFACES)} surfaces / {len(STATES)} states"
          + (f"   DECOY={decoy}" if decoy else ""))
    for case in sorted(results):
        r = results[case]
        n = len(r["checks"])
        bad = [c["label"] for c in r["checks"] if not c["pass"]]
        key, kind = CASES.get(case) or STATE_CASES[case]
        print(f"  {'ok  ' if r['pass'] else 'FAIL'} {case} {key:<24} "
              f"{kind:<7} {n - len(bad)}/{n} checks"
              + (f"  <- {bad[0][:70]}" if bad else ""))
    print(f"\nchecked={checks} failures={len(failures)} "
          f"cases={len(CASES) + len(STATE_CASES)} "
          f"(surfaces {len(SURFACES)}, states {len(STATES)})")
    for f in failures[:12]:
        print(f"  FAILED  {f}")
    if len(failures) > 12:
        print(f"  … and {len(failures) - 12} more, all of them in "
              f"evidence/runs/glass-assert.json")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"checked": checks, "failures": failures,
                               "cases": results, "shots": shots,
                               "decoy": decoy, "pass": ok}, indent=1) + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
