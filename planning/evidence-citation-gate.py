#!/usr/bin/env python3
"""Fail a campaign record that cites an evidence artifact the REPOSITORY does not hold.

## The defect this exists for

`G24`. `.gitignore:24` was `*.log`, unanchored, and the test campaign writes every run record it
produces as a `.log`. Measured on `main` at `d6e2958`: **42 evidence logs under
`planning/test-campaign/evidence/`, none of them tracked**, and **38 distinct log paths cited as
evidence** across `cases.json`, `inventory.json`, `defects.in.json` and the evidence page. Every
one of those citations resolved on the machine that wrote it and on no other checkout.

It is `G6`'s rule — *an artifact a record cites as evidence is committed, or the record does not
cite it* — one directory in, and it is worse than the `/tmp` citations G6 closed. A `/tmp` path
announces itself as scratch. `evidence/runs/make-test-2.log` names a path inside the repository,
in a directory full of committed siblings, and a reader who checks it on the machine that produced
it finds the file exactly where it was promised.

**Three had already been lost, and nobody noticed.** `ai/g19` merged
`evidence/wire-document/{arming,wire-document}.json` and `witness-socket.txt` while the three
`.log` files beside them stayed behind in `.worktrees/G19`, ignored. Six cases went on citing paths
that existed in one runner's worktree and in no commit anywhere. They were recovered by hand for
this item; the next three would not be.

## Why the working tree is not the frame

The whole failure is that the working tree and the repository disagree, so a check that reads the
working tree measures nothing. `os.path.exists` on the machine that ran the campaign answered
`True` for all 45 logs throughout the entire period in which zero of them were tracked.

So the frame is **`git ls-files` — the index**, which is what a fresh clone receives. The index
rather than `HEAD` because this runs inside `make lint`, ahead of the commit: a file staged and
about to be committed is one the repository is about to hold, and failing it would teach people to
run the gate last. A file merely sitting on disk is in neither.

## What counts as a citation, and why prose does not block

**A structured evidence field is a machine-readable claim that an artifact backs a row.** Those
are the ones that block: any string reached under a key in `EVIDENCE_KEYS` — `cases.json`'s
`evidence[]`, a surface's `shot`, a defect's `source`.

**Prose is not.** `inventory.json`'s DEF-010 text reads *"inventory.json HAD
shot=evidence/shots/SURF-012.ios-boot.png"* — the record of a pointer that was WRONG, whose whole
value is naming the path that no longer applies. Blocking that would demand the history be
rewritten to make a gate green, which is the one move this campaign forbids. So prose is swept,
counted and printed as `PROSE_UNRESOLVED` rather than dropped in silence, and the number is the
visible size of what this gate does not adjudicate.

That split was measured, not assumed. Over the whole tracked campaign corpus the prose reading
returns 30 unresolved paths and the structured reading 4; of the 30, three were `planning/evidence/`
records this reader had mis-rooted (see below) and the rest are historical.

## The extractor's own defect, found by running it

The first version matched `(?:planning/test-campaign/)?evidence/…` and re-rooted every hit at the
campaign directory. `planning/evidence/I5-transport-proof.md` — a real, tracked file one directory
up — was chopped to `evidence/I5-transport-proof.md` and reported `MISSING` in five registries at
once. Three of the first run's ten distinct findings were that one fault. A path token is therefore
taken **whole**, with a lookbehind that refuses a partial segment, and rooted by what it starts
with: `planning/…` is repo-relative, a bare `evidence/…` is campaign-relative.

## The classes, and which of them block

Every structured citation lands in exactly one, so the column sums to the population:

  TRACKED     in the index. A fresh clone gets it.
  UNTRACKED   not in the index, but on disk here. **BLOCKS, with no carry, ever.** `G24`'s exact
              shape, and the one that passes silently for whoever is looking at it.
  MISSING     in neither. **BLOCKS.** Louder — it fails for its author too — but the same remedy.
  WITHDRAWN   carries `foreign-path-gate`'s marker vocabulary — `(not retained)`, `(gone)`,
              `(unrecoverable)` — so it is a record saying the artifact is absent rather than a
              claim that it is present. Counted, never blocked. Reusing that vocabulary rather
              than inventing a second spelling for the same withdrawal.
  CARRIED     declared in `planning/evidence-citation-carry.json` with a reason and an owner.

## Why a carry file, and why it can only shrink

`registry-drop-gate.py`'s argument, restated: *a gate that lands permanently red is a gate somebody
switches off within a week.* Landing this one found four unresolvable citations that are not `G24`'s
axis and not `G24`'s to rewrite — two iOS captures a surface re-attribution renamed, and two
`UNATTRIBUTED.*.png` named in a defect's `source` with their shas. Narrowing the gate until they
disappeared would be `G8` — the too-narrow sweep that returns a confident zero — so they are
declared instead, by path, with who owns each.

The carry is a floor, not a licence. **A carried path that now resolves is a finding**, because a
carry entry outliving its defect is how a waiver list turns into a place things go to be forgotten.
And `UNTRACKED` is never carryable at all: it is the class this item exists for, and it is at 0.

## The corpus, stated because a narrow scope is this fleet's live defect (`G8`)

Every **tracked** `.json` under `planning/test-campaign/` that is not itself an evidence artifact —
discovered from `git ls-files`, not from a hand-written list, so the next registry somebody adds is
in the denominator on the day they add it. Evidence artifacts are excluded from the *citing* side
(a capture manifest naming the captures it wrote is provenance, not a claim) and are of course
still the *cited* set. `bin/` scripts are excluded for the same reason: a writer naming its own
output path is saying where the file goes, not that it is there.

`evidence.html` is generated from these registries, so a defect in it is a defect here. It is swept
on the prose side and printed, which costs a duplicate line rather than a missed one.

## The control, run on every invocation

Hermetic, in `citation-gate.py`'s idiom, because a gate whose passing and whose blindness look
identical is not evidence. `--control` builds a throwaway git repository, plants one citation per
class plus a stale carry entry, runs the real classifier over it and requires each planted answer
exactly. Two arms carry the weight:

  * **UNTRACKED** — its artifact IS written to disk in the control repo, so a classifier that
    consulted the filesystem answers `TRACKED` and the control fails. That is the whole of `G24`
    reproduced in a temp directory.
  * **stale carry** — a carried path that is tracked must be reported, or the carry file is a
    one-way valve.

The withdrawal window is same-line, and the control's `MISSING` and `WITHDRAWN` rows sit adjacent
so a re-widening trips it. That rule is not fastidiousness: with a flat 120-character window the
first run's `(not retained)` reached back past a newline and withdrew the `MISSING` row above it,
turning a blocking finding into a counted one. The control caught it.

Exit codes: 0 clean, 1 a citation the repository cannot honour or a stale carry, 2 the control
failed or the corpus was empty.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from input_accounting import Tally  # noqa: E402  — the sys.path line above has to come first

ROOT = Path(__file__).resolve().parent.parent
CAMPAIGN = "planning/test-campaign"
EVIDENCE = CAMPAIGN + "/evidence"
CARRY = "planning/evidence-citation-carry.json"

# Keys whose string values are a claim that an artifact backs the row. Prose keys — `note`, `text`,
# `armedBy` — are deliberately absent; see the docstring on why they are swept and not blocked.
EVIDENCE_KEYS = frozenset({"evidence", "shot", "shots", "source", "artifact", "capture"})

# A path token taken WHOLE. The lookbehind refuses a partial segment, which is what turned
# `planning/evidence/I5-transport-proof.md` into a phantom `MISSING` in the first run.
CITATION = re.compile(
    r"(?<![A-Za-z0-9._/-])((?:planning/[A-Za-z0-9._-]+/)*)"
    r"(evidence/[A-Za-z0-9._][A-Za-z0-9._/-]*\.[A-Za-z0-9]+)")

# `foreign-path-gate.py`'s marker vocabulary, deliberately not a second one. A marker this many
# characters after the citation, ON THE SAME LINE, withdraws it — see the docstring for the leak
# the same-line rule closed.
WITHDRAW = re.compile(r"\((?:gone|unrecoverable|not retained|does not exist|reconstructed[^)]*)\)")
WITHDRAW_WINDOW = 120

CLASSES = ("TRACKED", "CARRIED", "WITHDRAWN", "UNTRACKED", "MISSING")
BLOCKING = ("UNTRACKED", "MISSING")
NEVER_CARRIED = ("UNTRACKED",)


def root_path(match) -> str:
    """Repo-relative path for one match. `planning/…` is already rooted; a bare `evidence/…` is
    relative to the campaign directory, which is how every registry spells it."""
    prefix, tail = match.group(1), match.group(2)
    return (prefix + tail) if prefix else (CAMPAIGN + "/" + tail)


def tracked_set(root: Path) -> set:
    """Every path in the index. Not `HEAD` — see the docstring on why the index is the frame.

    Nothing is discarded here beyond `-z`'s trailing terminator, and that is removed by position
    rather than filtered out, so this reader has no unaccounted drop for `reader-accounting.py` to
    find. `git ls-files -z` TERMINATES every path, so the final field is always empty and its
    absence would mean the output was truncated.
    """
    out = subprocess.run(["git", "-C", str(root), "ls-files", "-z"],
                         capture_output=True, check=True).stdout.decode()
    fields = out.split("\0")
    if fields and fields[-1] == "":
        fields.pop()
    return set(fields)


def carried_set(root: Path):
    """The declared carry, as {path: reason}. An absent file is an empty carry, not an error."""
    full = root / CARRY
    if not full.exists():
        return {}
    doc = json.loads(full.read_text(encoding="utf-8"))
    return {row["path"]: row.get("reason", "") for row in doc.get("carried", [])}


def registries(root: Path, tracked: set):
    """The tracked campaign registries, parsed. Returns (rows, tally) — the tally is returned so
    the caller owns one accounting line, which is `reader-accounting.py`'s contract."""
    tally = Tally("campaign registries", CAMPAIGN)
    rows = []
    for path in sorted(p for p in tracked if p.startswith(CAMPAIGN + "/")):
        if path.startswith(EVIDENCE + "/"):
            tally.drop(path, "an evidence artifact — its own paths are provenance, not citations")
            continue
        if path.startswith(CAMPAIGN + "/bin/"):
            tally.drop(path, "a writer naming where it puts its output, not a record citing it")
            continue
        if not path.endswith(".json"):
            tally.drop(path, "not a registry; swept for prose instead")
            continue
        try:
            doc = json.loads((root / path).read_text(encoding="utf-8"))
        except (ValueError, UnicodeDecodeError, OSError) as exc:
            tally.drop(path, f"unparseable as JSON ({type(exc).__name__})")
            continue
        rows.append((path, doc))
        tally.keep(path)
    return rows, tally


