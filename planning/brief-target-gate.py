#!/usr/bin/env python3
"""A brief must name what in the registry would settle it, and every name it writes must resolve.

## The defect this exists for

`J1`. Measured by `reckon 1.7.0` over this repository on 2026-08-29, and re-measured on this
branch before a line of this file was written: **42 of 187 briefs (22.5%) join the registry at
all.** Every join edge `reckon` holds is a CITATION — a registry id somebody typed. Not one of the
82 `unjoined` briefs cites any id the registry holds, and the strongest textual near-miss anywhere
in that set scores 0.154, nowhere near the 0.18 threshold at which an overlap edge is even
proposed. So this is not an inference doing badly. **It is a channel that 145 briefs never wrote
to.**

Below a 50% join `reckon` sets `join.weak` and withholds retirement across the board, so at this
rate no brief can leave the remaining set however much ships. The consequence is the one that
matters to a reader: the remaining-work total cannot fall, and `unjoined` — "nobody has looked at
this" — is indistinguishable from "this shipped and nothing recorded it".

The same channel fails a second way, and it is one finding rather than two. **Nothing checks that a
citation resolves.** `reckon` reads a cited id the registry does not hold as evidence of ABSENCE —
class `unbuilt`, product work, "somebody wrote down what should exist and it is not there". That
reading is right for a citation somebody meant. It also means a typo, and an id belonging to
another project, are both reported as findings about this product.

## What this gate does NOT do, said first because it is the load-bearing constraint

It does not write citations into briefs, and nothing here has an `--apply`. A citation written in
bulk to satisfy a tool is the failure `reckon` names at its own `backed_by` guard and the failure
`shipped-brief-gate` names at its own: it moved one project's join from 6.2% to 100% while both
gates still exited 0. **Raising the number is not the goal; making the number mean something is.**

So this gate catches an uncitable brief when it is WRITTEN, and it holds the existing backlog at a
floor that may only fall. The 145 undeclared briefs stay undeclared and stay counted, visibly.

## The channel, and why it is this one rather than a new one

`reckon.read_briefs` parses a brief's frontmatter and takes `reckon-sources` / `sources` /
`source`, in that precedence, as `source_ids`; `reckon.build_join` unions those straight into the
cited set at **confidence 1.0** (reckon.py:594). Frontmatter is stripped from the body before the
prose id scan, so the two channels never double-count.

That is an existing, machine-readable slot in the tool that consumes these briefs, and inventing a
second one would produce a field this gate is happy about and `reckon` cannot see. The
`reckon`-agreement arm of the control exists so that claim is measured rather than asserted: it
builds a two-brief fixture queue against the REAL campaign registry, runs `reckon` over it, and
fails unless the declared brief carries a `cited` edge and the bare one lands `unjoined`.

## The classes, and which of them block

A partition over every brief `reckon` would count. Precedence is fixed and stated, because a brief
answering to two classes must answer to exactly one:

  BROKEN_TARGET  the frontmatter channel names an id NO registry holds. **BLOCKS, floor 0.**
                 First in precedence, ahead of every excuse: a dead link somebody wrote on purpose
                 is worse than no link, because `reckon` reports it as a finding about the product.
                 Held at zero rather than ratcheted because the channel is new — measured across
                 all 192 brief files on disk, ZERO carry any of the three keys today, so there is
                 no legacy debt in it and a floor above zero would be an amnesty for a defect that
                 does not exist yet.
  WAIVED         the brief declares a terminal status in `reckon.WAIVED_DECLARED`. `reckon` has
                 already taken it off the total, so demanding a target would be demanding evidence
                 for work nobody is going to schedule.
  DECLARED       the frontmatter channel names >=1 id and every one of them resolves.
  PROSE_CITED    no frontmatter channel; the body cites >=1 resolving id outside a fence, an HTML
                 comment and a struck-through span. `reckon` will make the same edge from the same
                 text, so demanding the field as well would be demanding a form rather than a join.
  NO_TARGET      the brief declares `registry-target: none` AND a reason of substance. Counted,
                 never blocked. This is the second acceptance clause of the brief and it is a
                 DIFFERENT FACT from `unjoined`: somebody read this and recorded that no evidence
                 exists for it yet, which a reader can act on.
  FOREIGN_ONLY   no frontmatter channel; every id in the prose belongs to a registry declared
                 foreign by `target-resolution-gate`. Reported, not blocked — see below.
  ABSENT_ONLY    no frontmatter channel; the prose ids resolve to nothing and none is declared
                 foreign. Reported, not blocked: this is `target-resolution-gate`'s `ID_ABSENT`,
                 which already blocks it. Two gates blocking one token is how two vocabularies
                 come to disagree about one word.
  UNDECLARED     names nothing. **BLOCKS above its per-file floor**, which is what makes a NEW
                 brief blocking and the 145 existing ones a backlog with a number on it.

## FOREIGN_ONLY is reported rather than blocked, and the reason is a real disagreement

`target-resolution-gate` declares `DEF-252`, `DEF-253` and `REQ-999` foreign — another project's
registry, cited here as prior art — and passes them at severity 0. `reckon` has no such vocabulary.
`G9`'s brief names `egress`'s `DEF-253` twice, and that is the whole of the reckoning's
`unbuilt` class: **one row, one piece of "product work", resting on a defect id belonging to a
different repository.**

Blocking it would demand the brief be edited, and the only edits `reckon` respects are fencing the
token — mangling a record's prose to satisfy a tool — or adding a target the brief may not have.
Both are worse than the disagreement. So the class is named, counted and printed with the
instrument that disagrees, which is the reporting clause of the brief's acceptance sketch and not
a repair of it.

## The correspondence, measured rather than argued — `--agree`

Run over the real queue on this branch, this gate's partition and `reckon`'s land on each other
exactly, 187 briefs, no residue in either direction:

    UNDECLARED    -> unjoined       82        FOREIGN_ONLY  -> unbuilt         2
    WAIVED        -> waived         68        PROSE_CITED   -> undecided       2
    PROSE_CITED   -> broken         23
    PROSE_CITED   -> unmeasured     10

Two things follow, and neither is a restatement of the other. **`UNDECLARED` IS the remaining
decision-work backlog**, file for file — so the floor below is not a proxy for the reckoning's 82
`unjoined` rows, it is those rows, and every entry that leaves it takes one off the total. And
**the whole of `reckon`'s `unbuilt` class — its only claim of "named in a brief; nothing in the
registry answers to it" — is `egress`'s `DEF-253`**, twice. Not one row of that product work is
about this product.

`--agree` is out of `make lint` because it runs `reckon` over every brief. It is what keeps the
paragraph above a measurement somebody can re-take.

## The floor, and why it is per file

The corpus carries 145 briefs written before any of this existed. A gate demanding they all gain
targets this week either never goes green or gets softened until it means nothing —
`citation-gate`'s argument, and `sweep-control-gate`'s, over the same corpus.

So `UNDECLARED` is held against `planning/brief-target-ratchet.json` and may only fall. Per citing
file rather than in total, for `citation-gate`'s reason restated: a scalar lets one brief gaining a
target buy headroom for a new brief that names nothing. **A file with no floor entry has a floor of
zero**, so a brief written after this lands blocks until it declares something — which is the whole
mechanism, and the only part of it that touches a runner writing a brief tomorrow.

Writing the floor is `--set-floor`, never a side effect of checking. A gate that mutates the tree
cannot be run between two merges (`registry-drop-gate`, 2026-08-27).

## The corpus

The git INDEX, `git ls-files` under `planning/features-to-triage/`, filtered by `reckon`'s own
discovery rules: `.md` only, dot-directories skipped, and the four reserved basename prefixes
(`BRIEF-TEMPLATE`, `README`, `00-INDEX`, `LEDGER`) excluded.

The index rather than the working tree, following `evidence-citation-gate` (`G24`) and
`target-resolution-gate`: this runs inside `make lint` ahead of the commit, so a staged brief is
caught before it lands, while another session's untracked scratch cannot redden a shared branch —
the harm `reader-accounting.py` measured when its first cut walked the working directory. **Briefs
on disk and not in the index are counted and named rather than passed over in silence**, because a
population this gate did not read is a blind spot and not a scope.

## Exit codes

0 clean · 1 a blocking class over its floor · 2 the control did not fire, because a zero from an
instrument that has not been shown to fire is not evidence.

  python3 planning/brief-target-gate.py              # the gate
  python3 planning/brief-target-gate.py --control    # the planted arms only
  python3 planning/brief-target-gate.py --set-floor  # write the backlog floor, deliberately
"""
from __future__ import annotations  # the gates run under /usr/bin/python3; `X | None` is 3.10+

