#!/usr/bin/env python3
"""Fail any file the repository can RUN that names a path under /Users or /Volumes.

## The defect this exists for

`G9`. `app/Scripts/pool-mutation-gate.sh` and `planning/run-gate.sh` each began by `cd`-ing into
`<home>/Dev/mcp-router/.worktrees/R2` — a literal home path, written out — guarded with `|| exit 90`. `.worktrees/R2` was
deleted in a routine cleanup. Both scripts were 0755, both were therefore permanently dead — every
invocation exited 90 before reaching a single check — and `planning/specs/spec-R2.md` went on
citing one of them as a mutation gate that had run. Nothing went red, because nothing invoked them.

  a file the repository can run derives the paths it needs, or it does not run here.

**The path was correct when it was written.** That is the whole argument for a gate rather than a
list. `.worktrees/R2` existed, the gate ran, the citation was true, and an unrelated cleanup
falsified all three without touching any of the three files. A violation list rots the same way the
violations do: it is written against one day's tree and is silently wrong on the next. This gate is
re-derived from the tree on every run, so a file added tomorrow is in the denominator tomorrow.

## Scope, stated because the last sweep's scope was the defect

The corpus is **every tracked file the repository can run**, derived from `git ls-files`, with no
directory filter. A file is runnable when its git mode is 100755, OR its suffix is an interpreter
suffix, OR its first line is a shebang — a union, because each of the three catches something the
others miss and the two G9 scripts happened to satisfy all three.

The scope is spelled out because a too-narrow scope is this fleet's live defect, filed as `G8`: the
sweep that found G9 covered `scripts/` only, returned a confident zero, and missed `app/Scripts/`
and `planning/` — where both offenders were. It was committed inside G9's own sweep, minutes after
G8 was filed. A gate reading `git ls-files` cannot acquire that fault, because it has no directory
argument to get wrong.

## What blocks, and what is counted and let through

**BLOCKS — a `/Users` or `/Volumes` path in a runnable file.** These name one person's home or one
mounted volume. No other checkout has them, and a script is the one artifact that *acts* on a path
rather than describing one, so the failure is silent execution against nothing rather than a reader
being confused.

**Counted, never blocked**, each with a reason it is a different problem:

  HOME_REL   `~/…` in a runnable file. User-relative, not machine-pinned: it resolves on any
             machine that has the file. It decays only when what it points AT is ephemeral, which
             is a property of the target and not of the path. `planning/watch-fleet.sh` pinned
             `~/.claude/projects/<session-uuid>/…` and did decay — fixed by discovering the session
             from a run id, not by rewriting the `~`. Blocking `~/` would red on every legitimate
             `$HOME` reference and teach people to waive, which is how a gate stops meaning
             anything.
  SYSTEM     `/Applications/`, `/opt/`, `/usr/local/`, `/Library/`. System locations that exist on
             any Mac. Pinning one is a portability wart with a different remedy (a PATH lookup),
             not the decay G9 is about.
  SCRATCH    `/tmp`, `/private/tmp`, `/var/folders`, `$TMPDIR`. **`planning/foreign-path-gate.py`
             owns this axis** and is deliberately not duplicated here — see below.
  RECORD     the same, in a file that is NOT runnable. 40 tracked files at the
             commit G9 was filed against, 44 today. Most are legitimate and rewriting them would
             falsify evidence, so the figure is printed as a diagnostic and blocks nothing. The
             per-file adjudication lives in `planning/progress/G9.md`.

## Why this sits beside `planning/foreign-path-gate.py` rather than inside it

Two axes, and the two gates take opposite corners:

                      hand-written record        runnable file
  scratch root        foreign-path-gate BLOCKS   foreign-path-gate: RUNTIME, passes
  machine root        foreign-path-gate: counted, never blocked      >>> THIS GATE BLOCKS <<<

That gate's own docstring declines the machine-path corner in as many words — *"a different defect
with a different remedy: a scratch path fails because the artifact evaporates, a machine path fails
because the reader is on another machine"* — and argues that folding it in would put a third,
uncoupled axis into an item whose case is that its own two halves are coupled. It is right, and
this is the remedy it names, for the half of that corner which is executed rather than read. A
scratch path in a script is fine under both gates and should be: a committed script that writes to
`/tmp` is re-runnable, which is exactly the property G6 wanted.

An earlier draft of this docstring gave a second, duller reason: that `foreign-path-gate.py` was on
`ai/g6` and unmerged, so importing it would make this gate's arming depend on another branch
landing. **`ai/g6` merged at `03c34c3` and that file is on `main`**, so the clause is deleted rather
than left to be false the day this branch lands. The two-axis argument above is the reason, and it
was the reason all along; the second one was scheduling.

## Waivers

A line may carry `# path-gate: ok — <reason>` or `// path-gate: ok — <reason>`, and the reason must
be non-empty; a bare marker does not waive. **The marker must be inside a comment.** Matching it
anywhere on the line let a violating line waive itself from inside a string: a `cd` into a machine
path followed by `; echo "path-gate: ok - decoy"` waived its own BLOCK, which is a gate a violation
can switch off by quoting at it. The example is written out rather than quoted here because quoting
it would plant a machine path in a runnable file, and this gate would block it — which it did, on
the draft of this paragraph. One waiver covers the whole line, so a line carrying two machine paths and one
trailing waiver waives both; that is deliberate and stated rather than discovered. Waivers are listed by name on every run rather than
subtracted in silence, because a waiver nobody re-reads is a violation with better manners.

## Counting

Four readings, printed together and never blended, because five sweeps over one phrase in this
repo once returned four different answers and none of the first four answered the question asked:

  N1  runnable tracked files                                  the denominator
  N2  of those, files holding at least one machine path       the sweep's finding, by file
  N3  the same, by occurrence                                 what a `grep -c` sees
  N4  N2 less waived files                                    the blocking set

The verdict reads N4. Exit 0 when N4 is zero, 1 otherwise, 2 if the presence control does not fire.

## Nothing is planted in the real corpus

An absence sweep with no presence control has never been shown to fire, and returns zero for
reasons it cannot distinguish. `--control` — which runs on every invocation, not behind a flag —
builds a throwaway git repository, plants one file per class plus a waived instance and an
unwaivable bare marker, runs the real classifier over it, and requires every planted answer
exactly. If any planted instance is missed, the run exits 2 and prints no verdict.

**The control's own failure path had this gate's defect in it.** A plant that never reached the
index returned a partial reading, and the report loop raised `KeyError` before it read the failed
set — so the interpreter chose the exit code, and it chose **1**, which this gate assigns to
FINDINGS. A broken control wearing a verdict's exit code is worse than no control, because 1 reads
as a real finding to everything downstream. The guard now returns a reading for every plant, so
the failure prints and exits 2. Armed both ways the failure can arrive — a plant added to the
index one-by-one, and a plant never written to disk — and both now print `NEVER REACHED THE INDEX`
and exit 2.

## What this gate cannot see

Printed on every run under `NOT MEASURED HERE`, and blocking nothing, because a blind spot
recorded only in a progress file is one this gate's own readers never meet. The `src/*.ts` sources
that build the `mcp-router` bin are mode 100644 with no shebang and no interpreter suffix, so they
sit outside N1 while `dist/index.js` — the thing that actually runs — is not tracked at all and is
therefore in no denominator here. And `BLOCK` matches neither a `$VAR`-interpolated home path,
which is arguably right because that is `~/`'s portable shape, nor a lower-case spelling, which on
a case-insensitive volume is G9's original defect written differently. Every figure in that block
is re-derived from the tree on each run, and each of its three counters has been shown to move
under a planted line. Widening the corpus in either direction is the owner's call, not this gate's.
"""