def structured_citations(rows):
    """Every evidence path reached under an EVIDENCE_KEYS key, with the string it came from."""
    out = []

    def walk(node, key, path):
        if isinstance(node, dict):
            for k, v in node.items():
                walk(v, k, path)
        elif isinstance(node, list):
            for v in node:
                walk(v, key, path)
        elif isinstance(node, str) and key in EVIDENCE_KEYS:
            for m in CITATION.finditer(node):
                out.append((path, root_path(m), node[m.end():]))

    for path, doc in rows:
        walk(doc, None, path)
    return out


def classify(cited: str, tail: str, tracked: set, carried: dict, root: Path) -> str:
    if WITHDRAW.search(tail.split("\n", 1)[0][:WITHDRAW_WINDOW]):
        return "WITHDRAWN"
    if cited in tracked:
        return "TRACKED"
    # Deliberately the LAST question asked, and only to tell the two failures apart. A classifier
    # that asked it first would answer TRACKED for the whole of G24, on the machine that caused it.
    on_disk = (root / cited).exists()
    cls = "UNTRACKED" if on_disk else "MISSING"
    if cls not in NEVER_CARRIED and cited in carried:
        return "CARRIED"
    return cls


def scan(root: Path, tracked: set, carried: dict):
    rows, tally = registries(root, tracked)
    cites = structured_citations(rows)
    return [(path, cited, classify(cited, tail, tracked, carried, root))
            for path, cited, tail in cites], tally


