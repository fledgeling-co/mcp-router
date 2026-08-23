# Marketplace Auto-Update Checker and Changelog Preview

- origin: user turn 1 directive · 2026-08-24
- audience: developers managing installed skills, plugins, and MCP servers who want seamless background update checks and changelog reviews
- platforms: mac, iphone
- proposed-by-ai: false

## What and why
Checks for updates to installed MCP servers, skills, and marketplace plugins at user-configured intervals (e.g. hourly, daily). Displays pending updates with GitHub-flavored markdown changelog diffs in the app and notifies via the menu bar status item and macOS notifications, allowing batch or selective updates.

## Acceptance sketch
- Periodic background check queries marketplace registries for version deltas on installed tools.
- Parses and renders GFM release notes and changelogs inside `CapabilityDocumentSheet` (M19).
- Surfaces update indicators on the Skills and Servers boards and the menu bar status item.
- Supports individual "Update" and global "Update All Skills" actions (M20 menu item).
- iPhone companion receives update notifications and can queue updates for Mac review.

## Assumptions made writing this
- Assuming update checks are read-only until the user approves the update.
- Assuming GitHub API or marketplace manifest is queried with local caching to avoid rate limits.
