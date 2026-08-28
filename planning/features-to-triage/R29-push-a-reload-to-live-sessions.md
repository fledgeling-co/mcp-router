---
status: to-triage
found-by: measuring the live-session control surface, 2026-08-28
---

# R29 — Push a reload to live sessions, rather than asking Claude to watch files

- origin: owner directive, 2026-08-28 — "ideally without the need to run `/reload-skills` or `/mcp reconnect`"
- audience: whoever changes an extension and does not want to restart thirteen sessions
- platforms: n/a
- proposed-by-ai: false

## What and why

**A running session does not re-read its configuration.** The router's own README records the MCP
half from measurement: *a running session fetches its tool list once at init and won't see the
change.* Measured again today from the other side — a live `claude` process holds **zero** open file
descriptors on anything under `~/.claude`, so its config is read on demand at startup and nothing
is watching it. The existence of `/reload-skills`, `/mcp reconnect` and `/reload-plugins` is the
same fact stated as a workaround.

So the goal cannot be met by making Claude notice. It can be met by the router **telling** it.

**There is a live control surface, and it is already in use.** Every Claude Code session owns a unix
socket at `/tmp/cc-socks/<pid>.sock`, registered in `~/.claude/sessions/<pid>.json`. Twenty sockets
exist on this machine right now and thirteen sessions are addressable by name. This is the transport
the cross-session messaging feature runs on, and it reaches a session that is mid-task.

That turns *"without the user running a reload"* from impossible into a delivery problem: the user
does not run it, the router does.

## The thing this brief cannot settle, and it is the whole risk

**Whether a pushed message can make the receiving session reload.** A message arrives as text in a
session's turn, and a slash command in text is not obviously executed as one — the harness is
recorded as handing a skill invocation to a run *as plain text* rather than running it. If that
holds for this transport too, the message can ask a session to reload and cannot make it. Establish
that before building on it, on a session deliberately started for the purpose. Do not test against
the thirteen live sessions on this machine: they belong to other work, and a message that lands
mid-task is an interruption somebody else pays for.

If it does not hold, the fallback is worth stating now: a reload the session performs at its next
turn boundary is still a reload nobody typed.

## Acceptance sketch

- Changing an extension in the router reaches every live Claude Code session without a person typing
  a command.
- A session that is mid-task is not corrupted by the arrival, whatever it does with it.
- A session that cannot reload says so, rather than appearing to have reloaded.
- The push names what changed, so a session reloads the kind that moved rather than everything.
- Sessions that have exited are not treated as unreachable failures — a stale socket is a normal
  condition, not an error.

## Assumptions made writing this

- Assuming the transport is the per-session socket rather than a new mechanism, since it exists,
  is authenticated per session and already carries cross-session traffic.
- Assuming a best-effort push with a recorded per-session outcome, rather than a guarantee: a
  session can be busy, and blocking the router on a client is the wrong direction of dependency.
