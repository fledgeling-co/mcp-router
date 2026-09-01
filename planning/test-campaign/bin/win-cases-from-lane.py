#!/usr/bin/env python3
"""Write the Windows campaign cases FROM the shell lane's own report.

A case is a claim about what was measured, so the least trustworthy way to write one is by hand
next to the run that produced it. Every status here is derived from
`planning/evidence/WIN-SHELL/run/assert-report.json` - the file the lane wrote - which means a
case cannot say `pass` unless the lane recorded a pass, and re-running this after a worse run
turns the cases red rather than leaving yesterday's green in the registry. That is the exact
failure this repository has already paid for once: a suite that stayed green over evidence
captured from a build that no longer existed.

Three things this deliberately does NOT do:

  · It does not invent a case for a surface the lane never reached. The three `manual` surfaces
    get a case whose status is `n/a:` and whose text names the actuation nobody has built, taken
    from the surface's own note rather than composed here.
  · It does not mark anything `armed`. Arming means the predicate was watched to fail under a
    planted defect, and that has not been done for these. `armed: false` with the reason recorded
    is a smaller claim than the truth would be, which is the correct direction to be wrong in.
  · It does not touch the 156 existing cases. It removes only the rows it wrote itself, keyed on
    `generatedBy`, so re-running is idempotent and cannot quietly drop somebody else's work.
"""
import io
import json
import re
import sys
from pathlib import Path

CAMPAIGN = Path("planning/test-campaign")
REPORT = Path("planning/evidence/WIN-SHELL/run/assert-report.json")
GENERATOR = "scripts/windows/uia/shell-lane.ps1 via planning/test-campaign/bin/win-cases-from-lane.py"
WIN_REQ = "REQ-031"


def read_json(path, encoding="utf-8"):
    return json.loads(io.open(path, encoding=encoding).read())


def write_json(path, doc):
    io.open(path, "w", encoding="utf-8").write(
        json.dumps(doc, ensure_ascii=False, indent=2) + "\n")


def next_case_id(cases):
    highest = 0
    for case in cases:
        match = re.match(r"CASE-(\d+)$", str(case.get("id") or ""))
        if match:
            highest = max(highest, int(match.group(1)))
    n = highest
    while True:
        n += 1
        yield "CASE-%04d" % n


