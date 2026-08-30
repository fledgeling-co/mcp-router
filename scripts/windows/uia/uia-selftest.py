#!/usr/bin/env python3
"""WIN20 — arm every assertion in uia-assert.py, both directions.

## Why this file exists at all

Most of what `uia-assert.py` checks is an ABSENCE or a NEGATIVE: the target never held the
foreground, no declared-unoracled control turned up, no unselected item reports itself selected.
A check that asserts an absence passes for free the moment it stops being able to fire, and from
outside, "correctly did not fire" and "could not fire" are the same silence.

`planning/evidence/M34-oracle-lane.md` records what that costs when it is left unarmed: an `awk`
rule whose `exit 0` was overridden by its own `END { exit 1 }`, so the tripwire watching for the
one event the lane existed to notice could never fire — and it passed every real run.

So each assertion here is handed a doctored dump and REQUIRED to fire, and then the real dump is
required to fire none of them. The second half is the control: a suite where every arm fires is
just as uninformative as one where none do.

## The three outcome classes are armed separately

`uia-assert.py` reserves exit 3 for "measured nothing", and the arms that must produce it — an
empty tree, a truncated walk, a dump that is not there — are the ones that keep a green tick from
being spent on a window that never existed. They are armed as 3, not as 1.

Usage:
    python scripts/windows/uia/uia-selftest.py --dump <real-dump.json>
                                               [--expectation <expectation.json>]

    exit 0  every arm behaved as required
    exit 1  an arm did not fire, or the real dump tripped something
    exit 3  NO VERDICT — no real dump to arm against
"""

import argparse
import copy
import importlib.util
import json
import os
import sys
import tempfile


HERE = os.path.dirname(os.path.abspath(__file__))

EXIT_PASS = 0
EXIT_FAIL = 1
EXIT_NO_VERDICT = 3


