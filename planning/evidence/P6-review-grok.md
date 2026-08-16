I'll read the review skill and the actual gate script so I can answer against the file, not just the pasted diff.Next I’ll diff the live script against the previous version and check the manifest plus the cutover pin, so the answers are grounded in what actually runs.The change is already on HEAD, so I’ll diff it against the parent and read the acceptance notes plus the old footer.The partition claim holds. `excluded` never writes `proven`/`total`/`blocked`, and the `parity: $proven of $total` line is the same string on every path. The measurements do not quite prove what the prompt implies they prove.

**On the measurements.** The nine assignment statements plus `excluded=$((excluded + 1))` sitting only inside the already-incremented `blocked` arm are the actual proof of the partition. The paired real run is the actual proof that this tree still prints `79 of 83` and exits 1. The `PARITY_LANES=" "` mutations do **not** re-prove 79/83. Empty lanes produce `parity: 0 of 83 rows proven, 83 blocked` (your `4708077` commit message says so; the prompt here did not). “Coverage line unchanged” on those runs means 0/83 stayed 0/83 while `excluded` moved. That is the right isolation for the counter. It is not a 79/83 test. You did not fool yourself about the arithmetic. You would be fooling yourself if you treated those mutations as a second measurement of the live fraction.

Not tested, and it matters for questions 3 and 5: `target_drifted=1` on a measured 79/83 run (census pin moved, lanes still ran). Empty-lanes drift is `remaining=$((82 - 0))`, which cannot show the sentence that goes stale.

---

**1. Coverage number the old code would have printed differently**

The measurement lines are unchanged. Same conditions, same strings:

```480:480:scripts/acceptance/parity-gate.sh
  echo "parity: $proven of $total rows proven$suite_note, $blocked blocked. This is NOT a pass."
```

```489:489:scripts/acceptance/parity-gate.sh
  echo "parity: $proven of $total rows proven$suite_note, 0 blocked."
```

```328:328:scripts/acceptance/parity-gate.sh
  echo "parity: $mismatched of $total rows DIVERGED from the reference."
```

```464:464:scripts/acceptance/parity-gate.sh
  echo "parity: COVERAGE IS NOT REPORTED for this run."
```

`env_failed=1` still withholds that fraction. `total=0` still exits 2 before any of this. Nothing newly withholds a `parity:` line the old file printed.

Two lines print a different `N of $total` than the old file:

The footer. Old blob `710810c` line 378 was `echo "The cutover requires $total of $total. It has $proven."` (`83 of 83`). Now:

```529:529:scripts/acceptance/parity-gate.sh
  echo "The cutover target is $PARITY_CUTOVER_TARGET of $total, decided by $PARITY_CUTOVER_DECIDED."
```

That is `82 of 83`. Intended. It is also the one overall `N of $total` a last-match scraper used to take.

A new line the old file never printed, including on the withhold path (old code exited 2 before the old footer, so env-failed runs used to have no overall `N of $total` at all):

```390:390:scripts/acceptance/parity-gate.sh
  echo "cutover target: $PARITY_CUTOVER_TARGET of $total, decided by $PARITY_CUTOVER_DECIDED."
```

That sits directly under `COVERAGE IS NOT REPORTED`. `82 of 83` is a decision, not a score, but it is the same shape as the number this file just refused to state.

No path raises or lowers `$proven` or `$total`.

---

**2. Print-only on pin/census mismatch**

Print-only is right. Drift is “the decision and this census disagree.” That is an owner question. It is not “a row is unproven” or “a lane did not run,” which are the two things this file is entitled to fail a run for.

Exit-on-drift is better at one thing only: a forgetful `# rows:` bump that leaves `82` behind cannot be ignored in CI. It is worse at the one case where the exit would actually change: `blocked=0` and `total != 82`, i.e. every remaining row is proven and the census is not 82. That includes proving the exclusion (83/83). Failing that run because a pin said 82 is the gate refusing a better outcome than the decision contemplated.

A motivated editor who wants a green by shrinking the surface already has to move `# rows:`. If they will do that, they will move `82` too. Exit-on-drift does not raise the cost of that edit. It only nags the forgetful case, and it misfires on 83/83.

The abuse you actually care about — marking another row `accepted-uncomparable` to lower a derived target — cannot pass anyway. Those rows stay `blocked`, so you already exit 1. Print-only vs exit is not load-bearing there.

What I would not leave as-is is not the exit code. It is printing `remaining` after saying the pin is stale. See 3 and 5.

---

**3. Is 82 a latent trap?**