def main():
    if not REPORT.is_file():
        print("no lane report at %s - run scripts/windows/uia/run-shell-lane.ps1 first." % REPORT)
        print("Writing cases without one would be writing the claim instead of the measurement.")
        return 2

    report = read_json(REPORT, encoding="utf-8-sig")
    surfaces = read_json(CAMPAIGN / "surfaces-windows.json")
    cases = read_json(CAMPAIGN / "cases.json")

    # Route -> surface, taken from the surface file rather than restated, so a surface that moves
    # takes its cases with it instead of leaving them pointing at the old id.
    by_fragment, shell_surface = {}, None
    for surface in surfaces:
        route = str(surface.get("route") or "")
        if route == "app://windows/shell":
            shell_surface = surface["id"]
        elif "#" in route:
            by_fragment[route.split("#", 1)[1]] = surface["id"]

    if shell_surface is None:
        print("the surface file names no `app://windows/shell` route, so the shell itself has no")
        print("surface to carry a case. That is the registry failing, not the product passing.")
        return 2

    kept = [c for c in cases if c.get("generatedBy") != GENERATOR]
    dropped = len(cases) - len(kept)
    ids = next_case_id(kept)
    written = []

    # ---------------------------------------------------------------- the measured destinations
    for row in report.get("results", []):
        surface = by_fragment.get(row["id"])
        if surface is None:
            print("  ! the lane measured destination '%s' and no campaign surface claims the route "
                  "app://windows/shell#%s. Skipped, and this line is the finding."
                  % (row["id"], row["id"]))
            continue

        status = row.get("status")
        if status == "pass":
            case_status = "pass"
        elif status == "fail":
            case_status = "fail"
        elif status == "unoracled":
            case_status = "unoracled: %s" % row.get("reason", "")
        else:
            case_status = "n/a: %s" % row.get("reason", "")

        evidence = ["planning/evidence/WIN-SHELL/run/assert-report.json",
                    "planning/evidence/WIN-SHELL/run/lane.log"]
        if row.get("dump"):
            evidence.append("planning/evidence/WIN-SHELL/run/uia-shell-%s.json" % row["id"])

        note = (
            "Driven through the UI Automation plane against the real MCPRouter.Shell binary in the "
            "interactive session, out of process, with the target never foregrounded. The pane item "
            "named '%s' was actuated with SelectionItemPattern.Select(), and the reads were taken "
            "AFTER that actuation: the window title, the realised control-view tree, and a "
            "fingerprint over the tree's names. The fingerprint is what makes this more than a "
            "presence check - a destination whose tree is identical to the previous one is recorded "
            "as a COLLAPSE and fails, which is the shape where six sidebar items opened one "
            "placeholder view and every gate passed."
        ) % row.get("label", row["id"])
        if row.get("crashed"):
            note += (" THIS ROW IS A CRASH: selecting the destination terminated the process. See "
                     "DEF-077.")
        if row.get("relaunched"):
            note += (" The shell was relaunched before this destination because a previous one "
                     "terminated it; this board was measured on a fresh process.")
        if row.get("attempts", 1) > 1:
            note += (" Actuation took %d attempts - UIA reported the selection pattern available "
                     "and then threw on fetch, a stale-element race in the harness rather than a "
                     "property of the board." % row["attempts"])

        written.append({
            "id": next(ids),
            "req": WIN_REQ,
            "surface": surface,
            "flow": None,
            "lane": "windows-glass",
            "cell": {
                "surface": surface,
                "state": "as-launched",
                "viewport": "default",
                "theme": "system",
                "role": "operator",
                "dataShape": "no-router-running",
                "executionPlane": "on-glass",
            },
            "oracle": "outcome",
            "status": case_status,
            "armed": False,
            "armedNote": ("not armed: no planted defect has been watched to fail this predicate. "
                          "The collapse and title checks would each fail on a real regression, but "
                          "that has been reasoned rather than demonstrated, so this stays false."),
            "actuates": [row.get("label", row["id"])],
            "evidence": evidence,
            "note": note,
            "generatedBy": GENERATOR,
        })

    # ---------------------------------------------------------------- the shell itself
    measured = [r for r in report.get("results", []) if r.get("status") in ("pass", "fail")]
    distinct = {r.get("fingerprint") for r in measured if r.get("fingerprint")}
    written.append({
        "id": next(ids),
        "req": WIN_REQ,
        "surface": shell_surface,
        "flow": None,
        "lane": "windows-glass",
        "cell": {
            "surface": shell_surface, "state": "as-launched", "viewport": "default",
            "theme": "system", "role": "operator", "dataShape": "no-router-running",
            "executionPlane": "on-glass",
        },
        "oracle": "outcome",
        "status": "pass" if len(distinct) == len(measured) and measured else
                  ("fail" if measured else "n/a: the lane measured no destination"),
        "armed": False,
        "armedNote": "not armed; see the destination rows.",
        "actuates": ["NavigationView pane"],
        "evidence": ["planning/evidence/WIN-SHELL/run/assert-report.json"],
        "note": (
            "The shell's own row, and it asserts the one thing no per-destination case can: that "
            "the destinations are DISTINCT. %d destination(s) were measured and produced %d "
            "distinct control-view fingerprint(s). Counting the shell as one surface and stopping "
            "there is how an application whose six sidebar items opened a single placeholder view "
            "reported 8 of 8 surfaces covered."
        ) % (len(measured), len(distinct)),
        "generatedBy": GENERATOR,
    })

    # ---------------------------------------------------------------- the unreachable surfaces
    for surface in surfaces:
        if surface.get("status") != "manual":
            continue
        written.append({
            "id": next(ids),
            "req": WIN_REQ,
            "surface": surface["id"],
            "flow": None,
            "lane": "windows-glass",
            "cell": {
                "surface": surface["id"], "state": "unreached", "viewport": "default",
                "theme": "system", "role": "operator", "dataShape": "no-router-running",
                "executionPlane": "on-glass",
            },
            "oracle": "presence",
            "status": ("n/a: not reachable from the shell's navigation, so the destination sweep "
                       "never opens it. %s" % (surface.get("note") or "").strip()),
            "armed": False,
            "armedNote": "not armed: nothing was measured, so there is no predicate to arm.",
            "actuates": [],
            "evidence": [],
            "note": ("Registered as a case so this surface appears in the denominator with its "
                     "reason attached. A surface left out of the registry is invisible to a "
                     "coverage figure; a surface in it with an `n/a:` status is counted against "
                     "one. The second is the honest shape and it is the whole reason this row "
                     "exists rather than being omitted."),
            "generatedBy": GENERATOR,
        })

    # ------------------------------------------------------------- the defect registry
    # defects-windows.json is where the Windows defects are authored, and inventory.json is what
    # `reckon` and the campaign gates actually read. Keeping both by hand drifted within one day:
    # DEF-071 was fixed and verified in the Windows file while inventory still called it open, so
    # the reckoning went on scheduling it as remaining work, and DEF-077, DEF-078 and DEF-079 did
    # not exist in the registry at all. A finding that never reaches the file the gate reads is a
    # finding nobody acts on, so the sync belongs in the same command that writes the cases.
    inv = read_json(CAMPAIGN / "inventory.json")
    windows = read_json(CAMPAIGN / "defects-windows.json")
    by_id = {d.get("id"): d for d in inv.get("defect", [])}
    added, updated = [], []
    for defect in windows:
        did = defect.get("id")
        if did not in by_id:
            inv["defect"].append(defect)
            added.append(did)
        elif by_id[did].get("status") != defect.get("status"):
            updated.append("%s %s -> %s" % (did, by_id[did].get("status"), defect.get("status")))
            by_id[did].update(defect)
    if added or updated:
        write_json(CAMPAIGN / "inventory.json", inv)
    print("win-cases-from-lane: registry defects added %d, status changed %d"
          % (len(added), len(updated)))
    for line in added:
        print("    added   %s" % line)
    for line in updated:
        print("    changed %s" % line)

    write_json(CAMPAIGN / "cases.json", kept + written)
    print("win-cases-from-lane: replaced %d generated case(s) with %d" % (dropped, len(written)))
    by_status = {}
    for case in written:
        key = str(case["status"]).split(":")[0]
        by_status[key] = by_status.get(key, 0) + 1
    for key in sorted(by_status):
        print("    %-12s %d" % (key, by_status[key]))
    print("    cases.json now holds %d case(s)" % len(kept + written))
    return 0


if __name__ == "__main__":
    sys.exit(main())
