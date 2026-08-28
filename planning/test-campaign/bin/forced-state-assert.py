#!/usr/bin/env python3
"""J5 — what each board said in an arranged state, checked against the router itself.

WHAT THIS IS FOR
----------------
`bin/forced-state.sh` puts a real router into three chosen conditions and photographs the Servers
board in each. This is the half that decides what those observations mean.

Three of the product's honesty promises had, until this lane, no observation behind them:

    REQ-004  The Servers board reflects live server states from ServerStateTracker without
             inventing a figure the tracker did not observe.
    REQ-005  When the tracker is stale or the router is not running, live counts go ABSENT rather
             than displaying last-known figures as current.
    REQ-007  Numbers the router does not observe are never displayed. There is no fabricated
             memory saving.

All three carried evidence `reported`, and the reason was structural rather than lazy: every board
this campaign had ever photographed was drawn by `FixtureControlAPIClient`, so the pictures proved
the board renders a JSON file in this repository. What a board does when a router that WAS answering
stops had never been arranged at all, and that is the direction that matters — a board showing a
stale figure as current looks exactly like one that is right.

THE ORACLE IS NOT THE APP
-------------------------
Every figure asserted here is compared against `evidence/forced-state/router.<state>.json`, which
`forced-state.sh` fetched from the router over HTTP at the moment of the shutter, in a different
process from the one that drew the board. So "3 servers" on screen is checked against a router that
said three, not against a fixture that says three because it was written to.

The declared names carry a per-run nonce for the second half of the same argument: if the shell had
fallen back to the shipping endpoint — because the endpoint variable was refused, or because another
router happens to be listening on the machine — the names on the board would belong to a different
world, and `every server the router declared is on the board` goes red rather than passing.

ABSENCE IS ASSERTED AS ABSENCE
------------------------------
`REQ-005` is a promise that something is NOT drawn, and the only honest way to check that is to
arrange the failing condition on purpose and then look for nothing. Two independent absences are
checked in the stale and cold states rather than one, because they are drawn by different code:
the board header's `· N running` (`ServersBoardHeader.subtitle()`) and the sidebar readout's
`N of M declared servers running` (`ReadoutCopy.accessibilityLabel`). A guardrail that held in one
place and not the other would pass a single-predicate check.

A placeholder is a figure of its own, so nothing here accepts one: the checks look for the absence
of any digit in those two positions, not for a dash or an em-dash standing in.

ITS OWN CONTROL, BECAUSE THIS IS AN ABSENCE SWEEP
-------------------------------------------------
Most of what this asserts is that a string is NOT in a file, which is the exact shape
`planning/sweep-control-gate.py` exists to distrust. `--control` therefore builds a scratch
observation set in a temp directory that is never this campaign, proves the clean set passes, and
then plants ONE mutation per check and requires that check — and, for the mutations that should be
surgical, only that check — to go red. A check no mutation can redden has not been written.

`--control` is hermetic: no router, no build, no display server, no accessibility grant. That is why
it can live in `make lint` while the lane it arms cannot.

EXIT CODES
----------
    0  every check ran and passed
    1  a check ran and failed — a claim about the product
    2  the control failed: this script could not see its own planted defects, so it printed no
       verdict about anything
    3  nothing was compared. No observations, or a state named with no dump behind it. A report of
       zero findings over zero comparisons is the failure this code exists to prevent.
"""
from __future__ import annotations

import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

CAMPAIGN = Path(__file__).resolve().parent.parent
OBSERVATIONS = "evidence/forced-state/observations.json"

