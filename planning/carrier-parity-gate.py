#!/usr/bin/env python3
"""A feature that lands in one router and not the other must be recorded as such.

## The defect this exists for

`R33`. This repository ships two routers: `src/*.ts`, which the differential harness drives as its
reference, and `app/Sources/RouterCore` plus `app/Sources/MCPRouterCLI`, which `docs/install.sh`
has pointed the launchd agents at by default since R4-C1 — `MCPR_ROUTER="${MCPR_ROUTER:-swift}"`,
`docs/install.sh:39` at `83e5380`.

On 2026-08-28, after the goal that was to make the router the sole home for marketplaces, skills,
plugins and MCPs, a deploy measured `GET /caches` answering **404** on the running router while
`GET /sessions` answered **200**. R28, R30, R31 and R32 had landed in Swift alone; R29 had landed
in TypeScript alone; all five merged with every gate in this tree green.

**No gate could have caught it, and the parity harness least of all.** The harness compares
BEHAVIOUR on rows that exist on both sides. A capability that exists on one side has no row to
compare against, so an absence and an agreement are the same observation to it. `surface.tsv` is a
census of what the cutover requires *both* to answer for; a route only one of them has was never
in scope for it. That is not a hole in the harness — it is a different question, and nothing was
asking it.

## What this gate requires, and what it deliberately does not

It does **not** require parity. One-sidedness is a normal act here: each of those five items was
built where its subject lives, `R4-C1` pointed the installer at Swift and held the deletion of the
TypeScript tree. The owner retired the Swift router on 2026-10-19, the retirement `REQ-020` reserved
to them. Porting four features into a reference implementation with a stated expiry date is work
nobody has asked for.

What it requires is that a one-sided landing be **said out loud**. Every landing at or after the
pin in `planning/parity/carriers.tsv` that touched one implementation and not the other needs a
disposition row carrying a reason. Silence is not a disposition — the same shape
`sweep-control-gate.py` gives a newly tracked sweep.

## Why the carrier is measured and not read

The recorded carrier is re-derived from each landing's own diff by
`scripts/acceptance/carrier-census.sh` on every run, and a row disagreeing with the tree is a
finding. A ledger that records what somebody typed is a ledger that can be made green by typing,
and this repository has already paid for a hand-maintained number: `# rows: N` in `surface.tsv`
was bumped five times and the fifth bump was wrong when it was written.

## Why the obligation begins at a pin

Discovery finds 41 one-sided or two-sided landings across the whole history, and 36 of those are
one-sided. A gate demanding a reason for every landing back to R1 either never goes green or gets
softened until it means nothing — `citation-gate.py`'s reasoning about bare citations, applied to
a different corpus. So the obligation runs from `since:` in the ledger, which is set at the goal
that produced the five items R33 measured, and everything earlier is printed as a stated backlog
with a count. **A backlog is not a pass and this gate never prints it as one.**

## Exit codes

  0  every one-sided landing in the window carries a disposition that matches the tree
  1  a landing has no row, a row disagrees with the tree, or a row is malformed
  2  the census could not be taken, or it found nothing to judge
  4  a control failed, so the run measured nothing it can be believed about

## The controls, run on every invocation

An absence check cannot detect its own blindness, so the requirement is armed against the real
ledger — in memory, never on disk — before any verdict is printed:

  C1  drop one real disposition row and the run must report that landing UNDISPOSITIONED
  C2  flip one real row's carrier and the run must report DISAGREES
  C3  the census over the whole history must yield at least one one-sided landing

C1 and C2 arm the two findings that can go quiet. C3 arms the reader: a census returning nothing
would let every landing pass for want of anything to check.
"""

import json
import os
import re
import shutil
import subprocess
import sys

# The verdict below is UTF-8, and the console's codepage does not get a vote in it: on a
# non-UTF-8 terminal an unencodable rule character would raise UnicodeEncodeError and this
# gate would exit on its terminal rather than on its findings.
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8")

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# `CARRIER_LEDGER` exists so the gate can be armed against a deliberately broken copy without
# a mutation ever reaching the working tree. A gate that has to be edited to be proved is a
# gate whose arming run and whose real run are different programs.
LEDGER = os.environ.get(
    "CARRIER_LEDGER", os.path.join(REPO_ROOT, "planning", "parity", "carriers.tsv")
)
CENSUS = os.path.join(REPO_ROOT, "scripts", "acceptance", "carrier-census.sh")
INSTALLER = os.path.join(REPO_ROOT, "docs", "install.sh")

