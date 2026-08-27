#!/usr/bin/env python3
"""Fail a record whose citation names a target this repository no longer holds.

## The defect this exists for

`G7`, third axis. A citation is *inside* the repository and *falsifiable in form*, and still does
not resolve to what it names — because the file moved, the file was deleted, or the id was
renumbered. The pointer was true where it was written and is false where it is read, which is the
one failure mode a reader cannot distinguish from evidence that was never gathered.

`G7`'s own brief is the specimen. It cites `planning/verification/G5-gapfix-3-sweep.py` as one of
two *"committed examples of the reader it would need"*, and that file is in no commit reachable
from `HEAD`. `G8`'s brief cites it too. The claim is not merely stale — it is a claim about
committedness, made about a path the repository does not hold.

## Why this is not one of the three gates that already run

Each of the three asks a different question, and none of them asks this one:

  `planning/citation-gate.py`      does a STATED FRAME hold — is the anchor at the cited line at
                                   the cited tree. It reads `path:line` only, and a citation whose
                                   path is not tracked is DROPPED from its checkable set rather
                                   than classified: 65 of them at the run this landed against.
                                   Those 65 are the top of this gate's population.
  `planning/foreign-path-gate.py`  does the artifact survive at all — for paths rooted at a SCRATCH
                                   root, which is outside the repository by construction. This gate
                                   is its complement: the same question for paths rooted INSIDE it.
  `planning/evidence-citation-gate.py`
                                   is a path named in a campaign record's STRUCTURED evidence field
                                   in the git index. Machine-readable claims in JSON, not prose.

So this is `foreign-path-gate`'s question over the other half of the path space, plus the id half
that no gate reads. Its withdrawal vocabulary is IMPORTED from `foreign-path-gate` rather than
respelled, for the reason `evidence-citation-gate` gives: one spelling of "the record says this is
gone", or the two drift and a writer has to guess which gate they are satisfying.

Its retirement vocabulary is `registry-drop-gate`'s `planning/registry-retirements.json`, for the
same reason. That file was cited by the LEDGER and had never existed — one of this gate's own
findings — and landing it is what makes the `ID_RETIRED` class reachable.

## The two arms

**Paths.** A backticked token rooted at a real top-level directory of this tree, carrying a file
extension, optionally with `:line`. Rooted, because a bare basename (`settings.json`, `CLAUDE.md`)
names something in a described system as often as it names a file here, and a gate that cannot tell
those apart reports a number without measuring anything.

**Ids.** A campaign id — `CASE-nnnn`, `REQ-nnn`, `SURF-nnn`, `DEF-nnn`, `FLOW-nnn`, `COMP-nnn` —
resolved against the UNION of every registry that holds ids: `cases.json`, the four `*.in.json`
seeds, and every kind inside `inventory.json`. The union is deliberate and it is the whole of this
arm's renumber tolerance; see below.

## The classes, and which of them block

Paths, in precedence order. The order is fixed and stated because the set is a partition and a
token that would answer to two classes must answer to exactly one:

  SUBJECT    inside a fenced block, or carrying an elided segment (`.../`). A value, not a
             pointer — `foreign-path-gate`'s discriminator, imported.
  RESOLVES   the path is in the tree at HEAD.
  FRAMED     not at HEAD; the citation names a tree and the path IS in that tree. **Not a defect.**
             This is `M16`'s form doing the work it was adopted for, and it is how a rename is
             absorbed without touching a historical record.
  WITHDRAWN  the record says the target is gone — `foreign-path-gate`'s marker, or an adjacent
             denial clause (see DENIAL). A record may keep a dead pointer if it says so.
  PLANNED    a plan or a spec naming a path under a work verb — `Create`, `Delete`, `New`.
             A plan states intent; it does not claim presence.
  MOVED      not at HEAD, was in history, and git names a rename successor. **BLOCKS.**
  DELETED    not at HEAD, was in history, no successor. **BLOCKS.**
  PHANTOM    in no commit reachable from any ref. **BLOCKS.** The worst of the three: there is no
             tree at which this citation was ever true, so no frame can repair it.

Ids:

  ID_RESOLVES  a row with that id exists in some registry.
  ID_RETIRED   declared in `planning/registry-retirements.json` with a reason.
  ID_FOREIGN   the id belongs to a namespace declared foreign — another project's registry, the
               vendored skill's own examples, the superseded paper campaign. Counted, never blocked.
  ID_ABSENT    none of the above. **BLOCKS.**

## How a legitimate renumber survives, and why that decided the design

This repository renumbers routinely: on 2026-08-27 alone, `G16`'s work was refiled as `DEF-059`,
`G19`'s as `SURF-027` and `G17`'s as `CASE-0184..0194`. A gate that reddens on a legitimate
renumber is a gate somebody switches off within a week, so the tolerance is structural rather than
a waiver list:

1. **The registries are read as a union, never as one file.** All three of today's renumbers are
   silent here, and they are silent for a reason that is checked rather than hoped for: the old
   ledger rows were kept and the new campaign rows were added, so BOTH ids resolve. Measured:
   `DEF-059` and `SURF-027` are in `inventory.json` and in NEITHER `defects.in.json` nor
   `surfaces.in.json`. A gate reading the seed registries alone would have blocked 55 cited ids on
   the day the refiling landed.
2. **A tree absorbs a rename with no registry at all.** A path citation carrying a SHA reads
   `FRAMED` forever, whatever happens to the path afterwards. That is the `M16` form, already the
   house rule, and it costs no new file.
3. **What is left is a renumber that deletes the old id from everywhere and names no successor** —
   and that is not a legitimate renumber, it is `registry-drop-gate`'s undeclared drop arriving one
   layer along. `registry-retirements.json` is where it is declared, and the same declaration
   satisfies both gates.

The negative control holds this: a planted renumber that keeps the old row must leave the gate
silent, and the run fails if it fires.

## The floor, and why it is per citing file

The corpus carries a backlog of dead pointers written before any of this existed. A gate demanding
they all be repaired at once either never goes green or gets softened until it means nothing, so
the blocking count is held against `planning/target-resolution-ratchet.json` and **may only fall**.

Per citing file, not in total — `citation-gate`'s argument, restated because it applies unchanged:
a scalar count lets a deletion in one file buy headroom for a brand-new dead citation in another,
so the defect spreads while the number holds.

Writing the floor is `--set-floor`, never a side effect of checking. A gate that mutates the
working tree cannot be run between two merges, and between two merges is where it earns its keep
(`registry-drop-gate`, 2026-08-27).

## The corpus, stated because a narrow scope is this fleet's live defect (`G8`)

**The git INDEX** — `git ls-files`, read from disk. Hand-written `.md` records only.

Two sibling gates read two different frames and both are right about their own axis, so the choice
is made explicitly rather than copied. `foreign-path-gate` reads the committed tree at `HEAD`
(`G11`: a verdict that changes with whatever is dirty on the runner is not a property of the
commit). `evidence-citation-gate` reads the index (`G24`: this runs inside `make lint`, ahead of
the commit, and failing a file that is staged and about to be committed would teach people to run
the gate last).

This gate follows `evidence-citation-gate`, because its whole purpose is to stop a dead pointer
being *written*, and a gate that only sees a citation after it is committed has already let it
through. `--rev <sha>` reads a commit instead, which is the deterministic per-commit reading
`foreign-path-gate`'s argument wants, and the control is hermetic either way. A dirty tree is
reported in the corpus block so a reader knows which of the two they are looking at.
Excluded by name, each with its reason:

  * the GENERATED globs — a stale pointer there is fixed by re-running its generator.
  * `vendor/**` — a pinned copy of an external skill. Its citations point into ITS repository, and
    resolving them here would report another project's tree as this one's defect.
  * `planning/test-campaign.2026-08-19-paper/**` — a superseded, self-contained campaign carrying
    its own `CASE-0nn` numbering. Reading its ids against the live registry produced 22 findings
    that are 22 readings of one fact: it is a different campaign.
  * this file and its floor.

## Exit codes

0 clean · 1 a blocking class over its floor · 2 the control did not fire, because a zero from an
instrument that has not been shown to fire is not evidence.
"""

