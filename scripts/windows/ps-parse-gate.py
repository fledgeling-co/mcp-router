#!/usr/bin/env python3
"""Every tracked PowerShell script parses under Windows PowerShell 5.1, and says what it means.

WHY THIS EXISTS. `scripts/windows/uia/shell-lane.ps1` was written, parse-checked clean, and
scheduled into the interactive session, where it exited 1 having written not one byte. It parsed
clean because the check ran under PowerShell 7 (`pwsh`), and it failed because scheduled tasks run
`powershell.exe`, which is Windows PowerShell 5.1. The two disagree about one thing:

    5.1 decodes a file with no byte-order mark as the ANSI code page (cp1252), not as UTF-8.

So an em dash - U+2014, three UTF-8 bytes E2 80 94 - arrives in 5.1 as three cp1252 characters,
the last of which is 0x94: U+201D, a RIGHT DOUBLE QUOTATION MARK. PowerShell honours curly quotes
as string delimiters. An em dash inside a double-quoted string therefore ENDS that string early,
and every construct after it parses against the wrong grammar. The script had fourteen such lines
and produced a cascade of errors starting nowhere near the real cause.

The trap's shape is what makes it worth a gate rather than a fix. Five other tracked scripts carry
non-ASCII with no BOM TODAY and all five parse and run correctly, because their non-ASCII happens
to sit in comments, where an early-terminated string is harmless. They are one prose edit away from
the same failure, and that edit will look completely unrelated to the breakage it causes.

TWO CHECKS, and the second is the one that catches it before it bites:

  PARSE      the file parses under 5.1 itself. Decisive, never a false positive, and it only fires
             AFTER someone has already been bitten.
  DECODING   the file has non-ASCII bytes and no BOM. Fires while the file still works, and the
             remedy is three bytes at the front.

Exit 0 clean, 1 on any finding, 2 if the gate could not run (no git, no powershell.exe) - which is
NOT a pass, because a check that could not run and a check that found nothing are the same green.
"""
import argparse
import io
import os
import subprocess
import sys
import tempfile
from pathlib import Path

# scripts/windows/ps-parse-gate.py -> the repository root, derived rather than assumed.
ROOT = Path(__file__).resolve().parents[2]

# The target arrives through the environment, not as an argument. `powershell.exe -Command "..."`
# does NOT bind trailing arguments to $args - it appends them to the command as further statements
# - so a snippet reading $args[0] parses a null path and reports EVERY file as broken. The control
# caught exactly that: all three fixtures, including the two healthy ones, came back PARSE.
PARSE_SNIPPET = (
    "$e = $null; "
    "[void][System.Management.Automation.Language.Parser]::ParseFile("
    "$env:PSPG_TARGET, [ref]$null, [ref]$e); "
    "if ($e.Count) { "
    "  $e | Select-Object -First 3 | ForEach-Object { "
    "    Write-Output ('line ' + $_.Extent.StartLineNumber + ': ' + $_.Message) }; "
    "  exit 1 } else { exit 0 }"
)


def windows_powershell():
    """Windows PowerShell 5.1 specifically - `pwsh` is a different parser and would defeat this."""
    for candidate in (
        os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                     r"System32\WindowsPowerShell\v1.0\powershell.exe"),
        "powershell.exe",
    ):
        try:
            probe = subprocess.run([candidate, "-NoProfile", "-Command",
                                    "$PSVersionTable.PSVersion.Major"],
                                   capture_output=True, text=True, timeout=60)
            if probe.returncode == 0 and probe.stdout.strip().startswith("5"):
                return candidate
        except (OSError, subprocess.SubprocessError):
            continue
    return None


def parse_under_51(shell, path):
    """Return (ok, message). A parse that could not be attempted is not a pass."""
    try:
        env = dict(os.environ, PSPG_TARGET=str(Path(path).resolve()))
        run = subprocess.run([shell, "-NoProfile", "-Command", PARSE_SNIPPET],
                             capture_output=True, text=True, timeout=120, env=env)
    except (OSError, subprocess.SubprocessError) as exc:
        return None, "the parse could not be run: %s" % exc
    if run.returncode == 0:
        return True, ""
    return False, (run.stdout or run.stderr or "").strip()


def inspect(path):
    """The decoding half: bytes only, no parse, so it fires while the file still works."""
    raw = io.open(path, "rb").read()
    has_bom = raw.startswith(b"\xef\xbb\xbf")
    non_ascii = any(b > 127 for b in raw)
    return has_bom, non_ascii


def shown(path):
    """Print a corpus path relative to the root, so the output does not move with the caller."""
    try:
        return Path(path).resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def tracked_scripts():
    """Every tracked .ps1, enumerated from the repo root rather than the caller's directory.

    ANCHORED, and the anchor is the point. `git ls-files` lists the tracked files under the
    working directory, so an unanchored call makes this gate's denominator a property of where
    somebody stood when they ran it: from `scripts/windows/` it reports clean over six files and
    from the root over eleven, and both print the same green. The subject here is the
    repository's PowerShell, which does not change when the caller moves.

    The filter's drops are RECORDED rather than silent. A path git tracks that is not a file on
    disk is a staged deletion or a submodule pointer, and it is exactly the shape that would
    shrink the denominator without shrinking the green - the gate would report clean over fewer
    scripts and say nothing about the ones it stopped reading.
    """
    run = subprocess.run(["git", "-C", str(ROOT), "ls-files", "*.ps1"],
                         capture_output=True, text=True)
    if run.returncode != 0:
        return None
    # Every line git emitted is classed, and nothing is filtered away on the way in. A blank
    # line and a tracked-but-missing path are different facts and both are counted, because the
    # only cheap way for this corpus to shrink without anybody noticing is for a line to be
    # dropped by a comprehension nobody reads.
    listed, kept, blank, absent = 0, [], 0, []
    for line in run.stdout.splitlines():
        listed += 1
        rel = line.strip()
        if not rel:
            blank += 1
        elif (ROOT / rel).is_file():
            kept.append(rel)
        else:
            absent.append(rel)
    print("ps-parse-gate: corpus read %d line(s) from `git -C %s ls-files -- *.ps1`; "
          "kept %d; dropped %d (blank %d, tracked but not a file on disk %d)"
          % (listed, ROOT, len(kept), blank + len(absent), blank, len(absent)))
    for rel in absent:
        print("    not read (tracked but not a file on disk): %s" % rel)
    return [ROOT / rel for rel in kept]