# The board header's own sentence, `ServersBoardHeader.subtitle()`.
CURRENT_HEADER = re.compile(r"(\d+) tools from (\d+) servers? · (\d+) running")
STALE_HEADER = re.compile(r"(\d+) tools from (\d+) servers? · last reading, not current")
# Any present-tense running claim in the header's position, whatever precedes it.
ANY_HEADER_RUNNING = re.compile(r"·\s*\d+\s+running")
# The sidebar readout's sentence, `ReadoutCopy.accessibilityLabel`.
SIDEBAR_RUNNING = re.compile(r"(\d+) of (\d+) declared servers running")
# Anything at all that reads as a count of tools and servers.
ANY_TOTALS = re.compile(r"\d+ tools from \d+ servers?")
# A fabricated memory saving, the figure `REQ-007` names by hand.
MEMORY_FIGURE = re.compile(r"\b\d+(?:[.,]\d+)?\s?(?:[KMGT]i?B|bytes)\b")
MEMORY_WORD = re.compile(r"\bsav(?:ed|ing|ings)\b", re.IGNORECASE)
# The copy `.failed` draws — `ControlAPIError.routerNotRunning`'s own headline.
NOT_RUNNING_COPY = "The router isn't running"
# A server this lane declared. The nonce is what makes a foreign name detectable.
LANE_SERVER = re.compile(r"j5-(?:alpha|beta|gamma)-[0-9A-Za-z-]+")
# The Signal Path's three figures — `SignalPath.swift`'s hub, which draws each line only when the
# fact behind it exists. `at rest` is a count of child processes that stay up when nothing is
# calling, and it is the product's central claim as a live number rather than a slogan.
AT_REST = re.compile(r"(\d+) at rest")
TOPOLOGY = re.compile(r"1 endpoint . (\d+) upstreams?")
# The port the board says the router answered on. `Text(":\(port)")` interpolates an Int through
# LocalizedStringKey, so what reaches the tree is group-separated — `:8,955`, not `:8955`.
PORT_DRAWN = re.compile(r":(\d[\d,]{2,})")

REQUIRED_STATES = ("cold", "running", "stale")


class Compared:
    """Findings, and the count of comparisons behind them.

    A findings list alone cannot tell a clean run from one that examined nothing, and this whole
    lane exists because a green that measured nothing is indistinguishable from a green that
    measured everything. So the denominator is carried beside the findings and is what decides
    exit 3.
    """

    def __init__(self) -> None:
        self.findings: list[tuple[str, str]] = []
        self.checks: list[str] = []

    def check(self, name: str, ok: bool, detail: str = "") -> None:
        self.checks.append(name)
        if not ok:
            self.findings.append((name, detail))

    def names(self) -> set[str]:
        return {n for n, _ in self.findings}


def read_router(campaign: Path, rel: str | None) -> dict | None:
    """What the router itself answered at this state, or None where it answered nothing.

    `None` is a reading rather than a gap: two of the three states are DEFINED by the router not
    answering, so a missing file there is the arrangement working.
    """
    if rel is None:
        return None
    return json.loads((campaign / rel).read_text())


class RouterFigures:
    """Tools, servers, running, at-rest, port, names — computed from the router's own response.

    Every one is recomputed here rather than read from a field the app also reads, so the board and
    this script agree only if both are right about the same payload. `atRest` in particular is the
    warm set WITH A CHILD ACTUALLY UP rather than the warm flag, which is the distinction
    `ServersBoardHeader` documents: `warmUp()` swallows a failure to start, so a warm server can
    carry `warm == true` with no process on the machine.
    """

    def __init__(self, reading: dict) -> None:
        servers = reading["servers"]
        self.tools = sum(int(s.get("tools") or 0) for s in servers)
        self.count = len(servers)
        self.running = sum(1 for s in servers if s.get("state") == "running")
        self.at_rest = sum(1 for s in servers if s.get("warm") and s.get("state") == "running")
        self.port = reading.get("port")
        self.names = [s["name"] for s in servers]