ONE_SIDED = ("swift-only", "typescript-only")
DISPOSITIONS = ("divergent-recorded", "ported", "reference-only", "not-a-feature")


# ---------------------------------------------------------------------------------------------
# The shell and the interpreter, resolved rather than assumed.
#
# Neither name below is a Windows-only trap. They are ordinary names with more than one answer,
# and the wrong answer is reached first on a machine that has several:
#
#   "bash"     handed to `subprocess` as a bare name is resolved by CreateProcess, which searches
#              System32 ahead of PATH and so returns the WSL launcher: a different machine, with
#              a different filesystem, which cannot see this checkout. With virtualisation off it
#              exits 1 having printed a UTF-16 error, and that reads as a failing gate rather
#              than as a missing shell. `/bin/bash` does not exist on Windows at all.
#   "python3"  is whatever is on PATH, which need not be the interpreter running this gate. On
#              Windows it is an App Execution Alias stub that raises OSError 216, "not a valid
#              application for this OS platform" — a message about the machine, not the corpus.
#
# So a candidate shell is proved by asking it to read this file; a shell that cannot see the tree
# it is being asked about is rejected instead of measured. `None` means there is no POSIX shell
# on this machine, and every caller reports that as could-not-run, which is not a pass.
_POSIX_SHELL: list = []


def posix_shell():
    """An absolute path to a shell that can read this checkout, or None if there is none."""
    if _POSIX_SHELL:
        return _POSIX_SHELL[0] or None
    witness = os.path.abspath(__file__).replace(os.sep, "/")
    candidates = [shutil.which("bash"), "/bin/bash"]
    git = shutil.which("git")
    if git:
        # Every caller here already needs git, and git ships the shell its own tooling runs.
        # Derived from a tool that must be present rather than a hardcoded install location.
        home = os.path.dirname(os.path.dirname(os.path.realpath(git)))
        candidates += [os.path.join(home, "bin", "bash.exe"), os.path.join(home, "bin", "bash")]
    for candidate in candidates:
        if not candidate or not os.path.exists(candidate):
            continue
        try:
            done = subprocess.run(
                [candidate, "-c", 'test -e "$1" && printf posix-ok', "sh", witness],
                capture_output=True, timeout=60)
        except (OSError, subprocess.SubprocessError):
            continue
        if done.stdout.strip() == b"posix-ok":
            _POSIX_SHELL.append(candidate)
            return candidate
    _POSIX_SHELL.append("")
    return None


def resolve_interpreter(command):
    """argv with a bare interpreter name replaced by the one this gate is actually running under.

    A member declared `python3 …` means "under the suite's Python" and one declared `bash …`
    means "under the shell that can read this tree"; taking either from PATH lets a second
    installation answer for the first. Returns None when the command names a shell this machine
    does not have, so the caller can say could-not-run rather than guess.
    """
    if not command:
        return list(command)
    head = os.path.basename(command[0]).lower()
    if head in ("python", "python3", "python.exe", "python3.exe"):
        return [sys.executable] + list(command[1:])
    if head in ("bash", "sh", "bash.exe", "sh.exe"):
        shell = posix_shell()
        return None if shell is None else [shell] + list(command[1:])
    return list(command)


def run(args):
    """Run a command in the repo and return (exit, stdout). stderr is passed through."""
    proc = subprocess.run(
        args, cwd=REPO_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, encoding="utf-8",
    )
    return proc.returncode, proc.stdout, proc.stderr


def take_census():
    """Measure every landing's carrier. Returns a dict sha -> (label, carrier, nswift, nts)."""
    shell = posix_shell()
    if shell is None:
        return None, "the census is a shell script and this machine has no POSIX shell"
    code, out, err = run([shell, CENSUS])
    if code != 0:
        return None, err.strip() or "the census exited %d having printed nothing" % code
    rows = {}
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) != 6 or parts[0] != "landing":
            return None, "the census printed a row this reader does not understand: %r" % line
        rows[parts[1]] = (parts[2], parts[3], parts[4], parts[5])
    if not rows:
        return None, "the census printed no landings"
    return rows, None


