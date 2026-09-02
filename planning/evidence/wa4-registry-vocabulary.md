# wa4 — the registry's own vocabulary, and a brief that can leave the remaining set

Branch `ai/wa4-registry-vocabulary`, 2026-09-02. Two briefs, one property each.
Raw transcript of every gate run quoted below: `planning/evidence/wa4-gate-transcript.txt`.

## 1 — a status word nobody taught the gate

### The remap, and what it did not lose

`DEF-011` was `partially-fixed · in-campaign` and `DEF-048` was `superseded · by-DEF-055`. Neither
reached any branch of `reckon`'s partition, so both were placed `broken` by the fail-closed default
rather than by anything the register said, and `reckon` said so in its own `why` field.

They are now `partially-fixed` and `superseded`, with everything the qualifier carried moved into a
new `resolution` field on each row. Nothing was flattened:

| row | was | is | class before | class after |
|---|---|---|---|---|
| `DEF-011` | `partially-fixed · in-campaign` | `partially-fixed` | `broken`, by default | `broken`, by the register |
| `DEF-048` | `superseded · by-DEF-055` | `superseded` | `broken`, by default | `waived`, by the register |

`DEF-011` does not move class and that is the point — it is the same answer, arriving from the
register instead of from a guess. `DEF-048` does move, `broken` to `waived`, which is this
register's own reading landing for the first time rather than a relaxation: `superseded` in
`reckon` means the row owes nothing, not that anybody repaired it, and such a row stays on the
ledger because the ruling can stop being true. Its successor `DEF-055` is **open**, so nothing is
counted as done by the move.

Sixteen further rows in `planning/test-campaign/defects.in.json` carried the pre-2026-08-27
spellings (`fixed-in-campaign`, `open-measured`, `open-owner`, …) and were reshaped onto compounds
whose lead the tool reads. `reckon` does not read that file — it takes defects from
`inventory.json` and nowhere else — but it is a hand-edited source that feeds it, and catching a
word there is catching it one edit earlier.

### Why the trap is not the obvious one

`reckon.py` reads a status in three steps, and only the first two are what a reader expects.
`state_of` splits on `:`; `defect_status_parts` splits the rest on `·  |  ,  ;` and returns both
the leading token and the whole string; and then **the classifier compares the LEAD against the
fixed and open sets and the WHOLE STRING against the partial, waived and not-owing sets.**

So `fixed · in-campaign` classifies and `superseded · by-DEF-055` does not, and both look identical
to a reader. Both of the rows this item was given were minted in good faith by somebody who had
seen the first form pass. A gate checking only "is the leading token a word reckon knows" would
have said yes to both and reddened for neither — which is why plant B below is the arm that
matters rather than a formality.

### The gate

`planning/defect-status-vocabulary-gate.py`, enrolled in `make lint` beside
`registry-drop-gate.py`, both the check and its `--selftest`.

It reads `inventory.json`'s `defect` array and every `planning/test-campaign/defects*.json`,
models `reckon`'s three steps in full, and exits 1 on any row whose status no branch reaches — or
that carries no status at all. On a clean run it prints **how each word in use will be counted**,
so a reader can see the class each row will land in rather than being told only that nothing is
wrong.

**`--agree` is the half that keeps this from becoming a third vocabulary.** It imports the
`reckon.py` that would actually run and compares the five word tuples against it. That arm fired
for real during this run: the plugin cache moved from **reckon 1.9.3 to 1.9.4** between the first
and last invocation, and the arm re-read the newer file and still reported no drift. It is
deliberately **not** in `make lint`, because the plugin cache belongs to a machine and not to this
repository; where no copy can be found it prints `NOT COMPARED` and exits 2, since a comparison
that did not happen is not a comparison that agreed.

### Proof that it reddens — four plants, each reverted

Full output in `planning/evidence/wa4-gate-transcript.txt`. Clean at exit 0 either side of every
plant.

| # | plant | result |
|---|---|---|
| A | `DEF-011` → `mostly-sorted`, a newly minted word | **exit 1**, word named with its row count |
| B | `DEF-048` restored to `superseded · by-DEF-055` | **exit 1** — the discriminating arm |
| C | `DEF-042` → `parked` in `defects.in.json` | **exit 1**, proving the source file is read too |
| D | the registry as `main` holds it, under `git stash` | **exit 1** over **18 rows** |

Plant B is the one that separates this from an instrument that cannot fail. Its leading token
`superseded` **is** a word `reckon` knows; a gate reading only the lead passes it, and it is the
exact shape of the two rows this item was given.

`--selftest` covers the same partition at the function level, 12 cases, exit 0, with the two
compound cases as the same arm.

**One instrument error inside this run, recorded rather than tidied.** Step 6 of the transcript
took `$?` after a `grep` in the pipeline, so it printed `exit=0` over a run whose own verdict line
said `exit: 1`. That is this repository's recorded tail-pipe trap arriving inside the evidence for
a gate about honest reporting. Step 6b re-takes the code from the gate itself.