def load_assert_module():
    """uia-assert.py has a dash in its name, so it cannot be imported by name."""
    path = os.path.join(HERE, "uia-assert.py")
    spec = importlib.util.spec_from_file_location("uia_assert", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def find(dump, automation_id):
    for element in dump["elements"]:
        if element.get("automationId") == automation_id:
            return element
    raise KeyError(
        "the real dump has no element with AutomationId %r, so the arm that depends on it cannot "
        "be built. That is a change in the subject, not a pass." % automation_id
    )


# --------------------------------------------------------------------------- the arms
# Each arm is (name, expected exit code, mutate(dump, expectation)).
# A mutation returns nothing; it edits the deep copies it is handed.


def arm_rename_control(dump, _expectation):
    find(dump, "probe.destination.servers")["name"] = "Servers "


def arm_remove_control(dump, _expectation):
    dump["elements"] = [
        e for e in dump["elements"] if e.get("automationId") != "probe.command.refresh"
    ]


def arm_duplicate_id(dump, _expectation):
    twin = copy.deepcopy(find(dump, "probe.button.pairServer"))
    twin["path"] = twin["path"] + "/twin"
    dump["elements"].append(twin)


def arm_wrong_control_type(dump, _expectation):
    find(dump, "probe.serverList")["controlType"] = "Table"


def arm_disabled_becomes_enabled(dump, _expectation):
    find(dump, "probe.button.removeServer")["isEnabled"] = True


def arm_selected_item_unselects(dump, _expectation):
    find(dump, "probe.destination.servers")["patternState"]["isSelected"] = False


def arm_second_item_also_selected(dump, _expectation):
    find(dump, "probe.destination.inbox")["patternState"]["isSelected"] = True


def arm_container_selection_wrong(dump, _expectation):
    find(dump, "probe.navigation")["patternState"]["selection"] = ["Inbox"]


def arm_container_publishes_no_selection(dump, _expectation):
    find(dump, "probe.serverList")["patternState"] = {}


def arm_held_becomes_off(dump, _expectation):
    find(dump, "probe.command.holdQueue")["patternState"]["toggleState"] = "Off"


def arm_toggle_pattern_disappears(dump, _expectation):
    element = find(dump, "probe.switch.pauseRouting")
    element["patternState"] = {}
    element["patterns"] = []


def arm_busy_marker_stripped(dump, _expectation):
    element = find(dump, "probe.status.busyRing")
    element["name"] = element["name"].replace("Busy", "").strip()


def arm_busy_offscreen(dump, _expectation):
    find(dump, "probe.status.busyRing")["isOffscreen"] = True


def arm_target_took_the_foreground(dump, _expectation):
    target = dump["targets"][0]
    for sample in dump["foregroundSamples"]:
        if sample.get("when") == "midwalk":
            sample["hwnd"] = target["hwnd"]
            sample["processId"] = target["processId"]


def arm_midwalk_sample_missing(dump, _expectation):
    dump["foregroundSamples"] = [
        s for s in dump["foregroundSamples"] if s.get("when") != "midwalk"
    ]


def arm_window_minimised(dump, _expectation):
    dump["targets"][0]["isMinimised"] = True


def arm_window_renamed(dump, _expectation):
    dump["targets"][0]["name"] = "Some other window"


def arm_unoracled_control_turns_up(dump, expectation):
    """The two-way rule. A declared-unmeasurable control that appears must FAIL, not pass quietly:
    the day it becomes addressable the row has to move out of the unoracled list."""
    template = copy.deepcopy(find(dump, "probe.command.refresh"))
    template["automationId"] = expectation["unoracled"][0]["automationId"]
    template["name"] = expectation["unoracled"][0]["onScreenName"]
    template["path"] = template["path"] + "/appeared"
    dump["elements"].append(template)


def arm_manifest_emptied(_dump, expectation):
    """The oracle's own side of the empty-tree hole. Every check iterates a list out of the
    manifest, so an emptied manifest grades everything as correct and exits 0."""
    expectation["controls"] = []
    expectation["states"] = {}


def arm_manifest_declares_no_floor(_dump, expectation):
    """Without `minimums` the emptied manifest above cannot be told from a real one."""
    expectation.pop("minimums", None)


def arm_empty_tree(dump, _expectation):
    dump["elements"] = []
    dump["elementCount"] = 0


def arm_no_target_window(dump, _expectation):
    dump["targets"] = []


def arm_truncated_walk(dump, _expectation):
    dump["truncated"] = True


ARMS = [
    ("a destination's published name drifts from the on-screen word", EXIT_FAIL, arm_rename_control),
    ("a command is missing from the tree", EXIT_FAIL, arm_remove_control),
    ("two controls carry one AutomationId", EXIT_FAIL, arm_duplicate_id),
    ("a list is published as the wrong ControlType", EXIT_FAIL, arm_wrong_control_type),
    ("a disabled control reports itself enabled", EXIT_FAIL, arm_disabled_becomes_enabled),
    ("the selected destination reports itself unselected", EXIT_FAIL, arm_selected_item_unselects),
    ("a second item in a single-selection list reports selected", EXIT_FAIL, arm_second_item_also_selected),
    ("the container names a different selection", EXIT_FAIL, arm_container_selection_wrong),
    ("the container publishes no SelectionPattern at all", EXIT_FAIL, arm_container_publishes_no_selection),
    ("a held toggle reports Off", EXIT_FAIL, arm_held_becomes_off),
    ("a toggle stops publishing TogglePattern", EXIT_FAIL, arm_toggle_pattern_disappears),
    ("the busy marker vanishes from the name", EXIT_FAIL, arm_busy_marker_stripped),
    ("the busy indicator is published but offscreen", EXIT_FAIL, arm_busy_offscreen),
    ("the target held the foreground mid-walk", EXIT_FAIL, arm_target_took_the_foreground),
    ("the walk was not bracketed by a midwalk sample", EXIT_FAIL, arm_midwalk_sample_missing),
    ("the window was minimised while it was read", EXIT_FAIL, arm_window_minimised),
    ("the tree came from a different window", EXIT_FAIL, arm_window_renamed),
    ("a declared-unoracled control turns up on the plane", EXIT_FAIL, arm_unoracled_control_turns_up),
    ("the expectation manifest is emptied", EXIT_FAIL, arm_manifest_emptied),
    ("the manifest declares no floor of its own", EXIT_FAIL, arm_manifest_declares_no_floor),
    ("the tree is empty", EXIT_NO_VERDICT, arm_empty_tree),
    ("no target window was found", EXIT_NO_VERDICT, arm_no_target_window),
    ("the walk hit its guard and truncated", EXIT_NO_VERDICT, arm_truncated_walk),
]


def run_case(module, dump, expectation, workdir, tag):
    dump_path = os.path.join(workdir, "dump-%s.json" % tag)
    exp_path = os.path.join(workdir, "exp-%s.json" % tag)
    with open(dump_path, "w", encoding="utf-8") as handle:
        json.dump(dump, handle)
    with open(exp_path, "w", encoding="utf-8") as handle:
        json.dump(expectation, handle)
    return module.main(
        ["--dump", dump_path, "--expectation", exp_path, "--quiet"]
    )


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dump", required=True, help="a REAL dump from a live probe run")
    parser.add_argument(
        "--expectation", default=os.path.join(HERE, "probe-expectation.json")
    )
    args = parser.parse_args(argv)

    if not os.path.exists(args.dump):
        print(
            "NO VERDICT: no real dump at %s. This suite arms assertions against a real tree; "
            "without one it would be testing its own fixtures." % args.dump
        )
        return EXIT_NO_VERDICT

    module = load_assert_module()
    real_dump = module.load_json(args.dump)
    real_expectation = module.load_json(args.expectation)

    if not (real_dump.get("elements") and real_dump.get("targets")):
        print("NO VERDICT: the supplied dump is empty; there is nothing to arm against.")
        return EXIT_NO_VERDICT

    rows = []
    failures = 0

    workdir = tempfile.mkdtemp(prefix="win20-selftest-")

    # ---- the control, taken FIRST. An arming suite whose subject already fails is measuring the
    # subject, not the assertions.
    control_exit = run_case(module, copy.deepcopy(real_dump), copy.deepcopy(real_expectation),
                            workdir, "control")
    if control_exit == EXIT_PASS:
        rows.append(("the real dump, unmodified", "silent", "required silent", True))
    else:
        rows.append(("the real dump, unmodified", "exit %d" % control_exit, "required silent", False))
        failures += 1

    # ---- the missing-file arm, which cannot be expressed as a dump mutation
    missing = os.path.join(workdir, "does-not-exist.json")
    missing_exit = module.main(
        ["--dump", missing, "--expectation", args.expectation, "--quiet"]
    )
    ok = missing_exit == EXIT_NO_VERDICT
    rows.append(("the dump file is not there", "exit %d" % missing_exit, "required exit 3", ok))
    if not ok:
        failures += 1

    # ---- every mutation arm
    for index, (name, want_exit, mutate) in enumerate(ARMS):
        dump = copy.deepcopy(real_dump)
        expectation = copy.deepcopy(real_expectation)
        try:
            mutate(dump, expectation)
        except KeyError as error:
            rows.append((name, "could not build the arm: %s" % error, "required exit %d" % want_exit, False))
            failures += 1
            continue

        got = run_case(module, dump, expectation, workdir, "arm%02d" % index)
        ok = got == want_exit
        rows.append((name, "exit %d" % got, "required exit %d" % want_exit, ok))
        if not ok:
            failures += 1

    width = max(len(row[0]) for row in rows)
    print("WIN20 automation-plane assertions, armed")
    print("  subject dump: %s" % args.dump)
    print("")
    for name, got, want, ok in rows:
        print("  %-4s %-*s  %-28s %s" % ("ok" if ok else "MISS", width, name, got, want))
    print("")
    print("  %d arms, %d did not behave as required" % (len(rows), failures))

    if failures:
        print("")
        print("  An arm that did not fire is not a cosmetic problem: it is an assertion that")
        print("  cannot distinguish the thing it exists to notice from its absence.")
        return EXIT_FAIL
    return EXIT_PASS


if __name__ == "__main__":
    sys.exit(main())
