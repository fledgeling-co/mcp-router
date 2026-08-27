# G8 acceptance — the executable part

The brief's remaining scope was executable. What had landed before this branch was **ten lines of
header comment** in `scripts/acceptance/mock_fidelity.py` recording M16's cross-branch rule, with
nothing downstream depending on it — which reads as a standard to satisfy rather than a call to
make, and is this item's own subject committed by the item.

Three deliverables, each with the plant that reddened it.

## 1. `planning/role-intersection-gate.py` — the cross-branch check, runnable

`make role-intersection`. Derives the union of every active branch's `VOUCHED_CONTROLS` roles by
`ast.literal_eval` of each ref's copy of the file, then walks **every** fidelity surface against the
added set — including surfaces with zero diff on the gate file, because the quota rule keys on the
build node's role rather than on the edit.

Both sets are established before any question about their members:

| set | how it is established | today |
|---|---|---|
| branches | every local head not already merged into the base | 65 heads, 62 merged, 3 active |
| surfaces | the union of `planning/fidelity/*.ledger.md` across all those refs, deduplicated by blob | 6 measurements, 6 paths, 5 readable |

**The reading it takes, stated rather than assumed.** It reads the tracked ledgers, not the MEASURE
build's `planning/fidelity/dumps/` — which are untracked and whose build exits 3 on this machine. The
ledger records **paired** build nodes only, so this is narrower than the dump reading, and every run
prints each surface's own unpaired remainder (`structure-unpaired`, `extra`, `extra-cited`,
`unclassified`) as its uncovered set. Quietly substituting a narrower instrument is the defect; the
figures are printed instead.

That narrower reading still reproduces the brief's finding exactly. `callout` on `unreadable-note`
is a paired node, so it sits in `planning/fidelity/harnesses.ledger.md:155` at `03c34c3`, on the
row anchored `role=callout kind=text`, and this gate reddens on it.

**Verdict on this tree: exit 3.** `planning/fidelity/popover.ledger.md` is an obituary — the fidelity
gate exited 3 on `#statusPopover has no '.v-ideal' block` and wrote *"This run did not produce a
table"*. A role sweep over it returns zero, and **a two-state gate reads that zero as a clean
surface**. Here it is `INCONCLUSIVE`. That is a true verdict about the corpus, not a broken gate.

