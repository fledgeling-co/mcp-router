#!/usr/bin/env python3
"""Phase 8, vocabulary vector: the controls the design and the build DISAGREE about, in both
directions — and the direction nothing else in this campaign can see.

## What this instrument is for, and what M32 found wrong with it

The original claim in this header was that the design-half is "the only pass that can see what the
build LACKS". That half is true and it is no longer this file's job: `design-controls.py` built a
declared control list per surface, `campaign.py check` counts how many of them a passing case
actuated, and `inventory.json` records the rest under `controlsUnactuatable` with a sentence each.
DEF-062, DEF-063, DEF-064 and DEF-065 are that machinery working.

**The other direction had no owner, and this file was already printing it.** `M32` is the class: a
gate that measures the build against the design can only fail on what the design DRAWS. A control
the build adds that the design never specified has no counterpart to disagree with, so the gate has
no opinion — **and no opinion reads exactly like agreement.**

This file was the instance as well as the instrument. Its own committed output at `63a4cda` carried

    SURF-005 · inBuildNotDesign: ["best match", "most used on smithery",
                                  "recently added to smithery"]

and `main()` returned 0. Those three are `RegistryPresentation.Ordering`, the third segmented
control on the Discover board — filed nine days later as `DEF-063` by `K3`, by driving the shipped
app by hand, because the instrument that already had it on disk exited 0 over it.

So the burden of proof is inverted here the way `mock_fidelity.py` inverts it, and for the same
reason: **a control the build draws that the design does not specify is a finding until a
disposition says otherwise.** Dispositions live in `planning/test-campaign/build-extras.json`, one
row per control, each naming either the defect it is or the reason it is intended. A control with
no row reddens this gate.

## The two halves, and why neither is what it used to be

DESIGN — `planning/test-campaign/evidence/design-controls.json`, not a live render of the mock.
The old design half rendered `design/mocks/prototype.html` through Obscura on every run. Three
things were wrong with that. The prototype is superseded — `ORCHESTRATOR.md`'s Contract settled
`design/mcp-router-console.html` as the design of record on 2026-08-22 — so the Harnesses, Insights
and capability-document surfaces were not in the comparison at all, which is to say the three
newest Mac surfaces were outside the one pass that could have seen their additions. The census
file already sources each surface from the design that actually draws it and records which in its
own `source` field. And the render dependency is on the engine whose `--eval` divergences this
repository has measured repeatedly. Reading the committed census removes the browser from the loop
and takes the surface count from 8 to 14.

Both the census's RESOLVED names and every `rawLabel` behind them count as specified. The census
renames a control whose drawn label is a fixture value — `Review 2.3.0…` becomes `Review the held
update…` — and comparing a build label against the resolved name alone would report the build's own
correct copy as an addition. The union is deliberately the generous reading: this gate should
under-report an extra rather than flood, which is the failure mode its own history records.

BUILD — every `evidence/ax/SURF-*.window.txt` dump for the surface, unioned. A control drawn in the
error state and not the ideal one is still drawn, so the states are a union rather than a choice.

## Four subtractions, each with the reason it is not signal

1. THE SHELL. The sidebar, window chrome and title appear on every board, so they belong to
   SURF-001 and to no board. Subtracted as SURF-001's design set UNION its build set — not, as
   before, as the intersection of every board's controls. The intersection is data-dependent and it
   failed in the direction that hides findings: the sidebar's Cleanup row reads `Cleanup, 3 never
   used` in one dump and `Cleanup` in another, so the intersection dropped it and three boards then
   reported `cleanup` as an addition of their own.

2. THE TENANT'S OWN DATA, structurally rather than by name. A control descending from a data
   collection — `AXOpaqueProviderGroup`, `AXOutline`, `AXTable`, `AXList`, `AXGrid` — is one
   affordance repeated once per fixture item, which is `design-controls.py`'s `ROW_CLASSES` rule
   read off the accessibility tree instead of off the mock's markup. Deriving it from the tree is
   what keeps a capture fixture's server names out of a registry that would then go stale whenever
   the fixture changed.

   **These are counted and named as their own class, never silently dropped.** A row-level control
   the design never specified is a real blind spot of this gate, and a blind spot with a printed
   number is a different thing from one without.

3. A LABEL CARRYING A FIGURE. A label containing a digit is a fixture value, a count or a
   timestamp, and its normalised form is noise — `2026-08-20T…Z` normalises to `j alpha t z`. The
   filter runs on the RAW label and on BOTH sides, so a control the design specifies with a version
   in its label leaves both sets together and cannot read as absent. `NUMERICISH` was defined in
   this file since it was written and never applied to anything; applying it is the fix.

4. WHAT WAS ALREADY DECIDED. `ACCEPTED` below, each with the reason it is not a finding.

## What this gate does NOT reach, stated rather than implied

  * A surface with no accessibility dump is INCONCLUSIVE and printed as such. It is never counted
    clean, and `examined=0` exits 2.
  * SURF-001's menu bar. `SURF-001.menu.txt` holds 160 menu items and most of them are the host
    operating system's — Finder, System Settings, Instruments. A menu-level differential over that
    dump reports the OS's items as this product's additions, so the shell's build half is its
    window dump alone and the menu bar is outside this gate. `M20` and `MenuCommand.swift` own it.
  * Row-level additions, per subtraction 2 — counted, not judged.
  * Whether a control that IS in both sets does the right thing. That is the effect ladder's
    question, not this one.

## Exits

    0  every surface compared, and every extra carries a disposition
    1  an extra with no disposition, or a disposition naming a control the build no longer draws
    2  nothing was compared — no dump on disk, or no census — which is not a pass
    3  the census or the disposition registry could not be read at all
"""
from __future__ import annotations  # `X | None` is evaluated at def time on 3.9

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CAMPAIGN = ROOT / "planning/test-campaign"
AX = CAMPAIGN / "evidence/ax"
CENSUS = CAMPAIGN / "evidence/design-controls.json"
REGISTRY = CAMPAIGN / "build-extras.json"
OUT = CAMPAIGN / "evidence/vocab-differential.json"
SHELL = "SURF-001"

