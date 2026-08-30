#!/usr/bin/env python3
"""WIN20 — grade a UIA dump against what the surface said it would publish.

## What this gate is for

The campaign stands every case on a rung of oracle. On macOS the rungs above `touch` are reached
through the accessibility plane; on Windows the channel is UI Automation. This file is the part
that turns a tree into a verdict, and the whole of its design is about one distinction the
repository already pays attention to everywhere else:

    a control that is ABSENT from the automation plane is not a failing control.
    It is an UNORACLED one, and it must be reported with the reason rather than passed quietly.

`planning/evidence/M34-oracle-lane.md` is the precedent. A menu badge that AppKit folds into the
title is recorded `unoracled` with the three conditions that would open a rung, not marked `n/a`.
This gate does the same thing for a Windows surface.

## The three outcomes, and why the third exists

    exit 0   every assertion that could run, ran and passed
    exit 1   an assertion ran and FAILED
    exit 3   NO VERDICT — nothing was measured

Exit 3 is the one that matters. A dump that does not exist, a dump with no target window, and a
dump taken while the probe was dead all produce an empty tree, and an empty tree trivially
satisfies "no control published a wrong name". A gate that returned 0 there would be reporting a
green tick for a measurement that never happened.

## The two-way rule on the unoracled list

An `unoracled` row asserts an ABSENCE, and a check that asserts an absence passes for free the day
it stops being able to fire. So a declared-unoracled control that TURNS UP in the dump fails this
gate. The list is a record of what could not be measured, not a place to put things that are
inconvenient to measure: the day one becomes addressable, the row has to move.

Usage:
    python scripts/windows/uia/uia-assert.py --dump <dump.json> --expectation <expectation.json>
                                             [--raw-dump <raw.json>] [--report <report.json>]
"""

import argparse
import json
import os
import sys


EXIT_PASS = 0
EXIT_FAIL = 1
EXIT_NO_VERDICT = 3


def load_json(path):
    """Read a JSON file that PowerShell may have written with a UTF-8 BOM."""
    with open(path, "r", encoding="utf-8-sig") as handle:
        return json.load(handle)


class Findings(object):
    """Three lists, kept apart on purpose. Merging them is the defect this whole file avoids."""

    def __init__(self):
        self.passed = []
        self.failed = []
        self.unoracled = []

    def ok(self, check, detail):
        self.passed.append({"check": check, "detail": detail})

    def bad(self, check, detail):
        self.failed.append({"check": check, "detail": detail})

    def no_oracle(self, check, detail, reason, opens_rung):
        self.unoracled.append(
            {"check": check, "detail": detail, "reason": reason, "whatWouldOpenARung": opens_rung}
        )


def index_by_automation_id(elements):
    """Map automationId -> list of elements. A duplicate id is itself a finding: two controls with
    one id are not individually addressable, which is the acceptance clause this gate exists for."""
    index = {}
    for element in elements:
        key = element.get("automationId") or ""
        if not key:
            continue
        index.setdefault(key, []).append(element)
    return index


def check_window(dump, expectation, findings):
    """The window facts. A minimised window still publishes a tree, and that tree is a WEAKER
    measurement than a mapped one — so 'not minimised' is asserted rather than assumed."""
    want = expectation.get("window", {})
    targets = dump.get("targets") or []

    if not targets:
        return None

    target = targets[0]

    pairs = [
        ("nameEquals", "name"),
        ("classNameEquals", "className"),
        ("frameworkIdEquals", "frameworkId"),
    ]
    for want_key, got_key in pairs:
        if want_key not in want:
            continue
        expected = want[want_key]
        actual = target.get(got_key)
        if actual == expected:
            findings.ok("window." + got_key, "%s == %r" % (got_key, actual))
        else:
            findings.bad(
                "window." + got_key,
                "expected %r, the dump carries %r" % (expected, actual),
            )

    if want.get("mustBeVisible"):
        if target.get("isVisible"):
            findings.ok("window.isVisible", "the window is mapped")
        else:
            findings.bad(
                "window.isVisible",
                "the window is not visible; a tree read off an unmapped window is a different "
                "and weaker measurement than the one this manifest describes",
            )

    if want.get("mustNotBeMinimised"):
        if target.get("isMinimised"):
            findings.bad(
                "window.isMinimised",
                "the window is minimised; WinUI collapses layout for a minimised window, so "
                "geometry and realisation read here would not be the ones a user gets",
            )
        else:
            findings.ok("window.isMinimised", "the window is not minimised")

    return target


