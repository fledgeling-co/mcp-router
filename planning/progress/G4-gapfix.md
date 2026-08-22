# G4 gap-fix — the census counted the instrument into its own denominator

Parent `G4` · branch `ai/g4` · worktree `.worktrees/G4` · base `72958de`
Answering the first verification's **Needs More Work**, 2026-08-22.

The block was one number and its family: the census's *before* column was not a measurement of the
base tree. It was taken with `reader-accounting.py` sitting inside `planning/`, and
`SCANNED = ("planning", "scripts")`, so the gate counted its own four readers and fourteen drop
sites as pre-existing. Nothing else in the verdict was disputed; the four other claims were
re-derived and held.

Two files changed: `planning/progress/G4.md` §1 and `planning/reader-accounting.tsv`'s header. No
change to either gate's logic — that was the scope line, and it is the reason the item's evidence is
still worth what it was.

---

## 1 · The corrected column, measured with the gate outside the directories it scans

`ROOT` is the gate's parent's parent, so a copy under `gate/` has `planning/` and `scripts/` in
scope and itself out of scope. The base is reconstructed from the branch point rather than reasoned
about:

```
$ rm -rf /tmp/g4-base && mkdir -p /tmp/g4-base/gate
$ git archive 72958de | tar -x -C /tmp/g4-base
$ cp planning/reader-accounting.py /tmp/g4-base/gate/
$ cd /tmp/g4-base && python3 gate/reader-accounting.py                        # exit 1

  files          18 Python files, 0 unparsed
  iterations    217 examined; 77 discard at least one item
  subject        55 discarding iterations decompose no raw input this gate can resolve
  readers        15 raw-input readers over 22 discarding iterations
  drop sites     34 places a reader discards an item; 2 name what they dropped, 32 do not

  accounts        0 record every drop into something they return, print or yield
  declared        0 drop by design, with a written reason
  gap             0 drop silently and are recorded as known gaps
  unaccounted    15 drop silently and say nothing
```

Exit 1 is `registry file is missing`, which is the base read correctly: `reader-accounting.tsv` did
not exist at `72958de` either, so all fifteen readers dropped silently and said nothing.

| Census line | Reported | Measured at the base |
|---|---|---|
| Python files parsed | 18 | 18 |
| Iterations examined | 274 | **217** |
| …that discard at least one item | 91 | **77** |
| Unresolved subjects | 64 | **55** |
| **Raw-input readers** | **19** | **15** |
| **Discarding iterations** | **27** | **22** |
| **Drop sites** | **48** | **34** |
| …naming what they dropped | 7 | **2** |
| Dropping silently and saying nothing | 19 | **15** |

The verifier's three figures are the three in bold. The other five moved the same way and for the
same reason, so the whole column is restated rather than three cells of it — a column where six of
nine numbers came from one measurement and three from another is not repairable by patching the
three that were noticed. The file count is the one figure that was already right.

## 2 · The old column reproduced, which is what makes this a defect rather than a disagreement

Copy the gate into the base tree's `planning/` — where it was when the column was written — and the
reported figures come back exactly:

```
$ rm -rf /tmp/g4-base-inside && mkdir -p /tmp/g4-base-inside
$ git archive 72958de | tar -x -C /tmp/g4-base-inside
$ cp planning/reader-accounting.py /tmp/g4-base-inside/planning/
$ cd /tmp/g4-base-inside && python3 planning/reader-accounting.py             # exit 1

  files          19 Python files, 0 unparsed
  iterations    281 examined; 91 discard at least one item
  subject        64 discarding iterations decompose no raw input this gate can resolve
  readers        19 raw-input readers over 27 discarding iterations
  drop sites     48 places a reader discards an item; 8 name what they dropped, 40 do not
  …
  unaccounted    19 drop silently and say nothing
```

19 readers, 27 discarding iterations, 48 drop sites, 91 discarding, 64 unresolved — the reported
column, from a tree the gate is standing in. The differences between this run and the reported
column (19 files against 18, 8 naming against 7) are the marks of a hand subtracting the gate's own
file after the fact and stopping there.

The after column needed no correction: after this item the gate *is* one of the repository's
readers, and 21 readers over 29 discarding iterations across 21 files is the population as it now
stands. Its arithmetic checks out against the corrected base — the three added files account for
every delta, and the unresolved count is the clearest of them: 55 at the base plus 12 from
`reader-accounting.py` (9), `null-run-gate.py` (2) and `input_accounting.py` (1) is the 67 printed
today, with the per-file breakdown identical across both runs for the other eighteen files.