def check_running(cmp_: Compared, text: str, reading: dict) -> None:
    """REQ-004: the board reflects the router, and invents nothing."""
    figures = RouterFigures(reading)
    tools, count, running, names = figures.tools, figures.count, figures.running, figures.names
    header = CURRENT_HEADER.search(text)
    cmp_.check("running/header-is-current", header is not None,
               "the board drew no current-reading header while the router was answering")
    if header:
        cmp_.check("running/tools-match-router", int(header.group(1)) == tools,
                   f"the board says {header.group(1)} tools, the router says {tools}")
        cmp_.check("running/servers-match-router", int(header.group(2)) == count,
                   f"the board says {header.group(2)} servers, the router says {count}")
        cmp_.check("running/running-match-router", int(header.group(3)) == running,
                   f"the board says {header.group(3)} running, the router says {running}")
    sidebar = SIDEBAR_RUNNING.search(text)
    cmp_.check("running/sidebar-is-current", sidebar is not None,
               "the sidebar readout drew no counts sentence while the router was answering")
    if sidebar:
        cmp_.check("running/sidebar-matches-router",
                   (int(sidebar.group(1)), int(sidebar.group(2))) == (running, count),
                   f"the sidebar says {sidebar.group(0)!r}, the router says {running} of {count}")
    missing = [n for n in names if n not in text]
    cmp_.check("running/declared-servers-are-drawn", not missing,
               f"the router declared {missing} and the board does not show them. A board drawn "
               f"from another router would fail exactly here.")
    foreign = sorted(set(LANE_SERVER.findall(text)) - set(names))
    cmp_.check("running/no-undeclared-server-is-drawn", not foreign,
               f"the board shows {foreign}, which this run's router never declared")

    # The Signal Path's three figures. The port is the one that catches a shell which fell back to
    # the shipping endpoint even if every other number happened to agree: this lane's router is
    # never on 8879, so a board drawing that port is reading somebody else's world.
    at_rest = AT_REST.search(text)
    cmp_.check("running/at-rest-is-drawn", at_rest is not None,
               "the Signal Path drew no at-rest count while the router was answering")
    if at_rest:
        cmp_.check("running/at-rest-matches-router", int(at_rest.group(1)) == figures.at_rest,
                   f"the board says {at_rest.group(1)} at rest, the router has "
                   f"{figures.at_rest} warm child(ren) actually up")
    topology = TOPOLOGY.search(text)
    cmp_.check("running/topology-is-drawn", topology is not None,
               "the Signal Path drew no upstream count while the router was answering")
    if topology:
        cmp_.check("running/topology-matches-router", int(topology.group(1)) == count,
                   f"the board says {topology.group(1)} upstreams, the router declared {count}")
    ports = {p.replace(",", "") for p in PORT_DRAWN.findall(text)}
    cmp_.check("running/port-matches-router", ports == {str(figures.port)},
               f"the board draws port(s) {sorted(ports)} and the router answered on "
               f"{figures.port}. The shipping endpoint is 8879, so this is where a shell that "
               f"fell back to it is caught however plausible its other figures look.")


def check_stale(cmp_: Compared, text: str, running_text: str, observation: dict) -> None:
    """REQ-005's hard half: a router that WAS answering has stopped, and the counts go absent."""
    cmp_.check("stale/absence-was-arranged", observation["routerReachable"] is False,
               "the router was still answering at the stale shutter, so nothing was arranged")
    cmp_.check("stale/header-says-not-current", STALE_HEADER.search(text) is not None,
               "the board did not say its reading was no longer current")
    cmp_.check("stale/no-present-tense-running", ANY_HEADER_RUNNING.search(text) is None,
               "the header still claims a running count over a router that has stopped answering")
    cmp_.check("stale/sidebar-withholds-running", SIDEBAR_RUNNING.search(text) is None,
               "the sidebar readout still states a live count over a router that has stopped")
    cmp_.check("stale/at-rest-withheld", AT_REST.search(text) is None,
               "the Signal Path still states a live child-process count over a stopped router")
    was, now = STALE_HEADER.search(text), CURRENT_HEADER.search(running_text)
    if was and now:
        cmp_.check("stale/servers-that-were-read-are-kept",
                   was.group(2) == now.group(2),
                   f"the board showed {now.group(2)} servers while the router answered and "
                   f"{was.group(2)} after it stopped. A failed refresh is not evidence that the "
                   f"servers went away.")


