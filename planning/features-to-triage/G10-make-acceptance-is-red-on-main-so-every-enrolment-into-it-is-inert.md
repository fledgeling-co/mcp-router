---
status: completed
shipped-by: 77857e5
found-by: M22's verifier, 2026-08-23, during a Done-verdict residual sweep
---

# `make acceptance` dies at its first lane, so enrolling a lane into it delivers nothing

`make acceptance` runs `shells.sh` first (`Makefile:484`). **That lane is red**, and has been for
long enough that the blob is byte-identical on `main`, on `ai/m22` and on `ai/m22`'s base —
`6ffa54a52b2fef985d8578246f172f5574b6fba2` at all three. **Not any item's regression.**

Two defects in it, and the second is why nobody noticed:

- **It reads the wrong attribute.** `shells.sh:216` does `set v to value of e as text`, where the
  shell puts its labels in the accessibility *description*. `mac-shell.sh` asks the same question
  correctly and passes at **9 of 9 boards**, so the product is fine and the lane is wrong — `G4`'s
  class, in an acceptance gate.
- **Its emptiness guard cannot fire.** AppleScript's `missing value` coerced `as text` **is not
  empty**, so the check that would have caught the first defect passes over it.

## Why this matters more than one red lane

`M22` enrolled `m22-boards.sh` into `make acceptance` deliberately, on the reasoning that **a lane
nothing dispatches passes by hand forever while reading as covered work** — `parity-stream.sh` sat
executable and unrun from `R2-R` until `P3`.

**That enrolment is inert.** The target dies four lanes earlier, so `m22-boards.sh` still runs only
when somebody remembers it — exactly the state the enrolling commit set out to end. And the same is
true of **every lane enrolled into `acceptance` from here** until this is fixed.

So the cost is not a red gate. It is that **enrolment has stopped being a way to make a lane run**,
while continuing to read like one in every commit message that claims it.

## Scope

- Fix `shells.sh` to read the description attribute, and give its emptiness guard a predicate that
  can fire on `missing value`. `mac-shell.sh` is the worked example.
- **Then re-check every lane already enrolled in `acceptance`**, because none of them has been
  reached since `shells.sh` went red, and a lane that has never run is not known to pass.
- Decide whether `acceptance` should continue on a failing lane or halt. Halting is why one stale
  lane hid five others; continuing risks a green summary over a red lane, which is worse.

**Do not fix this by moving `m22-boards.sh` earlier in the list.** That makes one lane run and leaves
the ordering as the thing that decides what gets measured.
