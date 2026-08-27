---
status: completed
shipped-by: b9ceec6
kind: inventory — not a migration plan
prepared-for: the armada conductor's request, 2026-08-23
constraint: rotation and any config change are the owner's, not this fleet's
---

# Which upstreams hold a credential at rest, and what Warden could actually serve

**Inventory only.** No credential value is reproduced here, and none was printed while producing it —
the reader below reports key names, lengths and shapes and never a value. Nothing in this file is a
step to take; rotation and config changes are the owner's.

## The file

`~/.claude/mcp-router/servers.json`, mode **0600**, 5,362 bytes. **21 upstreams, 9 holding a
credential, 15 distinct secret entries.**

| upstream | transport | entries |
|---|---|---|
| `atlas-admin` | http/sse | `headers.Authorization` — Bearer, 57 chars |
| `diolog-admin` | http/sse | `headers.Authorization` — Bearer, 73 chars |
| `diolog-tasks` | http/sse | `headers.Authorization` — Bearer, 72 chars |
| `dossier` | stdio | `GEMINI_API_KEY` 53 · `PERPLEXITY_API_KEY` 53 · `OPENAI_API_KEY` 164 · `XAI_API_KEY` 84 |
| `google-search` | stdio | `GEMINI_API_KEY` 53 |
| `media-gen-pro` | stdio | `AI_GATEWAY_API_KEY` 60 · `GEMINI_API_KEY` 53 · `OPENAI_API_KEY` 164 |
| `namecheap` | stdio | `NAMECHEAP_API_KEY` 32 |
| `ref-tools-mcp` | stdio | `REF_API_KEY` 24 |
| `yt-transcript` | stdio | `AI_GATEWAY_API_KEY` 60 · `GEMINI_API_KEY` 53 |

**One false positive, declared**: the reader's length heuristic also flagged `dossier`'s `env.PATH`
(169 chars, no spaces). It is not a secret and is excluded from the 15.

**`GEMINI_API_KEY` at 53 chars appears in four upstreams** and `OPENAI_API_KEY` at 164 in two, so the
distinct-secret count is lower than the entry count — a rotation touches more entries than it does
credentials.

## What Warden could serve: as things stand, none of the nine

Not a capability gap in Warden. A **structural mismatch in the consumer**, and it is worth stating
before any migration is costed.

Warden is a menu-bar broker granting **one authorised, scope-limited grant per agent session**, sealed
by the Secure Enclave and **automatically revoked on screen lock or sleep**. Its consent step is a
Touch ID sheet answered by a person.

What consumes these credentials is **not an agent session**:

- `gg.rhodes.mcp-router` is a **loaded launch agent** — measured, PID 1994. It has no session and
  cannot answer a consent sheet.
- `buildEnv` runs **on every spawn** (`src/pool.ts:62`), and spawns are **lazy** — *nothing is spawned
  until a tool is called* (`:136`). So a credential read happens at an arbitrary moment chosen by
  whichever agent called a tool, inside a daemon, with no interactive context.

**So the failure mode of a naive migration is precise**: an agent calls a tool → the router spawns →
`buildEnv` asks Warden → the screen is locked, or no grant was ever authorised for a daemon → the
tool call fails, and it fails at the moment of use rather than at configuration time.

## What each of the two transports would actually break

**stdio (7 of 9, 12 entries).** The env is copied at `exec`, so an already-running child survives a
lock. What breaks is **every respawn** — and respawns are lazy and routine. The observable change is
that *starting a server becomes interactive*, intermittently, depending on whether the machine was
locked since the last grant.

**http/sse (3 of 9, the three Bearer tokens).** Worse, because the header goes on **every request**
and there is no exec-time grace. A lock mid-session breaks the next call rather than the next start.
These are also the three whose credentials are Bearer tokens with their own lifetimes, so a broker
would be brokering something that can independently expire.

## What would have to exist first

Stated as questions rather than as a plan, because each is a decision:

- **A non-interactive grant for a daemon**, which is the thing Warden's design deliberately does not
  have — its value is that a grant is short-lived and lock-revoked. A daemon-shaped grant may be a
  different product rather than a setting.
- **Or the credential moving to the caller**, so the agent session that already has a Warden grant
  supplies it per call. That changes the router's contract: `command`, `args` and `env` are **never
  writable through the control API** by standing constraint, and this would put a credential on the
  wire between the app and the router — which the loopback-only boundary was drawn to avoid.
- **Or Warden serving at install time only**, which is `servers.json` again with extra steps.

## What is genuinely better today, and what is not

The recorded improvement is real and worth keeping in proportion: a live third-party key sat in
`~/.claude.json` in plaintext, that entry was a duplicate of a router upstream, and removing it leaves
the credential only in `servers.json` at 0600. **A smaller blast radius and a narrower audience.**

It is **not** a fix. Fifteen entries remain secrets at rest in a config file, and a 0600 file is
readable by every process running as that user — which on this machine includes every agent CLI.

**The honest summary**: this is not half-migrated. It is one duplicate removed, with the migration
still unstarted and its precondition unbuilt.