# Decided, with the reason. A term here is not a finding; it is a closed question.
ACCEPTED = {
    "evals": "the mock's board is named Evals and the app's is named Checks — DEF-007, "
             "raised by the capture tie pass; the rename went one way only",
    "conduit": "the prototype carries the product's former name; the app ships as MCP Router",
}

# Comparing every word on both sides was tried first and produced 257 "missing" and 274 "drifted"
# terms across eight boards — a uniform flood, which detector-defects.md names as the signature of a
# dead predicate rather than a broken product. It was comparing an app's terse control labels
# against a prototype's explanatory prose. The comparison that carries signal is CONTROLS.
CONTROL_ROLES = {"AXButton", "AXCheckBox", "AXPopUpButton", "AXTextField", "AXRadioButton",
                 "AXSlider", "AXDisclosureTriangle", "AXMenuItem", "AXTabGroup", "AXLink"}

# Subtraction 2, read off the tree. A control inside one of these is a row: the design specifies one
# affordance and the fixture decides how many times it lands.
DATA_COLLECTIONS = {"AXOpaqueProviderGroup", "AXOutline", "AXTable", "AXList", "AXGrid"}

NUMERICISH = re.compile(r"\d")

VALID_DISPOSITIONS = {"defect", "intended", "misattributed"}


def normalise(label: str) -> str:
    """One control, one key — case, punctuation and trailing counts removed."""
    t = re.sub(r"[ -⁯]", " ", label)
    t = re.sub(r"[^A-Za-z ]+", " ", t)
    return " ".join(t.lower().split())


