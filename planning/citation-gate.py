#!/usr/bin/env python3
"""Read every `path:line` citation in the tracked corpus, and check the ones that can be checked.

## The defect this exists for

`G7`. A citation resolves where it is *written* and not where it is *read*. Gap-fix 3's verdict
cites its blocker as `G5.md:159`, correct at `a9603e5`; at `0e5ff49` that line reads *"M28 docket
and the X7 brief all name"* — unrelated prose, and the sentence the citation was for is not in the
file at all any more. **A citation into nothing announces itself; a citation onto plausible text is
believed**, which is why the count of bare citations matters more than the count of dangling ones.

## The form, and why three coordinates

Settled by `M16`, 2026-08-23:

  ANCHOR  the phrase relied on   survives a line shift        NOT a re-wrap
  LINE    the number             survives a re-wrap           NOT a shift
  TREE    a commit SHA           is what makes either checkable at all

Three coordinates for three distinct failure modes. Any two leave a hole the third closes, so this
reads all three and says which one a citation is missing.

## The classes, and which of them block

Every citation lands in exactly one class — the set is a partition, so nothing falls out of the
denominator:

  RESOLVES    tree + anchor, and the anchor is at the cited line at the cited tree.
  DRIFTED     tree + anchor, anchor is in the file at that tree but NOT at the cited line.
  ABSENT      tree + anchor, anchor is not in the file at that tree at all.
  NOTREE      a tree was named and git does not know it, or the file is not in it.
  TREE_ONLY   a tree, no anchor. Only "the line exists at that tree" is checkable.
  ANCHOR_ONLY an anchor, no tree. Checked against HEAD, which is a moving frame.
  BARE        neither. **Unfalsifiable** — the class this item is about.

`DRIFTED` and `ABSENT` block, and only they. They are the citations that *invite* a check and then
fail it, which is a false claim rather than a missing one. `BARE` cannot block, because it cannot
fail: there is nothing to compare. It is ratcheted instead — see below.

Blocking on a *stated* frame is what keeps the form honest. Renumbering to the current revision —
the fix this item forbids — earns nothing here, because a number with no tree and no anchor stays
`BARE` however recently it was chased.

## Why BARE is ratcheted and not blocked

The corpus carries thousands of bare citations, written before the form existed. A gate that
demands they all be framed at once either never goes green or gets softened until it means nothing.
So the bare count in the hand-written scope is held against a tracked baseline in
`planning/citation-ratchet.json` and may only fall. Regenerate it with `--write-ratchet` after a
sweep, and the diff shows the number moving in the direction the discipline requires.

**The ratchet is per citing file, not a total.** A scalar count lets a deletion or a refactor in
one file buy headroom for a brand-new bare citation in another, so the defect spreads while the
number holds. Demonstrated by planting: one bare citation added to a file whose baseline is 0 and
one existing citation framed elsewhere leaves the total at 1291 against a baseline of 1291, which
a scalar ratchet passes and this one exits 1 on. Raised by the out-of-family review, 2026-08-25.

The hole this leaves is printed rather than argued away. A frame the adjacency grammar cannot
follow lands in `BARE` rather than in an error class, so an `M16`-form citation written with an
unrecognised connective drops past the `DRIFTED`/`ABSENT` check silently. Every run prints how many
`BARE` citations sit within reach of a SHA-shaped token, which is the visible size of that hole.

## The reader, and why it reads whole files

`planning/claim-sweep.py`'s finding, restated: a line-anchored reader cannot see a claim a text
editor wrapped, and every claim in this repo lives in a wrapped markdown file. So both halves of
this script read whole files and collapse every run of whitespace — newlines included — to a single
space: the half that *finds* citations (a citation and its frame routinely straddle a wrap), and
the half that *checks* an anchor at a target line. Blockquote markers opening a line collapse with
the whitespace, for the reason `claim-sweep.py` gives.

Mapping an anchor's hit back to a line number is what makes the wrap-tolerant reader answer a
line-anchored question: the anchor is found in the collapsed view, and its offset is mapped back
to the line of its *first* character in the original.

## The control, and why it is hermetic

`G4`'s seventeenth item: a wrap control **quoted, unwrapped, inside the document it guards** is
found by the naive matcher instead of the wrapped instance, and the control then passes for the
wrong reason and passes silently. So nothing is planted in this corpus. `--control` builds a
throwaway git repository in a temp directory with two commits and twelve planted citations, one per
answer, runs the real classifier over it, and requires each planted answer exactly. The printed
count is `len(rows)`, so it cannot drift from what was actually planted.

Two of the twelve are the ones that matter. The **wrap** row plants an anchor that is hard-wrapped
across a newline at its target: it must classify `RESOLVES` here **and** `ABSENT` under a
line-anchored reading of the same fixture, and the run fails if those two agree — a wrap-tolerant
reader that would have answered the same either way has demonstrated nothing. The **plausible**
row plants a citation whose cited line at the newer tree holds *different, plausible* text: it must
classify `DRIFTED` rather than `ABSENT`, which is the distinction the whole item turns on.

Those twelve are all one unwrapped line each, so they say nothing about the **citing** side of a
wrap. Two further checks run beside them, and they are what the N1/N2 identity below rests on:

  * a wrapped citation **token** (`a.md:` / `2` across a newline) must be found by *neither*
    reader. `normalise` replaces a whitespace run with a single space and `CITATION` admits no
    space, so a split token is `a.md: 2` in the collapsed view and matches nothing. The unwrapped
    form of the same string must be found, or the check proves nothing about wrapping.
  * a wrapped **frame** — the anchor on the line above its citation — must classify `RESOLVES`
    read whole and something else read a line at a time. That is the citing-side wrap this half
    actually buys, and it is why the reader takes whole files.

The control runs on every invocation and prints above the table rather than behind a flag.

## Counting

Five readings of "how many citations" over one corpus, printed together and never blended, because
five sweeps over one phrase in one file once returned four different answers and none of the first
four was right. Each is a different question:

  N1  every occurrence, line-anchored regex — what a `grep` sees
  N2  every occurrence, read from the whole file collapsed — the same tokens, by construction
  N3  N2 deduplicated by (citing file, cited path, cited line, frame)
  N4  N3 with generated and frozen files excluded — a generated one is regenerated rather
      than maintained, and a frozen one is a preserved copy that must not be edited at all
  N5  N4 whose cited path resolves to a tracked file — the checkable set

The ratchet reads N5's `BARE` count. Every other figure is printed beside it so no number can be
quoted without its question.
"""