def check_cold(cmp_: Compared, text: str, names: list[str], observation: dict) -> None:
    """REQ-005's other half and REQ-007: nothing has ever loaded, so nothing may be claimed."""
    cmp_.check("cold/absence-was-arranged", observation["routerReachable"] is False,
               "something answered on the endpoint at the cold shutter")
    cmp_.check("cold/says-the-router-is-not-running", NOT_RUNNING_COPY in text,
               f"the board did not draw {NOT_RUNNING_COPY!r} for a router that has never answered")
    cmp_.check("cold/claims-no-totals", ANY_TOTALS.search(text) is None,
               "the board stated a tools/servers total before any poll had ever succeeded")
    cmp_.check("cold/claims-no-running-count", ANY_HEADER_RUNNING.search(text) is None,
               "the board stated a running count before any poll had ever succeeded")
    cmp_.check("cold/sidebar-claims-nothing", SIDEBAR_RUNNING.search(text) is None,
               "the sidebar readout stated a count before any poll had ever succeeded")
    cmp_.check("cold/at-rest-claims-nothing", AT_REST.search(text) is None,
               "the Signal Path stated a child-process count before any poll had ever succeeded")
    cmp_.check("cold/port-claims-nothing", not PORT_DRAWN.search(text),
               "the board named a port for a router that has never answered — the only honest "
               "source for it is the router, and it has said nothing")
    shown = sorted(n for n in names if n in text)
    cmp_.check("cold/no-server-is-drawn", not shown,
               f"the board drew {shown} for a router that has never answered")


def check_no_fabricated_saving(cmp_: Compared, state: str, text: str) -> None:
    """REQ-007's second sentence, checked on every state rather than one.

    `DESIGN.md` §6 and this repository's standing constraint both name the memory saving by hand,
    because it is the figure a router of this kind is most often decorated with and the one nothing
    here observes: the router never runs the world it would have to be subtracted from.
    """
    figures = MEMORY_FIGURE.findall(text)
    cmp_.check(f"{state}/no-memory-figure", not figures,
               f"the board displays {sorted(set(figures))}, and the router observes no such figure")
    cmp_.check(f"{state}/no-saving-claim", MEMORY_WORD.search(text) is None,
               "the board claims a saving, and there is no measured saving in this product")


