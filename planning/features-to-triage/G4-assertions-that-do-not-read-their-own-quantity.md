# G4 — assertions that do not read the quantity they are named for

**Class:** harness / instrument. **Status:** Untriaged, not dispatched.
**Source:** a cross-session exchange with the `egress` project on 2026-08-21, which arrived at the
generalisation from a defect in its own suite. Filed here because this repository has now found
three instances of the same shape and treated each as unrelated.

## The shape

An assertion is named for a quantity, and reads a different one. Its pass and its
cannot-discriminate are indistinguishable, so it is green in both cases and the green carries no
information about the thing in the name.

Three already found here, each filed separately and none recognised as the same defect:

| Instance | Named for | Actually read |
|---|---|---|
| `ledger-reconcile.py` check H, before the skip list | rows | rows it could parse — 23 four-cell register rows were dropped silently |
| G2's first acceptance test | readability | in-scope-ness — satisfiable by moving rows *out* of the reader's scope |
| R7's `no-harness-config-writes.sh` | any write anywhere under `app/Sources` | writes on the *same physical line* as the token, so a realistic applier walks through |

And the one from `egress` that produced the framing: a test named
`the_exchange_budget_has_measured_headroom_over_the_slowest_verb` reads `warm_worst * 4`. Cutting
`EXCHANGE_TIMEOUT` from 1500ms to 10ms — a 150× reduction — left 7 of 7 green. The budget appears
in the expression and does no work in it.

## Why it is worth a gate rather than vigilance

Every one of these was found by accident, by someone attacking something adjacent. None was found
by review, and all four survived readers who were specifically looking for weak assertions —
because the assertion reads plausibly and its subject is in its name.

The detection is mechanical and cheap: **identify the quantity in the assertion's name, perturb
that quantity by a large factor, and require red.** Anything that stays green is misnamed at best.
The manual version found the `egress` instance in about four minutes.

## What is unresolved, and why this is Untriaged rather than Ready

Whether the name → quantity mapping is mechanisable at all. A gate that guesses the quantity from
the test name will mis-target, and a mis-targeted perturbation that stays green is a false finding
of exactly the kind this repository's `detector-defects` doctrine exists to refuse. Options, none
costed:

- Author-declared: each assertion names its quantity in a comment or attribute, and the gate
  perturbs what it is told. Honest, and it only covers assertions somebody annotated.
- Derived from the constant an assertion references, perturbing every named constant in scope and
  requiring at least one to turn it red. Mechanisable, noisier, and it catches the case above
  (`EXCHANGE_TIMEOUT` is in scope and unread).
- A one-off audit rather than a standing gate — cheaper, and it does not hold the line afterwards.

Triage should also decide whether this is one item or the *policy* half of `G1`, which already owns
soft-assertion findings (`D-r6-h`, `D-m27-b`, `D-r7-j`, `D-r7-k` are all this shape at the lane
level).

## A related instrument, recorded so it is not lost

The same exchange produced a discriminator worth having independently: **assert a relationship
between samples, not a bound on one.** A bound needs to know what the machine was doing; a
relationship does not, because both terms move together. Argmax position (warm-up puts it at index
0, contention is uniform), the count exceeding *k* × median (warm-up gives exactly 1), p99/p50 with
index 0 dropped, and the same vector run twice around a control workload you start and stop
yourself.

Its stated limit matters as much as the technique: it discriminates warm-up from contention and
**only** that. A mid-sequence peak means "not warm-up" and nothing more — a genuine regression
looks identical.

All of it is free once a timing test keeps its sample vector instead of reducing to `worst` and
`mean` and discarding the samples. None of it is available before that. This bears directly on
`G3`, whose subject is the only wall-clock assertion in this suite.
