#!/usr/bin/env python3
"""Sweep the tracked corpus for a version number bound to the word *installed*.

## The defect

`installed 0.9.4` is not a label. It is an assertion about what this machine holds right now, and
this machine's plugin cache is a directory four agents write to. Between 2026-08-22T05:19Z and
2026-08-22T09:54Z it took `0.9.4`, `0.9.6`, `0.9.8` and `0.9.9` — four versions in four hours
thirty-five minutes. Any number written next to *installed* is stale within the hour.

Gap-fix 2 wrote *"it holds 0.9.6 today"* into a hazard row and it was false eighty minutes later.
Gap-fix 3 withdrew that phrasing at four sites and left its siblings, because the guard it built
knew the strings that had gone wrong rather than the shape of the claim. Gap-fix 3's verification
blocked on one of the survivors. So the rule this script enforces is the one the documents already
own:

  a reading belongs to a NAMED VERSION; which version is installed is a question answered with a
  command, not a number in a record.

`0.9.4 reads 62 of 76` is a fact that cannot rot — the tree is still on disk and re-reads the same.
`installed 0.9.4 reads 62 of 76` rots the moment the cache moves, and takes the reading's
credibility with it. The fix is to drop the adjective, never to re-number it.

## Why the pattern and not the number

A guard keyed on `0.9.4` passes `0.9.9` tomorrow, which is the same mistake on a fresh fuse. So
every pattern here is keyed on a version-SHAPED token: `\\d+\\.\\d+\\.\\d+`, optionally wrapped in
markdown emphasis. Re-numbering a caught site to the next release trips the identical row.

The word is bounded the same way, and not by `\\b`. `_` is a word character to `re`, so
`\\binstalled\\b` cannot match inside `_installed_` — the emphasis these notes actually use. Gap-fix 4
wrote that form into `planning/progress/G5-gapfix.md:24` and its own guard could not see it, in any
class. LB/RB below spell the boundary out and `BOUNDARY` proves it; the trade is described where
they are defined.

## Classes

  block     a version-shaped token bound to *installed* in prose — in a sentence, or across a
            markdown table's cell wall — or a version quoted as what the shared cache holds now.
            Exit 1 if any hit outside RECORDS.
  role      *installed* used with NO version — "the installed version returns", "still loads the
            installed version". These name a role rather than a value and CANNOT rot. They are the
            model for the fix, so they are counted and shown rather than banned; a guard that
            reddened on the word would push documents away from the correct form.
  nonprose  the same binding in source, fixtures, mockups or generated data — Swift `installedAt:`
            neighbouring a fixture version, the console mockup's skills list, a JS check on a node
            package. Sample data is not a claim about this machine. Reported so the population is
            visible rather than silently filtered, never blocking.
  record    hits inside the notes whose job is to quote the withdrawn claim in order to record the
            withdrawal. Reported with file and line, never blocking.

## What this does not check

RECORDS below are not read at all, so a genuine re-assertion inside one of them is invisible here.
It holds two entries: this file, whose SELFTEST is the defect written out in full, and the vendored
tree, which is upstream's text rather than this repository's claims. A sweep that reds on its own
pasted evidence is not a fixed point — the same trade `planning/claim-sweep.py` documents, and the
reason the progress notes are scanned into `record` instead of being excluded outright.

`nonprose` is a judgement about file type, not about content: a real claim about this machine
written into a Swift comment would be reported and would not block. That is the deliberate cost of
keeping the Swift fixtures — which legitimately pair a version with an `installed` field — out of
the blocking set.

The connective vocabulary is closed. A binding phrased with a word outside it ("the deployed 0.9.4",
"running 0.9.4") is not caught. `role` exists partly to make that visible: an *installed* with no
`block` hit and no version nearby is either correct or phrased around the guard.

## Provenance

The wrap-tolerant reader is `planning/claim-sweep.py`'s, imported when that file is present and
carried inline otherwise. It was `main`-only when this guard was written, which is why the inline
copy exists; `main` has since been merged here, so the imported path is the one this branch takes
and the fallback is for a tree that predates the merge. R17 blocked four consecutive times on a
claim a hard wrap had hidden from `grep`, and that reader is what fixed it; it also handles the
blockquote-marker case a naive whitespace collapse misses. Which path was taken is printed, so a run
that silently used a stale inline copy is not possible.

The `B*` cache-claim patterns are `planning/verification/G5-gapfix-3-sweep.py`'s, carried forward so
this script supersedes that one rather than sitting beside it with a partial overlap.
"""

