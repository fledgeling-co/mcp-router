# R19 — a watch fire saves a manifest snapshot taken before a concurrent write

**Status:** Untriaged · **Found:** 2026-08-22 by R17's verifier, demonstrated against the fixed code
**Category:** router

## The finding

`cmdWatch` snapshots the manifest at `src/watch.ts:212` and saves that snapshot at `:273`. Anything
written to `manifest.json` in the window between is clobbered — **with no delete statement anywhere
in the code path.**

Demonstrated in a sandbox against the **fixed** node watcher: a `watch` fire held open six seconds
on a staged failing server, with `index --force` writing unstaged `lifeline`'s row at t+2s. The
final manifest holds `slowfail` only. `lifeline`'s row is gone.

## Why it matters beyond itself

**It produces the same observable R17 attributes solely to the deleted row**, and R17's own evidence
was gathered on a timeline where the two were concurrent — the owner ran `index --force` while the
launchd watch agent was live. So "the watcher deleted the row" is *sufficient* to explain what was
seen and not *exclusive*, which is R17's `VER-R17-1`.

R17's route account remains the better fit for the observed **asymmetry** — `namecheap` staged and
`lifeline` not — and should be kept as that. This item is the other mechanism, not a replacement.

## The class the repo already guards elsewhere

`manifest.json` has **five** `saveManifest` call sites and no lock. The config writer has exactly
this guard and states it: *"W11 — the read happens inside the lock, so a concurrent write is not
clobbered."* There is no equivalent for the manifest.

So the question this item answers is not "fix one race" but **whether the manifest wants the
treatment the config file already has.** Establish that before patching one call site.

## Related and undeclared: the implementations differ here

`VER-R17-2`. Swift's `WatchIndexer.apply` re-loads the manifest per entry immediately before
saving; node loads once per run. On the same fixture Swift keeps both rows and node does not — so
the two implementations already disagree on the property, and `parity-cli.sh` cannot see it because
it runs the binaries **sequentially**. Whatever is decided here has to be declared in
`surface.tsv` or covered by a scenario that overlaps a writer.

## Acceptance

1. A write landing between another path's read and its save survives, or the losing write is
   detected and retried — decided as a policy over all five call sites, not one.
2. A scenario that **overlaps** a writer, since a sequential lane is structurally blind to this.
3. The Swift and node behaviours either converge or the divergence is declared.
