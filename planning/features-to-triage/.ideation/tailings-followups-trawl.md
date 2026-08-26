# Ideation Log: tailings follow-ups (2026-08-25)

- [kept] Pool mutation gate reports a hole and a stale mutation — measured, exit 1, and the spec cited it as clean.
- [dropped] Bulk re-read of the 20 R10 "referenced only by its own test" rows — that is `code-review`'s subject
  (duplicate/reuse), not a defect brief, and tailings routes it there explicitly.
- [dropped] The 16 R9 empty-body sites as one brief — a regex cannot tell a stub from a no-op, and the two read so
  far were both correct (a protocol requirement and a false positive). Filing 16 unread sites as work would be the
  same bulk-stamp error in the other direction. Left as `unbacked` on the tailings ledger with a per-site remedy.
- [dropped] A brief for R4 (capture identity unchecked) — already covered by `campaign-capture-catalog-audit.md`.