import argparse
import importlib.util
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve()
ROOT = HERE.parent.parent
BRIEFS_REL = "planning/features-to-triage"
FLOOR = ROOT / "planning" / "brief-target-ratchet.json"

sys.path.insert(0, str(HERE.parent))
from input_accounting import Tally  # noqa: E402  — the drop contract, not an optional import


def _sibling(name: str):
    """Import a sibling gate by path. The filenames carry hyphens, so `import` cannot reach them,
    and copying the vocabulary instead is how two gates come to disagree about one word."""
    spec = importlib.util.spec_from_file_location(
        name.replace("-", "_"), str(HERE.parent / (name + ".py")))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


TRG = _sibling("target-resolution-gate")
registry_ids = TRG.registry_ids          # the union of every registry that holds an id
retirements = TRG.retirements            # `registry-drop-gate`'s declared retirements
FOREIGN_IDS = TRG.FOREIGN_IDS            # ids belonging to another project, named with evidence

# ---------------------------------------------------------------------------------------------
# `reckon` 1.7.0's own vocabulary, reproduced with the line it comes from so a version bump that
# moves it is findable. Reproduced rather than imported: `reckon` is a plugin in the machine's
# cache, not a vendored dependency, and a gate in `make lint` that cannot run without a cache hit
# is a gate that goes red on a clean checkout. The `--control`'s agreement arm is what checks that
# this copy still matches the original.
RECKON_VERSION = "1.7.0"
SOURCE_KEYS = ("reckon-sources", "sources", "source")            # reckon.py:349, in precedence
WAIVED_DECLARED = ("waived", "deferred", "wontfix", "won't fix", "declined", "out of scope",
                   "retired", "completed", "consumed", "scaffolded", "historical")  # reckon.py:58