import argparse
import fnmatch
import importlib.util
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve()
ROOT = HERE.parent.parent
FLOOR = ROOT / "planning" / "target-resolution-ratchet.json"
RETIREMENTS = ROOT / "planning" / "registry-retirements.json"
CAMPAIGN = ROOT / "planning" / "test-campaign"


def _sibling(name):
    """Import a sibling gate by path. The filenames carry hyphens, so `import` cannot reach them,
    and copying the vocabulary instead is how two gates come to disagree about one word."""
    spec = importlib.util.spec_from_file_location(
        name.replace("-", "_"), str(HERE.parent / (name + ".py")))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


FPG = _sibling("foreign-path-gate")
normalise = FPG.normalise
line_of = FPG.line_of
fenced_spans = FPG.fenced_spans
in_span = FPG.in_span
WITHDRAW = FPG.WITHDRAW
# An elided segment cannot be resolved, so it cannot be a citation — `foreign-path-gate`'s
# discriminator, imported rather than respelled. It is what tells this gate that
# `app/Tests/../../app/Sources/.../MenuCommand.swift`, a path-traversal *example* in the LEDGER's
# record of a defeated oracle, is a value in a described system and not a pointer at a file.
ELLIPSIS = FPG.ELLIPSIS

# Additive to `WITHDRAW`, not a replacement. `foreign-path-gate`'s marker must be delimited —
# parenthesised, a lone table cell, or a bold run OPENING with the marker word. This corpus also
# writes the denial as a clause bound to the citation by adjacency, which is the same frame grammar
# `citation-gate` reads an anchor with:
#
#   `scripts/acceptance/no-raw-design-values.sh`, which **does not exist** — the script is …
#   The lint's new comment cites `…-selftest.sh`, which is nowhere in the repo
#
# Adjacency is the discriminator: the clause must open within CLAUSE characters of the token and
# before the next citation, so a paragraph that happens to contain "does not exist" withdraws
# nothing.
DENIAL = re.compile(
    r"^[^`]{0,40}?\b(?:which|and it|but it|it|that)?\s*\**(?:"
    r"does\s+not\s+exist|do\s+not\s+exist|is\s+nowhere|are\s+nowhere|was\s+never\s+committed"
    r"|were\s+never\s+committed|is\s+not\s+in\s+the\s+repo|does\s+not\s+resolve"
    r"|no\s+longer\s+exists?|has\s+never\s+existed|never\s+existed"
    r"|is\s+absent|is\s+missing|is\s+gone)\b", re.I)
