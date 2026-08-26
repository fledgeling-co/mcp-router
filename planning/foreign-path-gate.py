#!/usr/bin/env python3
"""Find every scratch-directory path in the tracked corpus, and fail the ones that are citations.

## The defect this exists for

`G6`. An artifact a record cites as evidence lived in `/tmp`, and `/tmp` is emptied. Measured
2026-08-23, after a terminal died: `/tmp/g5gf3/sweep3.py`, `/tmp/g5gf2/sweep2.py`,
`/tmp/g5gf/sweep.py` and `/tmp/m18-build2.log` were all cited by durable records and all gone.

A sweep is the instrument that proves a guard is *armed* — that an assertion changes verdict under
input built to break it. `G5` gap-fix 2's accepted verdict rests entirely on one of those files:
four planted faults, four `FAIL` rows, plus three the verifier planted itself. The verdict was
sound when given and is now unfalsifiable.

**This is worse than a stale number.** A stale literal is wrong and *checkable* — run the thing,
compare, see the disagreement. A dead path produces no wrong answer to catch, only an absence, and
an absence reads identically to *not yet run*. A reader who cannot find the file cannot tell
whether the evidence was weak, strong, or never gathered.

The rule is not new; it was unenforced. `R17`'s equivalent sweep lives at `planning/claim-sweep.py`,
is committed, and survived the same crash. The two were written days apart to solve the same shape
of problem and only one is still evidence.

  an artifact a record cites as evidence is COMMITTED, or the record does not cite it.

## What this reads, and what it deliberately does not

**Scratch roots only**: `/tmp`, `/private/tmp`, `/var/folders`, `$TMPDIR`. Nothing durable ever
lives under one, so a path naming one is either a pointer with an expiry date nobody wrote down or
a value in a described system.

**Machine-durable absolute paths are counted and never blocked** — `/Users/…`, `~/…`,
`/Applications/…`. They are a different defect with a different remedy: a scratch path fails
because the artifact evaporates, a machine path fails because the reader is on another machine.
The count is printed under COUNTS so it cannot be forgotten, and folding it in would put a third,
uncoupled axis into an item whose argument is that its own two halves are coupled.

**`planning/citation-gate.py` is the sibling, not the parent.** It asks whether a `path:line`
pointer still resolves — anchor, line, tree. This asks whether the artifact behind a path survives
at all and sits inside the repository. A durable artifact with an imprecise pointer fails there; a
precise pointer to a dead artifact fails here. Neither implies the other, which is why there are
two files.

## The classes, and which of them block

Every scratch-path occurrence lands in exactly one class. The set is a partition, so nothing falls
out of the denominator:

  RUNTIME     the token is in an executable or a source file. A committed script that writes to
              `/tmp` is re-runnable, which is the property that was missing. Not a citation.
  GENERATED   the token is in a file a script regenerates. A stale path there is fixed by
              re-running its generator, not by a writer. Counted by name, never dropped in silence.
  SUBJECT     the token is in a hand-written record but is a VALUE in the described system — an
              env value (`HOME=/tmp/fakehome`), a config example (`cwd: "/tmp/project"`), a URL
              example (`file:///tmp/x`). Withdrawing these would be wrong: the record is describing
              behaviour, not pointing at an artifact.
  CITED_LIVE  an artifact pointer in a hand-written record, and the path exists on this machine
              right now. **Blocks.**
  CITED_DEAD  an artifact pointer in a hand-written record, and the path does not exist.
              **Blocks.**
  WITHDRAWN   an artifact pointer in a hand-written record, and the record says the artifact is
              gone, unrecoverable, reconstructed or recovered elsewhere. Does not block.

`CITED_LIVE` blocks for the same reason `CITED_DEAD` does. A live scratch path is one reboot from
being the other kind, and the gate that only fires after the file is gone fires after the evidence
is unrecoverable, which is the whole failure.

`WITHDRAWN` is what makes the rule satisfiable without deleting history. A record may keep a dead
path if it says so in a form a machine can read — which is exactly the distinction the defect
destroys, restored: *the evidence is unrecoverable* now reads differently from *the evidence was
never gathered*.

## Citation versus value — the discriminator, named

A scratch path is read as an artifact pointer when its last segment carries a document, log or
source extension, or when it ends in `/` (a directory citation). Otherwise it is a value.

Checked against the corpus this was written for: `/tmp/p4-before-root.txt`,
`/tmp/gate-R1-plan-{a,b}.stdout.txt`, `/tmp/g5gf/sweep.py` and `/tmp/mcp-router-setaside/` are
pointers; `/tmp/fakehome`, `/tmp/project` and `file:///tmp/x` are values. All seven land right.

**Two holes, printed rather than argued away.** A pointer at an extensionless artifact reads as a
value: `/tmp/m3-ax/axkit` names a built binary and this gate calls it `SUBJECT`. And a pointer at a
directory written without its trailing slash reads as a value too. Both are the safe direction for
a false negative to fall in only because the alternative — blocking every extensionless scratch
token — would red on `HOME=/tmp/fakehome`, which is not a defect. The count of extensionless
scratch tokens in records is printed on every run so the size of the hole is visible.

## The withdrawal marker, and why its window is strict

A marker is a delimited word, not a word: it must open with `(`, `|`, `*`, `**`, an em or en dash,
so that ordinary prose containing *deleted* does not silently satisfy the gate. False WITHDRAWN is
the dangerous direction — it is the gate passing when it should not — so the grammar is tight and
the misses are the visible kind.

The window runs from the end of the token to **the next scratch token or 200 characters, whichever
comes first**. That means two citations in one sentence need two markers; a single trailing *(both
gone)* satisfies only the second. This is deliberate strictness: a marker shared between pointers
is a marker whose subject a reader has to work out, and working it out is the labour the form
exists to remove.

Read on the collapsed view, so a marker the writer's editor wrapped onto the next line is still
adjacent here. The `--control` run proves that: its wrap plant must read `WITHDRAWN` under this
reader and `CITED_DEAD` under a line-anchored reading of the same fixture, and the run fails if the
two agree. A wrap-tolerant reader that would have answered the same either way has demonstrated
nothing.

## Nothing is planted in the real corpus

An absence sweep with no presence control is an instrument that has never been shown to fire; it
returns zero for the wrong reason and passes silently. So `--control` builds a throwaway git
repository in a temporary directory, plants one instance per class plus the wrap discriminator,
runs the real classifier over it, and requires each planted answer exactly. It runs on every
invocation and prints above the table rather than behind a flag.

## Counting

Five readings of "how many scratch paths" over one corpus, printed together and never blended,
because five sweeps over one phrase in one file once returned four different answers and none of
the first four was right. Each is a different question:

  N1  every occurrence, line-anchored regex — what a `grep` sees
  N2  every occurrence, wrap-tolerant — N1 plus the ones a wrap hid
  N3  N2 deduplicated by (citing file, token)
  N4  N3 in hand-written records only — `.md` that no script regenerates
  N5  N4 in a citing position — the blocking-eligible set

The gate's verdict reads N5. Every other figure is printed beside it so no number can be quoted
without its question.

## No ratchet, on purpose

`planning/citation-gate.py` ratchets because its corpus holds 1291 bare citations and a gate
demanding all of them at once either never goes green or gets softened until it means nothing. The
blocking set here is small enough to take to zero in one pass, so this is an absolute zero. A
ratchet whose baseline is zero is a worse gate than a threshold at zero, because it offers a
baseline bump as the way past a red.

Exit 0 when N5 holds no `CITED_LIVE` and no `CITED_DEAD`; exit 1 otherwise; exit 2 if the presence
control does not fire.
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

# A marker must be CLOSED. An earlier cut accepted any of `(`, `|`, `*`, `**` or a dash immediately
# before one of the words above, and the out-of-family review broke it three ways in one pass:
# `| recovered 40 items |` in a table cell, `* deleted the old cache` as the next bullet, and
# `the runner *recovered* state` in prose all satisfied it while withdrawing nothing. So the three
# accepted forms each have a closing side:
#
#   (gone)  (not retained, and the glob now resolves to unrelated files)   parenthesised
#   | gone |                                                              a cell that is ONLY the marker
#   **gone**                                                              bold, closed
#
# Everything else is not a marker, which is the safe direction: a missed marker reds a gate and a
# false one passes a dead citation.
WITHDRAW = re.compile(
    r"\((?:%s)\b[^)]{0,400}\)"          # parenthesised, optionally with an explanation
    r"|\|\s*(?:%s)\b\s*\|"              # a table cell holding only the marker
    r"|\*\*(?:%s)\b[^*]{0,80}\*\*"      # bold and closed
    % (_W, _W, _W), re.I)

WINDOW = 200

# A redirection target is a sink the quoted command CREATES, not an artifact the record points at.
# `cmd > /tmp/f.txt 2>&1; echo $?` is a record teaching how to capture an exit code, and
# `codex exec … -o /tmp/probe.md` is a record quoting an invocation; neither is evidence being
# cited. Read immediately before the token on the collapsed view, so the operator has to be
# attached to it rather than merely nearby.
REDIRECT = re.compile(r"(?:\d?>>?&?\d?|\|\s*tee(?:\s+-a)?|-o|--output(?:=|\s)|--out)\s*$")

# A segment written `...` is an elision — `/tmp/.../manifest.json` names a shape, not a path. It
# cannot be resolved, so it cannot be a citation, and demanding a withdrawal marker for it would be
# demanding one for a sentence.
ELLIPSIS = re.compile(r"(?:^|/)\.{3}(?:/|$)")

# An equality or a mapping arrow makes the token the VALUE being asserted, not an artifact being
# pointed at: `HOME=/tmp/x` → `claudeJSON == /tmp/x/.claude.json` is a test expectation.
# Narrowed to a real equality after the out-of-family review: `->` and `→` are how this corpus
# writes "and then", so `Results -> /tmp/sweep.py` is a citation, not an assertion.
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

# This file quotes every class name and a dozen example paths in order to explain them, so it would
# otherwise be its own largest source of hits — `claim-sweep.py`'s excluded-records problem, one
# layer along. Listed by name and not scanned, which is what keeps the output a fixed point under
# being explained.
SELF = ("planning/foreign-path-gate.py",)

# Undecodable and expected to be: counted in the total, not enumerated.
BINARY_SUFFIX = frozenset(
    ".png .jpg .jpeg .webp .gif .ico .icns .pdf .zip .tar .gz .woff .woff2 .ttf .otf "
    ".mp4 .mov .car .dat .bin .sqlite".split())

CLASSES = ("RUNTIME", "GENERATED", "SUBJECT", "CITED_LIVE", "CITED_DEAD", "WITHDRAWN")
BLOCKING = ("CITED_LIVE", "CITED_DEAD")

# Used when one (file, token) occurs several times in different positions. The worst reading wins,
# so a citation cannot be excused by a safer sibling elsewhere in the same file.
SEVERITY = {"RUNTIME": 0, "GENERATED": 0, "SUBJECT": 1, "WITHDRAWN": 2, "CITED_LIVE": 3, "CITED_DEAD": 4}


# ------------------------------------------------------------------------ the wrap-tolerant reader

def quote_marker_offsets(raw):
    """Offsets of blockquote markers opening a line. A `>` separates two words exactly as a wrap
    does; `claim-sweep.py` measured that after missing a claim quoted inside a blockquote."""
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


# ------------------------------------------------------------------------------ the classification

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
    """Does the cited path resolve on this machine? Brace groups widen to a glob."""
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
    return "CITED_LIVE" if exists_now(tok) else "CITED_DEAD"


# ------------------------------------------------------------------------------------ the two reads

def fenced_spans(raw):
    """Character ranges of ``` fenced blocks. A scratch path inside one is a quoted command or a
    pasted transcript — the same shape the REDIRECT rule recognises, one level out. A record that
    shows `$ swift /tmp/v1-trap.swift` is demonstrating an invocation, and demanding a withdrawal
    marker there would put prose inside a command line."""
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
        hits = [(m.start("path"), trim(m.group("path"))) for m in SCRATCH.finditer(line)]
        for idx, (start, tok) in enumerate(hits):
            if not tok:
                continue
            end = start + len(tok)
            limit = hits[idx + 1][0] if idx + 1 < len(hits) else len(line)
            tail = line[end:min(limit, end + WINDOW)]
            head = line[max(0, start - 40):start]
            cls = "SUBJECT" if in_span(fences, base + start) else classify(path, tok, head, tail)
            out.append({"file": path, "token": tok, "line": n, "class": cls})
    return out


# ------------------------------------------------------------------------------- the presence control

CONTROL_PLANTS = [
    # (filename, body, expected class, note)
    ("runtime.sh",
     "#!/bin/sh\nLOG=/tmp/control-runtime.log\necho hi > \"$LOG\"\n",
     "RUNTIME", "a committed script writing to /tmp"),
    ("subject.md",
     "Measured under `HOME=/tmp/fakehome`, node's `os.homedir()` returns that value.\n",
     "SUBJECT", "a scratch path as a value in the described system"),
    ("dead.md",
     "The sweep is at `/tmp/control-definitely-absent-9f3a/sweep.py` and decides the item.\n",
     "CITED_DEAD", "a pointer at an artifact that does not exist"),
    ("withdrawn.md",
     "The sweep was at `/tmp/control-definitely-absent-9f3a/sweep2.py` (gone) and is not re-runnable.\n",
     "WITHDRAWN", "a pointer the record marks gone"),
    ("redirect.md",
     "Each gate captured as `make test > /tmp/control-definitely-absent-9f3a/f.txt 2>&1; echo $?`.\n",
     "SUBJECT", "a redirect target inside a quoted command is a sink, not a citation"),
    ("ellipsis.md",
     "The run printed `0 tools cached -> /tmp/.../manifest.json`, which names a shape.\n",
     "SUBJECT", "an elided segment cannot be resolved, so it cannot be a citation"),
    ("fenced.md",
     "The trap was reproduced:\n\n```\n$ swift /tmp/control-definitely-absent-9f3a/trap.swift\n```\n",
     "SUBJECT", "a transcript inside a fence is an invocation, not a citation"),
    # Negative controls. Each holds a dead citation followed by prose that an earlier, looser marker
    # grammar accepted as a withdrawal. They must all still block; a gate that passes these is a gate
    # that can be satisfied by a table cell and a bullet point.
    ("neg-table.md",
     "| `/tmp/control-definitely-absent-9f3a/a.log` | the run | recovered 40 items |\n",
     "CITED_DEAD", "NEGATIVE: a cell saying `recovered 40 items` withdraws nothing"),
    ("neg-bullet.md",
     "- The log is `/tmp/control-definitely-absent-9f3a/b.log`\n* deleted the old cache first\n",
     "CITED_DEAD", "NEGATIVE: the next bullet is not a marker"),
    ("neg-emphasis.md",
     "The log at `/tmp/control-definitely-absent-9f3a/c.log` — the runner *recovered* state cleanly.\n",
     "CITED_DEAD", "NEGATIVE: an emphasised verb in prose is not a marker"),
    ("asserted.md",
     "| `homeComesFromTheEnvironment` | `HOME=/tmp/x` -> `claudeJSON == /tmp/control-definitely-absent-9f3a/.claude.json` |\n",
     "SUBJECT", "a token after an equality is the value asserted, not an artifact"),
]

# The discriminating plant. Its marker sits on the line AFTER its citation, so a line-anchored
# reader cannot see the two together. It must read WITHDRAWN collapsed and CITED_DEAD line-anchored,
# and the control fails if those agree.
CONTROL_WRAP = (
    "wrapped.md",
    "The instrument recorded in gap-fix 2 lived at `/tmp/control-definitely-absent-9f3a/sweep3.py`\n"
    "(gone), so the verdict that rests on it is no longer falsifiable.\n",
    "WITHDRAWN", "CITED_DEAD")


def dedupe(occurrences):
    """One row per (citing file, token), keeping the MOST SEVERE class rather than the first seen.

    First-wins was a hole the out-of-family review found, and it is this gate's own failure shape: a
    path quoted once inside a fence and again, unmarked, in prose would be filed as SUBJECT and the
    prose citation dropped before the verdict — green while the defect is present."""
    best = {}
    for h in occurrences:
        key = (h["file"], h["token"])
        cur = best.get(key)
        if cur is None or SEVERITY[h["class"]] > SEVERITY[cur["class"]]:
            best[key] = h
    return list(best.values())


def run_control(verbose=True):
    """Plant one instance per class in a throwaway repo and require each planted answer exactly."""
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

        # CITED_LIVE, end to end rather than through `exists_now` alone: a real file, cited by a
        # record, must reach the blocking class the gate fires on BEFORE a crash rather than after.
        live = d / "live-artifact.log"
        live.write_text("planted\n")
        body = "The gate log is at `%s` and decides the item.\n" % live
        got = scan_collapsed("live.md", body)
        actual = got[0]["class"] if got else "NO-HIT"
        # The planted file is under the OS temp root, which is what SCRATCH matches on macOS.
        expect = "CITED_LIVE" if str(live).startswith(("/tmp/", "/private/tmp/", "/var/folders/")) else actual
        good = actual == expect == "CITED_LIVE"
        ok &= good
        rows.append(("live-artifact.log", "CITED_LIVE", actual, "fired" if good else "MISSED",
                     "a live scratch citation blocks too — it is one reboot from the other kind"))

        # The severity-preserving dedup, exercised through the function the run uses.
        mixed = [{"file": "x.md", "token": "/tmp/t.py", "class": "SUBJECT"},
                 {"file": "x.md", "token": "/tmp/t.py", "class": "CITED_DEAD"}]
        d_ok = len(dedupe(mixed)) == 1 and dedupe(mixed)[0]["class"] == "CITED_DEAD"
        ok &= d_ok
        rows.append(("(dedupe) SUBJECT then CITED_DEAD", "CITED_DEAD",
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

        # A generated file and a self-excluded file are corpus decisions rather than classifier
        # decisions, so they are exercised through the same predicates the run uses.
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
                     "the LIVE/DEAD split reads the filesystem"))

    if verbose:
        print("PRESENCE CONTROL — planted in a throwaway tree, classified by the real reader")
        w = max(len(r[0]) for r in rows)
        for name, expect, actual, status, note in rows:
            print("  %-*s  expect %-22s got %-22s %-6s  %s" % (w, name, expect, actual, status, note))
        print("  control: %s" % ("ALL PLANTS FIRED" if ok else "DID NOT FIRE — the instrument has measured nothing"))
        print()
    return ok


# ---------------------------------------------------------------------------------------- the corpus

def tracked_files():
    out = subprocess.run(["git", "-C", str(ROOT), "ls-files"],
                         capture_output=True, text=True, check=True).stdout
    return [p for p in out.splitlines() if p and p not in SELF]


def read(path):
    try:
        return (ROOT / path).read_text(encoding="utf-8"), None
    except FileNotFoundError:
        return None, "missing"
    except IsADirectoryError:
        # A gitlink. `git ls-files` lists a submodule as one path and it is a directory here; the
        # plugin submodule is uninitialised on purpose in every worktree of this repo.
        return None, "submodule"
    except UnicodeDecodeError:
        return None, "undecodable"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--control", action="store_true",
                    help="run only the presence control and exit")
    ap.add_argument("--quiet", action="store_true", help="counts and verdict only")
    args = ap.parse_args()

    control_ok = run_control()
    if args.control:
        return 0 if control_ok else 2
    if not control_ok:
        print("REFUSING TO REPORT: the presence control did not fire, so a zero here means nothing.")
        return 2

    files = tracked_files()
    n1 = n2 = 0
    occurrences, undecodable, machine_files = [], [], []

    for path in files:
        raw, err = read(path)
        if raw is None:
            undecodable.append((path, err))
            continue
        if MACHINE.search(raw):
            machine_files.append(path)
        if "/tmp/" not in raw and "/var/folders/" not in raw and "$TMPDIR/" not in raw:
            continue
        n1 += len(scan_lines(path, raw))
        hits = scan_collapsed(path, raw)
        n2 += len(hits)
        occurrences.extend(hits)

    # Deduplicate by keeping the MOST SEVERE class for a (file, token), never the first seen.
    # First-wins is a hole the out-of-family review found and it is the exact shape this gate exists
    # to prevent: a path quoted once inside a fence and again, unmarked, in prose would be recorded
    # as SUBJECT and the prose citation dropped before the verdict — green while the defect is
    # present. Planted as `severity.md` in the control.
    n3 = dedupe(occurrences)

    n4 = [h for h in n3 if file_kind(h["file"]) == "RECORD"]
    # Both holes stated on the same denominator as the classes, N3, so neither can be quoted against
    # a different question than the table above it.
    extensionless_in_records = len([h for h in n4 if not is_pointer(h["token"])])
    fenced_pointers = len([h for h in n4 if h["class"] == "SUBJECT" and is_pointer(h["token"])])
    n5 = [h for h in n4 if h["class"] in ("CITED_LIVE", "CITED_DEAD", "WITHDRAWN")]
    blocking = [h for h in n5 if h["class"] in BLOCKING]

    tally = {c: 0 for c in CLASSES}
    for h in n3:
        tally[h["class"]] += 1

    print("COUNTS — five readings of one corpus, each answering a different question")
    print("  files scanned (git ls-files, minus this file)        %5d" % len(files))
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
    if undecodable:
        # Binary assets are expected to be undecodable and are counted, not listed — a wall of PNG
        # names buries the one entry that would mean something. Anything else is named.
        expected = [x for x in undecodable if pathlib.Path(x[0]).suffix.lower() in BINARY_SUFFIX]
        surprising = [x for x in undecodable if x not in expected]
        print("  files this reader could not decode                   %5d   (%d binary assets, %d other)"
              % (len(undecodable), len(expected), len(surprising)))
        for pth, why in surprising:
            print("      %s (%s)" % (pth, why))
    print()

    print("CLASSES — a partition over N3; the two starred ones block")
    for c in CLASSES:
        print("  %-12s %5d%s" % (c, tally[c], "  *" if c in BLOCKING else ""))
    print()

    if not args.quiet and n5:
        print("EVERY CITING-POSITION SCRATCH PATH IN A HAND-WRITTEN RECORD")
        for h in sorted(n5, key=lambda x: (x["class"], x["file"], x["line"])):
            print("  %-11s %s:%d  %s" % (h["class"], h["file"], h["line"], h["token"]))
        print()

    if blocking:
        print("BLOCKED — %d citation%s of an artifact outside the repository:"
              % (len(blocking), "" if len(blocking) == 1 else "s"))
        for h in sorted(blocking, key=lambda x: (x["file"], x["line"])):
            print("  %-11s %s:%d  %s" % (h["class"], h["file"], h["line"], h["token"]))
        print()
        print("Commit the artifact under planning/verification/ and cite the repo path, or keep the")
        print("path and mark it — `(gone)`, `(unrecoverable)`, `(reconstructed …)`, `(recovered …)` —")
        print("so a reader can tell unrecoverable evidence from evidence never gathered.")
        return 1

    print("PASS — no hand-written record cites a scratch path without saying what became of it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