### What this item does not settle

* **The asymmetry is `reckon`'s, and it is not fixed upstream.** This branch makes the register
  speak a vocabulary the tool can read; it does not make the tool read compounds symmetrically.
  `reckon` lives in `fledgeling-plugins`, a different repository and out of bounds here.
* **`--agree` compares word lists, never branch structure.** If `reckon` moved `superseded` to
  being read as a lead, `--agree` would still say no drift while this gate refused the wrong
  words. Modelled by hand in `classify`, held across 1.9.3 and 1.9.4, both read. The gate prints
  this on every clean run rather than keeping it here.
* **A status that classifies is not a status that is true.** `fixed` on a defect nobody
  re-measured passes this gate.
* **`DEF-011`'s own remaining halves are untouched.** The reason column still truncates; Checks'
  `Edit cases` and `Run again` and Settings' `Pair another device` and `Unpair` are still undrawn.
  That is why the row stays in the owing set.

## 2 — a brief that names nothing cannot be retired

### The specific brief

`G9-two-gates-pin-a-worktree-that-no-longer-exists.md`. It sat in the reckoning's `unbuilt`
class — *somebody wrote down what should exist and it is not there* — for an item that shipped,
was verified in fresh context and merged to `main` at `5ed60f6`. The cause is the single id it
cites: **`DEF-253` is egress's defect**, named here as prior art for the shape. Both repository
gates already read that correctly — `target-resolution-gate.py` declares the registry foreign and
`brief-target-gate.py` classes the brief `FOREIGN_ONLY` — but `reckon` joins on citations alone and
had nothing else to join to.

Retired through the mechanism this repository already uses rather than a second one: frontmatter
`status: completed`, plus `registry-target: none` with a reason of substance because the fix is a
repository gate and no case, requirement or defect in the campaign observes it. `shipped-by` is
deliberately absent: `shipped-by: 5ed60f6` is TRUE - that commit is the `ai/g9` merge, on `main` -
but `shipped-brief-gate.py` reads the LEDGER row's commits through its own cell parser and
witnesses only `03c34c3` from that row, so the two typed claims read as a disagreement. The sha
stays in the retirement note, where it is prose rather than a claim two parsers must agree on. The
gate's exit went 1 to 0 and its `shipped brief(s) still declare nothing` count 10 to 9. `planning/registry-retirements.json` was
read first and is **not** the right instrument — it declares id *renumberings* so a historical
citation still resolves, and nothing was renumbered here.

Its own two residuals are named in the retirement note rather than folded into it: the 40-file
absolute-path sweep, and `planning/hooks/pre-commit` being tracked but deliberately not installed.

### The general hole

`a-brief-that-names-nothing-cannot-be-retired.md` was itself unretirable, which is its own subject
arriving to it: it cites only `DEF-253` too, so it also sat in `unbuilt`. Those were the only two
`unbuilt` rows in the whole reckoning.

It now cites **`DEF-090`**, a real row filed on this branch that genuinely corresponds to it: *only
41 of 219 briefs name anything the registry holds, so the reckoning withholds retirement across the
board.* That figure is `brief-target-gate.py`'s own partition, re-measured on this branch. The
brief keeps `status: to-triage`, because the 78 `UNDECLARED` briefs are real remaining work and
retiring it would be a false green.

**No citation was written to raise a number.** `brief-target-gate.py`'s docstring records a sibling
project whose join went from 6.2% to 100% while every gate stayed green, because citations written
to satisfy a tool join nothing. Two briefs gained a target here; both targets are rows that exist
and say what the brief says.

`DEF-085` was filed for something found by arming rather than by reading: the first version of the
status remap synced `defects.in.json` to `inventory.json` wholesale and moved three rows that have
nothing to do with vocabulary — `DEF-002` `open`→`closed`, `DEF-040`
`open-instrument`→`fixed · in-campaign`, `DEF-063` `open · measured`→`open`. Those are
adjudications, not spellings. The sync was reverted, only the six unclassifiable shapes were
rewritten, and the standing disagreement between the two files is now a defect somebody can read
rather than a silent difference between a file that is read and a file that is not.

### What this item does not settle

* **78 briefs still name nothing**, and the join is 18.7%. That is `DEF-090`, open, and the remedy
  is deliberately not a bulk write.
* **Which of the two registry files is right about `DEF-002`, `DEF-040` and `DEF-063`** is an
  adjudication somebody has to make by reading each defect. `DEF-085`, open.
* **`target-resolution-gate.py` exits 1 on `main` today**, on two case ids in `ORCHESTRATOR.md`
  that no registry row holds — the gate names them; they are not repeated here, because writing
  them into this file made it a second offender at `2, floor 0` on the first attempt.
  Pre-existing, untouched, and named so this branch's green is not read as covering it.