## 3 · The two sub-figures

Measured in the same base run, from its per-reader drop list:

```
    planning/ledger-reconcile.py::table_ids
      drops at planning/ledger-reconcile.py:53 continue
    planning/ledger-reconcile.py::describes
      drops at planning/ledger-reconcile.py:87 continue, planning/ledger-reconcile.py:90 continue,
               planning/ledger-reconcile.py:93 continue
```

`table_ids` had **one** silent drop site at base, not three. `describes` had **three**. The progress
note's sentence now reads *"`table_ids` had one silent drop and `describes` three"*. The claim that
followed it is unaffected: between them they are still the whole denominator checks A, B, C, F and G
stand on.

## 4 · The sweep for those figures, and the two ways it was wrong before it was right

R17's gap-fix 2 returned a clean grep over a corpus that still held its claim, because a hard wrap
split the phrase. This repository held the same trap: `reader-accounting.tsv` carried
`19 raw-input readers over 27 discarding` / `# iterations and 50 drop sites` across exactly such a
wrap, and a line-oriented search for `27 discarding iterations` finds nothing there.

Collapsing whitespace across newlines is necessary and was not sufficient. Two controls caught what
prose would not have:

* **Whitespace normalisation alone yields `over 27 # iterations`.** The comment marker the wrap
  introduces defeats the match just as the newline did, so leading `#`, `//` and a `*` followed by
  whitespace come off each line before the join.
* **An unqualified `*` strip eats markdown bold at the start of a line.** `**Fifteen readers` became
  `*Fifteen readers` and stopped matching the pattern written for it, which is why the `*` rule is
  qualified with a lookahead.

Both were found by the CORPUS control — the sweep asserts the *corrected* figures are present where
they were written, so a matcher pointed at the wrong tree or broken by its own normalisation reports
`MISSING` instead of a clean sheet. A sweep that only looks for absence cannot tell a clean corpus
from a corpus it never read, which is this item's subject.

The sweep is pasted below rather than committed as a gate: adding a third instrument is outside this
gap-fix's scope, and an instrument nobody has armed is not one this item should be shipping.

```python
#!/usr/bin/env python3
"""Wrap-tolerant sweep for G4's superseded census figures, over every tracked text file."""
import re, subprocess, sys

SUPERSEDED = {
    "readers 19 → 15": [r"19 raw-input readers", r"19 readers", r"[Nn]ineteen readers",
                        r"readers\W{0,6}19\b"],
    "discarding iterations 27 → 22": [r"27 discarding", r"over 27\b",
                                      r"discarding iterations\W{0,6}27\b"],
    "drop sites 48 / 50 → 34": [r"(?:48|50) drop sites", r"drop sites\W{0,8}(?:48|50)\b"],
    "table_ids three silent drops → one": [r"table_ids[^.]{0,60}three silent",
                                           r"three silent drops each"],
    "before column 274 / 91 / 64 / 7": [r"[Ii]terations examined \| 274",
                                        r"discard at least one item \| 91", r"raw input \| 64",
                                        r"naming what they dropped \| \*\*7\*\*"],
}
CORRECTED = {
    "planning/progress/G4.md": [
        r"readers        15 raw-input readers over 22 discarding iterations",
        r"drop sites     34 places a reader discards an item; 2 name",
        r"\*\*Raw-input readers\*\* \| \*\*15\*\*", r"\*\*Drop sites\*\* \| \*\*34\*\*",
        r"\*\*Fifteen readers, and not one of them",
        r"`table_ids` had one silent drop and `describes` three"],
    "planning/reader-accounting.tsv": [
        r"15 raw-input readers over 22 discarding iterations and 34 drop sites"],
}
WRAP_PROBE = "19 raw-input readers over 27 discarding\n# iterations and 50 drop sites"


def flatten(text: str) -> str:
    """One line, no wrap artefacts: line furniture off each line, then whitespace collapsed."""
    return re.sub(r"\s+", " ",
                  " ".join(re.sub(r"^\s*(?:#+|//+|\*(?=\s))\s?", "", ln) for ln in text.splitlines()))


files = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True).stdout.split()
TEXT = (".md", ".py", ".tsv", ".txt", ".sh", ".json", ".yml", ".yaml", ".swift", ".ts", ".js", ".html")
corpus = {}
for f in files:
    if f.endswith(TEXT):
        try:
            corpus[f] = flatten(open(f, encoding="utf-8").read())
        except (UnicodeDecodeError, OSError):
            pass

ok = True
print(f"CORPUS  {len(corpus)} tracked text files of {len(files)} tracked, whitespace normalised.")
for f, pats in CORRECTED.items():
    for p in pats:
        found = f in corpus and re.search(re.sub(r"\s+", " ", p), corpus[f])
        print(f"  {'found  ' if found else 'MISSING'} {f}: {p[:64]}")
        ok &= bool(found)

flat_probe = flatten(WRAP_PROBE)
across = bool(re.search(r"27 discarding iterations", flat_probe))
by_line = any(re.search(r"27 discarding iterations", ln) for ln in WRAP_PROBE.splitlines())
print(f"\nWRAP    normalised match across the newline: {across}; line-oriented match: {by_line}")
ok &= across and not by_line

print("\nRESIDUE — every surviving hit on a superseded figure, with 90 characters either side:")
total = 0
for figure, pats in SUPERSEDED.items():
    print(f"\n  === {figure} ===")
    hits = 0
    for f, flat in corpus.items():
        seen = set()
        for p in pats:
            for m in re.finditer(p, flat):
                s, e = max(0, m.start() - 90), min(len(flat), m.end() + 90)
                if (f, s // 40) in seen:
                    continue
                seen.add((f, s // 40))
                print(f"    {f}\n        …{flat[s:e]}…")
                hits += 1
    total += hits
    if not hits:
        print("    no hit")
print(f"\n{total} surviving hit(s). Controls {'all passed' if ok else 'DID NOT PASS'}.")
sys.exit(0 if ok else 2)
```

