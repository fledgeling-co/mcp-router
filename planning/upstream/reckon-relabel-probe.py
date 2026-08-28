#!/usr/bin/env python3
"""Ask a `reckon` installation whether its re-label refusal can fire on a ledger it wrote itself.

## What this is for

`G27`. `reckon`'s ratchet carries a guard against a requirement being moved from `unmeasured` to
`observed` by typing: the move is refused unless a passing case cites the requirement, read from
`backed_by` — a list computed from the campaign rather than from the requirement's own word. The
guard's own comment records the measurement behind it, one campaign moving eight requirements in a
single session with no case having run in between.

The guard cannot fire on a ledger `reckon` writes. The writer emits `sorted(backing.get(id, []))
or None`, so zero backing cases serialise as `null` rather than as an empty list, and the reader
takes `null` as "this ledger predates the field" and continues. That allowance is deliberate and
correct — a pre-field ledger carries no such key, and refusing there would report the ledger's age
as a defect in the project — but because the writer never produces an empty list, every zero-backing
row takes the allowance and the refusal below it is unreachable.

The defect is upstream in `fledgeling-plugins`, not in this repository. This probe exists so the
estate can ask a given `reckon` whether it is still affected, rather than re-deriving the answer by
reading source each time a release lands. `planning/upstream/reckon-relabel-gate.md` is the report.

## Why three arms and not one

A one-arm probe that saw `exit 0` could not tell an unreachable guard from a transition the guard
correctly allowed. So the same transition is put to the tool three times, differing only in the
shape of `backed_by` on the one row:

  null       what the writer emits for zero backing cases. Must be REFUSED by a fixed reckon.
  []         what the guard's own text expects. The discriminating arm — a tool that lets this
             through is not affected-with-a-workaround, it has no working guard at all, and the
             probe says so rather than reporting the same verdict.
  key absent a ledger genuinely written before the field existed. Must be ALLOWED, or the fix has
             broken the allowance it was built around.

The `[]` arm is the planted instance this probe is armed by: it is a condition the tool must refuse
whatever else it does, so an arm-set that comes back all-clean means the probe measured nothing and
is reported as inconclusive rather than as a pass.

## What it does not touch

Nothing in this repository is written. The campaign registry and the brief queue are COPIED into a
scratch tree and edited there, and the `reckon` installation under test is read and never modified —
forking a vendored instrument is the failure this item is filed against, not a remedy for it.

## Exit codes

  0  every arm measured; the tool under test REFUSES the null arm — not affected
  1  every arm measured; the tool under test ALLOWS the null arm — affected, the G27 defect
  2  could not measure: no reckon found, a build failed, or the registry offered no subject row
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CAMPAIGN = os.path.join(ROOT, "planning", "test-campaign")
BRIEFS = os.path.join(ROOT, "planning", "features-to-triage")

# The word a requirement carries when the project reports it rather than a case observing it.
# Any word `reckon` classes `unmeasured` serves; this one is in the registry's own vocabulary.
SELF_REPORTED = "reported"


def candidate_tools():
    """Every `reckon` this machine holds, newest path last, derived rather than written out.

    `runnable-path-gate.py` fails a runnable file that names a path under a home or a volume, and
    it is right to: `.worktrees/R2` was written into two gates and deleted by a cleanup, and both
    ran dead for weeks. So the plugin cache is expanded from `~` at run time and the versions come
    from a glob, which means a release installed tomorrow is in scope tomorrow.
    """
    pattern = os.path.join(
        os.path.expanduser("~"), ".claude", "plugins", "cache", "fledgeling-plugins",
        "reckon", "*", "skills", "reckon", "scripts", "reckon.py")
    return sorted(glob.glob(pattern))


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def subject(campaign_dir):
    """A requirement recorded `observed` that at least one passing case cites, and that case's id.

    Chosen from the registry rather than named in this file, because a hard-coded `REQ-021` is a
    citation into a document somebody else maintains and rots the same way a path does. Returns
    `(requirement_id, [case ids])`, or `(None, [])` when the registry offers no such row — which
    is reported as inconclusive, never as a clean run.
    """
    cases = load(os.path.join(campaign_dir, "cases.json"))
    if isinstance(cases, dict):
        cases = cases.get("cases", [])
    citing = {}
    skipped_not_pass = 0
    skipped_no_req = 0
    for case in cases:
        if not isinstance(case, dict):
            continue
        if str(case.get("status", "")).lower() != "pass":
            skipped_not_pass += 1
            continue
        cited = case.get("req")
        ids = [cited] if isinstance(cited, str) else list(cited or [])
        if not ids:
            skipped_no_req += 1
            continue
        for rid in ids:
            citing.setdefault(rid, []).append(case.get("id"))
    print("  cases read: %d cited by a passing case, %d not passing, %d passing with no `req`"
          % (len(citing), skipped_not_pass, skipped_no_req))

    inventory = load(os.path.join(campaign_dir, "inventory.json"))
    requirements = inventory.get("requirements") if isinstance(inventory, dict) else None
    if not requirements:
        requirements = load(os.path.join(campaign_dir, "requirements.in.json"))
        if isinstance(requirements, dict):
            requirements = requirements.get("requirements", [])
    for req in requirements:
        if not isinstance(req, dict):
            continue
        rid = req.get("id")
        if str(req.get("evidence", "")).lower() == "observed" and citing.get(rid):
            return rid, citing[rid]
    return None, []


def scratch_campaign(dest, rid, drop_citations, self_report):
    """A copy of the registry with one requirement's backing and/or evidence word changed.

    Returns what it changed AND what it declined to open. A registry file this reader skipped is a
    file whose citations of `rid` survive into the scratch tree, which would leave the requirement
    backed after an edit that reported success — so the skips are counted and named by the caller
    rather than dropped, which is `reader-accounting.py`'s rule and the reason it exists.
    """
    shutil.rmtree(dest, ignore_errors=True)
    shutil.copytree(CAMPAIGN, dest)
    cleared = 0
    relabelled = 0
    not_json = []
    unreadable = []
    for name in sorted(os.listdir(dest)):
        if not name.endswith(".json"):
            not_json.append(name)
            continue
        path = os.path.join(dest, name)
        try:
            data = load(path)
        except (OSError, ValueError) as error:
            unreadable.append("%s (%s)" % (name, type(error).__name__))
            continue
        stack = [data]
        while stack:
            node = stack.pop()
            if isinstance(node, dict):
                if drop_citations and "req" in node:
                    cited = node["req"]
                    if cited == rid:
                        node["req"] = None
                        cleared += 1
                    elif isinstance(cited, list) and rid in cited:
                        node["req"] = [x for x in cited if x != rid]
                        cleared += 1
                if self_report and node.get("id") == rid and "evidence" in node:
                    node["evidence"] = SELF_REPORTED
                    relabelled += 1
                stack.extend(node.values())
            elif isinstance(node, list):
                stack.extend(node)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(data, handle)
    return cleared, relabelled, not_json, unreadable


def build(tool, campaign_dir, out_dir):
    """Build a ledger, and keep one the tool wrote while exiting non-zero.

    `build` reports a low join rate by exiting non-zero, and this repository's join rate is under
    a fifth — so a probe keyed on the exit code alone reports every older `reckon` as unmeasurable
    over a ledger sitting complete on disk beside it. What matters here is whether a ledger was
    WRITTEN, and by which version; the join warning is a fact about this corpus and says nothing
    about the guard. The exit code is printed rather than dropped.
    """
    result = subprocess.run(
        [sys.executable, tool, "build", "--briefs", BRIEFS,
         "--campaign", campaign_dir, "--out", out_dir],
        capture_output=True, text=True)
    ledger = os.path.join(out_dir, "ledger.json")
    if not os.path.exists(ledger):
        tail = (result.stderr or result.stdout).strip().splitlines()[-1:]
        return None, ["build exit=%d," % result.returncode] + tail
    if result.returncode != 0:
        print("    (build exit=%d and a ledger was written anyway; the message is about this "
              "corpus's join rate, not about the guard)" % result.returncode)
    return ledger, []


def variant(source, dest_dir, rid, shape):
    """The same ledger with one row's `backed_by` rewritten to the shape being put to the tool."""
    data = load(source)
    touched = 0
    for row in data.get("rows", []):
        if row.get("entity") == "requirement" and row.get("id") == rid:
            if shape == "empty":
                row["backed_by"] = []
            elif shape == "absent":
                row.pop("backed_by", None)
            touched += 1
    os.makedirs(dest_dir, exist_ok=True)
    out = os.path.join(dest_dir, "ledger.json")
    with open(out, "w", encoding="utf-8") as handle:
        json.dump(data, handle)
    return out, touched