* **`registry-drop-gate.py` exits 2 on `main` today** — `NOT COMPARED` on all four registry
  views, because the baseline ref it resolves does not carry `cases.json` or `inventory.json`.
  Reproduced on `main` before this branch was touched. `ledger-reconcile.py` exits 1 on `main`
  too; this branch adds no finding to either, only line counts.

## The reckoning, before and after

`reckon.py` 1.9.4 from the plugin cache, invoked by explicit path per ORCHESTRATOR's own
precondition, against `planning/features-to-triage` and `planning/test-campaign`. The **before**
run is this branch's registry stashed back to `main`'s state, so the two runs differ only by this
branch's edits; it reproduces `planning/reckoning/2026-09-02/ledger.json` exactly.

The after-ledger is written to `planning/evidence/wa4-reckoning-after/`, **not** to
`planning/reckoning/`, on purpose: `completion-gates.py`'s `waves` gate takes the newest reckoning
directory as the project's reckoning, and a branch-local run must not become that.

| class | before | after | |
|---|---|---|---|
| `unbuilt` | 2 | **0** | both rows were the DEF-253 citation |
| `unjoined` | 109 | 108 | `defect-vocabulary-blocks-the-reckoning-gate` joined |
| `broken` | 62 | 63 | −1 `DEF-048`, −1 `G5-gapfix`, +2 `DEF-090`/`DEF-085`, +1 net |
| `unmeasured` | 21 | 21 | |
| `undecided` | 19 | 21 | the two briefs below |
| `unnamed` | 1 | 1 | |
| `waived` | 77 | 79 | `DEF-048`, `BRIEF-G9` |
| `verified-done` | 263 | 266 | `REQ-040`, `CASE-0355`, `CASE-0356` |
| rows | 554 | 559 | five rows added |
| **work items** | **202** | **202** | 57/16/129 product/evidence/decision → 56/16/130 |
| requirements observed | 21/35 (60%) | 22/36 (61%) | REQ-040 added and observed |
| cases adjudicated | 165/175 (94%) | 167/177 (94%) | |
| `check` | exit 0 | **exit 0** | |

### Every row that moved class, and why

| row | before | after | why |
|---|---|---|---|
| `BRIEF-G9-two-gates-…` | `unbuilt` | `waived` | retired: terminal frontmatter status, witnessed by its LEDGER row |
| `BRIEF-a-brief-that-names-nothing…` | `unbuilt` | `broken` | now cites `DEF-090`, which is open — the honest class for it |
| `DEF-048` | `broken` | `waived` | `superseded`, read from the register instead of guessed |
| `BRIEF-G5-gapfix` | `broken` | `undecided` | it cites `CASE-0145` and `DEF-048`; with `DEF-048` no longer open, nothing in the registry says no against it, and the weak join stops it retiring outright |
| `BRIEF-defect-vocabulary-blocks-the-reckoning-gate` | `unjoined` | `undecided` | joined for the first time, to `REQ-040` |
| `DEF-090`, `DEF-085` | — | `broken` | filed here, open |
| `REQ-040`, `CASE-0355`, `CASE-0356` | — | `verified-done` | the property and its two observations |
| `DEF-011` | `broken` | `broken` | **deliberately unmoved** — same class, now from the register |

**One thing worth carrying out of this that the item was not asked for.** The join channel runs in
both directions. `defect-vocabulary-blocks-the-reckoning-gate.md` gained its edge without being
edited at all: `REQ-040`'s `source` field names the brief file, and `reckon.build_join` scans a
registry row's own `source`/`note`/`text` for brief slugs. So a registry row that names the brief it
answers closes the hole from the registry side, which is a second remedy for `DEF-090`'s 78
undeclared briefs and one that does not require touching somebody's stated intent.

**The reckoning caught a defect in this branch's own edit, and it is the exact class this item is
about.** `REQ-040` was first written with `evidence: "measured"`. `reckon` exits **4** on that —
*requirement evidence 'measured' … is not a word this tool classifies* — the same fail-closed
refusal, one vocabulary over. Corrected to `observed`, which is what the gate does: it reads the
committed registry and returns a verdict rather than the project reporting itself. Build and check
both exit 0 after.

### Reproducing the after-run

```
python <plugin-cache>/fledgeling-plugins/reckon/1.9.4/skills/reckon/scripts/reckon.py \
  build --briefs planning/features-to-triage --campaign planning/test-campaign \
        --out planning/evidence/wa4-reckoning-after --no-html
python <same>/reckon.py check planning/evidence/wa4-reckoning-after/ledger.json
```

`reckoning.md` — the tool's own prose report — is committed. **`ledger.json` is deliberately not**:
it is a generated file whose 559 rows carry 18 bare registry-id citations, and
`planning/citation-gate.py`'s ratchet went **red at exit 1** on it (`18, baseline 0`), correctly —
a bare citation is unfalsifiable and a generated artifact should not be the thing that raises the
repository's ceiling. The command above regenerates it byte-for-byte.
