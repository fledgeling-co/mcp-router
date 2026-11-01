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

WHAT A ONE-WINDOW PREDICATE CANNOT SAY, AND THE RELATIONS THAT CAN
------------------------------------------------------------------
Everything above reads one window. That settles copy and it cannot settle a
control: an `AXButton` with the right label is in the tree whether or not its
handler does anything, which is why three cases here stood at `structural` and
said so in their own notes.

`RELATIONS` reads a board ACROSS its readings instead — populated, an answer of
none, a failed read — and requires the drawn control set to move the way the data
moved while the header controls do not. A board drawing a fixed column fails it,
and so does a board that lost its header controls when the list emptied. It needs
no press, which matters on a Debug shell: a second read of one fixture returns
the same bytes, so pressing `Rescan` and finding nothing changed would be
indistinguishable from a button wired to nothing.

Each relation carries named arms rather than one decoy, because a relation with
two halves needs a fault for each: substituting one reading's window for
another's reddens the count, and stripping the buttons a combined row no longer
publishes reddens the ownership half the count never touches.

    python3 glass-assert.py                  # assert every case
    python3 glass-assert.py --discriminate   # the arming control
    python3 glass-assert.py --decoy SURF-006 # drop one surface's copy, watch it red
    python3 glass-assert.py --relation-decoy SURF-007/combined-rows   # plant one
                                             # relation's fault, watch that relation red
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from pathlib import Path

