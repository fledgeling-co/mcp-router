# RESUME.md — standing instruction after the fleet was killed, 2026-08-14

The session driving this fleet was killed deliberately at the user's instruction. Three dynamic
workflows were still running inside it and could not be stopped any other way: workflow agents are
async tasks inside the `claude` process, not child processes, so `TaskStop` (whose ids were lost to
a context compaction), `lifeline pause` (which only gates retries of *failed* agents) and killing
OS processes all failed to touch them. Killing the session process was the only remaining lever.

Read this file, `ORCHESTRATOR.md`, and `DESIGN.md` before doing anything.

---

## Why it was killed — read this before resuming anything

The user's complaint, in their words: the runners were "testing the same exact screens and menus
over and over again", wasting their time, on an app that "is really not that complex".

They were right, and the causes were the orchestrator's:

1. **Duplicate runners.** The original wave-3 run (`wf_9ba012c9-417`) was still alive after 3.2
   hours when the orchestrator concluded it had died and launched second runners for M1, R2, R3 and
   I1. Two runners per item, same worktrees, same branches, everything done twice. One of them
   committed with `git add -A` and swept up the other's in-flight work.
2. **The gates earned rework, not quality.** M1's spec gate returned REJECT with 19 findings and
   its plan gate REJECT with 18, each triggering a full rewrite before a line of UI was written.
   R2's three gates returned 25, 17 and 19. After all of it M1 has a 37-clause spec, a plan, three
   model files and **no UI at all**.
3. **Repeated whole-app acceptance sweeps.** Three separate full Mac-shell runs in one 30-minute
   window, each driving the user's real screen through `osascript` and launching the app.

## Testing etiquette — binding on every runner from now on

The full rule is `planning/practices/UI_VERIFICATION.md` and it is already in the runner prompt in
`planning/fleet-runner.js`. The short form, in the user's own words:

> **Only test a screen when you make changes to that screen, and only test the specific screen,
> not all screens.**

Concretely:

- Changed a row, a menu item, one pane? Test that one thing. A one-line change does not re-earn a
  pass over every screen in the app.
- Changed nothing under a screen since it was last proven? **Do not test it at all.** Cite the
  existing evidence instead.
- **Never relaunch the app or boot a simulator per screen.** One launch, one pass, quit. The Mac
  lane drives the user's real screen — every launch takes over their machine.
- After a fix, re-verify only the screens the fix touched.
- Keep `planning/evidence/<ID>-acceptance.md`: one row per screen — screen · how it was verified
  (the actual command or AX path) · commit SHA · result. Append, never rewrite, and commit it.
  **Read it before testing anything.** A row whose SHA-to-HEAD diff does not touch that screen's
  files IS the evidence. This file is the only thing that survives a relaunch; without it every new
  runner repeats every check its predecessor ran, which is exactly what happened here.

This narrows repetition, never rigour. A screen never yet tested still gets tested properly, once,
and behavioural claims still need behavioural proof. Skips are reported as skips.

## State on disk — verified, not reported

Nothing was lost. Every branch below is local and unmerged; `main` is pushed and clean.

| Item | Branch | Commits | Worktree | Real state |
|---|---|---|---|---|
| F1 · F2 · F3 · R1 | — | — | removed | **Merged** into `main` |
| **R2** | `ai/r2` | 6 | clean | **READY TO MERGE.** 279 tests, 224 parity cases, lint clean, 13 mutation guards proved load-bearing, 10 behavioural tests against a real spawned child process. Gate evidence all from one clean tree at `7c45f33`. Merge this first. |
| **R5** | `ai/r5` | 4 | clean | Blocked on ONE unbuilt file: `CallbackListening` has a protocol and a test double but no production implementation (`NWListener` on loopback, no new dependency). 274 tests, 230 parity vectors, mutation-proven. |
| **R3** | `ai/r3` | 7 | 7 dirty | Control/usage/registry done, 352 parity cases. Owes: Phase D critic, P6.4 mutation gate, acceptance Phase 6. `2a1121e` was committed by a stale duplicate with `git add -A` and contains another runner's work — kept deliberately, files are correct. |
| **F4** | `ai/f4` | 2 | 3 dirty | Died twice. Mutation gate: M50–M54 KILLED, **M55 SURVIVED** (real coverage gap — no test observes the notification lost when `register` is deferred into a `Task`), M56/M57 never ran. **F4 must merge before wave 4** (M2 and M3 both read `ServerStateTracker`). |
| **M1** | `ai/m1` | 2 | 12 dirty | Spec (37 clauses), plan, `Destination`/`MenuCommand`/`ReadoutModel` + tests. **No UI shipped.** Plan phases B (SwiftUI views), C (app assembly, keyboard, restoration) and D remain. |
| **I1** | `ai/i1` | 3 | 19 dirty | Pairing surfaces, copy, phone flow partially built. Was mid iOS simulator run when killed. |