import fnmatch
import importlib.util
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve()
ROOT = HERE.parent.parent

# Not read at all; see the docstring. Every literal here must name a tracked file — an entry that
# matches nothing overstates what the guard is choosing not to read, and two such entries shipped at
# gap-fix 4 (`G5-gapfix-4-verdict.md`, `G5-gapfix-4-sweep.py`, neither of which exists on any ref).
# `_unmatched()` prints any that stop resolving, so the next one is visible rather than inferred.
RECORDS = (
    "planning/installed-claim-sweep.py",
    "vendor/test-campaign/*",
)

# Scanned, but their `block`-class hits report as `record`: a pass that withdraws a claim has to
# quote it to record the withdrawal. A verifier's own verdict belongs here rather than in RECORDS —
# it is quoted evidence, so it should be read and reported, and `record` already keeps it from
# blocking. `planning/verification/` holds nothing on this branch yet; the glob is what makes a
# verdict landing there report as `record` on the day it lands.
QUOTING = (
    "planning/progress/G5-gapfix-2.md",
    "planning/progress/G5-gapfix-3.md",
    "planning/progress/G5-gapfix-4.md",
    "planning/verification/*.md",
)

# Prose asserts; source, fixtures and mockups carry sample data. See the docstring.
PROSE_SUFFIXES = (".md", ".txt")

V = r"[*`_]{0,2}\d+\.\d+\.\d+[*`_]{0,2}"

# `\b` is the wrong boundary for this corpus, and the corpus proves it. `_` is a word character to
# `re`, so `\binstalled\b` cannot match inside `_installed_` — and underscore emphasis is how these
# notes stress the word. Gap-fix 4 introduced that form at `planning/progress/G5-gapfix.md:24` and
# the guard could not see it: the site escaped EVERY class, `role` included, so a sentence written in
# that emphasis was not merely unblocked but uncounted.
#
# So the boundary is spelled out instead of borrowed. An underscore separates when it is emphasis and
# not when it is inside a word: the underscore run may carry no letter or digit on its far side. That
# admits `_installed_`, `__installed__` and `___installed___` — the three runs markdown uses — while
# `board_registry_installed_count` and `installed_plugins.json` stay out, because a substring of an
# identifier is not a use of the word. Each lookaround is fixed width, which is what `re` requires;
# runs of four or more underscores are neither emphasis nor common and are not distinguished.
LB = r"(?<![A-Za-z0-9])(?<![A-Za-z0-9]_)(?<![A-Za-z0-9]__)(?<![A-Za-z0-9]___)"
RB = r"(?![A-Za-z0-9])(?!_[A-Za-z0-9])(?!__[A-Za-z0-9])(?!___[A-Za-z0-9])"
W = LB + "installed" + RB

# A closed vocabulary of connectives. Anything else between the word and the number means the two
# are not bound, and a quote mark or an angle bracket means the number is data rather than prose.
CONN = r"(?:[ \t ]|[-—–,;:·*`_()]|\b(?:the|a|an|its?|is|was|now|still|says?|said|reads?|records?|holds?|gives?|version|campaign|plugin|cache|copy|tree|here|test-campaign)\b){0,6}"

PATTERNS = [
    # The general binding — the class this script exists for.
    ("block", "I1  installed → <ver>", rf"{W}{CONN}{V}"),
    ("block", "I2  <ver> → installed", rf"{V}{CONN}{W}"),
    # A markdown table binds a description to a value across a cell wall, which CONN excludes on
    # purpose — `|` between two words is a column boundary, not a connective. Line-anchored, because
    # a table row cannot wrap and the normalised view would otherwise run the gap across rows.
    ("block", "T1  cell: installed | <ver>", rf"\|[^|\n]*{W}[^|\n]*\|\s*{V}\s*\|"),
    # Carried forward from G5-gapfix-3-sweep.py: a version quoted as the cache's live state.
    ("block", "B1  holds <ver> today", rf"holds\s+{V}\s+today"),
    ("block", "B2  cache's current <ver>", rf"cache'?s?\s+current\s+{V}"),
    ("block", "B3  cache's newest version is", r"cache'?s?\s+newest\s+version\s+is"),
    ("block", "B4  json records <ver>", rf"installed_plugins\.json[*`]*\s+records\s+{V}"),
    ("block", "B5  <ver> installed in cache", rf"{V}[^.|]{{0,70}}?installed in the machine'?s plugin cache"),
    ("block", "B6  the cache holds <ver>", rf"cache\s+(?:now\s+)?holds\s+{V}"),
    ("block", "B7  currently holds <ver>", rf"currently\s+holds\s+{V}"),
    ("block", "B8  current version is <ver>", rf"current\s+(?:cache\s+)?version\s+is\s+{V}"),
    # Widened at gap-fix 4 from `—` alone: the selftest caught the hyphen form escaping a pattern
    # written against the one em dash that had actually gone wrong.
    ("block", "B9  '— newest' table label", r"[—–-]\s*newest\s*\|"),
    # Not a defect. Counted so the correct form is visible and the fix has a model.
    ("role", "R1  installed, no version", W),
]

