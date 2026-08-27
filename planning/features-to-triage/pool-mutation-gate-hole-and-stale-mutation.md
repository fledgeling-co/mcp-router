---
status: completed
shipped-by: 0bf48cc
---

# The pool mutation gate has a guard nothing proves, and a mutation that no longer applies

- origin: tailings audit of session 8246a1a7, after the worktree-path repair made the gate runnable · 2026-08-25
- audience: Engineers maintaining the upstream pool's race guards and the evidence behind them
- platforms: n/a
- proposed-by-ai: false

## What and why
The pool mutation gate proves each of the pool's race guards is load-bearing by removing one guard at a time and
requiring the test that covers it to go red. The gate had been unrunnable for long enough that nobody had seen its
verdict — it pointed at a deleted working directory and refused on every invocation. Repairing that made it run, and
it now reports a real result rather than a refusal: eleven guards are proved, one is not, and one check no longer
applies to the code it was written against.

The guard that is not proved is the one covering eviction of an ended session before anything suspends on it. Its
test passes whether or not the guard is present, so the guard could be removed today and nothing would say so. The
check that no longer applies is the one covering forced termination escalation; the code it was written against has
moved, so it silently measures nothing. Both matter more than an ordinary red, because the specification for this
area records the gate as having proved every guard — a claim the gate itself now contradicts.

## Acceptance sketch
- Removing the eviction guard makes at least one test fail, so the guard is proved load-bearing like the other eleven.
- The forced-termination check either applies to the current code or is withdrawn with its reason recorded, rather
  than reporting as skipped indefinitely.
- The gate reports a pass only when every check it lists either proved its guard or declared why it cannot.
- The specification's evidence table states the verdict the gate actually produces, and is re-checked when it changes.
- A check that cannot apply is distinguishable in the gate's output from one that applied and passed.

## Assumptions made writing this
- Assuming the unproved guard is real and its test is too weak (rather than the guard being redundant), because the
  other eleven guards in the same family are each proved by a test that goes red without them.
- Assuming the stale check should be re-pointed at the moved code rather than deleted, because deleting it would
  remove the only coverage of forced termination.
- Assuming this is one item rather than two: both were found by the same run and both are reasons the same gate's
  summary line cannot be trusted.
