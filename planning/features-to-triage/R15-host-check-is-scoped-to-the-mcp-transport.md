# R15 — the Host check guards `/mcp` and nothing else

**Status:** Untriaged · security
**Found:** 2026-08-21, by the xAI review lane on R14, confirmed by measurement against the running router

## The finding

DNS-rebinding protection is applied **inside the MCP transport**, not in the dispatcher. So it
guards `/mcp` and no other route. Measured against the router running right now
(`node`, pid 98273, port 8879):

```
/health        Host: evil.example -> 200   {"ok":true,"upstreams":13}
/status        Host: evil.example -> 200   port, idleMs, children[]
/servers       Host: evil.example -> 200   13 entries
/usage         Host: evil.example -> 200   200 records
/mcp           Host: evil.example -> 403   Invalid Host header
```

Swift: `MCPEndpoint.swift:150` — the check sits in `MCPEndpoint.respond`, which
`RouterServiceDispatch.respond` reaches only after `/health`, `/status` and the control block
have already answered. TypeScript reference: `src/router.ts:274` passes
`enableDnsRebindingProtection: true` with `allowedHosts` to the **transport**, so the reference
scopes it identically. Both implementations, same shape.

The lane's words, which is how this was found: *"that check currently lives **only** inside the
`/mcp` transport … Well-known, DCR, `/authorize`, and `/token` inherit none of it."* It was
raised as a constraint on the routes R14 would add; it is already true of the routes that exist.

## What is exposed

A page the user visits, on a domain whose DNS re-resolves to `127.0.0.1`, becomes same-origin
with the router and can **read** these responses. It sends `Host: attacker.com`, which `/mcp`
refuses and everything else accepts.

| route | discloses |
|---|---|
| `/usage` | 200 records of `server`, `tool`, `ts`, `ms`, `ok`, `cold` — what was called, when, and how it went |
| `/servers` | 13 entries with `command`, `args`, `envKeys`, `projects`, `auth`, `hash`, `state` |
| `/status` | port, idle window, the names of running child processes |
| `/health` | upstream count |

`/servers.projects` names the user's project directories. `args` carries filesystem paths.

**`envKeys` is variable *names* only** — `REF_API_KEY`, not its value. Verified rather than
assumed, because the difference decides what this is: reconnaissance, not a credential leak.
No token, no key value and no upstream credential is served by any of these routes.

Severity: **information disclosure, not takeover.** These are GETs. The attack needs the user
to visit an attacker-controlled page, and the attacker to control DNS with a short TTL and
defeat the browser's DNS pinning. It is not remote code execution and it does not reach the
upstream tokens. It does hand over a usage history, a project list, and the full command line
of every configured MCP server.

## Fix

Move the authority check ahead of the dispatch ladder in `RouterServiceDispatch.respond`, so
every route inherits it, rather than leaving each route to opt in. `MCPEndpoint`'s
`allowedHosts` already computes the right set — `cfg.host:port` plus the three loopback
spellings — and `[::1]` should be confirmed present.

Keep `/mcp`'s existing behaviour byte-identical: it answers `403 Invalid Host header: <host>`
as a JSON-RPC error, and the reference's wording is pinned by a parity row. A dispatcher-level
check must produce the same bytes for `/mcp` while giving the other routes an ordinary `403`.

## Why this is its own item and not part of R14

R14 adds routes that would inherit the gap. This is the gap. Fixing it is a precondition for
R14 rather than a part of it, and it stands on its own even if R14 is never built — the
disclosure above exists today, in the shipped product, with no OAuth anywhere near it.

## Acceptance

1. Every route — `/health`, `/status`, the control block, `/mcp`, and any route added later —
   answers 403 to a `Host` that is not the bound authority or a loopback spelling.
2. `/mcp`'s 403 body is byte-identical to today's and the parity row still passes.
3. The check is in the dispatcher, so a route added without touching it is covered by default.
   Arm that: add a throwaway route in a test and assert it refuses a foreign Host with no
   per-route code.
4. `[::1]` is in the allowed set.
5. A parity row covers the new dispatcher-level behaviour against the TypeScript reference, or
   the reference moves with it and the divergence is recorded.
