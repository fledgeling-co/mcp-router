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

# The census rows whose predicate has actually been WATCHED TO FAIL under a planted defect, and
# nothing else. `armed` used to be set for every effect-rung row, which reads as "this was proved
# falsifiable" over rows nobody has ever seen go red - and an assertion nobody has watched fail is
# indistinguishable from one that cannot.
#
# Two plants, 2026-09-02, both reverted, transcripts in planning/evidence/WIN-SHELL/arming/:
#   removing the call that carries the sign-in switch to the supervisor broke
#     settings.launchAtLogin.effect and settings.persistence
#   making SettingsStore.Save report success without writing broke settings.persistence.store alone
#
# settings.launchAtLogin.baseline, settings.launchAtLogin.silence and settings.copyEndpoint HELD
# through both, which shows they are independent of those two defects and says nothing at all about
# whether they can go red. They stay unarmed until something has been watched to break them.
ARMED_BY_PLANT = {
    "settings.launchAtLogin.effect",
    "settings.persistence",
    "settings.persistence.store",
}

# Which DECLARED control each lane row drives, keyed by the lane's own control id.
#
# This table exists because of DEF-080. This generator used to write the COMMAND into `actuates`
# -- literally `["UIA TogglePattern.Toggle()"]` -- and `actuates` names a control the SURFACE
# declares, not the call the lane made. control-census.py refused those rows as strays, the
# integration pass corrected them by hand in cases.json, and the next run of this generator would
# have written them straight back. It is a table rather than something derived because the lane's
# report carries no label at all (`assert-report.json` rows have `"label": null`), so there is
# nothing to derive from: the binding between an AutomationId the lane addresses and the name the
# surface declares is a fact somebody has to state. A control id absent from this table actuates
# NOTHING, which is the honest default -- a naming row reads a name and has not driven anything.
# The command the lane ran belongs in the case's `note`, and is written there.
CONTROL_ACTUATES = {
    "settings.effect": ["Launch router daemon at sign-in"],
}


def read_json(path, encoding="utf-8"):
    return json.loads(io.open(path, encoding=encoding).read())


def write_json(path, doc):
    io.open(path, "w", encoding="utf-8").write(
        json.dumps(doc, ensure_ascii=False, indent=2) + "\n")