def is_control_label(key: str) -> bool:
    """A control's accessible name is short and imperative; a row's is a sentence.

    Four words is where the corpus splits: 'Reset call history' and 'Manage marketplaces' survive,
    'succeeded browser navigate on obscura in mcp router …' does not.
    """
    return bool(key) and 2 < len(key) <= 40 and len(key.split()) <= 4


def control_key(raw: str) -> str | None:
    """The one place a raw label becomes a comparison key, so both halves drop the same things.

    Returns None when the label is not a control name this gate can compare: subtraction 3 (it
    carries a figure) or the width filter (it is a sentence rather than a name).
    """
    if not raw or NUMERICISH.search(raw):
        return None
    key = normalise(raw)
    return key if is_control_label(key) else None


class Tally:
    """What a reader was given, and what it kept. A count of what parsed is not a denominator."""

    def __init__(self) -> None:
        self.seen = 0
        self.wrong_role = 0
        self.in_collection = 0
        self.carried_figure = 0
        self.too_long = 0
        self.kept = 0

    def line(self) -> str:
        return (f"seen={self.seen} kept={self.kept} · dropped: not-a-control-role="
                f"{self.wrong_role} inside-a-data-collection={self.in_collection} "
                f"label-carries-a-figure={self.carried_figure} not-a-control-name={self.too_long}")


def ax_controls(sid: str) -> tuple[set[str], set[str], list[str], Tally, list[str]]:
    """Actionable elements the running app published, by accessible name, over every dumped state.

    Columns are axkit's: 0 depth, 1 role, 2 subrole, 3 title, 4 value, 5 description, 6 help,
    7 enabled, 8 selected, …

    Returns (controls, row-level controls, files read, tally, window titles). A row-level control is
    one whose ancestry passes through a data collection — subtraction 2, derived from the tree
    rather than from a list of fixture names.

    The window title is read and reported and never acted on. A dump whose window is not this
    surface's is a capture-provenance defect, `capture-lineage.py --gate` owns that question, and a
    second instrument re-deriving it would be a third screen to disagree with the other two.
    """
    tally = Tally()
    controls: set[str] = set()
    rows: set[str] = set()
    windows: list[str] = []
    files = sorted(p for p in AX.glob(f"{sid}.*window.txt"))
    for path in files:
        # Depth of the shallowest data collection still open above the current node. `None` means
        # no collection is open, so anything read here is the surface's own control.
        collection_depth: int | None = None
        for line in path.read_text(errors="replace").splitlines():
            cols = line.split("\t")
            if len(cols) < 7:
                tally.seen += 1
                tally.wrong_role += 1
                continue
            try:
                depth = int(cols[0])
            except ValueError:
                tally.seen += 1
                tally.wrong_role += 1
                continue
            if cols[1] == "AXWindow" and cols[3].strip():
                windows.append(cols[3].strip())
            if collection_depth is not None and depth <= collection_depth:
                collection_depth = None
            if cols[1] in DATA_COLLECTIONS and collection_depth is None:
                collection_depth = depth
                continue
            if cols[1] not in CONTROL_ROLES:
                continue
            tally.seen += 1
            if collection_depth is not None:
                tally.in_collection += 1
            name = next((c for c in (cols[3], cols[5], cols[4], cols[6]) if c.strip()), "")
            if not name or NUMERICISH.search(name):
                if collection_depth is None:
                    tally.carried_figure += 1
                continue
            key = normalise(name)
            if not is_control_label(key):
                if collection_depth is None:
                    tally.too_long += 1
                continue
            if collection_depth is not None:
                rows.add(key)
                continue
            tally.kept += 1
            controls.add(key)
    return controls, rows, [p.name for p in files], tally, sorted(set(windows))


