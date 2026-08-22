#!/usr/bin/env python3
"""Sweep the tracked corpus for a withdrawn claim, reading across line breaks.

R17 blocked four consecutive times on one sentence — *the declaration names all four uncovered
sites* — and the fourth block was the instrument rather than the diligence. The runner's
`grep -c "all four uncovered sites"` returned 0 while the phrase was sitting in the file, because
the hard wrap fell between `all four` and `uncovered sites`. A line-anchored reader cannot see a
claim a text editor wrapped, and every claim in this repo lives in a wrapped markdown file.

So this reads each file whole, collapses every run of whitespace — newlines included — to a single
space, matches against that view, and maps each hit's offset back to a line number in the original.
Markdown blockquote markers opening a line collapse with it, because a `>` separates two words
exactly as a wrap does; that was measured after this script missed a claim quoted inside a
blockquote. List markers and table pipes can do the same and are not handled — see
`quote_marker_offsets`.
It walks `git ls-files` rather than a hand-listed set of directories, so a new home for a claim is
in scope the moment it is tracked, and it reports how many files it could not decode instead of
skipping them in silence.

Exit code is 1 if any blocking-class pattern hits outside the excluded set, 0 otherwise.

## Why some files are excluded, and what that costs

A pass that withdraws a claim has to quote the claim in order to record the withdrawal, and this
script's own output echoes the matched text. So a progress doc that pastes a clean sweep makes the
next sweep red on the paste — the report becomes a corpus hit, and the gate reds on its own
evidence. The files below are therefore not scanned at all, and are listed by name with no counts,
which is what keeps the output a fixed point under being pasted into one of them.

The cost is real and is not hidden: a genuine re-assertion of a withdrawn claim inside one of these
files would not be seen. They are records of what was withdrawn, so that is the trade taken; a
claim asserted as current belongs in an evidence, spec or declaration file, all of which are
scanned.
"""

import fnmatch
import re
import subprocess
import sys

# Files whose job is to record a withdrawn claim rather than assert one. Not scanned; see above.
RECORDS = (
    "planning/progress/R17-gapfix-*.md",
    "planning/evidence/R17-gapfix-review-*.md",
    "planning/claim-sweep.py",
)

# A1-A3 block. A4-A7 widen the net around the same count so a rephrasing is visible; B1-B4 re-run
# gap-fix 2's withdrawn classes, which had only ever been checked line-anchored.
BLOCKING = ("A1", "A2", "A3")

PATTERNS = [
    ("A1  all four uncovered",            r"all\s+four\s+uncovered"),
    ("A2  four uncovered sites",          r"four\s+uncovered\s+sites?"),
    ("A3  which four it does not",        r"which\s+four\s+it\s+does\s+not"),
    ("A4  any 'four' near sites/saves",   r"four\s+(?:\W*\w+\W*){0,3}?(?:uncovered|save|saves|saveManifest|ManifestIO|sites|writers?)\b"),
    ("A5  every 'uncovered site' home",   r"(?:\*\*)?\w+(?:\*\*)?\s+uncovered\s+sites?"),
    ("A6  N sites left uncovered",        r"(?:\*\*)?\b(?:one|two|three|four|five|six|seven|eight|nine|ten|\d+)\b(?:\*\*)?\s+(?:\w+\s+){0,2}?sites?\s+(?:are\s+)?(?:left\s+)?uncovered"),
    ("A7  declaration + a count",         r"declaration\s+(?:\W*\w+){0,6}?\s*\b(?:one|two|three|four|five|six|eight)\b"),
    ("B1  withdrawn clause (verbatim)",   r"indifferent\s+to\s+whether\s+a\s+server\s+is\s+staged"),
    ("B2  withdrawn clause (concept)",    r"R19'?s?\s+window\s+is\s+\W*indifferent"),
    ("B3  symmetry claim",                r"read-?then-?save\s+window\s+on\s+both\s+sides"),
    ("B4  'still carry the same'",        r"still\s+carry\s+the\s+same"),
]


def quote_marker_offsets(raw):
    """Offsets of markdown blockquote markers that open a line, which carry no meaning for a claim.

    Found by this script blocking on its own evidence: a `>` prefix sits between the words of a
    quoted claim exactly as a hard wrap does, so `four uncovered` / `> sites` reads as no match even
    with whitespace collapsed. Measured, before this function existed, on a two-line probe carrying
    the withdrawn claim inside a blockquote — A1 fired on the part within one line and A2 did not
    fire across the marker at all.

    Only the blockquote marker is handled, because it is the only one measured. List bullets,
    numbered-list markers and table pipes can separate words the same way and are NOT stripped.
    """
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
    """Whitespace-collapsed view of `raw`, plus offsets back into `raw` per normalised char.

    Blockquote markers opening a line count as whitespace; see `quote_marker_offsets`.
    """
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


def main():
    tracked = subprocess.run(
        ["git", "ls-files", "-z"], capture_output=True, check=True
    ).stdout.decode().split("\0")
    tracked = [f for f in tracked if f]

    excluded = sorted(f for f in tracked
                      if any(fnmatch.fnmatch(f, p) for p in RECORDS))
    files = [f for f in tracked if f not in set(excluded)]

    scanned, skipped = 0, 0
    hits = {name: [] for name, _ in PATTERNS}

    for f in files:
        try:
            with open(f, encoding="utf-8") as fh:
                raw = fh.read()
        except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError):
            skipped += 1
            continue
        scanned += 1
        norm, offsets = normalise(raw)
        for name, pat in PATTERNS:
            for m in re.finditer(pat, norm, re.I):
                line = raw.count("\n", 0, offsets[m.start()]) + 1
                hits[name].append((f, line, re.sub(r"\s+", " ", m.group(0))))

    print("scanned %d tracked files (%d skipped as non-text)" % (scanned, skipped))
    print("excluded %d as records of a withdrawn claim, listed by name and not scanned:" % len(excluded))
    for f in excluded:
        print("      %s" % f)
    print()
    for name, _ in PATTERNS:
        found = hits[name]
        print("%-34s  %d hit(s)" % (name, len(found)))
        for f, line, txt in found:
            print("      %s:%d   %s" % (f, line, txt))
    print()
    blocking = sum(len(h) for name, h in hits.items() if name[:2] in BLOCKING)
    print("blocking classes %s total: %d" % ("+".join(BLOCKING), blocking))
    return 1 if blocking else 0


if __name__ == "__main__":
    sys.exit(main())
