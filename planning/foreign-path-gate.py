#!/usr/bin/env python3
"""Find every scratch-directory path in the tracked corpus, and fail the ones that are citations.

## The defects this exists for

`G6` and `G11`.

`G6` (unrecoverable scratch evidence): An artifact a record cites as evidence lived in `/tmp`, and
`/tmp` is emptied. A scratch path in a durable record without a withdrawal marker is either a dead
link or one reboot away from becoming one.

`G11` (checkout drift and non-deterministic corpus): The original gate enumerated tracked paths from
the index but opened each path from the working-tree disk. On commit `597236c`, the gate exited 1 on
a pristine detached checkout of `HEAD` and 0 on dirty main because uncommitted local edits marked two
citations withdrawn on disk. Additionally, querying the local host's `/tmp` filesystem inside the
class partition made classification counts dependent on whatever happened to sit in `/tmp` on that
runner.

## The corpus of record, decided explicitly

**The corpus is the committed git tree at `HEAD` (or `--rev <rev>`)**, read directly as blobs from
the git object store. This guarantees that:
1. The verdict is a pure, deterministic property of the commit.
2. A pristine checkout, a dirty working tree, and a fresh clone of the same commit give identical
   verdicts and identical class counts.
3. Uncommitted working-tree edits cannot accidentally pass or fail a commit-level gate.

`--worktree` is available for pre-commit inspection of working-tree files on disk, and prints an
explicit notice when uncommitted changes are present.

## What this reads, and what it deliberately does not

**Scratch roots only**: `/tmp`, `/private/tmp`, `/var/folders`, `$TMPDIR`. Nothing durable ever
lives under one, so a path naming one is either a pointer with an expiry date nobody wrote down or
a value in a described system.

**Machine-durable absolute paths are counted and never blocked** — `/Users/…`, `~/…`,
`/Applications/…`. They are a different defect with a different remedy: a scratch path fails
because the artifact evaporates, a machine path fails because the reader is on another machine.
The count is printed under COUNTS so it cannot be forgotten.

**`planning/citation-gate.py` is the sibling, not the parent.** It asks whether a `path:line`
pointer still resolves — anchor, line, tree. This asks whether the artifact behind a path survives
at all and sits inside the repository.

## The classes, and which of them block

Every scratch-path occurrence lands in exactly one class. The set is a partition over N3:

  RUNTIME     the token is in an executable or a source file. A committed script that writes to
              `/tmp` is re-runnable, which is the property that was missing. Not a citation.
  GENERATED   the token is in a file a script regenerates. A stale path there is fixed by
              re-running its generator, not by a writer. Counted by name, never dropped in silence.
  SUBJECT     the token is in a hand-written record but is a VALUE in the described system — an
              env value (`HOME=/tmp/fakehome`), a config example (`cwd: "/tmp/project"`), a URL
              example (`file:///tmp/x`), or inside code fences / test assertions / redirects.
  WITHDRAWN   an artifact pointer in a hand-written record, and the record says the artifact is
              gone, unrecoverable, reconstructed, not retained, or recovered elsewhere. Does not block.
  CITED       an unwithdrawn artifact pointer in a hand-written record. **Blocks.**

Host filesystem resolution (whether a cited `/tmp` path happens to exist on the current host machine
at run time) is reported as an informative diagnostic attribute (`live on host` vs `dead on host`),
but does not alter the partition class or gate verdict. An unwithdrawn scratch citation is equally
defective whether live or dead: a live scratch file is one reboot from being dead.

`WITHDRAWN` is what makes the rule satisfiable without deleting history. A record may keep a dead
path if it says so in a machine-readable form — restoring the distinction between unrecoverable
evidence and evidence never gathered.

## Citation versus value — the discriminator, named

A scratch path is read as an artifact pointer when its last segment carries a document, log or
source extension, or when it ends in `/` (a directory citation). Otherwise it is a value.

## The withdrawal marker, and why its window is strict

A marker is a delimited word: `(gone)`, `(unrecoverable)`, `(not retained)`, `(does not exist)`,
`| gone |`, `**gone**`. It must sit within 200 characters or before the next scratch token on the
collapsed view.

## Controls

An absence sweep with no presence control is an instrument that has never been shown to fire.
`--control` runs automatically on every invocation and verifies:
1. All class plants (RUNTIME, SUBJECT, CITED, WITHDRAWN, negative controls).
2. The wrap discriminator (collapsed vs line-anchored disagreement).
3. Severity-preserving deduplication (worst reading wins).
4. Generated file exclusion predicates.
5. Host resolution probe.
6. **2-way checkout control (G11)**: proves that a pristine clone of `HEAD` and a working tree with
   uncommitted changes both produce identical verdicts and counts when evaluating `HEAD`, while
   `--worktree` on the dirty tree reflects the working-tree differences.

Exit 0 when N5 holds no `CITED` occurrences; exit 1 otherwise; exit 2 if any presence control fails.
"""

