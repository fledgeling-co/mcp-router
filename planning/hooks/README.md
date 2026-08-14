# Fleet hooks — scaffolding for a run, not repo policy

`.git/hooks/` is not tracked, so these live here and are installed by hand. A fresh
orchestrator session resuming from `ORCHESTRATOR.md` must reinstall them, or the fleet runs
without the only controls that have actually held:

```sh
cp planning/hooks/pre-push planning/hooks/pre-commit .git/hooks/
chmod +x .git/hooks/pre-push .git/hooks/pre-commit
```

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