def design_controls(census: dict, sid: str) -> set[str]:
    """What the design of record specifies this surface carries.

    Resolved census names UNION every raw label behind them — see the header on why the union and
    not the resolved names alone.
    """
    surface = census.get("surfaces", {}).get(sid)
    if not surface:
        return set()
    out: set[str] = set()
    for name in surface.get("controls", []):
        key = control_key(name)
        if key:
            out.add(key)
    for detail in surface.get("detail", []):
        for raw in detail.get("rawLabels", []):
            key = control_key(raw)
            if key:
                out.add(key)
    return out


def read_dispositions(data: dict) -> tuple[dict[tuple[str, str], dict], list[str]]:
    """The registry's rules, over parsed data, so the control can plant one row at a time.

    Malformed rows are findings, never skips: a row this reader cannot understand is a control
    nobody has dispositioned, and dropping it would let a typo read as a reason.
    """
    rows: dict[tuple[str, str], dict] = {}
    problems: list[str] = []
    for row in data.get("dispositions", []):
        sid, control = row.get("surface"), row.get("control")
        if not sid or not control:
            problems.append(f"a disposition row names no surface or no control: {row!r}")
            continue
        if row.get("disposition") not in VALID_DISPOSITIONS:
            problems.append(f"{sid} · {control}: disposition {row.get('disposition')!r} is not one "
                            f"of {sorted(VALID_DISPOSITIONS)} — a word that is not a disposition "
                            f"is still silence")
            continue
        if row["disposition"] in ("defect", "misattributed") and not str(row.get("ref", "")):
            problems.append(f"{sid} · {control}: disposition `{row['disposition']}` with no `ref` — "
                            f"a defect nobody filed is a reason, not a disposition")
            continue
        if not row.get("reason"):
            problems.append(f"{sid} · {control}: no reason")
            continue
        rows[(sid, control)] = row
    return rows, problems


def load_dispositions() -> tuple[dict[tuple[str, str], dict], list[str]]:
    """The registry as it sits on disk."""
    if not REGISTRY.exists():
        return {}, [f"{REGISTRY.relative_to(ROOT)} does not exist — every extra is undisposed"]
    return read_dispositions(json.loads(REGISTRY.read_text()))


def findings_for(report: dict, dispositions: dict) -> list[str]:
    """The registry's two rules, in the one place both the gate and its control read them.

    Extracted rather than inlined because an arm that re-implements the predicate it is testing
    proves the arm, not the gate — which is `M32`'s own subject arriving inside `M32`'s own fix.
    """
    findings: list[str] = []
    for sid, row in sorted(report.items()):
        if "verdict" in row:
            continue
        for key in row["inBuildNotDesign"]:
            if (sid, key) not in dispositions:
                findings.append(f"{sid}: the build draws `{key}` and the design of record does not "
                                f"specify it — no row in {REGISTRY.relative_to(ROOT)}")
    # A disposition for a control the build stopped drawing is a claim nobody is checking any more.
    for (sid, key), row in sorted(dispositions.items()):
        entry = report.get(sid)
        if entry and "verdict" not in entry and key not in entry["inBuildNotDesign"]:
            findings.append(f"{sid}: a disposition for `{key}` ({row['disposition']}) and the "
                            f"build no longer draws it — a stale reason reads like a live one")
    return findings


