# P6 — the parity gate states the owner's cutover target

The gate printed `The cutover requires 83 of 83. It has 79.` The owner decided the target is
**82 of 83** at `bec9d18` (ORCHESTRATOR.md line 144, "CUTOVER TARGET"), because
`fixture-registry-search` is a standing exclusion and 83 of 83 is unreachable by construction.

This item changes what the gate SAYS about the finish line. It changes no coverage number, and
sections 2 and 4 are the measurements that show it.

---

## 1. The premises, each checked against the repo rather than taken from the prompt

| Claim the change rests on | How it was checked | Result |
|---|---|---|
| The owner decided 82 of 83 | `git show bec9d18` | "Ledger: cutover target is 82 of 83, decided", 2026-08-16. States "The denominator stays 83." |
| ORCHESTRATOR.md carries it | `grep -n "CUTOVER TARGET"` | Line 144: "82 of 83, decided by the owner 2026-08-16" |
| Exactly one row is excluded | `awk -F'\t' '$5=="accepted-uncomparable"'` | One row, `fixture-registry-search`, manifest line 77 |
| The census is 83 | `awk '!/^#/ && NF>1'` + the `# rows: 83` pin | 83 both ways |
| Derived target matches the pin | 83 − 1 | 82 = `PARITY_CUTOVER_TARGET`; no drift |
| The "would RISE" reason is the row's own | the note in manifest line 77 | Verbatim: "deleting the row would leave the numerator alone and shrink the denominator, and the coverage figure would RISE" |

## 2. The arithmetic diff is exactly zero — proved two ways

### 2a. Mechanically, over the statements that can write a coverage number

Every statement assigning `proven`, `total`, `blocked` or `mismatched` is **identical** before and
after: the same nine statements with the same expressions, only line numbers shifted and
`excluded=0` appended to the initialiser. No new write to a coverage variable exists anywhere in
the file. `excluded` is incremented in one place, inside the `blocked` arm, *after* `blocked` has
already been incremented — a partition, never a subtraction.

### 2b. Empirically, by running the real gate on one tree

Same worktree, same build, same manifest, under a confirmed sole parity lock. The only difference
between runs is the script on disk.

| Run | Script | Coverage line | Exit | Wall |
|---|---|---|---|---|
| BEFORE | `79f1a55e…` (pre-diff) | `79 of 83 rows proven (4 of them by suite only…), 4 blocked` | 1 | 3m47s |
| AFTER | `e3f383ba…` (inherited) | identical, byte for byte | 1 | 3m45s |
| FINAL | after all fixes below | identical, byte for byte | 1 | 3m51s |

The blocked list is identical line for line in all three. **79 stays 79. 83 stays 83.**
The entire diff in the report is the target sentence and the new block:

```
- The cutover requires 83 of 83. It has 79.
+ The cutover target is 82 of 83, decided by the owner on 2026-08-16 (…, bec9d18).
```

## 3. What the report now says

```
cutover target: 82 of 83, decided by the owner on 2026-08-16 (ORCHESTRATOR.md "CUTOVER TARGET", bec9d18).
This gate REPORTS that target; it does not enact it. Every blocked row still exits 1
below, and the cutover itself is the owner's call on R4-C's evidence, not this script's.

  1 of the 4 blocked rows is a STANDING EXCLUSION, not work — nobody is
  assigned to it and nobody is waiting on it:
    fixture     fixture-registry-search  registry-search

  It stays in the denominator deliberately: deleting it would leave the numerator alone
  and shrink the denominator, so the coverage figure would RISE. …

  3 rows stand between 79 proven and the target of 82.
  The blocked rows that are real work, and the item that would unblock each (a row that
  DIVERGED is not blocked and is reported separately):
    control     control-auth-post-http   D-p1-a
    install     install-launchd-watch    D-p1-e
    install     install-rollback         R4-C
```

The excluded row is **named**, not subtracted.

## 4. Mutations — each assertion driven red for the right reason

`PARITY_LANES=" "` runs no lanes, which makes reconciliation deterministic and takes 1.7s. It
therefore reports `0 of 83, 83 blocked`; that is the control those runs are compared against, and
it is **not** a second measurement of the live 79/83 fraction. The two full-lane mutations are.