import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

BLOCK = re.compile(r"(?<![A-Za-z0-9_~.-])(?P<path>/(?:Users|Volumes)/[A-Za-z0-9_.~+=@-][^\s\"'`,;:)\]}<>]*)")
HOME_REL = re.compile(r"(?<![A-Za-z0-9_~.-])~/[A-Za-z0-9_.]")
SYSTEM = re.compile(r"(?<![A-Za-z0-9_~.-])/(?:Applications|opt|usr/local|Library)/")
SCRATCH = re.compile(r"(?<![A-Za-z0-9_~.-])(?:(?:/private)?/tmp/|/var/folders/|\$TMPDIR/)")
# The marker only; the reason is whatever follows the RIGHTMOST marker on the line. A single
# regex with a greedy reason cannot do this: the first match swallows the rest of the line, so
# finditer returns one hit and "the last marker" and "the first marker" are the same object.
# The marker must sit behind a comment introducer. Without the `(?:#|//)` the regex matched the
# token anywhere on the line, so a `cd` into a machine path followed by an `echo` of the marker
# waived its own BLOCK from inside a string the shell would print — a gate a violating line could
# switch off by quoting at it (`grok-4.6`, 2026-08-26). A waiver is a note to a reader, and a note
# to a reader is a comment.
WAIVER = re.compile(r"(?:#|//)[^\n]*?path-gate:\s*ok\s*[—-]\s*")