def compare(census: dict, dispositions: dict, surfaces: list[str]) -> tuple[dict, list[str], list[str]]:
    """One pass over every surface the census declares.

    Returns (report, findings, rows) where `rows` names the surfaces actually compared — the
    denominator. A surface with no dump on disk is not in it, so `not rows` is the honest
    "this gate measured nothing" and never reads as "nothing diverged".
    """
    # The sidebar is the shell whether or not the accessibility tree draws it as a list. Reading
    # only SURF-001's non-row controls left `harnesses` and `insights` — the two destinations M22
    # added after the prototype drew the shell — leaking into every board as that board's own.
    shell_build, shell_rows, _, _, _ = ax_controls(SHELL)
    shell = design_controls(census, SHELL) | shell_build | shell_rows
    report: dict[str, dict] = {}
    rows: list[str] = []
    for sid in surfaces:
        build, row_level, files, tally, windows = ax_controls(sid)
        design = design_controls(census, sid)
        if sid != SHELL:
            build = build - shell
            design = design - shell
            row_level = row_level - shell
        if not files:
            report[sid] = {"verdict": "inconclusive — no accessibility dump on disk",
                           "designControls": len(design)}
            continue
        rows.append(sid)
        extras = sorted(k for k in build - design if k not in ACCEPTED)
        absent = sorted(k for k in design - build if k not in ACCEPTED)
        report[sid] = {
            "source": census["surfaces"][sid].get("source"),
            "dumps": files,
            "windows": windows,
            "reader": tally.line(),
            "buildControls": len(build),
            "designControls": len(design),
            "inBuildNotDesign": extras,
            "inDesignNotBuild": absent,
            "rowLevelNotJudged": sorted(row_level - design),
            "undisposed": [k for k in extras if (sid, k) not in dispositions],
        }
    return report, findings_for(report, dispositions), rows


