#!/usr/bin/env python3
"""Derive the union of every active branch's build roles, and walk every surface against it.

## The defect this exists for

`G8`. A citation that does not resolve announces itself when someone follows it; **a question
answered at the wrong scope returns a clean answer.** There is no dangling pointer and no red —
just a correct answer to a narrower question than the one that mattered.

`M22` is the measured instance. Three branches make three pairs; one pair was checked in both
directions and the cross-branch hazard was reported closed. `ai/m22` was left out because it had
**zero diff** on `scripts/acceptance/mock_fidelity.py`, which was taken for having no stake:

    Zero diff means no conflict. It does not mean no exposure.

The quota rule keys on the **build node's role**, not on the edit, so a branch that never touches
`VOUCHED_CONTROLS` can still have its nodes reclassified by another branch's additions. M22's
`harnesses` surface carries `callout`, which is `ai/m19`'s role, on `unreadable-note` in the error
frame. Harmless in the event — that node is paired, so the quota rule had nothing to reclassify —
but non-empty, and it was reported empty. **"Came back empty" was M16's surface, not a property of
the merge.**

So this is `M16`'s reduction made runnable: rather than asking whether a merge conflicts, derive
the union of all active branches' roles, walk each surface's own record against it, and name what
it could not check. The check is per-surface and runs **once per surface, including surfaces that
edited nothing**.

## Establish the set before answering about members of it

Both sets, in both directions, because the failure was a complete answer about the wrong set:

  * the **branch** set is every local head that is not already merged into the base — never the
    branches you happen to be in conversation with. The `VOUCHED_CONTROLS` collision was answered
    by asking the two parties already in the room, and the largest party at `+29/−6` was absent
    from the answer.
  * the **surface** set is the union of fidelity ledgers across *all* of those refs, not the ones
    on `HEAD`, so a surface another branch adds is in scope before it lands.

## The reading this takes, and the reading it does not

`mock-fidelity-gate.sh` derives roles from `planning/fidelity/dumps/`, which a `MEASURE` Swift
build writes and which is untracked. That build fails on this machine today, and a gate that can
only run behind a broken build is a gate nobody runs. So this reads the **tracked ledgers** at
`planning/fidelity/*.ledger.md`, which carry `role=… kind=…` for every build node the last real
measurement paired.

**That is narrower than the dump reading and the difference is stated rather than hidden**, because
quietly substituting a narrower instrument is this item's own subject. The ledger carries roles for
**paired** nodes only. `harnesses`' breadth layer counts 193 structure nodes and 15
`structure-unpaired`, against 40 rows carrying a role here. The unpaired remainder has no role in
any tracked file, so this gate cannot see it, and every run prints that remainder as its own
uncovered set rather than letting it read as agreement.

The ledgers are also a **frame** rather than the working tree: each answers *did the last recorded
measurement of this surface use a role the union adds*. Every row prints the blob it read, so a
stale ledger is visible as staleness instead of as a clean answer — the trade `citation-gate.py`
takes with `TREE_ONLY`.

What this reading does buy: it reproduces M22's exposure exactly. `callout` on `unreadable-note`
is a paired node, so it is in the ledger, and this gate reddens on it.

## Exit codes, and why four

They mirror `mock_fidelity.py` deliberately, and the last two are the reason this is not a diff:

    0   no surface's recorded measurement uses a role the union adds
    1   at least one does — a call to make, not yet a defect
    3   inconclusive — a branch's table or a surface's ledger could not be read, and the
        verdict depended on it
    4   the control failed, so nothing this run printed is evidence of anything
    2   usage

**3 and 4 were one code until 2026-08-26, and collapsing them lost the distinction that matters
most.** A 3 says *the instrument works and the corpus has a hole in it* — today, `popover`, and the
right response is to measure `popover`. A 4 says *the instrument is not known to work*, and the
right response is to fix the gate before reading a single line of its output. Answering both with
one number means a broken gate and a true inconclusive verdict are indistinguishable to anything
downstream, which is this item's own subject wearing a different hat. `runnable-path-gate.py` on
`ai/g9` separates them the same way; it uses 2 for the control, which is not available here because
`argparse` already owns 2 and `make` collapses every failing recipe to 2 as well.

Exit 1 is what makes this a call rather than a standard. A ten-line header comment recording this
rule landed in `mock_fidelity.py` with nothing downstream depending on it, which reads as a standard
to satisfy — the very failure this item is about, committed by the item. An exit code is read.

`planning/fidelity/popover.ledger.md` is why 3 exists and is not theoretical. It is an obituary:
the gate exited 3 on `#statusPopover has no '.v-ideal' block` and wrote *"This run did not produce a
table"*. A role sweep over it returns zero. **A two-state gate reads that zero as a clean surface**,
which is a surface that has never been measured reporting as measured. Here it is `INCONCLUSIVE`.

## Counting

No count is printed bare. Five sweeps over one phrase in one file once returned four answers and
only the widest was complete, so a bare integer from an unnamed reader is an assertion wearing a
measurement's clothes. Every figure below carries its reader's identity, and every intersection row
carries its `file:line` site — because a bare count is what let two parties report *verified* over
disjoint subsets, and two runs that both say `2` and disagree about **which 2** is the failure
actually hit.

## The controls

An absence check cannot detect its own blindness. This corpus has four measured absence checks that
could not fail — a line-anchored `grep` returning 0 for a phrase present twice, a sentinel matching
the product's own copy, an `awk` reading the wrong AX column, and a first-pass sweep over `scripts/`
alone. Today the union adds **zero** roles on this repo, because M16, M19 and M22 are all merged, so
this gate's headline answer is a zero and the controls are the only thing standing behind it.

Two run on every invocation, and both print above the table:

  * a **hermetic** control, following `citation-gate.py --control`: a throwaway git repository in a
    temp directory with a base branch and two others, planted so that each of the five answers is
    required exactly. Nothing is planted in this corpus, because a control quoted inside the
    document it guards is found by the naive matcher instead of the planted instance and then
    passes for the wrong reason. The row that matters is `silent`: a branch with **zero diff** on
    `mock_fidelity.py` whose ledger uses a role another branch adds. It must read `EXPOSED`. The
    same fixture run with an empty added-role set must read `CLEAR`, and the control fails if those
    two agree — an instrument that answers the same either way has demonstrated nothing.
  * a **live presence** control over the real corpus: a role a surface actually uses, and the base
    table does not name, is committed into `VOUCHED_CONTROLS` on a **new branch of a `--local
    --shared` clone**. To pass, it must reach the added set through `for-each-ref`, `git show` and
    `ast.parse`, and the surface must move `CLEAR → EXPOSED` over the **real, unmodified** ledger.
    A role no ledger contains is then planted the same way and must match nothing.

    Its first version injected a role straight into the added set and checked that `intersect`
    found it — `x in {x}` on tuples already in memory, which could not fail for any ledger with a
    role in it and exercised none of the pipeline. The out-of-family review caught that
    (`gemini-3.7-flash-high`, 2026-08-26), and it is worth recording plainly: **the gate against
    checks that cannot fail was shipped containing one.**
"""