RESERVED_PREFIXES = ("BRIEF-TEMPLATE", "README", "00-INDEX", "LEDGER")              # reckon.py:330
ID_RE = re.compile(r"\b(?:REQ|CASE|DEF|SURF|FLOW|COMP)-\d+\b")                      # reckon.py:388
FRONTMATTER_RE = re.compile(r"\A---\s*\n(.*?)\n---\s*\n", re.S)                     # reckon.py:312
FENCE_RE = re.compile(r"^([ \t]*)(`{3,}|~{3,})[^\n]*\n.*?(?:^\1?\2[^\n]*\n|\Z)", re.M | re.S)
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)
STRIKETHROUGH_RE = re.compile(r"~~[^\n]+?~~")
EXCLUSION_KINDS = (("fenced", FENCE_RE), ("comment", HTML_COMMENT_RE),
                   ("struck", STRIKETHROUGH_RE))

# The explicit "no evidence exists for this yet" declaration. A closed vocabulary of one word, and
# a reason long enough to be a sentence: the escape hatch has to cost the writer the thought, or it
# becomes the cheapest class and the gate has taught people to type `none`.
NO_TARGET_KEY = "registry-target"
NO_TARGET_WORD = "none"
NO_TARGET_REASON_KEY = "no-target-reason"
REASON_FLOOR = 24

CLASSES = ("BROKEN_TARGET", "WAIVED", "DECLARED", "PROSE_CITED", "NO_TARGET",
           "FOREIGN_ONLY", "ABSENT_ONLY", "UNDECLARED")
BLOCKING_AT_ZERO = ("BROKEN_TARGET",)
BLOCKING_RATCHETED = ("UNDECLARED",)
REPORTED = ("FOREIGN_ONLY", "ABSENT_ONLY")

FINDINGS = 1
CONTROL_FAILED = 2


# ---------------------------------------------------------------------------------- reading

def blank_shown(text: str) -> str:
    """`reckon.citable_text`, one direction. The three places a markdown document SHOWS an id
    rather than uses one, blanked rather than deleted so line offsets hold."""
    out = text or ""
    for _, rx in EXCLUSION_KINDS:
        out = rx.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), out)
    return out


def parse_brief(raw: str) -> dict:
    """Frontmatter map and body, split exactly where `reckon` splits them.

    `reckon` strips the frontmatter off `body` before scanning prose for ids, so a target declared
    in the frontmatter reaches the join through `source_ids` and NOT through the prose scan. This
    reader reproduces that split rather than approximating it: read the two channels as one and a
    declared id would be counted twice, which is how a gate comes to report a join `reckon` does
    not make.
    """
    meta: dict = {}
    body = raw
    m = FRONTMATTER_RE.match(raw)
    if m:
        for line in m.group(1).splitlines():
            if ":" not in line:
                continue
            k, _, v = line.partition(":")
            meta[k.strip().lower()] = v.strip().strip("\"'")
        body = raw[m.end():]
    return {"meta": meta, "body": body}


