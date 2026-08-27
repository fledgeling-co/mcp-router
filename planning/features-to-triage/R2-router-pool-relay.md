---
status: completed
shipped-by: a8091bb
---

# R2 — Swift router: lazy pool, relay, HTTP passthrough

**Depends on:** R1.

Port `src/pool.ts`, `src/router.ts`, `src/watch.ts` — the mechanism the product exists
for: one shared endpoint, children spawned only when a tool on them is actually called,
reaped when idle, with a warm set held under a RAM budget.

Carry across the behaviours that were tuned against real traffic rather than designed:
- The reaper skips warm servers; warm implies running.
- Schema quarantine — a server whose tool descriptions change after install is held,
  not silently accepted.
- HTTP upstreams route through the same lazy-spawn path as stdio children.
- `watch.ts` migrates new stdio entries out of client configs automatically.

Known trap: reading the HTTP request body for every POST breaks the MCP endpoint,
because a request stream can be consumed exactly once. Body reading must stay gated on
control paths only.
