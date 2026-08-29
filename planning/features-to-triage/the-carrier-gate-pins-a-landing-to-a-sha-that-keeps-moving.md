---
status: to-triage
found-by: merging R27 through an integration branch onto main, 2026-08-29
---

# The carrier gate pins a landing to a SHA that moves every time the work is carried forward

- origin: R33's carrier-parity gate, on its first two real merges · 2026-08-29
- audience: whoever merges through an integration branch, which is this repo's normal path
- platforms: n/a
- proposed-by-ai: true

## What and why

`planning/carrier-parity-gate.py` records a one-sided landing — work that touched one router and
not the other — as a row in `planning/parity/carriers.tsv` keyed by the landing's commit SHA. The
idea is right and it caught a real thing on its first outing: R27 landed Swift-only with no
disposition, and the gate said so.

The key is the problem. **A landing's SHA is not stable under this repo's merge workflow.** R27's
row was pinned to `91b2802d` on `ai/l6`. Merging `ai/l6` into `integ/l` made the landing
`1bfad22d`, and the gate reported the row both UNDISPOSITIONED (for the new landing) and STALE
(for the old one) at once. Repointing it to `1bfad22d` held until `integ/l` merged onto `main`,
at which point the landing became `9128737` and the same pair of findings returned.

So the gate goes red on every integration hop, for the same unchanged work, and the only way to
keep it green is to re-pin the row after each merge. A gate that must be edited on every merge to
stay green is one that gets edited without being read.

Two merges is a small sample, but the mechanism is not in doubt: the identity being recorded is
"which commit currently introduces this diff", and that changes whenever the work is carried.

## Acceptance sketch

- A one-sided landing keeps one identity from the branch it was built on through to the
  integration branch, so carrying it forward does not invalidate its disposition.
- Merging an already-dispositioned landing produces no finding.
- A genuinely new one-sided landing still produces one — demonstrated by planting one, since the
  first property is easy to satisfy by weakening the gate into silence.
- The gate states what it treats as a landing's identity, so a reader can tell a re-pin from a
  new decision.

## Assumptions made writing this

- Assuming the identity should come from the branch tip or the first-parent path rather than the
  merge commit, because those survive being carried; not proposing a specific one, since which is
  right depends on how the census walks history and that is the gate's own design.
- Assuming the row's reason text is unaffected — R27's was correct throughout and only its key
  went stale, so this is about the key alone.