def declared_ids(meta: dict) -> tuple:
    """(ids, blank fields, the key they came from) for the frontmatter channel.

    `reckon.build_join` unions this list into its cited set at confidence 1.0. The blank fields come
    back rather than being filtered away in a comprehension: `reader-accounting.py` classes a
    filtered item as a silent drop by shape, and `reckon-sources: [DEF-001,,]` is a writer who meant
    to name a second target — a fact worth being able to print, not one to swallow.
    """
    raw, key_used = "", None
    for key in SOURCE_KEYS:
        if meta.get(key):
            raw, key_used = meta[key], key
            break
    ids: list = []
    blank: list = []
    for field in raw.strip("[]").split(","):
        if field.strip():
            ids.append(field.strip())
        elif raw:
            blank.append(field)
    return ids, blank, key_used


def discover(root: pathlib.Path) -> tuple:
    """Every brief in the index that `reckon` would count, and everything this reader threw away.

    The discards come back with the corpus rather than being filtered away in a comprehension:
    `reader-accounting.py` classes a filtered item as a silent drop by shape, and the drop here is
    the difference between "this gate read the queue" and "this gate read part of the queue".
    """
    out = subprocess.run(["git", "ls-files", "--", BRIEFS_REL],
                         capture_output=True, text=True, cwd=str(root))
    tally = Tally("brief discovery", "the git index under " + BRIEFS_REL)
    for path in out.stdout.splitlines():
        rel = path[len(BRIEFS_REL) + 1:]
        if not path.endswith(".md"):
            tally.drop(path, "not a .md file")
            continue
        if any(part.startswith(".") for part in rel.split("/")[:-1]):
            tally.drop(path, "under a dot-directory reckon does not walk")
            continue
        if os.path.basename(path).upper().startswith(RESERVED_PREFIXES):
            tally.drop(path, "a reserved basename reckon excludes")
            continue
        tally.keep(path)

    # Named rather than passed over: a brief on disk and not in the index is a brief `reckon`
    # counts and this gate did not read.
    on_disk = set()
    briefs_dir = root / BRIEFS_REL
    if briefs_dir.is_dir():
        for base, dirs, files in os.walk(briefs_dir):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for name in files:
                if not name.endswith(".md") or name.upper().startswith(RESERVED_PREFIXES):
                    continue
                on_disk.add(os.path.relpath(os.path.join(base, name), str(root)))
    untracked = sorted(on_disk - set(tally.kept))
    return tally, untracked


# ------------------------------------------------------------------------------- classifying

def classify(raw: str, known: dict, retired: dict) -> tuple:
    """(class, evidence, detail) for one brief. Precedence is the order of the tests below.

    `detail` carries every id this reader saw, on both sides of every split it made. Nothing is
    filtered away into a comprehension, because a partition whose smaller half vanishes is the
    silent drop `reader-accounting.py` exists for, and here the discarded halves are the findings:
    the prose ids that do NOT resolve are the whole of `FOREIGN_ONLY` and `ABSENT_ONLY`.
    """
    parsed = parse_brief(raw)
    meta, body = parsed["meta"], parsed["body"]

    declared, blank_fields, key_used = declared_ids(meta)
    live: list = []
    unresolved: list = []
    for i in declared:
        (live if (i in known or i in retired or i in FOREIGN_IDS) else unresolved).append(i)

    prose = sorted(set(ID_RE.findall(blank_shown(body))))
    resolving: list = []
    foreign: list = []
    absent: list = []
    for i in prose:
        if i in known or i in retired:
            resolving.append(i)
        elif i in FOREIGN_IDS:
            foreign.append(i)
        else:
            absent.append(i)

    detail = {"declared": declared, "declared_live": live, "declared_unresolved": unresolved,
              "declared_blank_fields": blank_fields, "declared_key": key_used,
              "prose": prose, "prose_resolving": resolving, "prose_foreign": foreign,
              "prose_absent": absent}

    def out(cls, evidence):
        return cls, evidence, detail

    if unresolved:
        return out("BROKEN_TARGET", "declares %s; no registry holds %s"
                   % (", ".join(declared), ", ".join(unresolved)))

    status = (meta.get("status") or "").lower()
    if status in WAIVED_DECLARED:
        return out("WAIVED", "declares status %r — reckon takes it off the total" % status)

    if declared:
        return out("DECLARED", "declares %s, all resolving" % ", ".join(declared))

    if resolving:
        return out("PROSE_CITED", "cites %s in prose" % ", ".join(resolving))

    if meta.get(NO_TARGET_KEY, "").lower() == NO_TARGET_WORD:
        reason = (meta.get(NO_TARGET_REASON_KEY) or "").strip()
        if len(reason) >= REASON_FLOOR:
            return out("NO_TARGET", "no registry target, with a reason: %s" % reason[:60])
        return out("UNDECLARED",
                   "declares `%s: %s` with no reason of substance (%d chars, floor %d)"
                   % (NO_TARGET_KEY, NO_TARGET_WORD, len(reason), REASON_FLOOR))

    if foreign and not absent:
        return out("FOREIGN_ONLY", "every id it cites is another project's: %s"
                   % "; ".join("%s — %s" % (i, FOREIGN_IDS[i]) for i in foreign))
    if absent:
        return out("ABSENT_ONLY", "cites %s, which no registry holds — target-resolution-gate's "
                   "ID_ABSENT arm blocks these" % ", ".join(absent + foreign))

    return out("UNDECLARED", "names nothing the registry could answer to")


