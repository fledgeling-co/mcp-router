---
status: to-triage
found-by: the 2026-08-28 directive that the router become the sole home for every extension
---

# R28 — The router owns skills, plugins and marketplaces, not just MCP servers

- origin: owner directive, 2026-08-28
- audience: whoever installs an extension and wants one place it lives
- platforms: n/a
- proposed-by-ai: false

## What and why

The router is already the single place MCP servers live: the user scope holds one entry, `router`,
and it fronts 21 upstreams. Nothing equivalent exists for the other three kinds of extension.
Measured on this machine today, they live in four places Claude owns directly:

| kind | where it lives now | count |
|---|---|---|
| skills | `~/.claude/skills/` | 23 |
| marketplaces | `~/.claude/plugins/marketplaces/` | 7 |
| plugin versions | `~/.claude/plugins/cache/` | 12 |
| which plugins are on | `~/.claude/settings.json` → `enabledPlugins` | — |
| which marketplaces are known | `~/.claude/settings.json` → `extraKnownMarketplaces` | — |

The control API has `/servers`, `/servers/:name` and `/status` and nothing else, so there is no
surface to register a skill against, no inventory that spans the four kinds, and no single answer to
*what is installed*.

This is the foundation the rest of the goal stands on: propagation, ingestion and cache
invalidation all need one authority to propagate FROM, and there is not one yet.

## Acceptance sketch

- The control API can list, add and remove a skill, a plugin and a marketplace, the way it already
  does a server.
- One request answers what is installed across all four kinds.
- The router holds the authoritative copy; Claude's directories become something it writes rather
  than something a person edits.
- Removing an extension through the router removes it everywhere it was written.
- The existing `/servers` behaviour is unchanged — this adds kinds, it does not re-model the one
  that works.

## Assumptions made writing this

- Assuming the router stores extensions rather than symlinking Claude's directories, because the
  goal includes removing them from Claude, and a symlink to a directory that must not exist is a
  contradiction.
- Assuming `enabledPlugins` and `extraKnownMarketplaces` stay in `settings.json` as the file Claude
  reads, with the router owning their content rather than replacing the mechanism.
