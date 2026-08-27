---
status: completed
shipped-by: 8686fd6
---

# P4 — Derive the manifest rows from source, and fix the directory-dependent normaliser

**Source:** `cutover` = `finish-first`.

Two defects in the harness itself, both of which make its own number untrustworthy.

`D-n` — the `cli` and `mcp` manifest rows are hand-maintained. `src/index.ts`'s ten `case` arms and
`src/router.ts`'s endpoints are mechanically extractable, and until they are, **42 of 82 rows are
hand-written and deleting one raises the coverage figure.** That is the gate's own worst failure mode.

`D-o` — `parity-fixture.sh:121` normalises `"project":"[A-Za-z0-9]+"`, a character class omitting `-`
and `_`. A call's project is the directory it came from, so **the gate's verdict depends on the name
of the directory it is run from**: from `.worktrees/R2W` it reads one number, from `mcp-router` it
reads another. Measured on 2026-08-15: 71 of 82 from the repo root against the runner's 72 from its
worktree, same tree. One character class.

**Done means:** the rows derived, the normaliser fixed, and the number identical from both a worktree
and the repo root. Note the fix moves coverage up, so record the before and after from both places.