import fnmatch
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve()
ROOT = HERE.parent.parent
RATCHET = ROOT / "planning" / "citation-ratchet.json"

# A citation needs a file extension to be one. Without it `127.0.0.1:8879` and `12:30` are
# citations, and the corpus has both.
EXTS = ("md", "py", "swift", "ts", "tsx", "js", "mjs", "json", "sh", "zsh", "yml", "yaml",
        "html", "css", "tsv", "txt", "plist", "toml")

CITATION = re.compile(
    r"(?<![A-Za-z0-9_./-])((?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.(?:%s)):(\d+)(?:-(\d+))?"
    % "|".join(EXTS))

# A bare `:159` continuing a path named earlier in the sentence. Counted, never resolved: the
# path it continues is a matter of reading, not of parsing.
BARE_LINE = re.compile(r"(?<![A-Za-z0-9_./:-])`:(\d+)(?:-(\d+))?`")

# The frame is recognised by ADJACENCY, not by proximity. A first cut took every backticked span
# within a few hundred characters of a citation as a candidate anchor; over this corpus that made
# 1163 citations look anchored, blocked 54 of them, and several of the blocks were the reader
# picking up an unrelated phrase from the same sentence — an instrument that reports a number
# without measuring anything. So the frame must sit immediately against the citation, with only a
# connective between, in one of the two spellings this repo actually writes.
#
#   anchor first, the common one:  `StaleReadingBanner(error: staleError)`, `CleanupBoard.swift:95` at `0f5f118`
#                                  (anchor `.disabled(board.state.reading == nil)`, `CleanupBoard.swift:179` at `0f5f118`)
#   citation first:                `RUN-2026-08-20.md:589` records *"58 of 76 (76%)"* at `cef3729`
#
# Read on the collapsed view, so a frame the writer's editor wrapped is still one token here.
#
# The cost of the tight reading is named rather than hidden: a citation whose anchor sits two
# clauses away is read as unanchored. That is the right way round — a frame a machine cannot parse
# is a frame a reader has to reconstruct, and reconstructing it is the work the form exists to
# remove.

QUOTE = r"(?:`(?P<%s>[^`]{4,200})`|[\"\u201c](?P<%s>[^\"\u201d]{4,200})[\"\u201d])"

# An anchor ending right where the citation begins.
ANCHOR_BEFORE = re.compile(
    r"(?:\(|\b(?:anchor|anchors|the phrase|quoting|reads|read|records|says)\s+)?\*{0,2}"
    + (QUOTE % ("b1", "b2")) +
    r"\*{0,2}\s*[,;—–-]?\s*(?:at\s+)?$")

# A tree stated immediately after the citation.
# The closing backtick must be consumed with the SHA, not left for the next reader: a trailing
# `` `? `` followed by `\b` backtracks off it, and the stranded tick then opens a span that eats
# the anchor behind it.
TREE_AFTER = re.compile(r"^\s*[,;—–-]?\s*(?:at|@|as of|in|on)\s+"
                        r"(?:`(?P<sha>[0-9a-f]{7,40})`|(?P<sha2>[0-9a-f]{7,40})\b)")

# An anchor stated immediately after the citation (optionally after the tree).
ANCHOR_AFTER = re.compile(
    r"^\s*[,;—–:-]?\s*"
    r"(?:reads?|records?|says?|carries|carrying|naming|names|quoting|is|the phrase)?\s*"
    r"[—–:-]?\s*\*{0,2}" + (QUOTE % ("a1", "a2")) + r"\*{0,2}")

SHA_SHAPED = re.compile(r"`([0-9a-f]{7,40})`")

