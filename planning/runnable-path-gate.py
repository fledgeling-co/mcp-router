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

They are also separate for a duller reason: `foreign-path-gate.py` is on `ai/g6` and unmerged. A
gate on `ai/g9` that imported it would be a gate whose arming depends on another branch landing.

## Waivers

A line may carry `# path-gate: ok — <reason>` (or `path-gate: ok - <reason>`), and the reason must
be non-empty; a bare marker does not waive. Waivers are listed by name on every run rather than
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
WAIVER = re.compile(r"path-gate:\s*ok\s*[—-]\s*")


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


# ---------------------------------------------------------------------------- the presence control

PLANTS = {
    "block_sh": ("#!/bin/sh\ncd /Users/someone/Dev/thing || exit 90\n", "BLOCK"),  # path-gate: ok — a planted fixture for the presence control; the string is the subject under test
    "block_py": ("#!/usr/bin/env python3\nP = '/Volumes/Scratch/out.png'\n", "BLOCK"),  # path-gate: ok — a planted fixture for the presence control; the string is the subject under test
    "waived.sh": ("#!/bin/sh\nREF=/Users/ci/fixture  # path-gate: ok — the fixture the CI box mounts\n", "WAIVED"),  # path-gate: ok — a planted fixture; its inner marker is data, not this line's waiver
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
    for name, (_, expected) in PLANTS.items():
        mark = "ok  " if got[name] == expected else "MISS"
        print(f"  {mark}  {name:<18} expected {expected:<13} read {got[name]}")
    if bad:
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
