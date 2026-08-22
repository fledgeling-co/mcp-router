# R19 — a watch fire saves a manifest snapshot taken before a concurrent write

**Status:** Untriaged · **Found:** 2026-08-22 by R17's verifier, demonstrated against the fixed code
**Category:** router

## The finding

`cmdWatch` snapshots the manifest at `src/watch.ts:212` and saves that snapshot at `:292`. Anything
written to `manifest.json` in the window between is clobbered — **with no delete statement anywhere
in the code path.**

*(The save was at `:273` when this was filed. R17's gap-fix pass grew the comment block above it by
nineteen lines on 2026-08-22; the code did not move. Re-cited here rather than left to rot, because a
line citation that no longer lands is how a finding gets read as already fixed.)*

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

`manifest.json` has **five** `saveManifest` call sites on the node side and **three**
`ManifestIO.save` sites on the Swift side, and no lock on either. The config writer has exactly
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

**Declared 2026-08-22 by R17's gap-fix pass**, in `surface.tsv`'s `cli-watch` note and at the head
of `WatchIndexing.swift`. The declaration is scoped to the **watch save alone** — `src/watch.ts:292`
against `WatchIndexing.swift:187`.

**Six sites are left uncovered, and they are not four pairs.** The two inventories are different
sizes, counted from source on 2026-08-22. node has **five** `saveManifest` sites and `saveManifest`
is its only manifest writer — `src/watch.ts:292`, `src/index.ts:146`, `src/index.ts:186`,
`src/control.ts:262`, `src/control.ts:432` (`grep -rn saveManifest src/`). Swift has **three**
`ManifestIO.save` sites and no other manifest writer — `AuthRoutes.swift:120`,
`ServicePorts.swift:391`, `WatchIndexing.swift:187` (`grep -rn ManifestIO.save app/Sources/`). One
save on each side is declared, which leaves **four on node and two on Swift**:

| Uncovered site | Verb | What it faces on the other side |
|---|---|---|
| `src/index.ts:146` | `import` | Nothing positional. Swift has no once-per-run save on this verb |
| `src/index.ts:186` | `index` | Nothing positional. Same |
| `src/control.ts:262` | control re-index | `ServicePorts.swift:391`, which saves per entry |
| `src/control.ts:432` | `/approve` | `AuthRoutes.swift:120` — the one genuine pair in this list |
| `AuthRoutes.swift:120` | `/approve` | `src/control.ts:432` |
| `ServicePorts.swift:391` | `index`, `import`, control re-index | node's three above, none of them positionally |

Each of the six carries an unlocked read-then-save window **on its own side**; there is no
site-for-site symmetry between the sides to claim, and on half the node list there is no twin to be
symmetric with. `src/index.ts` loads once at `:101` and `:177` and saves once at `:146` and `:186`,
while Swift routes both verbs through `ManifestIndexer.record`, which re-loads at
`ServicePorts.swift:381` and saves at `:391` **per entry** — the same read-window disagreement the
declaration records for `watch`, on the writer this item's own reproduction drove. That one is
established by reading the source rather than by measuring it, and is registered as `VER2-R17-3`.

Acceptance 2 below is unchanged: declaring the divergence is not seeing it, and only a scenario that
overlaps a writer can.

## Acceptance

1. A write landing between another path's read and its save survives, or the losing write is
   detected and retried — decided as a policy over **every manifest writer on both sides**, node's
   five `saveManifest` sites and Swift's three `ManifestIO.save` sites, not one.
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
