---
status: to-triage
found-by: M30's runner, 2026-08-26; reproduced and diagnosed by the orchestrator the same day
---

# A gate answers differently on two checkouts of one commit

`planning/foreign-path-gate.py` decides whether any hand-written record cites a scratch path
without saying what became of it. Run against one commit it gives two different verdicts depending
on which checkout you run it in.

## The measurement

Both runs at `597236c`, same machine, same minute, `/usr/bin/python3`:

| Checkout | Exit |
|---|---|
| A pristine `git worktree add --detach` of that sha | **1 — FAIL** |
| The main checkout, at that same sha, with its own working-tree state | **0 — PASS** |

The classification totals move with it: RUNTIME 91 → 87, SUBJECT 71 → 74, WITHDRAWN 52 → 54. The
main checkout gains two `WITHDRAWN` rows that the pristine checkout does not have, both in
`planning/evidence/` files that are **modified but uncommitted** there.

## The mechanism, and it is two mechanisms

1. **It enumerates from the index and reads from the disk.** The file list comes from
   `git ls-files`, so only tracked paths are considered — which looks committed-only and is the
   reason this is easy to miss. But each path is then opened from the working tree, so a file with
   uncommitted modifications is judged on its *modified* text. The gate's subject is a commit; its
   evidence is a working tree.
2. **It asks the filesystem whether a cited path exists right now.** `resolves()` calls
   `glob.glob(probe)` to decide whether a cited path resolves on this machine, which is the whole
   point for a `/tmp` citation — and it means a verdict also depends on what happens to be in
   `/tmp` at the moment of the run. That half is arguably intended; it is recorded here because it
   is the second independent source of the same class of drift, and a fix that addresses only the
   first will not make the gate reproducible.

## Why this matters more than a flaky number

**It fails in the direction that ships.** A developer runs the gate in the main checkout, where
uncommitted work makes it pass, and merges. The merged commit is then a commit at which the gate
fails, and anything running it on a clean checkout — CI, a hook, another worktree, a fresh clone —
sees the failure the author never saw. The pristine answer is the one that describes the artifact;
the main-checkout answer describes the artifact plus whatever the author had not committed yet.

It is also self-concealing in the ordinary case. Most of the time the working tree is clean and
the two answers agree, so the gate looks deterministic right up until someone has local changes —
which is exactly when a gate is being consulted.

This repository's own rule already names the standard the gate misses:
"a citation must resolve where it is **read**, not merely where it was written". A gate whose
answer depends on the reader's working tree cannot enforce that rule, because it does not itself
satisfy it.

## Scope

- **Decide what the gate's corpus is, and say so in the file.** Either the committed tree at a
  named revision (read blobs via `git show <rev>:<path>`, which makes the verdict a property of
  the commit) or the working tree (in which case it must refuse to run, or say loudly what it is
  doing, when `git status --porcelain` is non-empty). Both are defensible; silently being the
  second while looking like the first is not.
- **Decide whether machine-resolution belongs in the verdict at all.** Asking whether `/tmp/x`
  exists is the honest question for "is this evidence still there", and it is unreproducible by
  construction. It may belong on a separate rung — reported, not gating — the way this repo already
  separates blocking classes from ratcheted ones.
- **Whatever is decided, add the control that would have caught this**: run the gate twice, once in
  a pristine checkout of `HEAD` and once in the working tree, and fail if the verdicts differ. That
  is three lines and it turns an invisible drift into a red.

## Not folded into `G6` or `G9`, and why

`G6` is about whether a cited artifact survives; `G9` is about paths pinned to a machine. This is
neither: every citation here is well-formed and every artifact is in the state the record claims.
The defect is in the **instrument's corpus** rather than in any record it reads, and the remedy —
choosing between blob-reads and a dirty-tree refusal — moves nothing in either of those items.

Found while M30 was running its own gates and reported rather than worked around, which is the
only reason it is written down: in the main checkout, where the work was happening, the gate was
green.