def read_ledger(text):
    """Parse the disposition ledger. Returns (pin, rows, malformed)."""
    pin = None
    rows = {}
    malformed = []
    for number, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):
            found = re.match(r"#\s*since:\s*([0-9a-f]{7,40})\s*$", stripped)
            if found:
                pin = found.group(1)
            continue
        parts = line.split("\t")
        if len(parts) != 5:
            malformed.append((number, "%d fields, not 5" % len(parts)))
            continue
        sha, label, carrier, disposition, note = parts
        if not re.match(r"^[0-9a-f]{40}$", sha):
            malformed.append((number, "the sha is not 40 hex characters: %r" % sha[:50]))
            continue
        if disposition not in DISPOSITIONS:
            malformed.append((number, "disposition %r is not one of %s"
                              % (disposition, ", ".join(DISPOSITIONS))))
            continue
        if not note.strip():
            malformed.append((number, "no note. A row with no reason records nothing"))
            continue
        rows[sha] = (label, carrier, disposition, note)
    return pin, rows, malformed


def window_shas(pin):
    """Every landing on the first-parent line from the pin to HEAD, exclusive of the pin."""
    code, out, _ = run(["git", "rev-list", "--first-parent", "%s..HEAD" % pin])
    if code != 0:
        return None
    return set(out.split())


def judge(census, pin, rows, malformed, window):
    """Return the list of findings. A finding is (class, sha, detail)."""
    findings = []
    for number, why in malformed:
        findings.append(("MALFORMED", "line %d" % number, why))

    for sha, (label, carrier, _nswift, _nts) in sorted(
        census.items(), key=lambda item: item[1][0]
    ):
        if sha not in window or carrier not in ONE_SIDED:
            continue
        if sha not in rows:
            findings.append((
                "UNDISPOSITIONED", sha,
                "%s landed %s and carries no row. Say what the other router does about it."
                % (label, carrier),
            ))
            continue
        if rows[sha][1] != carrier:
            findings.append((
                "DISAGREES", sha,
                "%s is recorded %s and the diff measures %s."
                % (label, rows[sha][1], carrier),
            ))

    for sha, (label, _carrier, _disposition, _note) in sorted(rows.items()):
        if sha not in census:
            findings.append((
                "STALE", sha,
                "%s has a row and touched neither router, or is not on this branch." % label,
            ))
        elif sha not in window:
            findings.append((
                "OUTSIDE", sha,
                "%s has a row and sits before the pin. Move the pin or drop the row." % label,
            ))
    return findings


def controls(census, pin, ledger_text, window):
    """Arm the two findings that can go quiet, and the reader behind them."""
    results = []
    pin_read, rows, malformed = read_ledger(ledger_text)

    live = [sha for sha in rows
            if sha in census and census[sha][1] in ONE_SIDED and sha in window]

    if not live:
        results.append(("C1", False, "no in-window one-sided row exists to arm the check with"))
        results.append(("C2", False, "no in-window one-sided row exists to arm the check with"))
    else:
        victim = sorted(live)[0]

        dropped = dict(rows)
        del dropped[victim]
        seen = judge(census, pin, dropped, malformed, window)
        fired = any(kind == "UNDISPOSITIONED" and where == victim for kind, where, _ in seen)
        results.append(("C1", fired,
                        "dropping %s must report UNDISPOSITIONED" % victim[:7]))

        flipped = dict(rows)
        label, carrier, disposition, note = flipped[victim]
        other = "typescript-only" if carrier == "swift-only" else "swift-only"
        flipped[victim] = (label, other, disposition, note)
        seen = judge(census, pin, flipped, malformed, window)
        fired = any(kind == "DISAGREES" and where == victim for kind, where, _ in seen)
        results.append(("C2", fired,
                        "recording %s as %s must report DISAGREES" % (victim[:7], other)))

    one_sided_total = sum(1 for value in census.values() if value[1] in ONE_SIDED)
    results.append(("C3", one_sided_total > 0,
                    "the census must find at least one one-sided landing across all history"))
    return results