# An anchor shorter than this matches too much to be evidence of anything.
MIN_ANCHOR = 8

# Regenerated by a script rather than maintained by a writer: a stale citation in one of these is
# fixed by re-running its generator, not by a writer carrying a frame. Excluded from N4 by name
# and counted, never dropped in silence.
GENERATED = (
    "planning/fidelity/*.tsv",
    "planning/fidelity/*.ledger.md",
    "planning/reckoning/*/*.json",
    # `planning/tailings*/*.json`, not `planning/tailings/*.json`: the same skill has now run
    # three times over three commit windows and written `tailings/`, `tailings-2/` and
    # `tailings-3/`. All three carry schema 1 and the identical machine-written probe title —
    # `"function body is empty: <path>:<line>"` — so the first run's exclusion and the second's
    # inclusion were the same artifact answered two ways because the glob named a directory
    # instead of a generator. Measured 2026-08-27: `tailings-2/` put 7 bare citations over the
    # ratchet across two files, every one of them a probe title of that form.
    "planning/tailings*/*.json",
    "planning/test-campaign/*.json",
    "planning/test-campaign/evidence/*.json",
    "planning/test-campaign/evidence/*/*.json",
    # The campaign's run logs, tracked from `G24` onward. They are written by `bin/arm-*.py`,
    # `bin/wire-document.py` and the capture shells, and they quote source locations the way a
    # compiler and a test runner do — `DocumentPackage.swift:214`. Measured when the 45 logs were
    # first staged: 16 of them carry 32 such tokens between them, every one BARE, which took the
    # ratchet's over-baseline set from 14 files to 30 without a writer having typed a citation.
    # They belong in this tuple by its own definition — a stale one is fixed by re-running the
    # generator, never by a writer carrying an anchor and a tree.
    "planning/test-campaign/evidence/*.log",
    "planning/test-campaign/evidence/*/*.log",
    "planning/reader-accounting.tsv",
    "planning/parity/*.tsv",
    "planning/status/*.json",
    # The campaign's evidence page, built by
    # `vendor/test-campaign/skills/test-campaign/scripts/evidence-page.py` from
    # `campaign.json`, `inventory.json`, `cases.json` and `evidence/`. Every citation in it is
    # a verbatim copy of a `why` or a `note` string in those registries, which the two globs
    # above already exclude — so the page and its source were being answered two different
    # ways for the same 18 strings. Proved by regenerating it 2026-08-27: the fresh page
    # carries the same 18 bare citations, one for one, so a hand-edit here buys nothing that
    # survives the next run of the generator. That is the decisive half — a per-file counter
    # on this artifact can only be satisfied by editing a file that is overwritten, which is
    # the wrong fix taught by a green gate. The right fix is in the registry and this gate
    # cannot see it: the campaign registries are unguarded for bare citations, and naming
    # that hole is the cost of this line.
    "planning/test-campaign/evidence.html",
)

# Not regenerated — *frozen*, which is a different reason for the same exclusion and so gets
# its own name rather than being folded into GENERATED.
#
# `planning/rescue/campaign-stash-20260827/` is a byte-copy of a campaign registry taken from a
# git stash that had been dropped, committed at `cb1d7de` so five cases could not be lost a
# second time. It makes no claim a reader follows — the live registry at
# `planning/test-campaign/cases.json` does, and it is excluded above as generated. And the
# exclusion is not a convenience: a rescue copy is evidence *because* it is identical to what
# it rescued, so framing a citation inside one would destroy the only property it has. There
# is no edit to this file that both satisfies the ratchet and leaves it a rescue.
FROZEN = (
    "planning/rescue/*/*.json",
)

# This file quotes every class name and several example citations in order to explain them, so it
# would otherwise be its own largest source of hits — `claim-sweep.py`'s excluded-records problem,
# one layer along. Listed by name and not scanned, which is what keeps the output a fixed point.
SELF = ("planning/citation-gate.py", "planning/citation-ratchet.json")

CLASSES = ("RESOLVES", "DRIFTED", "ABSENT", "NOTREE", "TREE_ONLY", "ANCHOR_ONLY", "BARE")
BLOCKING = ("DRIFTED", "ABSENT")


# ---------------------------------------------------------------- the wrap-tolerant reader

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

    def blank(k):
        return raw[k].isspace() or k in marks

    chars, offsets, i, n = [], [], 0, len(raw)
    while i < n:
        if blank(i):
            chars.append(" ")
            offsets.append(i)
            while i < n and blank(i):
                i += 1
        else:
            chars.append(raw[i])
            offsets.append(i)
            i += 1
    return "".join(chars), offsets


def line_of(raw, offsets, pos):
    return raw.count("\n", 0, offsets[pos]) + 1


def collapse(s):
    return re.sub(r"\s+", " ", s).strip()


# ---------------------------------------------------------------- git, cached

