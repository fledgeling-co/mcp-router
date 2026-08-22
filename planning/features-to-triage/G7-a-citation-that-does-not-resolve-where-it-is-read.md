---
status: to-triage
found-by: lukerhodes-2f, 2026-08-23
---

# A citation that resolved when written and does not resolve where it is read

Split out of `G6` on that item's own coupling test. `G6` is about whether an **artifact**
survives; this is about whether a **pointer** resolves. Neither fix helps the other and neither
displaces the other, which is why they are two items — the full argument is at the foot of
`G6-evidence-that-lives-in-tmp-is-not-evidence.md`.

## The third axis: a citation that resolved when written and not where it is read

Found 2026-08-23 by `lukerhodes-2f`, which had made the error itself and reported it unprompted.

`/tmp` paths rot **in time**. Bare line numbers rot **across revisions**, and the failure looks
identical to whoever lands on them: a pointer into nothing, indistinguishable from evidence that
was never gathered.

The measurement. Gap-fix 3's verdict cites its blocker as `G5.md:159`. That is **correct at
`a9603e5`**, the base gap-fix 3 worked from and the frame `D-g5-d`'s own ten citations use. It
becomes `:170` at `43b44a2` and stays there. Both the recovery session and this orchestrator
independently declared it "not revision drift" after checking `43b44a2`, `3e63811` and the
worktree — **three frames, all on the same side of the edit.** Three concordant readings from
one side of a change are one reading, and ruling out drift on that basis is an absence check
with no presence control, which is a guard this document set already ships.

It is systemic rather than incidental: **six of `D-g5-d`'s ten citations fail the same way**, and
gap-fix 3's own verdict carries `:159` bare in its opening sentence, its arm-4 paragraph and its
work order — the three places a reader acts.

**The fix is not renumbering, which would hide it.** A number chased to the current revision is
correct until the next edit and carries no way to tell. Carry the frame — `G5.md:159` at
`a9603e5` — and the pointer stays checkable from either side. Where a frame is impractical, quote
the phrase relied on, which this repo already requires of cross-file citations for exactly this
reason.

So this item now has three axes and one root: **a record's pointer must resolve where it is
read, not merely where it was written.** `/tmp` fails it in time, a bare line number fails it
across revisions, and a dispatch artifact written into the subject fails it by changing what it
points at. A guard for the first two is mechanical and cheap; the argument for building it is
that two independent agents hit the third axis within an hour of writing the item about the
first.

## Scope

- Settle the form. `G5.md:159 at a9603e5` is one answer; quoting the phrase relied on is another,
  and this repo **already requires the second of cross-file citations** for exactly this reason —
  a bare `§6`-style reference is recorded as unfalsifiable. Extending that rule to line numbers
  is a small change to a discipline that exists rather than a new one.
- Sweep the existing corpus. Six of `D-g5-d`'s ten fail; gap-fix 3's verdict fails in three
  places. Nobody has counted the rest.
- Decide whether it earns a guard. A check that a cited line still holds the phrase its citer
  relied on is mechanical, and `planning/claim-sweep.py` plus
  `planning/verification/G5-gapfix-3-sweep.py` are both committed examples of the reader it
  would need.

**Do not fix this by renumbering to the current revision.** A number chased forward is correct
until the next edit and carries no way for a reader to tell — which is the defect, restated.