def installer_default():
    """Which binary a fresh install selects, read from the installer rather than remembered."""
    try:
        with open(INSTALLER, encoding="utf-8") as handle:
            for line in handle:
                found = re.match(r'\s*MCPR_ROUTER="\$\{MCPR_ROUTER:-(\w+)\}"', line)
                if found:
                    return found.group(1)
    except OSError:
        return None
    return None


def main():
    if not os.path.exists(LEDGER):
        print("environment: no disposition ledger at %s" % LEDGER)
        return 2

    with open(LEDGER, encoding="utf-8") as handle:
        ledger_text = handle.read()

    census, why = take_census()
    if census is None:
        print("environment: the carrier census could not be taken.")
        print("  %s" % why)
        print("  Nothing is judged from a census that did not happen.")
        return 2

    pin, rows, malformed = read_ledger(ledger_text)
    if pin is None:
        print("environment: %s carries no `# since: <sha>` pin, so the gate has no window and"
              % LEDGER)
        print("             every landing would pass for want of an obligation. Exit 2.")
        return 2

    window = window_shas(pin)
    if window is None:
        print("environment: git does not know %s, so the window cannot be computed." % pin)
        return 2
    if not window:
        print("environment: the window %s..HEAD is empty. A gate that compared nothing is not a"
              % pin[:7])
        print("             gate that passed. Exit 2.")
        return 2

    print("carrier parity — the two routers, and what landed in only one of them")
    print()

    control_results = controls(census, pin, ledger_text, window)
    for name, passed, what in control_results:
        print("  control %s  %-4s  %s" % (name, "ok" if passed else "FAIL", what))
    print()
    if not all(passed for _name, passed, _what in control_results):
        print("a control failed, so nothing below is a measurement. Exit 4.")
        return 4

    default = installer_default()
    in_window = {sha: value for sha, value in census.items() if sha in window}
    one_sided_window = {sha: value for sha, value in in_window.items()
                        if value[1] in ONE_SIDED}
    before_pin = sum(1 for sha, value in census.items()
                     if sha not in window and value[1] in ONE_SIDED)

    print("  window        %s..HEAD, %d landings" % (pin[:7], len(window)))
    print("  touched a router in the window   %d" % len(in_window))
    print("  of those, one-sided              %d, each needing a row" % len(one_sided_window))
    print("  one-sided BEFORE the pin         %d, a stated backlog and not a pass"
          % before_pin)
    print()

    if default is None:
        print("  a fresh install selects: NOT READABLE from docs/install.sh. Reachability below")
        print("  is withheld rather than guessed.")
    else:
        print("  a fresh install selects the %s router, so a swift-only capability is reachable"
              % default)
        print("  on it and a typescript-only one is not. WHAT IS INSTALLED ON A GIVEN MACHINE IS")
        print("  NOT A FACT THIS REPOSITORY HOLDS — R33 measured launchd agents running node on")
        print("  2026-08-28, which is an install predating R4-C1, not a disagreement with the")
        print("  line above.")
    print()

    if one_sided_window:
        print("  one-sided landings in the window:")
        for sha, (label, carrier, nswift, nts) in sorted(
            one_sided_window.items(), key=lambda item: item[1][0]
        ):
            disposition = rows[sha][2] if sha in rows else "NO ROW"
            print("    %-7s %-14s %-16s swift=%-3s ts=%-3s  %s"
                  % (sha[:7], label[:14], carrier, nswift, nts, disposition))
        print()

    findings = judge(census, pin, rows, malformed, window)
    if not findings:
        print("carrier parity: %d one-sided landing(s) in the window, %d dispositioned, 0 findings."
              % (len(one_sided_window), len(one_sided_window)))
        print("This gate REPORTS the split; it does not close it. Retiring src/*.ts is REQ-020 and")
        print("stays the owner's decision.")
        return 0

    print("carrier parity: %d finding(s)." % len(findings))
    print()
    for kind, where, detail in findings:
        print("  %-15s %-8s %s" % (kind, where[:8], detail))
    print()
    print("A landing that touched one router and not the other is not a defect. Not saying so is.")
    print("Add a row to planning/parity/carriers.tsv naming the carrier the diff measures and why.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