def check_never_foregrounded(dump, target, findings):
    """WIN20's acceptance: enumerate 'without activating or foregrounding the window'.

    The invariant asserted is that the TARGET never held the foreground — not that the foreground
    never changed. `planning/evidence/M34-oracle-lane.md` records the cost of getting that wrong:
    a check that failed because frontmost went from Chrome to ghostty, neither of them the app
    under test.
    """
    samples = dump.get("foregroundSamples") or []

    if len(samples) < 3:
        findings.bad(
            "foreground.sampleCount",
            "%d foreground samples; the walk must be bracketed before, during and after, or the "
            "claim covers only the instant it was taken" % len(samples),
        )
        return

    whens = set(sample.get("when") for sample in samples)
    for required in ("before", "midwalk", "after"):
        if required not in whens:
            findings.bad("foreground.sampleCount", "no %r sample in the dump" % required)
            return

    target_hwnd = target.get("hwnd")
    target_pid = target.get("processId")
    offenders = []
    for sample in samples:
        if sample.get("hwnd") == target_hwnd or sample.get("processId") == target_pid:
            offenders.append(sample)

    if offenders:
        findings.bad(
            "foreground.targetNeverFront",
            "the target held the foreground at %s — the walk activated the surface it was "
            "measuring" % ", ".join(str(o.get("when")) for o in offenders),
        )
    else:
        findings.ok(
            "foreground.targetNeverFront",
            "target hwnd %s / pid %s held the foreground at none of the %d samples"
            % (target_hwnd, target_pid, len(samples)),
        )


def check_addressability(index, expectation, findings):
    for want in expectation.get("controls", []):
        aid = want["automationId"]
        matches = index.get(aid, [])

        if not matches:
            findings.bad(
                "addressable." + aid,
                "no element carries this AutomationId; the control is not individually "
                "addressable on this surface",
            )
            continue

        if len(matches) > 1:
            findings.bad(
                "addressable." + aid,
                "%d elements carry this AutomationId; an id that names more than one control "
                "does not address either of them" % len(matches),
            )
            continue

        element = matches[0]
        findings.ok("addressable." + aid, "one element, at path %s" % element.get("path"))

        expected_name = want.get("name")
        actual_name = element.get("name")
        if expected_name is not None:
            if actual_name == expected_name:
                findings.ok("vocabulary." + aid, "name == %r" % actual_name)
            else:
                findings.bad(
                    "vocabulary." + aid,
                    "the plane publishes %r where the on-screen vocabulary is %r"
                    % (actual_name, expected_name),
                )

        expected_type = want.get("controlType")
        actual_type = element.get("controlType")
        if expected_type is not None:
            if actual_type == expected_type:
                findings.ok("controlType." + aid, "controlType == %s" % actual_type)
            else:
                findings.bad(
                    "controlType." + aid,
                    "expected ControlType %s, the plane publishes %s"
                    % (expected_type, actual_type),
                )


def check_disabled(index, expectation, findings):
    for want in expectation.get("states", {}).get("disabled", []):
        aid = want["automationId"]
        matches = index.get(aid, [])
        if not matches:
            findings.bad("state.disabled." + aid, "the control is not on the plane at all")
            continue
        actual = bool(matches[0].get("isEnabled"))
        expected = bool(want["isEnabled"])
        if actual == expected:
            findings.ok("state.disabled." + aid, "isEnabled == %s, off the plane" % actual)
        else:
            findings.bad(
                "state.disabled." + aid,
                "isEnabled reads %s, the surface declares %s" % (actual, expected),
            )


def check_selected(index, expectation, findings):
    for want in expectation.get("states", {}).get("selected", []):
        container_id = want["container"]
        containers = index.get(container_id, [])
        if not containers:
            findings.bad(
                "state.selected." + container_id,
                "the selection container is not on the plane",
            )
            continue

        state = containers[0].get("patternState") or {}
        selection = state.get("selection")
        if selection is None:
            findings.bad(
                "state.selected." + container_id,
                "the container publishes no SelectionPattern, so which item is selected cannot "
                "be read from the container",
            )
        else:
            if isinstance(selection, str):
                selection = [selection]
            expected_names = want.get("selectionNames", [])
            if list(selection) == list(expected_names):
                findings.ok(
                    "state.selected." + container_id,
                    "SelectionPattern reports %s" % json.dumps(list(selection)),
                )
            else:
                findings.bad(
                    "state.selected." + container_id,
                    "SelectionPattern reports %s, expected %s"
                    % (json.dumps(list(selection)), json.dumps(expected_names)),
                )

        selected_id = want["selectedAutomationId"]
        selected = index.get(selected_id, [])
        if not selected:
            findings.bad("state.selected." + selected_id, "the selected item is not on the plane")
        else:
            is_selected = (selected[0].get("patternState") or {}).get("isSelected")
            if is_selected is True:
                findings.ok("state.selected." + selected_id, "isSelected == True")
            else:
                findings.bad(
                    "state.selected." + selected_id,
                    "SelectionItemPattern.isSelected reads %r" % (is_selected,),
                )

        for other_id in want.get("unselected", []):
            others = index.get(other_id, [])
            if not others:
                findings.bad("state.unselected." + other_id, "the item is not on the plane")
                continue
            is_selected = (others[0].get("patternState") or {}).get("isSelected")
            if is_selected is False:
                findings.ok("state.unselected." + other_id, "isSelected == False")
            else:
                findings.bad(
                    "state.unselected." + other_id,
                    "isSelected reads %r on an item the surface does not have selected; a plane "
                    "that reports two selected items in a single-selection list is reporting a "
                    "state the surface cannot be in" % (is_selected,),
                )


