---
status: completed
shipped-by: 7a28de8
---

# M4 — Skills and marketplaces

**Depends on:** M1.

The half of the product that is not MCP: skills and plugin marketplaces installed across
Claude Code, Claude Desktop, Codex/ChatGPT, opencode and Cursor from one place.

- Per-skill: version, marketplace, run count, last run, eval result, and **which clients
  it is installed into** as a slot row — the same skill can be live in two clients and
  absent from two others.
- Auto-update as a visible toggle, never a silent default, with update notifications and
  a changelog view per version.
- **Trust decays per version, not at install time.** A new version lands as a shadow copy
  and promotes automatically only when its capability delta is empty; a version that
  wants more than the one before it is held for review.
- Provenance warnings where an upstream owner has changed since install.
- Marketplace management: add, remove, and see what each one supplies.

Deep link: `?only=mac&pane=skills`. Artwork rules: DESIGN.md §4.