CLAUSE = 90

# A plan or a spec is a statement of intent about files that do not exist yet, or should not exist
# any more. The verb is what says so. Kept narrow on purpose and COUNTED, because a widening
# discriminator is how a sweep arrives at a confident zero (`G8`).
WORK_VERB = re.compile(
    r"\b(?:Create|Created|Delete|Deleted|Deletes|New|Removed?|Retire[ds]?|Rename[ds]?|Port|"
    r"Where\s+the\s+code\s+goes|Files|Add|Adds|Added)\b")
PLAN_FILE = ("planning/plans/plan-*.md", "planning/specs/spec-*.md")

SHA_IN_WINDOW = re.compile(r"`([0-9a-f]{7,40})`|\bat\s+([0-9a-f]{7,40})\b")

EXTS = ("md", "py", "swift", "ts", "tsx", "js", "mjs", "json", "sh", "zsh", "yml", "yaml",
        "html", "css", "tsv", "txt", "plist", "toml", "png", "svg", "xml", "lock")

CAMPAIGN_ID = re.compile(r"\b(CASE|REQ|SURF|DEF|FLOW|COMP)-(\d{3,4})\b")

# Ids that belong to another registry entirely. Named, with the evidence, so the exclusion is a
# statement rather than a silence.
FOREIGN_ID_FILES = (
    "vendor/*",                              # the vendored skill's own worked examples
    "planning/test-campaign.2026-08-19-paper/*",
)
FOREIGN_IDS = {
    # `egress`, another project. Its DEF numbering runs to 253 and this campaign's stops at 61.
    "DEF-252": "egress's registry, cited as prior art (ORCHESTRATOR.md, G9)",
    "DEF-253": "egress's registry, cited as prior art (G9's brief and the reckoning ledgers)",
    # A control plant, documented at planning/progress/G18.md as SEED-ORPHAN's arming.
    "REQ-999": "a documented control plant (planning/progress/G18.md, SEED-ORPHAN)",
}

GENERATED = (
    "planning/fidelity/*.tsv",
    "planning/fidelity/*.ledger.md",
    "planning/reckoning/*/*.json",
    "planning/tailings/*.json",
    "planning/test-campaign/*.json",
    "planning/test-campaign/evidence/*.json",
    "planning/test-campaign/evidence/*/*.json",
    "planning/test-campaign/evidence/*.log",
    "planning/test-campaign/evidence/*/*.log",
    "planning/reader-accounting.tsv",
    "planning/parity/*.tsv",
    "planning/status/*.json",
)

EXCLUDED = (
    "vendor/*",
    "planning/test-campaign.2026-08-19-paper/*",
)

SELF = ("planning/target-resolution-gate.py", "planning/target-resolution-ratchet.json")

PATH_CLASSES = ("SUBJECT", "RESOLVES", "FRAMED", "WITHDRAWN", "PLANNED",
                "MOVED", "DELETED", "PHANTOM")
PATH_BLOCKING = ("MOVED", "DELETED", "PHANTOM")
ID_CLASSES = ("ID_RESOLVES", "ID_RETIRED", "ID_FOREIGN", "ID_ABSENT")
ID_BLOCKING = ("ID_ABSENT",)


def matches_any(path, globs):
    return any(fnmatch.fnmatch(path, g) for g in globs)


# ------------------------------------------------------------------------------------ git, cached