def prose_sweep(root: Path, tracked: set):
    """Every evidence path in a tracked campaign file that is NOT a structured claim. Counted and
    printed, never blocking — the visible size of what this gate declines to adjudicate."""
    tally = Tally("prose sweep", CAMPAIGN)
    unresolved = set()
    for path in sorted(p for p in tracked if p.startswith(CAMPAIGN + "/")):
        if path.startswith(EVIDENCE + "/"):
            tally.drop(path, "an evidence artifact")
            continue
        try:
            text = (root / path).read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            tally.drop(path, "unreadable as text")
            continue
        tally.keep(path)
        for m in CITATION.finditer(text):
            cited = root_path(m)
            if cited not in tracked:
                unresolved.add(cited)
    return unresolved, tally


# ------------------------------------------------------------------------------------- the control

# (cited path, written to disk, added to the index, carried, citing JSON, expected class)
CONTROL_PLANTS = (
    ("evidence/runs/committed.log", True, True, False, "TRACKED"),
    ("evidence/runs/on-disk-only.log", True, False, False, "UNTRACKED"),
    ("evidence/runs/never-written.log", False, False, False, "MISSING"),
    ("evidence/runs/withdrawn.log", False, False, False, "WITHDRAWN"),
    ("evidence/runs/declared.log", False, False, True, "CARRIED"),
)


