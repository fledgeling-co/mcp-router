#!/usr/bin/env python3
"""A brief leaves the remaining-work set on a merge somebody can point at, or it does not leave.

G31. Measured across this fleet's own output on 2026-08-27: eleven items shipped, were verified
and were merged in one session, and `reckon` read **190 pieces of work before and 190 after**.
Every shipped brief was still counted -- five `unjoined`, one `undecided`, none `verified-done`.

The mechanism is not a fault in the instrument. `reckon` reads the brief FILES under
`planning/features-to-triage/`, and a brief carries no state that says it shipped: that lives in
`LEDGER.md`, which `reckon` does not read. A brief leaves the remaining set only by JOINING to a
passing case in the campaign registry, and this repository's join rate is **28 of 156 (17.9%)** --
below the 50% floor at which `reckon` withholds retirement claims outright, so at this join rate
nothing can reach `retirable` however green it is. The consequence is not a reporting nuisance:
`ship-fleet` finishes when the ledger drains AND the reconciliation is clean, so a reconciliation
that shipping cannot move is an unreachable termination condition.

THE ONE LEVER `reckon` LEAVES OPEN, and why it needs a guard around it.

`reckon.WAIVED_DECLARED` reads a brief's frontmatter `status:` and, for a word in that closed set,
classes the brief `waived` -- an exception rather than remaining work. That is a status WORD. It is
exactly the release-by-typing that `reckon` refuses everywhere else: a requirement may not leave
`unmeasured` on its own evidence word when no passing case cites it (`reckon.py:1296`, the
`backed_by` refusal), because "a registry a person edits cannot also be the witness that the edit
was earned".

`reckon`'s own ratchet cannot hold this end. `reckon.py:1310` is `if crow["entity"] == "brief":
continue` -- briefs are exempt from the ratchet by construction, so typing `status: retired` into a
brief that never shipped passes `check` and `ratchet` at exit 0 and removes the row from the total.
This gate is the missing half. It gives the brief's word a witness the brief cannot write.

THE WITNESS. Git, adjudicating two typed claims that have to agree.

  the brief says     `status: retired` / `status: completed` and `shipped-by: <sha>`
  the LEDGER says    the row's status cell leads with a shipped word and names commits
  git rules          the commit resolves AND is an ancestor of the integration branch

A word with no LEDGER row, a LEDGER row that is not shipped, or a commit git cannot place on the
branch is refused. That is R1-R3 below, and it is the whole point: the route out is a merge, not a
sentence.

TWO TERMINAL WORDS, BECAUSE "SHIPPED AND MEASURED" AND "SHIPPED AND NEVER MEASURED" ARE DIFFERENT
CONCLUSIONS.

  retired    shipped, and at least one PASSING case at or above the retirement oracle rung is
             reached by a citation the brief itself wrote. The registry answered.
  completed  shipped, and nothing in the registry answers to it. This is a real class and it says
             so: the work landed and no case stands behind it. It is NOT `unjoined`, which means
             nobody has looked at the brief at all -- the opposite conclusion, and the one 128
             rows of this repository's reckoning currently carry.

Both words are in `reckon.WAIVED_DECLARED`, so `reckon` stops counting either as work and prints
the declared word on the row. Which of the two a brief has earned is R4.

A MERGE DOES NOT SETTLE A MEASUREMENT, WHICH IS R6 AND IS THE RULE THAT MAKES THE REST SAFE.

`reckon` tests the declared status FIRST (reckon.py:945), ahead of every evidence branch. So a
terminal word on a brief the registry still records a failing case or an open defect against would
class `waived` and take the row off the total -- a status word overriding a measurement, in the one
direction that cannot be recovered from. Five of this repository's shipped briefs are exactly that
shape: `R10`, `R21`, `I1`, `M6` and `M27` all merged and all sit in `broken` because a case against
their subject is red. R6 refuses a terminal word on any brief whose edges reach a failing case, an
open or partially-fixed defect, or a requirement whose evidence is contradicted or vacuous. Those
briefs stay work, and `--apply` will not write a word onto them.

WHAT THIS DOES NOT FIX, stated here rather than discovered later.

  * `reckon` lands both words in its `waived` class, which is named for decisions somebody took.
    A shipped brief is not a decision not to do something. The word on the row (`declared_status`)
    is what carries the distinction, and a class of its own would be an upstream change.
  * The join rate is the real lever and this is the stopgap. At 17.9% most briefs are unjoined
    whether they shipped or not, and this gate moves none of them into the registry -- it only
    stops a merged one being counted as work nobody has looked at. Raising the join means writing
    real citations as cases are written; writing them in bulk afterwards is the failure `reckon`
    records at its own `backed_by` guard.
  * It reads `LEDGER.md`'s status cell, which is prose with a status word at the front. A row whose
    cell has been rewritten so the leading word is gone reads as unshipped here. That fails in the
    safe direction -- the brief stays counted as work -- and it is why R5 prints the shipped rows
    that declared nothing rather than staying silent about them.

R5 IS A FINDING AND NEVER A REFUSAL. A brief whose row is shipped-with-witness and that declares no
terminal status is the exact defect this item is about, and blocking on it would make `lint` red
for every runner between a merge and its bookkeeping. Over-reporting remaining work is the safe
direction; under-reporting done is not. So R5 is counted and printed, and R1-R4 block.

EXIT CODES.  0 clean · 1 findings · 2 the control failed · 3 inconclusive (no LEDGER.md, no
integration ref, or no reckon ledger to read citations out of). A run that could not read one of
its three inputs prints no verdict, because a census from an instrument that could not see its
subject is not a measurement.

  python3 planning/shipped-brief-gate.py            # the gate
  python3 planning/shipped-brief-gate.py --control  # the arms only
  python3 planning/shipped-brief-gate.py --apply    # write the statuses git already witnesses
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIEFS = ROOT / "planning" / "features-to-triage"
LEDGER = BRIEFS / "LEDGER.md"
RECKONINGS = ROOT / "planning" / "reckoning"
CAMPAIGN = ROOT / "planning" / "test-campaign"
INTEGRATION = "main"

FINDINGS = 1
CONTROL_FAILED = 2
INCONCLUSIVE = 3

# The two words this repository may put on a shipped brief. Both are in `reckon.WAIVED_DECLARED`
# (reckon 1.7.0, reckon.py:58) -- a word outside that set does not release the brief from the
# total however true it is, so the vocabulary is closed here and checked against reckon's there.
MEASURED, UNMEASURED = "retired", "completed"
TERMINAL = (MEASURED, UNMEASURED)

# Words a brief may carry that are decisions rather than shipping claims. reckon classes them
# `waived` too. They are NOT this gate's axis -- a decision is earned by somebody recording a
# reason, not by a commit -- and they are printed separately so a reader can see this gate did not
# adjudicate them.
DECISIONS = ("waived", "deferred", "wontfix", "won't fix", "declined", "out of scope",
             "consumed", "scaffolded", "historical")

# A LEDGER status cell is prose with a status word at the front. Only these three mean the work
# landed on the integration branch. `Retired` and `Superseded` are deliberately absent: they are
# rulings, and a ruling is not a merge.
SHIPPED_LEAD = re.compile(r"^\*{0,2}(merged|done|delivered)\b", re.I)
CELL_SHA = re.compile(r"`([0-9a-f]{7,40})`")

# The oracle ladder, weakest first, mirroring `reckon.ORACLE_RUNGS` and its `RETIREMENT_RUNG`
# floor of `outcome` (reckon.py:315-322). Re-spelling a vocabulary is the drift risk reckon names
# in its own header, and it is taken knowingly: reckon is a machine-local plugin, this gate runs
# in `lint` on any checkout, and a five-word tuple with the source named is the cheaper of the two
# failures. A `pass` at `presence` proves a thing exists on screen, which is compatible with it
# doing nothing at all, so it cannot carry a retirement.
ORACLE_RUNGS = ("presence", "structural", "outcome", "effect-witness", "interactive-glass")
RETIREMENT_RUNG = "outcome"

# Defect statuses that mean the row is still owed, mirroring `reckon.DEFECT_OPEN` and
# `reckon.DEFECT_PARTIAL` (reckon.py:110, 131). A registry writes a compound status
# (`answered · F191 · not re-measured`), so the leading verb is what is read. `partially-fixed` is
# here for reckon's own reason: a half still broken owes a reproduction for that half.
DEFECT_STILL_OWED = ("open", "new", "confirmed", "reopened", "regressed", "in progress",
                     "recorded", "standing", "partially-fixed", "partially fixed", "part-fixed")

# Requirement evidence that means the documents and the build disagree (`reckon.EVIDENCE_DISPUTED`,
# reckon.py:348). A brief over one of these is `undecided` work, not done.
EVIDENCE_DISPUTED = ("contradicted", "vacuous")

FRONTMATTER = re.compile(r"\A---\s*\n(.*?)\n---\s*\n", re.S)


# ------------------------------------------------------------------------------------- the inputs

def frontmatter(text):
    """reckon parses frontmatter shallowly -- `k: v`, one per line -- and this must match it or
    the two disagree about what a brief declares while both parse cleanly."""
    match = FRONTMATTER.match(text)
    if not match:
        return {}, text
    meta = {}
    for line in match.group(1).splitlines():
        key, sep, value = line.partition(":")
        if sep:
            meta[key.strip().lower()] = value.strip().strip("\"'")
    return meta, text[match.end():]


def briefs_on_disk():
    """Every brief, plus what this reader put down. The dropped names are returned rather than
    swallowed: a brief this gate could not read is a brief whose word nobody checked, and a census
    that silently narrows its own denominator is the failure `reader-accounting.py` exists for."""
    out, dropped = {}, []
    if not BRIEFS.is_dir():
        return out, dropped
    for path in sorted(BRIEFS.glob("*.md")):
        if path.name.upper().startswith(("BRIEF-TEMPLATE", "README", "00-INDEX", "LEDGER")):
            dropped.append("%s: not a brief, and reckon.read_briefs skips the same names" % path.name)
            continue
        try:
            meta, _ = frontmatter(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError) as error:
            dropped.append("%s: unreadable (%s)" % (path.name, type(error).__name__))
            continue
        out[path.name] = {
            "file": path.name,
            "path": path,
            "status": (meta.get("status") or "").lower(),
            "shipped_by": (meta.get("shipped-by") or "").lower(),
        }
    return out, dropped


def ledger_rows(text):
    """One row per pipeline item. The Brief column names a file; the Status cell is prose whose
    first word is the state. Rows naming no brief file are kept -- they are why R1 can say
    `no row names this brief` rather than `no row exists`.

    A pipe-led line this rejects is returned beside the rows. LEDGER.md carries prose and a header
    rule as well as its table, so most of the drop is expected -- but a table row that stops
    parsing is a pipeline item that stops being checked, and that has to be countable."""
    rows, dropped = [], []
    for line in text.splitlines():
        if not line.startswith("| "):
            # A line carrying a pipe that this reader will not read as a row is the shape that
            # matters: `|A|B|` with no leading space is a table row to a markdown renderer and
            # prose to this parser. A line with no pipe at all is recorded as prose and named by
            # count, because LEDGER.md is mostly prose and listing it would bury the other class.
            dropped.append(("pipe but not a row: " if "|" in line else "prose: ") + line[:70])
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 6:
            dropped.append("%d cell(s): %s" % (len(cells), line[:70]))
            continue
        if cells[0] in ("ID", "---") or set(cells[0]) <= {"-", ":"}:
            dropped.append("header or rule: %s" % line[:70])
            continue
        rows.append({"id": cells[0], "brief": cells[2].strip("`").strip(), "cell": cells[5]})
    return rows, dropped


def cell_witness(cell):
    """What the LEDGER row claims: a shipped lead word, and the commits it names."""
    return bool(SHIPPED_LEAD.match(cell)), CELL_SHA.findall(cell)


def on_branch(shas):
    """Resolve short shas and place them on the integration branch, in two subprocesses rather
    than one per row. Returns None when the branch cannot be read at all -- an absent ref is a
    fact about the checkout, and answering `not merged` for every row would report the whole
    pipeline as unshipped."""
    try:
        listing = subprocess.run(["git", "-C", str(ROOT), "rev-list", INTEGRATION],
                                 capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        return None
    reachable = set(listing.stdout.split())
    if not reachable:
        return None
    wanted = sorted(set(shas))
    if not wanted:
        return {}
    probe = subprocess.run(["git", "-C", str(ROOT), "cat-file", "--batch-check"],
                           input="\n".join(s + "^{commit}" for s in wanted),
                           capture_output=True, text=True)
    resolved = {}
    for short, line in zip(wanted, probe.stdout.splitlines()):
        parts = line.split()
        if len(parts) == 3 and parts[1] == "commit" and parts[0] in reachable:
            resolved[short] = parts[0]
    return resolved


def newest_reckoning():
    """The freshest reckoning that actually wrote a ledger, and the ones that did not.

    A reckoning directory with no `ledger.json` is a run that did not finish, and picking the
    newest DIRECTORY rather than the newest ledger would read R4 and R6 out of a run that produced
    nothing. The skipped directories are returned so the choice is visible."""
    if not RECKONINGS.is_dir():
        return None, []
    dirs, skipped = [], []
    for path in sorted(RECKONINGS.iterdir()):
        if (path / "ledger.json").is_file():
            dirs.append(path)
        else:
            skipped.append(path.name)
    return (dirs[-1] if dirs else None), skipped


def citation_backing(ledger_path, cases, defects, requirements):
    """What the registry says about each brief: what backs it, and what contradicts it.

    This is the `backed_by` discipline, one entity out. The edges are computed by `reckon` from the
    brief text against the registry -- a different tool reading a different source -- so a brief
    cannot put itself in either map by declaring anything.

    `backing` counts only CITED edges reaching a passing case at or above the retirement rung:
    reckon's own note is that an overlap edge is a guess and cannot retire a brief. `contra` counts
    EVERY edge, cited or overlap, because it holds a brief open rather than closing it, and a
    guess that keeps work on the list costs a re-read while the other direction costs the failure
    this whole tool exists against.
    """
    try:
        led = json.loads(Path(ledger_path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None, None
    floor = ORACLE_RUNGS.index(RETIREMENT_RUNG)
    strong, red = {}, {}

    def mark(table, key, value):
        if key:
            table.setdefault(key, []).append(value)

    for case in cases:
        status = str(case.get("status") or "").split(":")[0].strip()
        for key in ("id", "req", "surface", "flow"):
            if status == "fail":
                mark(red, case.get(key), "%s fails" % case["id"])
            elif status == "pass":
                rung = case.get("oracle")
                if rung in ORACLE_RUNGS and ORACLE_RUNGS.index(rung) >= floor:
                    mark(strong, case.get(key), case["id"])
    for defect in defects:
        lead = re.split(r"\s*[·|,;]\s*", str(defect.get("status") or "").lower())[0].strip()
        if lead in DEFECT_STILL_OWED:
            for key in ("id", "req", "surface"):
                mark(red, defect.get(key), "%s is %s" % (defect["id"], lead))
    for req in requirements:
        if str(req.get("evidence") or "").lower() in EVIDENCE_DISPUTED:
            mark(red, req.get("id"), "%s is %s" % (req["id"], req["evidence"]))

    backing, contra = {}, {}
    for row in led.get("rows", []):
        if row.get("entity") != "brief":
            continue
        edges = row.get("edges") or []
        cited = {e["target"] for e in edges if e.get("method") == "cited"}
        every = {e["target"] for e in edges}
        hits = sorted({c for t in cited for c in strong.get(t, [])})
        if hits:
            backing[row["id"]] = hits
        against = sorted({c for t in every for c in red.get(t, [])})
        if against:
            contra[row["id"]] = against
    return backing, contra


def campaign_registry():
    """cases.json plus the inventory the registry keeps beside it. Each part is optional; a part
    this cannot read simply contributes nothing, which loses a refusal rather than inventing one."""
    def load(path, key=None):
        if not path.is_file():
            return []
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return []
        if isinstance(data, dict):
            return data.get(key) or data.get(key + "s") or [] if key else []
        return data

    cases = load(CAMPAIGN / "cases.json", "case")
    inv = {}
    path = CAMPAIGN / "inventory.json"
    if path.is_file():
        try:
            inv = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            inv = {}
    return cases, inv.get("defect", []), inv.get("requirement", [])


# -------------------------------------------------------------------------------------- the rules

def judge(briefs, rows, resolved, backing, contra):
    """R1-R6 over one corpus. `resolved` maps a short sha to its full sha when git placed it on
    the integration branch; `backing` maps BRIEF-<slug> to the passing cases that answer to it and
    `contra` to whatever in the registry still says no.

    Returns (classes, findings). `classes` partitions every brief this gate has an opinion about;
    a brief that declares nothing and whose row is not shipped appears in neither, which is right
    -- it is ordinary remaining work and not this gate's subject.
    """
    by_brief = {}
    for row in rows:
        if row["brief"] and row["brief"] not in ("-", "—"):
            by_brief.setdefault(row["brief"], []).append(row)

    classes = {"shipped-measured": [], "shipped-unmeasured": [], "shipped-contested": [],
               "undeclared-shipped": [], "decision": []}
    findings = []

    for name, brief in sorted(briefs.items()):
        status = brief["status"]
        rows_here = by_brief.get(name, [])
        witnessed = []
        for row in rows_here:
            shipped, shas = cell_witness(row["cell"])
            if shipped:
                witnessed.extend(s for s in shas if s in resolved)
        witnessed = sorted(set(witnessed))
        brief_id = "BRIEF-" + Path(name).stem
        earned = MEASURED if backing.get(brief_id) else UNMEASURED
        contested = contra.get(brief_id)

        if status in DECISIONS:
            classes["decision"].append(name)
            continue

        if status not in TERMINAL:
            # R5 -- reported, never a refusal. This is the merge the reckoning cannot see.
            if witnessed and contested:
                classes["shipped-contested"].append((name, witnessed[0], contested))
            elif witnessed:
                classes["undeclared-shipped"].append((name, witnessed[0]))
            continue

        # R1 -- a word with no row is a claim with nothing behind it at all.
        if not rows_here:
            findings.append("%s declares `status: %s` and no LEDGER row names it. The word is the "
                            "only thing saying this shipped" % (name, status))
            continue

        # R2 -- the row must lead with a shipped word AND name a commit git places on the branch.
        if not witnessed:
            leads = [row["cell"].split("—")[0].strip()[:60] for row in rows_here]
            findings.append("%s declares `status: %s` and no LEDGER row for it is shipped with a "
                            "commit reachable from `%s` (rows say: %s)"
                            % (name, status, INTEGRATION, "; ".join(leads) or "nothing"))
            continue

        # R3 -- the brief's own pointer must be one of the commits its row witnesses.
        claimed = brief["shipped_by"]
        if claimed and not any(w.startswith(claimed) or claimed.startswith(w) for w in witnessed):
            findings.append("%s declares `shipped-by: %s`, which is not among the commits its "
                            "LEDGER row witnesses (%s). Two typed claims that disagree is not "
                            "evidence" % (name, claimed, ", ".join(witnessed)))
            continue

        # R6 -- a merge does not settle a measurement. Checked before R4 because it is the refusal
        # that keeps a status word from overriding a red case, which is the unrecoverable direction.
        if contested:
            findings.append("%s declares `status: %s` and the registry still says no against its "
                            "subject (%s). It merged; that is not a measurement, and `reckon` reads "
                            "the declared word ahead of the evidence, so this word would take a "
                            "failing row off the total" % (name, status, "; ".join(contested[:4])))
            continue

        # R4 -- `retired` is the measured word and needs a passing case behind it.
        if status == MEASURED and earned != MEASURED:
            findings.append("%s declares `status: %s` and no passing case at or above the %r rung "
                            "is reached by a citation it wrote. It shipped; nothing measured it. "
                            "The earned word is `%s`" % (name, MEASURED, RETIREMENT_RUNG, UNMEASURED))
            continue
        classes["shipped-measured" if status == MEASURED else "shipped-unmeasured"].append(name)

    return classes, findings


# ------------------------------------------------------------------------------------ the control

CONTROL_ROWS = """| ID | Title | Brief | Spec | Plan | Status |
|---|---|---|---|---|---|
| A1 | measured | `a-measured.md` | - | - | **Merged** `aaaaaaa` |
| A2 | unmeasured | `a-unmeasured.md` | - | - | **Done** (`bbbbbbb`) |
| A3 | not shipped | `a-typed.md` | - | - | **To Do** - allocated today |
| A4 | ghost sha | `a-ghost.md` | - | - | **Merged** `ccccccc` |
| A5 | over-claim | `a-overclaim.md` | - | - | **Merged** `aaaaaaa` |
| A6 | drift | `a-drift.md` | - | - | **Merged** `bbbbbbb` |
| A7 | quiet | `a-quiet.md` | - | - | **To Do** |
| A8 | wrong pointer | `a-pointer.md` | - | - | **Merged** `aaaaaaa` |
| A9 | contested | `a-contested.md` | - | - | **Merged** `aaaaaaa` |
| A10 | contested drift | `a-contested-drift.md` | - | - | **Merged** `aaaaaaa` |
"""


def control():
    """Ten arms on a synthetic corpus, every invocation.

    A rule set that matches nothing returns clean over any tree, and a clean tree returns clean
    too -- they are indistinguishable from the exit code, which is how this repository has twice
    shipped a gate that could not go red. Each arm below is one of the six rules in exactly one
    direction, plus the three silences that prove the gate is not simply reporting everything.
    """
    rows, dropped = ledger_rows(CONTROL_ROWS)
    if len(rows) != 10:
        return "the row reader found %d row(s) in the control ledger, expected 10" % len(rows)
    if sorted(d.split(":")[0] for d in dropped) != ["header or rule", "pipe but not a row"]:
        return ("the row reader dropped %r from the control ledger, expected the header row and "
                "the alignment rule and nothing else" % dropped)

    def brief(name, status="", shipped_by=""):
        return {"file": name, "path": None, "status": status, "shipped_by": shipped_by}

    briefs = {
        "a-measured.md": brief("a-measured.md", MEASURED),
        "a-unmeasured.md": brief("a-unmeasured.md", UNMEASURED),
        "a-typed.md": brief("a-typed.md", MEASURED),
        "a-ghost.md": brief("a-ghost.md", UNMEASURED),
        "a-overclaim.md": brief("a-overclaim.md", MEASURED),
        "a-drift.md": brief("a-drift.md", "to-triage"),
        "a-quiet.md": brief("a-quiet.md", "to-triage"),
        "a-pointer.md": brief("a-pointer.md", UNMEASURED, "ddddddd"),
        "a-absent.md": brief("a-absent.md", UNMEASURED),
        "a-decision.md": brief("a-decision.md", "deferred"),
        "a-contested.md": brief("a-contested.md", UNMEASURED),
        "a-contested-drift.md": brief("a-contested-drift.md", "to-triage"),
    }
    # `ccccccc` is deliberately absent: a sha typed into the ledger that git cannot place.
    resolved = {"aaaaaaa": "aaaaaaa" + "0" * 33, "bbbbbbb": "bbbbbbb" + "0" * 33}
    backing = {"BRIEF-a-measured": ["CASE-0001"]}
    contra = {"BRIEF-a-contested": ["CASE-0009 fails"],
              "BRIEF-a-contested-drift": ["DEF-0009 is open"]}

    classes, findings = judge(briefs, rows, resolved, backing, contra)
    text = " || ".join(findings)

    if classes["shipped-measured"] != ["a-measured.md"]:
        return "the measured arm classed %r, expected ['a-measured.md']" % classes["shipped-measured"]
    if classes["shipped-unmeasured"] != ["a-unmeasured.md"]:
        return ("the unmeasured arm classed %r, expected ['a-unmeasured.md']"
                % classes["shipped-unmeasured"])
    if [n for n, _ in classes["undeclared-shipped"]] != ["a-drift.md"]:
        return "the R5 drift arm classed %r, expected ['a-drift.md']" % classes["undeclared-shipped"]
    if [n for n, _, _ in classes["shipped-contested"]] != ["a-contested-drift.md"]:
        return ("a shipped brief the registry contradicts was offered to --apply: %r"
                % classes["shipped-contested"])
    if classes["decision"] != ["a-decision.md"]:
        return "the decision arm classed %r, expected ['a-decision.md']" % classes["decision"]
    if any("a-quiet.md" in f for f in findings):
        return "a brief that declares nothing and did not ship was reported: %s" % text
    if any("a-drift.md" in f for f in findings):
        return "R5 blocked instead of reporting -- a drifted brief must never be a finding: %s" % text
    if any("a-contested-drift.md" in f for f in findings):
        return "a contested brief that declares nothing was blocked rather than held back: %s" % text

    for name, why in (("a-absent.md", "R1, a terminal word with no LEDGER row"),
                      ("a-typed.md", "R2, a terminal word over a To Do row"),
                      ("a-ghost.md", "R2, a sha the branch does not carry"),
                      ("a-pointer.md", "R3, a shipped-by the row does not witness"),
                      ("a-contested.md", "R6, a terminal word over a failing case"),
                      ("a-overclaim.md", "R4, `retired` with no passing case behind it")):
        if not any(name in f for f in findings):
            return "%s was not reported (%s). Findings were: %s" % (name, why, text or "none")
    if len(findings) != 6:
        return "the arms produced %d finding(s), expected exactly 6: %s" % (len(findings), text)
    return None


# -------------------------------------------------------------------------------------- the apply

def apply_statuses(drifted, backing):
    """Write the terminal status git already witnesses. A deliberate flag, never a side effect of
    checking: a gate that writes on every run leaves the tree dirty and the next merge refuses."""
    wrote = []
    for name, sha in drifted:
        path = BRIEFS / name
        text = path.read_text(encoding="utf-8")
        word = MEASURED if backing.get("BRIEF-" + Path(name).stem) else UNMEASURED
        meta_match = FRONTMATTER.match(text)
        lines = ["status: %s" % word, "shipped-by: %s" % sha]
        if meta_match:
            kept = [ln for ln in meta_match.group(1).splitlines()
                    if ln.partition(":")[0].strip().lower() not in ("status", "shipped-by")]
            block = "---\n" + "\n".join(lines + kept) + "\n---\n"
            # FRONTMATTER's trailing `\s*\n` eats the blank line under the closing fence, so put
            # it back rather than closing the fence hard against the heading.
            rest = text[meta_match.end():]
            text = block + ("" if rest.startswith("\n") else "\n") + rest
        else:
            text = "---\n" + "\n".join(lines) + "\n---\n\n" + text.lstrip("\n")
        path.write_text(text, encoding="utf-8")
        wrote.append((name, word, sha))
    return wrote


# --------------------------------------------------------------------------------------- the run

def main():
    parser = argparse.ArgumentParser(
        description="Refuse a brief that leaves the remaining-work set on a word rather than a merge.")
    parser.add_argument("--control", action="store_true", help="run the arms and print the verdict only")
    parser.add_argument("--apply", action="store_true",
                        help="write the terminal status git already witnesses into drifted briefs")
    args = parser.parse_args()

    bad = control()
    if bad:
        print("control FAILED: %s" % bad)
        print("no census printed -- an instrument that cannot see the defect is not evidence")
        return CONTROL_FAILED
    print("control HELD (6 refusals fire: a word with no row, a word over a To Do row, a sha the "
          "branch does not carry, a shipped-by the row does not witness, a word over a failing "
          "case, `retired` with no case. A drifted brief, a contested one and an untouched one "
          "stay silent)")
    if args.control:
        return 0

    if not LEDGER.is_file():
        print("NOT A PASS -- no %s, so no brief's word could be checked against anything"
              % LEDGER.relative_to(ROOT))
        return INCONCLUSIVE
    rows, unparsed = ledger_rows(LEDGER.read_text(encoding="utf-8"))
    briefs, unread = briefs_on_disk()
    if not rows or not briefs:
        print("NOT A PASS -- %d LEDGER row(s) and %d brief(s); this run measured nothing"
              % (len(rows), len(briefs)))
        return INCONCLUSIVE

    every_sha = [s for row in rows for s in cell_witness(row["cell"])[1]]
    resolved = on_branch(every_sha)
    if resolved is None:
        print("NOT A PASS -- `%s` could not be read in this checkout, so no commit could be placed "
              "on the branch and every row would read as unshipped" % INTEGRATION)
        return INCONCLUSIVE

    reckoning, unfinished = newest_reckoning()
    if reckoning is None:
        print("NOT A PASS -- no reckoning under %s holds a ledger.json, so R4 and R6 have no "
              "citation edges to read and nothing could be told apart"
              % RECKONINGS.relative_to(ROOT))
        return INCONCLUSIVE
    cases, defects, requirements = campaign_registry()
    backing, contra = citation_backing(reckoning / "ledger.json", cases, defects, requirements)
    if backing is None:
        print("NOT A PASS -- %s could not be read" % (reckoning / "ledger.json").relative_to(ROOT))
        return INCONCLUSIVE

    classes, findings = judge(briefs, rows, resolved, backing, contra)

    print("corpus: %d brief(s), %d LEDGER row(s), %d of %d cited commit(s) placed on `%s`"
          % (len(briefs), len(rows), len(resolved), len(set(every_sha)), INTEGRATION))
    stray = [d for d in unparsed if d.startswith("pipe but not a row")]
    print("  not read: %d markdown file(s) under the brief queue, %d line(s) of LEDGER.md (%d of "
          "them carrying a pipe), %d reckoning(s) that wrote no ledger.json"
          % (len(unread), len(unparsed), len(stray), len(unfinished)))
    for note in stray[:5]:
        print("    %s" % note)
    for note in unread:
        print("    %s" % note)
    print("  registry read through %s over %d case(s), %d defect(s), %d requirement(s): %d brief(s) "
          "reach a passing case at or above the %r rung, %d have something still saying no"
          % ((reckoning / "ledger.json").relative_to(ROOT), len(cases), len(defects),
             len(requirements), len(backing), RETIREMENT_RUNG, len(contra)))
    print()
    print("terminal on a merge git can place on `%s`:" % INTEGRATION)
    print("  %-20s %d  shipped, and a passing case answers to a citation it wrote"
          % ("`" + MEASURED + "`", len(classes["shipped-measured"])))
    print("  %-20s %d  shipped, and nothing in the registry answers to it. Not `unjoined`: that "
          "means nobody looked" % ("`" + UNMEASURED + "`", len(classes["shipped-unmeasured"])))
    print("  %-20s %d  decisions somebody recorded -- not this gate's axis and not adjudicated here"
          % ("decision", len(classes["decision"])))

    if args.apply:
        wrote = apply_statuses(classes["undeclared-shipped"], backing)
        print()
        print("--apply wrote a terminal status into %d brief(s):" % len(wrote))
        for name, word, sha in wrote:
            print("  %s -> %s (%s)" % (name, word, sha))
        print("held back %d shipped brief(s) the registry contradicts -- see R6"
              % len(classes["shipped-contested"]))
        print("re-run without --apply to gate the result")
        return 0

    if classes["shipped-contested"]:
        print()
        print("R6 -- %d shipped brief(s) the registry still says no against. They merged and a case "
              "or a defect against their subject is red, so they stay work and no word may be "
              "written onto them:" % len(classes["shipped-contested"]))
        for name, sha, why in classes["shipped-contested"]:
            print("  %s (%s) — %s" % (name, sha, "; ".join(why[:3])))

    if classes["undeclared-shipped"]:
        print()
        print("R5 -- %d brief(s) whose LEDGER row is shipped with a commit on `%s` and that declare "
              "no terminal status. These are the merges the reckoning cannot see. Reported, never "
              "blocked: over-reporting remaining work is the safe direction. `--apply` writes the "
              "word git already witnesses."
              % (len(classes["undeclared-shipped"]), INTEGRATION))
        for name, sha in classes["undeclared-shipped"][:12]:
            print("  %s (%s)" % (name, sha))
        if len(classes["undeclared-shipped"]) > 12:
            print("  ...and %d more" % (len(classes["undeclared-shipped"]) - 12))

    if findings:
        print()
        print("FINDINGS:")
        for finding in findings:
            print("  %s" % finding)
        print()
        print("A brief leaves the remaining-work set on a merge somebody can point at. `reckon`")
        print("stops counting a brief whose frontmatter carries one of these words, reads that word")
        print("ahead of the evidence, and exempts briefs from its own ratchet (reckon.py:1310), so")
        print("this is the only place the word is earned rather than typed.")
        return FINDINGS

    print()
    print("every terminal brief is witnessed by a commit on `%s` and contradicted by nothing in the "
          "registry; %d shipped brief(s) still declare nothing and %d are held back by R6"
          % (INTEGRATION, len(classes["undeclared-shipped"]), len(classes["shipped-contested"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