Result, exit 0:

```
CORPUS  1083 tracked text files of 1274 tracked, whitespace normalised.
  found   planning/progress/G4.md: readers        15 raw-input readers over 22 discarding iteration
  found   planning/progress/G4.md: drop sites     34 places a reader discards an item; 2 name
  found   planning/progress/G4.md: \*\*Raw-input readers\*\* \| \*\*15\*\*
  found   planning/progress/G4.md: \*\*Drop sites\*\* \| \*\*34\*\*
  found   planning/progress/G4.md: \*\*Fifteen readers, and not one of them
  found   planning/progress/G4.md: `table_ids` had one silent drop and `describes` three
  found   planning/reader-accounting.tsv: 15 raw-input readers over 22 discarding iterations and 34 drop s

WRAP    normalised match across the newline: True; line-oriented match: False

RESIDUE — every surviving hit on a superseded figure, with 90 characters either side:

  === readers 19 → 15 ===
    planning/progress/G4.md
        …the earlier before column of 19 readers, 27 discarding iterations and 48 drop sites was this instrument in its own denominator…
    planning/reader-accounting.tsv
        …The earlier version of this line read 19 readers, 27 discarding iterations and 50 drop sites, from a run with the gate inside…

  === discarding iterations 27 → 22 ===
    (the same two, matched on the other figure in the same sentence)

  === drop sites 48 / 50 → 34 ===
    (the same two)

  === table_ids three silent drops → one ===
    no hit

  === before column 274 / 91 / 64 / 7 ===
    no hit

6 surviving hit(s). Controls all passed.
```

Six surviving hits, and all six are the two correction clauses that name those figures as
superseded — one in `planning/progress/G4.md` §1, one in the tsv header. Both say what the number
was, what it is, and why it moved. The rest of the repository holds none of them.

## 5 · The commit claim

`5a9569c`'s subject line is *"Nineteen readers in this repository, and none of them could say what
it dropped"*, and its body states 19 readers, 27 discarding iterations, 50 drop sites, 7 naming.
`6605609`'s body states 19 readers and 48 drop sites, and `2787354`'s states three silent drops each
for `table_ids` and `describes`. History is not rewritten; this gap-fix's own commit message carries
the correction, and the two artefacts those commits produced now carry it in the tree.

## 6 · Gates, measured on this branch today

One `make all` on `ai/g4` at `27417a9`, 2026-08-22, its own timestamps running 15:41 to 15:44.
`make all` does not call the reconciler, so that is a second run from this worktree. Both are pasted
below; every elision is marked and cuts repetition only.