class Tree:
    def __init__(self, root):
        self.root = str(root)
        self._commits = {}
        self._blobs = {}

    def known(self, sha):
        if sha not in self._commits:
            r = subprocess.run(["git", "-C", self.root, "cat-file", "-t", sha],
                               capture_output=True)
            self._commits[sha] = (r.returncode == 0 and r.stdout.decode().strip() == "commit")
        return self._commits[sha]

    def blob(self, sha, path):
        key = (sha, path)
        if key not in self._blobs:
            r = subprocess.run(["git", "-C", self.root, "show", "%s:%s" % (sha, path)],
                               capture_output=True)
            self._blobs[key] = r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None
        return self._blobs[key]


def anchor_lines(text, anchor):
    """Lines of `text` where `anchor` starts, read wrap-tolerantly. [] when it is not there."""
    norm, offsets = normalise(text)
    needle = collapse(anchor)
    if not needle:
        return []
    return [line_of(text, offsets, m.start())
            for m in re.finditer(re.escape(needle), norm, re.I)]


def anchor_lines_line_anchored(text, anchor):
    """The same question asked by a reader that cannot see across a wrap. Used only by the control,
    to prove the wrap-tolerant reader answers differently on a wrapped anchor."""
    needle = collapse(anchor)
    return [i + 1 for i, ln in enumerate(text.split("\n")) if needle.lower() in ln.lower()]


# ---------------------------------------------------------------- extraction and classification

def _q(m, *names):
    for n in names:
        if m.group(n):
            return m.group(n)
    return None


def read_frame(cit):
    """The tree and anchor stated against this citation, or None for each that is not.

    Tries both spellings and both suffix orderings. Nothing is inferred from mere proximity."""
    anchor = tree = None

    m = ANCHOR_BEFORE.search(cit["prefix"])
    if m:
        anchor = _q(m, "b1", "b2")

    rest = cit["suffix"]
    for _ in range(2):
        if tree is None:
            m = TREE_AFTER.match(rest)
            if m:
                tree = m.group("sha") or m.group("sha2")
                # `X.md:159 at a9603e5` writes the whole frame inside ONE span, so consuming the
                # tree leaves the span's closing tick at the head of `rest`, where it opens a new
                # span that swallows the rest of the clause as an anchor. That read the G7 brief's
                # own sentence as an anchor and blocked on it.
                rest = _trim_tick(rest[m.end():], False)
                continue
        if anchor is None:
            m = ANCHOR_AFTER.match(rest)
            if m:
                cand = _q(m, "a1", "a2")
                # A pointer is not an anchor, and neither is the tree restated.
                if cand and not CITATION.search(cand) and not re.fullmatch(r"[0-9a-f]{7,40}", cand):
                    anchor = cand
                    rest = rest[m.end():]
                    continue
        break

    if anchor is not None:
        if len(anchor) < MIN_ANCHOR or CITATION.search(anchor):
            anchor = None
        elif re.fullmatch(r"[0-9a-f]{7,40}", anchor):
            anchor = None
    return tree, anchor


def _trim_tick(s, is_prefix):
    if is_prefix:
        return s[:-1] if s.endswith("`") else s
    return s[1:] if s.startswith("`") else s


def citations_in(text):
    """Every citation in one file's collapsed view, with its window.

    **What the collapsed view buys, and what it does not.** It does not recover a citation the wrap
    split: `normalise` turns a whitespace run into a single space and `CITATION` admits no space, so
    a token broken across a newline reads `a.md: 2` here and is invisible to this reader exactly as
    it is to a line-anchored one. That is why N1 and N2 are equal by construction rather than as a
    finding about the corpus.

    What it buys is the **window**. `prefix` and `suffix` are taken from the collapsed text, so an
    anchor phrase or a tree sha that a wrap separated from its citation is adjacent to it here and
    is read as its frame. A line-anchored reader would call the same citation `BARE`. Both halves
    of this are planted in `control()`."""
    norm, offsets = normalise(text)
    found = []
    for m in CITATION.finditer(norm):
        path, a, b = m.group(1), int(m.group(2)), m.group(3)
        found.append({
            "path": path, "line": a, "end": int(b) if b else a,
            "at": line_of(text, offsets, m.start()),
            # A citation is nearly always written inside backticks, and those delimiters belong to
            # the citation rather than to its frame. Left in, the closing one opens a span that
            # swallows the connective and the tree — `RUN-2026-08-20.md:589` read its own anchor as
            # " records *…* at " on the first run.
            "prefix": _trim_tick(norm[max(0, m.start() - 240): m.start()], True),
            "suffix": _trim_tick(norm[m.end(): m.end() + 240], False),
            "token": m.group(0),
        })
    bare = len(BARE_LINE.findall(norm))
    return found, bare


def resolve_path(path, tracked, by_base):
    if path in tracked:
        return path, "exact"
    hits = by_base.get(os.path.basename(path), [])
    if len(hits) == 1:
        return hits[0], "basename"
    if len(hits) > 1:
        return None, "ambiguous"
    return None, "untracked"


def line_text(text, n):
    lines = text.split("\n")
    return lines[n - 1] if 0 < n <= len(lines) else None


