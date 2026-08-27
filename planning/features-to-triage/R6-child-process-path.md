---
status: completed
shipped-by: 1d958b4
---

# R6 — the router hands its children launchd's PATH, and capabilities disappear silently

**Category:** router · **Found:** 2026-08-15, by measurement on the author's own machine
**Depends on:** nothing. Independent of R4-C.

## What was measured

The listening router process (`lsof -nP -iTCP:8879 -sTCP:LISTEN` → pid 89259 at the time)
runs with:

```
PATH=/Users/lukerhodes/.nvm/versions/node/v22.23.1/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
```

`~/.local/bin` and `~/.grok/bin` are **absent**. Every stdio child the router spawns
inherits that environment, so no routed MCP server can execute `claude`, `codex`,
`cursor-agent`, `grok` or `agy` — all five of which are installed and all five of which
resolve fine from an interactive shell.

## Why it matters, and why it is a defect rather than a setting

The failure is silent and it inverts into a lie about the machine.

A routed MCP server that shells out to a user-installed CLI does not error. It reports the
capability *unavailable*. Measured instance: the `dossier` research server, running as a
router child, reports "No signed-in CLI found. Any of the above would give you a
zero-API-cost research backend" and lists all five as `NOT INSTALLED` — while the same
server's own cache holds successful model probes for three of them from 18 days earlier,
when it was evidently launched with a different environment.

The user-visible consequence is a paid API call made in place of a free one against a
subscription they already hold, with the tool confidently explaining that the free option
does not exist.

This is the router's business, not the user's, for one reason: **the router's entire job is
spawning other people's programs.** An MCP server that shells out to a developer tool is a
normal MCP server, not an exotic one. A launchd agent's minimal PATH is the correct default
for a daemon that runs only its own code, and the wrong default for one whose purpose is
executing arbitrary child programs on a developer's behalf.

## What "fixed" should mean

Not simply "append `~/.local/bin`". Some candidates, in rough order of preference:

1. **Resolve the user's real PATH at install time** and bake it into the launchd plist's
   `EnvironmentVariables`, the way the installer already bakes in absolute paths. Cheap,
   inspectable, stale after the user installs a new tool.
2. **Resolve a login-shell PATH at router start** (`$SHELL -l -c 'echo $PATH'`) and merge
   it into the environment children inherit. Always current, costs one subprocess at
   startup, and is what most GUI Mac developer tools end up doing.
3. **Per-server `env` and `path` in the config**, so a server that needs an unusual binary
   declares it. Most precise, most work for the user, and it does not fix the default.

Whichever is chosen, the interesting half is the diagnostic: **a child that cannot resolve
its own `command` should be a named, surfaced error state**, not a server that starts and
then quietly reports reduced capability. That belongs on the Servers board.

## Acceptance

- The router's spawned children see a PATH containing the user's own bin directories, by a
  mechanism recorded in the spec rather than inherited by accident.
- A red-green proof: a fixture server whose `command` resolves only via `~/.local/bin`
  fails to start before the change and starts after it.
- A child whose `command` cannot be resolved surfaces a distinct, testable error rather
  than a generic spawn failure.
- Evidence recorded the way this item was found: the actual `PATH=` line from the running
  process, before and after.

## Not in scope

Whether `mcp-remote` should remain the way non-HTTP-capable harnesses reach the router.
That is the multi-harness question and it is separate — see the companion note on Gemini
CLI carrying 18 stdio entries, ten of them duplicating servers the router already fronts.
