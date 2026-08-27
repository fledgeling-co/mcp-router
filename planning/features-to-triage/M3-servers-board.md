---
status: completed
shipped-by: 3b11f33
---

# M3 — Servers: the breaker board

**Depends on:** M1.

The app's signature surface. One breaker per declared server, live.

- The board: breaker, name, state subtitle, transport, tools, calls, errors, last used,
  and a per-row action that changes with state (Reset when tripped, Review… when a
  schema is held).
- The inspector: full config, the per-project scoping list, the tool inventory, the
  held-description diff, and the eval result.
- Actions: add server, remove (undoable, never confirmed), reset, toggle warm, scope to
  a project.
- **State correctness is the thing that failed twice in the prototype.** Warm implies
  running; the reaper skips warm; a warm server never shows a reap countdown. The
  subtitle branches on warm before running.

Deep link: `?only=mac&pane=servers`.