import argparse
import fnmatch
import glob as globmod
import os
import pathlib
import re
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve()
ROOT = HERE.parent.parent

# ------------------------------------------------------------------ what a scratch path looks like

# A path segment body. Brace groups are atomic so `{1..4}` and `{a,b}` survive without letting a
# bare comma run the token into the next clause.
BODY = r"(?:[A-Za-z0-9_.~+=*@-]|/|\{[^}\s|`\"']{0,40}\})+"

SCRATCH = re.compile(
    r"(?<![A-Za-z0-9_~.-])"
    r"(?P<path>(?:/private)?/tmp/" + BODY + r"|/var/folders/" + BODY + r"|\$TMPDIR/" + BODY + r")")

# Counted, never blocked. See the module docstring.
MACHINE = re.compile(r"(?<![A-Za-z0-9_~.-])(?:/Users/[a-z]|~/|/Applications/|/Library/|/opt/)")

# An artifact pointer carries one of these on its last segment, or ends in `/`.
DOC_EXT = frozenset("""
md txt log json py sh zsh bash js mjs cjs ts tsx swift diff patch tsv csv html css yml yaml
plist toml png svg pdf out stdout stderr ndjson xml lock sql rb go rs c h m mm
trace ips crash profraw profdata heapsnapshot dSYM spindump
""".split())

# A delimited withdrawal marker. The delimiter is the point: ordinary prose containing `deleted`
# must not satisfy the gate.
_W = (r"gone|unrecoverable|not\s+recover(?:ed|able)|no\s+longer\s+(?:exists?|present|on\s+disk)"
      r"|does\s+not\s+exist|never\s+retained|not\s+retained|withdrawn|deleted"
      r"|reconstructed|recovered")

WITHDRAW = re.compile(
    r"\((?:%s)\b[^)]{0,400}\)"          # parenthesised, optionally with an explanation
    r"|\|\s*(?:%s)\b\s*\|"              # a table cell holding only the marker
    r"|\*\*(?:%s)\b[^*]{0,80}\*\*"      # bold and closed
    % (_W, _W, _W), re.I)

WINDOW = 200

REDIRECT = re.compile(r"(?:\d?>>?&?\d?|\|\s*tee(?:\s+-a)?|-o|--output(?:=|\s)|--out)\s*$")
ELLIPSIS = re.compile(r"(?:^|/)\.{3}(?:/|$)")
ASSERTED = re.compile(r"(?:==|:=)\s*`?$")

# Regenerated by a script rather than maintained by a writer.
GENERATED = (
    "planning/fidelity/*.tsv",
    "planning/fidelity/*.ledger.md",
    "planning/reckoning/*/*.json",
    "planning/tailings/*.json",
    "planning/test-campaign/*.json",
    "planning/test-campaign/evidence/*.json",
    "planning/test-campaign/evidence/*/*.json",
    "planning/test-campaign/evidence/*/*/*.json",
    "planning/test-campaign/evidence/*/*/.*.ndjson",
    "planning/reader-accounting.tsv",
    "planning/parity/*.tsv",
    "planning/status/*.json",
    "planning/test-campaign.2026-08-19-paper/*.json",
)

SELF = ("planning/foreign-path-gate.py",)

BINARY_SUFFIX = frozenset(
    ".png .jpg .jpeg .webp .gif .ico .icns .pdf .zip .tar .gz .woff .woff2 .ttf .otf "
    ".mp4 .mov .car .dat .bin .sqlite".split())

CLASSES = ("RUNTIME", "GENERATED", "SUBJECT", "CITED", "WITHDRAWN")
BLOCKING = ("CITED",)

SEVERITY = {"RUNTIME": 0, "GENERATED": 0, "SUBJECT": 1, "WITHDRAWN": 2, "CITED": 3}


# ------------------------------------------------------------------------ the wrap-tolerant reader

def quote_marker_offsets(raw):
    """Offsets of blockquote markers opening a line."""
    marks, i, n = set(), 0, len(raw)
    at_line_start = True
    while i < n:
        if at_line_start:
            j = i
            while j < n and raw[j] in " \t":
                j += 1
            while j < n and raw[j] == ">":
                marks.add(j)
                j += 1
                while j < n and raw[j] in " \t":
                    j += 1
            i = j
            at_line_start = False
            continue
        if raw[i] == "\n":
            at_line_start = True
        i += 1
    return marks