BINDING = ("I1", "I2", "T1")


def _reader():
    """`planning/claim-sweep.py`'s normalise, imported if present, carried inline if not."""
    cs = ROOT / "planning" / "claim-sweep.py"
    if cs.exists():
        spec = importlib.util.spec_from_file_location("claim_sweep", cs)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod.normalise, "imported from planning/claim-sweep.py"
    return _inline_normalise, "inline copy (planning/claim-sweep.py is absent from this tree)"


def _quote_marker_offsets(raw):
    """Offsets of blockquote markers opening a line; they separate words exactly as a wrap does."""
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


def _inline_normalise(raw):
    marks = _quote_marker_offsets(raw)

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


def _unmatched(tracked):
    """Literal RECORDS/QUOTING entries that name no tracked file.

    A list of exclusions is a claim about what the guard declined to read, and an entry matching
    nothing overstates it. Globs are exempt: `planning/verification/*.md` is deliberately forward
    looking, and holding it to a present match would delete the reason it is there.
    """
    out = []
    for label, group in (("RECORDS", RECORDS), ("QUOTING", QUOTING)):
        for pat in group:
            if any(c in pat for c in "*?["):
                continue
            if not any(fnmatch.fnmatch(f, pat) for f in tracked):
                out.append("%s: %s" % (label, pat))
    return out


# Each pattern's proof: one string it must catch, and the strings it must stay silent on. A guard
# that reds on nothing is indistinguishable from a guard that cannot fire, and this file set has
# twice shipped a checker whose passing was never demonstrated. `--selftest` runs these in memory,
# so it needs no tree mutation and cannot leave a plant behind.
#
# The negatives are the load-bearing half. `installed version` with no number and `0.9.9 reads 62 of
# 76` are the CORRECT forms — a guard that reddened on them would push documents away from the fix.
SELFTEST = [
    ("I1", "the same numbers the installed 0.9.4 gives"),
    ("I1", "the same numbers the installed 0.9.9 gives"),          # re-numbered to the next release
    ("I1", "the same numbers the installed 1.0.0 gives"),          # and to a major bump
    ("I1", "it reads what the installed version 0.9.9 reads"),     # with the `version` connective
    ("I1", "the installed\ncampaign version `0.9.9` on this data"),  # hard-wrapped mid-claim
    ("I1", "> the installed\n> 0.9.9 reading"),                     # wrapped across a blockquote
    ("I1", "the installed cache says `0.9.2`"),
    # The boundary samples. `\b` cannot match any of the three emphasis runs, and the first of them
    # is a live site in this corpus (`planning/progress/G5-gapfix.md:24`) that escaped gap-fix 4's
    # guard entirely. See LB/RB above.
    ("I1", "the _installed_ 0.9.9 gives the same numbers"),
    ("I1", "the __installed__ 0.9.9 gives the same numbers"),
    ("I1", "the ___installed___ 0.9.9 gives the same numbers"),
    ("I2", "| 0.9.4 - installed | 62 of 76 |"),
    ("I2", "| 0.9.9 - installed | 62 of 76 |"),
    ("I2", "`0.9.9`, the installed one"),
    ("I2", "`0.9.9`, the _installed_ one"),
    ("T1", "| Installed in the machine's plugin cache | `0.9.2` |"),
    ("T1", "| still installed today | **0.9.9** |"),
    ("T1", "| _installed_ in the cache | `0.9.9` |"),
    ("B1", "it holds 0.9.9 today"),
    ("B2", "the cache's current 0.9.9"),
    ("B3", "the cache's newest version is 0.9.9"),
    ("B4", "`installed_plugins.json` records **0.9.9**"),
    ("B5", "`0.9.2` is installed in the machine's plugin cache"),
    ("B6", "the cache now holds 0.9.9"),
    ("B7", "it currently holds 0.9.9"),
    ("B8", "the current cache version is 0.9.9"),
    ("B9", "| 0.9.9 - newest | 62 of 76 |"),
]