def ratchet(tool, previous, current):
    result = subprocess.run([sys.executable, tool, "ratchet", previous, current],
                            capture_output=True, text=True)
    text = (result.stdout or "") + (result.stderr or "")
    refused = "re-label" in text
    return result.returncode, refused


def probe(tool, work):
    home = os.path.expanduser("~")
    label = "~/" + os.path.relpath(tool, home) if tool.startswith(home + os.sep) else tool
    print("reckon under test: %s" % label)

    rid, backing_cases = subject(CAMPAIGN)
    if rid is None:
        print("  INCONCLUSIVE: no requirement in the registry is recorded `observed` with a "
              "passing case citing it, so this probe has no transition to put to the tool.")
        return 2
    print("  subject: %s, cited by %d passing case(s): %s"
          % (rid, len(backing_cases), ", ".join(str(c) for c in backing_cases)))

    unbacked = os.path.join(work, "campaign-unbacked")
    cleared, _, not_json, unreadable = scratch_campaign(
        unbacked, rid, drop_citations=True, self_report=False)
    earlier = os.path.join(work, "campaign-earlier")
    _, relabelled, _, _ = scratch_campaign(
        earlier, rid, drop_citations=True, self_report=True)
    print("  scratch registries: %d case citation(s) of %s cleared, evidence word set to %r at "
          "%d site(s) for the earlier ledger" % (cleared, rid, SELF_REPORTED, relabelled))
    print("  registry files this edit did not open: %d not .json (%s), %d it could not parse (%s)"
          % (len(not_json), ", ".join(not_json) or "none",
             len(unreadable), ", ".join(unreadable) or "none"))
    if cleared == 0 or relabelled == 0:
        print("  INCONCLUSIVE: the scratch edit changed nothing, so the two ledgers do not differ "
              "in the way this probe reports on.")
        return 2

    previous, why = build(tool, earlier, os.path.join(work, "previous"))
    if previous is None:
        print("  INCONCLUSIVE: the earlier ledger did not build. %s" % " ".join(why))
        return 2
    written, why = build(tool, unbacked, os.path.join(work, "written"))
    if written is None:
        print("  INCONCLUSIVE: the current ledger did not build. %s" % " ".join(why))
        return 2

    row = [r for r in load(written).get("rows", [])
           if r.get("entity") == "requirement" and r.get("id") == rid]
    if not row:
        print("  INCONCLUSIVE: %s is absent from the ledger the tool wrote." % rid)
        return 2
    emitted = row[0].get("backed_by", "<key absent>")
    print("  the writer emitted backed_by=%r for %s with zero backing cases" % (emitted, rid))

    before = load(previous)
    was = [r.get("class") for r in before.get("rows", [])
           if r.get("entity") == "requirement" and r.get("id") == rid]
    print("  %s in the earlier ledger: class=%s" % (rid, was[0] if was else "<absent>"))

    empty, _ = variant(written, os.path.join(work, "arm-empty"), rid, "empty")
    absent, _ = variant(written, os.path.join(work, "arm-absent"), rid, "absent")

    arms = [("as written (backed_by null)", written, "refuse"),
            ("backed_by []", empty, "refuse"),
            ("backed_by key absent", absent, "allow")]
    results = {}
    for name, ledger, expected in arms:
        code, refused = ratchet(tool, previous, ledger)
        got = "refused" if refused else "allowed"
        results[name] = (code, refused)
        print("  arm %-30s exit=%d  %-8s (a working guard must %s)" % (name, code, got, expected))

    written_refused = results["as written (backed_by null)"][1]
    empty_refused = results["backed_by []"][1]
    absent_refused = results["backed_by key absent"][1]

    if not empty_refused:
        print("  INCONCLUSIVE: the planted arm was not refused either, so this run distinguishes "
              "nothing — the guard is absent or renamed rather than unreachable, and the source "
              "has to be read before any verdict is taken from these exit codes.")
        return 2
    if absent_refused:
        print("  INCONCLUSIVE: a ledger with no `backed_by` key was refused, which is the "
              "allowance for an older ledger failing rather than the defect this probe reports.")
        return 2
    if written_refused:
        print("  NOT AFFECTED: the refusal fires on a ledger this tool wrote itself, and a "
              "pre-field ledger still passes.")
        return 0
    print("  AFFECTED (G27): the same transition is refused when `backed_by` is [] and allowed "
          "when it is the null this tool's own writer emits, so the guard cannot fire on any "
          "ledger this version writes.")
    return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--reckon", action="append", default=[],
                        help="a reckon.py to test; repeatable. Default: every one under the "
                             "plugin cache in this account's home.")
    args = parser.parse_args()

    tools = args.reckon or candidate_tools()
    if not tools:
        print("INCONCLUSIVE: no reckon.py found under the plugin cache, and none named with "
              "--reckon. Nothing was measured.")
        return 2
    for path in tools:
        if not os.path.exists(path):
            print("INCONCLUSIVE: %s does not exist." % path)
            return 2

    verdicts = []
    for tool in tools:
        with tempfile.TemporaryDirectory(prefix="reckon-relabel-probe-") as work:
            verdicts.append((tool, probe(tool, work)))
        print("")

    affected = [t for t, v in verdicts if v == 1]
    clean = [t for t, v in verdicts if v == 0]
    unmeasured = [t for t, v in verdicts if v == 2]
    print("%d reckon installation(s) put to the probe: %d affected, %d not affected, %d not measured"
          % (len(verdicts), len(affected), len(clean), len(unmeasured)))
    if unmeasured and not affected and not clean:
        return 2
    return 1 if affected else 0


if __name__ == "__main__":
    sys.exit(main())