```
$ make all                                    # stopped at parity-selftest; nothing before it red
tools: Version: 2.45.4 · swiftlint 0.65.0 · swiftformat 0.62.1
Running SwiftFormat...
(lint mode - no files will be changed.)
Ignoring config file at /Users/lukerhodes/Dev/mcp-router/.swiftformat
SwiftFormat completed in 0.21s.
0/537 files require formatting, 252 files skipped.
…
Done linting! Found 0 violations, 0 serious in 530 files.
no-raw-design-values: scanning 118 files
no-raw-design-values: 77 files under the geometry and boundary rules
no-raw-design-values: clean
…
􁁛  Test run with 1684 tests in 209 suites passed after 5.324 seconds.
executed 1684 tests
test-ios: simulator A105F476-9B39-43A4-B37F-9A739C5C5930 (MCPRouter-Unit)
…
** TEST SUCCEEDED **
test-ios-glass: simulator 995BEF6F-101F-4D8A-ACE5-38724A13689A (MCPRouter-Glass)
…
** TEST SUCCEEDED **
…
parity: 358 vector cases compared (floor 358)
./scripts/acceptance/parity-manifest-selftest.sh
parity-manifest-selftest — can the manifest check fail?

  green the unmutated tree                                             exit 0
…                       (22 cases across cli, mcp and cited row ids, each `red … exit 1`)

the pinned census — the deletion neither derivation nor the lanes can see
  WRONG REASON  a blocked row deleted: div-r1-d3 (exit 1)
                wanted a message containing: holds 82 rows and pins itself at 83
                got:   a note cites "div-r1-d3", which is not a row id in this manifest.     Either the row it names was deleted, or the word is not an id and belongs in KNOWN_NON_IDS. 
  WRONG REASON  a blocked row deleted: install-claude-json (exit 1)
                wanted a message containing: holds 82 rows and pins itself at 83
                got:   the manifest holds 91 rows and pins itself at 92.     A row was added or removed. If that was deliberate, move the pin in the same change and 
  WRONG REASON  a blocked row deleted: install-import-servers (exit 1)
                wanted a message containing: holds 82 rows and pins itself at 83
                got:   the manifest holds 91 rows and pins itself at 92.     A row was added or removed. If that was deliberate, move the pin in the same change and 
  WRONG REASON  a blocked row deleted: install-rollback (exit 1)
                wanted a message containing: holds 82 rows and pins itself at 83
                got:   the manifest holds 91 rows and pins itself at 92.     A row was added or removed. If that was deliberate, move the pin in the same change and 
  WRONG REASON  a duplicate blocked twin ADDED (exit 1)
                wanted a message containing: holds 84 rows and pins itself at 83
                got:   the manifest holds 93 rows and pins itself at 92.     A row was added or removed. If that was deliberate, move the pin in the same change and 
  red   the pin removed from the manifest                              exit 1

dispatch shapes that used to be silent
…                       (7 dispatch-shape cases, each `red … exit 1`)

───────────────────────────────────────────────────────────────────────
manifest selftest: 31 behaved, 5 did not

A case that stays green is a mutation the manifest check cannot see, which means the
coverage fraction can be moved without the gate noticing. That is the finding.
make: *** [parity-selftest] Error 1
```

```
$ /opt/homebrew/bin/python3 planning/ledger-reconcile.py                      # exit 0
LEDGER         91 rows,  94 named
ORCHESTRATOR   91 rows, 102 named
merged ai/*    27 branches
  table row scan read 299 items of LEDGER.md; kept 91; dropped 208 (not a table row 206; first cell is not an allocation id 2)
  table row scan read 1464 items of ORCHESTRATOR.md; kept 96; dropped 1368 (not a table row 1076; first cell is not an allocation id 292)

  description scan read 299 items of LEDGER; kept 91; dropped 208 (not a table row 206; first cell is not an allocation id 2)
  description scan read 1464 items of ORCHESTRATOR; kept 96; dropped 1368 (not a table row 1076; first cell is not an allocation id 292)

H examined 85 rows with a status cell; skipped 21 with fewer cells than their header (#, CUTOVER TARGET, D-i4-a, D-i4-b, D-i5-a, D-i5-b, D-i6-a, D-i6-b, D-i6-c, D-i6-d, D-i6-e, D-i6-f, D-p5-a, D-p5-b RESOLVED — the gateway was pointed at a dead upstream, D-p6-a, D-p6-b, D-p6-c, D-p6-d, D-p6-e, D-p6-f, RULE)
  status row scan read 1464 items of ORCHESTRATOR.md; kept 85; dropped 1379 (not a row of a table with a Status column 1349; fewer cells than its header 21; a header rule, read for its column names rather than as a row 7; first cell is not an allocation id 2)

I examined 85 ids present in both files; LEDGER skipped 0 rows with fewer cells than their header
  status row scan read 299 items of LEDGER.md; kept 91; dropped 208 (not a row of a table with a Status column 206; a header rule, read for its column names rather than as a row 1; first cell is not an allocation id 1)
J examined 470 table rows in both files
K examined 213 deferred-register rows in both files
L examined 1761 lines in both files

reconciled — no findings across A, B, B-range, C, D, E, F, G, H, I, J, K, L
```

