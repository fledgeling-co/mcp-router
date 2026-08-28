---
status: to-triage
found-by: measuring Claude Desktop against Claude Code, 2026-08-28
---

# R32 — Claude Desktop takes the config but has no live reload, and that gap is structural

- origin: owner directive, 2026-08-28 — the half of "Claude Code and Claude Desktop" that does not work the same way
- audience: whoever expects Desktop to follow the router the way a terminal session can
- platforms: n/a
- proposed-by-ai: false

## What and why

The two clients are not symmetrical and the goal reads as though they are.

**The easy half.** `~/Library/Application Support/Claude/claude_desktop_config.json` exists, is
1,441 bytes, and its `mcpServers` block is **empty** — the router is not registered with Desktop at
all. Writing it there is a small change, and it is the one that makes Desktop share the pool.

**The half that does not exist.** Every Claude Code session owns a socket at
`/tmp/cc-socks/<pid>.sock` and can be reached while running. Desktop has no such socket. It is a
different application with a different lifecycle, and nothing measured today offers a way to make a
running Desktop re-read its MCP configuration. R29's mechanism does not reach it.

So Desktop can be made to use the router, and cannot currently be made to notice a change without
being restarted. Restarting it is not a thing this system should do on its own: it is the owner's
foreground application and it may be mid-conversation.

The value of this brief is the boundary. A goal that says *update both clients automatically* is
achievable for one of them, and stating which is worth more than a mechanism that half-works
silently.

## Acceptance sketch

- Desktop is registered with the router, so it uses the same pool as every terminal session.
- A change that Desktop cannot pick up without a restart is reported as exactly that, to somebody
  who can decide, rather than propagated and assumed.
- Nothing restarts Desktop without being asked.
- If a live-reload path for Desktop is found, it is measured before it is relied on — the same way
  Claude Code's was.

## Assumptions made writing this

- Assuming Desktop's restart is the owner's to perform, since it is a foreground application with
  conversation state that a restart discards.
- Assuming registration and reload are separable, so the first can ship while the second stays open.
