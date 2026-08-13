# M2 — Activity: the live call log

**Depends on:** M1.

The surface that answers "what is my agent actually calling?" — a live-updating log of
tool calls with session, working directory, server, tool, duration and outcome.

- Filter by session and by directory; this is the per-project ledger the router already
  keeps in `usage.ts`.
- Cold-start calls are marked, because a call that had to spawn its server is a
  different event from one that hit a warm child.
- Row height is fixed; long tool names truncate with the full value in the inspector.
- States: empty (no calls yet since the router started — say that, it is not an error),
  loading, offline.

Deep link: `?only=mac&pane=activity`.
