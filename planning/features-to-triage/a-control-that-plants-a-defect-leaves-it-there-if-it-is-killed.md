---
status: to-triage
found-by: the G8 runner, observed 2026-08-29 in .worktrees/L4
registry-target: none
no-target-reason: the campaign registry covers the product's surfaces and flows, not the lint chain's own hygiene. Nothing in it would go red on a control that leaves its plant in the tree, because no case observes the working tree's cleanliness after a gate runs. The evidence for this brief is the gate chain itself, and the check that would settle it does not exist yet — a runner that compares the tree's state before and after each declared control.
---

# A control that plants a defect leaves the defect in the tree if it is killed

`make lint` runs `planning/sweep-control-gate.py`, which runs the controls the registry declares.
One of them is `bash planning/evidence/M31/arm-sweep.sh`, a mutation harness: for each arm it
copies the target to `/tmp/m31.arm.$$`, applies a `sed -i ''` that re-creates a defect M31 fixed,
runs the sweep twice, and copies the backup back.

**There is no `trap`.** The restore is a straight-line `cp` after two `python3` sweeps. Any path
that leaves the script between the plant and that `cp` — a kill, a timeout, a governor, a `^C` —
leaves the planted defect in the working tree.

## What was observed

On 2026-08-29 in `.worktrees/L4`, on a machine under load, a `sweep-control-gate.py` run exited 1
reporting `acceptance-lanes selftest: 8 assertion(s) failed` (a known load flake — a clean re-run
in the same worktree minutes later exited 0). After it, `design/mcp-router-console.html` was
modified with respect to `HEAD`, and the diff was exactly the M31 plant: the
`.tb-btn.on.disabled,.tb-btn.on:disabled` selector removed and `background:` narrowed to
`background-color:`. The worktree had been clean at the start of the session and nothing else had
written to `design/`.

Individually re-running `reader-accounting.py`, `sweep-control-gate.py`, `role-intersection-gate.py`
and `acceptance-lanes-selftest.sh` afterwards left `design/` clean each time, so this is an
interrupted run rather than a reproducible write. The file was restored with `git checkout --`.

## Why it is worse than a dirty tree

The arm's own restore check compares the file's sha **before and after its own run**. A file left
in the planted state by an earlier killed run is that run's `before`, so the next run plants on top
of it, restores to it, and prints `restored … IDENTICAL`. **One failed restore is permanent and
invisible to the control that caused it** — and the file in question is the design of record, whose
rules other gates read as their oracle.

## Two things to decide at triage

1. `trap 'cp "/tmp/m31.arm.$$" "$file" 2>/dev/null' EXIT INT TERM` is the one-line version, and it
   is not obviously enough: the backup path is `/tmp`, so a reboot or a `/tmp` sweep between the
   plant and the restore loses the original outright. A backup under the repository's own scratch
   space, or `git checkout --` as the restore, both survive that.
2. More generally: **a gate must not mutate the working tree as a side effect of checking**, and
   `sweep-control-gate.py` currently runs a registry-declared control that does. Whether the fix is
   in the arm script or in the gate's willingness to run mutation harnesses as controls is the
   triage question. Nothing here checks that a declared control leaves the tree as it found it,
   which is a cheap thing for the runner to check and would have caught this at the source.