def assess(campaign: Path) -> tuple[Compared, int]:
    """Every check, over every arranged state. Returns the findings and the state count."""
    cmp_ = Compared()
    path = campaign / OBSERVATIONS
    if not path.exists():
        print(f"no observations at {OBSERVATIONS} — run bin/forced-state.sh first. Nothing was "
              f"compared, and a clean verdict over nothing is the failure this gate exists for.")
        return cmp_, 0
    record = json.loads(path.read_text())
    states = {s["state"]: s for s in record["states"]}
    missing = [s for s in REQUIRED_STATES if s not in states]
    if missing:
        print(f"the observation set is missing {missing}. Every check below depends on the three "
              f"states being arranged, so no partial verdict is offered.")
        return cmp_, 0

    texts = {}
    for name, observation in states.items():
        dump = campaign / observation["ax"]
        if not dump.exists():
            print(f"state {name!r} names {observation['ax']}, and there is no file there.")
            return cmp_, 0
        texts[name] = dump.read_text()
        cmp_.check(f"{name}/settled", observation["settled"] is True,
                   "the board never reached a settled reading inside the wait, so this picture is "
                   "of a board mid-flight rather than of an arranged state")
        check_no_fabricated_saving(cmp_, name, texts[name])

    # No two FILED frames may share a digest, and at least one state must have been filed.
    #
    # `bin/paint-check.py` already refuses a frame whose window had not laid out, so a state with no
    # `shot` is a withheld picture rather than a missing one and is not a finding here — the reason
    # is carried on the observation and the case that cites it records `n/a`. What this catches is
    # the failure that got past the first two runs of this lane: two states photographing
    # identically, which is what a window that never painted does every time.
    #
    # The second half is the denominator. A run in which every frame was withheld would satisfy the
    # distinctness check vacuously, and a raster claim over zero pictures is the shape this whole
    # campaign exists to refuse.
    filed = {name: o["sha256"] for name, o in states.items() if o.get("shot")}
    duplicates = sorted(n for n, sha in filed.items()
                        if list(filed.values()).count(sha) > 1)
    cmp_.check("raster/filed-frames-are-distinct", not duplicates,
               f"{duplicates} share a capture digest. Two arranged states cannot photograph "
               f"identically; a window that never painted photographs the same every time.")
    cmp_.check("raster/something-was-photographed", bool(filed),
               "every frame in this run was withheld, so the raster lane compared nothing. "
               "A distinctness check over an empty set passes without measuring anything.")

    running_reading = read_router(campaign, states["running"]["routerReading"])
    if running_reading is None:
        print("the running state carries no router reading, so every figure on that board would "
              "be checked against nothing.")
        return cmp_, 0
    check_running(cmp_, texts["running"], running_reading)
    check_stale(cmp_, texts["stale"], texts["running"], states["stale"])
    check_cold(cmp_, texts["cold"], record["declared"]["names"], states["cold"])
    return cmp_, len(states)


# ---------------------------------------------------------------------------------------
# The control. Every check above is an absence or an equality over text, and both classes
# pass when the reader is pointed at the wrong thing. So each one is planted against.
# ---------------------------------------------------------------------------------------

NAMES = ["j5-alpha-CONTROL", "j5-beta-CONTROL", "j5-gamma-CONTROL"]

CLEAN_RUNNING = (
    "0\tAXWindow\tAXStandardWindow\tServers\t\t\t\t\t\t\t\t\t180.0\t140.0\t980.0\t620.0\t0\n"
    "4\tAXStaticText\t\t\tChild processes, 1 of 3 declared servers running\t\t\t1\t\n"
    "5\tAXStaticText\t\t\t6 tools from 3 servers · 1 running\t\t\t1\t\n"
    "5\tAXStaticText\t\t\t1 endpoint \u2192 3 upstreams\t\t\t1\t\n"
    "5\tAXStaticText\t\t\tRouter, :8,955, 1 at rest\t\t\t1\t\n"
    + "".join(f"6\tAXButton\t\t\t{n}\t\t\t1\t\n" for n in NAMES)
)
CLEAN_STALE = (
    "0\tAXWindow\tAXStandardWindow\tServers\t\t\t\t\t\t\t\t\t180.0\t140.0\t980.0\t620.0\t0\n"
    "4\tAXStaticText\t\t\tChild processes\t\t\t1\t\n"
    "5\tAXStaticText\t\t\t6 tools from 3 servers · last reading, not current\t\t\t1\t\n"
    "5\tAXStaticText\t\t\t1 endpoint \u2192 3 upstreams\t\t\t1\t\n"
    "5\tAXStaticText\t\t\tRouter, :8,955\t\t\t1\t\n"
    + "".join(f"6\tAXButton\t\t\t{n}\t\t\t1\t\n" for n in NAMES)
)
CLEAN_COLD = (
    "0\tAXWindow\tAXStandardWindow\tServers\t\t\t\t\t\t\t\t\t180.0\t140.0\t980.0\t620.0\t0\n"
    "4\tAXStaticText\t\t\tThe router isn't running, Nothing is listening on the control port.\t\t\t1\t\n"
    "5\tAXStaticText\t\t\tThe router isn't running\t\t\t1\t\n"
)
CLEAN_READING = {
    "port": 8955,
    "servers": [
        {"name": NAMES[0], "tools": 4, "state": "running", "warm": True},
        {"name": NAMES[1], "tools": 2, "state": "idle", "warm": False},
        {"name": NAMES[2], "tools": 0, "state": "never-used", "warm": False},
    ],
}