def check(paths, shell, label="tracked"):
    findings = []
    for path in sorted(paths):
        has_bom, non_ascii = inspect(path)
        ok, detail = parse_under_51(shell, path)
        if ok is None:
            findings.append((path, "NOT-RUN", detail))
            continue
        if not ok:
            findings.append((path, "PARSE", detail))
        elif non_ascii and not has_bom:
            findings.append((path, "DECODING",
                             "holds non-ASCII bytes and no BOM, so Windows PowerShell 5.1 decodes "
                             "it as cp1252. It parses today only because none of that non-ASCII "
                             "sits inside a quoted string. Add a UTF-8 BOM."))
    print("ps-parse-gate: checked %d %s PowerShell script(s) under Windows PowerShell 5.1"
          % (len(paths), label))
    return findings


def report(findings):
    if not findings:
        print("             all clean: every one parses, and every one with non-ASCII carries a BOM")
        return 0
    print("             %d finding(s):" % len(findings))
    for path, kind, detail in findings:
        print("  * %-9s %s" % (kind, shown(path)))
        for line in detail.splitlines():
            print("               %s" % line)
    print("")
    print("  A DECODING finding is not cosmetic and not a style preference. The file works now and")
    print("  breaks on the first em dash, curly quote or accented character somebody adds inside a")
    print("  string - an edit that will look like prose and read like a parser bug.")
    return 1


# ---------------------------------------------------------------------------
def control(shell):
    """Prove the gate fires, and prove it stays silent - a one-way check is a green light.

    Three fixtures. The third is the real subject: it reproduces the exact byte sequence that cost
    this repo a scheduled-task run, and it must fire on BOTH checks at once.
    """
    dash = "\u2014"
    fixtures = [
        ("ascii-no-bom.ps1", b'Write-Host "plain ascii"\n', set(),
         "ASCII with no BOM is correct and must stay silent - most of the tree is this"),
        ("nonascii-with-bom.ps1",
         b"\xef\xbb\xbf" + ('Write-Host "an em dash %s inside a string"\n' % dash).encode("utf-8"),
         set(),
         "non-ASCII WITH a BOM decodes correctly under 5.1 and must stay silent, or the gate is "
         "just banning non-ASCII"),
        ("nonascii-no-bom.ps1",
         ('Write-Host "an em dash %s inside a string"\nif ($true) { Write-Host "after" }\n'
          % dash).encode("utf-8"),
         {"PARSE"},
         "the measured failure: no BOM, an em dash inside a double-quoted string. 5.1 reads the "
         "dash's third byte as a curly quote, ends the string early, and the file stops parsing. "
         "PARSE alone is correct here and DECODING would be noise: one cause owes one finding, and "
         "the remedy printed for a file that will not parse is the same either way"),
        ("nonascii-no-bom-comment-only.ps1",
         ('# an em dash %s in a comment, where an early-terminated string harms nothing\n'
          'Write-Host "plain ascii"\n' % dash).encode("utf-8"),
         {"DECODING"},
         "THE LATENT CASE, and the reason the decoding check exists at all. This parses perfectly "
         "under 5.1 today - it is the exact shape of the five tracked scripts - and it breaks the "
         "moment somebody moves that dash, or any other non-ASCII character, inside a string. Only "
         "the byte-level check can see it; the parser cannot, because there is nothing yet wrong"),
    ]

    wrong = 0
    with tempfile.TemporaryDirectory() as tmp:
        for name, content, expected, why in fixtures:
            path = Path(tmp) / name
            io.open(path, "wb").write(content)
            got = {kind for _, kind, _ in check([path], shell, label="fixture")}
            verdict = "correct" if got == expected else "WRONG"
            if got != expected:
                wrong += 1
            print("  %-7s %-22s expected {%s} got {%s}"
                  % (verdict, name, ", ".join(sorted(expected)) or "-",
                     ", ".join(sorted(got)) or "-"))
            print("          %s" % why)
    print("")
    print("control: %d fixture(s), %d correct, %d WRONG" % (len(fixtures), len(fixtures) - wrong, wrong))
    return 1 if wrong else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--control", action="store_true",
                    help="prove the gate fires on the failure and stays silent on the healthy shapes")
    args = ap.parse_args()

    shell = windows_powershell()
    if shell is None:
        print("ps-parse-gate: NOT RUN - no Windows PowerShell 5.1 on this machine.")
        print("               That is not a pass. This gate measures a 5.1-specific decoding rule,")
        print("               and 5.1 is what scheduled tasks and the shipped lanes run.")
        return 2

    if args.control:
        return control(shell)

    paths = tracked_scripts()
    if paths is None:
        print("ps-parse-gate: NOT RUN - `git ls-files` failed, so the subject set is unknown.")
        return 2
    if not paths:
        print("ps-parse-gate: NOT RUN - zero tracked .ps1 files. A gate whose subject set is empty")
        print("               reports clean forever; that is the instrument failing, not the tree.")
        return 2

    return report(check(paths, shell))


if __name__ == "__main__":
    sys.exit(main())
