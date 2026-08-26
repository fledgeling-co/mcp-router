#!/usr/bin/env python3
"""Every absence sweep in this corpus must carry a presence control. This is what checks that.

## The defect this exists for

`G8`, second half. **An absence check cannot detect its own blindness.** A sweep that returns zero
because it is looking in the wrong place, at the wrong granularity, or with the wrong reader
returns a clean answer, and a clean answer is what everybody wanted anyway.

Four measured instances in this repository, all four of which passed at the time:

  * a **line-anchored `grep`** used as an absence sweep over hard-wrapped prose returned `0` for a
    phrase present **twice**, and a verbatim quotation was reported as a paraphrase — to the party
    who had quoted it correctly, who then adopted the wrong version.
  * a **sentinel that matched the product's own legitimate copy**, so the control passed on the
    wrong string and said nothing about the planted one.
  * an **`awk` reading the wrong AX column**, which produced a well-formed count of the wrong thing.
  * a first-pass sweep scoped to **`scripts/` alone** that returned zero while the instances sat in
    `app/Scripts/` and `planning/` — filed minutes after the item about answering at the wrong scope.

The remedy is one line and this repo already knows it: **plant a known instance, confirm the
instrument sees it, then trust the zero.** Every sweeping script here already carries a control.
**Nothing checks that the next one does**, and that is the whole gap.

## Why a gate rather than a rule

The rule has been written down twice — in `claim-sweep.py`'s docstring and in the `G8` brief — and a
rule with nothing downstream depending on it reads as a standard to satisfy rather than a call to
make. `mock_fidelity.py`'s header comment is the worked example: ten lines recording exactly this
class of invariant, nothing reading them, and the very exposure they describe went unmeasured.

So this does three things a rule cannot:

  1. **Discovers** sweeping scripts across the tracked corpus, so a new one is in scope the moment
     it is tracked rather than when somebody remembers.
  2. **Requires a disposition** for each — a runnable control, an explicit waiver with a reason, or
     an explicit "this is not a sweep". Silence is not a disposition.
  3. **Runs** the declared controls rather than believing the registry, so a control that has rotted
     into a no-op reddens instead of continuing to reassure.

## Why the registry is a ratchet and not a demand

Discovery finds 57 tracked scripts carrying two or more sweep markers. A gate that demands all 57
grow a runnable control this week either never goes green or gets softened until it means nothing —
`citation-gate.py`'s reasoning about bare citations, applied to the same corpus.

So what exists today is **grandfathered by name**, and the gate blocks on what is *new*: a newly
tracked script matching discovery with no entry, a declared control that fails, or a registry entry
whose file has gone. The grandfathered set is a visible backlog with a count that may fall, rather
than an amnesty with no number attached.

**Grandfathered is not a pass and this gate never says it is.** Each run prints the grandfathered
count beside the controlled count, and they are never blended into one figure.

## Discovery, and the four readers behind it

No count here is printed bare, and no file is discovered by an unnamed reader. Five sweeps over one
phrase in one file once returned four different answers and only the widest was complete, so every
figure below carries the identity of the reader that produced it and every discovered file names
which markers fired on it.

    V1  a counting or existence grep      `grep -c`, `grep -q`, `grep -L`
    V2  zero is the answer                `== 0`, `-eq 0`, `if not count`
    V3  absence vocabulary                sweep, absence, absent, nothing found, returns 0
    V4  an empty collection is the answer `len(...) == 0`, `not rows`

A file is discovered at **two or more** markers. One marker alone is too wide — 84 of 107 tracked
scripts carry at least one — and the threshold is printed with the count at each level so the choice
is visible rather than buried. Every reader reads whole files.

## Its own control, because this script is an absence sweep too

This gate's headline claim is *no undisposed sweep exists*, which is an absence claim made by a
regex, which is the exact shape it exists to distrust. So it plants, in a temp directory that is
never this corpus:

  * a script that **is** a sweep — discovery must find it;
  * a script that is **not** — discovery must not;
  * a registry entry whose control command **exits 1** — the runner must report it failing.

That third one is the one that matters. A control-runner that cannot report a failing control is a
decoration, and this gate's whole value over the written rule is that it executes.

## Exit codes

    0   every discovered sweep is disposed and every declared control passed
    1   findings — a new undisposed sweep, a rotted control, a stale or mislabelled row
    3   inconclusive — the registry is missing or unreadable, or `git ls-files` returned no
        script at all, so the corpus this gate would answer about does not exist
    4   the control failed, so nothing this run printed is evidence of anything
    2   usage

**3 and 4 were one code until 2026-08-26.** They answer opposite questions. A 3 means the
instrument works and there is nothing to point it at; a 4 means the instrument is not known to work
and its output should not be read. Collapsing them makes a broken gate and an empty corpus
indistinguishable downstream, which is a gate that cannot report its own blindness — this file's
subject, one layer up. `role-intersection-gate.py` splits them the same way and for the same reason.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import traceback

REGISTRY = "planning/sweep-controls.json"
CONTROL_TIMEOUT = 120

# Four readers, named. Each is one way a script announces that it treats a zero as an answer.
MARKERS: dict[str, re.Pattern] = {
    "V1": re.compile(r"grep\s+-[a-zA-Z]*[cqL]"),
    # `len(...) == 0` used to fire V2 *and* V4, so one statement reached the two-marker threshold
    # on its own and the "two independent signals" claim was false for that shape
    # (`gemini-3.7-flash-high`, 2026-08-26, File 2 finding b1). V2 now excludes what V4 owns.
    "V2": re.compile(r"(?<!\))\s(?:==\s*0\b|!=\s*0\b|-eq\s+0\b)|\bif\s+not\s+\w*(?:count|hits|matches|found)"),
    "V3": re.compile(r"\b(?:sweep|absence|absent|no instance|nothing found|returns 0)\b", re.I),
    "V4": re.compile(r"len\([^)]*\)\s*==\s*0|\bnot\s+\w*(?:rows|sites|hits)\b"),
}
MARKER_NAMES = {
    "V1": "a counting or existence grep",
    "V2": "zero is the answer",
    "V3": "absence vocabulary",
    "V4": "an empty collection is the answer",
}
THRESHOLD = 2

DISPOSITIONS = ("control", "grandfathered", "not-a-sweep", "waived")

CONTROL_FAILED = 4
INCONCLUSIVE_CODE = 3


SHEBANG = re.compile(r"^#!.*\b(?:sh|bash|zsh|python3?|node|perl|ruby)\b")

#: The two reasons a tracked path does not reach discovery, named so the count can be printed
#: beside the corpus rather than described in prose next to it.
DISCARDS = ("vendor/", "no .py or .sh extension")


def is_shebang_script(root: str, relative: str) -> bool:
    """Whether a path with no script extension is nonetheless a script, by its first line.

    This is the half of the extension filter that is a real hole rather than a scope: a tracked
    `planning/hooks/pre-commit` is a shell script that discovery never opens. Naming it costs one
    `read(2)` per extensionless path and turns an unexamined set into a listed one.
    """
    if "." in os.path.basename(relative):
        return False
    try:
        with open(os.path.join(root, relative), encoding="utf-8") as handle:
            return bool(SHEBANG.match(handle.readline()))
    except (OSError, UnicodeDecodeError):
        return False


def tracked_scripts(root: str) -> tuple[list[str], dict[str, list[str]], list[str]]:
    """Every tracked `.py`/`.sh` outside `vendor/`, and everything this reader threw away to get it.

    The filter here narrows 1662 tracked paths to 114, and a narrowing nobody counts is this item's
    own subject one layer down. It used to be a comprehension, which `reader-accounting.py` classes
    as silent by shape — a filtered item leaves no trace by construction — so the drop could only
    ever be *declared* in `reader-accounting.tsv`. A declaration would have hidden a real hole:
    two tracked shell scripts carry no `.sh` and were outside every figure this gate prints. So the
    discards come back with the corpus and are printed with it, which is what the gate demands of
    every other reader in the tree.
    """
    out = subprocess.run(["git", "ls-files"], capture_output=True, text=True, cwd=root)
    kept: list[str] = []
    discarded: dict[str, list[str]] = {reason: [] for reason in DISCARDS}
    shebang: list[str] = []
    # `splitlines` rather than `split("\n")` so the trailing empty field is never produced, and
    # this loop has no drop site that is not a real path.
    for path in out.stdout.splitlines():
        if path.startswith("vendor/"):
            discarded["vendor/"].append(path)
            continue
        if not path.endswith((".py", ".sh")):
            discarded["no .py or .sh extension"].append(path)
            if is_shebang_script(root, path):
                shebang.append(path)
            continue
        kept.append(path)
    return kept, discarded, shebang


def markers_for(text: str) -> list[str]:
    return [name for name, pattern in MARKERS.items() if pattern.search(text)]


class Corpus:
    """What discovery found, and everything it did not look at, carried together on purpose.

    An earlier shape returned the four figures the report prints and left the filter's discards
    unreturned, so `reader-accounting.py` classed `tracked_scripts` as a silent drop. Binding the
    discards to the corpus is what makes them printable, and printing them is the difference
    between a scope and a blind spot.
    """

    def __init__(self, hits, by_level, files, undecodable, discarded, shebang):
        self.hits = hits
        self.by_level = by_level
        self.files = files
        self.size = len(files)
        self.undecodable = undecodable
        self.discarded = discarded
        self.shebang = shebang

    @property
    def considered(self) -> int:
        return self.size + sum(len(v) for v in self.discarded.values())


def discover(root: str) -> Corpus:
    """Every tracked script, with the markers that fired on it.

    Returns the discovered set, the count at each threshold, the corpus size, the files that
    could not be decoded — reported rather than skipped in silence, because a file this reader
    could not open is a file it has said nothing about — and the tracked paths the extension
    filter threw away before any of that.
    """
    hits: dict[str, list[str]] = {}
    by_level: dict[int, int] = {1: 0, 2: 0, 3: 0, 4: 0}
    undecodable: list[str] = []
    files, discarded, shebang = tracked_scripts(root)
    for relative in files:
        path = os.path.join(root, relative)
        try:
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
        except (OSError, UnicodeDecodeError) as error:
            undecodable.append(f"{relative}: {type(error).__name__}")
            continue
        found = markers_for(text)
        for level in range(1, len(found) + 1):
            by_level[level] = by_level.get(level, 0) + 1
        if len(found) >= THRESHOLD:
            hits[relative] = found
    return Corpus(hits, by_level, files, undecodable, discarded, shebang)


def load_registry(root: str) -> tuple[dict[str, dict], str | None]:
    path = os.path.join(root, REGISTRY)
    if not os.path.exists(path):
        return {}, f"no registry at {REGISTRY}"
    try:
        with open(path, encoding="utf-8") as handle:
            raw = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        return {}, f"{REGISTRY} did not read: {type(error).__name__}: {error}"
    entries = {entry["path"]: entry for entry in raw.get("sweeps", [])}
    return entries, None


def run_control(root: str, entry: dict) -> tuple[bool, str]:
    command = entry.get("control")
    if not command:
        return False, "disposition is `control` but no command is declared"
    # A registry written by hand naturally carries a string. Splitting it here rather than handing
    # it to `subprocess` whole is what stops every string-formed control failing with
    # FileNotFoundError and reading as a rotted control (`gemini-3.7-flash-high`, 2026-08-26,
    # File 2 finding d2).
    if isinstance(command, str):
        command = shlex.split(command)
    try:
        done = subprocess.run(command, capture_output=True, text=True, cwd=root,
                              timeout=CONTROL_TIMEOUT)
    except subprocess.TimeoutExpired:
        return False, f"control did not finish in {CONTROL_TIMEOUT}s"
    except OSError as error:
        return False, f"control would not start: {type(error).__name__}: {error}"
    if done.returncode != 0:
        tail = (done.stdout + done.stderr).strip().splitlines()
        said = tail[-1] if tail else "(no output)"
        return False, f"control exited {done.returncode} — it said: {said}"
    return True, "exited 0"


# ------------------------------------------------------------------------------- the control

SWEEP_FIXTURE = """#!/usr/bin/env python3
# A planted sweep. It counts and treats the zero as an answer.
import re, sys
hits = re.findall(r'needle', open(sys.argv[1]).read())
if len(hits) == 0:
    print('absence confirmed')
