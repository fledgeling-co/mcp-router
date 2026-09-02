---
status: completed
registry-target: none
no-target-reason: the fix is a repository gate rather than a product surface, so no case, requirement or defect in the campaign registry observes it; the only id this brief cites, DEF-253, is egress's and is declared foreign
found-by: egress's DEF-253 shape, swept for here 2026-08-23
---

# Two executable gates `cd` into a worktree that was deleted, and one is cited by a spec

Swept for after egress rescoped the family as **"a destructive git call whose target is established
somewhere other than immediately before the call"**, and its newest find: arming scripts hardcoding
a worktree path a cleanup deleted.

**This repo has the shape. It is mitigated, and it is not harmless.**

| script | pinned path | guard | invoked by |
|---|---|---|---|
| `app/Scripts/pool-mutation-gate.sh:15` | `…/.worktrees/R2/app` | `\|\| exit 90` | cited in `planning/specs/spec-R2.md` |
| `planning/run-gate.sh:10` | `…/.worktrees/R2` | `\|\| exit 90` | nothing |

`.worktrees/R2` does not exist — `git worktree list` has no R2, the directory is gone. Both scripts
are `0755` and both are therefore **permanently dead**: every invocation exits 90 at line 10 or 15
without reaching a single check.

## What saves it, and what does not

**The `|| exit 90` is what makes this better than DEF-253.** Egress's case proceeded into whatever
repository it landed in and ran `git add && git commit -q` then `git reset --hard`; its own header
records that the reset had already destroyed a gate patch. These two fail closed instead. Neither
contains a destructive git call reachable past the `cd`.

**What is not saved is the gate.** A gate that always exits 90 measures nothing, and `spec-R2.md`
cites `pool-mutation-gate.sh` as though it were runnable. So the spec asserts a mutation gate exists
for R2's pool work, and what exists is a file that cannot run. **That is this fleet's recurring
shape one more time** — a record naming an instrument that cannot produce a result, indistinguishable
from one that can until somebody runs it.

## Why an absolute path is the slow-acting version of the fault

It was **correct when written**. `.worktrees/R2` existed, the gate ran, the spec's citation was
true. A routine worktree cleanup falsified all three without touching any of the files, and nothing
went red because nothing invokes them. **It decays with nobody touching it**, which is why an
inventory of violations is the wrong remedy — inventories rot the same way.

## The invariant to prefer, from splice

Rather than enumerating violations: **the hook runs with `GIT_DIR` and `GIT_WORK_TREE` explicitly
unset, so no descendant can inherit them whatever it invokes.** One line, survives dependency
updates, and it demotes the inventory to a diagnostic. That does not fix these two scripts, but it
is the right shape for the family they belong to.

## Scope

- Decide per script: derive the path (`git rev-parse --show-toplevel`, or the caller's cwd), or
  delete it. `run-gate.sh` is referenced by nothing and is the easier call.
- **Fix `spec-R2.md`'s citation either way.** A spec citing an unrunnable gate is the defect
  regardless of what happens to the script.
- Add the `GIT_DIR`/`GIT_WORK_TREE` unset to the pre-commit hook, per splice.
- **Sweep the other four files carrying absolute paths** — `planning/fleet-runner.js`,
  `planning/watch-fleet.sh`, and the two campaign capture scripts. None pins a worktree, so none is
  this shape, but `watch-fleet.sh` pins a `~/.claude/projects/…` session directory, which decays the
  same way.

**Not filed as urgent**: nothing is destructive and nothing is silently wrong at runtime. Filed
because a spec cites an instrument that cannot run, and because the sweep that found it was one this
session had scoped too narrowly the first time.


---

**RETIRED 2026-08-27, recorded here rather than deleted, and the frontmatter is the retirement.**

The work landed and was graded. `pool-mutation-gate.sh` and `planning/run-gate.sh` derive the
repository root through `git rev-parse --show-toplevel` instead of pinning `.worktrees/R2`;
`planning/runnable-path-gate.py` is a `lint:` recipe step rather than a target, which is what makes
it visible to the goal's lint reader; the pre-commit hook refuses `GIT_WORK_TREE`; and the control
arm that could not fire now returns a full result and exits 2 on all three plants. Merged to `main`
at `5ed60f6`, verified in fresh context by an agent that did not write the closing commits.
`planning/features-to-triage/LEDGER.md` carries the full account.

**Why this brief needed retiring rather than citing.** It sat in the reckoning's `unbuilt` class —
*somebody wrote down what should exist and it is not there* — for a shipped, verified item. The
cause was the one id it cites: `DEF-253` is **egress's** defect, named here as prior art for the
shape (a destructive git call whose target is established somewhere other than immediately before
it). `planning/target-resolution-gate.py` already declares that registry foreign and
`brief-target-gate.py` classes this brief `FOREIGN_ONLY`, so both gates read it correctly; `reckon`
joins on citations alone and had nothing else to join to, so the brief could never leave the
remaining set however much shipped. That is exactly the mechanism
`a-brief-that-names-nothing-cannot-be-retired.md` describes, and this is the specific brief it is
about.

**Not settled by this retirement.** The G9 ledger row records two residuals that are still open and
belong to their own items rather than to this one: the 40-file absolute-path sweep, and the fact
that `planning/hooks/pre-commit` is tracked but deliberately **not installed** on this machine —
`install.sh --check` reports DRIFTED by design, and installing it is the orchestrator's call
because `.git/hooks` is shared by every worktree.