def announces_itself(text, cit):
    """Whether a failed citation would be *noticed*. `M16`: a citation into nothing announces
    itself; a citation onto a line that reads plausibly is believed. So the two are reported apart
    — the second is the dangerous variety and the reason this gate is worth its exit code."""
    t = line_text(text, cit["line"])
    if t is None:
        return True, "past EOF"
    if not t.strip():
        return True, "blank line"
    return False, collapse(t)[:70]


def classify(cit, tree, resolved):
    """Exactly one class, plus the evidence the class rests on."""
    sha, anchor = read_frame(cit)

    if sha is not None and not tree.known(sha):
        # A frame naming a tree git does not know claims checkability and has none. Kept out of the
        # blocking set: the repo carries short SHAs from branches that were rebased away, and a
        # gate cannot tell that from a typo.
        return "NOTREE", sha, (anchor[:60] if anchor else None)
    if sha is None and anchor is None:
        # A frame the grammar could not follow lands here rather than in an error class, so an
        # M16-form citation written with an unrecognised connective drops silently past the
        # DRIFTED/ABSENT check. It cannot be classified — there is nothing parsed to check — but it
        # can be made visible: a SHA-shaped token inside the window says a frame was probably
        # intended. Raised by the out-of-family review, 2026-08-25.
        near = bool(SHA_SHAPED.search(cit["prefix"]) or SHA_SHAPED.search(cit["suffix"]))
        return "BARE", None, ("near-miss: a SHA-shaped token is in the window" if near else None)

    if sha is None:
        if resolved is None:
            return "ANCHOR_ONLY", None, anchor[:60]
        text = tree.blob("HEAD", resolved)
        if text is None:
            return "ANCHOR_ONLY", None, anchor[:60]
        hit = any(cit["line"] <= n <= cit["end"] for n in anchor_lines(text, anchor))
        return "ANCHOR_ONLY", "HEAD", ("%s — holds at HEAD" if hit else "%s — NOT at HEAD") % anchor[:60]

    if resolved is None:
        return "NOTREE", sha, (anchor[:60] if anchor else None)
    text = tree.blob(sha, resolved)
    if text is None:
        return "NOTREE", sha, (anchor[:60] if anchor else None)
    if anchor is None:
        nlines = len(text.split("\n"))
        return ("TREE_ONLY" if cit["line"] <= nlines else "NOTREE"), sha, None

    lines = anchor_lines(text, anchor)
    if any(cit["line"] <= n <= cit["end"] for n in lines):
        return "RESOLVES", sha, anchor[:60]
    loud, reads = announces_itself(text, cit)
    tag = "announces itself (%s)" % reads if loud else "DANGEROUS, cited line reads: %s" % reads
    if lines:
        return "DRIFTED", sha, "%s is at :%d; %s" % (anchor[:40], lines[0], tag)
    return "ABSENT", sha, "%s; %s" % (anchor[:40], tag)


# ---------------------------------------------------------------- the hermetic control

CONTROL_ANCHOR = "records the version it finds"

CONTROL_OLD_A = """A note about the router.
The gate reads the manifest and records the version it finds.
Filler line one.
Filler line two.
The breaker column carries nineteen rows of geometry.
"""

# Identical but for one prepended line, so every citation into it is off by exactly one: the
# shift the LINE coordinate does not survive.
CONTROL_NEW_A = """A note about the router.
Prepended paragraph that pushes everything down by exactly one line.
The gate reads the manifest and records the version it finds.
Filler line one.
Filler line two.
The breaker column carries nineteen rows of geometry.
"""

# Line 3 reads plausibly and is NOT what the citation was for, and the anchor is nowhere in the
# file: the `G5.md:159` shape, and the variety that gets believed.
CONTROL_NEW_B = """A note about the router.
Filler line two.
The gate consults a file and reports what it sees.
The breaker column carries nineteen rows of geometry.
"""

# The anchor is split across a newline at lines 3/4, so a line-anchored reader cannot see it and
# this one must: the re-wrap the ANCHOR coordinate does not survive on its own.
CONTROL_WRAP = """First line.
Second line.
The sentence continues and a wrap-tolerant
reader finds this phrase whole.
Last line.
"""


def build_control_repo(d):
    def run(*a):
        subprocess.run(["git", "-C", d] + list(a), check=True, capture_output=True)

    run("init", "-q")
    run("config", "user.email", "control@example.invalid")
    run("config", "user.name", "control")
    (pathlib.Path(d) / "a.md").write_text(CONTROL_OLD_A)
    (pathlib.Path(d) / "w.md").write_text(CONTROL_WRAP)
    run("add", "-A")
    run("commit", "-q", "-m", "old")
    old = subprocess.run(["git", "-C", d, "rev-parse", "--short=7", "HEAD"],
                         capture_output=True, check=True).stdout.decode().strip()
    (pathlib.Path(d) / "a.md").write_text(CONTROL_NEW_A)
    (pathlib.Path(d) / "b.md").write_text(CONTROL_NEW_B)
    run("add", "-A")
    run("commit", "-q", "-m", "new")
    new = subprocess.run(["git", "-C", d, "rev-parse", "--short=7", "HEAD"],
                         capture_output=True, check=True).stdout.decode().strip()
    return old, new