def check_held(index, expectation, findings):
    for want in expectation.get("states", {}).get("held", []):
        aid = want["automationId"]
        matches = index.get(aid, [])
        if not matches:
            findings.bad("state.held." + aid, "the control is not on the plane")
            continue
        actual = (matches[0].get("patternState") or {}).get("toggleState")
        expected = want["toggleState"]
        if actual == expected:
            findings.ok("state.held." + aid, "TogglePattern.ToggleState == %s" % actual)
        elif actual is None:
            findings.bad(
                "state.held." + aid,
                "the control publishes no TogglePattern, so whether it is held cannot be read "
                "from the plane at all",
            )
        else:
            findings.bad(
                "state.held." + aid,
                "ToggleState reads %r, expected %r" % (actual, expected),
            )


def check_busy(index, expectation, findings):
    for want in expectation.get("states", {}).get("busy", []):
        aid = want["automationId"]
        matches = index.get(aid, [])
        if not matches:
            findings.bad("state.busy." + aid, "the busy indicator is not on the plane")
            continue

        element = matches[0]
        name = element.get("name") or ""

        expected_type = want.get("controlType")
        if expected_type and element.get("controlType") != expected_type:
            findings.bad(
                "state.busy." + aid,
                "expected ControlType %s, the plane publishes %s"
                % (expected_type, element.get("controlType")),
            )

        needle = want.get("nameContains")
        if needle and needle not in name:
            findings.bad(
                "state.busy." + aid,
                "the accompanying word %r is not in the published name %r" % (needle, name),
            )

        marker = want.get("busyMarkerInName")
        if marker:
            if marker in name:
                findings.ok(
                    "state.busy." + aid,
                    "the plane carries the busy marker in the name: %r" % name,
                )
            else:
                findings.bad(
                    "state.busy." + aid,
                    "the name %r carries no %r marker, so the busy state is not readable from "
                    "the plane and would have to be inferred from pixels" % (name, marker),
                )

        if want.get("mustNotBeOffscreen"):
            if element.get("isOffscreen"):
                findings.bad(
                    "state.busy." + aid,
                    "the element reports isOffscreen; an offscreen indicator is published but "
                    "not shown, which is not the state being claimed",
                )
            else:
                findings.ok("state.busy." + aid + ".onscreen", "isOffscreen == False")


def check_unoracled(index, raw_index, expectation, findings):
    """Each row asserts an absence — and is FAILED if the thing turns up.

    An absence-assertion that cannot fire is indistinguishable from one that correctly did not,
    so this direction is what keeps the list honest rather than convenient.
    """
    for row in expectation.get("unoracled", []):
        aid = row["automationId"]
        in_control = aid in index
        in_raw = raw_index is not None and aid in raw_index

        if in_control or in_raw:
            where = []
            if in_control:
                where.append("control view")
            if in_raw:
                where.append("raw view")
            findings.bad(
                "unoracled." + aid,
                "declared unmeasurable, but the element is present in the %s. The declaration is "
                "stale: this control now has an oracle and the row must move out of the "
                "unoracled list rather than sit there passing for free" % " and ".join(where),
            )
            continue

        detail = "%r is absent from the control view" % row.get("onScreenName", aid)
        if raw_index is not None:
            detail += " and from the raw view, so it is not realised at all"
        else:
            detail += "; no raw-view dump was supplied, so 'hidden' and 'not realised' are not "
            detail += "separated here"

        findings.no_oracle(
            "unoracled." + aid,
            detail,
            row.get("reason", ""),
            row.get("whatWouldOpenARung", ""),
        )


