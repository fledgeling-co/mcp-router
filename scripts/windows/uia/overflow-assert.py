#!/usr/bin/env python3
"""SURF-029 — grade the three overflow readings taken by overflow-lane.ps1.

## What this grades, and why it takes three readings rather than one

`probe-expectation.json` carried the two SecondaryCommands, 'Export log' and 'Reset router', on
its `unoracled` list: a CommandBar does not realise its overflow items while the overflow is shut,
so neither element exists on the automation plane at rest. SURF-029 enumerated both controls and
no case had ever reached them, which is what `planning/registry-drop-gate.py` reports as an
uncovered surface. An absence recorded with a reason is honest; it is still not coverage.

The lane opens the overflow through `ExpandCollapsePattern.Expand` and reads the tree back. This
file grades what came out, and the shape of the grading is the point:

    BASELINE  overflow shut     both ids absent from the control view AND the raw view
    EFFECT    overflow opened   both ids present, with their on-screen name and ControlType
    SILENCE   overflow shut     both ids absent again

A presence asserted alone is satisfied by a harness that reads a stale dump, points at the wrong
process, or grades a file it wrote itself. BASELINE and SILENCE are the two readings that can say
no, and a recorder that has never said no is an echo. So all three are required: a run that
produced only EFFECT is NO VERDICT, not a pass.

## The never-activated claim is measured here, and it turned out to cost something

`probe-expectation.json` predicted that opening the overflow would cost the never-activated
guarantee. It was right, and this file is where that stopped being a prediction. Measured on
LUKESFF 2026-09-02: the probe owned the foreground at NONE of the three baseline samples and at
ALL SIX of the effect and silence samples, so `ExpandCollapsePattern.Expand` on a WinUI CommandBar
activates the window, and collapsing it again does not hand the foreground back.

That cost is declared in the manifest as `overflow.activationCost` and compared BOTH WAYS, so the
day WinUI stops activating, this arm reddens and the row has to move rather than the lane quietly
acquiring a guarantee nobody re-checked. BASELINE is the arm that stays a hard assertion: nothing
has been actuated yet there, so a probe already in front means the harness activated it on its own
and every later reading is of a different condition from the one claimed.

## Vacuity

Every check below iterates the `overflow.commands` list out of the expectation. An emptied list
would produce zero failures and exit 0, which is the emptied-manifest hole `uia-assert.py`'s
`minimums` was written for, arriving at a second oracle. So the floor from `minimums.overflow` is
asserted here before anything is graded, and a floor below 1 is itself a failure.

    exit 0   every assertion ran and passed
    exit 1   an assertion ran and FAILED
    exit 3   NO VERDICT — a reading is missing, empty or truncated

Usage:
    python scripts/windows/uia/overflow-assert.py --out <lane out dir>
                                                  --expectation <probe-expectation.json>
                                                  [--report <report.json>]
"""

import argparse
import json
import os
import sys

EXIT_PASS = 0
EXIT_FAIL = 1
EXIT_NO_VERDICT = 3

PHASES = ("baseline", "effect", "silence")
PRESENT_IN = "effect"


