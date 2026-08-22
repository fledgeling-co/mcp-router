# Changelog

## 1.5.0 — 18 Aug 2026

- Reads Codex's SQLite store directly rather than shelling out.
- `--decisions` now recognises a decision recorded as a table row.
- Fixes a crash on a truncated final line, which happens whenever a session is killed.

**Capability change:** none. This version promotes itself.

## 1.4.2 — 17 Aug 2026

- Date filters honour the local timezone instead of UTC.
- Zero matches is reported as zero rather than as an error.

## 1.4.0 — 9 Aug 2026

- Grok session store added.
- Check suite grew from 11 to 12.

## 1.3.6 — 28 Jul 2026

- First release with a check suite.
