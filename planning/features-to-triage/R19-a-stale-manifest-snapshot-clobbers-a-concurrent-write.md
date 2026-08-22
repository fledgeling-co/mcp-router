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

---

## Triage — 2026-08-22

**Verdict: Ready for AI.** Standard tier. Depends on nothing; `R17` merging first is convenient
(its `watch.ts` line numbers move) but not required.

### The precondition question is settled, and the answer is neither option this brief listed

The brief asked whether the manifest wants the treatment `servers.json` already has, and framed it
as lock-versus-no-lock. Referred to the Google lane (`agy`, `gemini-3.7-flash-high`) with the
write-site census, the `ConfigMutationLock` source and both options in full. It returned a third
shape and it is right:

> Perform long-running child indexing in memory with **no lock held**. Once the indexed row is
> ready, acquire the lock strictly around the commit phase: read current disk state, merge the
> single server row, write to temp, and rename. Lock duration drops from seconds to <1ms.

**The policy, over all eight sites:** `withExclusiveLock { load; merge the rows this path owns;
save }`. The load moves *inside* the lock, adjacent to the merge — it is the stale read that
clobbers, not the write. Everything expensive stays outside.

This is not the lock this brief feared. Option A held the lock across the read-then-index window,
which for `cmdWatch` is seconds and would have made a concurrent control-API PATCH fail at the
2000 ms daemon bound — a new user-visible failure. Commit-phase-only has no such window, so the
daemon's fail-fast timeout is never reached and the objection that made this a fork dissolves.

The two shapes the lane was asked about explicitly and rejected, recorded so they are not
rediscovered: a `manifest.d/*.json` split ("orphan cleanup bugs on delete/rename, migration churn
for a single small config"), and optimistic versioning with CAS retry ("unnecessary — a <1 ms
locked mutation lets `flock(2)` queue writes with zero retries").

### What this makes of `VER-R17-2`

Swift's re-load-per-entry was the right instinct implemented without exclusion. The fix upgrades
it rather than reverting it, and the two implementations converge by construction rather than by
a declaration in `surface.tsv`. Convergence is therefore the expected outcome and a declaration is
the fallback, which inverts what this brief assumed.

### The component is already built

`ConfigMutationLock` (`app/Sources/RouterCore/Config/ConfigMutationLock.swift`) is generic over the
path, not specific to `servers.json`. It already solves the sidecar-versus-inode problem, the
`O_CLOEXEC` inheritance problem, thread-local reentrancy, path standardisation, and the
`ENOTSUP` filesystem that has no advisory locking. Its two timeout constants and the reasoning
behind each apply unchanged. Node has no counterpart and needs one; that is the larger half of
the work.

### Sizing

Eight call sites — node `watch.ts:253`, `index.ts:146`, `index.ts:186`, `control.ts:262`,
`control.ts:432`; Swift `AuthRoutes.swift:120`, `ServicePorts.swift:391`, `WatchIndexing.swift:150`
— a node lock module, and one overlapping-writer scenario. The scenario is the part with no
precedent in this repo: `parity-cli.sh` runs the binaries sequentially, so it is structurally
blind here and a new lane is needed rather than a new row in an existing one.