from __future__ import annotations

import argparse
import ast
import bisect
import collections
import os
import re
import shutil
import subprocess
import sys
import traceback
import tempfile

FIDELITY_DIR = "planning/fidelity"
GATE_FILE = "scripts/acceptance/mock_fidelity.py"

# `role=<x> kind=<y>` as the ledger's build column writes it. Anchored on the pair rather than on
# `role=` alone so a prose mention of the word cannot enter the census.
ROLE_KIND = re.compile(r"\brole=([A-Za-z0-9_.-]+)\s+kind=([A-Za-z0-9_.-]+)")

# The obituary `mock_fidelity.py` writes when it reached no verdict. A ledger carrying it has no
# table, and its zero roles are an absence of measurement rather than an absence of exposure.
OBITUARY = "This run did not produce a table"

CLEAR, EXPOSED, INCONCLUSIVE = "CLEAR", "EXPOSED", "INCONCLUSIVE"


class Git:
    """Every git read this gate makes, against one repository root."""

    def __init__(self, root: str):
        self.root = root

    def run(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(("git",) + args, capture_output=True, text=True, cwd=self.root)

    def out(self, *args: str) -> str | None:
        r = self.run(*args)
        return None if r.returncode else r.stdout

    def heads(self) -> list[str]:
        """Local heads only, and the report says so rather than claiming every branch.

        A branch that exists here only as `refs/remotes/origin/*` — a colleague's push, a PR ref —
        is outside this set. Calling that "every active branch" would be this gate answering at the
        wrong scope in the sentence describing how it avoids answering at the wrong scope
        (`gemini-3.7-flash-high`, 2026-08-26, File 1 finding b2). `remotes()` measures the size of
        that hole and every run prints it.
        """
        return (self.out("for-each-ref", "--format=%(refname:short)", "refs/heads") or "").split()

    def remotes(self) -> list[str]:
        return (self.out("for-each-ref", "--format=%(refname:short)", "refs/remotes") or "").split()

    def merged_into(self, base: str) -> set[str]:
        return set((self.out("branch", "--merged", base, "--format=%(refname:short)") or "").split())

    def ls(self, ref: str, path: str) -> list[str]:
        return (self.out("ls-files", "--with-tree", ref, "--", path) or "").split("\n")

    def blob_id(self, ref: str, path: str) -> str | None:
        got = self.out("rev-parse", f"{ref}:{path}")
        return got.strip() if got else None

    def show(self, ref: str, path: str) -> str | None:
        return self.out("show", f"{ref}:{path}")


# ------------------------------------------------------------------ the branch side of the union

def roles_from_gate_source(source: str) -> tuple[set[str], str | None]:
    """The build roles `VOUCHED_CONTROLS` names, read by parsing rather than by grepping.

    Returns `(roles, error)`. A file that exists and does not parse is an error rather than an
    empty set, because an empty set is indistinguishable from a clean answer and this whole item
    is about that confusion.
    """
    # Parsed as a module rather than matched as text. An earlier draft anchored the closing brace
    # at column 0 (`^\}` under re.M), which is a property of this file's current formatting rather
    # than of Python: a formatter that indents the brace, or an inner set literal whose brace lands
    # at column 0, would have made this report "no VOUCHED_CONTROLS literal found" — an absence
    # produced by the reader, which is the exact class of defect this gate exists over.
    # (`gemini-3.7-flash-high`, review of 2026-08-26, File 1 finding d3.)
    try:
        tree = ast.parse(source)
    except SyntaxError as error:
        return set(), f"the module did not parse: {error}"
    node = None
    for statement in tree.body:
        targets = ([statement.target] if isinstance(statement, ast.AnnAssign)
                   else getattr(statement, "targets", []))
        for target in targets:
            if isinstance(target, ast.Name) and target.id == "VOUCHED_CONTROLS":
                node = statement.value
    if node is None:
        return set(), "no module-level VOUCHED_CONTROLS assignment"
    try:
        table = ast.literal_eval(node)
    except (ValueError, SyntaxError) as error:
        return set(), f"VOUCHED_CONTROLS did not evaluate: {type(error).__name__}: {error}"
    if not isinstance(table, dict):
        return set(), f"VOUCHED_CONTROLS is {type(table).__name__}, not a dict"
    roles: set[str] = set()
    for pairs in table.values():
        for pair in pairs:
            roles.add(pair[0])
    return roles, None


def active_refs(git: Git, base: str) -> tuple[list[str], int, int]:
    """Every local head not already merged into the base, plus the base itself.

    A head merged into the base contributes nothing to the union: its additions are in the
    baseline. Everything else is a party to the merge whether or not it is in the room.
    """
    heads = git.heads()
    merged = git.merged_into(base)
    active = sorted(h for h in heads if h != base and h not in merged)
    return [base] + active, len(heads), len(merged)


# ------------------------------------------------------------------ the surface side of the union

class SurfaceRead:
    """One ledger blob, and the roles it records — with what it could not record."""

    def __init__(self, path: str, blob: str, refs: list[str], text: str):
        self.path = path
        self.blob = blob
        self.refs = refs
        self.text = text
        self.error: str | None = None
        self.sites: list[tuple[int, str, str]] = []      # (line, role, kind)
        self.line_anchored = 0
        self.collapsed = 0
        self.unpaired: dict[str, int] = {}

        if OBITUARY in text:
            self.error = self._obituary_reason(text)
            return
        self._census()
        if not self.sites:
            self.error = "no `role=… kind=…` row in the ledger, so it records no build node"
        self.unpaired = self._uncovered(text)

    @staticmethod
    def _obituary_reason(text: str) -> str:
        fenced = re.search(r"```\n(.*?)\n```", text, re.S)
        said = fenced.group(1).strip().splitlines()[0] if fenced else "reason not recorded"
        return f"the gate reached no verdict and wrote no table — it said: {said}"

    def _census(self) -> None:
        """Two readers over the same file. **The wrap-tolerant one is the verdict's reader.**

        `collapsed` reads the file whole with every run of whitespace — newlines included — reduced
        to one space, which is `claim-sweep.py`'s finding: a line-anchored reader cannot see what a
        text editor wrapped. `line_anchored` is what a `grep` sees, and is kept as the comparison.

        An earlier draft had these the other way round: `sites` came from the line-anchored loop and
        the collapsed figure was computed, printed, and used by nothing — while the report said *the
        collapsed figure is the complete one*. A `role=` split across a wrap would have incremented
        the collapsed count, left `sites` empty, and returned CLEAR. **A decorative reader beside a
        sentence claiming it is the complete one is this item's defect wearing this item's clothes**,
        and it was caught by the out-of-family review rather than by me (`gemini-3.7-flash-high`,
        2026-08-26, File 1 finding b1).
        """
        collapsed, offsets = collapse(self.text)
        starts = line_starts(self.text)
        for match in ROLE_KIND.finditer(collapsed):
            raw = offsets[match.start()] if match.start() < len(offsets) else -1
            self.sites.append((line_of(starts, raw), match.group(1), match.group(2)))
        self.collapsed = len(self.sites)
        for line in self.text.splitlines():
            self.line_anchored += len(ROLE_KIND.findall(line))

    @staticmethod
    def _uncovered(text: str) -> dict[str, int]:
        """The breadth layer's own count of build nodes this ledger gives no role for.

        `structure-unpaired` and `extra` are nodes the measurement saw and did not pair, so they
        carry no `role=` anywhere tracked. They are this gate's blind spot, quoted from the ledger's
        own arithmetic rather than estimated.
        """
        row = re.search(r"\|\s*`breadth`\s*\|[^|]*\|([^|]*)\|", text)
        if not row:
            return {}
        found = {}
        for name, count in re.findall(r"([a-z-]+)\s+(\d+)", row.group(1)):
            if name in ("structure-unpaired", "extra", "extra-cited", "unclassified"):
                found[name] = int(count)
        return found

    @property
    def roles(self) -> set[str]:
        return {role for _, role, _ in self.sites}

    def intersect(self, added: set[str]) -> list[tuple[int, str, str]]:
        return sorted(s for s in self.sites if s[1] in added)


def collapse(raw: str) -> tuple[str, list[int]]:
    """Whitespace-collapsed view of a whole file, with each output char's source offset.

    `claim-sweep.py`'s reader, restated: every claim in this repo lives in a wrapped markdown file
    and a line-anchored reader cannot see a claim the wrap split. The offset list is what maps a
    hit in the collapsed view back to a line in the original, which is how a wrap-tolerant reader
    answers a line-anchored question.
    """
    out: list[str] = []
    offsets: list[int] = []
    in_space = False
    for index, char in enumerate(raw):
        if char.isspace():
            if not in_space:
                out.append(" ")
                offsets.append(index)
                in_space = True
        else:
            out.append(char)
            offsets.append(index)
            in_space = False
    return "".join(out), offsets


def line_starts(raw: str) -> list[int]:
    return [0] + [index + 1 for index, char in enumerate(raw) if char == "\n"]


def line_of(starts: list[int], raw_offset: int) -> int:
    """The 1-indexed line holding a raw character offset.

    It previously returned `offsets[position]` — a character index, not a line number, so every
    mapped "line" was a four-digit offset into the file. Nothing consumed it, which is why it went
    unnoticed; once the collapsed reader became the verdict's reader it became load-bearing.
    """
    if raw_offset < 0:
        return -1
    return bisect.bisect_right(starts, raw_offset)


def read_surfaces(git: Git, refs: list[str]) -> tuple[list[SurfaceRead], list[str]]:
    """Every fidelity ledger on every ref, deduplicated by blob.

    Keyed by blob rather than by path so a surface identical across four refs is one row naming
    four refs, and a surface that differs is two rows — which is the distinction that matters and
    which a path-keyed read would flatten.
    """
    by_blob: dict[tuple[str, str], list[str]] = collections.defaultdict(list)
    paths: set[str] = set()
    for ref in refs:
        for path in git.ls(ref, FIDELITY_DIR):
            if not path.endswith(".ledger.md"):
                continue
            paths.add(path)
            blob = git.blob_id(ref, path)
            if blob:
                by_blob[(path, blob)].append(ref)

    reads, unreadable = [], []
    for (path, blob), owners in sorted(by_blob.items()):
        text = git.show(owners[0], path)
        if text is None:
            unreadable.append(f"{path} at {owners[0]} ({blob[:7]}) could not be read")
            continue
        reads.append(SurfaceRead(path, blob[:7], sorted(owners), text))
    return reads, unreadable


# ------------------------------------------------------------------------------ the verdict

CONTROL_FAILED = 4
INCONCLUSIVE_CODE = 3


class Inconclusive(Exception):
    """A verdict could not be reached. Raised so it exits 3 rather than 1.

    `raise SystemExit("message")` prints the message and exits **1**, which in this gate means
    FINDINGS — so a base ref whose table could not be read would have reported as exposure. Caught
    by the out-of-family review (`gemini-3.7-flash-high`, 2026-08-26, File 1 finding d2).
    """


class Verdict:
    def __init__(self, base_roles, union_roles, added, per_branch, unreadable_branches,
                 surfaces, unreadable_surfaces, head_count, merged_count):
        self.base_roles = base_roles
        self.union_roles = union_roles
        self.added = added
        self.per_branch = per_branch
        self.unreadable_branches = unreadable_branches
        self.surfaces = surfaces
        self.unreadable_surfaces = unreadable_surfaces
        self.head_count = head_count
        self.merged_count = merged_count
        self.without_table: list[str] = []

    def status(self, surface: SurfaceRead) -> str:
        if surface.error:
            return INCONCLUSIVE
        return EXPOSED if surface.intersect(self.added) else CLEAR

    #: Below this many readable surfaces the run is evidence of nothing. `mock_fidelity.py`'s
    #: preflight rule: a property the measurement cannot compute reads as agreement on both sides.
    FLOOR = 1

    def code(self) -> int:
        states = [self.status(s) for s in self.surfaces]
        readable = sum(1 for state in states if state != INCONCLUSIVE)
        # An empty or below-floor surface set returned 0 in an earlier draft: `EXPOSED in []` is
        # False, so a missing or renamed fidelity directory reported CLEAN. A pass because nothing
        # was measured is the defect this gate is named after
        # (`gemini-3.7-flash-high`, 2026-08-26, File 1 finding c1).
        if readable < self.FLOOR:
            return 3
        if self.unreadable_branches or self.unreadable_surfaces or INCONCLUSIVE in states:
            return 3
        return 1 if EXPOSED in states else 0


def measure(git: Git, base: str, inject: set[str] | None = None) -> Verdict:
    refs, head_count, merged_count = active_refs(git, base)

    base_source = git.show(base, GATE_FILE)
    if base_source is None:
        raise Inconclusive(f"{base}:{GATE_FILE} is not in the tree")
    base_roles, error = roles_from_gate_source(base_source)
    if error:
        raise Inconclusive(f"{base}:{GATE_FILE} — {error}")

    union = set(base_roles)
    per_branch: list[tuple[str, int, int]] = []
    unreadable_branches: list[str] = []
    without_table: list[str] = []
    for ref in refs[1:]:
        source = git.show(ref, GATE_FILE)
        if source is None:
            # A branch that predates the file and a branch that DELETED it are indistinguishable
            # here, and an earlier draft recorded both as `(ref, 0, 0)` — a silent zero, which is
            # the shape this gate exists to refuse. It is now its own printed class rather than a
            # row in the table (`gemini-3.7-flash-high`, 2026-08-26, File 1 finding c2).
            without_table.append(ref)
            continue
        roles, error = roles_from_gate_source(source)
        if error:
            unreadable_branches.append(f"{ref}:{GATE_FILE} — {error}")
            continue
        per_branch.append((ref, len(roles), len(roles - base_roles)))
        union |= roles

    added = (union - base_roles) | (inject or set())
    surfaces, unreadable_surfaces = read_surfaces(git, refs)
    verdict = Verdict(base_roles, union, added, per_branch, unreadable_branches,
                      surfaces, unreadable_surfaces, head_count, merged_count)
    verdict.without_table = without_table
    return verdict


# ---------------------------------------------------------------------------- the live control

def live_control(git: Git, base: str, verdict: Verdict) -> tuple[bool, list[str]]:
    """Plant a role on a REAL branch of a clone, and require the real corpus to redden.

    The first version of this control was a decoration and the out-of-family review said so
    (`gemini-3.7-flash-high`, 2026-08-26, File 1 finding a1). It took a role out of
    `surface.roles`, passed it back in as `inject`, and checked that `intersect` found it — which
    reduces to `x in {x}` on tuples already parsed into memory. **It could not fail for any ledger
    carrying at least one role**, and it exercised neither the ref walk, nor the `ast` parse of
    another branch's table, nor the union. A control that cannot fail is the thing this item is
    about, and it was sitting inside the gate for it.

    So this plants where a real merge would. It makes a `--local --shared` clone (about a second,
    hard-linked objects), commits a patched `VOUCHED_CONTROLS` onto a **new branch** there, and runs
    the whole measurement against it. To pass, the planted role must reach `added` — which it can
    only do through `git for-each-ref`, `git show` of that branch's file, `ast.parse` and the union
    — and the surface must move from `CLEAR` to `EXPOSED` over the **real, unmodified ledgers**.

    Both ends of the transition are measured. The earlier version printed `0 → {hits}` with the
    zero hardcoded, so a surface already exposed would have had its starting state misreported
    (same review, finding c3).
    """
    lines: list[str] = []
    ok = True

    measurable = [s for s in verdict.surfaces if not s.error]
    if not measurable:
        return False, ["  no measurable surface to plant into, so the zero above is unproved"]

    # A role a surface actually uses and the base table does not name, so planting it into the
    # table genuinely enlarges the union rather than re-stating it.
    target = None
    for surface in measurable:
        candidates = sorted(surface.roles - verdict.base_roles)
        if candidates:
            target = (surface, candidates[0])
            break
    if target is None:
        return False, ["  every role on every surface is already in the base table, so no plant "
                       "can enlarge the union and this control cannot run"]
    surface, role = target

    before = len(surface.intersect({role})) if role in verdict.added else 0
    if verdict.status(surface) == EXPOSED:
        lines.append(f"  note  {os.path.basename(surface.path)} is already EXPOSED before planting")

    clone = tempfile.mkdtemp(prefix="role-intersection-live-")
    try:
        shutil.rmtree(clone, ignore_errors=True)
        made = subprocess.run(["git", "clone", "--local", "--shared", "-q", git.root, clone],
                              capture_output=True, text=True)
        if made.returncode:
            return False, [f"  could not clone the repository to plant into: "
                           f"{made.stderr.strip().splitlines()[-1] if made.stderr.strip() else '?'}"]
        cloned = Git(clone)
        # A clone of a linked worktree carries only the checked-out branch as a local head, so the
        # base may exist here only as `origin/<base>`. Resolving it rather than assuming it is what
        # stops this control failing for a reason that has nothing to do with the instrument.
        resolved = next((candidate for candidate in (base, f"origin/{base}")
                         if cloned.out("rev-parse", "--verify", "-q", candidate)), None)
        if resolved is None:
            return False, [f"  the clone has no {base} and no origin/{base} to plant onto"]
        cloned.run("branch", "-f", base, resolved)
        cloned.run("checkout", "-q", "-B", "live-control-plant", base)

        source = cloned.show("live-control-plant", GATE_FILE)
        if source is None:
            return False, [f"  the clone has no {GATE_FILE} to plant into"]
        patched, count = re.subn(
            r"(VOUCHED_CONTROLS[^=]*=\s*\{\n)",
            f'\\1    "__live_control__": {{("{role}", "text")}},\n',
            source, count=1)
        if count != 1:
            return False, ["  could not patch VOUCHED_CONTROLS in the clone, so nothing was planted"]
        with open(os.path.join(clone, GATE_FILE), "w", encoding="utf-8") as handle:
            handle.write(patched)
        cloned.run("add", "-A")
        cloned.run("-c", "user.email=c@x", "-c", "user.name=c", "-c", "commit.gpgsign=false",
                   "commit", "-q", "-m", "live control plant")

        planted = measure(cloned, base)

        reached = role in planted.added
        ok = ok and reached
        lines.append(f"  {'sees ' if reached else 'BLIND'} role={role!r} planted on a real branch "
                     f"reached the union via for-each-ref + ast.parse "
                     f"({'in' if reached else 'NOT in'} the added set of {len(planted.added)})")

        match = next((p for p in planted.surfaces if p.path == surface.path), None)
        # Counted against `planted.added` rather than against `{role}` directly, so the number
        # follows the same path as the verdict. Counting it directly reported "0 → 3 row(s)" beside
        # a status of CLEAR when the union merge was broken — a true count of the wrong quantity,
        # sitting in the control that exists to catch exactly that.
        after = len(match.intersect(planted.added)) if match else 0
        moved = match is not None and after > before and planted.status(match) == EXPOSED
        ok = ok and moved
        lines.append(f"  {'sees ' if moved else 'BLIND'} {surface.path} moved "
                     f"{verdict.status(surface)} → {planted.status(match) if match else 'MISSING'}, "
                     f"intersection {before} → {after} row(s) over the real ledger")

        absent_planted, count = re.subn(
            r"(VOUCHED_CONTROLS[^=]*=\s*\{\n)",
            '\\1    "__live_control__": {("__role_that_cannot_exist__", "text")},\n',
            source, count=1)
        with open(os.path.join(clone, GATE_FILE), "w", encoding="utf-8") as handle:
            handle.write(absent_planted)
        cloned.run("add", "-A")
        cloned.run("-c", "user.email=c@x", "-c", "user.name=c", "-c", "commit.gpgsign=false",
                   "commit", "-q", "--amend", "-m", "live control absence plant")
        quiet = measure(cloned, base)
        stray = [p.path for p in quiet.surfaces if p.intersect({"__role_that_cannot_exist__"})]
        if stray:
            ok = False
            lines.append(f"  FALSE a role no ledger contains matched anyway: {stray}")
        else:
            lines.append(f"  quiet a role no ledger contains reached the union and matched 0 rows "
                         f"on all {len(quiet.surfaces)} surfaces, so a hit is not automatic")
        return ok, lines
    finally:
        shutil.rmtree(clone, ignore_errors=True)


# ------------------------------------------------------------------------- the hermetic control

FIXTURE_GATE = '''VOUCHED_CONTROLS: dict[str, set[tuple[str, str]]] = {
    "heading": {("board-title", "text")},
    "row": {("table-row", "hstack")},
%s}
'''

FIXTURE_ADDS = '    "callout": {("callout", "hstack")},\n'


def fixture_ledger(rows: list[tuple[str, str, str]]) -> str:
    body = "\n".join(
        f"| {state} | v-{state}/x/{node} | x | unclassified | mock=\"\" kind=x | "
        f"build=s.{state}/{node} text=\"\" role={role} kind=text |  |"
        for state, node, role in rows)
    return ("# Breadth ledger — fixture\n\n## Layers\n\n| Layer | Result | Detail |\n|---|---|---|\n"
            "| `breadth` | 2 finding(s) | covered-by-pair 2 · structure-unpaired 7 · extra 3 |\n\n"
            "## Present / divergent / absent\n\n"
            "| State | Affordance | Kind | Status | Mock value | Build value | Citation |\n"
            "|---|---|---|---|---|---|---|\n" + body + "\n")


OBITUARY_LEDGER = (
    "# Breadth ledger — fixture\n\n## This run did not produce a table\n\n"
    "The gate exited 3 without completing a measurement, so there are no rows below rather than "
    "no differences. What stopped it, and at which stage, verbatim:\n\n"
    "```\ninventory[ideal]: error: #fixture has no '.v-ideal' block\n```\n")


def hermetic_control() -> tuple[bool, list[str]]:
    """A throwaway repository with every answer planted, and each one required exactly.

    Nothing is planted in this corpus. `G4`'s seventeenth item: a control quoted inside the
    document it guards is found instead of the planted instance, and the control then passes for
    the wrong reason and passes silently.

    Five rows, and the two that carry the item:

      `silent`      a branch with ZERO diff on the gate file whose ledger uses a role another
                    branch adds. **EXPOSED.** This is M22, and it is the row that would have
                    reddened had this existed.
      `no-union`    the identical fixture measured with the added set forced empty. **CLEAR.**
                    The control fails if this agrees with `silent`, because an instrument that
                    answers the same either way has measured nothing.
    """
    root = tempfile.mkdtemp(prefix="role-intersection-control-")
    lines: list[str] = []
    try:
        git = Git(root)
        env_args = ("-c", "user.email=c@x", "-c", "user.name=c", "-c", "commit.gpgsign=false")

        def commit(message: str) -> None:
            git.run("add", "-A")
            git.run(*env_args, "commit", "-q", "-m", message)

        git.run("init", "-q", "-b", "main")
        os.makedirs(os.path.join(root, "scripts", "acceptance"))
        os.makedirs(os.path.join(root, FIDELITY_DIR))

        def write(rel: str, text: str) -> None:
            with open(os.path.join(root, rel), "w", encoding="utf-8") as handle:
                handle.write(text)

        # main: the baseline table, and one surface using only baseline roles.
        write(GATE_FILE, FIXTURE_GATE % "")
        write(f"{FIDELITY_DIR}/baseline.ledger.md",
              fixture_ledger([("ideal", "n1", "board-title"), ("ideal", "n2", "table-row")]))
        commit("base")

        # edits: adds `callout` to the table, and uses it on its own surface.
        git.run("checkout", "-q", "-b", "edits")
        write(GATE_FILE, FIXTURE_GATE % FIXTURE_ADDS)
        write(f"{FIDELITY_DIR}/edits.ledger.md",
              fixture_ledger([("ideal", "n3", "callout")]))
        commit("edits")

        # silent: ZERO diff on the gate file. Its ledger uses `callout`, which `edits` adds.
        git.run("checkout", "-q", "main")
        git.run("checkout", "-q", "-b", "silent")
        write(f"{FIDELITY_DIR}/silent.ledger.md",
              fixture_ledger([("error", "n4", "callout"), ("ideal", "n5", "board-title")]))
        write(f"{FIDELITY_DIR}/obituary.ledger.md", OBITUARY_LEDGER)
        commit("silent")
        git.run("checkout", "-q", "main")

        planted = git.run("diff", "--name-only", "main", "silent", "--", GATE_FILE).stdout.strip()
        if planted:
            return False, [f"  fixture is wrong: `silent` diffs the gate file ({planted})"]

        verdict = measure(git, "main")
        got = {os.path.basename(s.path).replace(".ledger.md", ""): verdict.status(s)
               for s in verdict.surfaces}
        want = {"baseline": CLEAR, "edits": EXPOSED, "silent": EXPOSED, "obituary": INCONCLUSIVE}

        ok = True
        for name in sorted(want):
            actual = got.get(name, "MISSING")
            good = actual == want[name]
            ok = ok and good
            lines.append(f"  {'ok  ' if good else 'FAIL'}  {name:10s} want {want[name]:12s} "
                         f"got {actual}")

        if verdict.added != {"callout"}:
            ok = False
            lines.append(f"  FAIL  added-role set should be {{'callout'}}, got {verdict.added}")
        if verdict.code() != 3:
            ok = False
            lines.append(f"  FAIL  a fixture carrying an obituary must exit 3, got "
                         f"{verdict.code()}")

        # The fail-if-agree row. Same fixture, added set forced empty: `silent` must go CLEAR.
        empty = measure(git, "main")
        empty.added = set()
        silent = next(s for s in empty.surfaces if s.path.endswith("silent.ledger.md"))
        if empty.status(silent) != CLEAR:
            ok = False
            lines.append("  FAIL  `silent` reads EXPOSED with an empty added set, so the verdict "
                         "does not depend on the union and the fixture proves nothing")
        else:
            lines.append("  ok    `silent` reads EXPOSED with the union and CLEAR without it, so "
                         "the answer depends on the union rather than on the ledger alone")

        lines.append(f"  ok    `silent` has zero diff on {GATE_FILE} and is still EXPOSED — "
                     "the M22 case, which is the whole point")

        # All three verdicts must be reachable, and on this corpus one of them is not observable:
        # `popover` is an obituary, 3 dominates, and exit 1 cannot be seen however much exposure a
        # plant creates. A gate whose findings code has never been produced is a gate whose findings
        # code is not known to work, so the fixture produces each one by filtering its own surfaces.
        for want_code, keep, why in (
                (0, lambda s: s.path.endswith("baseline.ledger.md"), "only a surface using baseline roles"),
                (1, lambda s: not s.path.endswith("obituary.ledger.md"), "exposure and nothing unreadable"),
                (3, lambda s: True, "an obituary in the set")):
            probe = measure(git, "main")
            probe.surfaces = [s for s in probe.surfaces if keep(s)]
            got_code = probe.code()
            good = got_code == want_code
            ok = ok and good
            lines.append(f"  {'ok  ' if good else 'FAIL'}  exit {want_code} is reachable — "
                         f"{why} gives {got_code}")

        return ok, lines
    finally:
        shutil.rmtree(root, ignore_errors=True)


# --------------------------------------------------------------------------------- the report

def guarded(label: str, run) -> tuple[bool, list[str]]:
    """Run a control, and turn anything it throws into a failed control rather than a traceback.

    Measured 2026-08-26 with a `git` on PATH that exits 128 for every invocation: the ref walk
    broke, `measure` raised `Inconclusive` from inside `hermetic_control`, nothing caught it, and
    the process died with a traceback and Python's default exit **1** — which in this gate means
    FINDINGS. That is precisely the confusion `Inconclusive`'s own docstring was written to prevent,
    reintroduced one frame further out: the control path had no handler at all, so a gate that could
    not test itself reported exposure it had never looked for.

    An exception here is never a verdict about the corpus. It is the instrument failing, so it takes
    the control code and prints the exception rather than swallowing it.
    """
    try:
        return run()
    except Exception as error:  # noqa: BLE001 — a control that throws is a control that failed
        detail = traceback.format_exc().strip().splitlines()
        return False, [f"  CONTROL FAILED  the {label} raised {type(error).__name__}: {error}",
                       f"                  at {detail[-3].strip() if len(detail) >= 3 else '?'}",
                       "                  Nothing below this line was tested, so nothing below it "
                       "is evidence."]


def report(verdict: Verdict, git: Git, base: str, run_live: bool,
           hermetic: tuple[bool, list[str]]) -> int:
    print("role-intersection gate — the union of every active branch's roles, per surface\n")

    ok_hermetic, hermetic_lines = hermetic
    print("Hermetic control (a throwaway repository, every answer planted and required exactly):")
    print("\n".join(hermetic_lines))
    print(f"  => {'the instrument answers all five planted cases' if ok_hermetic else 'CONTROL FAILED'}\n")

    ok_live = True
    if run_live:
        ok_live, live_lines = guarded("live control",
                                      lambda: live_control(git, base, verdict))
        print("Live presence control (planted onto a real branch of a throwaway clone):")
        print("\n".join(live_lines))
        print(f"  => {'a zero below is measured' if ok_live else 'CONTROL FAILED — a zero below is unproved'}\n")

    print("Branch set — established before any question about members of it:")
    print(f"  B1  {verdict.head_count:3d}  local heads")
    print(f"  B2  {verdict.merged_count:3d}  already merged into {base} — their additions are in the baseline")
    print(f"  B3  {len(verdict.per_branch):3d}  active refs read for a {GATE_FILE} table")
    print(f"  B4  {len(verdict.base_roles):3d}  roles in {base}'s VOUCHED_CONTROLS (ast.parse of the module, not a regex)")
    print(f"  B5  {len(verdict.union_roles):3d}  roles in the union across every active ref")
    print(f"  B6  {len(verdict.added):3d}  roles the union ADDS — the set every surface is walked against")
    if verdict.added:
        print(f"      {', '.join(sorted(verdict.added))}")
    for ref, total, adds in verdict.per_branch:
        if adds:
            print(f"      {ref} carries {total} roles, {adds} of them new")
    remote_refs = git.remotes()
    print(f"  B7  {len(remote_refs):3d}  refs under refs/remotes — OUTSIDE this measurement. A branch")
    print("      that exists here only as a remote ref is not in the union above.")
    if verdict.without_table:
        print(f"  B8  {len(verdict.without_table):3d}  active ref(s) with no {GATE_FILE} at all — no table to")
        print(f"      contribute, and indistinguishable here from one that deleted it: "
              f"{', '.join(verdict.without_table)}")
    print()

    print("Surface set — the union of ledgers across those refs, deduplicated by blob:")
    print(f"  S1  {len(verdict.surfaces):3d}  distinct (surface, blob) measurements")
    print(f"  S2  {len({s.path for s in verdict.surfaces}):3d}  distinct surface paths")
    print(f"  S3  {sum(1 for s in verdict.surfaces if not s.error):3d}  carrying a table this gate can read")
    print()

    print("Per surface — every one of them, including any that edited nothing:\n")
    header = f"  {'surface':30s} {'blob':8s} {'roles':>5s} {'rows':>5s} {'grep':>5s} {'wrap':>5s}  status"
    print(header)
    print("  " + "-" * (len(header) - 2))
    code_rows = []
    for surface in verdict.surfaces:
        status = verdict.status(surface)
        name = os.path.basename(surface.path)
        print(f"  {name:30s} {surface.blob:8s} {len(surface.roles):5d} {len(surface.sites):5d} "
              f"{surface.line_anchored:5d} {surface.collapsed:5d}  {status}")
        code_rows.append((surface, status))
    print()
    print("  roles = distinct role= values · rows = (role,kind) pairs · grep = line-anchored reader ·")
    print("  wrap  = whole-file whitespace-collapsed reader. Two readers, printed side by side, because")
    print("  a bare integer from an unnamed reader is an assertion wearing a measurement's clothes.")
    disagree = [s.path for s in verdict.surfaces if s.line_anchored != s.collapsed]
    if disagree:
        print(f"  ** the two readers DISAGREE on {disagree} — the collapsed figure is the complete one.")
    print()

    for surface, status in code_rows:
        if status != EXPOSED:
            continue
        print(f"EXPOSED  {surface.path}  (blob {surface.blob}; on {', '.join(surface.refs)})")
        print("  Its recorded measurement uses a role the union adds. Zero diff on the gate file")
        print("  would not have shown this: the quota rule keys on the build node's role.")
        for line, role, kind in surface.intersect(verdict.added):
            print(f"    {surface.path}:{line}  role={role} kind={kind}")
        print()

    for surface, status in code_rows:
        if status != INCONCLUSIVE:
            continue
        print(f"INCONCLUSIVE  {surface.path}  (blob {surface.blob}; on {', '.join(surface.refs)})")
        print(f"  {surface.error}")
        print("  A role sweep over it returns zero. That zero is an absence of measurement, not an")
        print("  absence of exposure, and a two-state gate would have reported this surface clean.")
        print()

    print("What this run did NOT check:")
    print(f"  * the unpaired remainder. This reads roles from the ledger, which records PAIRED build")
    print(f"    nodes only. Every surface's own breadth arithmetic, for the nodes with no role here:")
    for surface in verdict.surfaces:
        if surface.unpaired:
            detail = " · ".join(f"{k} {v}" for k, v in sorted(surface.unpaired.items()))
            print(f"      {os.path.basename(surface.path):30s} {detail}")
    print("    Those carry no `role=` in any tracked file. Closing that needs the MEASURE build's")
    print(f"    dumps, which are untracked; `make mock-fidelity SURFACE=servers` exits 3 today.")
    print("  * the working tree. Each ledger is a frame — the last recorded measurement — so a stale")
    print("    one answers about the surface as it was. The blob column is what makes that visible.")
    for note in verdict.unreadable_branches:
        print(f"  * a branch table that would not parse: {note}")
    for note in verdict.unreadable_surfaces:
        print(f"  * a ledger that would not read: {note}")
    print()

    code = verdict.code()
    if not ok_hermetic or (run_live and not ok_live):
        print(f"CONTROL-FAILED role-intersection: a control failed, so nothing below it is "
              f"evidence. This is exit {CONTROL_FAILED} and not {INCONCLUSIVE_CODE}: the corpus "
              f"was not measured badly, the instrument is not known to work.")
        return CONTROL_FAILED
    verdicts = {CLEAR: "clean", EXPOSED: "exposed", INCONCLUSIVE: "inconclusive"}
    tally = collections.Counter(verdicts[s] for _, s in code_rows)
    summary = " · ".join(f"{v} {k}" for k, v in sorted(tally.items()))
    if code == 0:
        print(f"CLEAN role-intersection: {summary}. No surface's recorded measurement uses a role")
        print("      the union adds, and the controls above are what make that zero a measurement.")
    elif code == 1:
        print(f"FINDINGS role-intersection: {summary}. A call to make before merging, not yet a")
        print("      defect: check whether the quota rule reclassifies any node listed above.")
    else:
        print(f"INCONCLUSIVE role-intersection: {summary}. At least one surface or branch could not")
        print("      be read, and a surface that was never measured is not a clean surface.")
    return code


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Derive the union of every active branch's build roles and walk every "
                    "fidelity surface against it, including surfaces that edited nothing.")
    parser.add_argument("--base", default="main",
                        help="the ref whose table is the baseline (default: main)")
    parser.add_argument("--repo", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."),
                        help="repository root")
    parser.add_argument("--control-only", action="store_true",
                        help="run the hermetic control and exit; measures no corpus")
    parser.add_argument("--no-live-control", action="store_true",
                        help="skip the live presence control (it re-measures once per surface)")
    args = parser.parse_args()

    if args.control_only:
        ok, lines = guarded("hermetic control", hermetic_control)
        print("Hermetic control:")
        print("\n".join(lines))
        print(f"  => {'ok' if ok else 'CONTROL FAILED'}")
        return 0 if ok else CONTROL_FAILED

    git = Git(os.path.abspath(args.repo))

    # The control runs FIRST, and the corpus is not measured until it has spoken. The earlier order
    # measured first, so a broken ref walk raised `Inconclusive` before any control existed and the
    # process answered 3 — a verdict about the corpus, produced by an instrument nothing had tested
    # (`grok-4.6`, 2026-08-26). A control that runs after the measurement cannot certify it.
    hermetic = guarded("hermetic control", hermetic_control)
    if not hermetic[0]:
        print("Hermetic control (a throwaway repository, every answer planted and required "
              "exactly):")
        print("\n".join(hermetic[1]))
        print(f"\nCONTROL-FAILED role-intersection: the control failed, so the corpus was not "
              f"measured at all. This is exit {CONTROL_FAILED} and not {INCONCLUSIVE_CODE} — "
              f"nothing is known about the corpus because nothing was asked of it.")
        return CONTROL_FAILED

    try:
        verdict = measure(git, args.base)
    except Inconclusive as error:
        print(f"INCONCLUSIVE role-intersection: {error}")
        print("      The baseline could not be established, so nothing could be measured against")
        print("      it. The control above held, so this is a fact about the corpus.")
        return INCONCLUSIVE_CODE
    except Exception as error:  # noqa: BLE001 — see guarded(); an unexpected throw is not a verdict
        print(f"CONTROL-FAILED role-intersection: measuring the corpus raised "
              f"{type(error).__name__}: {error}")
        print(f"      {traceback.format_exc().strip().splitlines()[-3].strip()}")
        return CONTROL_FAILED
    try:
        return report(verdict, git, args.base, run_live=not args.no_live_control,
                      hermetic=hermetic)
    except Exception as error:  # noqa: BLE001
        print(f"CONTROL-FAILED role-intersection: reporting raised "
              f"{type(error).__name__}: {error}")
        return CONTROL_FAILED


if __name__ == "__main__":
    sys.exit(main())