"""

QUIET_FIXTURE = """#!/usr/bin/env python3
# Planted as a non-sweep: it asserts nothing about a zero.
def add(a, b):
    return a + b
"""

# A tracked script with no script extension. D0 does not reach it and the X block must say so; the
# X block is an absence claim ("nothing else is being dropped") and gets a planted instance like
# every other absence claim here.
HOOK_FIXTURE = """#!/bin/sh
echo hook
"""


def guarded(run) -> tuple[bool, list[str]]:
    """Run the control, and turn anything it throws into a failed control rather than a traceback.

    An uncaught exception exits **1**, which in this gate means FINDINGS — so a control that could
    not run at all would have reported undisposed sweeps it never looked for. Measured on the sister
    gate 2026-08-26 with a `git` that exits 128: traceback, exit 1, no verdict line.
    """
    try:
        return run()
    except Exception as error:  # noqa: BLE001 — a control that throws is a control that failed
        detail = traceback.format_exc().strip().splitlines()
        return False, [f"  CONTROL FAILED  the control raised {type(error).__name__}: {error}",
                       f"                  at {detail[-3].strip() if len(detail) >= 3 else '?'}"]


def self_control(root: str) -> tuple[bool, list[str]]:
    """Plant a sweep, a non-sweep, and a control that fails. Require all three answers.

    Nothing is planted in this corpus. A control quoted inside the document it guards is matched
    instead of the planted instance and then passes for the wrong reason — `citation-gate.py`'s
    finding, and one of the four instances in the docstring above.
    """
    lines: list[str] = []
    ok = True
    temp = tempfile.mkdtemp(prefix="sweep-control-")
    try:
        git = ["git", "-c", "user.email=c@x", "-c", "user.name=c", "-c", "commit.gpgsign=false"]
        subprocess.run(["git", "init", "-q", "-b", "main", temp], capture_output=True)
        for name, body in (("planted_sweep.py", SWEEP_FIXTURE), ("planted_quiet.py", QUIET_FIXTURE),
                           ("planted_hook", HOOK_FIXTURE), ("planted_notes.md", "# not a script\n")):
            with open(os.path.join(temp, name), "w", encoding="utf-8") as handle:
                handle.write(body)
        subprocess.run(["git", "add", "-A"], capture_output=True, cwd=temp)
        subprocess.run(git + ["commit", "-q", "-m", "fixture"], capture_output=True, cwd=temp)

        corpus = discover(temp)
        found = corpus.hits
        saw_sweep = "planted_sweep.py" in found
        saw_quiet = "planted_quiet.py" in found
        ok = ok and saw_sweep and not saw_quiet
        lines.append(f"  {'sees ' if saw_sweep else 'BLIND'} a planted sweep is discovered "
                     f"({'markers ' + ','.join(found.get('planted_sweep.py', [])) if saw_sweep else 'not found'})")
        lines.append(f"  {'quiet' if not saw_quiet else 'FALSE'} a planted non-sweep is not "
                     f"discovered, so discovery is not automatic")

        # The discard census, armed both ways. `planted_hook` is a script D0 cannot see and the
        # census must name it; `planted_notes.md` is a drop the census must NOT call a script, so a
        # census that simply listed every extensionless-or-otherwise drop would fail here.
        saw_hook = "planted_hook" in corpus.shebang
        saw_notes = "planted_notes.md" in corpus.shebang
        counted = corpus.considered == corpus.size + sum(len(v) for v in corpus.discarded.values())
        ok = ok and saw_hook and not saw_notes and counted
        lines.append(f"  {'sees ' if saw_hook else 'BLIND'} a tracked script with no script "
                     f"extension is named by the discard census "
                     f"({'planted_hook' if saw_hook else 'not named — D0 drops it in silence'})")
        lines.append(f"  {'quiet' if not saw_notes else 'FALSE'} a planted non-script drop is not "
                     f"called a script, so the census is a reading and not a list of everything")
        lines.append(f"  {'ok   ' if counted else 'FAIL '} kept + discarded accounts for every path "
                     f"`git ls-files` returned ({corpus.size} + "
                     f"{sum(len(v) for v in corpus.discarded.values())} = {corpus.considered})")

        failing = {"path": "planted_sweep.py", "disposition": "control",
                   "control": ["python3", "-c", "import sys; sys.exit(1)"]}
        passed, said = run_control(temp, failing)
        ok = ok and not passed
        lines.append(f"  {'sees ' if not passed else 'BLIND'} a control that exits 1 is reported "
                     f"failing — it said: {said}")

        working = {"path": "planted_sweep.py", "disposition": "control",
                   "control": ["python3", "-c", "import sys; sys.exit(0)"]}
        passed, said = run_control(temp, working)
        ok = ok and passed
        lines.append(f"  {'ok   ' if passed else 'FAIL '} a control that exits 0 is reported "
                     f"passing, so the runner is not simply always red")
        return ok, lines
    finally:
        shutil.rmtree(temp, ignore_errors=True)


# -------------------------------------------------------------------------------- the report

def report(root: str) -> int:
    print("sweep-control gate — every absence sweep must carry a presence control\n")

    ok, control_lines = guarded(lambda: self_control(root))
    print("Control (planted in a temp directory, never in this corpus):")
    print("\n".join(control_lines))
    print(f"  => {'the instrument fires and can report a failure' if ok else 'CONTROL FAILED'}\n")
    if not ok:
        print(f"CONTROL-FAILED sweep-control: the control failed, so nothing below it is evidence. "
              f"This is exit {CONTROL_FAILED} and not {INCONCLUSIVE_CODE} — the corpus is fine and "
              f"the instrument is not known to be.")
        return CONTROL_FAILED

    census = discover(root)
    found, by_level, corpus, undecodable = census.hits, census.by_level, census.size, census.undecodable
    print("Discovery — four readers, each named, over the whole tracked script corpus:")
    print(f"  D0  {corpus:4d}  tracked .py/.sh files, vendor/ excluded")
    for level in sorted(by_level):
        mark = "  <= the threshold" if level == THRESHOLD else ""
        print(f"  D{level}  {by_level[level]:4d}  carrying {level}+ marker(s){mark}")
    print(f"  D5  {len(found):4d}  discovered as absence sweeps")
    for name in sorted(MARKER_NAMES):
        count = sum(1 for markers in found.values() if name in markers)
        print(f"        {name} {MARKER_NAMES[name]:34s} fired on {count:3d} of them")
    if undecodable:
        print(f"  ** {len(undecodable)} file(s) could not be decoded and are outside every count "
              f"above: {undecodable}")
    print()

    # The filter that produces D0 is itself a reader discarding raw input, and until 2026-08-26 it
    # discarded silently — `reader-accounting.py` found it and exited 1 on this gate alone. The
    # counts below are that reader reporting rather than being declared, and they are printed as
    # their own figures rather than folded into D0.
    print("What the D0 filter discarded, counted rather than described:")
    print(f"  X0  {census.considered:4d}  paths returned by `git ls-files`, before any filter")
    for reason in DISCARDS:
        print(f"  X-  {len(census.discarded[reason]):4d}  dropped: {reason}")
    print(f"  X+  {len(census.shebang):4d}  of those drops are scripts by shebang with no script "
          f"extension —")
    if census.shebang:
        for path in census.shebang:
            print(f"            {path}")
        print("        outside D0 and therefore outside every figure above. Named here because a")
        print("        script this gate never opens is a script it has said nothing about.")
    else:
        print("        none today, so the extension filter drops no script it can recognise.")
    print()

    if corpus == 0:
        print("INCONCLUSIVE sweep-control: `git ls-files` returned no script at all. A clean")
        print("      verdict over an empty corpus is a pass because nothing was measured.")
        return INCONCLUSIVE_CODE

    print("What discovery does NOT reach, printed rather than implied:")
    print("  * files that are not `.py` or `.sh` — an extensionless executable, `.zsh`, a node")
    print("    script. They are outside D0 entirely, so they are outside every figure above.")
    print("    The X block above counts them, and names the ones that are scripts by shebang.")
    print("  * idiomatic absence checks these four readers do not spell: `if not results:`,")
    print("    `assert not errors`, a bare `if count == 0:` with no other marker. They fall below")
    print("    the threshold and are not discovered.")
    print("  * whether a declared control is a real control. This runs it and reads its exit code;")
    print("    a command that exits 0 without testing anything passes. `proves` records the intent")
    print("    in prose and this gate does not verify it.")
    print()

    entries, registry_error = load_registry(root)
    if registry_error:
        print(f"INCONCLUSIVE sweep-control: {registry_error}")
        print("      Without it, every discovered sweep is undisposed and the number below would")
        print("      be a property of the missing file rather than of the corpus.")
        return INCONCLUSIVE_CODE

    findings: list[str] = []

    unregistered = sorted(set(found) - set(entries))
    # An entry with a misspelled or invented disposition is in `entries`, so it is not
    # `unregistered`; its file exists, so it is not `stale`; it is not `control`, so nothing runs.
    # It therefore produced no finding at all, and the docstring's "silence is the only answer this
    # gate refuses" was false for it (`gemini-3.7-flash-high`, 2026-08-26, File 2 finding d1).
    mislabelled = sorted(path for path, entry in entries.items()
                         if entry.get("disposition") not in DISPOSITIONS)
    # A registered row whose file is still in the tree but which discovery no longer matches had no
    # class at all: not `unregistered` (it is in the registry), not `stale` (the file exists), not
    # `mislabelled` (its word is one of the four). It was counted in the grandfathered tally and
    # nowhere else, so the backlog figure was one larger than the set discovery claims. That is a
    # hole in the classifier rather than a defect in the corpus, so it is printed rather than
    # failed: the two ways to close it — drop the row, or widen the readers — are both owner calls,
    # and dropping a row to make an inventory agree inverts the check this gate is.
    undiscovered = sorted(path for path in entries
                          if path not in found and os.path.exists(os.path.join(root, path)))
    tally = {kind: 0 for kind in DISPOSITIONS}
    for path, entry in entries.items():
        if entry.get("disposition") in tally:
            tally[entry["disposition"]] += 1

    print("Disposition — never blended into one figure:")
    for kind in DISPOSITIONS:
        print(f"  {tally[kind]:4d}  {kind}")
    print(f"  {len(unregistered):4d}  UNDISPOSED — discovered and absent from {REGISTRY}")
    print(f"  {len(mislabelled):4d}  MISLABELLED — an entry whose disposition is not one of the four")
    print(f"  {len(undiscovered):4d}  UNDISCOVERED — registered, still in the tree, and no longer "
          f"matched by the four readers")
    for path in undiscovered:
        now = markers_for(open(os.path.join(root, path), encoding="utf-8", errors="replace").read())
        print(f"        {path} — disposition {entries[path].get('disposition')!r}, markers now "
              f"{','.join(now) if now else '(none)'}, below the threshold of {THRESHOLD}")
    if undiscovered:
        print(f"        So {len(undiscovered)} of the {tally['grandfathered']} grandfathered rows "
              f"names a file discovery does not claim.")
        print(f"        The live grandfathered backlog is "
              f"{tally['grandfathered'] - sum(1 for p in undiscovered if entries[p].get('disposition') == 'grandfathered')}"
              f"; the registry figure above is the registry's, and they are not the same number.")
    print()

    print("Declared controls, run rather than believed:")
    ran = 0
    for path in sorted(entries):
        entry = entries[path]
        if entry.get("disposition") != "control":
            continue
        ran += 1
        passed, said = run_control(root, entry)
        print(f"  {'ok  ' if passed else 'FAIL'}  {path:38s} {said}")
        if not passed:
            findings.append(f"{path}: its declared control does not pass — {said}")
        elif entry.get("proves"):
            print(f"          proves: {entry['proves']}")
    if not ran:
        print("  (none declared)")
    print()

    stale = sorted(path for path in entries
                   if not os.path.exists(os.path.join(root, path)))
    for path in stale:
        findings.append(f"{path}: registered in {REGISTRY} and no longer in the tree")
    for path in unregistered:
        findings.append(f"{path}: discovered as a sweep ({','.join(found[path])}) with no "
                        f"disposition in {REGISTRY}")
    for path in mislabelled:
        findings.append(f"{path}: its disposition is "
                        f"{entries[path].get('disposition')!r}, which is not one of "
                        f"{DISPOSITIONS} — a word that is not a disposition is still silence")
    for note in undecodable:
        findings.append(f"{note}: this reader could not open the file, so it has said nothing "
                        f"about whether it is a sweep")

    if findings:
        print(f"FINDINGS sweep-control: {len(findings)}\n")
        for finding in findings:
            print(f"  * {finding}")
        print()
        print("  An undisposed sweep is not an accusation. It needs one of four words in the")
        print("  registry: `control` with a runnable command, `grandfathered`, `not-a-sweep`, or")
        print("  `waived` with a reason. Silence is the only answer this gate refuses.")
        return 1

    print(f"CLEAN sweep-control: {len(found)} discovered sweep(s), all disposed; {ran} declared "
          f"control(s) run and passing.")
    print(f"      {tally['grandfathered']} are grandfathered, which is a backlog with a number on")
    print("      it rather than a pass, and this gate does not report them as controlled.")
    return 0


def write_registry(root: str) -> int:
    """Seed the registry from a discovery run. Everything grandfathered; controls added by hand."""
    found = discover(root).hits
    entries = [{"path": path, "disposition": "grandfathered",
                "markers": markers,
                "reason": "predates this gate; carries no control this gate can run",
                "since": "2026-08-26"}
               for path, markers in sorted(found.items())]
    payload = {
        "note": ("Every tracked script discovered as an absence sweep, and what has been decided "
                 "about its presence control. Written by planning/sweep-control-gate.py. "
                 "`grandfathered` is a backlog entry, not a pass."),
        "threshold": THRESHOLD,
        "sweeps": entries,
    }
    with open(os.path.join(root, REGISTRY), "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")
    print(f"wrote {REGISTRY} with {len(entries)} entries, all `grandfathered`")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Require every discovered absence sweep to carry a disposition, and run the "
                    "controls that are declared.")
    parser.add_argument("--repo", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    parser.add_argument("--write-registry", action="store_true",
                        help=f"seed {REGISTRY} from a discovery run, everything grandfathered")
    parser.add_argument("--control-only", action="store_true",
                        help="run this gate's own control and exit")
    args = parser.parse_args()
    root = os.path.abspath(args.repo)

    if args.control_only:
        ok, lines = guarded(lambda: self_control(root))
        print("Control:")
        print("\n".join(lines))
        print(f"  => {'ok' if ok else 'CONTROL FAILED'}")
        return 0 if ok else CONTROL_FAILED
    if args.write_registry:
        return write_registry(root)
    return report(root)


if __name__ == "__main__":
    sys.exit(main())
