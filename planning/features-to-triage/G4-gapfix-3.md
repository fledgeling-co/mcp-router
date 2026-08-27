---
status: completed
shipped-by: 87e16dc
---

# G4 gap-fix 3 — the two gates this item shipped both violate the doctrine this item wrote

**Parent:** G4 (merged `de1315d`) · **Status:** Ready for AI, **urgent — `main`'s `make lint` is red**
**Raised:** 2026-08-22 by the orchestrator, from the merged-tree gate run.

## What happened

G4's two new gates are wired into `make lint` at `Makefile:540-541`. Both were **green on `ai/g4`**
and both are **red on the merged tree**. `swiftlint` is clean — 0 violations over 549 files — so
`make lint` exits 2 on `main` for these two alone. This is the fleet's **fourth merge-only break**:
green on the branch, red once other verified work is beside it.

Measured, not inferred: `null-run-gate.py` exits **0** in `.worktrees/G4` and **1** on `main`.

## BL-1 — `null-run-gate.py`'s three RAW arms carry a stale directory list

`BASE-raw`, `RAW-import` and `RAW-bridge` all report `HELD … stayed green under poison input`.
`no-raw-design-values.sh` itself is fine — standalone it exits 0, scanning 125 files with 84 under
the geometry rules.

The arms build a scratch tree via `lint_tree(script, dirs, …)` at `planning/null-run-gate.py:138`,
which creates exactly the directories in the `dirs` tuple its callers pass. **M15 widened
`GEOMETRY_DIRS` to four** — `Shell`, `Activity`, `Boards` and now **`Settings`**
(`scripts/lint/no-raw-design-values.sh:135-140`). The callers still pass three. The rule exits early
at `:140` with *the geometry checks did not run*, the plant is never reached, the script stays
green, and the arm correctly reports that it could not discriminate.

**The fix is this item's own thirteenth instance, verbatim.** M15's arm 6b found that
`no-raw-design-values.sh` reads *the directories currently listed in `GEOMETRY_DIRS`* rather than
*the design surfaces*, and G4 filed it as such. **Derive `dirs` from the script** — parse
`GEOMETRY_DIRS` out of `no-raw-design-values.sh` at run time — rather than restating it in a
literal beside it. A hardcoded list of what to create is a denominator that stops tracking its
numerator the first time somebody adds a directory, which is the sentence already in G4's own table.

## BL-2 — `reader-accounting.py` enumerates the filesystem, not the repository

It reports one silent-dropping reader:

```
planning/test-campaign/bin/witness-fixture/fixture-server.py::<module>
  drops at …:18 continue, …:22 continue
```

That file is **untracked** — `git status` shows `?? planning/test-campaign/bin/witness-fixture/` —
and belongs to **another session's in-progress work**. So `main`'s lint gate is red because of a
file that is not in the repository and that this fleet does not own.

**The fix is again this item's own doctrine, and its own sweep already does it right.** G4's
`claim-sweep.py` usage closes its accounting as `1118 scanned + 157 skipped = 1275 = git ls-files`,
which the verification checked. `reader-accounting.py` should enumerate the same way: **`git
ls-files`, not a filesystem walk.** A gate whose denominator includes other people's untracked
work-in-progress reports findings nobody can act on and reds a shared branch.

Do **not** fix this by adding `planning/test-campaign/` to an exclusion list. The subject is the
enumeration, not that one directory.

## Acceptance

1. `make lint` exits **0** on `main` with both gates wired as they are now. Paste it.
2. `null-run-gate.py`'s RAW arms derive their directories from `no-raw-design-values.sh` rather
   than restating them, and **the derivation is armed**: add a fifth directory to `GEOMETRY_DIRS`
   in a scratch copy and confirm the arms follow it without being edited.
3. `reader-accounting.py` enumerates through `git ls-files`, and its own count is stated and
   reconciles — the pattern G4's sweep already uses.
4. Both gates still bite: re-run the two arms G4's first verification used (delete a `tally.drop`
   from `table_ids`; make an assertion intact but unmatchable) and confirm each still reddens.
5. Reconciler 0 across A–L, `make test` unmoved at **1725 in 215 suites**.

## Why this is a gap-fix and not a revert

Both gates are verified, armed and correct about their subject; what is stale is a literal in one
and an enumeration boundary in the other. Reverting would discard an item that took two gap-fixes
and two verifications, to fix two lines. **But `main` is red while this is open**, so it goes first
and nothing else dispatches until it lands.

## For whoever reads a red gate in the meantime

`main`'s `make lint` exits 2 from 2026-08-22 ~17:1x until this lands, on these two gates only.
`swiftlint` is clean, `make test` is 1725/215 green, and the reconciler is 0 across A–L. **A runner
reporting this red did not cause it.**
