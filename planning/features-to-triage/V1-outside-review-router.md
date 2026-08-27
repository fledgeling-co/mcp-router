---
status: completed
shipped-by: 29af3eb
---

# V1 — Re-run the out-of-family review on the router items

**Source:** `review-rerun` = `rerun-the-router` (confirmed). **The note qualifies the answer and the
owner flagged it as blocking automation**, so the lane below is the owner's instruction, not a default:

> Use grok cli and grok-4.6 high for the out-of-family reviews. Codex is blocked

Lane verified by the orchestrator on 2026-08-15: `grok --model grok-4.6 -p` returned a probe string,
exit 0, binary at `~/.grok/bin/grok`, version 1.0.3.

The pipeline routes three checks out of family on purpose, because every other reviewer in it is Claude
auditing Claude. That lane hit an account limit and several items shipped on the in-family fallback,
each logged as a downgrade rather than quietly passed.

**Scope: the two router items with the weakest review.**

- **R3** — its Phase D critic **never ran at all** (codex account limit). This is the worst case in the
  repository: not a downgrade, an absence.
- **R2-W** — the watcher and the cross-process adoption protocol, reviewed in family. It is the newest
  router code and the part that runs unattended.

R5 and R2-R also shipped in family and are candidates if the first two find anything worth widening for.

**Done means:** both reviewed by grok-4.6 at high effort, every finding accepted-and-fixed or
rejected-with-a-citation, and the verdict recorded in each item's evidence file. A lane failure
(missing binary, wrong model on the wire, empty output) routes back to Opus and is logged, never
silently skipped.