# ----------------------------------------------------------------------------------- reckon

def find_reckon() -> tuple:
    """`reckon.py`, or why it could not be found. Never fatal: this gate must run on a checkout
    whose plugin cache is empty, and an arm that could not run is reported as such rather than
    counted as a pass."""
    env = os.environ.get("RECKON_PY")
    if env and os.path.isfile(env):
        return env, "RECKON_PY"
    cache = pathlib.Path.home() / ".claude/plugins/cache/fledgeling-plugins/reckon"
    cand = cache / RECKON_VERSION / "skills/reckon/scripts/reckon.py"
    if cand.is_file():
        return str(cand), "the plugin cache at %s" % RECKON_VERSION
    return None, "no RECKON_PY and no %s in the plugin cache" % RECKON_VERSION


def reckon_classes(reckon_py: str, briefs_dir: str, campaign: str) -> dict:
    """{brief id: class} from a real `reckon build` over a fixture queue and the REAL registry."""
    with tempfile.TemporaryDirectory() as out:
        r = subprocess.run([sys.executable, reckon_py, "build", "--briefs", briefs_dir,
                            "--campaign", campaign, "--out", out],
                           capture_output=True, text=True)
        led = pathlib.Path(out) / "ledger.json"
        if r.returncode != 0 or not led.is_file():
            return {}
        d = json.loads(led.read_text())
    rows = {}
    for row in d.get("rows", []):
        if row.get("entity") == "brief":
            rows[row["id"]] = row.get("class")
    edges = (d.get("join") or {}).get("edges", []) or d.get("edges", [])
    cited = {e["brief"] for e in edges if e.get("method") == "cited"}
    return {"classes": rows, "cited": cited}


# ---------------------------------------------------------------------------------- control