SELFTEST_CLEAN = [
    "what the installed version returns on the same registry",     # G5.md:8@6a3dbb8 - models the fix
    "an agent invoking the skill still loads the installed version",  # G5.md:185@6a3dbb8
    "whatever version happens to be installed on the machine",      # vendor/README.md:5@6a3dbb8
    "| 0.9.4 - a later cache copy | **62 of 76 (82%)** |",         # the fixed table row
    "0.9.4 reads 62 of 76 (82%) on this registry",                 # a reading against a named version
    "the cache held 0.9.4 when this was measured",                 # bound to a past instant
    "`installedAt: \"2026-03-02T10:14:00.000Z\"`",                  # a date is not a version
    "board_registry_installed_count is 0.9.9",                      # an identifier, not the word
    "`installed_plugins.json` is read at 0.9.9",                    # a filename, not the word
]


# LB/RB decide which tokens the word is even SEEN in, and that is not provable through the block
# patterns: `board_registry_installed_count is 0.9.9` stays clean under any boundary, because CONN
# stops at `count` before the version is reached. So the boundary is checked against itself. Each
# `False` row is one a naive `(?<![A-Za-z0-9])installed(?![A-Za-z0-9])` would count as `role` — the
# word inside an identifier read as a use of the word, which is V6's defect in the instrument.
BOUNDARY = [
    ("installed", True),
    ("the installed version", True),
    ("_installed_", True),                      # V1: `\b` cannot reach inside this
    ("__installed__", True),
    ("___installed___", True),
    ("*installed*", True),                      # asterisk emphasis, which `\b` already handled
    ("(installed)", True),
    ("installed-claim-sweep", True),            # V6: seen, and reported as a filename subset
    ("board_registry_installed_count", False),  # an identifier
    ("installed_plugins.json", False),          # a filename
    ("installedAt", False),
    ("preinstalled", False),
    ("x_installed", False),
    ("installed_x", False),
]


def selftest():
    """Prove every pattern fires on its own defect and on none of the correct forms."""
    by_prefix = {}
    for kind, name, pat in PATTERNS:
        if kind == "block":
            by_prefix.setdefault(name[:2], []).append((name, pat))

    def fires(pat, name, s):
        if name.startswith("T"):
            return any(re.search(pat, l, re.I) for l in s.split("\n"))
        norm, _ = _inline_normalise(s)
        return bool(re.search(pat, norm, re.I))

    failures, checked = [], 0
    for sample, want in BOUNDARY:
        checked += 1
        if bool(re.search(W, sample, re.I)) != want:
            failures.append("boundary: %r should%s be seen as the word"
                            % (sample, "" if want else " NOT"))
    for prefix, sample in SELFTEST:
        checked += 1
        if not any(fires(pat, name, sample) for name, pat in by_prefix[prefix]):
            failures.append("%s did NOT fire on %r" % (prefix, sample))
    for sample in SELFTEST_CLEAN:
        for prefix, pats in by_prefix.items():
            for name, pat in pats:
                checked += 1
                if fires(pat, name, sample):
                    failures.append("%s fired on a correct form: %r" % (name, sample))

    print("selftest: %d checks over %d patterns" % (checked, len(by_prefix)))
    print("          %d boundary cases, %d seen and %d not"
          % (len(BOUNDARY), sum(1 for _, w in BOUNDARY if w), sum(1 for _, w in BOUNDARY if not w)))
    print("          %d defect samples, each of which must be caught" % len(SELFTEST))
    print("          %d correct forms, none of which may be caught" % len(SELFTEST_CLEAN))
    for f in failures:
        print("  FAIL  %s" % f)
    print("selftest: %s" % ("%d case(s) held" % checked if not failures
                            else "%d FAILURE(S)" % len(failures)))
    return 1 if failures else 0