# name -> (what it does to the scratch set, the check it must redden)
# mutation name -> the check it must redden. Every check `assess` can run appears on the right of
# this table exactly once, and `control()` refuses to report anything if one does not: a check no
# planted defect can redden has not been written, whatever it says about itself.
MUTATIONS: dict[str, str] = {
    "header-removed": "running/header-is-current",
    "tools-inflated": "running/tools-match-router",
    "servers-inflated": "running/servers-match-router",
    "running-inflated": "running/running-match-router",
    "sidebar-removed": "running/sidebar-is-current",
    "sidebar-disagrees": "running/sidebar-matches-router",
    "declared-server-hidden": "running/declared-servers-are-drawn",
    "foreign-server-drawn": "running/no-undeclared-server-is-drawn",
    "stale-router-alive": "stale/absence-was-arranged",
    "stale-not-marked": "stale/header-says-not-current",
    "stale-claims-running": "stale/no-present-tense-running",
    "stale-sidebar-claims-running": "stale/sidebar-withholds-running",
    "stale-drops-servers": "stale/servers-that-were-read-are-kept",
    "cold-router-alive": "cold/absence-was-arranged",
    "cold-copy-removed": "cold/says-the-router-is-not-running",
    "cold-claims-totals": "cold/claims-no-totals",
    "cold-claims-running": "cold/claims-no-running-count",
    "cold-sidebar-claims": "cold/sidebar-claims-nothing",
    "cold-draws-server": "cold/no-server-is-drawn",
    "twin-captures": "raster/filed-frames-are-distinct",
    "nothing-photographed": "raster/something-was-photographed",
    "at-rest-removed": "running/at-rest-is-drawn",
    "at-rest-inflated": "running/at-rest-matches-router",
    "topology-removed": "running/topology-is-drawn",
    "topology-inflated": "running/topology-matches-router",
    "port-is-the-shipping-one": "running/port-matches-router",
    "stale-claims-at-rest": "stale/at-rest-withheld",
    "cold-claims-at-rest": "cold/at-rest-claims-nothing",
    "cold-claims-port": "cold/port-claims-nothing",
}
# The three checks every state carries get a mutation per state rather than one between them.
# A guardrail that held on the board a run happened to look at and nowhere else is the shape this
# whole lane exists to catch, and it would survive a single planted instance.
for _state in REQUIRED_STATES:
    MUTATIONS[f"{_state}-memory-figure"] = f"{_state}/no-memory-figure"
    MUTATIONS[f"{_state}-saving-claim"] = f"{_state}/no-saving-claim"
    MUTATIONS[f"{_state}-unsettled"] = f"{_state}/settled"