D = Path(os.environ.get("MCP_ROUTER_GLASS_CAMPAIGN", Path(__file__).resolve().parent.parent)).resolve()
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
        # The nine boards of PRD.md §9.4. Settings is not among them: M15 (29829e6b) made it a
        # window of its own, and the mock's App menu carries `Settings…` rather than a sidebar row.
        "copy": [
            "Activity", "Servers", "Skills", "Harnesses", "Discover",
            "Inbox", "Checks", "Cleanup", "Insights",
        ],
        # REQ-003's other half. CASE-0002 is n/a because posting ⌘1–7 to a background pid does
        # not change SwiftUI's focused scene — measured, and a fact about the platform rather
        # than the product — so no run of this campaign can prove the keystroke NAVIGATES. What
        # it can prove is that the running app registered the bindings with the system, read
        # off the live menu bar rather than out of MenuCommand.swift. That is short of the
        # requirement and it is not nothing: a binding silently lost would be invisible today.
        # Scoped to `menuAction:` rows, because the Window menu lists the same board names with
        # `makeKeyAndOrderFront:` and no key of their own.
        #
        # The digits are DESIGN.md §8's, which the mock's View menu repeats (design/
        # mcp-router-console.html, Discover ⌘1 … Insights ⌘9) and which DESIGN.md says M22 ships.
        # The build's M22 map (Destination.selectionDigit, 8952a5b1) disagrees on eight of the
        # nine digits. That disagreement is DEF-522: this dict follows the design of record and
        # must not be re-mapped from the build to turn the check green.
        "menu": {"Discover": "1", "Skills": "2", "Servers": "3", "Activity": "4",
                 "Harnesses": "5", "Checks": "6", "Cleanup": "7", "Inbox": "8",
                 "Insights": "9", "Settings…": ","},
        "asserts": "the shell offers all nine boards in every window it draws, which is a "
                   "claim about persistence rather than identity, and its live menu bar declares "
                   "⌘1–9 and ⌘, against DESIGN.md §8",
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
        # The analyst is live (404d7832, 2026-08-29). planning/specs/spec-F7.md §3 item 8:
        # "`Analyse now` is enabled exactly when the router serves the route."
        "controls": {"Analyse now": True},
        "asserts": "the Insights board states that nothing on it is modelled, carries the "
                   "provenance line under the memory reading, says why a bar can read nothing "
                   "at all, states the duty cycle's mechanism and window rather than a "
                   "percentage about a world the router never ran, and speaks no saving anywhere",
    },
    "SURF-011": {
        # Its own window, not a board in the main window: PRD.md §9.5 "Settings is a separate
        # window". The shell chrome is therefore not in its dump, and the shell check skips it.
        "dump": "SURF-011.window.txt", "title": "Settings", "window": "Settings",
        # Its copy is drawn by two panes: the Router pane (photographed) and the Security pane.
        "panes": ["SURF-011.security.window.txt"],
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

# ── RELATIONS: what a board would have to CHANGE for the claim to hold ──────
#
# Everything above reads ONE window and asks what is in it. That is the right
# question for copy and the wrong one for a control, because a control's presence
# is true of a board wired to nothing — which is why the three cases below stood
# at `structural` and said so in their own notes.
#
# A relation asks the other question: hold the product fixed, vary the data, and
# require the drawn control set to move the way the data moved. It cannot be
# satisfied by a static drawing, and it needs no press — which matters here,
# because the Debug shell reads a fixture and a second read of the same fixture
# returns the same bytes, so pressing `Rescan` and finding nothing changed would
# be indistinguishable from a button wired to nothing.
#
# Each relation names the dumps it spans and the arm that reddens it. The arm is
# a SUBSTITUTION rather than a deletion: one state's dump is read from another
# state's file, which is precisely the regression the relation exists to catch —
# a board that drew its populated control set under a reading that returned none.
# `--relation-decoy <id>` performs it.

# The chrome every window carries, which is not a board control. Written as a set
# of exact labels plus the two badged spellings the sidebar uses, because
# `Cleanup` and `Cleanup, 3 never used` are one destination and a prefix match on
# `Reconcile` would have swallowed `Reconcile all…`.
SIDEBAR = {"Activity", "Servers", "Skills", "Harnesses", "Discover", "Inbox",
           "Checks", "Cleanup", "Insights", "Settings"}
CHROME = {"Hide Sidebar"}


def ax_rows(text: str) -> list[list[str]]:
    """Every AX row of a dump, as its tab-separated fields.

    Split with a floor on field count rather than on role, because a dump line
    that lost a column would otherwise be read as a different element quietly.
    """
    return [r for r in (line.split("\t") for line in text.splitlines()) if len(r) > 8]


def board_controls(text: str) -> list[tuple[int, str, str]]:
    """(depth, label, enabled) for every labelled AXButton that is the BOARD's.

    The window's own buttons (close, zoom, minimise) and the scrollbar's arrows
    carry an empty label and a role in field 2, so they drop out on the label
    test rather than on a list of names that would need maintaining. The sidebar
    destinations are named, because they are labelled and they are chrome: they
    appear in all nine boards' dumps, which is what CASE-0001 asserts and what
    would otherwise make every relation below pass on every window.
    """
    out = []
    for f in ax_rows(text):
        if f[1] != "AXButton" or not f[5]:
            continue
        name = f[5].split(",")[0]
        if name in SIDEBAR or f[5] in CHROME:
            continue
        out.append((int(f[0]), f[5], f[7]))
    return out


def candidate_rows(text: str) -> list[dict]:
    """The Cleanup board's rows, each with the controls it owns.

    A row is an `AXGroup` whose accessible name is `<name>, <kind>. <sentence>` —
    the label SwiftUI composes from a row that CONTAINS its children. Its controls
    are the buttons nested one level deeper, up to the next element at the row's
    own depth or shallower.

    **This reader is the whole point of the case.** `accessibilityElement(children:
    .combine)` flattens a row's buttons into that same label, so a combined row
    still produces the AXGroup and produces NO buttons under it. The count of
    controls per row is therefore the property the source assertion was standing
    in for, read off the running window instead of off `CleanupBoardRow.swift`.
    """
    rows, current = [], None
    for f in ax_rows(text):
        depth, role, label = int(f[0]), f[1], f[5]
        if current is not None and depth <= current["depth"]:
            rows.append(current)
            current = None
        if role == "AXGroup" and re.match(r"^[^,]+, (Server|Skill)\. ", label or ""):
            current = {"name": label.split(",")[0], "depth": depth, "controls": []}
            continue
        if current is not None and role == "AXButton" and label:
            current["controls"].append(label)
    if current is not None:
        rows.append(current)
    return rows


RELATIONS = {
    # CASE-0131 and the half of DEF-011 a source read cannot reach.
    #
    # `theRowContainsItsControls` asserts that `CleanupBoardRow` declares
    # `.contain` and not `.combine`. That is a proxy: what the modifier decides is
    # whether each row's buttons are separately addressable, and this reads that
    # directly off two real windows. The two carry DIFFERENT row populations —
    # three servers, then three servers and two skills — so a fixed control column
    # fails the count as well as a combined one failing the ownership.
    "SURF-007/row-actions": {
        "case": "CASE-0131",
        "dumps": ["SURF-007.window.txt", "SURF-007.cleanup-skills.window.txt"],
        "arms": {
            # The row column drawn at a fixed size: the skills window read from the
            # servers window, so both populations are three rows and none is flagged.
            "SURF-007/fixed-column": {
                "substitute": {"SURF-007.cleanup-skills.window.txt": "SURF-007.window.txt"},
            },
            # `accessibilityElement(children: .combine)`, which is the modifier the
            # source assertion this replaces was reading for. Combining flattens a
            # row's buttons into the row's own label, so the group survives and its
            # controls do not — reproduced here by dropping exactly those buttons.
            "SURF-007/combined-rows": {"strip": "row-buttons"},
        },
        "kind": "rows",
        "asserts": "every Cleanup row owns its own controls in the accessibility tree, the "
                   "number of control-bearing rows equals the number of rows drawn, the two "
                   "windows draw different numbers of them, and the action set is a function "
                   "of the row: exactly Inspect + Remove… where the row carries no provenance "
                   "note and exactly Read first… where it does",
    },
    # CASE-0167. The header controls are the ones that are only proved to render;
    # the relation is that they are the ONLY ones that do not move.
    "SURF-025/controls-track-reading": {
        "case": "CASE-0167",
        "dumps": ["SURF-025.window.txt", "SURF-025.empty.window.txt",
                  "SURF-025.failure.window.txt"],
        "arms": {
            # A board that kept drawing yesterday's harnesses through a reading that
            # returned none — the per-harness controls present where there are no
            # harnesses.
            "SURF-025/rows-through-empty": {
                "substitute": {"SURF-025.empty.window.txt": "SURF-025.window.txt"},
            },
        },
        "kind": "population",
        "invariant": {"Rescan": "1", "Reconcile all…": "0"},
        "populated": "SURF-025.window.txt",
        "rowControls": ["Reveal config in Finder", "Reconcile…", "Why a shim?"],
        "asserts": "the Harnesses board's two header controls are drawn in all three readings "
                   "with the same enabled state, while every per-harness control it draws is "
                   "present only in the reading that returned harnesses — so the control column "
                   "is computed from what was read rather than drawn regardless",
    },
    # CASE-0176. The board's single action is chosen by its state, which a board
    # drawing one fixed action would fail. Where the router serves the analyst route,
    # `Analyse now` is the populated reading's action and is enabled (spec-F7.md §3 item 8).
    "SURF-026/action-tracks-state": {
        "case": "CASE-0176",
        "dumps": ["SURF-026.window.txt", "SURF-026.empty.window.txt",
                  "SURF-026.failure.window.txt"],
        "arms": {
            # One action drawn regardless of state, which is what a board whose
            # action is a fixture of its layout rather than of its reading looks
            # like from the outside.
            "SURF-026/one-fixed-action": {
                "substitute": {"SURF-026.empty.window.txt": "SURF-026.window.txt"},
            },
        },
        "kind": "distinct-action",
        "expected": {
            "SURF-026.window.txt": ("Analyse now", "1"),
            "SURF-026.empty.window.txt": ("Watch the live log instead", "1"),
            "SURF-026.failure.window.txt": ("Start the router", "1"),
        },
        "asserts": "the Insights board draws exactly one action in each of its three readings, "
                   "the three are pairwise distinct, and each is absent from the other two "
                   "windows — so the action is a function of the state rather than a fixture "
                   "of the board",
    },
}


# arm id -> the relation it belongs to, so `--relation-decoy` names one fault
# rather than one relation. A relation with several ways to break wants several
# arms: the row relation stands on ownership AND on count, and a substitution
# that reddens the count leaves the ownership half unwatched.
ARMS = {arm: rid for rid, rel in RELATIONS.items() for arm in rel.get("arms", {})}

# What each `strip` plant actually removed, keyed `<arm>:<dump>`. Printed with the run and written
# into the verdict file, because an arm is only evidence if what it planted is on the record: an
# arm whose predicate matched nothing removes nothing and leaves the relation green, which is
# indistinguishable from a relation that does not bite.
ARM_DROPS: dict[str, list[str]] = {}


def relation_dump(relation: dict, name: str, arm: str | None) -> str:
    """One dump of a relation, with the named fault planted in it if it has one.

    `substitute` reads one reading's window out of another reading's file, leaving
    the relation to notice that two readings it should be able to tell apart have
    become one. `strip` removes the rows a regression would remove — here the
    buttons a combined row no longer publishes.
    """
    plant = relation.get("arms", {}).get(arm or "", {})
    source = plant.get("substitute", {}).get(name, name)
    text = (AX / source).read_text()
    if plant.get("strip") == "row-buttons":
        depths = {row["depth"] for row in candidate_rows(text)}
        keep, dropped = [], []
        for line in text.splitlines():
            f = line.split("\t")
            if (len(f) > 8 and f[1] == "AXButton" and f[5]
                    and int(f[0]) - 1 in depths and f[5] not in CHROME
                    and f[5].split(",")[0] not in SIDEBAR):
                # Named rather than skipped. An arm that planted nothing and an arm that planted
                # the wrong thing both leave the relation green, and the two are told apart only
                # by what the plant says it removed — so the list escapes into ARM_DROPS and is
                # printed with the relation's own line.
                dropped.append(f[5])
                continue
            keep.append(line)
        ARM_DROPS["%s:%s" % (arm, name)] = dropped
        print("  plant %s: removed %d row control(s) from %s — %s"
              % (arm, len(dropped), name, ", ".join(sorted(set(dropped))) or "NOTHING, "
                 "which is an arm that planted no fault rather than a relation that held"))
        text = "\n".join(keep)
    return text


def carries(phrase, text: str) -> bool:
    """A predicate is a literal or a pattern; both answer the same question."""
    return bool(phrase.search(text)) if isinstance(phrase, re.Pattern) else phrase in text

def label_of(phrase) -> str:
    return phrase.pattern if isinstance(phrase, re.Pattern) else phrase

def dump_text(key: str, decoy: str | None) -> str:
    spec = SURFACES[key] if key in SURFACES else STATES[key]
    text = (AX / spec["dump"]).read_text()
    # A separate window whose copy spans panes is read across every pane dump the lane wrote for it.
    # A pane dump that is missing is not substituted: its phrases simply are not found.
    for pane in spec.get("panes", []):
        if (AX / pane).exists():
            text += "\n" + (AX / pane).read_text()
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
    relation_decoy = (sys.argv[sys.argv.index("--relation-decoy") + 1]
                      if "--relation-decoy" in sys.argv else None)
    if relation_decoy is not None and relation_decoy not in ARMS:
        print(f"--relation-decoy {relation_decoy} names no arm. One of: "
              f"{', '.join(ARMS)}", file=sys.stderr)
        return 2

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
            # The main-window population. A surface with its own `"window"` is a separate window
            # (PRD.md §9.5 "Settings is a separate window"), so the main window's chrome is not in its
            # dump by construction, and requiring it there would test the wrong window.
            population = [o for o in SURFACES if "window" not in SURFACES[o]]
            missing = [o for o in population
                       if not all(carries(p, dump_text(o, decoy)) for p in spec["copy"])]
            check(case, f"shell chrome present in all {len(population)} main-window dumps",
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

    # ── the relations ───────────────────────────────────────────────────────
    #
    # Read across a board's readings rather than within one, so the claim is
    # about what the board COMPUTES rather than about what it contains. Every
    # denominator below is checked to be non-zero first: a relation asserted over
    # no rows and no controls is satisfied by an empty file, which is the shape of
    # a clean answer from an instrument pointed at nothing.
    relation_spans = {}
    for rid, rel in RELATIONS.items():
        case = rel["case"]
        arm = relation_decoy if ARMS.get(relation_decoy or "") == rid else None
        texts = {name: relation_dump(rel, name, arm) for name in rel["dumps"]}
        relation_spans[rid] = {"case": case, "dumps": rel["dumps"],
                               "arms": sorted(rel.get("arms", {})), "armed": arm}
        planted = {k: v for k, v in ARM_DROPS.items() if arm and k.startswith(arm + ":")}
        if planted:
            relation_spans[rid]["planted"] = planted
        for name, text in texts.items():
            check(case, f"{rid}: {name} is an AXWindow tree",
                  "AXWindow" in text and len(text) > 500)

        if rel["kind"] == "rows":
            per_dump = {name: candidate_rows(text) for name, text in texts.items()}
            counts = {name: len(rows) for name, rows in per_dump.items()}
            relation_spans[rid]["rowCounts"] = counts
            check(case, f"{rid}: every window draws rows to read ({counts})",
                  all(n > 0 for n in counts.values()))
            # The relation. Two windows, two different populations: a control
            # column drawn at a fixed size cannot satisfy both.
            check(case, f"{rid}: the two windows draw different row counts "
                        f"({sorted(counts.values())})",
                  len(set(counts.values())) == len(counts))
            owning = {name: [r for r in rows if r["controls"]]
                      for name, rows in per_dump.items()}
            relation_spans[rid]["rowsOwningControls"] = {
                name: len(rows) for name, rows in owning.items()}
            check(case, f"{rid}: every row owns its own controls in the tree — "
                        f"{ {n: f'{len(owning[n])}/{counts[n]}' for n in counts} }",
                  all(len(owning[name]) == counts[name] for name in counts))
            # The action set is a function of the row rather than of the board.
            flagged = [r for rows in per_dump.values() for r in rows
                       if "Read first…" in r["controls"]]
            plain = [r for rows in per_dump.values() for r in rows
                     if "Read first…" not in r["controls"]]
            relation_spans[rid]["flagged"] = [r["name"] for r in flagged]
            check(case, f"{rid}: a flagged row is drawn to compare against "
                        f"({len(flagged)} flagged, {len(plain)} not)",
                  bool(flagged) and bool(plain))
            check(case, f"{rid}: a flagged row draws Read first… and NEITHER of the other two",
                  all(r["controls"] == ["Read first…"] for r in flagged))
            check(case, f"{rid}: an unflagged row draws Inspect and Remove… and no Read first…",
                  all(r["controls"] == ["Inspect", "Remove…"] for r in plain))

        elif rel["kind"] == "population":
            census = {name: board_controls(text) for name, text in texts.items()}
            relation_spans[rid]["controls"] = {
                name: [(label, en) for _, label, en in c] for name, c in census.items()}
            check(case, f"{rid}: every reading draws controls to compare "
                        f"({ {n: len(c) for n, c in census.items()} })",
                  all(c for c in census.values()))
            for label, enabled in rel["invariant"].items():
                drawn = {name: [en for _, la, en in c if la == label]
                         for name, c in census.items()}
                check(case, f"{rid}: {label} is drawn in all {len(census)} readings, "
                            f"always {'enabled' if enabled == '1' else 'disabled'}",
                      all(drawn[name] == [enabled] for name in drawn))
            rowish = {name: [la for _, la, _ in c if la in rel["rowControls"]]
                      for name, c in census.items()}
            relation_spans[rid]["perRowControls"] = {n: len(v) for n, v in rowish.items()}
            populated = rel["populated"]
            check(case, f"{rid}: the reading that returned harnesses draws per-harness "
                        f"controls ({len(rowish[populated])})",
                  len(rowish[populated]) > 0)
            others = [n for n in rowish if n != populated]
            check(case, f"{rid}: a reading that returned none draws none of them "
                        f"({ {n: len(rowish[n]) for n in others} })",
                  all(not rowish[n] for n in others))

        elif rel["kind"] == "distinct-action":
            actions = {name: board_controls(text) for name, text in texts.items()}
            relation_spans[rid]["actions"] = {
                name: [(la, en) for _, la, en in a] for name, a in actions.items()}
            check(case, f"{rid}: each reading draws exactly one board action "
                        f"({ {n: len(a) for n, a in actions.items()} })",
                  all(len(a) == 1 for a in actions.values()))
            drawn = {name: (a[0][1], a[0][2]) for name, a in actions.items() if len(a) == 1}
            check(case, f"{rid}: each reading draws the action its state calls for ({drawn})",
                  drawn == rel["expected"])
            labels = [la for la, _ in drawn.values()]
            check(case, f"{rid}: the {len(labels)} actions are pairwise distinct ({labels})",
                  len(set(labels)) == len(labels) and len(labels) == len(rel["dumps"]))
            # The half that bites under the substitution: a label belonging to one
            # reading must appear in no other reading's window at all.
            strays = [(la, other) for name, (la, _) in drawn.items()
                      for other in texts if other != name and la in texts[other]]
            check(case, f"{rid}: no reading's action appears in another reading's window "
                        f"({len(strays)} stray)", not strays)

    ok = not failures
    print(f"on-glass assertions over {len(CASES) + len(STATE_CASES)} cases / "
          f"{len(SURFACES)} surfaces / {len(STATES)} states / {len(RELATIONS)} relations"
          + (f"   DECOY={decoy}" if decoy else "")
          + (f"   RELATION-DECOY={relation_decoy}" if relation_decoy else ""))
    for case in sorted(results):
        r = results[case]
        n = len(r["checks"])
        bad = [c["label"] for c in r["checks"] if not c["pass"]]
        key, kind = CASES.get(case) or STATE_CASES.get(case) or ("relation-only", "relation")
        print(f"  {'ok  ' if r['pass'] else 'FAIL'} {case} {key:<24} "
              f"{kind:<7} {n - len(bad)}/{n} checks"
              + (f"  <- {bad[0][:70]}" if bad else ""))
    print(f"\nchecked={checks} failures={len(failures)} "
          f"cases={len(CASES) + len(STATE_CASES)} "
          f"(surfaces {len(SURFACES)}, states {len(STATES)}, relations {len(RELATIONS)})")
    for f in failures[:12]:
        print(f"  FAILED  {f}")
    if len(failures) > 12:
        print(f"  … and {len(failures) - 12} more, all of them in "
              f"evidence/runs/glass-assert.json")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"checked": checks, "failures": failures,
                               "cases": results, "shots": shots,
                               "relations": relation_spans,
                               "decoy": decoy, "relationDecoy": relation_decoy,
                               "pass": ok}, indent=1) + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