def control():
    """Twelve planted citations, one per answer, through the real classifier, plus the two
    citing-side wrap checks the twelve do not reach. Nothing is planted in the corpus this gate
    guards; see the module docstring."""
    with tempfile.TemporaryDirectory() as d:
        old, new = build_control_repo(d)
        tree = Tree(d)
        rows = [
            # label, citing prose, want class
            ("correct frame, anchor first",
             "`records the version it finds`, `a.md:2` at `%s`" % old, "RESOLVES"),
            ("correct frame, citation first",
             "`a.md:2` at `%s` reads \"records the version it finds\"" % old,
             "RESOLVES"),
            ("shifted by one",
             "`records the version it finds`, `a.md:2` at `%s`" % new, "DRIFTED"),
            # The real `G5.md:159` shape: the anchor is gone from the file entirely and the
            # cited line reads unrelated prose that a reader would believe. ABSENT, and the
            # evidence must say DANGEROUS rather than "past EOF".
            ("plausible wrong text",
             "anchor `records the version it finds`, `b.md:3` at `%s`" % new, "ABSENT"),
            ("citation into nothing",
             "anchor `records the version it finds`, `b.md:40` at `%s`" % new, "ABSENT"),
            ("tree git does not know",
             "anchor `records the version it finds`, `a.md:2` at `deadbee`", "NOTREE"),
            ("tree, no anchor", "`a.md:2` at `%s`" % old, "TREE_ONLY"),
            ("anchor, no tree", "anchor `records the version it finds`, `a.md:2`",
             "ANCHOR_ONLY"),
            ("neither", "see `a.md:2` for the detail", "BARE"),
            # The whole frame inside one span, with prose following. TREE_ONLY, not an anchor
            # scraped off the clause behind the span's closing tick.
            ("frame inside one span", "`a.md:2 at %s` is one answer; quoting the phrase "
             "relied on is another" % old, "TREE_ONLY"),
            # The first cut's false positive, planted so it cannot come back: a backticked phrase
            # in the same sentence but not against the citation is not this citation's anchor.
            ("phrase in the sentence, not against the citation",
             "the note at `a.md:2` argues, elsewhere, that `The gate reads "
             "`installed_plugins.json`` matters", "BARE"),
            ("wrapped anchor",
             "anchor `a wrap-tolerant reader finds this phrase`, `w.md:3` at `%s`" % old, "RESOLVES"),
        ]
        tracked = {"a.md", "b.md", "w.md"}
        by_base = {p: [p] for p in tracked}

        failures = []
        evidence = {}
        for label, prose, want in rows:
            found, _ = citations_in(prose)
            if not found:
                failures.append("%s: the reader found no citation at all" % label)
                continue
            got, _, ev = classify(found[0], tree,
                                  resolve_path(found[0]["path"], tracked, by_base)[0])
            evidence[label] = ev or ""
            if got != want:
                failures.append("%s: got %s, want %s" % (label, got, want))

        # Both rows are ABSENT. What separates them is whether the failure would be noticed, and a
        # gate that could not tell them apart would be reporting the two halves of this item's
        # central observation as one thing.
        if "DANGEROUS" not in evidence.get("plausible wrong text", ""):
            failures.append("plausible row: evidence did not read DANGEROUS — %s"
                            % evidence.get("plausible wrong text"))
        if "announces itself" not in evidence.get("citation into nothing", ""):
            failures.append("nothing row: evidence did not read announces-itself — %s"
                            % evidence.get("citation into nothing"))

        # The wrap row again, both ways. If a line-anchored reader would have said the same thing,
        # the wrap tolerance has demonstrated nothing and this run has no business reporting a zero.
        wrapped = tree.blob(old, "w.md")
        phrase = "a wrap-tolerant reader finds this phrase"
        tol = anchor_lines(wrapped, phrase)
        naive = anchor_lines_line_anchored(wrapped, phrase)
        if not tol:
            failures.append("wrap negative control: the wrap-tolerant reader did not find it")
        if naive:
            failures.append("wrap negative control: the line-anchored reader found it too, so the "
                            "fixture is not actually wrapped")

        # ---- the citing side, which none of the rows above reaches ----
        #
        # Every row above is a single unwrapped line, so the twelve say nothing about a citation a
        # text editor has wrapped. Two different things happen there and they point opposite ways.

        # A wrapped citation TOKEN is invisible to BOTH readers, by construction rather than by
        # luck: `normalise` replaces a whitespace run with a single space and `CITATION` admits no
        # space, so the collapsed view holds `a.md: 2` and matches nothing. This is what warrants
        # the record's reading of `N2 == N1` as a structural identity rather than as a measurement
        # of the corpus — and it fails here the day either of those two facts stops holding, at
        # which point that reading has to be earned again.
        split_token = "see `a.md:\n2` for the detail"
        if citations_in(split_token)[0]:
            failures.append("citing-side wrap: the collapsed reader found a wrapped citation "
                            "token, so N2 == N1 is no longer an identity and the record is stale")
        if CITATION.findall(split_token):
            failures.append("citing-side wrap: the line-anchored reader found a wrapped citation "
                            "token, which the tokeniser does not permit")
        if len(citations_in(split_token.replace("\n", ""))[0]) != 1:
            failures.append("citing-side wrap: the unwrapped form of the same string is not found "
                            "either, so the two checks above prove nothing about wrapping")

        # A wrapped FRAME is the citing-side wrap that does matter, and the whole reason this half
        # reads whole files. The anchor sits on the line before its citation; collapsed, the two are
        # adjacent and the citation resolves. Read a line at a time — which is what a line-anchored
        # reader gets — the same citation has no anchor at all.
        wrapped_frame = "anchor `records the version it finds`,\n`a.md:2` at `%s`" % old
        whole = citations_in(wrapped_frame)[0]
        one_line = citations_in(wrapped_frame.split("\n")[1])[0]
        if not whole or not one_line:
            failures.append("wrapped frame: the reader found no citation in the fixture at all")
            got_whole = got_line = "—"
        else:
            got_whole = classify(whole[0], tree,
                                 resolve_path(whole[0]["path"], tracked, by_base)[0])[0]
            got_line = classify(one_line[0], tree,
                                resolve_path(one_line[0]["path"], tracked, by_base)[0])[0]
            if got_whole != "RESOLVES":
                failures.append("wrapped frame: read whole, got %s, want RESOLVES" % got_whole)
            if got_line == got_whole:
                failures.append("wrapped frame: a line-at-a-time reader answered %s as well, so "
                                "reading whole files has demonstrated nothing here" % got_line)

        print("control: %d planted citation(s) over %d classes, in a throwaway repo at %s"
              % (len(rows), len(set(r[2] for r in rows)), d))
        print("control: citing-side wrap — a split token is invisible to both readers, so N2 == N1 "
              "is an identity; a frame across a wrap reads %s whole, %s a line at a time"
              % (got_whole, got_line))
        print("control: wrapped anchor reads line %s wrap-tolerant, %s line-anchored"
              % (tol or "—", naive or "— (invisible, as required)"))
        for f in failures:
            print("  FAIL  %s" % f)
        print("control: %s" % ("HELD — every class was reached and answered as planted"
                               if not failures else "%d FAILURE(S)" % len(failures)))
        return 1 if failures else 0


