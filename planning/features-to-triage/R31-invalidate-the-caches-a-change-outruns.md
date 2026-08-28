---
status: to-triage
found-by: the 2026-08-28 directive, on why a propagated change can still serve stale code
---

# R31 — Invalidate the caches a change outruns

- origin: owner directive, 2026-08-28 — "any cache such as npx is invalidated"
- audience: whoever updates an extension and gets the old one anyway
- platforms: n/a
- proposed-by-ai: false

## What and why

Propagating a change is not the same as the new version being what runs. Three caches sit between a
change and a call, and each can serve the old thing after everything upstream has been told:

**`~/.npm/_npx` — 2.0 GB on this machine today.** Most stdio upstreams are `npx` invocations, and
npx resolves a package to a cached tree. A version bump that npx believes it already has is a bump
that does not run.

**The router's own tool manifest.** The README states the design: the router caches `tools/list` to
disk, because learning an stdio server's tools means starting it, and that start is the cost the
router exists to remove. It is keyed on each server's command/args/env identity — so a change that
does not alter that identity does not alter the key, and the cached manifest survives it.

**Claude's plugin cache** — `~/.claude/plugins/cache/`, 12 versions today.

## Acceptance sketch

- Changing an extension through the router causes the next call to run the new code, not a cached
  copy of the old.
- Each cache is invalidated narrowly: the entry that changed, not the whole store. Discarding 2 GB
  of npx cache to update one package is a cost the next twenty starts pay.
- An invalidation that cannot be scoped says so and asks, rather than clearing everything quietly.
- The tool manifest is re-derived when the thing it describes changes, including when the change
  leaves command, args and env identical.
- Nothing is deleted that the router cannot cause to be re-fetched.

## Assumptions made writing this

- Assuming the identity key needs a content component rather than replacement, since command/args/env
  identity is what makes the cache safe to share between sessions and that property is worth keeping.
- Assuming npx invalidation is per-package, and that clearing `~/.npm/_npx` wholesale is a fallback
  with a stated cost rather than the mechanism.