`make lint` is **0 violations, 0 serious in 530 files** with **0/537** requiring formatting.
`make test` is **1684 tests in 209 suites passed**, and both simulator lanes reach
`** TEST SUCCEEDED **`. The reconciler is **0 across A–L, exit 0**: check E now has nothing to
report, and no tracker file changed to make that so — which is `D-g4-b` in §7.

The one red is `parity-selftest`, and it is the base's. The first verification established that by
reconstructing `72958de` and the second confirmed it; this gap-fix touched no gate, no fixture and
no manifest, and it still holds unchanged — `manifest selftest: 31 behaved, 5 did not`, the five
being the pinned-census cases pasted above. Each of the five does exit 1; each exits 1 for a reason
its fixture does not recognise, because the counts it expects (82 rows pinned at 83, 84 pinned at
83) are the manifest as it was, where the tree holds 91 pinned at 92. That is a stale fixture in a
gate this item was told not to touch, it is red identically at the base, and it is not re-litigated
here.

### The sweep for this gap-fix's own two corrections

R17's `planning/claim-sweep.py` is the wrap-tolerant reader in this repository, and it is not on
this branch — it merged into `main` after `72958de`. So it is loaded from `main` and its `normalise`
used as it stands, hard wraps and blockquote markers and all, rather than copied into a second
instrument nobody has armed. Two properties its docstrings ask for are bought differently here:

* **Every pattern is armed against a bearer derived from the pattern itself**, so a matcher broken
  by its own escaping prints `DEAD` instead of a clean sheet. §4 got this from the CORPUS control;
  this gets it per pattern, including the presence controls. The bearer is derived rather than
  typed, because a synthetic residue written into the script would put the withdrawn claim back
  into the corpus the script scans.
* **Each pattern separates its words with `\s+`**, so no pattern matches its own text once
  whitespace is collapsed. That is what keeps the script and its result a fixed point when they are
  pasted into the file they scan. `claim-sweep.py` buys the same property by refusing to scan its
  record files; that is not available here, because the corrected figures live in the scanned file
  and the presence controls have to be able to see them.

