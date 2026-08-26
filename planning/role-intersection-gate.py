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

## Exit codes, and why three

They mirror `mock_fidelity.py` deliberately, and the third is the reason this is not a diff:

    0   no surface's recorded measurement uses a role the union adds
    1   at least one does — a call to make, not yet a defect
    3   inconclusive — a branch's table or a surface's ledger could not be read, and the
        verdict depended on it
    2   usage

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
  * a **live presence** control over the real corpus: a role known to be on each surface is injected
    into the added set, and that surface must go from `CLEAR` to `EXPOSED`. A role that cannot exist
    is injected and must leave it `CLEAR`. Both print the count they moved, so the zero this gate
    reports today is measured rather than blind.
"""

from __future__ import annotations

import argparse
import ast
import collections
import os
import re
import shutil
import subprocess
import sys
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
        return (self.out("for-each-ref", "--format=%(refname:short)", "refs/heads") or "").split()

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
    match = re.search(r"^VOUCHED_CONTROLS[^=]*=\s*(\{.*?^\})", source, re.S | re.M)
    if not match:
        return set(), "no VOUCHED_CONTROLS literal found"
    try:
        table = ast.literal_eval(match.group(1))
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
        """Two readers over the same file, and both counts are reported.

        `line_anchored` is what a `grep` sees. `collapsed` reads the file whole with every run of
        whitespace — newlines included — reduced to one space, which is `claim-sweep.py`'s finding:
        a line-anchored reader cannot see what a text editor wrapped. The ledger is generated and
        does not wrap today, so the two agree; they are printed side by side anyway, because the
        day they disagree is the day the line-anchored figure is the wrong answer and nothing else
        would say so.
        """
        for number, line in enumerate(self.text.splitlines(), 1):
            for match in ROLE_KIND.finditer(line):
                self.line_anchored += 1
                self.sites.append((number, match.group(1), match.group(2)))
        collapsed, offsets = collapse(self.text)
        for match in ROLE_KIND.finditer(collapsed):
            self.collapsed += 1
            _ = offsets  # line mapping is carried for the report, see `line_of`
        self.collapsed_lines = [line_of(offsets, m.start()) for m in ROLE_KIND.finditer(collapsed)]

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


def line_of(offsets: list[int], position: int) -> int:
    return offsets[position] if position < len(offsets) else -1


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

    def status(self, surface: SurfaceRead) -> str:
        if surface.error:
            return INCONCLUSIVE
        return EXPOSED if surface.intersect(self.added) else CLEAR

    def code(self) -> int:
        states = [self.status(s) for s in self.surfaces]
        if self.unreadable_branches or self.unreadable_surfaces or INCONCLUSIVE in states:
            return 3
        return 1 if EXPOSED in states else 0


def measure(git: Git, base: str, inject: set[str] | None = None) -> Verdict:
    refs, head_count, merged_count = active_refs(git, base)

    base_source = git.show(base, GATE_FILE)
    if base_source is None:
        raise SystemExit(f"INCONCLUSIVE role-intersection: {base}:{GATE_FILE} is not in the tree")
    base_roles, error = roles_from_gate_source(base_source)
    if error:
        raise SystemExit(f"INCONCLUSIVE role-intersection: {base}:{GATE_FILE} — {error}")

    union = set(base_roles)
    per_branch: list[tuple[str, int, int]] = []
    unreadable_branches: list[str] = []
    for ref in refs[1:]:
        source = git.show(ref, GATE_FILE)
        if source is None:
            # Not an error: a branch that predates the file has no table to contribute. It is
            # recorded so the denominator below is honest about how many refs were actually read.
            per_branch.append((ref, 0, 0))
            continue
        roles, error = roles_from_gate_source(source)
        if error:
            unreadable_branches.append(f"{ref}:{GATE_FILE} — {error}")
            continue
        per_branch.append((ref, len(roles), len(roles - base_roles)))
        union |= roles

    added = (union - base_roles) | (inject or set())
    surfaces, unreadable_surfaces = read_surfaces(git, refs)
    return Verdict(base_roles, union, added, per_branch, unreadable_branches,
                   surfaces, unreadable_surfaces, head_count, merged_count)


# ---------------------------------------------------------------------------- the live control

def live_control(git: Git, base: str, verdict: Verdict) -> tuple[bool, list[str]]:
    """Inject a role known present, then one that cannot exist, and watch the count move.

    Plant a known instance, confirm the instrument sees it, then trust the zero. This runs against
    the real corpus and mutates nothing on disk: the injection is a parameter to `measure`, so
    there is no planted string for a later sweep to trip over — the trap `citation-gate.py` names,
    where a control quoted inside the document it guards is matched instead of the planted instance
    and passes for the wrong reason.
    """
    lines: list[str] = []
    ok = True

    measurable = [s for s in verdict.surfaces if not s.error]
    if not measurable:
        return False, ["  no measurable surface to plant into, so the zero above is unproved"]

    for surface in measurable:
        known = sorted(surface.roles)[0]
        planted = measure(git, base, inject={known}).surfaces
        match = next((p for p in planted if p.blob == surface.blob), None)
        hits = len(match.intersect({known})) if match else 0
        moved = hits > 0
        ok = ok and moved
        lines.append(
            f"  {'sees' if moved else 'BLIND'}  {surface.path:38s} planting role={known!r} "
            f"moved its intersection 0 → {hits} row(s)")

    absent = "__role_that_cannot_exist__"
    planted = measure(git, base, inject={absent})
    stray = [(p.path, len(p.intersect({absent}))) for p in planted.surfaces if p.intersect({absent})]
    if stray:
        ok = False
        lines.append(f"  FALSE   a role no ledger contains matched anyway: {stray}")
    else:
        lines.append(f"  quiet   planting role={absent!r} matched 0 rows on all "
                     f"{len(planted.surfaces)} surfaces, so a hit is not automatic")
    return ok, lines


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
        return ok, lines
    finally:
        shutil.rmtree(root, ignore_errors=True)


# --------------------------------------------------------------------------------- the report

def report(verdict: Verdict, git: Git, base: str, run_live: bool) -> int:
    print("role-intersection gate — the union of every active branch's roles, per surface\n")

    ok_hermetic, hermetic_lines = hermetic_control()
    print("Hermetic control (a throwaway repository, every answer planted and required exactly):")
    print("\n".join(hermetic_lines))
    print(f"  => {'the instrument answers all five planted cases' if ok_hermetic else 'CONTROL FAILED'}\n")

    ok_live = True
    if run_live:
        ok_live, live_lines = live_control(git, base, verdict)
        print("Live presence control (planted into the parameter, never into the corpus):")
        print("\n".join(live_lines))
        print(f"  => {'a zero below is measured' if ok_live else 'CONTROL FAILED — a zero below is unproved'}\n")

    print("Branch set — established before any question about members of it:")
    print(f"  B1  {verdict.head_count:3d}  local heads")
    print(f"  B2  {verdict.merged_count:3d}  already merged into {base} — their additions are in the baseline")
    print(f"  B3  {len(verdict.per_branch):3d}  active refs read for a {GATE_FILE} table")
    print(f"  B4  {len(verdict.base_roles):3d}  roles in {base}'s VOUCHED_CONTROLS (ast.literal_eval, not grep)")
    print(f"  B5  {len(verdict.union_roles):3d}  roles in the union across every active ref")
    print(f"  B6  {len(verdict.added):3d}  roles the union ADDS — the set every surface is walked against")
    if verdict.added:
        print(f"      {', '.join(sorted(verdict.added))}")
    for ref, total, adds in verdict.per_branch:
        if adds:
            print(f"      {ref} carries {total} roles, {adds} of them new")
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
        print("INCONCLUSIVE role-intersection: a control failed, so nothing below it is evidence.")
        return 3
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
        ok, lines = hermetic_control()
        print("Hermetic control:")
        print("\n".join(lines))
        print(f"  => {'ok' if ok else 'CONTROL FAILED'}")
        return 0 if ok else 3

    git = Git(os.path.abspath(args.repo))
    verdict = measure(git, args.base)
    return report(verdict, git, args.base, run_live=not args.no_live_control)


if __name__ == "__main__":
    sys.exit(main())
