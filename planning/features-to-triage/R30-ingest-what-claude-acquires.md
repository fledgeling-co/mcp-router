---
status: to-triage
found-by: the 2026-08-28 directive, on the half that keeps the router authoritative over time
---

# R30 — Ingest what Claude acquires, so the router stays the only source

- origin: owner directive, 2026-08-28
- audience: whoever installs a plugin the normal way and expects the router to know
- platforms: n/a
- proposed-by-ai: false

## What and why

R28 makes the router the authority. Nothing keeps it authoritative: a plugin installed through
Claude's own commands lands in `~/.claude/plugins/` and `settings.json` knowing nothing about the
router, and from that moment the two disagree. A single source of truth that only holds while
nobody uses the other door is not one.

So new extensions acquired by Claude are extracted into the router and removed from Claude, leaving
the router's copy as the only one.

**This is the half that can destroy something.** It moves files the user did not ask it to move, and
it edits `settings.json`, which holds `enabledPlugins` and `extraKnownMarketplaces` for every
project on this machine. An ingestion that mis-identifies a directory removes a working extension.

## Acceptance sketch

- A skill, plugin or marketplace that appears in Claude's directories is registered in the router.
- After ingestion the router's copy is the only one, and the extension still works.
- Nothing is removed from Claude until the router's copy is readable and complete — the order is
  copy, verify, then remove, never remove-then-copy.
- An extension the router cannot identify is reported and left alone rather than moved on a guess.
- The removal is reversible from the router without re-downloading anything.
- Ingestion never runs against a directory a person is editing.

## Assumptions made writing this

- Assuming ingestion is triggered rather than continuous to begin with, because a watcher that moves
  files under a running session is a larger risk than a command that does it at a known moment.
- Assuming `settings.json` is edited by a writer that preserves everything it does not own — it
  carries hooks, permissions, model settings and env for this machine, and a rewrite that drops a
  key it did not understand is worse than the drift it fixes.
