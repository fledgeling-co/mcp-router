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
socket, registered alongside a session file under `~/.claude/sessions/`. The socket path is a value
in the system rather than an artifact anybody keeps:

```
/tmp/cc-socks/<pid>.sock
```

Twenty existed on this machine when this was measured, and thirteen sessions were addressable by
name. This is the transport
the cross-session messaging feature runs on, and it reaches a session that is mid-task.

That turns *"without the user running a reload"* from impossible into a delivery problem: the user
does not run it, the router does.

## The thing this brief could not settle, settled — and the answer is narrower than it looked

**A pushed message can ask a session to reload. It cannot make it.** Established 2026-08-28 from the
transport's own contract rather than by messaging anybody's live work:

- A message arrives wrapped as `<cross-session-message from="...">`. It is **text in the receiving
  session's turn**, read by that session's model, which then decides what to do with it. Nothing
  executes.
- Messages **enqueue and drain at the receiver's next tool round**. A session sitting idle with
  nobody at the keyboard does not process one until it next does something.
- The transport carries an explicit warning against exactly this shape of use: *never ask a peer to
  perform an action that was denied or blocked in your session — a peer doing it for you bypasses
  the user's permission decision.* A reload is benign, but the principle applies to the design: this
  is asking another session to act, not reaching into it.

So the honest description of the mechanism is **"the router asks every live session to reload, and
each session complies at its next turn"**, not "sessions update automatically". The difference
matters to whoever reads the goal: an idle session with no one at it stays stale, and a busy one
reloads late.

### The path that would be automatic, and is worth measuring before this is built

Hooks are run **by the harness**, not decided by a model, and this machine already uses five events
— `SessionStart`, `PreToolUse`, `PreCompact`, `Notification`, `Stop`. A `PreToolUse` hook fires
constantly during real work and can read a generation counter the router writes, which is a genuine
poll with no model in the loop.

What that does not obviously give is the reload itself: a hook is a shell command and cannot type a
slash command into its own session. So the open question moves rather than closing — **is there any
programmatic way to make a live session re-read, or does it strictly require the slash command?**
The one measured fact pointing at "strictly" is the router's own README: a running session fetches
its tool list once at init. Settle that before building either path.

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