def plant(root: Path, mutation: str | None) -> None:
    """Write a scratch observation set, optionally with one planted defect."""
    out = root / "evidence/forced-state"
    ax = root / "evidence/ax"
    out.mkdir(parents=True, exist_ok=True)
    ax.mkdir(parents=True, exist_ok=True)

    dumps = {"running": CLEAN_RUNNING, "stale": CLEAN_STALE, "cold": CLEAN_COLD}
    reading = json.loads(json.dumps(CLEAN_READING))
    reachable = {"running": True, "stale": False, "cold": False}
    settled = {"running": True, "stale": True, "cold": True}
    shas = {"cold": "c" * 64, "running": "r" * 64, "stale": "s" * 64}

    if mutation == "header-removed":
        dumps["running"] = dumps["running"].replace("6 tools from 3 servers · 1 running", "")
    elif mutation == "tools-inflated":
        dumps["running"] = dumps["running"].replace("6 tools from", "9 tools from")
    elif mutation == "servers-inflated":
        dumps["running"] = dumps["running"].replace("from 3 servers", "from 4 servers")
    elif mutation == "running-inflated":
        dumps["running"] = dumps["running"].replace("· 1 running", "· 2 running")
    elif mutation == "sidebar-removed":
        dumps["running"] = dumps["running"].replace("1 of 3 declared servers running", "")
    elif mutation == "sidebar-disagrees":
        dumps["running"] = dumps["running"].replace("1 of 3 declared servers running",
                                                   "2 of 3 declared servers running")
    elif mutation == "declared-server-hidden":
        dumps["running"] = dumps["running"].replace(f"6\tAXButton\t\t\t{NAMES[1]}\t\t\t1\t\n", "")
    elif mutation == "foreign-server-drawn":
        dumps["running"] += "6\tAXButton\t\t\tj5-alpha-SOMEONE-ELSES-ROUTER\t\t\t1\t\n"
    elif mutation == "stale-router-alive":
        reachable["stale"] = True
    elif mutation == "stale-not-marked":
        dumps["stale"] = dumps["stale"].replace(" · last reading, not current", "")
    elif mutation == "stale-claims-running":
        dumps["stale"] = dumps["stale"].replace("· last reading, not current", "· 1 running")
    elif mutation == "stale-sidebar-claims-running":
        dumps["stale"] = dumps["stale"].replace("Child processes",
                                                "Child processes, 1 of 3 declared servers running")
    elif mutation == "stale-drops-servers":
        dumps["stale"] = dumps["stale"].replace("6 tools from 3 servers", "0 tools from 0 servers")
    elif mutation == "cold-router-alive":
        reachable["cold"] = True
    elif mutation == "cold-copy-removed":
        dumps["cold"] = dumps["cold"].replace(NOT_RUNNING_COPY, "Nothing to show")
    elif mutation == "cold-claims-totals":
        dumps["cold"] += "5\tAXStaticText\t\t\t0 tools from 0 servers\t\t\t1\t\n"
    elif mutation == "cold-claims-running":
        dumps["cold"] += "5\tAXStaticText\t\t\tsomething · 0 running\t\t\t1\t\n"
    elif mutation == "cold-sidebar-claims":
        dumps["cold"] += "4\tAXStaticText\t\t\t0 of 3 declared servers running\t\t\t1\t\n"
    elif mutation == "cold-draws-server":
        dumps["cold"] += f"6\tAXButton\t\t\t{NAMES[0]}\t\t\t1\t\n"
    elif mutation == "twin-captures":
        shas["stale"] = shas["cold"]
    elif mutation == "nothing-photographed":
        shas = dict.fromkeys(shas, None)
    elif mutation == "at-rest-removed":
        dumps["running"] = dumps["running"].replace(", 1 at rest", "")
    elif mutation == "at-rest-inflated":
        dumps["running"] = dumps["running"].replace("1 at rest", "4 at rest")
    elif mutation == "topology-removed":
        dumps["running"] = dumps["running"].replace("1 endpoint \u2192 3 upstreams", "")
    elif mutation == "topology-inflated":
        dumps["running"] = dumps["running"].replace("\u2192 3 upstreams", "\u2192 5 upstreams")
    elif mutation == "port-is-the-shipping-one":
        dumps["running"] = dumps["running"].replace(":8,955", ":8,879")
    elif mutation == "stale-claims-at-rest":
        dumps["stale"] = dumps["stale"].replace("Router, :8,955", "Router, :8,955, 1 at rest")
    elif mutation == "cold-claims-at-rest":
        dumps["cold"] += "5\tAXStaticText\t\t\tRouter, 1 at rest\t\t\t1\t\n"
    elif mutation == "cold-claims-port":
        dumps["cold"] += "5\tAXStaticText\t\t\tRouter, :8,955\t\t\t1\t\n"
    elif mutation and mutation.endswith("-memory-figure"):
        dumps[mutation[: -len("-memory-figure")]] += \
            "7\tAXStaticText\t\t\t1.4 GB of memory saved\t\t\t1\t\n"
    elif mutation and mutation.endswith("-saving-claim"):
        dumps[mutation[: -len("-saving-claim")]] += \
            "7\tAXStaticText\t\t\tSaving you a whole lot\t\t\t1\t\n"
    elif mutation and mutation.endswith("-unsettled"):
        settled[mutation[: -len("-unsettled")]] = False
    elif mutation is not None:
        raise SystemExit(f"the control does not know how to plant {mutation!r}")

    for state, text in dumps.items():
        (ax / f"SURF-002.live-{state}.window.txt").write_text(text)
    (out / "router.running.json").write_text(json.dumps(reading))

    record = {
        "tool": "control",
        "endpoint": "http://127.0.0.1:8955",
        "declared": {"names": NAMES, "count": len(NAMES)},
        "states": [
            {
                "state": state,
                "arrangement": "planted by --control",
                "settled": settled[state],
                "routerReachable": reachable[state],
                "sha256": shas[state],
                "shot": f"evidence/shots/forced-state/SURF-002.live-{state}.png"
                        if shas[state] else None,
                "routerReading": "evidence/forced-state/router.running.json"
                                 if state == "running" else None,
                "ax": f"evidence/ax/SURF-002.live-{state}.window.txt",
            }
            for state in ("cold", "running", "stale")
        ],
    }
    (out / "observations.json").write_text(json.dumps(record, indent=1))


