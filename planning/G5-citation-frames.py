#!/usr/bin/env python3
"""Read `D-g5-d`'s ten citations at two frames, under three named predicates.

## Why this file exists

Gap-fix 4 printed a `HIT`/`MISS` table for these ten citations and headlined it `10/10 resolve at
a9603e5 · 4/10 resolve at 43b44a2`, while the same note nine lines earlier said *"Nine of the ten
bound; the tenth did not"*. Both figures were right and they answer different questions, which is the
defect: the block stated no reader and no predicate, so its own numbers could not be reconciled
against each other. A presence control whose reading depends on which predicate you supply, and which
supplies neither, controls nothing.

Three predicates fit the word *resolve*, and they give three different answers over the same ten
rows:

  IDENTICAL  the line at (path, n) is byte-identical at both commits.               2/10 at 43b44a2
  SUBJECT    the line still names what `D-g5-d` pointed at — the same first cell
             for a table row, the same text otherwise.                             4/10 at 43b44a2
  BINDS      one of the guard's blocking patterns fires on the line, so the site
             binds a version to the defect's shape.                                9/10 at a9603e5

`4/10` is SUBJECT. `9/10` is BINDS. `10/10` is either of the first two read at `a9603e5`, where a
citation is compared against itself, so it holds by construction rather than by measurement;
all it establishes is that each of the ten lands on a line that exists. The frame decision the block
exists to justify rests on SUBJECT, because a citation that has stopped naming its subject is the
failure being guarded against; the other two are printed beside it so the number cannot be quoted
without its question.

BINDS delegates to `planning/installed-claim-sweep.py` rather than restating a pattern, so the
predicate cannot drift away from the guard whose classes it names. `G5.md:159` fires `B4` — a version
bound to `installed_plugins.json` — which is the guard's blocking shape rather than a use of the
word; `G5.md:163` fires nothing, and is the tenth.

## The control

A reader that returned all-HIT, or all-MISS, would produce a table that looks exactly like a
measurement. So six synthetic rows go through the same three predicates on every run — each with a
known answer, and each answer required — and the result is printed above the table rather than kept
behind a flag. `--control` runs that half alone.
"""

import importlib.util
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve()
ROOT = HERE.parent.parent

WRITTEN_AT = "a9603e5"   # the frame D-g5-d's citations are stated at
MOVED_TO = "43b44a2"     # the tip they were nearly re-numbered to

CITATIONS = [
    ("ORCHESTRATOR.md", 314),
    ("planning/features-to-triage/LEDGER.md", 67),
    ("planning/features-to-triage/LEDGER.md", 295),
    ("planning/progress/G5.md", 76),
    ("planning/progress/G5.md", 94),
    ("planning/progress/G5.md", 123),
    ("planning/progress/G5.md", 143),
    ("planning/progress/G5.md", 159),
    ("planning/progress/G5.md", 163),
    ("planning/progress/G5-gapfix.md", 22),
]


def _guard():
    spec = importlib.util.spec_from_file_location(
        "installed_claim_sweep", ROOT / "planning" / "installed-claim-sweep.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def line_at(commit, path, n):
    """The nth line of `path` at `commit`, or None if the file has fewer lines."""
    out = subprocess.run(["git", "-C", str(ROOT), "show", "%s:%s" % (commit, path)],
                         capture_output=True, check=True).stdout.decode()
    lines = out.split("\n")
    return lines[n - 1] if n - 1 < len(lines) else None


def first_cell(text):
    """A markdown row's first cell, or None when the line is not a row."""
    if text is None or not text.lstrip().startswith("|"):
        return None
    return text.strip().strip("|").split("|")[0].strip()


def identical(a, b):
    return a is not None and a == b


def subject(a, b):
    """Same subject: the same first cell for a table row, the same text otherwise."""
    if a is None or b is None:
        return False
    ca, cb = first_cell(a), first_cell(b)
    if ca is not None or cb is not None:
        return ca is not None and ca == cb
    return a == b


def binds(guard, text):
    """The guard's blocking patterns that fire on this line. Empty means it binds nothing."""
    if text is None:
        return []
    fired = []
    for kind, name, pat in guard.PATTERNS:
        if kind != "block":
            continue
        if name.startswith("T"):
            hit = bool(re.search(pat, text, re.I))
        else:
            norm, _ = guard._inline_normalise(text)
            hit = bool(re.search(pat, norm, re.I))
        if hit:
            fired.append(name[:2])
    return fired


# (label, text at WRITTEN_AT, text at MOVED_TO, want IDENTICAL, want SUBJECT, want BINDS)
CONTROL = [
    ("unchanged prose", "it reads what the installed 0.9.4 reads", "it reads what the installed 0.9.4 reads", True, True, True),
    ("rewritten prose", "it reads what the installed 0.9.4 reads", "0.9.4 reads", False, False, True),
    ("row, same id", "| G5 | one thing |", "| G5 | another thing |", False, True, False),
    ("row, different id", "| G5 | one thing |", "| G6 | one thing |", False, False, False),
    ("line now blank", "installed 0.9.4 today", "", False, False, True),
    ("line past EOF", "installed 0.9.4 today", None, False, False, True),
]


def control(guard):
    failures = []
    for label, a, b, w_id, w_su, w_bi in CONTROL:
        got = (identical(a, b), subject(a, b), bool(binds(guard, a)))
        want = (w_id, w_su, w_bi)
        if got != want:
            failures.append("%s: got %s want %s" % (label, got, want))
    print("control: %d synthetic row(s) over 3 predicates" % len(CONTROL))
    for f in failures:
        print("  FAIL  %s" % f)
    print("control: %s" % ("held — each predicate answers both ways" if not failures
                           else "%d FAILURE(S)" % len(failures)))
    return 1 if failures else 0


def main():
    guard = _guard()
    rc = control(guard)
    print()
    if "--control" in sys.argv:
        return rc

    print("D-g5-d's ten citations, stated at %s" % WRITTEN_AT)
    print("%-44s  %-9s  %-9s  %s" % ("citation", "IDENTICAL", "SUBJECT", "BINDS"))
    tally = {"identical": 0, "subject": 0, "binds": 0}
    for path, n in CITATIONS:
        a = line_at(WRITTEN_AT, path, n)
        b = line_at(MOVED_TO, path, n)
        i, s, fired = identical(a, b), subject(a, b), binds(guard, a)
        tally["identical"] += i
        tally["subject"] += s
        tally["binds"] += bool(fired)
        print("%-44s  %-9s  %-9s  %s"
              % ("%s:%d" % (path, n), "HIT" if i else "MISS",
                 "HIT" if s else "MISS", ",".join(fired) or "—"))
    n = len(CITATIONS)
    present = sum(1 for path, ln in CITATIONS if line_at(WRITTEN_AT, path, ln) is not None)
    print()
    print("at %s: %d/%d citations land on a line that exists — IDENTICAL and SUBJECT are compared"
          % (WRITTEN_AT, present, n))
    print("       against this frame, so they read 10/10 here by construction rather than by measurement")
    print("at %s: %d/%d IDENTICAL · %d/%d SUBJECT" % (MOVED_TO, tally["identical"], n, tally["subject"], n))
    print("BINDS at %s: %d/%d — the tenth is %s:%d"
          % (WRITTEN_AT, tally["binds"], n, CITATIONS[8][0], CITATIONS[8][1]))
    return rc


if __name__ == "__main__":
    sys.exit(main())
