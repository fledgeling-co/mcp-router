---
status: completed
shipped-by: e716f46
found-by: the mechanism behind the 2026-08-27 loss, generalised
---

# Nothing refuses a registry edit that drops a case

- origin: session investigation, generalising from the G15-G19 merge run · 2026-08-27
- audience: whoever needs today's loss to be the last one of its shape
- platforms: n/a
- proposed-by-ai: false

## What and why

Five armed cases left the campaign registry this afternoon and every gate in the repository stayed
quiet about the departure. `five-armed-cases-and-the-floor-that-would-have-caught-it` is the
recovery; this is the reason it could happen at all, and it will happen again in the same shape
until something refuses it.

`cases.json` is one hand-edited JSON file that every parallel worktree writes. Eleven worktrees
currently hold eleven different versions of it. When those lines converge, the merge is a
whole-file replacement rather than a per-row union, so a case present in one lineage and absent in
the other leaves without a conflict marker.

Three gates could each have caught it and none did, for three separate reasons.

`strict-check` ratchets on the checked count, which is precisely the right instrument — but the
ratchet file travelled with the same registry, so the floor fell from 70 to 58 alongside the
coverage and the comparison was made against the lowered number. A ratchet stored inside the thing
it is watching is not a ratchet.

`campaign.py check` did notice, and it says so plainly: `4 surface(s) with no case at all`,
`5 requirement(s) no case traces to`. But it is not in `make all`, no CI job runs it and no
pre-merge hook calls it, so its verdict was available and nobody was asked to read it.

The reckoning would have caught the five orphaned requirements and could not, for the separate
reason in `the-relabel-gate-cannot-fire-on-any-ledger-it-writes`.

`surface-reconcile` — which G18 landed today, and which derives the surface denominator from the app
rather than from a hand-written list — is the pattern that works, and it is red on `main` right now
for real reasons. It catches a surface the app grew. It does not catch a case the registry lost,
because it reads the product rather than the registry's own history.

## Acceptance sketch

- A registry edit that removes a case, a requirement or a surface is refused, or passes only with
  the removal named and a reason recorded.
- The strict floor is read from somewhere the registry edit cannot carry with it, so a fall is
  compared against the number that was actually earned.
- `campaign.py check` runs where a merge has to meet it rather than only when somebody invokes it.
- The removal guard is watched to fail: dropping a case from a copy of the registry turns it red.
- A case count that falls between two runs is reported as a fall, in the artifact a reader meets
  first, rather than as a new lower total.

## Assumptions made writing this

- Assuming the guard belongs in this repository as a gate over its own registry, rather than
  upstream in `test-campaign`, since the merge discipline being violated is this project's.
- Assuming removal should be possible with a recorded reason rather than forbidden outright,
  because a case retired on purpose is legitimate and an unexplained one is the failure.
- Assuming the ratchet's storage location is part of this fix rather than a separate one, since the
  floor moving with the coverage is what made today's fall invisible rather than merely unnoticed.
