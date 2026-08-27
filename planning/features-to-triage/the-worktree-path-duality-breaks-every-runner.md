---
status: to-triage
found-by: P9's runner, 2026-08-27, after ~60 errors that read as a TypeScript defect
---

# `.worktrees` resolves two ways, and both failures read as source errors

- origin: Wave B, reported by a runner as a finding outside its scope · 2026-08-27
- audience: whoever loses an hour to it next
- platforms: n/a
- proposed-by-ai: false

## What and why

`/Users/lukerhodes/Dev/mcp-router/.worktrees` is a symlink to
`/Volumes/LLMs/Dev/mcp-router/.worktrees`. So every worktree has two spellings of its own path, and
two separate toolchains resolve them differently. Neither failure names the symlink.

**`node_modules` disappears.** A worktree's `node_modules` symlink points at `../../node_modules`.
The OS resolves that physically, to `/Volumes/LLMs/Dev/mcp-router/node_modules`, which does not
exist. `npm run build` then emits roughly sixty `Cannot find module 'node:os'` and
`Cannot find name 'process'` errors — the shape of a broken `tsconfig`, not of a missing directory.
Any runner needing `dist/` in a worktree hits this.

**The Swift module cache is poisoned.** `make parity` run once from `/Users/…` and once from
`/Volumes/…` gives `module '_DarwinFoundation1' is defined in both …/Users/… and …/Volumes/…`,
holding two spellings of one `.pcm`, and then `clang: Segmentation fault: 11`. A segfault from the
compiler is the last thing anyone reads as a path problem.

Both cost real time this evening before the cause was found, and both will recur for every runner
that builds in a worktree, because nothing about either message points at the cause.

## Acceptance sketch

- A runner building in a worktree gets a working `node_modules` without repairing a symlink first.
- The two spellings of a worktree path cannot both reach the same module cache.
- Where the duality cannot be removed, the failure names it — a runner meeting one of these
  messages is told the cause rather than diagnosing sixty type errors.
- The check runs before a build rather than explaining one afterwards, since it costs nothing.

## Assumptions made writing this

- Assuming the volume layout is deliberate (the repository is on an external volume with a symlink
  from `~/Dev`) and the fix belongs on this side rather than moving the repository.
- Assuming an absolute `node_modules` symlink is a workaround rather than the fix, since it is what
  the runner did to get moving and it is not committed.
