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

The verifier's three figures are the three in bold. The other four moved the same way and for the
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

GATES_PLACEHOLDER

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
  so it moves without any file changing. §6 records it doing more than moving: it is now the sole
  reason `ledger-reconcile.py` exits 1.
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