def check_manifest_is_not_vacuous(expectation, findings):
    """The expectation manifest is the oracle, and an empty oracle grades everything as correct.

    Every check below iterates a list out of the manifest, so a manifest that declares nothing
    produces zero failures and exit 0 — a green tick meaning "nothing was asked". That is the same
    shape as the empty-tree hole one file along, arriving from the other side, and it is the one an
    editor could open by accident while trimming a row.

    So the manifest declares its own floor in `minimums`, and the floor is asserted before anything
    is graded against it.
    """
    minimums = expectation.get("minimums") or {}

    counts = {
        "controls": len(expectation.get("controls") or []),
        "disabled": len(expectation.get("states", {}).get("disabled") or []),
        "selected": len(expectation.get("states", {}).get("selected") or []),
        "held": len(expectation.get("states", {}).get("held") or []),
        "busy": len(expectation.get("states", {}).get("busy") or []),
    }

    if not minimums:
        findings.bad(
            "manifest.minimums",
            "the expectation declares no `minimums`, so it cannot be told from an emptied one. "
            "An oracle that asks nothing grades everything as correct",
        )
        return

    for key, floor in sorted(minimums.items()):
        actual = counts.get(key)
        if actual is None:
            findings.bad("manifest.minimums", "unknown minimum %r" % key)
        elif actual < floor:
            findings.bad(
                "manifest.minimums." + key,
                "the manifest declares %d %s and its own floor is %d; it has been trimmed below "
                "what it promises to check" % (actual, key, floor),
            )
        else:
            findings.ok("manifest.minimums." + key, "%d %s, floor %d" % (actual, key, floor))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dump", required=True, help="control-view dump from uia-dump.ps1")
    parser.add_argument("--raw-dump", default=None, help="optional raw-view dump")
    parser.add_argument("--expectation", required=True)
    parser.add_argument("--report", default=None, help="write the graded findings here as JSON")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)

    if not os.path.exists(args.dump):
        print("NO VERDICT: no dump at %s. Nothing was measured." % args.dump)
        return EXIT_NO_VERDICT

    dump = load_json(args.dump)
    expectation = load_json(args.expectation)

    elements = dump.get("elements") or []
    targets = dump.get("targets") or []

    if not targets or not elements:
        print(
            "NO VERDICT: the dump holds %d target window(s) and %d elements. An empty tree "
            "satisfies every assertion below for free, so this is recorded as measuring nothing "
            "rather than as a pass." % (len(targets), len(elements))
        )
        return EXIT_NO_VERDICT

    if dump.get("truncated"):
        print(
            "NO VERDICT: the walk hit its depth or element guard and the tree is incomplete. A "
            "missing control cannot be told from a truncated one."
        )
        return EXIT_NO_VERDICT

    raw_index = None
    if args.raw_dump and os.path.exists(args.raw_dump):
        raw_index = index_by_automation_id(load_json(args.raw_dump).get("elements") or [])

    findings = Findings()
    index = index_by_automation_id(elements)

    target = check_window(dump, expectation, findings)
    if target is not None:
        check_never_foregrounded(dump, target, findings)
    check_manifest_is_not_vacuous(expectation, findings)
    check_addressability(index, expectation, findings)
    check_disabled(index, expectation, findings)
    check_selected(index, expectation, findings)
    check_held(index, expectation, findings)
    check_busy(index, expectation, findings)
    check_unoracled(index, raw_index, expectation, findings)

    report = {
        "schema": "win20.assert/1",
        "subject": expectation.get("subject"),
        "subjectIsNotTheProduct": expectation.get("subjectIsNotTheProduct"),
        "proposedSurfaceId": expectation.get("proposedSurfaceId"),
        "dump": os.path.abspath(args.dump),
        "rawDump": os.path.abspath(args.raw_dump) if args.raw_dump else None,
        "capturedAtUtc": dump.get("capturedAtUtc"),
        "elementCount": dump.get("elementCount"),
        "passed": findings.passed,
        "failed": findings.failed,
        "unoracled": findings.unoracled,
    }

    if args.report:
        report_dir = os.path.dirname(os.path.abspath(args.report))
        if report_dir and not os.path.isdir(report_dir):
            os.makedirs(report_dir)
        with open(args.report, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=2, ensure_ascii=False)
            handle.write("\n")

    if not args.quiet:
        print("WIN20 automation-plane assertions against %s" % expectation.get("proposedSurfaceId"))
        print("  subject: %s" % expectation.get("subject"))
        print("  dump:    %s (%d elements)" % (args.dump, len(elements)))
        print("")
        print("  passed    %d" % len(findings.passed))
        print("  FAILED    %d" % len(findings.failed))
        print("  unoracled %d  (neither pass nor failure)" % len(findings.unoracled))
        for row in findings.failed:
            print("    FAIL  %s: %s" % (row["check"], row["detail"]))
        for row in findings.unoracled:
            print("    UNORACLED  %s: %s" % (row["check"], row["detail"]))
            print("               reason: %s" % row["reason"])
            print("               a rung opens if: %s" % row["whatWouldOpenARung"])

    return EXIT_FAIL if findings.failed else EXIT_PASS


if __name__ == "__main__":
    sys.exit(main())