```python
#!/usr/bin/env python3
"""Gap-fix 2's two corrections, swept with R17's reader rather than a second copy of it.

`planning/claim-sweep.py` is not on this branch — it landed on `main` at R17's merge — so it is
loaded from `main` and its `normalise` used as it stands. That buys the wrap tolerance its
docstring describes and the blockquote handling underneath it, on an instrument someone else
already armed, instead of a fresh one nobody has.

Every pattern separates its words with `\\s+`, so no pattern matches its own text once whitespace
is collapsed. That is what makes this a fixed point when it is pasted into the file it scans, and
it has to be bought this way rather than by claim-sweep.py's exclusion list, because the corrected
figures live in the scanned file and a presence control has to be able to see them. The bearer each
pattern is armed against is derived from the pattern at run time for the same reason: a synthetic
residue typed out here would put the withdrawn claim back in the corpus.
"""
import re
import subprocess
import sys
import types

src = subprocess.run(["git", "show", "main:planning/claim-sweep.py"],
                     capture_output=True, text=True, check=True).stdout
cs = types.ModuleType("claim_sweep")
exec(compile(src, "main:planning/claim-sweep.py", "exec"), cs.__dict__)

WITHDRAWN = [
    ("W1  §1's count of the rows that moved", r"other\s+four\s+moved\s+the\s+same\s+way"),
    ("W2  D-g4-b's exit-1 claim",             r"is\s+now\s+the\s+sole\s+reason"),
    ("W3  D-g4-b's citation of §6",           r"records\s+it\s+doing\s+more\s+than\s+moving"),
    ("W4  the superseded branch count",       r"measures\s+it\s+at\s+\*\*26\*\*"),
]
PRESENT = [
    ("P1  §1, corrected",         r"other\s+five\s+moved\s+the\s+same\s+way"),
    ("P2  §6 pastes the count",   r"merged\s+ai/\*\s+27\s+branches"),
    ("P3  D-g4-b, corrected",     r"reads\s+it\s+at\s+\*\*27\*\*"),
]
FILE = "planning/progress/G4-gapfix.md"


def bearer(pat):
    """A string the pattern must match, built from the pattern so the phrase is never typed here."""
    return pat.replace(r"\s+", " ").replace("\\", "")


tracked = subprocess.run(["git", "ls-files", "-z"], capture_output=True,
                         check=True).stdout.decode().split("\0")
tracked = [f for f in tracked if f]

corpus, skipped = {}, 0
for f in tracked:
    try:
        with open(f, encoding="utf-8") as fh:
            raw = fh.read()
    except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError, OSError):
        skipped += 1
        continue
    corpus[f] = (raw, cs.normalise(raw))

print("CORPUS  %d tracked files read, %d skipped as non-text, normalised by "
      "main:planning/claim-sweep.py" % (len(corpus), skipped))

ok = True
print("\nARMED   every pattern against a bearer derived from itself:")
for name, pat in WITHDRAWN + [(n, p) for n, p in PRESENT]:
    fires = bool(re.search(pat, bearer(pat), re.I))
    print("  %-7s %s" % ("fires" if fires else "DEAD", name))
    ok &= fires

w1 = bearer(WITHDRAWN[0][1]).split()
half = len(w1) // 2
wrap = " ".join(w1[:half]) + "\n" + " ".join(w1[half:])
quoted = "> " + " ".join(w1[:half]) + "\n> " + " ".join(w1[half:])
pat = WITHDRAWN[0][1]
for label, probe in (("WRAP  ", wrap), ("QUOTE ", quoted)):
    across = bool(re.search(pat, cs.normalise(probe)[0], re.I))
    by_line = any(re.search(pat, ln, re.I) for ln in probe.splitlines())
    print("%s  normalised match across the break: %s; line-anchored match: %s"
          % (label, across, by_line))
    ok &= across and not by_line

print("\nPRESENT the corrected figures, where they were written:")
for name, pat in PRESENT:
    found = bool(re.search(pat, corpus[FILE][1][0], re.I))
    print("  %-7s %-26s %s: %s" % ("found" if found else "MISSING", name, FILE, pat))
    ok &= found

print("\nRESIDUE every surviving hit on a withdrawn claim, anywhere in the corpus:")
total = 0
for name, pat in WITHDRAWN:
    hits = []
    for f, (raw, (norm, offsets)) in corpus.items():
        for m in re.finditer(pat, norm, re.I):
            hits.append((f, raw.count("\n", 0, offsets[m.start()]) + 1,
                         re.sub(r"\s+", " ", m.group(0))))
    print("  %-38s  %d hit(s)" % (name, len(hits)))
    for f, line, txt in hits:
        print("        %s:%d   %s" % (f, line, txt))
    total += len(hits)

print("\n%d surviving hit(s). Controls %s." % (total, "all passed" if ok else "DID NOT PASS"))
sys.exit(0 if ok and not total else 2)
```

Result, exit 0:

```
CORPUS  1118 tracked files read, 157 skipped as non-text, normalised by main:planning/claim-sweep.py

ARMED   every pattern against a bearer derived from itself:
  fires   W1  §1's count of the rows that moved
  fires   W2  D-g4-b's exit-1 claim
  fires   W3  D-g4-b's citation of §6
  fires   W4  the superseded branch count
  fires   P1  §1, corrected
  fires   P2  §6 pastes the count
  fires   P3  D-g4-b, corrected
WRAP    normalised match across the break: True; line-anchored match: False
QUOTE   normalised match across the break: True; line-anchored match: False

PRESENT the corrected figures, where they were written:
  found   P1  §1, corrected          planning/progress/G4-gapfix.md: other\s+five\s+moved\s+the\s+same\s+way
  found   P2  §6 pastes the count    planning/progress/G4-gapfix.md: merged\s+ai/\*\s+27\s+branches
  found   P3  D-g4-b, corrected      planning/progress/G4-gapfix.md: reads\s+it\s+at\s+\*\*27\*\*

RESIDUE every surviving hit on a withdrawn claim, anywhere in the corpus:
  W1  §1's count of the rows that moved   0 hit(s)
  W2  D-g4-b's exit-1 claim               0 hit(s)
  W3  D-g4-b's citation of §6             0 hit(s)
  W4  the superseded branch count         0 hit(s)

0 surviving hit(s). Controls all passed.
```