def control(root: pathlib.Path, verbose: bool = True) -> bool:
    """Plant one brief of every class and read them back through the real classifier.

    A zero from an absence sweep that has not been shown to fire is not a measurement — this
    repository has four recorded instances of exactly that (`sweep-control-gate`'s docstring), so
    every class this gate can print has a plant here, and three of the arms are NEGATIVE: a form
    that looks like a declaration and must not count as one.
    """
    known = {"DEF-001": {"defects.in.json"}, "CASE-0184": {"cases.json"}}
    retired = {"DEF-900": "superseded, 2026-08-27"}
    rows, failures = [], []

    def read(raw, want, label, why):
        got, ev, _ = classify(raw, known, retired)
        ok = got == want
        rows.append((label, want, got, ok, why))
        if not ok:
            failures.append("%s: got %s, want %s" % (label, got, want))
        return got

    read("---\nreckon-sources: [DEF-001]\n---\n\n# a brief\n", "DECLARED",
         "declares a resolving id", "the frontmatter channel reckon unions at confidence 1.0")
    read("---\nsources: DEF-001, CASE-0184\n---\n\n# a brief\n", "DECLARED",
         "the `sources` spelling, bare list", "reckon accepts three keys and so must this")
    read("---\nreckon-sources: [DEF-777]\n---\n\n# a brief\n", "BROKEN_TARGET",
         "declares an id no registry holds", "a dead link written on purpose")
    read("---\nreckon-sources: [DEF-001, DEF-777]\n---\n\n# a brief\n", "BROKEN_TARGET",
         "one live target does not excuse a dead one", "BROKEN_TARGET is first in precedence")
    read("---\nstatus: retired\nreckon-sources: [DEF-777]\n---\n\n# a brief\n", "BROKEN_TARGET",
         "NEGATIVE: a terminal status does not excuse a dead link",
         "a waived brief with a dead pointer is still a dead pointer")
    read("---\nstatus: retired\n---\n\n# a brief\n", "WAIVED",
         "a terminal status", "reckon has already taken it off the total")
    read("# a brief\n\nthe failure is DEF-001, measured twice.\n", "PROSE_CITED",
         "a resolving id in prose", "reckon makes the same edge from the same text")
    read("# a brief\n\n```\nsee DEF-001\n```\n", "UNDECLARED",
         "NEGATIVE: the same id inside a fence",
         "reckon blanks fences, so counting it would report a join reckon will not make")
    read("# a brief\n\n<!-- DEF-001 -->\n", "UNDECLARED",
         "NEGATIVE: the same id inside an HTML comment", "reckon blanks comments too")
    read("---\nregistry-target: none\nno-target-reason: nothing in the campaign observes the "
         "installer path yet\n---\n\n# a brief\n", "NO_TARGET",
         "an explicit no-target declaration, with a reason",
         "a recorded absence is a different fact from unjoined")
    read("---\nregistry-target: none\nno-target-reason: n/a\n---\n\n# a brief\n", "UNDECLARED",
         "NEGATIVE: the same declaration with no reason of substance",
         "the escape hatch has to cost a sentence or it becomes the cheapest class")
    read("# a brief\n\negress's DEF-253 shape, swept for here.\n", "FOREIGN_ONLY",
         "every cited id belongs to another project",
         "target-resolution-gate passes these at severity 0; reckon calls them unbuilt")
    read("# a brief\n\nDEF-253 and DEF-001 both.\n", "PROSE_CITED",
         "NEGATIVE: a foreign id beside a resolving one",
         "FOREIGN_ONLY means every id, not any id")
    read("# a brief\n\nREQ-404 is the one.\n", "ABSENT_ONLY",
         "an id in no registry and not declared foreign",
         "target-resolution-gate's ID_ABSENT arm already blocks this one")
    read("# a brief\n\nnothing here names anything.\n", "UNDECLARED",
         "a brief that names nothing", "the class the item exists for")
    read("---\nreckon-sources: [DEF-900]\n---\n\n# a brief\n", "DECLARED",
         "a declared id retired with a reason",
         "registry-drop-gate's retirements are a resolution, not an absence")

    # THE FLOOR MUST BE ABLE TO BLOCK. A ratchet nobody has seen fire is a ratchet nobody knows is
    # wired up, and this one is the whole of the "a new brief is caught" claim.
    over = risen_against({"planning/features-to-triage/new.md": 1},
                         {"planning/features-to-triage/old.md": 1})
    ok = [f for f, _, _ in over] == ["planning/features-to-triage/new.md"]
    rows.append(("a brief with no floor entry is over its floor", "risen",
                 "risen" if ok else "silent", ok, "floor 0 for a file the floor does not name"))
    if not ok:
        failures.append("floor arm: a file absent from the floor did not read as risen")
    under = risen_against({"planning/features-to-triage/old.md": 1},
                          {"planning/features-to-triage/old.md": 1})
    ok = not under
    rows.append(("NEGATIVE: a file at its floor", "silent", "silent" if ok else "risen", ok,
                 "the backlog must not redden while it stands still"))
    if not ok:
        failures.append("floor negative: a file at its floor read as risen")

    # THE AGREEMENT ARM. Everything above is this gate reading its own vocabulary back. This is the
    # only arm that checks the claim the whole item rests on: that the field this gate demands is
    # the field `reckon` joins on.
    reckon_py, how = find_reckon()
    agreement = "NOT RUN — %s" % how
    if reckon_py:
        campaign = str(root / "planning" / "test-campaign")
        target = first_resolving_id(root)
        with tempfile.TemporaryDirectory() as q:
            pathlib.Path(q, "AGREE-01-declared.md").write_text(
                "---\nreckon-sources: [%s]\n---\n\n# a planted brief that declares its target\n\n"
                "Planted by planning/brief-target-gate.py --control.\n" % target)
            pathlib.Path(q, "AGREE-02-bare.md").write_text(
                "# a planted brief that names nothing\n\nPlanted by "
                "planning/brief-target-gate.py --control.\n")
            got = reckon_classes(reckon_py, q, campaign)
        classes, cited = got.get("classes", {}), got.get("cited", set())
        declared_joined = "BRIEF-AGREE-01-declared" in cited
        bare_unjoined = classes.get("BRIEF-AGREE-02-bare") == "unjoined"
        ok = declared_joined and bare_unjoined
        agreement = ("reckon %s: declared -> %s, bare -> %s"
                     % (RECKON_VERSION,
                        "cited edge" if declared_joined else "NO EDGE",
                        classes.get("BRIEF-AGREE-02-bare") or "no row"))
        rows.append(("reckon joins on the field this gate demands", "cited edge ≠ unjoined",
                     "%s ≠ %s" % ("cited" if declared_joined else "none",
                                  classes.get("BRIEF-AGREE-02-bare") or "?"),
                     ok, "the claim the whole item rests on, measured"))
        if not ok:
            failures.append("agreement arm: %s" % agreement)

    if verbose:
        print("PRESENCE CONTROL — planted briefs, read by the real classifier")
        w = max(len(r[0]) for r in rows)
        for label, want, got, ok, why in rows:
            print("  %-*s  expect %-14s got %-14s %-7s %s"
                  % (w, label, want, got, "fired" if ok else "MISSED", why[:58]))
        print("  agreement: %s" % agreement)
        print("  control: %s"
              % ("ALL PLANTS FIRED" if not failures
                 else "%d DID NOT FIRE — the instrument has measured nothing" % len(failures)))
        print()
    return not failures