def control() -> int:
    """Plant, then require the instrument to see it. Prints what it planted either way."""
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="j5-forced-state-control-") as tmp:
        root = Path(tmp)

        plant(root, None)
        clean, states = assess(root)
        if states != 3:
            failures.append(f"the clean control arranged {states} state(s), not 3")
        if clean.findings:
            failures.append("the clean control reported findings, so a green here would mean "
                            f"nothing: {sorted(clean.names())}")
        planted_checks = set(clean.checks)
        print(f"control: the clean set runs {len(planted_checks)} distinct check(s) and reports "
              f"{len(clean.findings)} finding(s)")

        for mutation, must_redden in sorted(MUTATIONS.items()):
            if must_redden not in planted_checks:
                failures.append(f"{mutation} names {must_redden}, which the clean control never runs")
                continue
            shutil.rmtree(root / "evidence", ignore_errors=True)
            plant(root, mutation)
            got, _ = assess(root)
            if must_redden not in got.names():
                failures.append(f"{mutation}: planted, and {must_redden} stayed green. "
                                f"Findings were {sorted(got.names()) or 'none'}.")
        print(f"control: planted {len(MUTATIONS)} mutation(s), one per check that can be planted "
              f"against")

    uncovered = sorted(set(planted_checks) - set(MUTATIONS.values()))
    if uncovered:
        failures.append(f"these checks have no mutation and are therefore unproved: {uncovered}")

    if failures:
        print("CONTROL FAILED — this script could not see its own planted defects, so it has "
              "printed no verdict about the product:")
        for f in failures:
            print(f"   {f}")
        return 2
    print("control: every check was planted against and every planted defect was seen")
    return 0


def main(argv: list[str]) -> int:
    if "--control" in argv:
        return control()

    rc = control()
    if rc != 0:
        return rc
    cmp_, states = assess(CAMPAIGN)
    if states == 0:
        return 3
    print(f"forced-state: {len(cmp_.checks)} check(s) over {states} arranged state(s)")
    if cmp_.findings:
        print(f"{len(cmp_.findings)} finding(s):")
        for name, detail in cmp_.findings:
            print(f"   {name}: {detail}")
        return 1
    print("forced-state: every check passed against a router this lane arranged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
