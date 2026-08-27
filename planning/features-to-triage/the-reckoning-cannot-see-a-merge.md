---
status: to-triage
found-by: measuring the reckoning across six merges in one session, 2026-08-27
---

# The reckoning cannot see a merge, so its total is not a progress figure

- origin: the remaining-backlog fleet, measured across its own output · 2026-08-27
- audience: whoever reads "190 remaining" and takes it for the amount of work left
- platforms: n/a
- proposed-by-ai: false

## What and why

Six items shipped, were verified and were merged this session — G26, G30, G12, G13 and then
P11, G25, G22, M35. The reckoning's total did not move: 190 before, 190 after. Every one of the
shipped briefs is still counted as remaining work.

| brief | class after merging | counted as work |
|---|---|---|
| `nothing-prevents-a-sixth-vector-…` (P11) | `unjoined` | yes |
| `test-campaign-effect-provider-resolver` (G22) | `unjoined` | yes |
| `nothing-refuses-a-registry-edit-…` (G30) | `unjoined` | yes |
| `mac-shell-hand-named-rows-…` (M35) | `unjoined` | yes |
| `the-wave-enumerated-three-surfaces-…` (G25) | `undecided` | yes |
| `five-armed-cases-and-the-floor-…` (G26) | `undecided` | yes |

The mechanism is not a bug in the instrument. `reckon` reads the brief *files* in
`planning/features-to-triage/`, and a brief carries no state that says it shipped: the status
lives in `LEDGER.md`, which `reckon` does not read. A brief leaves the remaining set only by
being *joined* to a passing case in the campaign registry, and this repository's join rate is
**28 of 156, 17.9%** — below the 50% floor at which `reckon` withholds retirement claims
outright. So the ordinary outcome of shipping something is that its brief stays exactly where
it was.

Two consequences, and the second is the one that matters.

The number is not a progress figure. A reader watching 190 across a session in which eight
items merged would reasonably conclude nothing happened.

**And the fleet's own exit condition is unreachable.** `ship-fleet` finishes when the ledger is
drained *and* the reconciliation is clean. If shipping cannot move the reconciliation, no amount
of shipping ends the run. The fleet would keep dispatching against a total that never falls.

This is the same illness as `campaign-reanchor-to-current-tree` — evidence describing a tree
that has moved — reached from the brief side rather than the campaign side, and that one was
closed by re-measuring rather than by fixing the mechanism.

## Acceptance sketch

- A brief that shipped stops being counted as remaining work, without anyone having to guess.
- The route out is evidence rather than a status word, so that marking a brief done by typing is
  refused the way a requirement's evidence word already is.
- Where a shipped brief genuinely has no case behind it, it lands in a class that says so rather
  than in the same bucket as a brief nobody has looked at.
- The reckoning states its join rate beside its total wherever the total appears, so a low join
  is visible to a reader who did not go looking.
- A run in which N items merged and the total did not fall reports that as a finding.

## Assumptions made writing this

- Assuming the fix is to give a brief a terminal state the reckoning can read and verify, rather
  than to delete a shipped brief — deleting it would shrink the denominator and make coverage
  look better for having lost the row, which is the failure this whole tool exists against.
- Assuming the join rate is the real lever and a terminal state is the stopgap: at 17.9% most
  briefs are unjoined whether they shipped or not.
- Assuming this is scoped to `reckon`'s inputs in this repository rather than to `reckon` itself,
  which may be right to refuse a claim it cannot check.