def first_resolving_id(root: pathlib.Path) -> str:
    """A real registry id for the agreement arm. Reading one out of the registry rather than
    hard-coding it means the arm cannot rot into a plant the registry stopped holding."""
    ids = sorted(registry_ids(str(root)))
    return ids[0] if ids else "DEF-001"


def risen_against(current: dict, floor: dict) -> list:
    """(file, now, floor) for every file over its floor. A file the floor does not name has a
    floor of zero — that is the whole of the "a new brief is caught" mechanism."""
    return sorted((f, n, floor.get(f, 0)) for f, n in current.items() if n > floor.get(f, 0))


# -------------------------------------------------------------------------------------- main

def sweep(root: pathlib.Path) -> dict:
    tally, untracked = discover(root)
    known = registry_ids(str(root))
    retired = retirements(str(root))
    read = Tally("brief reading", "the discovered briefs")
    rows = []
    for path in tally.kept:
        try:
            raw = (root / path).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            read.drop(path, "could not be decoded (%s)" % type(exc).__name__)
            continue
        read.keep(path)
        cls, ev, detail = classify(raw, known, retired)
        rows.append({"file": path, "class": cls, "evidence": ev, "detail": detail})
    return {"discovery": tally, "reading": read, "untracked": untracked,
            "rows": rows, "known": known, "retired": retired}