def control() -> int:
    """One arm per predicate, each reddening ALONE, on dictionaries this function builds.

    An absence claim made by a set subtraction is the shape this campaign has been burned by four
    times, so every rule gets a planted instance and every planted instance differs from the clean
    one in exactly the thing it tests. The two refutations matter as much: a satisfied path that
    goes red is a gate that will be softened until it means nothing.
    """
    census = {"surfaces": {
        "SURF-001": {"source": "x", "controls": ["Servers"], "detail": []},
        "CTRL-900": {"source": "x", "controls": ["Rescan"],
                     "detail": [{"rawLabels": ["Review 2.3.0…"]}]},
    }}
    design = design_controls(census, "CTRL-900")
    arms: list[tuple[str, bool, str]] = []

    arms.append(("a resolved census name is specified", "rescan" in design, "rescan"))
    arms.append(("a raw label behind a resolved name is specified too",
                 "review" not in design, "the digit filter drops `Review 2.3.0…` on BOTH sides"))
    arms.append(("subtraction 3 drops a label carrying a figure",
                 control_key("All 4") is None, "All 4"))
    arms.append(("subtraction 3 does not drop a label without one",
                 control_key("Best match") == "best match", "Best match"))
    arms.append(("a sentence is not a control name",
                 control_key("succeeded browser navigate on obscura in mcp router") is None,
                 "a row label"))

    # The registry's own rules, planted one at a time and run through `findings_for` itself.
    drawn = {"SURF-005": {"inBuildNotDesign": ["best match"], "source": "x", "dumps": ["d"]}}
    gone = {"SURF-005": {"inBuildNotDesign": [], "source": "x", "dumps": ["d"]}}
    inconclusive = {"SURF-005": {"verdict": "no dump", "designControls": 1}}
    disposed = {("SURF-005", "best match"): {"disposition": "defect", "ref": "DEF-063",
                                             "reason": "r"}}
    stale = {("SURF-005", "gone"): {"disposition": "intended", "reason": "r"}}
    checks = [
        ("an extra with no disposition is a finding", drawn, {}, 1),
        ("an extra with a disposition is not", drawn, disposed, 0),
        ("a disposition the build no longer draws is a finding", gone, stale, 1),
        ("an inconclusive surface neither finds nor absolves", inconclusive, stale, 0),
    ]
    for label, report, disp, want in checks:
        found = len(findings_for(report, disp))
        arms.append((label, found == want, f"expected {want}, got {found}"))

    # The registry reader's own rules, planted the same way.
    for label, row, want in [
        ("a disposition that is not one of the two", {"surface": "S", "control": "c",
                                                      "disposition": "fine", "reason": "r"}, 1),
        ("`defect` with no DEF id", {"surface": "S", "control": "c",
                                     "disposition": "defect", "reason": "r"}, 1),
        ("`misattributed` with no ref", {"surface": "S", "control": "c",
                                         "disposition": "misattributed", "reason": "r"}, 1),
        ("`intended` with no reason", {"surface": "S", "control": "c",
                                       "disposition": "intended"}, 1),
        ("a well-formed row", {"surface": "S", "control": "c", "disposition": "intended",
                               "reason": "r"}, 0),
    ]:
        rows, problems = read_dispositions({"dispositions": [row]})
        arms.append((label, len(problems) == want, f"expected {want}, got {len(problems)}"))

    bad = 0
    for label, passed, detail in arms:
        mark = "ok" if passed else "FAILED"
        if not passed:
            bad += 1
        print(f"control: {mark:6s} {label:62s} {detail}")
    if bad:
        print(f"control: {bad} arm(s) FAILED. A differential that cannot see the difference it is "
              f"for is not evidence, so no figure is printed.")
        return 2
    print(f"control: {len(arms)} of {len(arms)} arms as expected.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--control", action="store_true",
                    help="Run the presence control and exit; touches no file.")
    ap.add_argument("--write", action="store_true",
                    help="Write evidence/vocab-differential.json. Off by default: a gate must not "
                         "mutate the working tree as a side effect of checking.")
    args = ap.parse_args()

    if args.control:
        return control()

    if not CENSUS.exists():
        print(f"vocab differential: NOT RUN — {CENSUS.relative_to(ROOT)} does not exist. Run "
              f"planning/test-campaign/bin/design-controls.py first. A missing design half is not "
              f"a design that specifies nothing.")
        return 3
    census = json.loads(CENSUS.read_text())
    surfaces = sorted(census.get("surfaces", {}))
    if not surfaces:
        print("vocab differential: NOT RUN — the census declares no surfaces.")
        return 3

    dispositions, problems = load_dispositions()
    report, findings, rows = compare(census, dispositions, surfaces)
    findings = problems + findings

    print(f"design of record: {census.get('designOfRecord')}")
    print(f"shell subtraction: {SHELL}'s design set union its build set, removed from every "
          f"other surface\n")
    for sid in surfaces:
        row = report[sid]
        if "verdict" in row:
            print(f"{sid}: {row['verdict']} — the design specifies {row['designControls']} "
                  f"control(s) here and nothing on disk says what the build drew")
            continue
        print(f"{sid} ({row['source']}): build={row['buildControls']} design={row['designControls']}"
              f" · in-build-not-design={len(row['inBuildNotDesign'])} "
              f"({len(row['undisposed'])} undisposed) · in-design-not-build="
              f"{len(row['inDesignNotBuild'])} · row-level-not-judged="
              f"{len(row['rowLevelNotJudged'])}")
        print(f"    window(s) the dump names: {', '.join(row['windows']) or 'none'}")
        print(f"    reader: {row['reader']}")
        if row["rowLevelNotJudged"]:
            print(f"    row-level, counted and NOT judged: "
                  f"{'; '.join(row['rowLevelNotJudged'])}")
        for key in row["inBuildNotDesign"]:
            disp = dispositions.get((sid, key))
            if disp is None:
                mark = "UNDISPOSED"
            else:
                mark = disp["disposition"] + (f" {disp['ref']}" if disp.get("ref") else "")
            print(f"    + {key}  [{mark}]")

    inconclusive = [s for s in surfaces if "verdict" in report[s]]
    print(f"\nexamined={len(rows)} surface(s) compared, {len(inconclusive)} inconclusive "
          f"({', '.join(inconclusive) or 'none'}) · accepted={len(ACCEPTED)} · "
          f"dispositions={len(dispositions)}")
    if not rows:
        print("examined=0 — the differential did not run, which is not a pass")
        return 2

    if args.write:
        OUT.write_text(json.dumps({"accepted": ACCEPTED, "surfaces": report}, indent=2) + "\n")
        print(f"wrote {OUT.relative_to(ROOT)}")

    print(f"findings: {len(findings)}")
    for line in findings:
        print(f"  · {line}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