def main():
    if "--selftest" in sys.argv:
        return selftest()
    normalise, provenance = _reader()

    tracked = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z"], capture_output=True, check=True
    ).stdout.decode().split("\0")
    tracked = [f for f in tracked if f]

    excluded = sorted(f for f in tracked if any(fnmatch.fnmatch(f, p) for p in RECORDS))
    files = [f for f in tracked if f not in set(excluded)]
    stale = _unmatched(tracked)

    scanned, skipped = 0, 0
    hits = {name: [] for _, name, _ in PATTERNS}
    filename_hits = {}

    for f in files:
        try:
            raw = (ROOT / f).read_text(encoding="utf-8")
        except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError, OSError):
            skipped += 1
            continue
        scanned += 1
        quoting = any(fnmatch.fnmatch(f, p) for p in QUOTING)
        prose = f.endswith(PROSE_SUFFIXES)
        norm, offsets = normalise(raw)

        bound = set()
        for kind, name, pat in PATTERNS:
            if name.startswith("T"):
                found = [(i + 1, m.group(0))
                         for i, l in enumerate(raw.split("\n"))
                         for m in re.finditer(pat, l, re.I)]
            else:
                found = [(raw.count("\n", 0, offsets[m.start()]) + 1, m.group(0))
                         for m in re.finditer(pat, norm, re.I)]
            for line, hit in found:
                txt = re.sub(r"\s+", " ", hit)
                if kind == "block":
                    if name[:2] in BINDING:
                        bound.add((f, line))
                    cls = "record" if quoting else ("block" if prose else "nonprose")
                else:
                    cls = kind
                hits[name].append((cls, f, line, txt))

        # `installed-claim-sweep` is this guard's own filename. The word inside a path is not a use
        # of the word, and gap-fix 4's note reported one such hit as a correct-form site the fix was
        # modelled on. These stay inside `role` — removing them would move a total the notes quote —
        # but they are counted here so the subset has a normaliser committed beside it rather than a
        # number arrived at in a scratch directory.
        # A `role` hit sharing a line with a binding is the binding, not the correct form.
        hits["R1  installed, no version"] = [
            h for h in hits["R1  installed, no version"] if (h[1], h[2]) not in bound
        ]

        # Counted after that suppression and under the same rule, so the subset is a subset: a
        # filename on a line that also carries a binding is already reported as the binding, and
        # counting it here too would make `of those N, M are …` read M > its own population.
        for m in re.finditer(W + r"-claim-sweep", norm, re.I):
            line = raw.count("\n", 0, offsets[m.start()]) + 1
            if (f, line) not in bound:
                filename_hits.setdefault(f, []).append(line)

    print("reader: %s" % provenance)
    print("scanned %d tracked files (%d skipped as non-text)" % (scanned, skipped))
    print("excluded %d, listed by name and not read:" % len(excluded))
    for f in excluded[:4]:
        print("      %s" % f)
    if len(excluded) > 4:
        print("      … and %d more under vendor/test-campaign/" % (len(excluded) - 4))
    print("blocking class is prose only (%s); source and fixtures report as `nonprose`."
          % ", ".join(PROSE_SUFFIXES))
    for entry in stale:
        print("      names no tracked file — %s" % entry)
    print()

    totals = {"block": 0, "record": 0, "nonprose": 0, "role": 0}
    for kind, name, _ in PATTERNS:
        found = hits[name]
        counts = {}
        for cls, *_rest in found:
            counts[cls] = counts.get(cls, 0) + 1
            totals[cls] += 1
        tally = ", ".join("%d %s" % (v, k) for k, v in sorted(counts.items())) or "0 hits"
        print("%-26s  %s" % (name, tally))
        show = found if kind == "block" else [h for h in found if h[0] != "role"]
        for cls, f, line, txt in show:
            print("      [%-8s] %s:%d   %s" % (cls, f, line, txt[:92]))
        if kind == "role":
            byfile = {}
            for _cls, f, line, _t in found:
                byfile.setdefault(f, []).append(line)
            for f in sorted(byfile):
                print("      [role    ] %s   %s" % (f, ", ".join(":%d" % l for l in byfile[f])))
            nfn = sum(len(v) for v in filename_hits.values())
            print("      of those %d, %d are `installed-claim-sweep` — this guard's own filename,"
                  " not a use of the word:" % (len(found), nfn))
            for f in sorted(filename_hits):
                print("      [filename] %s   %s"
                      % (f, ", ".join(":%d" % l for l in filename_hits[f])))
    print()
    print("blocking %d · record %d · nonprose %d · role %d"
          % (totals["block"], totals["record"], totals["nonprose"], totals["role"]))
    return 1 if totals["block"] else 0


if __name__ == "__main__":
    sys.exit(main())