def control() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        subprocess.run(["git", "-C", tmp, "init", "-q"], check=True)
        (root / EVIDENCE / "runs").mkdir(parents=True)
        (root / "planning").mkdir(exist_ok=True)

        cases, carry = [], []
        for cited, on_disk, add, carried, _ in CONTROL_PLANTS:
            if on_disk:
                (root / CAMPAIGN / cited).write_text("planted\n", encoding="utf-8")
            if add:
                subprocess.run(["git", "-C", tmp, "add", "-f", CAMPAIGN + "/" + cited], check=True)
            if carried:
                carry.append({"path": CAMPAIGN + "/" + cited, "reason": "planted by the control"})
            marker = " (not retained)" if cited.endswith("withdrawn.log") else ""
            cases.append({"id": cited, "evidence": [cited + marker]})
        # The stale arm: a path that IS in the index and is carried anyway. A carry file that never
        # reports its own obsolete rows is a one-way valve.
        carry.append({"path": CAMPAIGN + "/evidence/runs/committed.log",
                      "reason": "planted stale by the control"})

        (root / CARRY).write_text(json.dumps({"carried": carry}), encoding="utf-8")
        (root / CAMPAIGN / "cases.json").write_text(json.dumps(cases), encoding="utf-8")
        subprocess.run(["git", "-C", tmp, "add", "-f", CAMPAIGN + "/cases.json"], check=True)

        tracked = tracked_set(root)
        carried = carried_set(root)
        rows, tally = scan(root, tracked, carried)
        got = {cited: cls for _, cited, cls in rows}
        want = {CAMPAIGN + "/" + c: e for c, _, _, _, e in CONTROL_PLANTS}
        bad = [(c, want[c], got.get(c, "NOT FOUND")) for c in sorted(want) if got.get(c) != want[c]]
        stale = sorted(p for p in carried if p in tracked)

        print("control: %d citation(s) planted, one per class of %d, plus one stale carry"
              % (len(want), len(CLASSES)))
        if tally.measured_nothing():
            print("control FAILED — the citing corpus was empty, so nothing was classified")
            return 2
        for cited, expect, actual in bad:
            print("  MISBEHAVED  %-46s expected %-9s got %s" % (cited, expect, actual))
        if not stale:
            print("  MISBEHAVED  the planted stale carry entry was not reported")
        if bad or not stale:
            print("control FAILED — this instrument cannot see the defect it is placed for.")
            print("  UNTRACKED is the arm that matters: its artifact IS on disk in the control")
            print("  repo, so a classifier that reads the filesystem answers TRACKED.")
            return 2
        print("control HELD — committed reads TRACKED, on-disk-but-never-added reads UNTRACKED,")
        print("  never-written reads MISSING, `(not retained)` reads WITHDRAWN, a declared path")
        print("  reads CARRIED, and a carry entry for a tracked path is reported as stale.")
        return 0


def main(argv) -> int:
    rc = control()
    print()
    if "--control" in argv:
        return rc
    if rc != 0:
        return rc

    tracked = tracked_set(ROOT)
    carried = carried_set(ROOT)
    rows, tally = scan(ROOT, tracked, carried)
    unresolved_prose, prose_tally = prose_sweep(ROOT, tracked)
    print(tally.line())
    print(prose_tally.line())

    if tally.measured_nothing():
        print("INCONCLUSIVE — no tracked campaign registry was read, so nothing was checked.")
        return 2

    counts = {c: 0 for c in CLASSES}
    for _, _, cls in rows:
        counts[cls] += 1
    distinct = {cited for _, cited, _ in rows}
    print("structured citations: %d occurrence(s) over %d distinct evidence path(s)"
          % (len(rows), len(distinct)))
    for cls in CLASSES:
        print("  %-11s %5d%s" % (cls, counts[cls], "  BLOCKS" if cls in BLOCKING else ""))
    print("  prose paths that resolve nowhere: %d — counted, never blocked, and this number is"
          % len(unresolved_prose))
    print("  the visible size of what this gate declines to adjudicate.")

    findings = sorted({(cited, cls, path) for path, cited, cls in rows if cls in BLOCKING})
    stale = sorted(p for p in carried if p in tracked)

    if not findings and not stale:
        print("\nPASS — every evidence path a campaign record claims is one the repository holds;")
        print("  %d carried, each named in %s." % (len(carried), CARRY))
        return 0

    if findings:
        print("\nFINDINGS evidence-citation: %d" % len(findings))
        for cited, cls, path in findings:
            why = ("on this machine and in no commit — a fresh clone gets nothing"
                   if cls == "UNTRACKED" else "named by a record and written nowhere")
            print("  * %s cites %s: %s (%s)" % (path, cited, cls, why))
        print("\n  Commit the artifact; or stop citing it and mark the citation `(not retained)`;")
        print("  or, if it is somebody else's item, declare it in %s with an owner." % CARRY)
        print("  UNTRACKED is never carryable — it is the class this gate exists for.")
        print("  `.gitignore` exempts %s/**/*.log; an artifact under" % EVIDENCE)
        print("  any other ignore pattern needs its own exemption before `git add` will take it.")
    if stale:
        print("\nSTALE CARRY: %d" % len(stale))
        for p in stale:
            print("  * %s now resolves — remove its row from %s." % (p, CARRY))
        print("  A carry that never sheds a row is a place defects go to be forgotten.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