def waiver_reason(line):
    """The reason after the rightmost marker, or "" when there is no marker or no reason."""
    last = None
    for m in WAIVER.finditer(line):
        last = m
    return line[last.end():].strip() if last else ""

RUN_SUFFIX = frozenset(".sh .bash .zsh .py .js .mjs .cjs .rb .pl .command".split())


def tracked(root):
    """(path, mode) for every tracked file. Mode comes from the index, not the filesystem."""
    out = subprocess.run(["git", "-C", str(root), "ls-files", "-s"],
                         capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        meta, _, name = line.partition("\t")
        yield name, meta.split()[0]


def is_runnable(root, name, mode):
    """Runnable = executable bit in the index, OR an interpreter suffix, OR a shebang.

    A union rather than a choice: the mode is what makes a file the OS will run, the suffix is
    what survives a checkout that lost its modes, and the shebang is what catches an
    extensionless script somebody chmod'd later.
    """
    if mode == "100755":
        return True
    if pathlib.PurePath(name).suffix in RUN_SUFFIX:
        return True
    p = root / name
    try:
        with open(p, "rb") as fh:
            return fh.read(2) == b"#!"
    except OSError:
        return False


def scan(root):
    runnable, findings, counts = [], [], {"HOME_REL": 0, "SYSTEM": 0, "SCRATCH": 0}
    for name, mode in tracked(root):
        p = root / name
        if not p.is_file():
            continue
        if not is_runnable(root, name, mode):
            continue
        runnable.append(name)
        try:
            text = p.read_text(errors="replace")
        except OSError:
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            # The RIGHTMOST marker wins: a waiver is a trailing comment, and this file's own plant
            # strings carry marker text as data. Reading the first match let a fixture's inner
            # marker supply the reason and printed nonsense beside a legitimate waiver.
            reason = waiver_reason(line)
            for m in BLOCK.finditer(line):
                findings.append({"file": name, "line": lineno, "path": m.group("path"),
                                 "waived": bool(reason), "reason": reason})
            if HOME_REL.search(line):
                counts["HOME_REL"] += 1
            if SYSTEM.search(line):
                counts["SYSTEM"] += 1
            if SCRATCH.search(line):
                counts["SCRATCH"] += 1
    return runnable, findings, counts


def record_diagnostic(root):
    """Machine paths in files the repository does NOT run. Printed, never blocked."""
    files = 0
    for name, mode in tracked(root):
        p = root / name
        if not p.is_file() or is_runnable(root, name, mode):
            continue
        try:
            if BLOCK.search(p.read_text(errors="replace")):
                files += 1
        except OSError:
            pass
    return files


# ------------------------------------------------------------------- what this gate cannot see

# Two limits the verifier certified rather than closed, because closing either widens the corpus.
# They lived only in `planning/progress/G9.md`, where nobody reading this gate's output would meet
# them — and an absence sweep whose blind spots are recorded somewhere else reports a zero at the
# wrong width. Printed on every run, blocking nothing; both are the owner's call. Every figure is
# re-derived from the tree here rather than written down, because a pinned figure is what this
# gate exists to argue against.
#
# Neither pattern below contains a literal capital-U machine path, so this file does not plant one.
USERVAR = re.compile(r"/(?:[Uu]sers|[Vv]olumes)/\$(?:USER|USERNAME|LOGNAME|HOME)\b")
FOLDED = re.compile(r"(?<![A-Za-z0-9_~.-])/(?:users|volumes)/[A-Za-z0-9_.~+=@-]")


def blind_spots(root, runnable):
    """(compiled-source count, how many carry a machine path, product tracked?, $VAR hits, folded hits)."""
    names = [n for n, _ in tracked(root)]
    runnable_set = set(runnable)
    sources = [n for n in names
               if n.startswith("src/") and n.endswith(".ts") and n not in runnable_set]
    with_path = 0
    for name in sources:
        try:
            if BLOCK.search((root / name).read_text(errors="replace")):
                with_path += 1
        except OSError:
            pass
    uservar = folded = 0
    for name in runnable:
        try:
            text = (root / name).read_text(errors="replace")
        except OSError:
            continue
        uservar += len(USERVAR.findall(text))
        folded += len(FOLDED.findall(text))
    return len(sources), with_path, "dist/index.js" in names, uservar, folded


# ---------------------------------------------------------------------------- the presence control

PLANTS = {
    "block_sh": ("#!/bin/sh\ncd /Users/someone/Dev/thing || exit 90\n", "BLOCK"),  # path-gate: ok — a planted fixture for the presence control; the string is the subject under test
    "block_py": ("#!/usr/bin/env python3\nP = '/Volumes/Scratch/out.png'\n", "BLOCK"),  # path-gate: ok — a planted fixture for the presence control; the string is the subject under test
    "waived.sh": ("#!/bin/sh\nREF=/Users/ci/fixture  # path-gate: ok — the fixture the CI box mounts\n", "WAIVED"),  # path-gate: ok — a planted fixture; its inner marker is data, not this line's waiver
    # The marker inside a STRING rather than a comment. Without this plant the comment-scoping rule
    # was untested: removing `(?:#|//)` from WAIVER left every arm reading exactly as planted, so
    # the control could not tell a waiver from a violation quoting at it (`grok-4.6`, 2026-08-26).
    "quoted_marker.sh": ("#!/bin/sh\ncd /Users/someone/Dev/thing; echo 'path-gate: ok - decoy'\n",
                         "BLOCK"),  # path-gate: ok — a planted fixture: the inner marker is inside a string, so it must NOT waive
    "bare_marker.sh": ("#!/bin/sh\nREF=/Users/ci/fixture  # path-gate: ok —\n", "BLOCK"),  # path-gate: ok — a planted fixture: a bare marker with no reason, which must NOT waive
    "home_rel.sh": ("#!/bin/sh\nls ~/.claude/projects\n", "CLEAN"),
    "system.sh": ("#!/bin/sh\nexec /opt/homebrew/bin/thing\n", "CLEAN"),
    "scratch.sh": ("#!/bin/sh\necho hi > /tmp/out.log\n", "CLEAN"),
    "notrunnable.md": ("A record citing /Users/someone/Dev/thing/evidence.png\n", "NOT_RUNNABLE"),  # path-gate: ok — a planted fixture for the presence control; the string is the subject under test
    "extensionless": ("#!/bin/bash\ncd /Users/someone/x\n", "BLOCK"),  # path-gate: ok — a planted fixture for the presence control; the string is the subject under test
}


def control():
    """Plant one instance per class in a throwaway repo; require every planted answer exactly."""
    with tempfile.TemporaryDirectory(prefix="g9-runnable-control.") as td:
        d = pathlib.Path(td)
        subprocess.run(["git", "init", "-q", str(d)], check=True)
        for name, (body, _) in PLANTS.items():
            (d / name).write_text(body)
            if name.endswith((".sh", ".py")) or name == "extensionless":
                os.chmod(d / name, 0o755)
        subprocess.run(["git", "-C", str(d), "add", "-A"], check=True)

        # Every plant must be on disk AND in the index before a verdict means anything. Without
        # this, `NOT_RUNNABLE` was returned both for a correct exclusion and for a plant that was
        # never written or never added — so the `notrunnable.md` arm could not fail in the skip
        # direction (`grok-4.6`, 2026-08-26).
        tracked = subprocess.run(["git", "-C", str(d), "ls-files"],
                                 capture_output=True, text=True).stdout.split()
        missing = [n for n in PLANTS if n not in tracked or not (d / n).is_file()]
        if missing:
            # A guard that returned a PARTIAL `got` was this gate's own subject one layer up.
            # `main` indexed the first plant, raised `KeyError`, and the interpreter exited **1**
            # — the FINDINGS code — so a control that never ran wore a verdict's exit code, and
            # the string below could not be printed by any input. Every plant gets a reading
            # here, so the table prints, `bad` is non-empty, and the run exits 2. Nothing was
            # classified once one plant is missing, so no plant may read `ok`: the ones that
            # arrived read NOT ASSESSED rather than a verdict this run did not earn.
            got = {n: ("NEVER REACHED THE INDEX" if n in missing else "NOT ASSESSED")
                   for n in PLANTS}
            return got, {n: (PLANTS[n][1], got[n]) for n in PLANTS}

        runnable, findings, _ = scan(d)
        got = {}
        for name, (_, expected) in PLANTS.items():
            hits = [f for f in findings if f["file"] == name]
            if name not in runnable:
                got[name] = "NOT_RUNNABLE"
            elif not hits:
                got[name] = "CLEAN"
            elif all(h["waived"] for h in hits):
                got[name] = "WAIVED"
            else:
                got[name] = "BLOCK"

        bad = {n: (PLANTS[n][1], got[n]) for n in PLANTS if PLANTS[n][1] != got[n]}
        return got, bad


def main():
    print("runnable-path-gate — /Users/ and /Volumes/ in anything this repository can run")
    print(f"root  : {ROOT}")
    print("scope : every tracked file (git ls-files) whose index mode is 100755, or whose suffix")
    print("        is an interpreter suffix, or whose first two bytes are '#!'. No directory filter.")
    print()

    got, bad = control()
    print("presence control (a throwaway repo; nothing is planted here)")
    # The TABLE decides the exit code, not `bad` alone. `bad` and `got` are two derivations of
    # one fact, and a future path that returns a partial reading with an empty `bad` would
    # otherwise print MISS rows and fall through to a verdict — the same defect as the guard
    # below, one step further on (`grok-4.6`, 2026-08-26). `.get` keeps a missing key out of the
    # exception path that already chose the wrong code once; `missed` makes it choose 2.
    missed = []
    for name, (_, expected) in PLANTS.items():
        reading = got.get(name, "NOT ASSESSED")
        mark = "ok  " if reading == expected else "MISS"
        if mark == "MISS":
            missed.append(name)
        print(f"  {mark}  {name:<18} expected {expected:<13} read {reading}")
    if bad or missed:
        print("\nCONTROL DID NOT FIRE — the classifier missed a planted instance.")
        print("The verdict below would be an absence this instrument cannot see, so none is printed.")
        return 2
    print("  control fired: every planted class read exactly.\n")

    runnable, findings, counts = scan(ROOT)
    blocking = [f for f in findings if not f["waived"]]
    waived = [f for f in findings if f["waived"]]
    n2 = len({f["file"] for f in findings})
    n4 = len({f["file"] for f in blocking})

    print("COUNTS  — four readings, never blended; each answers a different question")
    print(f"  N1 runnable tracked files                    {len(runnable)}")
    print(f"  N2 of those, files with a machine path        {n2}")
    print(f"  N3 the same, by occurrence                    {len(findings)}")
    print(f"  N4 blocking set (N2 less waived files)        {n4}")
    print()
    print("COUNTED, NEVER BLOCKED — different defects, named so they are not forgotten")
    print(f"  lines with ~/ in a runnable file              {counts['HOME_REL']}   user-relative, not machine-pinned")
    print(f"  lines with /Applications /opt /usr/local /Library  {counts['SYSTEM']}   system locations, any Mac has them")
    print(f"  lines with a scratch root                     {counts['SCRATCH']}   planning/foreign-path-gate.py owns this axis")
    print(f"  NON-runnable tracked files with a machine path {record_diagnostic(ROOT)}   adjudicated in planning/progress/G9.md")
    print()

    n_src, src_with_path, product_tracked, uservar, folded = blind_spots(ROOT, runnable)
    print("NOT MEASURED HERE — this gate's own blind spots, so the zero above is read at its width")
    print(f"  {n_src} tracked src/*.ts sources are outside N1: mode 100644, no shebang, no interpreter")
    print(f"      suffix. They compile into the `mcp-router` bin, whose artefact dist/index.js is")
    print(f"      {'TRACKED — which would put it in N1' if product_tracked else 'NOT tracked, so it is in no denominator here at all'}.")
    print(f"      {src_with_path} of the {n_src} name a machine path today. Widening N1 to reach them is the owner's call.")
    print("  BLOCK matches neither a $VAR-interpolated home path — arguably right, since that is")
    print("      ~/'s portable shape — nor a lower-case spelling, which on a case-insensitive")
    print(f"      volume is G9's original defect written differently. In runnable files today:")
    print(f"      {uservar} $VAR-interpolated and {folded} lower-case. Neither is counted above.")
    print()

    if waived:
        print("WAIVED — listed by name every run, never subtracted in silence")
        for f in waived:
            print(f"  {f['file']}:{f['line']}  {f['path']}")
            print(f"      because: {f['reason']}")
        print()

    if blocking:
        print("BLOCKING")
        for f in blocking:
            print(f"  {f['file']}:{f['line']}  {f['path']}")
        print()
        print(f"FAIL  {n4} runnable file(s) name a path this checkout cannot rely on.")
        print("      Derive it (git rev-parse --show-toplevel, __file__, the caller's cwd), delete the")
        print("      file, or waive the line with `# path-gate: ok — <reason>`.")
        return 1

    print("PASS  no runnable tracked file names a /Users/ or /Volumes/ path.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
