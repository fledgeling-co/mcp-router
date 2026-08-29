---
status: to-triage
found-by: N8, 2026-08-29
registry-target: none
no-target-reason: no case or defect covers `scripts/m19-red-green.py`'s crash safety — the registries record what the arms prove, not how the harness behaves when it is killed mid-arm
---

# A killed mutation run leaves its mutation behind, inside a file `git status` already calls modified

- origin: N8, measured while re-witnessing arm A10 · 2026-08-29
- audience: any runner that runs a mutation harness, and anyone who trusts a red-green log
- platforms: n/a
- proposed-by-ai: true

## What and why

`scripts/m19-red-green.py` writes a mutation into a source file, runs one test, and restores the
file in a `finally`. A `finally` does not run when the process is killed, and on this machine
processes are killed: three background runs of that harness were terminated by the agent harness
with exit 144, one of them mid-arm.

That left arm A3's mutation — `isPermittedLink` rewritten from `url.scheme?.lowercased() == "https"`
to `url.scheme != nil` — sitting in `app/Sources/MCPRouterKit/Markdown/MarkdownInline.swift`. The
file was **already** modified by this branch for an unrelated doc-comment change, so `git status`
reported exactly what it had reported all along: one `M`. A second leftover, arm A8's, landed in a
file the branch does not touch and was visible immediately; this one was not.

Three subsequent measurements were taken against that tree and all three were wrong. The
counter-measurement this item depends on inverted: a guard that must SURVIVE a mutation was
recorded as going red, because the poisoned `isPermittedLink` accepted every scheme. It took a
standalone probe disagreeing with the in-suite result to find it, and the disagreement was the only
signal — every individual run was internally consistent and exited cleanly.

The general shape is worth naming: **a mutation harness's blast radius is invisible in a working
tree that is legitimately dirty**, which is every worktree a runner works in.

## Acceptance sketch

- The harness cannot leave a mutation behind a kill: it records what it is about to change and where
  before changing it, and any invocation refuses to start while a prior record is outstanding.
- A runner can ask "is this tree poisoned" and get an answer that does not depend on reading a diff
  by eye — a hash of every file the ARMS table names, taken before the first arm and checked after
  the last.
- Two concurrent runs of the harness against one worktree refuse rather than race; the first
  symptom here was two runs interleaving into one log and reporting `NO CONTROL` on arms that were
  fine.
- The same question is asked of `scripts/red-green.py` and any other harness in this repo that
  writes to tracked source, rather than fixing the one that was caught.

## Assumptions made writing this

- Assuming a lock plus a pre-run manifest is the shape, rather than making runs copy the tree: the
  harness already depends on building in place, and a copy would change what is measured.
- Assuming this is not the same item as the `--only` addition N8 made to the harness. That made a
  subset watchable in one window, which is why the kills stopped happening; it does nothing about a
  kill that does happen.