Yes. It is a second pin next to `# rows: 83`. Adding a legitimate row, done properly, is now two coordinated edits. Forgetting the second is silent on the exit code.

What actually happens if a row is added and `# rows:` is moved to 84:

- Forget `# rows:`: `parity-manifest-check.sh` fails, this block never runs, coverage is withheld. Same as today.
- Update `# rows:` to 84, leave `82`: `target_derived` becomes 83 (or 82 if the new row is also excluded). Drift prints. Coverage becomes `N of 84`, which is the honest fraction. Exit codes do not change.
- Then this line still subtracts from the stale pin:

```382:382:scripts/acceptance/parity-gate.sh
remaining=$((PARITY_CUTOVER_TARGET - proven))
```

Add a blocked work row: proven 79, four items in `remaining.txt`, and it prints `3 rows stand between 79 proven and the target of 82`. Add a proven row: proven 80, three work items still listed, and it prints `2 rows stand between`. The work list and the distance disagree, after the drift block has just said not to read any number here as a finish line.

The surrounding check is now also wrong. `parity-manifest-check.sh` still says the denominator **is** the cutover target and tells you to move `# rows:` for that reason. That was true when the footer was `$total of $total`. It is not true now. The old pin will keep getting updated as if it were the target; this file will keep saying 82.

Adding a second `accepted-uncomparable` without touching 82 is the one add that does **not** drift (`84 - 2 = 82`). Coverage falls to `79 of 84`. That is honest. The report will call the new row a standing exclusion that nobody is waiting on, on the strength of a free-text owner match.

---

**4. Shell bugs**

- Unset under `set -u`: nothing. `excluded`, `target_derived`, `target_drifted`, `remaining` are all assigned before use. `local measured="$1"` is only reached with an argument.
- Arithmetic with negatives: nothing that faults. `remaining` can be negative (`proven > 82`); `[ "$remaining" -gt 1 ]` is false, the `= 1` arm is false, the else arm prints “at or past.” `excluded` cannot exceed `total` from these increments.
- `local` outside a function: nothing. `report_cutover_target` is a function.
- Word splitting: nothing on the new code. The new `echo`/`printf` arguments are quoted. `${MANIFEST#"$REPO_ROOT/"}` is quoted.
- Subshell scoping of counters: nothing. `excluded=$((excluded + 1))` is in `while … done < "$MANIFEST"`, not a pipe.
- `while read` eating stdin: nothing. Both new readers take `done < "$WORK/excluded.txt"` / `remaining.txt`, and they run after the manifest loop.

One classification leak, not a shell bug: the unscoreable `continue` at 160–167 increments `blocked` and writes `blocked.txt`, and writes neither `excluded.txt` nor `remaining.txt`. So `excluded ∪ remaining ≠ blocked` when a verdict is garbage. “Never a subtraction” is still true. “Partition of the blocked rows” is not, on that path. A typo in the exclusion row’s verdict column also drops `excluded` to 0 and fires drift, which is the guard you wanted for an owner typo, not for a verdict typo.

---

**5. Asserted without being shown, or readable as licence**

Three assertions:

`Every blocked row still exits 1 below` (line 391) is false on the path that calls `report_cutover_target 0`. That path exits 2. The sentence is printed anyway.

`The blocked rows that are real work, and the item that would unblock each` (line 447) asserts that `remaining.txt` is that set. Unscoreable blocked rows are not in it. Failures are not in it either (`mismatched` does not write that file), so with a divergence plus blocked work the distance is `82 - proven` and the list is short by the diverged rows.

After drift it prints `Take it back to the owner before any number here is read as a finish line` (line 400) and then, if `measured=1`, still prints `$remaining rows stand between $proven proven and the target of $PARITY_CUTOVER_TARGET` (line 439). That is the finish line it just disclaimed, computed from the pin it just called stale.

Licence: the only sentence that can be copied as a go is `$proven proven is at or past the target of $PARITY_CUTOVER_TARGET` (line 443). The next clause denies it, and the footer still says flipping the installer on this evidence is the outcome the gate exists to prevent. That is enough on the blocked path. It is not a licence. “The cutover itself is the owner's call on R4-C's evidence” (line 392) is the closest it comes: it names the current report as the evidence the owner acts on. At 79/83 that is harmless. At 82 proven and one blocked exclusion, a skimmer who stops at line 443 has the sentence they wanted; the file contradicts them if they keep reading.

`named above` is guarded. The `excluded=0` footer does not claim a list it did not print.

nothing else in that block reads as permission to cut over.