def by_file(rows, classes) -> dict:
    out: dict = {}
    for r in rows:
        if r["class"] in classes:
            out[r["file"]] = out.get(r["file"], 0) + 1
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=str(ROOT))
    ap.add_argument("--control", action="store_true", help="run only the presence control")
    ap.add_argument("--set-floor", action="store_true",
                    help="write the per-file floor. Never a side effect of checking.")
    ap.add_argument("--quiet", action="store_true", help="counts and verdict only")
    ap.add_argument("--list", metavar="CLASS", default=None,
                    help="print every brief in one class, for a person deciding what to do")
    ap.add_argument("--agree", action="store_true",
                    help="cross-tabulate this gate's classes against reckon's over the REAL queue. "
                         "Out of `make lint` because it runs reckon over every brief; it is how "
                         "the correspondence stays a measurement rather than a claim in a doc.")
    args = ap.parse_args()

    root = pathlib.Path(args.root).resolve()
    if not control(root, verbose=not args.quiet):
        print("REFUSING TO REPORT: the control did not fire, so a zero here means nothing.")
        return CONTROL_FAILED
    if args.control:
        return 0

    s = sweep(root)
    rows = s["rows"]
    if not rows:
        print("REFUSING TO REPORT: no brief was read, so every class below would be a zero over "
              "an empty set.")
        return CONTROL_FAILED

    tally = {c: 0 for c in CLASSES}
    for r in rows:
        tally[r["class"]] += 1

    print("corpus — %s" % s["discovery"].line())
    print("         %s" % s["reading"].line())
    print("  registry read as a union: %d distinct ids, %d declared retired, %d declared foreign"
          % (len(s["known"]), len(s["retired"]), len(FOREIGN_IDS)))
    if s["untracked"]:
        print("  %d brief(s) on disk are NOT in the index and are outside this verdict:"
              % len(s["untracked"]))
        for p in s["untracked"][:10]:
            print("      %s" % p)
        if len(s["untracked"]) > 10:
            print("      … and %d more" % (len(s["untracked"]) - 10))
    print()

    print("HOW EACH BRIEF NAMES ITS TARGET — a partition over %d brief(s)" % len(rows))
    for c in CLASSES:
        mark = ""
        if c in BLOCKING_AT_ZERO:
            mark = "   BLOCKS at 0"
        elif c in BLOCKING_RATCHETED:
            mark = "   BLOCKS above its floor"
        elif c in REPORTED:
            mark = "   reported"
        print("  %-14s %5d%s" % (c, tally[c], mark))
    print("  %-14s %5d" % ("(sum)", sum(tally.values())))
    joined = tally["DECLARED"] + tally["PROSE_CITED"]
    print()
    print("  %d of %d brief(s) (%.1f%%) name something the registry holds. reckon withholds"
          % (joined, len(rows), 100.0 * joined / len(rows)))
    print("  retirement claims below 50%, so that figure is what decides whether shipping can")
    print("  move the remaining-work total at all.")
    print()

    for c in REPORTED:
        hits = [r for r in rows if r["class"] == c]
        if hits:
            print("%s — %d, reported and not blocked" % (c, len(hits)))
            for r in hits:
                print("  %s" % r["file"])
                print("      %s" % r["evidence"])
            print()

    broken = [r for r in rows if r["class"] in BLOCKING_AT_ZERO]
    if broken:
        print("declared targets that name no row — %d" % len(broken))
        for r in broken:
            print("  %s" % r["file"])
            print("      %s" % r["evidence"])
        print()

    if args.agree:
        reckon_py, how = find_reckon()
        if not reckon_py:
            print("--agree: NOT RUN — %s" % how)
        else:
            got = reckon_classes(reckon_py, str(root / BRIEFS_REL),
                                 str(root / "planning" / "test-campaign"))
            theirs = got.get("classes", {})
            mine = {"BRIEF-" + pathlib.Path(r["file"]).stem: r["class"] for r in rows}
            shared = sorted(set(mine) & set(theirs))
            pairs: dict = {}
            for k in shared:
                pairs[(mine[k], theirs[k])] = pairs.get((mine[k], theirs[k]), 0) + 1
            print("AGREEMENT WITH reckon %s over the real queue — %d brief(s) in both"
                  % (RECKON_VERSION, len(shared)))
            print("  %d in this gate's population and not reckon's; %d the other way"
                  % (len(set(mine) - set(theirs)), len(set(theirs) - set(mine))))
            for (a, b), n in sorted(pairs.items(), key=lambda kv: -kv[1]):
                print("  %-14s -> %-14s %5d" % (a, b, n))
            print()

    if args.list:
        want = args.list.upper()
        print("%s — every brief" % want)
        for r in rows:
            if r["class"] == want:
                print("  %s" % r["file"])
        print()

    now = by_file(rows, BLOCKING_RATCHETED)

    if args.set_floor:
        FLOOR.write_text(json.dumps({
            "note": "Briefs that name nothing the registry holds, per FILE. Written by "
                    "planning/brief-target-gate.py --set-floor. Each file's count may only fall, "
                    "and a file the floor does not name has a floor of zero — which is what makes "
                    "a NEW brief blocking while this backlog stands still. Per file rather than in "
                    "total, because a scalar lets one brief gaining a target buy headroom for a "
                    "new brief that names nothing.",
            "blocking": list(BLOCKING_RATCHETED),
            "total": len(now),
            "by_file": dict(sorted(now.items())),
        }, indent=2) + "\n")
        print("floor: written — %d undeclared brief(s)" % len(now))
        return 0

    rc = 0
    if not FLOOR.exists():
        print("floor: no baseline at %s — run --set-floor to set one"
              % FLOOR.relative_to(ROOT))
    else:
        base = json.loads(FLOOR.read_text())
        risen = risen_against(now, base.get("by_file", {}))
        if risen:
            rc = FINDINGS
            print("floor: %d brief(s) name nothing and are not in the backlog:" % len(risen))
            for f, n, was in risen:
                print("  %s  %d, floor %d" % (f, n, was))
            print("  Declare what in the registry would settle it:")
            print("      reckon-sources: [DEF-nnn, CASE-nnnn]")
            print("  or record that nothing does yet, which is a different fact and readable as one:")
            print("      registry-target: none")
            print("      no-target-reason: <why no evidence exists for this yet>")
        fell = sum(1 for f, was in base.get("by_file", {}).items() if now.get(f, 0) < was)
        print("floor: %d undeclared over %d file(s) against floor %d — %d above, %d below%s"
              % (sum(now.values()), len(now), base.get("total", 0), len(risen), fell,
                 "; re-run --set-floor to lower it" if fell and not risen else ""))

    if tally["BROKEN_TARGET"]:
        rc = FINDINGS
        print("BROKEN_TARGET is held at zero: %d declared target(s) name no row."
              % tally["BROKEN_TARGET"])

    print("exit: %d" % rc)
    return rc


if __name__ == "__main__":
    sys.exit(main())
