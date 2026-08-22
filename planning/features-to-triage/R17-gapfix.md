# R17 gap-fix — the fix is right; the claim is wider than the evidence

**Parent:** R17 · **Verdict:** Needs More Work, 2026-08-22
**Worktree:** `.worktrees/R17`, branch `ai/r17`, base `a1a3ec2`

## Read this first: no code change is needed

The verifier's own words — *the fix itself is correct and needs no code change*. Both blockers are
about what the item **claims**, not what it does. This is a records pass with one new scenario.

## What held, measured rather than argued

**The route account's pre-registered prediction held exactly.** Pre-fix, two identically-failing
servers: with `namecheap` staged and `lifeline` not, `watch` leaves `lifeline` only; stage
`lifeline` too and it leaves **no rows at all**. With the fix, both survive on node and Swift.

And the owner's live machine corroborates it read-only: 14 upstreams, 13 rows, the one missing is
`namecheap` — the only configured upstream that is also staged. `lifeline` is configured, unstaged,
row present. `pocketsmith` is staged-but-unconfigured, also no row. **The partition is perfect.**

The reason surviving only in `watch-state.json` is confirmed: `STATE_PATH` appears in `src/watch.ts`
alone, and `WatchState.Failure` is consumed only for `hash` and `at`, never `error`.

**The gate attribution is now measured, and it favours the branch more strongly than the runner
argued.** Same machine, both gates within two hours: `main` exits 1 with **one** diverged row;
the branch exits 1 with **zero**. The oauth divergence fired on **main and not the branch**. Both
exit 1 on the same standing exclusion. `surface.tsv` is census-identical between them.

## BL-1 — "one bug, not two" is under-determined

A **second** mechanism erases a freshly-written manifest row *after* the fix, on node: `cmdWatch`
snapshots the manifest at `src/watch.ts:212` and saves that snapshot at `:273`. Demonstrated
against the fixed code — a `watch` fire held open six seconds while `index --force` wrote unstaged
`lifeline`'s row at t+2s leaves a manifest holding `slowfail` only, **with no delete statement in
the path**.

That is the same observable R17 attributes solely to the deleted row, and **R17's evidence was
gathered on a timeline where the two were concurrent** — the owner ran `index --force` while the
launchd watch agent was live.

So: correct the claim to **sufficient, not exclusive**, in `R17-acceptance.md`, the two source
comment blocks and the `surface.tsv` note. **Keep the route account** — it is still the better fit
for the observed asymmetry, and it is what the prediction confirmed. The second mechanism is filed
as **R19**; cite it rather than absorbing it.

## BL-2 — the implementations diverge on the property this change makes load-bearing

Swift's `WatchIndexer.apply` re-loads the manifest per entry immediately before saving; node loads
once per run. On the same fixture Swift keeps both rows and node does not. **`parity-cli.sh` runs
the binaries sequentially, so the lane is structurally blind to it.**

Declare it in `surface.tsv`, or grow a scenario that overlaps a writer. The repo already guards this
class for the config writer and says so — *W11, the read happens inside the lock, so a concurrent
write is not clobbered* — and has no equivalent for `manifest.json`, which has five `saveManifest`
call sites. If you declare rather than fix, say which of the five the declaration covers.

## Also correct, all measured

- **`VER-R17-5`: the acceptance's "21 of 21 both times" does not reproduce** — 19/21 twice today,
  under unrelated load. The conclusion survives; the stated evidence does not. Restate it as what
  was measured.
- **`VER-R17-6`: F2 is not new.** `ToolUnion.swift` on `main` already documents it verbatim as a
  ported reference defect *reported as a deferred child*. Cite that rather than filing it fresh.
- **`VER-R17-3`**: criterion 1's *regardless of how it was configured* is unmet for the staged-only
  route — such a server gets a row and no surface reads it, since `/servers` and `reportUpstreams`
  both iterate `config.upstreams`. Strictly better than pre-fix, which had no row at all. Both lanes
  raised it independently. Record the bound rather than claiming the criterion.
- **`VER-R17-4`**: the one place R17 makes a surface **newly wrong** — a staged entry sharing a name
  with a healthy router upstream wipes its tools and attributes the staged definition's error to it.
  Measured: a healthy `db` with 2 tools, then a broken `db` staged, gives `indexError: spawn
  /nonexistent/not-a-server ENOENT` for a server whose configured command is `node`. Pre-fix it read
  `error: None`. The tool loss is not a regression; **the misattribution is.** R7's duplicate class —
  file it or declare it.
- **`VER-R17-7`**: two weak-but-not-vacuous assertions, and **no TypeScript unit test at all** — the
  node row-keep is pinned only by the parity lane. Neither was armed.

## Criterion 2 stays open, with its reason

Only a run of the fixed watcher against the owner's real `~/.claude.json` and router home, then
reading `namecheap`'s row on `/servers`, closes it. The sandbox rule forbids that. The precondition
is now measured true read-only. Leave it open and say so.

## One process note

Two of the runner's gate rows were captured through a `tail` pipeline, so `$?` read `tail`. The
verifier re-ran both logging to file first. That rule is in this repo's own record; apply it.

## Acceptance

1. The claim reads sufficient-not-exclusive at all four sites, citing R19.
2. BL-2 is declared or covered, and if declared, the coverage bound is stated.
3. The four corrections above land, each stating what was measured.
4. Gates unmoved: `make test` 0 twice at 1686/210, lint 0 over 531 files, parity 358/358,
   `acceptance-r6` clean, R7 lane 0, `parity-cli.sh` 18/0, reconciler 0.