Verify each before trusting this table:

```bash
git -C ~/Dev/mcp-router log --oneline -5 main
git -C ~/Dev/mcp-router worktree list
for b in r2 r5 r3 f4 m1 i1; do
  echo "$b $(git -C ~/Dev/mcp-router rev-list --count main..ai/$b)"
done
```

## What to do next, in order

1. **Merge R2.** It is genuinely finished. Rebase onto `main`, run the gate on the *merged* tree
   (not the branch), merge, push. Serialised — one branch at a time, always.
2. **Finish R5's listener** — one file — then merge R5.
3. **Close out R3** (Phase D critic in-family, P6.4, acceptance), then merge.
4. **Finish F4** (kill M55, run M56/M57), then merge. F4 blocks wave 4.
5. **Then reconsider the pipeline for the UI items.** The orchestrator's own recommendation, which
   the user had not yet ruled on: for M1, I1 and the remaining Mac/iPhone items, **drop the
   per-item spec→gate→plan→gate→work→gap-fix→acceptance pipeline and build directly against
   `design/mocks/prototype.html`, with one test pass at the end.** The gates are producing rework
   rather than quality at this app's size, and they are most of where the hours went.

## Hazards that will bite a fresh session

- **`ai/f4` predates the hooks commit**, so its diff proposes deleting `planning/hooks/*` and
  reverting `planning/watch-fleet.sh`. Rebase before merging and take `main`'s side on those four.
- **`ai/r3` and `ai/r5` conflict structurally** in the vector registry: R3 restructures `files` into
  `coreFiles + controlFiles` and raises the floor to 352; R5 appended to the array literal and
  raised it to 230. Same lines. Resolve at the second of the two merges.
- **`.swiftformat` excludes `.worktrees`**, so any runner linting inside its worktree gets
  `0 files formatted`, exit 0, having examined nothing. R5 found 8 of 11 files needed formatting
  and 4 swiftlint violations including two force-unwraps when linting from outside. **Fix this
  fleet-wide before trusting any lint gate.**
- **`codex exec` exits 0 on a usage limit**, so a gate keyed on `$?` records a pass for a review
  that never ran. The lane is account-limited until **Aug 20** — run the three out-of-family gates
  in-family and log `codex: usage limit -> claude (downgrade)`.
- **Two git hooks are installed** (`.git/hooks/pre-commit`, `pre-push`) refusing commits on `main`
  in the shared checkout and refusing all pushes. Tracked copies in `planning/hooks/`.
  **Remove both when the fleet finishes** — they are scaffolding for a run, not repo policy.
- **A runner that messages the orchestrator ends its turn** and stays stopped until replied to.
- **lifeline holds four paused mcp-router runs.** They are dead now, but check
  `lifeline_status` and clear them so nothing retries against these worktrees.

## Open questions the user has never answered

From M1, still outstanding and genuinely theirs:

1. Offline/empty states currently ship with **no action button** — DESIGN.md §5 wants "offer to
   start it" but the control API exposes no start. Inert button, or M1 grows daemon lifecycle?
2. §8 binds `Space` to the breaker, but no start/stop operation exists — only `warm`/`idleMs`/
   `projects`/`placard`. Toggle warm, add a lifecycle endpoint, or is §8 aspirational there?
3. `⌘R` "Reset the selected server" has no exact operation; `reindex` is nearest. Equate, or M3?
4. Disabled commands read "This part of the app isn't built yet." — acceptable in a Debug build?

Also unanswered and non-blocking: Apple team ID, Developer ID identity, App Store Connect record.
Bundle ids assumed `app.fledgeling.mcprouter` and `.ios`.