def load_json(path):
    """Read a JSON file PowerShell may have written with a UTF-8 BOM."""
    with open(path, "r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def index_by_automation_id(elements):
    index = {}
    for element in elements:
        key = element.get("automationId") or ""
        if key:
            index.setdefault(key, []).append(element)
    return index


def read_phase(out_dir, phase):
    """Both views for one phase, or a reason this phase measured nothing."""
    control_path = os.path.join(out_dir, "%s-control-view.json" % phase)
    raw_path = os.path.join(out_dir, "%s-raw-view.json" % phase)

    for path in (control_path, raw_path):
        if not os.path.exists(path):
            return None, "no dump at %s" % path

    control = load_json(control_path)
    raw = load_json(raw_path)

    for label, dump in (("control", control), ("raw", raw)):
        if not (dump.get("targets") or []) or not (dump.get("elements") or []):
            return None, ("the %s %s-view dump holds %d target window(s) and %d elements; an "
                          "empty tree satisfies every absence below for free"
                          % (phase, label, len(dump.get("targets") or []),
                             len(dump.get("elements") or [])))
        if dump.get("truncated"):
            return None, ("the %s %s-view walk hit its depth or element guard; a missing control "
                          "cannot be told from a truncated one" % (phase, label))

    return {
        "control": control,
        "raw": raw,
        "controlIndex": index_by_automation_id(control.get("elements") or []),
        "rawIndex": index_by_automation_id(raw.get("elements") or []),
    }, None


def read_receipt(out_dir, action):
    path = os.path.join(out_dir, "actuate-%s.json" % action)
    if not os.path.exists(path):
        return None
    return load_json(path)


class Findings(object):
    def __init__(self):
        self.passed = []
        self.failed = []

    def ok(self, check, detail):
        self.passed.append({"check": check, "detail": detail})

    def bad(self, check, detail):
        self.failed.append({"check": check, "detail": detail})


def check_floor(expectation, findings):
    commands = (expectation.get("overflow") or {}).get("commands") or []
    floor = (expectation.get("minimums") or {}).get("overflow")

    if floor is None:
        findings.bad(
            "manifest.minimums.overflow",
            "the expectation declares no floor for `overflow`, so an emptied command list cannot "
            "be told from a deliberate one. An oracle that asks nothing grades everything correct",
        )
        return commands
    if floor < 1:
        findings.bad(
            "manifest.minimums.overflow",
            "the floor for overflow is %d; a floor below 1 is satisfied by an empty list and "
            "guards nothing" % floor,
        )
        return commands
    if len(commands) < floor:
        findings.bad(
            "manifest.minimums.overflow",
            "the manifest declares %d overflow command(s) and its own floor is %d; it has been "
            "trimmed below what it promises to check" % (len(commands), floor),
        )
        return commands

    findings.ok("manifest.minimums.overflow", "%d overflow command(s), floor %d"
                % (len(commands), floor))
    return commands


def check_actuation(out_dir, findings):
    """The actuator's own receipt, read back from disk rather than trusted in-process.

    This is the writer's account of what it did. It is graded because a lane whose actuation
    silently no-opped would otherwise show up only as a confusing absence in EFFECT.
    """
    for action, want_before, want_after in (("expand", "Collapsed", "Expanded"),
                                            ("collapse", "Expanded", "Collapsed")):
        receipt = read_receipt(out_dir, action)
        if receipt is None:
            findings.bad("actuate.%s" % action, "no receipt at actuate-%s.json" % action)
            continue
        before, after = receipt.get("stateBefore"), receipt.get("stateAfter")
        if before == want_before and after == want_after:
            findings.ok("actuate.%s" % action,
                        "ExpandCollapseState %s -> %s" % (before, after))
        else:
            findings.bad(
                "actuate.%s" % action,
                "ExpandCollapseState reads %r -> %r, expected %r -> %r"
                % (before, after, want_before, want_after),
            )


def check_foreground(phases, expectation, findings):
    """What the actuation costs, measured in both directions rather than hoped for.

    `probe-expectation.json` predicted that opening the overflow would give up the
    never-activated guarantee. IT WAS RIGHT, and this is where that stopped being a prediction:
    measured on LUKESFF 2026-09-02, the probe did not own the foreground at any of the three
    baseline samples and owned it at all six effect and silence samples. So
    `ExpandCollapsePattern.Expand` on a WinUI CommandBar activates the window, and collapsing it
    again does not hand the foreground back.

    That is a cost of this lane, not a requirement of the surface, so it is not asserted as one.
    What IS asserted is the pair:

      · BASELINE must be clean. Nothing has been actuated yet, so a probe already holding the
        foreground there means the harness activated it on its own and every reading after it is
        of a different condition from the one claimed. This is the arm that can still say no.
      · EFFECT and SILENCE must match the manifest's DECLARED `activationCost`, in both
        directions. Declaring `target-takes-foreground` and measuring a probe that stayed back
        fails just as loudly as the reverse: the day WinUI stops activating, this arm reddens and
        the row has to move, rather than the lane quietly acquiring a guarantee nobody checked.
    """
    declared = (expectation.get("overflow") or {}).get("activationCost")
    if declared not in ("target-takes-foreground", "target-stays-back"):
        findings.bad(
            "manifest.activationCost",
            "the expectation declares %r; this arm compares the measured foreground against a "
            "declared value and cannot run without one" % (declared,),
        )
        return

    for phase, data in phases.items():
        for view in ("control", "raw"):
            dump = data[view]
            target = (dump.get("targets") or [{}])[0]
            samples = dump.get("foregroundSamples") or []
            check = "foreground.%s.%s" % (phase, view)

            if len(samples) < 3:
                findings.bad(
                    check + ".sampleCount",
                    "%d foreground samples; the walk must be bracketed before, during and after, "
                    "or the claim covers only the instant it was taken" % len(samples),
                )
                continue

            offenders = [s for s in samples
                         if s.get("hwnd") == target.get("hwnd")
                         or s.get("processId") == target.get("processId")]
            held = len(offenders) > 0

            if phase == "baseline":
                if held:
                    findings.bad(
                        check + ".targetNeverFront",
                        "the probe held the foreground at %s, BEFORE anything was actuated. The "
                        "harness activated the surface on its own, so every reading after this "
                        "one is of a different condition from the one claimed"
                        % ", ".join(str(o.get("when")) for o in offenders),
                    )
                else:
                    findings.ok(
                        check + ".targetNeverFront",
                        "hwnd %s / pid %s held the foreground at none of the %d samples, with "
                        "nothing yet actuated"
                        % (target.get("hwnd"), target.get("processId"), len(samples)),
                    )
                continue

            expected_held = declared == "target-takes-foreground"
            if held == expected_held:
                findings.ok(
                    check + ".activationCost",
                    "declared %s and measured the same: the probe held the foreground at %d of "
                    "%d samples" % (declared, len(offenders), len(samples)),
                )
            elif held:
                findings.bad(
                    check + ".activationCost",
                    "the manifest declares %s and the probe held the foreground at %s. Opening "
                    "the overflow activates the surface it is measuring and the manifest does "
                    "not say so" % (declared, ", ".join(str(o.get("when")) for o in offenders)),
                )
            else:
                findings.bad(
                    check + ".activationCost",
                    "the manifest declares %s and the probe held the foreground at none of the "
                    "%d samples. The declared cost is stale: this lane no longer gives up the "
                    "never-activated guarantee, and the row must move rather than sit here "
                    "passing for free" % (declared, len(samples)),
                )


def check_commands(phases, commands, findings):
    for want in commands:
        aid = want["automationId"]

        for phase in PHASES:
            data = phases[phase]
            in_control = aid in data["controlIndex"]
            in_raw = aid in data["rawIndex"]

            if phase != PRESENT_IN:
                # BASELINE and SILENCE. These are the readings that can say no.
                if not in_control and not in_raw:
                    findings.ok(
                        "%s.absent.%s" % (phase, aid),
                        "absent from the control view and the raw view, so it is not realised "
                        "at all while the overflow is shut",
                    )
                else:
                    where = " and ".join(
                        [w for w, hit in (("control view", in_control), ("raw view", in_raw)) if hit])
                    findings.bad(
                        "%s.absent.%s" % (phase, aid),
                        "present in the %s with the overflow shut. The at-rest lane asserts this "
                        "control is unrealised there, so either that assertion or this one is "
                        "measuring the wrong tree" % where,
                    )
                continue

            # EFFECT.
            matches = data["controlIndex"].get(aid, [])
            if not matches:
                findings.bad(
                    "effect.present.%s" % aid,
                    "the overflow was opened through ExpandCollapsePattern and the control view "
                    "still carries no element with this AutomationId; the command is not "
                    "addressable even with the overflow realised",
                )
                continue

            # MORE THAN ONE MATCH IS NOT AUTOMATICALLY A DUPLICATE CONTROL, and the first version
            # of this file said it was. Measured on LUKESFF 2026-09-02: with the overflow open,
            # WinUI publishes the OverflowPopup subtree TWICE under the probe's one top-level
            # window - once through a `Microsoft.UI.Content.PopupWindowSiteBridge` ("PopupHost")
            # child, and once in place beneath the ApplicationBar - so each command is reachable
            # at two paths. Both copies carried identical name, controlType, className, isEnabled,
            # isOffscreen, accessKey, pattern list AND bounding rectangle, which is what makes it
            # one control on two routes rather than two controls sharing an id.
            #
            # So the assertion is the one that can tell those apart: several matches are permitted
            # only while they agree on everything a caller would act on. Two genuinely different
            # controls under one id still fails, which is the case the original check was for.
            SAME = ("name", "controlType", "className", "isEnabled", "isOffscreen",
                    "boundingRectangle", "accessKey")
            if len(matches) > 1:
                differ = [k for k in SAME
                          if len({json.dumps(m.get(k), sort_keys=True) for m in matches}) > 1]
                paths = ", ".join(str(m.get("path")) for m in matches)
                if differ:
                    findings.bad(
                        "effect.present.%s" % aid,
                        "%d elements carry this AutomationId at %s and they disagree on %s; an id "
                        "that names more than one distinct control does not address either of them"
                        % (len(matches), paths, ", ".join(differ)),
                    )
                    continue
                findings.ok(
                    "effect.oneControlTwoRoutes.%s" % aid,
                    "%d elements at %s, agreeing on every property a caller would act on "
                    "(%s) - WinUI's popup site-bridge publishing one control on two tree routes"
                    % (len(matches), paths, ", ".join(SAME)),
                )

            element = matches[0]
            findings.ok("effect.present.%s" % aid, "one control, at path %s" % element.get("path"))

            expected_name = want.get("name")
            if expected_name is not None:
                actual = element.get("name")
                if actual == expected_name:
                    findings.ok("effect.vocabulary.%s" % aid, "name == %r" % actual)
                else:
                    findings.bad(
                        "effect.vocabulary.%s" % aid,
                        "the plane publishes %r where the on-screen vocabulary is %r"
                        % (actual, expected_name),
                    )

            expected_type = want.get("controlType")
            if expected_type is not None:
                actual = element.get("controlType")
                if actual == expected_type:
                    findings.ok("effect.controlType.%s" % aid, "controlType == %s" % actual)
                else:
                    findings.bad(
                        "effect.controlType.%s" % aid,
                        "expected ControlType %s, the plane publishes %s"
                        % (expected_type, actual),
                    )

            if want.get("mustBeEnabled"):
                if element.get("isEnabled"):
                    findings.ok("effect.isEnabled.%s" % aid, "isEnabled == True")
                else:
                    findings.bad(
                        "effect.isEnabled.%s" % aid,
                        "the command is realised but disabled; a command nobody can run is not "
                        "the affordance the surface enumerates",
                    )

            if want.get("mustNotBeOffscreen"):
                if element.get("isOffscreen"):
                    findings.bad(
                        "effect.onscreen.%s" % aid,
                        "the element reports isOffscreen; published but not shown is not the "
                        "state being claimed",
                    )
                else:
                    findings.ok("effect.onscreen.%s" % aid, "isOffscreen == False")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, help="the lane's artifact directory")
    parser.add_argument("--expectation", required=True)
    parser.add_argument("--report", default=None)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)

    expectation = load_json(args.expectation)

    phases = {}
    for phase in PHASES:
        data, why = read_phase(args.out, phase)
        if data is None:
            print("NO VERDICT: %s. Nothing is graded from a partial set of readings — a run "
                  "carrying only the effect has no reading that could have said no." % why)
            return EXIT_NO_VERDICT
        phases[phase] = data

    findings = Findings()
    commands = check_floor(expectation, findings)
    check_actuation(args.out, findings)
    check_foreground(phases, expectation, findings)
    check_commands(phases, commands, findings)

    report = {
        "schema": "surf029.overflow-assert/1",
        "surface": (expectation.get("overflow") or {}).get("surfaceId"),
        "subject": expectation.get("subject"),
        "subjectIsNotTheProduct": expectation.get("subjectIsNotTheProduct"),
        "out": os.path.abspath(args.out),
        "phases": {p: {"elementCount": phases[p]["control"].get("elementCount"),
                       "capturedAtUtc": phases[p]["control"].get("capturedAtUtc")}
                   for p in PHASES},
        "passed": findings.passed,
        "failed": findings.failed,
    }

    if args.report:
        report_dir = os.path.dirname(os.path.abspath(args.report))
        if report_dir and not os.path.isdir(report_dir):
            os.makedirs(report_dir)
        with open(args.report, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=2, ensure_ascii=False)
            handle.write("\n")

    if not args.quiet:
        print("SURF-029 overflow assertions against %s"
              % ((expectation.get("overflow") or {}).get("surfaceId")))
        print("  subject: %s" % expectation.get("subject"))
        for phase in PHASES:
            print("  %-9s %d elements, captured %s"
                  % (phase, phases[phase]["control"].get("elementCount"),
                     phases[phase]["control"].get("capturedAtUtc")))
        print("")
        print("  passed  %d" % len(findings.passed))
        print("  FAILED  %d" % len(findings.failed))
        for row in findings.failed:
            print("    FAIL  %s: %s" % (row["check"], row["detail"]))

    return EXIT_FAIL if findings.failed else EXIT_PASS


if __name__ == "__main__":
    sys.exit(main())