# ---------------------------------------------------------------- the sweep

def main():
    argv = sys.argv[1:]
    rc_control = control()
    print()
    if "--control" in argv:
        return rc_control

    tree = Tree(ROOT)
    tracked = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z"],
                             capture_output=True, check=True).stdout.decode().split("\0")
    tracked = [f for f in tracked if f]
    tracked_set = set(tracked)
    by_base = {}
    for f in tracked:
        by_base.setdefault(os.path.basename(f), []).append(f)

    generated = sorted(f for f in tracked
                       if any(fnmatch.fnmatch(f, p) for p in GENERATED))
    frozen = sorted(f for f in tracked
                    if any(fnmatch.fnmatch(f, p) for p in FROZEN))
    # Both leave N4, and the two lists are printed apart so the two reasons never blend into one
    # number nobody can question.
    unmaintained = set(generated) | set(frozen)
    selfnamed = [f for f in tracked if f in SELF]
    scan = [f for f in tracked if f not in set(selfnamed)]

    n1 = n2 = 0
    bare_continuation = 0
    seen = set()
    rows = []
    skipped = 0
    scanned = 0

    for f in scan:
        try:
            raw = (ROOT / f).read_text(encoding="utf-8")
        except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError, OSError):
            skipped += 1
            continue
        scanned += 1
        n1 += len(CITATION.findall(raw))
        found, bare = citations_in(raw)
        n2 += len(found)
        bare_continuation += bare
        for c in found:
            # The frame is part of the key. Keyed on (file, path, line) alone, a second citation of
            # the same line carrying a DIFFERENT and wrong frame is deduplicated away behind the
            # first one that resolves — found by planting exactly that in `G5-gapfix-3.md` and
            # watching the gate stay green. Same shape as `G8`: a clean answer to a narrower
            # question.
            c["frame"] = read_frame(c)
            key = (f, c["path"], c["line"], c["end"]) + c["frame"]
            if key in seen:
                continue
            seen.add(key)
            c["file"] = f
            c["unmaintained"] = f in unmaintained
            rows.append(c)

    n3 = len(rows)
    hand = [c for c in rows if not c["unmaintained"]]
    n4 = len(hand)

    checkable = []
    unresolved = {"ambiguous": 0, "untracked": 0}
    for c in hand:
        resolved, how = resolve_path(c["path"], tracked_set, by_base)
        if resolved is None:
            unresolved[how] += 1
            continue
        c["resolved"] = resolved
        checkable.append(c)
    n5 = len(checkable)

    tally = {k: 0 for k in CLASSES}
    blocked = []
    for c in checkable:
        cls, sha, ev = classify(c, tree, c["resolved"])
        c["class"], c["sha"], c["evidence"] = cls, sha, ev
        tally[cls] += 1
        if cls in BLOCKING:
            blocked.append(c)

    print("scanned %d tracked files (%d skipped as non-text, %d named as this gate's own "
          "and not scanned)" % (scanned, skipped, len(selfnamed)))
    print()
    print("denominators — five readings of \"how many citations\", none of them blended")
    print("  N1  every occurrence, line-anchored regex                    %6d" % n1)
    print("  N2  every occurrence, wrap-tolerant (whole file, collapsed)  %6d   %+d vs N1"
          % (n2, n2 - n1))
    print("  N3  N2 deduplicated by (citing file, cited path, line, frame) %5d" % n3)
    print("  N4  N3 with %d generated and %d frozen files excluded by name %5d"
          % (len(generated), len(frozen), n4))
    print("  N5  N4 whose cited path resolves to a tracked file           %6d" % n5)
    print("      dropped from N5: %d ambiguous basename, %d path not tracked"
          % (unresolved["ambiguous"], unresolved["untracked"]))
    print("  also: %d bare `:NNN` continuations of a path named earlier — counted, never resolved"
          % bare_continuation)
    print()
    print("classes over N5 = %d — a partition, so the column sums to N5" % n5)
    for k in CLASSES:
        mark = "  BLOCKS" if k in BLOCKING else ""
        print("  %-12s %6d%s" % (k, tally[k], mark))
    print("  %-12s %6d" % ("(sum)", sum(tally.values())))
    near = sum(1 for c in checkable
               if c["class"] == "BARE" and c["evidence"] and "near-miss" in c["evidence"])
    print("  of the BARE, %d sit within reach of a SHA-shaped token. A frame the adjacency grammar"
          % near)
    print("  could not follow lands in BARE rather than in an error class, so it drops past the")
    print("  DRIFTED/ABSENT check silently; this number is how visible that hole is.")
    print()

    if blocked:
        print("blocking — a stated frame that does not hold at the tree it names:")
        for c in sorted(blocked, key=lambda c: (c["file"], c["at"])):
            print("  %s:%d  cites %s:%d at %s  [%s]  %s"
                  % (c["file"], c["at"], c["path"], c["line"], c["sha"], c["class"],
                     c["evidence"]))
        print()

    bare_by_file = {}
    for c in checkable:
        if c["class"] == "BARE":
            bare_by_file[c["file"]] = bare_by_file.get(c["file"], 0) + 1
    if bare_by_file:
        top = sorted(bare_by_file.items(), key=lambda kv: -kv[1])[:10]
        print("where the unfalsifiable ones are — top %d of %d files, so the ratchet is lowerable "
              "rather than merely held" % (len(top), len(bare_by_file)))
        for f, n in top:
            print("  %5d  %s" % (n, f))
        print()

    baseline = None
    if RATCHET.exists():
        baseline = json.loads(RATCHET.read_text())
    bare_now = tally["BARE"]
    if "--write-ratchet" in argv:
        RATCHET.write_text(json.dumps({
            "note": "BARE citations over N5, per citing file. Written by "
                    "planning/citation-gate.py --write-ratchet. Each file's count may only fall, "
                    "and a file absent here may hold none: a scalar total would let a deletion in "
                    "one file buy headroom for a new bare citation in another.",
            "denominator": "N5",
            "bare": bare_now,
            "n5": n5,
            "by_file": dict(sorted(bare_by_file.items())),
        }, indent=2) + "\n")
        print("ratchet: written — BARE %d over N5 %d, across %d files"
              % (bare_now, n5, len(bare_by_file)))
        return rc_control

    rc_ratchet = 0
    if baseline is None:
        print("ratchet: no baseline at %s — run --write-ratchet to set one"
              % RATCHET.relative_to(ROOT))
    else:
        # Per file, not in total. A scalar ratchet lets a deletion or a refactor in one file buy
        # headroom for a brand-new bare citation in another, and the defect spreads while the
        # number holds. Raised by the out-of-family review, 2026-08-25.
        base_by_file = baseline.get("by_file", {})
        risen = sorted((f, n, base_by_file.get(f, 0)) for f, n in bare_by_file.items()
                       if n > base_by_file.get(f, 0))
        if risen:
            print("ratchet: %d file(s) hold more bare citations than the baseline allows:"
                  % len(risen))
            for f, n, was in risen:
                print("  %s  %d, baseline %d" % (f, n, was))
            print("  A bare citation is unfalsifiable; carry anchor and tree.")
            rc_ratchet = 1
        fell = sum(1 for f, was in base_by_file.items() if bare_by_file.get(f, 0) < was)
        print("ratchet: BARE %d over N5 %d against baseline %d — %d file(s) above, %d below%s"
              % (bare_now, n5, baseline["bare"], len(risen), fell,
                 "; re-run --write-ratchet to lower it" if fell and not risen else ""))

    rc_block = 1 if blocked else 0
    print("exit: control %d · blocking %d · ratchet %d" % (rc_control, rc_block, rc_ratchet))
    return 1 if (rc_control or rc_block or rc_ratchet) else 0


if __name__ == "__main__":
    sys.exit(main())