def normalise(raw):
    """Whitespace-collapsed view of `raw`, plus an offset back into `raw` per normalised char."""
    marks = quote_marker_offsets(raw)
    chars, offsets, i, n = [], [], 0, len(raw)
    while i < n:
        if raw[i].isspace() or i in marks:
            j = i
            while j < n and (raw[j].isspace() or j in marks):
                j += 1
            chars.append(" ")
            offsets.append(i)
            i = j
            continue
        chars.append(raw[i])
        offsets.append(i)
        i += 1
    return "".join(chars), offsets


def line_of(raw, offset):
    return raw.count("\n", 0, offset) + 1


def trim(tok):
    """Drop sentence punctuation the path regex swallowed, and a markdown emphasis tail."""
    while tok and tok[-1] in ".,;:!?":
        tok = tok[:-1]
    while tok.endswith("*"):
        tok = tok[:-1]
    return tok


def is_pointer(tok):
    """True when the token names an artifact rather than a value. See the docstring's discriminator."""
    if ELLIPSIS.search(tok):
        return False
    if tok.endswith("/"):
        return True
    last = tok.rsplit("/", 1)[-1]
    if "." not in last:
        return False
    return last.rsplit(".", 1)[-1].lower() in DOC_EXT


def exists_now(tok):
    """Does the cited path resolve on this host machine? Brace groups widen to a glob."""
    if tok.startswith("$TMPDIR"):
        tmpdir = os.environ.get("TMPDIR", "/tmp").rstrip("/")
        tok = tmpdir + tok[len("$TMPDIR"):]
    probe = re.sub(r"\{[^}]*\}", "*", tok)
    if probe != tok or "*" in probe:
        return bool(globmod.glob(probe))
    return os.path.exists(tok)


def matches_any(path, globs):
    return any(fnmatch.fnmatch(path, g) for g in globs)


def file_kind(path):
    """RECORD, GENERATED or RUNTIME — the corpus split every reading below is stated against."""
    if matches_any(path, GENERATED):
        return "GENERATED"
    if path.endswith(".md"):
        return "RECORD"
    return "RUNTIME"


def classify(path, tok, head, tail):
    """One class per occurrence. `head` is the collapsed text immediately before the token and
    `tail` the collapsed text between this token and the next."""
    kind = file_kind(path)
    if kind == "GENERATED":
        return "GENERATED"
    if kind == "RUNTIME":
        return "RUNTIME"
    if REDIRECT.search(head) or ASSERTED.search(head):
        return "SUBJECT"
    if not is_pointer(tok):
        return "SUBJECT"
    if WITHDRAW.search(tail):
        return "WITHDRAWN"
    return "CITED"


# ------------------------------------------------------------------------------------ the two reads

def fenced_spans(raw):
    """Character ranges of ``` fenced blocks."""
    spans, open_at, i = [], None, 0
    for line in raw.splitlines(keepends=True):
        stripped = line.lstrip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            if open_at is None:
                open_at = i
            else:
                spans.append((open_at, i + len(line)))
                open_at = None
        i += len(line)
    if open_at is not None:
        spans.append((open_at, len(raw)))
    return spans


def in_span(spans, off):
    return any(a <= off < b for a, b in spans)


def scan_collapsed(path, raw):
    """Every scratch occurrence on the wrap-tolerant view, classified. This is the gate's reading."""
    fences = fenced_spans(raw)
    view, offsets = normalise(raw)
    hits = [(m.start("path"), trim(m.group("path"))) for m in SCRATCH.finditer(view)]
    out = []
    for idx, (start, tok) in enumerate(hits):
        if not tok:
            continue
        end = start + len(tok)
        limit = hits[idx + 1][0] if idx + 1 < len(hits) else len(view)
        tail = view[end:min(limit, end + WINDOW)]
        head = view[max(0, start - 40):start]
        raw_off = offsets[min(start, len(offsets) - 1)]
        cls = "SUBJECT" if in_span(fences, raw_off) else classify(path, tok, head, tail)
        out.append({
            "file": path,
            "token": tok,
            "line": line_of(raw, raw_off),
            "class": cls,
        })
    return out


def scan_lines(path, raw):
    """The same scan, line-anchored — what a `grep` sees. Reported as N1 and used by the control to
    prove the collapsed reader is doing work a line reader cannot."""
    out, fences, off = [], fenced_spans(raw), 0
    for n, line in enumerate(raw.splitlines(keepends=True), 1):
        base, line = off, line.rstrip("\n")
        off = base + len(line) + 1
        for m in SCRATCH.finditer(line):
            tok = trim(m.group("path"))
            if not tok:
                continue
            start = m.start("path")
            end = start + len(tok)
            tail = line[end:min(len(line), end + WINDOW)]
            head = line[max(0, start - 40):start]
            cls = "SUBJECT" if in_span(fences, base + start) else classify(path, tok, head, tail)
            out.append({"file": path, "token": tok, "line": n, "class": cls})
    return out