class Repo:
    def __init__(self, root):
        self.root = str(root)
        self._hist = {}
        self._at = {}
        self._succ = {}
        self._anc = {}

    def _git(self, *a):
        return subprocess.run(["git", "-C", self.root] + list(a), capture_output=True)

    def tree(self, rev="HEAD"):
        out = self._git("ls-tree", "-r", "-z", "--name-only", rev).stdout.decode()
        return set(p for p in out.split("\0") if p)

    def index(self):
        """Every path in the index. What a fresh clone of the next commit receives."""
        out = self._git("ls-files", "-z").stdout.decode()
        return set(p for p in out.split("\0") if p)

    def records_from_disk(self):
        """Every tracked `.md` read from the working tree. The index names them; disk holds what
        is about to be committed."""
        data = {}
        for path in sorted(self.index()):
            if not path.endswith(".md"):
                continue
            try:
                data[path] = (pathlib.Path(self.root) / path).read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
        return data

    def dirty(self):
        r = self._git("status", "--porcelain")
        return len([l for l in r.stdout.decode().splitlines() if l.strip()])

    def blobs(self, rev="HEAD"):
        """Every text blob at `rev`, as {path: text}. Read from the object store, never from disk:
        the deterministic per-commit reading, reached with `--rev`."""
        out = self._git("ls-tree", "-r", "-z", rev).stdout
        want = []
        for e in (x for x in out.split(b"\0") if x):
            meta, path_b = e.split(b"\t", 1)
            parts = meta.split()
            if parts[1].decode() != "blob":
                continue
            path = path_b.decode("utf-8", "replace")
            if path.endswith(".md"):
                want.append((path, parts[2].decode()))
        data = {}
        if not want:
            return data
        proc = subprocess.Popen(["git", "-C", self.root, "cat-file", "--batch"],
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        stdout, _ = proc.communicate(("\n".join(s for _, s in want) + "\n").encode())
        off = 0
        for path, _sha in want:
            nl = stdout.index(b"\n", off)
            size = int(stdout[off:nl].split()[2])
            body = stdout[nl + 1:nl + 1 + size]
            data[path] = body.decode("utf-8", "replace")
            off = nl + 1 + size + 1
        return data

    def ever_existed(self, path):
        """Whether any commit reachable from any ref held this path. The discriminator between a
        pointer that has rotted and one that was never true anywhere."""
        if path not in self._hist:
            r = self._git("log", "--all", "--format=%H", "-1", "--", path)
            self._hist[path] = r.stdout.decode().strip() or None
        return self._hist[path]

    def ancestor(self, sha):
        if sha not in self._anc:
            self._anc[sha] = self._git("merge-base", "--is-ancestor", sha, "HEAD").returncode == 0
        return self._anc[sha]

    def at(self, sha, path):
        key = (sha, path)
        if key not in self._at:
            self._at[key] = self._git("cat-file", "-e", "%s:%s" % (sha, path)).returncode == 0
        return self._at[key]

    def successor(self, path):
        """Where git says the path went, when the commit that removed it recorded a rename."""
        if path in self._succ:
            return self._succ[path]
        last = self.ever_existed(path)
        out = None
        if last:
            r = self._git("show", "--name-status", "-M", "--format=", last)
            for line in r.stdout.decode("utf-8", "replace").splitlines():
                parts = line.split("\t")
                if len(parts) == 3 and parts[0].startswith("R") and parts[1] == path:
                    out = parts[2]
                    break
        self._succ[path] = out
        return out


# ------------------------------------------------------------------------------- the reader

def path_token_re(roots):
    return re.compile(
        r"`(%s)/([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*\.(?:%s))(?::\d+(?:-\d+)?)?`"
        % ("|".join(map(re.escape, sorted(roots))), "|".join(EXTS)))


def windows(norm, start, end):
    return norm[max(0, start - 240):start], norm[end:end + 240]


def classify_path(citing, path, head, tail, repo, tree, fenced):
    """One class, plus the evidence it rests on. Precedence is the docstring's order."""
    if fenced:
        return "SUBJECT", "inside a fenced block"
    if ELLIPSIS.search(path):
        return "SUBJECT", "an elided segment cannot be resolved, so it cannot be a citation"
    if path in tree:
        return "RESOLVES", None
    for window in (tail[:200], head[-200:]):
        for m in SHA_IN_WINDOW.finditer(window):
            sha = m.group(1) or m.group(2)
            if repo.at(sha, path):
                # Whether the named tree is an ANCESTOR of HEAD is printed rather than folded into
                # the class. A frame naming a commit reachable only from a side branch is checkable
                # in this clone and would stop being checkable if that branch were pruned, which is
                # a weaker guarantee than the same frame on mainline and should not read as the
                # same fact.
                return "FRAMED", ("in the tree at %s%s"
                                  % (sha[:7], "" if repo.ancestor(sha) else
                                     " (NOT an ancestor of HEAD — reachable only from a side "
                                     "branch, so a prune would take it)"))
    if WITHDRAW.search(tail[:FPG.WINDOW]) or DENIAL.match(tail[:CLAUSE]):
        return "WITHDRAWN", "the record says so"
    if matches_any(citing, PLAN_FILE) and (WORK_VERB.search(tail[:120])
                                           or WORK_VERB.search(head[-120:])):
        return "PLANNED", "a work item in a plan, not a claim of presence"
    if repo.ever_existed(path):
        succ = repo.successor(path)
        if succ:
            return "MOVED", "git names the successor: %s" % succ
        return "DELETED", "last held at %s" % repo.ever_existed(path)[:7]
    return "PHANTOM", "in no commit reachable from any ref"


def registry_ids(root):
    """The union of every registry that holds an id, with where each id was found."""
    src = {}

    def add(i, where):
        if i:
            src.setdefault(i, set()).add(where)

    camp = pathlib.Path(root) / "planning" / "test-campaign"
    for fn in ("cases.json", "cases.in.json", "requirements.in.json", "surfaces.in.json",
               "defects.in.json", "flows.in.json", "components.in.json"):
        p = camp / fn
        if p.exists():
            try:
                rows = json.loads(p.read_text())
            except (ValueError, OSError):
                continue
            for r in rows if isinstance(rows, list) else []:
                if isinstance(r, dict):
                    add(r.get("id"), fn)
    inv = camp / "inventory.json"
    if inv.exists():
        try:
            d = json.loads(inv.read_text())
        except (ValueError, OSError):
            d = {}
        for kind, rows in (d.items() if isinstance(d, dict) else []):
            for r in rows if isinstance(rows, list) else []:
                if isinstance(r, dict):
                    add(r.get("id"), "inventory.%s" % kind)
    return src


def retirements(root):
    p = pathlib.Path(root) / "planning" / "registry-retirements.json"
    if not p.exists():
        return {}
    try:
        rows = json.loads(p.read_text())
    except (ValueError, OSError):
        return {}
    return {r["id"]: r.get("reason", "") for r in rows
            if isinstance(r, dict) and r.get("id") and r.get("reason")}


def classify_id(cid, citing, known, retired):
    if matches_any(citing, FOREIGN_ID_FILES):
        return "ID_FOREIGN", "a foreign corpus: %s" % citing.split("/")[0]
    if cid in known:
        return "ID_RESOLVES", ", ".join(sorted(known[cid]))
    if cid in retired:
        return "ID_RETIRED", retired[cid]
    if cid in FOREIGN_IDS:
        return "ID_FOREIGN", FOREIGN_IDS[cid]
    return "ID_ABSENT", "no row in any registry, no retirement declared"


# ------------------------------------------------------------------------- the hermetic control

def build_control_repo(d):
    """Two commits, so a path can be present at one tree and gone at another. Nothing is planted in
    the corpus this gate guards: a plant quoted inside the document it guards is read by the gate as
    a real citation and the control then passes for the wrong reason (`G4`'s seventeenth item)."""
    p = pathlib.Path(d)

    def run(*a):
        subprocess.run(["git", "-C", d] + list(a), check=True, capture_output=True)

    run("init", "-q")
    run("config", "user.email", "control@example.invalid")
    run("config", "user.name", "control")
    (p / "planning").mkdir()
    (p / "planning" / "plans").mkdir()
    (p / "planning" / "kept.py").write_text("kept\n")
    (p / "planning" / "vanishes.py").write_text("vanishes\n")
    (p / "planning" / "renamed.py").write_text("a" * 400 + "\n")
    run("add", "-A")
    run("commit", "-q", "-m", "old")
    old = subprocess.run(["git", "-C", d, "rev-parse", "--short=7", "HEAD"],
                         capture_output=True, check=True).stdout.decode().strip()
    run("rm", "-q", "planning/vanishes.py")
    run("mv", "planning/renamed.py", "planning/moved-here.py")
    run("commit", "-q", "-m", "new")
    return old


def control(verbose=True):
    rows = []
    failures = []
    with tempfile.TemporaryDirectory() as d:
        old = build_control_repo(d)
        repo = Repo(d)
        tree = repo.tree("HEAD")
        roots = {"planning"}
        TOK = path_token_re(roots)

        def read(citing, prose):
            norm, _ = normalise(prose)
            m = TOK.search(norm)
            if not m:
                return None
            head, tail = windows(norm, m.start(), m.end())
            return classify_path(citing, m.group(1) + "/" + m.group(2), head, tail,
                                 repo, tree, False)

        plants = [
            ("present at HEAD", "planning/progress/x.md",
             "the reader is at `planning/kept.py` and runs nightly", "RESOLVES"),
            ("gone at HEAD, tree carried", "planning/progress/x.md",
             "measured with `planning/vanishes.py` at `%s`" % old, "FRAMED"),
            ("gone at HEAD, no tree", "planning/progress/x.md",
             "measured with `planning/vanishes.py` and reported clean", "DELETED"),
            ("renamed, no tree", "planning/progress/x.md",
             "the sweep lives at `planning/renamed.py` today", "MOVED"),
            ("never committed", "planning/progress/x.md",
             "see `planning/never-was.py` for the reader it would need", "PHANTOM"),
            ("gone, and the record says so", "planning/progress/x.md",
             "the brief named `planning/vanishes.py`, which **does not exist**", "WITHDRAWN"),
            ("gone, denied by an adjacent clause", "planning/progress/x.md",
             "the comment cites `planning/never-was.py`, which is nowhere in the repo", "WITHDRAWN"),
            ("a plan naming a file to create", "planning/plans/plan-F1.md",
             "- **File:** `planning/never-was.py` · **Create** - **Details:** a new reader",
             "PLANNED"),
        ]
        for label, citing, prose, want in plants:
            got = read(citing, prose)
            cls = got[0] if got else "NO CITATION FOUND"
            rows.append((label, want, cls, cls == want,
                         (got[1] if got and got[1] else "")))
            if cls != want:
                failures.append("%s: got %s, want %s" % (label, cls, want))

        # A plan is not a blanket exemption. The same plan file citing the same missing path with no
        # work verb against it must still block, or PLANNED is the hole that swallows the finding.
        got = read("planning/plans/plan-F1.md",
                   "the argument at `planning/never-was.py` settled it")
        ok = bool(got) and got[0] == "PHANTOM"
        rows.append(("NEGATIVE: a plan with no work verb", "PHANTOM",
                     got[0] if got else "—", ok, "PLANNED is verb-bound, not file-bound"))
        if not ok:
            failures.append("plan negative: got %s, want PHANTOM" % (got[0] if got else "none"))

        # A paragraph that merely contains the words is not a denial. DENIAL is bound to the
        # citation by adjacency, the same way `citation-gate` binds an anchor.
        got = read("planning/progress/x.md",
                   "`planning/vanishes.py` was the reader we used all week, and the point of the "
                   "whole exercise was that the harness does not exist on the phone")
        ok = bool(got) and got[0] == "DELETED"
        rows.append(("NEGATIVE: the words, far from the citation", "DELETED",
                     got[0] if got else "—", ok, "a denial must be adjacent to withdraw"))
        if not ok:
            failures.append("denial negative: got %s, want DELETED" % (got[0] if got else "none"))

        # THE TREE MUST BUY SOMETHING. The same dead path, cited with and without a frame, must
        # answer differently. If it answers the same, `M16`'s third coordinate has been demonstrated
        # to do nothing and a green run here means nothing either.
        with_tree = read("planning/progress/x.md",
                         "`planning/renamed.py` at `%s`" % old)
        without = read("planning/progress/x.md", "`planning/renamed.py` today")
        ok = bool(with_tree) and bool(without) and with_tree[0] == "FRAMED" \
            and without[0] == "MOVED"
        rows.append(("the tree coordinate buys something", "FRAMED ≠ MOVED",
                     "%s ≠ %s" % (with_tree[0] if with_tree else "—",
                                       without[0] if without else "—"),
                     ok, "a rename is absorbed by a frame and by nothing else"))
        if not ok:
            failures.append("frame arm: with-tree %s, without %s"
                            % (with_tree, without))

        # ---- the id arm, and the renumber it must survive ----
        #
        # `G16`'s work was refiled as `DEF-059` on 2026-08-27 and the `G16` row was KEPT. That is
        # what a legitimate renumber looks like here, and the gate has to be silent on it. The
        # illegitimate one drops the old row and names no successor.
        known = {"DEF-001": {"defects.in.json"}, "DEF-059": {"inventory.defect"}}
        retired = {"DEF-900": "superseded by DEF-059, 2026-08-27"}
        idrows = [
            ("id in a seed registry", "DEF-001", "planning/progress/x.md", "ID_RESOLVES"),
            ("id only in the built inventory — today's renumber", "DEF-059",
             "planning/progress/x.md", "ID_RESOLVES"),
            ("id retired with a reason", "DEF-900", "planning/progress/x.md", "ID_RETIRED"),
            ("id in a foreign corpus", "CASE-0117", "vendor/test-campaign/README.md", "ID_FOREIGN"),
            ("id in no registry at all", "DEF-777", "planning/progress/x.md", "ID_ABSENT"),
        ]
        for label, cid, citing, want in idrows:
            cls, ev = classify_id(cid, citing, known, retired)
            rows.append((label, want, cls, cls == want, ev))
            if cls != want:
                failures.append("%s: got %s, want %s" % (label, cls, want))

        # The renumber arm, both ways, in one comparison. A gate that answered the same on both
        # would either block every legitimate renumber or catch no illegitimate one.
        legit = classify_id("DEF-059", "planning/progress/x.md", known, retired)[0]
        undeclared = classify_id("DEF-059", "planning/progress/x.md", {}, {})[0]
        ok = legit == "ID_RESOLVES" and undeclared == "ID_ABSENT"
        rows.append(("a renumber that keeps the old row vs one that does not",
                     "ID_RESOLVES ≠ ID_ABSENT", "%s ≠ %s" % (legit, undeclared), ok,
                     "the union of registries is the whole of the renumber tolerance"))
        if not ok:
            failures.append("renumber arm: kept %s, dropped %s" % (legit, undeclared))

    if verbose:
        print("PRESENCE CONTROL — planted in a throwaway repo, read by the real classifier")
        w = max(len(r[0]) for r in rows)
        for label, want, got, ok, ev in rows:
            print("  %-*s  expect %-22s got %-22s %-7s %s"
                  % (w, label, want, got, "fired" if ok else "MISSED", ev[:52]))
        print("  control: %s"
              % ("ALL PLANTS FIRED" if not failures
                 else "%d DID NOT FIRE — the instrument has measured nothing" % len(failures)))
        print()
    return not failures


# ------------------------------------------------------------------------------------ the sweep

def sweep(root, rev=None):
    repo = Repo(root)
    if rev is None:
        tree = repo.index()
        blobs = repo.records_from_disk()
    else:
        tree = repo.tree(rev)
        blobs = repo.blobs(rev)
    roots = sorted({p.split("/")[0] for p in tree if "/" in p})
    TOK = path_token_re(roots)

    records = {p: t for p, t in blobs.items()
               if not matches_any(p, GENERATED)
               and not matches_any(p, EXCLUDED)
               and p not in SELF}
    foreign_records = {p: t for p, t in blobs.items() if matches_any(p, EXCLUDED)}

    known = registry_ids(root)
    retired = retirements(root)

    p1 = p2 = 0
    seen = set()
    prows = []
    for f, raw in sorted(records.items()):
        p1 += len(TOK.findall(raw))
        norm, offsets = normalise(raw)
        fences = fenced_spans(raw)
        for m in TOK.finditer(norm):
            p2 += 1
            path = m.group(1) + "/" + m.group(2)
            key = (f, path)
            if key in seen:
                continue
            seen.add(key)
            head, tail = windows(norm, m.start(), m.end())
            at = line_of(raw, offsets[m.start()])
            cls, ev = classify_path(f, path, head, tail, repo, tree,
                                    in_span(fences, offsets[m.start()]))
            prows.append({"file": f, "at": at, "path": path, "class": cls, "evidence": ev})

    i1 = 0
    iseen = set()
    irows = []
    for f, raw in sorted(list(records.items()) + list(foreign_records.items())):
        for m in CAMPAIGN_ID.finditer(raw):
            i1 += 1
            cid = m.group(0)
            if (f, cid) in iseen:
                continue
            iseen.add((f, cid))
            cls, ev = classify_id(cid, f, known, retired)
            irows.append({"file": f, "id": cid, "class": cls, "evidence": ev})

    return {"repo": repo, "records": records, "foreign": foreign_records,
            "p1": p1, "p2": p2, "prows": prows, "i1": i1, "irows": irows,
            "known": known, "retired": retired, "dirty": repo.dirty()}


def by_file(rows, classes, key="file"):
    out = {}
    for r in rows:
        if r["class"] in classes:
            out[r[key]] = out.get(r[key], 0) + 1
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=str(ROOT))
    ap.add_argument("--rev", default=None,
                    help="read a commit instead of the index, for a deterministic per-commit "
                         "verdict")
    ap.add_argument("--control", action="store_true", help="run only the presence control")
    ap.add_argument("--set-floor", action="store_true",
                    help="write the per-file floor. Never a side effect of checking.")
    ap.add_argument("--quiet", action="store_true", help="counts and verdict only")
    args = ap.parse_args()

    if not control(verbose=not args.quiet):
        print("REFUSING TO REPORT: the control did not fire, so a zero here means nothing.")
        return 2
    if args.control:
        return 0

    root = pathlib.Path(args.root).resolve()
    s = sweep(root, args.rev)
    prows, irows = s["prows"], s["irows"]

    ptally = {c: 0 for c in PATH_CLASSES}
    for r in prows:
        ptally[r["class"]] += 1
    itally = {c: 0 for c in ID_CLASSES}
    for r in irows:
        itally[r["class"]] += 1

    print("corpus — %s, hand-written records only"
          % ("the committed tree at %s" % args.rev if args.rev
             else "the git index (%d uncommitted change(s) in the working tree)" % s["dirty"]))
    print("  hand-written .md records read                    %6d" % len(s["records"]))
    print("  records in a declared foreign corpus, id arm only %5d   (vendor, the paper campaign)"
          % len(s["foreign"]))
    print()
    print("denominators — two citation forms, two questions, neither blended into the other")
    print("  P1  repo-rooted path tokens, every occurrence    %6d" % s["p1"])
    print("  P2  the same, read wrap-tolerantly               %6d   %+d vs P1"
          % (s["p2"], s["p2"] - s["p1"]))
    print("  P3  P2 deduplicated by (citing file, path)       %6d" % len(prows))
    print("  I1  campaign-id tokens, every occurrence         %6d" % s["i1"])
    print("  I2  I1 deduplicated by (citing file, id)         %6d" % len(irows))
    print()
    print("PATHS — does the target exist. A partition over P3 = %d" % len(prows))
    for c in PATH_CLASSES:
        print("  %-10s %6d%s" % (c, ptally[c], "   BLOCKS" if c in PATH_BLOCKING else ""))
    print("  %-10s %6d" % ("(sum)", sum(ptally.values())))
    print("  PLANNED is the declared hole: %d tokens are excused by a work verb in a plan or a"
          % ptally["PLANNED"])
    print("  spec. A widening discriminator is how a sweep reaches a confident zero, so the size")
    print("  of this one is printed rather than argued away.")
    print()
    print("IDS — does the id still name a row. A partition over I2 = %d" % len(irows))
    for c in ID_CLASSES:
        print("  %-12s %6d%s" % (c, itally[c], "   BLOCKS" if c in ID_BLOCKING else ""))
    print("  %-12s %6d" % ("(sum)", sum(itally.values())))
    print("  registries read as a union: %d distinct ids across %d sources. That union is the whole"
          % (len(s["known"]), len({w for ws in s["known"].values() for w in ws})))
    print("  of the renumber tolerance — see the control's renumber arm.")
    print()

    blocking = [r for r in prows if r["class"] in PATH_BLOCKING]
    idblocking = [r for r in irows if r["class"] in ID_BLOCKING]

    if blocking:
        print("dead path targets — %d, most-severe first" % len(blocking))
        order = {"PHANTOM": 0, "MOVED": 1, "DELETED": 2}
        for r in sorted(blocking, key=lambda r: (order[r["class"]], r["file"], r["at"])):
            print("  %-8s %s:%d  ->  %s" % (r["class"], r["file"], r["at"], r["path"]))
            print("           %s" % r["evidence"])
        print()
    if idblocking:
        print("ids that name no row — %d" % len(idblocking))
        for r in sorted(idblocking, key=lambda r: (r["file"], r["id"])):
            print("  %-12s %s  in %s" % (r["class"], r["id"], r["file"]))
        print()

    now = by_file(prows, PATH_BLOCKING)
    idnow = by_file(irows, ID_BLOCKING)

    if args.set_floor:
        FLOOR.write_text(json.dumps({
            "note": "Blocking-class citations per CITING file. Written by "
                    "planning/target-resolution-gate.py --set-floor. Each file's count may only "
                    "fall. Per file rather than in total, because a scalar lets a deletion in one "
                    "file buy headroom for a new dead citation in another.",
            "paths": {"blocking": PATH_BLOCKING, "total": len(blocking),
                      "by_file": dict(sorted(now.items()))},
            "ids": {"blocking": ID_BLOCKING, "total": len(idblocking),
                    "by_file": dict(sorted(idnow.items()))},
        }, indent=2) + "\n")
        print("floor: written — %d dead path target(s) across %d file(s), %d absent id(s) across "
              "%d file(s)" % (len(blocking), len(now), len(idblocking), len(idnow)))
        return 0

    rc = 0
    if not FLOOR.exists():
        print("floor: no baseline at %s — run --set-floor to set one"
              % FLOOR.relative_to(ROOT))
    else:
        base = json.loads(FLOOR.read_text())
        for arm, cur, label in (("paths", now, "dead path target"),
                                ("ids", idnow, "absent id")):
            b = base.get(arm, {}).get("by_file", {})
            risen = sorted((f, n, b.get(f, 0)) for f, n in cur.items() if n > b.get(f, 0))
            if risen:
                rc = 1
                print("floor: %d file(s) hold more %ss than the floor allows:" % (len(risen), label))
                for f, n, was in risen:
                    print("  %s  %d, floor %d" % (f, n, was))
            fell = sum(1 for f, was in b.items() if cur.get(f, 0) < was)
            print("floor[%s]: %d over %d file(s) against floor %d — %d above, %d below%s"
                  % (arm, sum(cur.values()), len(cur), base.get(arm, {}).get("total", 0),
                     len(risen), fell,
                     "; re-run --set-floor to lower it" if fell and not risen else ""))

    print("exit: %d" % rc)
    return rc


if __name__ == "__main__":
    sys.exit(main())
