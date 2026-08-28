# R29: push a reload to live sessions

**Category:** router · **Brief:** `planning/features-to-triage/R29-push-a-reload-to-live-sessions.md`
**Related:** R32 (Claude Desktop has no live reload) — this spec settles what R32 inherits.

The brief asked one question before anything was built: *is there any programmatic way to make a
live session re-read, or does it strictly require the slash command?* It is settled, and the
answer inverts the brief's conclusion for one of the two halves.

---

## 1 · What was measured

All of §1 was taken on **2026-08-28** on the author's machine. Nothing in it was taken against
another person's live session; §1.2 and §1.3 ran against a fixture MCP server on port 8977 and a
`claude -p` session started for the purpose, both created and owned by this item.

### 1.1 · Nothing is watching config, and the socket transport only asks

Restated from the brief, and confirmed against the shipped `claude` 2.1.250 binary rather than
against behaviour:

- A live `claude` process holds zero open file descriptors under `~/.claude`.
- Every session registers `~/.claude/sessions/<pid>.json` carrying `messagingSocketPath`,
  `sessionId`, `procStart` and `status`, beside a 0600 `<pid>.<sha256>.key` holding a `peerToken`.
- The binary documents its own inject form: an `auth` line then a `user` line, newline-delimited
  JSON over the unix socket.
- **A message enqueued from that socket is enqueued with `skipSlashCommands` set.** So a pushed
  `/mcp reconnect` is text and does not execute — not merely "a model decides what to do with
  it", but "the harness will not run it as a command even if the model emits it". This is the
  sharpest statement of the brief's finding and it is a property of the receiver, not a
  convention.

That half therefore **asks**. It cannot tell.

### 1.2 · The MCP protocol's own reload exists, works, and needs no model

`notifications/tools/list_changed` is in the client. The binary carries
`Received tools/list_changed notification, refreshing tools`.

Measured end to end against a fixture server holding a standalone `GET /mcp` SSE stream, with a
`claude -p` session mid-turn inside a 25-second `sleep`:

| t | event |
|---|---|
| 02:37:22.548 | client opens `GET /mcp`; the standalone SSE stream is held |
| 02:37:22.549 | `tools/list` #1 answered with **1** tool |
| 02:37:32.121 | fixture pushes `notifications/tools/list_changed` down the stream |
| 02:37:32.124 | `tools/list` #2 arrives unprompted, answered with **2** tools |

`planning/evidence/R29/exp-A-session-id-sent.log`. **Three milliseconds, mid-task, no person, no
model in the loop, no slash command.** The session was inside a tool call at the time and was not
disturbed by it.

Re-run with the `mcp-session-id` response header suppressed — which is what a stateless server
returns — and the result is identical (`exp-B-session-id-suppressed.log`). So the session id is
not the discriminator, and a stateless server is not excluded on that ground.

### 1.3 · The router already holds the stream it never uses

`curl -N -H 'Accept: text/event-stream' http://127.0.0.1:8879/mcp` against the live router
returns `200` with `content-type: text/event-stream` and holds the connection. Every attached
session already has this stream open — the shutdown comment records the consequence from the
other side: `An MCP client holds its connection for the whole session`,
`src/router.ts:471` at `bb3359a`.

The router never sends anything down it, and keeps no reference to it. Each request builds a
fresh transport — `Stateless: a transport and server per request`, `src/router.ts:409` at
`bb3359a` — and `res.on('close')` discards it. **That is the entire gap.** It is not a protocol
limit, not a client limit, and not the session id.

---

## 2 · What this builds

Two mechanisms, because they reach different things, and the difference is the deliverable.

### 2.1 · The tool list — the router tells (primary)

Keep a registry of the open standalone `GET /mcp` SSE streams. When the served tool list changes,
send `notifications/tools/list_changed` to every one of them. Fired from the control API on the
mutations that change tools, and from a manifest-mtime watcher so the `mcpr index` and launchd
paths are covered too.

Reaches: every attached session, busy or idle, within milliseconds. Requires nobody.
Does not reach: a session with no stream open, and anything that is not the MCP tool list.

### 2.2 · Skills, plugins and anything else — the router asks (secondary, default off)

The socket push from §1.1, carrying a message that names what changed. It reaches the session's
inbox; it drains at the receiver's next tool round; the receiving model reads it as text and
decides. `/reload-skills` and `/reload-plugins` have no protocol equivalent, so this is the only
lever for them, and it is an ask.

**Default off.** Enabled by `notifySessions` in `servers.json`. A router that pushes text into
every live session on the machine by default is outward-facing on somebody else's turn; the
reversible default is the one that does not. `--dry-run` prints who it would reach and sends
nothing.

---

## 3 · Boundaries, stated rather than implied

- `list_changed` carries **no payload**. The protocol has no field for what changed, so the
  brief's *"the push names what changed"* is met by the §2.2 message and not by §2.1. §2.1 tells
  the client to re-fetch; the client discovers the difference itself.
- A session that is not attached to the router has no stream, and is not reached by §2.1. It is
  reported as absent, not as a failure.
- §2.2 delivers to an inbox. `delivered` is the outcome it reports, never `reloaded` — the router
  has no way to observe whether the receiving session complied, and a name that implies otherwise
  would be the fabricated number this repo does not ship.
- Claude Desktop has neither mechanism: no `cc-socks` socket, and it is not attached to the
  router. R32's boundary stands unchanged.

---

## 4 · Assumptions

- **Assuming §2.1 is the primary path and §2.2 the fallback**, against the brief's assumption that
  the socket is the transport. The brief made that call before §1.2 was measured and asked for it
  to be settled first. The losing option — socket only — is better at naming what changed and at
  reaching non-MCP state, which is why §2.2 is built rather than dropped.
- **Assuming §2.2 ships default-off**, against default-on. Default-on is better at meeting the
  acceptance sketch literally on a fresh machine; it is worse at every other moment, because the
  cost lands in somebody else's session.