| # | Mutation (one field, one row) | Lanes | Expected | Observed | Exit |
|---|---|---|---|---|---|
| m0 | none (control) | none | excluded 1, no drift | `0 of 83, 83 blocked`, excluded 1, no drift | 1 |
| m1 | excluded row's owner → `D-fake` | none | excluded → 0, drift fires, coverage unmoved | excluded 0, `DISAGREE … less 0 is 83` vs 82, row appears as work, `0 of 83, 83 blocked` | 1 |
| m2 | a second row → `accepted-uncomparable` | none | excluded → 2, drift fires, coverage unmoved | excluded 2, `DISAGREE … less 2 is 81` vs 82, both named, `0 of 83, 83 blocked` | 1 |
| **m3** | **a proven row → blocked** | **all 12** | **proven −1, blocked +1, total same, distance +1** | **proven 79→78, blocked 4→5, total 83, distance 3→4, row named with owner `D-mutant`** | **1** |
| m4 | a lane that cannot run | bad lane | fraction and distance withheld | `COVERAGE IS NOT REPORTED`, distance withheld, "this run exits 2" | 2 |
| m5 | verdict → `probably-fine` | none | unscoreable branch | **not reached** — see the honest limit below | 1 |
| **m6** | **m2's census with real lanes** | **all 12** | **drift fires on a measured run, distance withheld** | **`79 of 83, 4 blocked`, excluded 2, drift fires, distance WITHHELD** | **1** |

m3 is the one that matters most: it shows the distance is a live function of `proven`, not a
constant, and that every coverage term still moves under a real stimulus.

**Honest limit.** m5 did not reach the branch it aimed at. `parity-manifest-check.sh` validates the
verdict against its closed set and the gate exits 1 before reconciliation, so the gate's
unscoreable arm is defence-in-depth and unreachable while the check runs ahead of it. The fix
applied to that arm (§5.3) is therefore **not** mutation-proven, and is recorded as such.

## 5. Defects found and fixed

Three were found by the mutations, four by an out-of-family review (grok-4.6), which confirmed the
partition claim and then found these. Every one is the report asserting something untrue.

1. **Subject-verb disagreement** — with two exclusions it read "2 … row(s) IS a STANDING EXCLUSION".
2. **A false claim with no exclusions** — the tail read "0 rows are excluded … AND NAMED ABOVE"
   while the naming block had not printed. Now reports the census/decision disagreement instead.
3. **A comment asserting a guard that does not exist** — it said `accepted-uncomparable` is
   "already checked" by `parity-manifest-check.sh`. That file checks only that a blocked row *has*
   an owner; the column is otherwise free text. The comment now says so and names what does catch
   a typo: the census/pin comparison, which m1 fires.
4. **"Every blocked row still exits 1 below" printed on the exit-2 path.** Each path now states its
   own exit code.
5. **The distance contradicted the drift warning** — it printed "3 rows stand between you and 82"
   one paragraph after "take it back to the owner before any number here is read as a finish line".
   The distance is now withheld on drift, as it already was when the fraction is withheld. m6 is
   the proof.
6. **"The blocked rows that are real work" over-claimed** — an unscoreable verdict was written to
   neither `excluded.txt` nor `remaining.txt`, so `excluded + remaining < blocked` and "partition"
   was untrue on that path. Unscoreable rows now go in the remaining list. The sentence also now
   says a DIVERGED row is not blocked and is reported separately.
7. **`parity-manifest-check.sh` still said "the denominator IS the cutover target".** True while the
   footer read `$total of $total`; false since `bec9d18`. Comment and operator guidance only.

### Reviewer points considered and NOT acted on

- **Print-only on drift rather than exit.** Grok argued print-only is correct and I agree: drift is
  "the decision and this census disagree", which is an owner question, not "a row is unproven".
  Exiting on it would also misfire on the one genuinely better outcome — every row proven with a
  census that is not 82.
- **`82` is a second pin beside `# rows: 83`.** Real, and left in place deliberately: a *derived*
  target could be lowered by marking one more row `accepted-uncomparable`, which is deleting a row
  to improve a number in different clothes. Pinned decision + derived census + reported
  disagreement is the manifest's own idiom. §5.7 makes the coupling explicit for whoever adds a row.

## 6. Reconciliation asked for, NOT fixed: "4 by suite only" vs D-g1-e's "eight"

**They do not contradict each other — they count different things.**

- The gate's `4 of them by suite only` counts rows whose manifest verdict is `proven-by-suite`
  (`div-r1-d2`, `div-r1-d4`, `div-r1-d5`, `div-r5-p7`). It is about the KIND of evidence: a cited
  test rather than a wire diff.
- `D-g1-e` counts checks whose assertions have never been demonstrated able to go red. That is a
  property of the assertion, orthogonal to whether its row was proven by wire or by suite.

A row can be wire-compared and still have an unfailable assertion, so the two figures should not
agree and their disagreement is not evidence of a defect.

**There is a real staleness, in the register rather than in the gate.** The `D-g1-e` row still
reads *"Eight parity rows have never been shown able to fail"* (ORCHESTRATOR.md line 278), while
D1's own merged entry (line 166) records the count moved `11 → 16 of 19` — which leaves **three**
unproven, not eight. The headline is stale against its own update. Flagged for the orchestrator;
not edited here, since the register is not this item's to move.