Three presence controls found, four withdrawn patterns at zero hits across the 1118 tracked files
the reader could decode — with the 157 it could not counted and named as skipped rather than
dropped — and all seven proved able to fire before any of it was believed. Re-run after this section
was pasted into the file: byte-identical output, exit 0, which is the fixed-point property measured
rather than argued.

## 7 · Registered, not fixed

The verdict asked for three to be recorded rather than chased. They are recorded here rather than in
`ORCHESTRATOR.md`: four other runners share that file, and the parent item deliberately made no
tracker edit for the same reason. Whoever merges this owns moving them into the deferred register.

* **`D-g4-a`** — `planning/fidelity/servers.ledger.md` is stale on `main` after M21. Checked from
  here: `git show main:planning/fidelity/servers.ledger.md` still reads
  `| tokens | clean | 25 matched, 64 pending, of 89 rows |`, byte-identical to this branch's base,
  while `git show main:planning/fidelity/token-register.json` binds **70** of its 89 rows to a Swift
  token and leaves **19** unbound — M21's verifier read that split as `70 matched, 19 pending`.
  Running the gate rewrites the ledger and nothing asserts its freshness, so the row has been
  reporting a superseded count since M21 merged. This item's class exactly: a record nothing checks.
  (On this branch the two agree — the suite prints `MOCK-FIDELITY-TOKENS: rows=89 matched=25
  pending=64 uncited=0`, which is why the drift is invisible from inside `ai/g4`.)
* **`D-g4-b`** — the reconciler's `merged ai/*` line reads a live `git branch --merged main` count,
  so it moves without any file changing. §6 reads it at **27**, with the reconciler at **exit 0**,
  and the verdict is what moved rather than the count: `G4.md` §3 records **27** for the run that
  exited 1, against **29** for the run before it, and every other number in §6's paste is identical
  to the one pasted there. What fired check E was `ai/g5` sitting merged into `main` with no row; `ai/g5` has since
  committed twice past that merge point (`2fbe062` → `3cd45c6`, `64e1631`), so it is no longer an
  ancestor of `main` and check E cannot see it. Three readings, two of them the same number under
  opposite verdicts, and neither tracker file edited between any of them. Each was right when it was
  taken, which is why this is registered rather than fixed: the finding was never a property of the
  two files, so there is nothing in them to correct.
* **`D-g4-c`** — `make test` failed twice standalone on `AuthorizationURLBoxTests / "a waiter that is
  cancelled is resumed rather than stranded"` (`OAuthWireTests.swift:263`, a 3-second wall-clock
  budget), then passed inside `make all` and in isolation in 3.164 s, at load 900–945. Attributable
  to load but not excludable as a real intermittency, and recorded that way rather than as a flake.
  `G3` owns the only other wall-clock assertion in this suite.

## 8 · Scope held

* No change to either gate's logic. `reader-accounting.py` and `null-run-gate.py` are byte-identical
  to what the first verification armed; the arms it ran independently still stand.
* One `reader-accounting.tsv` row's reason text changed alongside the header — `analyse_file`'s said
  *"naming the 194 non-discarding iterations individually would bury the 92 that do discard"*, and
  neither figure matches any run of the gate. Corrected to 205 and 96, measured on this tree and
  stamped with the date. The gate reads a row's reason only for emptiness, so no verdict depends on
  it; it is in scope as a census figure in one of the census's homes.
* No tracker status change, no merge, no rebase, no push.
* One census figure is **left wrong on purpose**: the tsv's `accounting_tree` row says copying the
  whole registry would leave *"fifteen rows pointing at absent files"*, and the true count is
  fourteen (18 rows less the 4 the scratch tree holds). The same wrong number is a comment inside
  `null-run-gate.py:131`. Correcting one and not the other would put them out of step, and
  correcting both means editing a gate this gap-fix is told not to touch. Registered as **`D-g4-d`**.