def stable_ids(all_cases, kept):
    """Give each generated subject an id that does NOT move when somebody adds a case by hand.

    THE DEFECT THIS FIXES, measured 2026-09-02. The first version allocated from `max(kept) + 1`,
    where `kept` is everything this generator did not write. So the generated block sat immediately
    above the highest hand-written id, and adding ONE case by hand slid all fifteen generated ids up
    by one. Two hand-written cases were authored against CASE-0309 and CASE-0310, the generator ran,
    and those numbers became the Discover and Skills rows instead - a silent collision that would
    have put two different claims under one id.

    It is also the exact shape this repository already paid for: `3189d028` renumbered
    CASE-0151..0161 and left brief X7 citing rows that no longer existed, which
    `target-resolution-gate` found and `registry-retirements.json` now has to carry.

    So an id is allocated ONCE per subject and then remembered, keyed on `generatedKey` - the
    destination or surface the row is about, which is what the row IS rather than where it landed.
    A new subject takes the next number above EVERY id in the file, generated ones included, so a
    number is never handed to a second claim even after its first one is deleted.
    """
    reserved = set()
    for case in all_cases:
        match = re.match(r"CASE-(\d+)$", str(case.get("id") or ""))
        if match:
            reserved.add(int(match.group(1)))

    remembered = {}
    for case in all_cases:
        key = case.get("generatedKey")
        if key and case.get("generatedBy") == GENERATOR:
            remembered[key] = case["id"]

    highest = max(reserved) if reserved else 0
    taken = {case["id"] for case in kept}

    def allocate(key):
        existing = remembered.get(key)
        if existing and existing not in taken:
            return existing
        nonlocal highest
        while True:
            highest += 1
            candidate = "CASE-%04d" % highest
            if candidate not in taken:
                return candidate

    return allocate


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
    # `cases` and not `kept`: the allocator has to see the ids it wrote last time, or it
    # cannot remember them and cannot avoid re-issuing them.
    allocate = stable_ids(cases, kept)
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
            "id": allocate("destination:" + row["id"]),
            "generatedKey": "destination:" + row["id"],
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
            # THE CONTROL PRESSED IS THE SHELL'S, AND THE CLAIM IS THE BOARD'S. The pane item lives
            # on the shell surface; the case is filed against the board it opens. control-census.py
            # takes `actuates` names from the surface a case is FILED against unless the case says
            # otherwise, so without this the row names a control SURF-03x has never declared and
            # the census exits 1.
            #
            # This pair was added to the registry BY HAND after a previous run and silently
            # reverted by the next one, which cost the census ten actuated controls and a red exit.
            # It belongs in the generator for the same reason every other field here does: a row
            # this tool writes is a row this tool must write completely.
            "actuatesSurface": shell_surface,
            "actuatesSurfaceNote": (
                "The control pressed is the shell's pane item; the claim is the board's. Filed "
                "against the board it proves, counted against the surface that carries the "
                "control."),
            "evidence": evidence,
            "note": note,
            "generatedBy": GENERATOR,
        })

    # ---------------------------------------------------------------- the shell itself
    measured = [r for r in report.get("results", []) if r.get("status") in ("pass", "fail")]
    distinct = {r.get("fingerprint") for r in measured if r.get("fingerprint")}
    written.append({
        "id": allocate("shell"),
        "generatedKey": "shell",
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
        # `Nav`, not "NavigationView pane". The registry's control vocabulary is the literal name
        # the source carries, so that `win-surface-reconcile.py` R4 can check the declaration
        # against ShellWindow.xaml rather than against a phrase somebody typed here. The pane is
        # `x:Name="Nav"` and carries no AutomationProperties.Name of its own, which SURF-030's
        # note records as the accessibility finding it is.
        "actuates": ["Nav"],
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

    # ---------------------------------------------------------------- the control census
    # Section 3b of the lane names controls and reads their state, which is the thing the
    # destination sweep above structurally cannot do: it grades a board on whether the board
    # CHANGED, so seven sections of working switches and three inert ones are the same pass.
    # DEF-076 lived in exactly that gap.
    #
    # These rows are generated from the report for the same reason every other row here is - a
    # case written by hand beside the run it describes is a claim about a measurement rather than
    # the measurement - and a census row that came back `unoracled` becomes an unoracled case
    # rather than being dropped, because a check that could not run and a check that found
    # nothing are the same green.
    census_surface = {"settings": "SURF-038", "discover": "SURF-044"}
    census_req = {"settings": "REQ-038", "discover": "REQ-039"}
    for row in report.get("controls", []):
        control_id = str(row.get("id") or "")
        family = control_id.split(".", 1)[0]
        surface = census_surface.get(family)
        if surface is None:
            print("  ! the census produced a control row '%s' that belongs to no known surface "
                  "family. Skipped, and this line is the finding." % control_id)
            continue

        status = row.get("status")
        if status in ("pass", "fail"):
            case_status = status
        else:
            case_status = "unoracled: %s" % row.get("detail", "")

        evidence = ["planning/evidence/WIN-SHELL/run/assert-report.json",
                    "planning/evidence/WIN-SHELL/run/lane.log"]
        if family == "settings":
            evidence.append("planning/evidence/WIN-SHELL/run/uia-shell-settings.json")
        else:
            evidence.append("planning/evidence/WIN-SHELL/run/uia-shell-discover-detail.json")
        if row.get("recorder"):
            # The two arming transcripts. A predicate nobody has watched fail is
            # indistinguishable from one that cannot, so the runs where these went red are
            # evidence in the same sense the green one is.
            evidence.append("planning/evidence/WIN-SHELL/arming/unbind-supervisor-lane.txt")
            evidence.append("planning/evidence/WIN-SHELL/arming/store-writes-nothing-lane.txt")

        # The effect row is a different rung from the naming rows, and saying so is the point:
        # reading a name proves the tree publishes one, and only the effect row can tell a bound
        # control from an inert one.
        #
        # `recorder`, added for DEF-087, is what the lane names when the thing that read the effect
        # is NOT this process at all - the Windows task scheduler through Get-ScheduledTask, a read
        # of the settings file off the disk, a clipboard read from a separate PowerShell host. A
        # row carrying one is an effect-witness whose recorder is not the writer; a row without one
        # was read off the shell's own accessibility tree, which is out of process and still only
        # ever a read of the shell.
        recorder = row.get("recorder")
        is_effect = control_id.endswith(".effect") or bool(recorder)
        reaches_the_machine = bool(recorder)
        note = (
            "Written from the control census in scripts/windows/uia/shell-lane.ps1 section 3b, "
            "which runs out of process against the real shell binary in the interactive session. "
            "The ids and labels it asserts are READ OUT OF THE PRODUCT'S OWN SOURCE "
            "(SettingsPresentation.cs) rather than restated in the harness, so a rename moves the "
            "expectation with it instead of leaving the lane measuring a product that does not "
            "ship. Controls are addressed by AutomationId, never by name: a UIA name search "
            "returns the first element carrying that name anywhere in the tree, and this shell's "
            "menu bar already holds a 'Router' and a 'Help'. The lane recorded: %s"
        ) % (row.get("detail") or "")
        if control_id.endswith(".effect") and not recorder:
            note += (
                " THIS IS THE ROW THAT SEPARATES A BOUND CONTROL FROM AN INERT ONE. It toggles "
                "the switch through TogglePattern and then reads a DIFFERENT element - the "
                "board's state readout, which the view renders from the model - so a switch that "
                "moved and wrote through to nothing would leave that line unchanged and fail "
                "here. It went red for real on the first run, against a readout carrying a static "
                "AutomationProperties.Name that overrode its own text."
            )
        if recorder:
            note += (
                " THE RECORDER IS NOT THE WRITER, and on this row it is not even the shell: %s. "
                "That is what makes this row a claim about the MACHINE rather than about the "
                "application's own report of itself, which is the whole of DEF-087. WHAT IT DOES "
                "NOT SETTLE: that the registration fires at a real logon, and that a daemon "
                "executable resolves on an operator's machine - the lane points the shipped "
                "resolution at a witness task name and a witness executable of its own so it "
                "cannot disturb the operator's real registration. Both limits stay on DEF-087's "
                "resolution rather than being folded into this green."
            ) % recorder
        else:
            note += (
                " WHAT THIS ROW DOES NOT SETTLE: anything outside the shell process. It is a read "
                "of the application's own accessibility tree, so a control that moved a model and "
                "reached no file and no scheduler passes it. The rows carrying a `recorder` are "
                "the ones that leave the process."
            )
        if is_effect:
            # DEF-080: the CALL is not the control. Named here because the field
            # above carries the control SURF-038 declares, and a reader of this row
            # is entitled to know what was actually invoked.
            note += (
                " THE CALL THIS LANE MADE, which is what `actuates` is NOT for: the row was "
                "driven through System.Windows.Automation's TogglePattern.Toggle() from "
                "shell-lane.ps1. `actuates` carries the control the surface declares - DEF-080."
            )

        written.append({
            "id": allocate("control:" + control_id),
            "generatedKey": "control:" + control_id,
            "req": census_req[family],
            "surface": surface,
            "flow": None,
            "lane": "windows-glass",
            "cell": {
                "surface": surface, "state": "as-launched", "viewport": "default",
                "theme": "system", "role": "operator", "dataShape": "no-router-running",
                "executionPlane": "on-glass",
            },
            "oracle": "effect-witness" if is_effect else "structural",
            "status": case_status,
            "armed": control_id in ARMED_BY_PLANT or (
                control_id.endswith(".effect") and not recorder),
            "armedNote": (
                ("armed by a planted defect, watched on 2026-09-02. Removing the call that "
                 "carries the sign-in switch to the supervisor broke "
                 "settings.launchAtLogin.effect and settings.persistence; making the store's Save "
                 "report success without writing broke settings.persistence.store alone. Both "
                 "transcripts are in planning/evidence/WIN-SHELL/arming/.")
                if control_id in ARMED_BY_PLANT else
                ("NOT armed. This row HELD through both plants of 2026-09-02 - see "
                 "planning/evidence/WIN-SHELL/arming/ - which establishes that it is independent "
                 "of those two defects and says nothing about whether it can go red at all. It "
                 "stays unarmed until something has been watched to break it.")
                if recorder else
                ("armed by observation rather than by a planted defect: this predicate FAILED on "
                 "the run of 2026-09-02T08:58Z, against a state readout whose accessible name was "
                 "a static label instead of its own text, and passed on the next run once the "
                 "override was removed. The failure is in lane.log verbatim.")
                if is_effect else
                ("not armed: no planted defect has been watched to fail this predicate. The "
                 "settings.sections row did come back red for real on 2026-09-02T08:55Z, when the "
                 "census read the tree before the board had realised - which arms the id lookup "
                 "against absence but not against a renamed control.")
            ),
            # A CONTROL THE SURFACE DECLARES, never the command the lane ran (DEF-080).
            # Two runners fixed this in the same wave and differently: wb1 made the LANE
            # emit `actuates` per row, and wb4 wrote CONTROL_ACTUATES here because
            # assert-report.json rows carried `"label": null` and there was nothing to
            # derive from. wb1's change makes that premise false, so the lane is the
            # source of record and the table is the fallback for a row emitted before it.
            # A control id in neither actuates NOTHING, which is the honest default: a
            # naming row reads a name and has not driven anything.
            "actuates": (list(row.get("actuates") or [])
                         or list(CONTROL_ACTUATES.get(control_id, []))),
            "evidence": evidence,
            "note": note,
            "witness": {
                "recorder": recorder or (
                    "System.Windows.Automation, in a PowerShell process that is not the "
                    "shell, reading the shell's published accessibility tree"),
                "effect": "machine-state" if reaches_the_machine else "ui-state",
                "count": 1,
            } if is_effect else None,
            "generatedBy": GENERATOR,
        })
        if written[-1]["witness"] is None:
            del written[-1]["witness"]

    # ---------------------------------------------------------------- the unreachable surfaces
    for surface in surfaces:
        if surface.get("status") != "manual":
            continue
        written.append({
            "id": allocate("manual:" + surface["id"]),
            "generatedKey": "manual:" + surface["id"],
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