def scan_file(path, raw):
    """The gate's reading of one file. THE SINGLE SEAM: `main` reads a file only through here.

    Before this existed, `main` called `scan_collapsed` directly and the control called
    `scan_collapsed` and `scan_lines` directly, which left the *choice between them* untested —
    the verify pass of 2026-08-26 found that swapping the wrap-tolerant reader for the
    line-anchored one survived every plant green. Keeping one seam is half the fix; the other
    half is `driver_arm` below, which runs the driver over a corpus the two readers disagree on.
    """
    return scan_collapsed(path, raw)


def dedupe(occurrences):
    """One row per (citing file, token), keeping the MOST SEVERE class rather than the first seen."""
    best = {}
    for h in occurrences:
        key = (h["file"], h["token"])
        cur = best.get(key)
        if cur is None or SEVERITY[h["class"]] > SEVERITY[cur["class"]]:
            best[key] = h
    return list(best.values())


# ---------------------------------------------------------------------------------------- the corpus

def read_corpus(root=ROOT, rev="HEAD", worktree=False):
    """Enumerate and read all tracked files in the corpus.

    When `worktree=False` (the default), reads tracked blobs from the git commit at `rev`
    directly via git cat-file, ensuring a hermetic, deterministic verdict independent of
    working-tree modifications.

    When `worktree=True`, reads files from the working tree on disk.

    Returns `(files_data, dropped, undecodable, is_dirty, dirty_count)`.
    """
    dirty_res = subprocess.run(["git", "-C", str(root), "status", "--porcelain"],
                               capture_output=True, text=True, check=True)
    dirty_lines = [l for l in dirty_res.stdout.splitlines() if l.strip()]
    is_dirty = len(dirty_lines) > 0
    dirty_count = len(dirty_lines)

    files_data = {}
    dropped = []
    undecodable = []

    if not worktree:
        out = subprocess.run(["git", "-C", str(root), "ls-tree", "-r", "-z", rev],
                             capture_output=True, check=True).stdout
        entries = [e for e in out.split(b"\0") if e]
        blobs_to_read = []
        for e in entries:
            meta, path_b = e.split(b"\t", 1)
            path = path_b.decode("utf-8", errors="replace")
            parts = meta.split()
            mode, kind, sha = parts[0].decode(), parts[1].decode(), parts[2].decode()
            if kind == "commit":
                undecodable.append((path, "submodule"))
                continue
            if path in SELF:
                dropped.append(path)
                continue
            if pathlib.Path(path).suffix.lower() in BINARY_SUFFIX:
                undecodable.append((path, "binary asset"))
                continue
            blobs_to_read.append((path, sha))

        if blobs_to_read:
            proc = subprocess.Popen(["git", "-C", str(root), "cat-file", "--batch"],
                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            for path, sha in blobs_to_read:
                proc.stdin.write(f"{sha}\n".encode())
            proc.stdin.flush()

            for path, sha in blobs_to_read:
                header = proc.stdout.readline().decode("utf-8", errors="replace").strip()
                parts = header.split()
                if len(parts) >= 3 and parts[1] == "blob":
                    size = int(parts[2])
                    content = proc.stdout.read(size)
                    proc.stdout.read(1)  # trailing newline
                    try:
                        files_data[path] = content.decode("utf-8")
                    except UnicodeDecodeError:
                        undecodable.append((path, "undecodable"))
                else:
                    undecodable.append((path, "missing"))
            proc.stdin.close()
            proc.wait()
    else:
        out = subprocess.run(["git", "-C", str(root), "ls-files", "-z"],
                             capture_output=True, check=True).stdout
        paths = [p.decode("utf-8", errors="replace") for p in out.split(b"\0") if p]
        for path in paths:
            if path in SELF:
                dropped.append(path)
                continue
            p = root / path
            try:
                raw = p.read_text(encoding="utf-8")
                files_data[path] = raw
            except FileNotFoundError:
                undecodable.append((path, "missing"))
            except IsADirectoryError:
                undecodable.append((path, "submodule"))
            except UnicodeDecodeError:
                undecodable.append((path, "undecodable" if pathlib.Path(path).suffix.lower() not in BINARY_SUFFIX else "binary asset"))

    return files_data, dropped, undecodable, is_dirty, dirty_count


# ------------------------------------------------------------------------------- the presence control

CONTROL_PLANTS = [
    ("runtime.sh",
     "#!/bin/sh\nLOG=/tmp/control-runtime.log\necho hi > \"$LOG\"\n",
     "RUNTIME", "a committed script writing to /tmp"),
    ("subject.md",
     "Measured under `HOME=/tmp/fakehome`, node's `os.homedir()` returns that value.\n",
     "SUBJECT", "a scratch path as a value in the described system"),
    ("dead.md",
     "The sweep is at `/tmp/control-definitely-absent-9f3a/sweep.py` and decides the item.\n",
     "CITED", "a pointer at an uncommitted scratch artifact blocks"),
    ("withdrawn.md",
     "The sweep was at `/tmp/control-definitely-absent-9f3a/sweep2.py` (gone) and is not re-runnable.\n",
     "WITHDRAWN", "a pointer the record marks gone"),
    ("not-retained.md",
     "Prompt `/tmp/control-definitely-absent-9f3a/p.txt` (not retained) — option order swapped.\n",
     "WITHDRAWN", "(not retained) marker withdraws scratch prompt"),
    ("redirect.md",
     "Each gate captured as `make test > /tmp/control-definitely-absent-9f3a/f.txt 2>&1; echo $?`.\n",
     "SUBJECT", "a redirect target inside a quoted command is a sink, not a citation"),
    ("ellipsis.md",
     "The run printed `0 tools cached -> /tmp/.../manifest.json`, which names a shape.\n",
     "SUBJECT", "an elided segment cannot be resolved, so it cannot be a citation"),
    ("fenced.md",
     "The trap was reproduced:\n\n```\n$ swift /tmp/control-definitely-absent-9f3a/trap.swift\n```\n",
     "SUBJECT", "a transcript inside a fence is an invocation, not a citation"),
    ("neg-table.md",
     "| `/tmp/control-definitely-absent-9f3a/a.log` | the run | recovered 40 items |\n",
     "CITED", "NEGATIVE: a cell saying `recovered 40 items` withdraws nothing"),
    ("neg-bullet.md",
     "- The log is `/tmp/control-definitely-absent-9f3a/b.log`\n* deleted the old cache first\n",
     "CITED", "NEGATIVE: the next bullet is not a marker"),
    ("neg-emphasis.md",
     "The log at `/tmp/control-definitely-absent-9f3a/c.log` — the runner *recovered* state cleanly.\n",
     "CITED", "NEGATIVE: an emphasised verb in prose is not a marker"),
    ("asserted.md",
     "| `homeComesFromTheEnvironment` | `HOME=/tmp/x` -> `claudeJSON == /tmp/control-definitely-absent-9f3a/.claude.json` |\n",
     "SUBJECT", "a token after an equality is the value asserted, not an artifact"),
]

CONTROL_WRAP = (
    "wrapped.md",
    "The instrument recorded in gap-fix 2 lived at `/tmp/control-definitely-absent-9f3a/sweep3.py`\n"
    "(gone), so the verdict that rests on it is no longer falsifiable.\n",
    "WITHDRAWN", "CITED")


def driver_arm(d):
    """Run this gate's own driver over a planted repository, end to end.

    Every other plant calls a scanner directly, so all of them pass whichever scanner `main`
    happens to use. The verify pass of 2026-08-26 measured the consequence: replacing the
    wrap-tolerant reader with the line-anchored one inside `main` left the control ALL PLANTS
    FIRED, because `N1 == N2` on this repository and the two readers disagree on exactly one
    shape — a withdrawal marker carried onto the line after its citation.

    So the corpus here is built out of that shape, and the two readers give DIFFERENT verdicts
    over it: line-anchored blocks both files, wrap-tolerant blocks one. The arm asserts the
    wrap-tolerant verdict through the real driver, which is the only place the reader choice
    is observable. Returns (ok, expected, actual).
    """
    repo = d / "driver"
    repo.mkdir()
    subprocess.run(["git", "init"], cwd=repo, capture_output=True, check=True)
    subprocess.run(["git", "config", "user.name", "Control"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.email", "control@test.com"], cwd=repo, check=True)
    # The wrap: `(gone)` sits on the next source line, adjacent only once whitespace collapses.
    (repo / "wrapped.md").write_text(
        "The sweep that decided it lived at `/tmp/control-definitely-absent-9f3a/w.py`\n"
        "(gone), so the verdict resting on it is no longer falsifiable.\n")
    (repo / "dead.md").write_text(
        "The sweep is at `/tmp/control-definitely-absent-9f3a/d.py` and decides the item.\n")
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-m", "planted"], cwd=repo, capture_output=True, check=True)

    res = subprocess.run(
        [sys.executable, str(pathlib.Path(__file__).resolve()),
         "--root", str(repo), "--skip-control", "--quiet"],
        capture_output=True, text=True)
    # Read the BLOCKED block alone, whole, with no per-line discard — naming the file anywhere
    # in stdout is not enough, because the counts block names it too in the reader-disagreement
    # diagnostic. Matched rather than looped so this reader drops nothing silently.
    m = re.search(r"^BLOCKED —.*\n((?:  .*\n)*)", res.stdout, re.M)
    blocked = m.group(1).splitlines() if m else []
    expected = "exit 1 · blocks dead.md only"
    blocked_dead = any(" dead.md:" in b for b in blocked)
    blocked_wrapped = any(" wrapped.md:" in b for b in blocked)
    actual = "exit %d · %s" % (
        res.returncode,
        "blocks dead.md only" if (blocked_dead and not blocked_wrapped)
        else ("blocks both" if blocked_wrapped and blocked_dead
              else ("blocks wrapped.md only" if blocked_wrapped else "blocks neither")))
    ok = res.returncode == 1 and blocked_dead and not blocked_wrapped
    return ok, expected, actual


def run_control(verbose=True):
    """Plant test cases and run the 2-way checkout control in a throwaway repo."""
    rows, ok = [], True
    with tempfile.TemporaryDirectory() as td:
        d = pathlib.Path(td)
        for name, body, expect, note in CONTROL_PLANTS:
            (d / name).write_text(body)
            got = scan_collapsed(name, body)
            actual = got[0]["class"] if got else "NO-HIT"
            good = actual == expect
            ok &= good
            rows.append((name, expect, actual, "fired" if good else "MISSED", note))

        # The severity-preserving dedup, exercised through the function the run uses.
        mixed = [{"file": "x.md", "token": "/tmp/t.py", "class": "SUBJECT"},
                 {"file": "x.md", "token": "/tmp/t.py", "class": "CITED"}]
        d_ok = len(dedupe(mixed)) == 1 and dedupe(mixed)[0]["class"] == "CITED"
        ok &= d_ok
        rows.append(("(dedupe) SUBJECT then CITED", "CITED",
                     dedupe(mixed)[0]["class"], "fired" if d_ok else "MISSED",
                     "the worst reading of a repeated token wins, not the first"))

        name, body, expect_c, expect_l = CONTROL_WRAP
        (d / name).write_text(body)
        c = scan_collapsed(name, body)
        line = scan_lines(name, body)
        ac = c[0]["class"] if c else "NO-HIT"
        al = line[0]["class"] if line else "NO-HIT"
        good = (ac == expect_c) and (al == expect_l) and (ac != al)
        ok &= good
        rows.append((name, "%s / %s" % (expect_c, expect_l), "%s / %s" % (ac, al),
                     "fired" if good else "MISSED",
                     "wrap discriminator: collapsed and line-anchored must DISAGREE"))

        gen_ok = file_kind("planning/reckoning/2026-08-25/ledger.json") == "GENERATED"
        ok &= gen_ok
        rows.append(("(corpus) reckoning ledger.json", "GENERATED",
                     file_kind("planning/reckoning/2026-08-25/ledger.json"),
                     "fired" if gen_ok else "MISSED", "the GENERATED globs are live"))

        live_ok = exists_now("/tmp") is True and exists_now("/tmp/control-definitely-absent-9f3a") is False
        ok &= live_ok
        rows.append(("(probe) exists_now", "True / False",
                     "%s / %s" % (exists_now("/tmp"), exists_now("/tmp/control-definitely-absent-9f3a")),
                     "fired" if live_ok else "MISSED",
                     "the host filesystem probe resolves live paths"))

        # G11: 2-way checkout control (dirty working tree vs pristine clone both evaluating HEAD)
        repo_dir = d / "repo"
        repo_dir.mkdir()
        subprocess.run(["git", "init"], cwd=repo_dir, capture_output=True, check=True)
        subprocess.run(["git", "config", "user.name", "Control"], cwd=repo_dir, check=True)
        subprocess.run(["git", "config", "user.email", "control@test.com"], cwd=repo_dir, check=True)

        (repo_dir / "record.md").write_text("Evidence cited at `/tmp/control-definitely-absent-9f3a/e.log`.\n")
        subprocess.run(["git", "add", "record.md"], cwd=repo_dir, check=True)
        subprocess.run(["git", "commit", "-m", "init"], cwd=repo_dir, capture_output=True, check=True)

        pristine_dir = d / "pristine"
        subprocess.run(["git", "clone", "--shared", str(repo_dir), str(pristine_dir)],
                       capture_output=True, check=True)

        # Dirty the working tree in repo_dir by adding (gone) on disk without committing
        (repo_dir / "record.md").write_text("Evidence cited at `/tmp/control-definitely-absent-9f3a/e.log` (gone).\n")

        repo_head_data, _, _, repo_dirty, _ = read_corpus(root=repo_dir, rev="HEAD", worktree=False)
        pristine_head_data, _, _, pristine_dirty, _ = read_corpus(root=pristine_dir, rev="HEAD", worktree=False)
        repo_wt_data, _, _, _, _ = read_corpus(root=repo_dir, worktree=True)

        repo_head_hits = scan_collapsed("record.md", repo_head_data["record.md"])
        pristine_head_hits = scan_collapsed("record.md", pristine_head_data["record.md"])
        repo_wt_hits = scan_collapsed("record.md", repo_wt_data["record.md"])

        cls_repo_head = repo_head_hits[0]["class"] if repo_head_hits else "NO-HIT"
        cls_pristine_head = pristine_head_hits[0]["class"] if pristine_head_hits else "NO-HIT"
        cls_repo_wt = repo_wt_hits[0]["class"] if repo_wt_hits else "NO-HIT"

        two_way_ok = (repo_dirty is True and pristine_dirty is False and
                      cls_repo_head == "CITED" and cls_pristine_head == "CITED" and
                      cls_repo_head == cls_pristine_head and
                      cls_repo_wt == "WITHDRAWN")
        ok &= two_way_ok
        rows.append(("(2-way G11) dirty HEAD vs pristine HEAD", "CITED == CITED (wt WITHDRAWN)",
                     "%s == %s (wt %s)" % (cls_repo_head, cls_pristine_head, cls_repo_wt),
                     "fired" if two_way_ok else "MISSED",
                     "committed blob reading guarantees deterministic verdicts across checkouts"))

        driver_ok, driver_expect, driver_actual = driver_arm(d)
        ok &= driver_ok
        rows.append(("(driver) reader choice, end to end", driver_expect, driver_actual,
                     "fired" if driver_ok else "MISSED",
                     "the driver's own reader is the one the plants describe"))

    if verbose:
        print("PRESENCE CONTROL — planted in a throwaway tree, classified by the real reader")
        w = max(len(r[0]) for r in rows)
        for name, expect, actual, status, note in rows:
            print("  %-*s  expect %-28s got %-28s %-6s  %s" % (w, name, expect, actual, status, note))
        print("  control: %s" % ("ALL PLANTS FIRED" if ok else "DID NOT FIRE — the instrument has measured nothing"))
        print()
    return ok


# ------------------------------------------------------------------------------------------- driver

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=str(ROOT),
                    help="repository root directory (default: repo containing this script)")
    ap.add_argument("--rev", default="HEAD",
                    help="git revision to scan (default: HEAD)")
    ap.add_argument("--worktree", action="store_true",
                    help="scan working tree files on disk rather than committed git blobs")
    ap.add_argument("--control", action="store_true",
                    help="run only the presence control and exit")
    ap.add_argument("--skip-control", action="store_true",
                    help=argparse.SUPPRESS)  # used by the driver arm; a run of the driver arm
                                             # that ran the control would recurse forever
    ap.add_argument("--quiet", action="store_true", help="counts and verdict only")
    args = ap.parse_args()

    control_ok = True if args.skip_control else run_control()
    if args.control:
        return 0 if control_ok else 2
    if not control_ok:
        print("REFUSING TO REPORT: the presence control did not fire, so a zero here means nothing.")
        return 2

    root_path = pathlib.Path(args.root).resolve()
    files_data, dropped, undecodable, is_dirty, dirty_count = read_corpus(
        root=root_path, rev=args.rev, worktree=args.worktree)

    n1 = n2 = 0
    occurrences, line_occurrences, machine_files = [], [], []

    for path, raw in files_data.items():
        if MACHINE.search(raw):
            machine_files.append(path)
        if "/tmp/" not in raw and "/var/folders/" not in raw and "$TMPDIR/" not in raw:
            continue
        lhits = scan_lines(path, raw)
        n1 += len(lhits)
        line_occurrences.extend(lhits)
        hits = scan_file(path, raw)
        n2 += len(hits)
        occurrences.extend(hits)

    n3 = dedupe(occurrences)
    n4 = [h for h in n3 if file_kind(h["file"]) == "RECORD"]
    extensionless_in_records = len([h for h in n4 if not is_pointer(h["token"])])
    fenced_pointers = len([h for h in n4 if h["class"] == "SUBJECT" and is_pointer(h["token"])])
    n5 = [h for h in n4 if h["class"] in ("CITED", "WITHDRAWN")]
    blocking = [h for h in n5 if h["class"] in BLOCKING]

    tally = {c: 0 for c in CLASSES}
    for h in n3:
        tally[h["class"]] += 1

    live_host_count = sum(1 for h in blocking if exists_now(h["token"]))
    dead_host_count = len(blocking) - live_host_count

    # What the wrap-tolerant reader buys, WITH its denominator. The record used to say it buys
    # nothing on this corpus and give no denominator, which makes an unfalsifiable claim out of a
    # measurable one: nothing-out-of-nothing and nothing-out-of-345 read the same in prose.
    lines_by_key = {(h["file"], h["token"]): h["class"] for h in dedupe(line_occurrences)}
    collapsed_by_key = {(h["file"], h["token"]): h["class"] for h in n3}
    disagreements = [k for k in set(lines_by_key) | set(collapsed_by_key)
                     if lines_by_key.get(k) != collapsed_by_key.get(k)]

    corpus_desc = f"working tree disk ({len(files_data)} text files)" if args.worktree else f"committed tree at {args.rev} ({len(files_data)} text blobs)"

    print("COUNTS — five readings of one corpus, each answering a different question")
    print("  corpus scanned:                                       %s" % corpus_desc)
    if is_dirty:
        if args.worktree:
            print("  NOTICE: working tree has %d uncommitted change(s)    (scanned disk as requested)" % dirty_count)
        else:
            print("  note: working tree has %d uncommitted change(s)      (evaluating committed %s; pass --worktree to scan disk)" % (dirty_count, args.rev))
    print("  files this gate excludes from its own corpus         %5d   %s"
          % (len(dropped), ", ".join(dropped) if dropped else "none"))
    print("  N1  occurrences, line-anchored regex                 %5d" % n1)
    print("  N2  occurrences, wrap-tolerant reader                %5d" % n2)
    print("  N3  N2 deduplicated by (citing file, token)          %5d" % len(n3))
    print("  N4  N3 in hand-written records (.md, not generated)  %5d   in %d files"
          % (len(n4), len({h["file"] for h in n4})))
    print("  N5  N4 in a citing position — blocking-eligible      %5d   in %d files"
          % (len(n5), len({h["file"] for h in n5})))
    print()
    print("  files holding any scratch path                       %5d" % len({h["file"] for h in n3}))
    print("  hand-written record files holding one                %5d" % len({h["file"] for h in n4}))
    print("  files holding a machine-durable absolute path        %5d   (counted, never blocked)"
          % len(machine_files))
    print("  N4 tokens with no document extension                 %5d   (discriminator hole 1)"
          % extensionless_in_records)
    print("  N4 pointers read as SUBJECT (fence, redirect, …)     %5d   (discriminator hole 2)"
          % fenced_pointers)
    print("  rows the two readers class differently               %5d   of N3 %d — what the"
          % (len(disagreements), len(n3)))
    print("                                                               wrap-tolerant reader buys here")
    for k in sorted(disagreements)[:10]:
        print("      %s  %s  line-anchored %s · wrap-tolerant %s"
              % (k[0], k[1], lines_by_key.get(k, "—"), collapsed_by_key.get(k, "—")))
    if undecodable:
        expected = [x for x in undecodable if pathlib.Path(x[0]).suffix.lower() in BINARY_SUFFIX or x[1] in ("binary asset", "submodule")]
        surprising = [x for x in undecodable if x not in expected]
        print("  files this reader could not decode                   %5d   (%d binary/submodule assets, %d other)"
              % (len(undecodable), len(expected), len(surprising)))
        for pth, why in surprising:
            print("      %s (%s)" % (pth, why))
    print()

    print("CLASSES — a partition over N3; the starred one blocks")
    for c in CLASSES:
        print("  %-12s %5d%s" % (c, tally[c], "  *" if c in BLOCKING else ""))
    print()

    if not args.quiet and n5:
        print("EVERY CITING-POSITION SCRATCH PATH IN A HAND-WRITTEN RECORD")
        for h in sorted(n5, key=lambda x: (x["class"], x["file"], x["line"])):
            host_state = "live on host" if exists_now(h["token"]) else "dead on host"
            print("  %-11s %s:%d  %s  (%s)" % (h["class"], h["file"], h["line"], h["token"], host_state))
        print()

    if blocking:
        print("BLOCKED — %d citation%s of an artifact outside the repository (%d live on host, %d dead):"
              % (len(blocking), "" if len(blocking) == 1 else "s", live_host_count, dead_host_count))
        for h in sorted(blocking, key=lambda x: (x["file"], x["line"])):
            host_state = "live on host" if exists_now(h["token"]) else "dead on host"
            print("  %-11s %s:%d  %s  (%s)" % (h["class"], h["file"], h["line"], h["token"], host_state))
        print()
        print("Commit the artifact under planning/verification/ and cite the repo path, or keep the")
        print("path and mark it — `(gone)`, `(unrecoverable)`, `(not retained)`, `(reconstructed …)` —")
        print("so a reader can tell unrecoverable evidence from evidence never gathered.")
        return 1

    print("PASS — no hand-written record cites a scratch path without saying what became of it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
