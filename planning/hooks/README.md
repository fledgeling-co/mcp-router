# Fleet hooks — scaffolding for a run, not repo policy

`.git/hooks/` is not tracked, so these live here and are installed. The tracked files are the
source of record; `.git/hooks/` holds derived copies. A fresh clone, or a fresh orchestrator
session resuming from `ORCHESTRATOR.md`, must install them, or the fleet runs without the only
controls that have actually held:

```sh
planning/hooks/install.sh           # install both, then print each sha256
planning/hooks/install.sh --check   # is what is installed still what is tracked? exit 1 if not
```

`--check` is the half that used to be missing. The `cp` line this replaces told a fresh clone how
to install and gave it no way to find out afterwards whether it had worked, so an edited tracked
hook and a stale installed copy looked identical from outside — a control believed armed with
nothing checking, which is the shape `G9` exists for. The installer derives the repository root
and resolves `--git-common-dir`, so it installs once for the main checkout and every worktree.

Run it from the orchestrating session: `.git/hooks` is shared by every linked worktree, so
installing from inside one changes the controls under every runner in flight.

`planning/hooks/prove-pre-commit.sh` re-runs the pre-commit proof — six directions and two
presence controls, in throwaway repositories, never touching this one.

Both defer to `MCPR_ORCHESTRATOR=1`. The orchestrator sets it on its own merges and pushes;
nothing else should.

**Delete both when the fleet finishes.** They exist because runners write to `main` — twice on
record — and outside a fleet they are just friction.

## Why they exist, and what each one learned

`pre-push` — a runner committed a correct `.gitignore` change to `main` in the shared checkout
and pushed it. Every runner prompt already forbade that, so the instruction is not the control.

Its first version then **named its own bypass in the refusal text** ("if you are the
orchestrator, set MCPR_ORCHESTRATOR=1"), a runner read that and pushed again. A control that
publishes its key in the error the unauthorised party is guaranteed to read is not a control. The
variable is unchanged; the message no longer mentions it.

`pre-commit` — the hook above blocks pushes, not commits, so the second runner still landed a
commit on `main`, sweeping up an edit the orchestrator was midway through making. This refuses a
commit on `main` **in the main checkout only**: runners must commit freely on their own branches,
so it exits early when `git rev-parse --git-dir` reports a worktree path
(`.git/worktrees/<name>`) rather than `.git`.

Proved in four directions before being trusted: refused on `main` in the main checkout, allowed
for the orchestrator, allowed for a runner committing inside its own worktree, and the push
refusal verified to contain no mention of the variable.

Those four were a one-off nobody could re-run. `prove-pre-commit.sh` re-runs them and adds the
two they missed, both measured 2026-08-26 under `G9`:

**`GIT_WORK_TREE` was a bypass.** Git runs a hook standing in the work tree, and `GIT_WORK_TREE`
moves the work tree without moving the commit. Committing from the main checkout with it aimed at
any linked worktree put the hook's cwd inside that worktree while the commit still landed on
`main` — the exact thing this refuses — and a cwd-derived `git rev-parse --git-dir` read
`.git/worktrees/<name>`, called it a runner and let it through. The hook now reads
`git rev-parse --absolute-git-dir`, which answers from the environment git set up for the commit
and so names the repository the commit is going to. The presence control reconstructs the old
cwd-derived hook and requires it to allow the bypass; if it refuses, the direction proved nothing
and the script exits 2.

**`GIT_DIR` and `GIT_WORK_TREE` are now unset**, for a different fault with a different remedy.
Git exports `GIT_DIR` for every commit inside a linked worktree — every runner commit here — so
anything the hook invokes would carry that git dir into whatever directory it walked into and
operate on the runner's repository rather than the one it was standing in. Measured both ways: a
child standing in an unrelated repository resolved the committer's git dir without the unset, and
its own with it. The unset does *not* close the `GIT_WORK_TREE` bypass — that one is carried by
the cwd, not by the variable. Two faults, two lines, and the invariant is preferred to an
inventory because it holds for whatever this hook is asked to invoke next.

One case is an expected allow, recorded so nobody later "closes" it: with `GIT_DIR` aimed at a
worktree git redirects the whole commit there, so it lands on `runner` rather than `main` and
there is no commit on the integration branch to refuse.
