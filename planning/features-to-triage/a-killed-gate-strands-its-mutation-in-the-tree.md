---
status: to-triage
found-by: R26, then hit twice while verifying its finding, 2026-08-30
registry-target: none
no-target-reason: the subject is the mutation gates' own restore discipline, and the registry holds no entity for a gate's behaviour when it is interrupted
---

# A killed gate strands its mutation in the tree, and the next `git add -A` adopts it

- origin: R26's report, reproduced immediately afterwards · 2026-08-30
- audience: anyone running `make lint` on a loaded machine, and every runner that commits with `-A`
- platforms: n/a
- proposed-by-ai: true

## What and why

The mutation gates plant a defect, run a suite, and restore the file on their own exit. That is
correct when they finish. When they are killed — a timeout, a SIGALRM, a machine under load — the
restore never runs and the mutation stays in the working tree.

Nothing announces it. The file is a normal modification, so `git status` shows it beside real
work, and a runner that commits with `git add -A` adopts it silently.

R26 reported two instances. Verifying that report, this session hit both:

- **`design/mcp-router-console.html`** carrying the fidelity gate's own plant — the
  `.tb-btn.on.disabled, .tb-btn.on:disabled` selectors deleted, so a toggled-on toolbar button
  draws its disabled state as though enabled. That is M31 and M36's defect exactly, planted on
  purpose and then left behind.
- **`docs/mcp-router-store.html`** missing its `.btn[disabled], .btn.disabled` rule entirely.

Both presented as four failing `MockButtonFidelityTests` on a tree whose only intended change was
in `ControlHandler.swift`, and the same suite passed 9 of 9 on clean `main`. The failure reads as
a regression in the work being verified, which is the expensive way to be wrong: the natural
response is to debug the innocent change.

This is the fleet's existing rule — *a gate must not mutate the working tree as a side effect of
checking* — arriving from the other side. The gate is well-behaved on the happy path, and the
guarantee it offers is exactly as strong as its exit.

## Acceptance sketch

- A gate that plants a mutation restores it even when interrupted, or leaves a marker naming what
  it changed and where.
- A tree carrying a stranded mutation is detectable without knowing which gate ran — a person or a
  runner can ask "is anything here a gate's plant?" and get an answer.
- A runner cannot adopt a stranded mutation by committing broadly; the check runs before the
  commit, not after the review.
- The four `MockButtonFidelityTests` failures reproduce from a stranded plant and pass once it is
  reverted, so the detection is watched working rather than assumed.

## Assumptions made writing this

- Assuming a trap handler on the gates is the shape, since the restore already exists and only its
  reachability is in question; not proposing which signal set, because SIGKILL cannot be trapped
  and the marker file is what covers that case.
- Assuming this is worth its own item rather than a note on each gate, because the gates that do
  this are several and the runner-side risk — `git add -A` — is common to all of them.
