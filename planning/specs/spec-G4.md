# spec-G4 — Readers that cannot account for their own input

Status: **Ready for Work** · Item: G4 · Category: harness · Deps: none
Branch: `ai/g4` · Worktree: `.worktrees/G4`
Brief: `planning/features-to-triage/G4-assertions-that-do-not-read-their-own-quantity.md`

---

## 0 · The question this item was blocked on is closed, and the answer is no

G4's brief was Untriaged because it could not say whether an assertion's name could be mapped
mechanically to the quantity it is supposed to read. The Google lane (`agy`,
`gemini-3.7-flash-high`) answered on 2026-08-22:

> No. Heuristic or NLP mapping from test identifiers to arbitrary in-scope constants yields
> ambiguous bindings and false positives on auxiliary constants, directly violating your
> zero-false-finding doctrine.

So the brief's option B is refused on this repository's own `detector-defects` doctrine, option A
(author-declared quantities) starts at zero coverage, and option C (a one-off audit) holds no line
afterwards. **None of the three is built.**

The substitute declines the framing rather than the question: two mechanisms that need no quantity
at all, and therefore have no false-finding class on correct code.

## 1 · What is built

### 1.1 Raw-input accounting as a structural invariant

A reader that discards part of its raw input either **records** what it discarded and reports it,
or carries a **written declaration** saying what it drops and why that is not its subject.

* `planning/input_accounting.py` — `Tally`, the primitive a reader uses to satisfy the contract.
  `drop(item, reason)` is shorter than `continue`, and `line()` is a sentence naming the whole of
  the reader's input.
* `planning/reader-accounting.py` — the gate. An AST pass over every Python file under `planning/`
  and `scripts/` finds each iteration that decomposes raw input and discards an item, and asks
  whether the discard is recorded into something the reader returns, prints or yields.
* `planning/reader-accounting.tsv` — the declarations, one line each, with a pinned row count.

The convention is not new here. `ledger-reconcile.py` already prints `H examined 85 rows …;
skipped 21 …`, and that clause is the only reason instances 1, 4 and 5 in the brief's table were
ever found. What was missing is that it is a habit rather than a contract: the census below found
that the file which invented the skip list recorded one of its own four drops.

### 1.2 A null-run gate

`planning/null-run-gate.py` runs the repository's hermetic assertions against input built to change
their verdict, in a scratch tree under `mktemp`. Two kinds of arm, and the difference is
load-bearing:

* **poison** — plant the exact defect the assertion is named for and require red. A violation
  detector over an empty tree correctly passes, so emptiness proves nothing about one.
* **null** — hand the assertion nothing and require it to *refuse* rather than report clean. A
  census or a coverage claim over zero input must be a usage error.

An assertion that passes on a null or poisoned input is provably vacuous. That is a property of the
assertion, measured by running it, not an inference about its name — which is what made this
buildable after name → quantity was refused.

Both gates run inside `make lint`, which is where the repository's other four script gates live.
Neither adds a new environment requirement, and together they take under ten seconds.

## 2 · What this does not reach, stated rather than implied

The brief's table has eight instances. These two mechanisms reach **four**: 1, 4, 5 and 6 — every
silent-drop and partial-match case.

| # | Instance | Reached | Why |
|---|---|---|---|
| 1 | check H before the skip list | yes | a silent drop; §1.1 is the contract that names it |
| 2 | G2's first acceptance test read in-scope-ness | **no** | it drops nothing; it reads a real quantity that is the wrong one |
| 3 | `no-harness-config-writes.sh` read same-line writes | **no** | same shape; already fixed and armed by its own selftest |
| 4 | check H's skip list read only short rows | yes | the drop in the other direction, now named |
| 5 | the ten checks read rows, not the file | yes | check L reads lines; `table_ids`' pipe filter is declared and cross-referenced to it |
| 6 | `table_ids` and friends drop a non-row line | yes | recorded by `Tally` as of this item |
| 7 | G3's criterion 3 read the integer at `:87` | **no** | a real quantity, wrongly chosen |
| — | `egress`'s `warm_worst * 4` | **no** | same |

**Half of this brief's own table is out of scope for its own fix.** Four of eight, mechanically and
permanently, beats eight of eight by vigilance — but the item does not close the class, and both
gates print that sentence on every run so a green cannot absorb it.

Two further boundaries:

* The accounting contract reaches **Python only**. 66 shell files under `scripts/` and `planning/`
  hold readers, and a `grep | while read` pipeline has no syntax the AST pass can resolve.
* The null-run gate's population is the **hermetic** assertions. What it does not arm is enumerated
  in its own output — check E (needs a git repository), `no-harness-config-writes.sh` (has its own
  selftest), 62 shell files needing a simulator or a built router, and the Swift suite (armed by
  `red-green.py`).

## 3 · Acceptance

1. `python3 planning/reader-accounting.py` exits 0 and prints the census: files, iterations,
   discarding iterations, readers, drop sites, and the four dispositions.
2. Every reader it finds is `accounts`, `declared` or `gap`; a `gap` is printed on every run.
3. `python3 planning/null-run-gate.py` exits 0 with every arm biting, and prints the populations it
   does not arm.
4. `make lint` runs both and stays at 0.
5. `python3 planning/ledger-reconcile.py` stays at 0 across A–L, with every pre-existing number
   unchanged.
6. Both gates are armed against a deliberately planted defect that is then removed, and the arms
   are recorded in `planning/progress/G4.md` including any that did not bite.

## 4 · Relationship to G1

G1 keeps the soft-assertion findings at lane level (`D-r6-h`, `D-m27-b`, `D-r7-j`, `D-r7-k`). G1
owns assertions that are too weak; this owns readers that cannot account for their input. They want
different gates and stay separate items.
