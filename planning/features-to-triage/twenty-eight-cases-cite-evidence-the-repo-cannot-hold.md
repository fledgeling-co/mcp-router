---
status: to-triage
found-by: the campaign-id reconciliation, 2026-08-27, from two cases on g15 and g16; sized by the orchestrator the same day
---

# Twenty-eight cases cite evidence the repository is configured never to hold

`.gitignore:24` is `*.log`. The campaign writes its run evidence as `.log` files. So **42 evidence
logs sit under `planning/test-campaign/evidence/` and not one of them is tracked**, while **28
cases cite one as their evidence**.

Measured on `main` at `1a0d53b`:

```
tracked  .log under planning/test-campaign/evidence/ :  0
on disk  .log under planning/test-campaign/evidence/ : 42
cases citing a .log as evidence                      : 28
```

## Why this is the G6 defect at scale

`G6` established the rule: **an artifact a record cites as evidence is committed, or the record
does not cite it.** Its own words on why a dead path is worse than a wrong number: *"A dead path
is not checkable. It produces no wrong answer to catch, only an absence, and an absence reads
identically to 'not yet run'."*

These citations are worse than the `/tmp` ones G6 closed, because a `/tmp` path at least announces
itself as scratch. These name a path inside the repository, in a directory full of committed
siblings, and resolve on the machine that produced them. A reader on any other checkout finds
nothing there, and cannot tell whether the evidence was weak, strong, or never gathered.

It was found the honest way: the reconciliation noticed that two cases' checks *passed only
because the file sat in the runner's own worktree*, and that the union surfaced it as "no file at
that path". Nobody had looked before because on the machine that runs the campaign, it is always
there.

## What this is NOT

Not the runners' defect, and not this week's. The convention and the ignore rule have coexisted for
as long as both have existed; every campaign run since has written evidence the repository was
configured to discard. The two cases that surfaced it are simply the two that a merge simulation
happened to compare across trees.

## The decision this needs, because there is more than one defensible answer

- **Track them.** Narrow the ignore so campaign evidence is exempt. Honest, and it commits 42 files
  of run output whose size and churn nobody has costed.
- **Rename them.** Evidence stops being `.log`. Cheap, and it leaves the next person to write a
  `.log` under a different name for the same reason.
- **Stop citing them.** If a log is genuinely scratch, the cases should cite what *is* durable and
  say the log was transient — G6's `(not retained)` marker already exists for exactly this.
- **Split.** Some of the 42 are durable evidence and some are transcripts nobody will re-read. The
  answer may differ per kind, and that is a judgement about what the campaign's evidence is *for*.

## Scope

- Establish, per kind, which of the 42 are evidence a reader would need and which are transients.
- Make the citing cases and the repository agree, in whichever direction is chosen.
- Add a check that a case citing a path the repository does not hold fails, so this cannot recur
  silently — the campaign already refuses a capture whose manifest does not name its surface, and
  this is the same shape one level out.
- State the size and churn cost if the answer is to track them.