**Denominators, each with its reader named.** `B1..B6` for the branch side, `S1..S3` for the surface
side, and per surface two independent counts side by side: `grep` (line-anchored, what a `grep` sees)
and `wrap` (whole file, whitespace collapsed, `claim-sweep.py`'s reader). They agree at 40/16/0/28/32/3
today because the ledger is generated and does not wrap; the run prints a `**` warning on the row if
they ever disagree, and names the collapsed figure as the complete one. Every intersection row prints
its `file:line` site, because a bare count is what let two parties report *verified* over disjoint
subsets.

## 2. `planning/sweep-control-gate.py` — a presence control on every absence sweep

In `make lint`, eight seconds, hermetic. Discovers sweeps across the whole tracked script corpus with
four named readers, requires a disposition for each, and **runs** the declared controls rather than
believing the registry at `planning/sweep-controls.json`.

```
D0   114  tracked .py/.sh files, vendor/ excluded
D1    91  carrying 1+ marker(s)
D2    60  carrying 2+ marker(s)  <= the threshold
D3    19  carrying 3+ marker(s)
D4     1  carrying 4+ marker(s)
D5    60  discovered as absence sweeps

X0  1662  paths returned by `git ls-files`, before any filter
X-    86  dropped: vendor/
X-  1462  dropped: no .py or .sh extension
X+     2  of those drops are scripts by shebang with no script extension
```

Every figure here was re-derived by running `python3 planning/sweep-control-gate.py` at `7048d44`
and reading the block above its disposition table. **An earlier draft of this file transcribed
D0 108 / D1 85 / D2 57 / D5 57 and 54 grandfathered.** Those were the numbers on the day the gate
was written; nothing in the corpus was measured again before they were copied here, and by then six
more scripts were tracked. A record certifying a count it did not re-derive is the failure this
item is named after, committed by the item's own evidence file, so the correction is written out
rather than quietly substituted.

The count at every threshold is printed so the choice of two is visible rather than buried — one
marker alone catches 91 of 114 and would mean nothing. The X block is the D0 filter reporting what
it discarded, added at `7048d44`: it names `planning/hooks/pre-commit` and `planning/hooks/pre-push`
as tracked scripts D0 cannot see, so the corpus's edge is a listed set rather than a prose caveat.

The registry is a **ratchet**, for `citation-gate.py`'s reason: demanding all 60 grow a runnable
control this week either never goes green or gets softened until it means nothing. So **3 control ·
55 grandfathered · 3 UNDISPOSED · 0 mislabelled · 1 UNDISCOVERED**, never blended into one figure,
and the gate blocks on what is new.
**Grandfathered is a backlog with a number on it, not a pass, and the gate says so on every run.**

Two of those five figures are not zero, and neither is being reported as clean:

* **3 UNDISPOSED** — `planning/goals/{citations-blocking-check,lint-except-citation-ratchet,worklist-check}.sh`.
  They are the orchestrator's own goal scripts, so this gate exits 1 and `make lint` with it. The
  strongest of the three is `lint-except-citation-ratchet.sh`, which decides that lint failed only
  on the ratchet by counting matches of `error:|Violation|FAIL|did not pass lint` — a lint failure
  spelled none of those four ways, in a run whose output contains `ratchet: BARE` anywhere, exits 0.
  Left standing rather than disposed: the fix is a change to what those scripts judge, which is
  their owner's call and not this branch's.
* **1 UNDISCOVERED** — `design/assets/slice-tiles.py`, registered `grandfathered`, still in the tree,
  and matching only V4 since V2 stopped claiming what V4 owns. The registry holds 55 rows; the live
  backlog is 54. Both numbers are printed, and neither is the other.

Three controls are declared and run: `citation-gate.py --control`, `role-intersection-gate.py
--control-only`, and this gate's own. `claim-sweep.py` is grandfathered with an accurate reason — it
carries the wrap-tolerant reader a control produced but exposes no flag that re-runs it, so its proof
lives in a docstring rather than in an exit code. That is the obvious next entry to promote.

## 3. Every sweep names the normaliser that produced its count

No count in either script is printed bare, and every discovered file names which of `V1..V4` fired on
it. Five sweeps over one phrase in one file returned four answers and only the widest was complete, so
a bare integer from an unnamed reader is an assertion wearing a measurement's clothes.

## Proof that each check can fail

Plant, watch it redden, restore byte-identically, report the hash. An assertion nobody has watched
fail is not known to bite, and this item exists because of exactly that.

| # | plant | before | after plant | restored |
|---|---|---|---|---|
| A | `("board-action", "leaf")` added to `VOUCHED_CONTROLS` on `ai/g8` — a role present on `harnesses` and absent from `main`'s table | `harnesses` CLEAR, `B6` = 0 added | **`harnesses` EXPOSED**, `B6` = 1, three sites printed at `:27`, `:28`, `:127` | `mock_fidelity.py` back to `cacb2947…`, byte-identical to the pre-plant copy |
| B1 | a new tracked sweeping script `planning/PLANT-sweep.py` (deleted after; the plant was reverted and it is in no commit) | 0 UNDISPOSED, exit 0 | **exit 1**, `1 UNDISPOSED`, named with its markers `V2,V3,V4` | removed from the index and the tree |
| B2 | `citation-gate.py`'s declared control rewritten to exit 7 | 3 controls passing, exit 0 | **exit 1**, `FAIL … control exited 7` | `sweep-controls.json` back to `885abffc…`, byte-identical |

**All three of the role gate's exit codes are proved reachable inside the hermetic control**, and this
is not decoration: on the real corpus **exit 1 cannot be observed however much exposure a plant
creates**, because `popover`'s 3 dominates. A findings code that has never been produced is not known
to work, so the fixture produces each of 0, 1 and 3 by filtering its own surfaces.

## The controls, and why they are hermetic

Nothing is planted in this corpus. `G4`'s seventeenth item: a control quoted inside the document it
guards is found by the naive matcher instead of the planted instance, and then passes for the wrong
reason and passes silently.

**Role gate — hermetic**, a throwaway repository with five planted answers, each required exactly:

```
ok    baseline   want CLEAR        got CLEAR
ok    edits      want EXPOSED      got EXPOSED
ok    obituary   want INCONCLUSIVE got INCONCLUSIVE
ok    silent     want EXPOSED      got EXPOSED
ok    `silent` reads EXPOSED with the union and CLEAR without it, so the answer depends on
      the union rather than on the ledger alone
ok    `silent` has zero diff on scripts/acceptance/mock_fidelity.py and is still EXPOSED
ok    exit 0 / 1 / 3 are each reachable
```

`silent` is M22: a branch with **zero diff on the gate file** whose ledger uses a role another branch
adds. It must read EXPOSED. The fail-if-agree row is what stops the fixture proving nothing — an
instrument that answers the same with and without the union has demonstrated nothing.

**Role gate — live presence control**, planted onto a real branch of a `--local --shared` clone:

```
sees  role='board-action' planted on a real branch reached the union via for-each-ref + ast.parse
sees  harnesses.ledger.md moved CLEAR → EXPOSED, intersection 0 → 3 row(s) over the real ledger
quiet a role no ledger contains reached the union and matched 0 rows on all 6 surfaces
```

This is what makes today's headline zero a measurement. `B6` is **0** on this tree because M16, M19
and M22 are all merged — the gate's answer is an absence, and an absence check cannot detect its own
blindness.

## The out-of-family review, and the control that could not fail

`gemini-3.7-flash-high` via `agy --new-project`, 2026-08-26, on-subject and adversarial. `grok-4.6`
was dispatched to the same prompt and **stalled at 263 bytes with no verdict**, so it is recorded as
a lane that did not answer rather than as agreement. That is one family, not two.

**Its first finding is the one worth recording plainly: the gate against checks that cannot fail was
shipped containing one.** The original live presence control took a role out of `surface.roles`,
passed it back as `inject`, and checked that `intersect` found it — `x in {x}` on tuples already
parsed into memory. It could not return `False` for any ledger carrying a single role, and it
exercised neither the ref walk, nor the `ast` parse of another branch's table, nor the union. It
looked exactly like a presence control and measured nothing.

**Its second is worse in kind**, because it was an overclaim rather than an omission: the collapsed,
wrap-tolerant reader computed a count that fed nothing. `sites`, `roles`, `intersect`, `status` and
`code` all read the **line-anchored** list, so a `role=` split across a wrap would have incremented
the collapsed figure, left `sites` empty and returned `CLEAR` — while the report printed *the
collapsed figure is the complete one*. The wrap-tolerant reader is now the verdict's reader and the
line-anchored count is the comparison.

Everything acted on, each traceable in the source at the line that names the finding:

| # | finding | what changed |
|---|---|---|
| F1a-1 | live control was `x in {x}` and could not fail | replaced with a plant onto a real branch of a clone; must reach `added` through `for-each-ref` + `ast.parse` |
| F1b-1 | collapsed reader decorative while claimed complete | collapsed reader is now the verdict's reader |
| F1d-1 | `line_of` returned a character offset, not a line | rewritten over line starts with `bisect` |
| F1d-2 | `raise SystemExit(str)` exits **1**, which here means FINDINGS | `Inconclusive` exception routed to 3 |
| F1d-3 | `^\}` anchored the closing brace at column 0 | `ast.parse` of the module, no regex |
| F1c-1 | an empty surface set returned **0** | `FLOOR = 1` readable surface; below it, 3 |
| F1c-2 | a branch with no gate file was a silent `(ref, 0, 0)` | its own printed class `B8` |
| F1c-3 | `0 → {hits}` hardcoded the starting state | both ends measured |
| F1b-2 | `refs/heads` only, called "every active branch" | `B7` prints the remote-ref count as outside the measurement |
| F2d-1 | a misspelled disposition produced **no finding at all** | `MISLABELLED` class; the docstring's claim is now true |
| F2d-2 | a string `control` crashed with `FileNotFoundError` | `shlex.split` |
| F2b-1 | `len(x) == 0` fired V2 **and** V4, reaching the threshold alone | V2 and V4 made disjoint; D2 fell 58 → 57 |
| F2c-1 | undecodable files were a warning, not a finding | they are findings |
| F2c-2 | an empty corpus returned **0** | exits 3 |
| F2a/b | no-op controls, non-`.py`/`.sh` files, idiomatic `if not results:` | printed as a named uncovered set on every run |

One finding was **not** acted on and is recorded rather than argued away: `run_control` verifies an
exit code and cannot tell a real control from `true`. `proves` records the intent in prose and this
gate does not verify it. That limit is printed on every run.

## The second red-green round, on what the review changed

| # | plant | result | restored |
|---|---|---|---|
| C | one registry disposition misspelled `grandfather` | **exit 1**, `1 MISLABELLED`, named with the four legal words | `sweep-controls.json` byte-identical |
| D | `ROLE_KIND` altered so the verdict's reader matches nothing | **exit 3**, `CONTROL FAILED — a zero below is unproved` | gate byte-identical |
| E | `union \|= roles` removed — **only** the cross-branch merge broken | **exit 3**, live control `BLIND … NOT in the added set of 0` | gate byte-identical |

**E is the decisive one.** It breaks nothing except the union derivation, leaves every ledger and
every parse intact, and the *old* injection-based control would have reported `sees` on all five
surfaces. The new one goes blind. That is the difference between a control that watches the
instrument and one that watches itself.

**Sweep gate — its own control** plants a sweep that must be discovered, a non-sweep that must not,
and a control command that exits 1 that must be reported failing. That third one is the one that
matters: a control-runner that cannot report a failure is a decoration, and executing is this gate's
only advantage over the written rule.

## What is left open

* **The unpaired remainder.** `harnesses` alone carries `structure-unpaired 15 · extra-cited 88 ·
  unclassified 36` with no `role=` anywhere tracked. Closing it needs the MEASURE build's dumps;
  `make mock-fidelity SURFACE=servers` exits 3 today (known-inherited).
* **`popover` has never been measured.** Until it produces a table the role gate stands at 3 and
  stays out of `make all` — wiring a permanent 3 into `all` would mean softening it within the week.
* **55 registered grandfathered rows, 54 of them still discovered.** A visible backlog with a count
  that may fall, not an amnesty — and two counts rather than one, because a row discovery no longer
  claims is not backlog.

## Hashes at the close

```
3581db8d…  scripts/acceptance/mock_fidelity.py   (header now points at the check)
1a6d2451…  planning/role-intersection-gate.py    (was 971c3df3… before the gap-fix)
c02737c8…  planning/sweep-control-gate.py        (was 425caa8d… before the gap-fix)
885abffc…  planning/sweep-controls.json          (unchanged — no row added, none removed)
```

## Gap-fix, 2026-08-26

One gap and three findings, returned by a fresh-context verifier that confirmed the rest.

**The gap: this item regressed a lint gate it had wired itself into.**
`python3 planning/reader-accounting.py` exited **1** on this branch and **0** on `ai/g9`, on one
reader — `planning/sweep-control-gate.py::tracked_scripts`, dropping at a comprehension filter and
recording nothing. The gate offers two ways out and they are not equivalent here. Declaring the drop
in `planning/reader-accounting.tsv` would have satisfied the gate and hidden a real hole: the filter
narrows 1662 tracked paths to 114, and two of the paths it threw away are shell scripts. So the code
reports instead, which is the remedy this item exists to argue for. `reader-accounting.py` now
classes it `accounts` rather than `unaccounted`, and exits 0.

**Finding a — a registry state with no reporting class.** Closed with the UNDISCOVERED class above.

**Finding b — a broken control exited 1, which in these gates means FINDINGS.** Reproduced with a
`git` on PATH that exits 128 for every invocation: `active_refs` returned nothing, `measure` raised
`Inconclusive` from inside `hermetic_control`, and nothing caught it — traceback, exit 1. That is
the confusion `Inconclusive`'s own docstring was written to prevent, one frame further out. Both
gates now run controls through a guard; the same fault re-run answers `CONTROL FAILED … raised
Inconclusive` at exit 4.

**Finding c — control-failure and inconclusive answered with one number.** Split. 3 now means the
instrument works and the corpus has a hole in it; 4 means the instrument is not known to work and
nothing it printed should be read. They are opposite instructions. `runnable-path-gate.py` on
`ai/g9` makes the same split with 2 and 1; 2 is unavailable here because `argparse` owns it and
`make` collapses every failing recipe to it, which the `role-intersection` target already says.

**Four more, from the out-of-family review (`grok-4.6` at xhigh, with `claude-fable-5` and
`gpt-5.6-sol` consulted by it on the open call; `gemini-3.7-flash-high` was down — headless
permission auto-denial, zero-byte output).** It read the branch rather than the summary and each
finding is measured, not argued:

* **The census's conservation arm was `a == a`.** It compared `corpus.considered` against the sum
  that defines `corpus.considered`, so it held however badly the loop dropped — a control that
  cannot fail, in a gate whose subject is controls that cannot fail. It now compares against an
  independent second `git ls-files`, and the fixture gained a `vendor/` plant so the arm has
  something to lose: deleting the vendor record now prints `BLIND a vendored script is discarded BY
  NAME rather than by silence (nothing recorded)` and `FAIL … 2 + 2 = 4 against 5 counted
  independently` at exit 4. Restored byte-identically, sha256 prefix `b2d6cd857d494a12`.

* **`is_shebang_script` required a dot-free basename**, which read "extensionless" for "script D0
  cannot see" and exempted the larger half of the hole. Removed. X+ moves from 2 to **6**: the two
  hooks plus `scripts/fixtures/{registry-fixture-server,slow-failing-server,slow-mcp-server}.mjs`
  and `src/index.ts`, all four `#!/usr/bin/env node`.

* **UNDISCOVERED should block, and now does.** The first draft printed it and passed, reasoning
  that both remedies are owner calls. Three reviewers took the other side: a reader tightening that
  drops rows out of discovery while the gate still exits 0 is the gate certifying a corpus it
  stopped measuring, which is this file's subject. The finding names both calls and the third
  answer the registry already accepts.

* **The control ran after the measurement.** On a stub `git`, `--control-only` answered 4 but the
  default path answered **3**, because `main` called `measure` before `guarded(hermetic_control)` —
  a verdict about the corpus from an instrument nothing had tested — and `report` printed the whole
  corpus table before returning. Reordered: the control runs first, the corpus is not measured if
  it fails, and the same stub now prints the control failure and nothing else at exit 4.

**D0 is deliberately still 114.** Six tracked scripts are named as outside it and outside every
disposition, which is a decision owed rather than one taken; a verifier re-derived D0 exact and
widening it would move a confirmed denominator. Measured 2026-08-26: none of the six carries two
markers, so widening today would add 0 sweeps and move only the denominators.

**The three UNDISPOSED were acted on by their owner while this gap-fix ran.** `main` at `db15862`
repaired all three goal scripts and its message credits this gate's finding; `lint-except-citation-
ratchet.sh` now carries `MIN_STEPS=8` as a presence control on its own parser. They are still
UNDISPOSED here because `planning/sweep-controls.json` exists only on this branch and holds no row
for them — bookkeeping the owner can close with three rows, not an open defect. The finding is left
standing rather than silenced by this branch.

**The new census is armed both ways.** `self_control` plants an extensionless shebang script that
must be named and a `.md` that must not. Forcing `is_shebang_script` to return `False` for every
path turned the row `BLIND a tracked script with no script extension is named by the discard census
(not named — D0 drops it in silence)` at exit 4; restored byte-identically, sha256 prefix
`f1bab3ae67ce92df` before and after, back to exit 0.
