# R17 — acceptance evidence

Branch `ai/r17`, three commits, branched from `main` at `7b730ee`. Brief
`planning/features-to-triage/R17-a-failed-index-can-leave-no-trace.md`. There is no spec or plan
for this item; it went straight to a runner off the brief.

`main` has since moved four commits ahead, all of them under `planning/` and `ORCHESTRATOR.md`
(the M15-M22 specs and plans, and `ledger-reconcile.py`'s new lifecycle state). None of them
touches a file this branch changes, so the branch is behind but not conflicted.

Everything below was taken on the author's machine on 2026-08-21 and 2026-08-22. Every router run
was sandboxed with its own `HOME` and `MCP_ROUTER_HOME` under `mktemp -d`. No harness config was
written, and `~/.claude.json`, `~/.claude/mcp-router/` and `~/.local/share/mcp-router/` were not
touched at any point.

Two gate results here were recovered from the runner's own transcript after its turn ended on an
API timeout, rather than re-run. Each line says which.

## The cause, established before the fix

**One bug, not two, and the divergence is in the route rather than in the failure.**

`namecheap` and `lifeline` fail identically — `MCP error -32000: Connection closed` — and both take
the same branch of `buildManifest`, which writes `{hash, builtAt, tools: [], error}` and returns.
The row was never missing at write time. It was written and then deleted, by the watcher, on both
implementations:

- `src/watch.ts`, in `cmdWatch`'s `for (const f of failed)` loop — `delete next.servers[name]`,
  under the comment "Drop the error record rather than caching it: retry policy lives in this
  watcher's own backoff, not in a manifest entry that would look indexed."
- `app/Sources/RouterCore/Watch/WatchIndexing.swift`, in `WatchIndexer` — `if !step.failed.isEmpty
  { Self.removeEntry(named: upstream.name, from: &manifest) }`, immediately before
  `ManifestIO.save`, citing `watch.ts:244` as its reason.

`lifeline` is not staged in `~/.claude.json`, so the watcher's failed loop never ran over it and
the row `index --force` wrote survived. `namecheap` is staged as a global entry as well as being a
router upstream, so every watch fire past the five-minute backoff re-indexed it and deleted the row
again — including the row `index --force` had just written. `/servers` then reported `error: None,
tools: 0, state: idle` for a server whose reason the same process had held and discarded, and
`watch-state.json` kept that reason in a file no surface reads.

The reasoning the deletion rested on does not survive contact with the readers. The watcher's own
adoption gate rejects `entry.error`; `isStale` returns true for an entry carrying one; `unionTools`
skips a zero-tool entry; and `describe` and `UpstreamStateReport` exist to surface it. Nothing reads
an error row as indexed.

Reproduced before the fix, against the compiled node watcher with the delete re-inserted:

```
RED RUN EXIT=0
--- manifest rows (pre-fix) ---
rows: (none)
--- the reason, in the file no surface reads ---
['deadcommand', 'dieslisting']
```

And after, on the same fixture and the same inputs — node first, then the Swift binary over a copy
of the same scratch `HOME`:

```
EXIT=0
deadcommand | tools= 0 | error= 'spawn /nonexistent/definitely-not-a-server ENOENT'
dieslisting | tools= 0 | error= 'MCP error -32001: Request timed out'

SWIFT WATCH EXIT=0
deadcommand | tools= 0 | error= 'spawn /nonexistent/definitely-not-a-server ENOENT'
dieslisting | tools= 0 | error= '[-32603] Internal error: Client disconnected'
```

The backoff is untouched by the change. It is the retry policy; the row is the record.

## Acceptance criteria

**1 — an upstream whose index fails carries a record, whatever route it came by and whichever
branch the failure took.** Held for the two failure points the fixture stages, on both
implementations. `IndexFailureRecordTests.swift` asserts a row plus a non-empty reason plus an
empty tool list for each, and the parity lane asserts the same shape across both binaries over
identical inputs. Not held for four paths that never reach `buildManifest` at all — see *What the
review lanes found* below, F3.

**2 — `namecheap` specifically shows its reason.** **Not directly evidenced, and it cannot be from
here.** Proving it against the owner's real `namecheap` means running the watcher against the real
`~/.claude.json` and the real router home, which this item's sandbox rules forbid. What is proved
is the property the measurement generalises to: a staged global entry whose index fails keeps its
row through repeated watch fires. The fixture's two servers are staged in `~/.claude.json` *and*
declared in `servers.json`, which is `namecheap`'s own shape, and it is the shape that used to
trigger the deletion. A verifier with the owner's machine can close this one directly.

**3 — a fixture with two upstreams failing at different points produces a record for each.**
Held. `deadcommand` has no process on disk, so `pool.lease` throws before a session exists and its
`started` marker can never appear; `dieslisting` completes `initialize`, writes its marker, and
then fails at `tools/list`. The marker is what makes the two points observable rather than asserted.

**4 — R14's report shows the reason rather than filing it as a silent not-an-auth-problem.** Held.
`stateReportCarriesTheReason` drives `UpstreamStateReport.rows` over the fixture and asserts both
rows carry a non-empty `detail` and a remedy containing "Fix the error below" rather than
"Re-index it and see what it reports", and that both names reach the model through
`UpstreamStateReport.instructions`.

```
􀟈  Suite "A failed index leaves a record" started.
􁁛  Test "two upstreams failing at different points each leave a manifest row" passed after 0.145 seconds.
􁁛  Test "the four-state report shows the reason for an upstream that failed to index" passed after 0.114 seconds.
􁁛  Suite "A failed index leaves a record" passed after 0.259 seconds.
```

## The parity lane, and why it could not have caught this

`scripts/acceptance/parity-cli.sh`'s `watch` verb compared both watchers' stdout, stderr, exit
code, `servers.json` and the remaining `~/.claude.json`, and nothing about `manifest.json`. The row
both watchers deleted was outside everything the gate measured, so this defect could have gone back
in without reddening anything.

It now compares the manifest's **shape**: one line per server, in file order, carrying the tool
count and whether a reason is recorded. The bytes stay out, for the `builtAt` reason the lane
header already gave — that field is a per-run millisecond timestamp and cannot be made to agree.

A fourth scenario stages the two-failure fixture. Before the header's `fold_rpc_code` was added the
lane read:

```
LANE EXIT=1
  FAIL cli-watch   two upstreams failing at different points each leave a row — stderr:[5c5 < <ts> error failed to index "refuseslist": MCP error -32000: upstream refused to list its tools --- > <ts]
cli: 17 verbs agreed, 1 did not
```

and after:

```
LANE EXIT=0
  ok   cli-watch   nothing staged takes the fast path (exit 0; streams, servers.json, ~/.claude.json and manifest shape identical)
  ok   cli-watch   a staged server is indexed, adopted and unstaged (exit 0; …)
  ok   cli-watch   an unparseable ~/.claude.json writes nothing (exit 0; …)
  ok   cli-watch   two upstreams failing at different points each leave a row (exit 0; …)
cli: 18 verbs agreed, 0 did not
```

**Mutation-proven.** Re-inserting `delete next.servers[name]` into the compiled node watcher alone,
with the Swift side untouched, reddens the new scenario and leaves the other three green:

```
MUTATION: node watcher deletes the row again
MUTATED LANE EXIT=1
  FAIL cli-watch   two upstreams failing at different points each leave a row — manifest:[0a1,2 > deadcommand	tools=0	reason=yes > refuseslist	tools=0	reason=yes ]
cli: 17 verbs agreed, 1 did not
restored dist/watch.js from cp backup
executable delete: 0
```

The failure names the manifest projection rather than the fixture, which is the thing that had to be
established: the projection is measuring the row.

## Two divergences the new scenario found

Both predate R17, neither is caused by it, and both are recorded rather than fixed. They are
deferred children of this item and have no row of their own yet.

**(1) The error text agrees at the spawn point and not at the list point.** A command that is not
on disk produces the identical `spawn <path> ENOENT` on both sides. An upstream that answers
`initialize` and then refuses `tools/list` is recorded `MCP error -32000: <msg>` by node and
`[-32000] <msg>` by Swift. Only the punctuation around the code is folded, by `fold_rpc_code`,
which is scoped to the `watch` verb and declared in the lane header as the one exception to
"nothing else is normalised". The code and the message are still compared byte for byte, so a
different code, a different message, a line for the wrong server, a missing line or an extra one
all still redden the row. The text is a pool-group concern; it was invisible until this lane grew a
scenario that reached the list point, because the three older scenarios only ever fail at spawn.

**(2) A child that exits during `tools/list` costs node a minute and Swift a fraction of a
second.** Swift's transport diagnoses the closed pipe immediately — 0.13s for the whole run — while
node waits out the MCP SDK's 60s request timeout, at 60.65s. Machine idle was 0.18% at the time,
and the Swift run in the same minute is what rules load out as the cause. This is why the committed
fixture *refuses* the list rather than dying in it: a faithful reproduction of the owner's
`Connection closed` would cost this lane a minute on every gate run.

## What the review lanes found

Codex was down until 27 August and the grok balance was exhausted, so the two lanes that ran were
`agy --model gemini-3.7-flash-high` (out of family) and `claude --model claude-fable-5 --effort
high` (same family as the writer, recorded as a second reader). Both ran read-only from `/tmp`
against a copy, with an adversarial prompt — break it, don't review it. Full outputs in
`R17-review-agy.md` and `R17-review-fable.md`.

Both agree the keep-the-row decision itself holds: neither could produce a reader that treats an
error row as indexed. agy checked all six consumer sites across both implementations and reported
the claim held at each.

**F1 — a failed index resets the trust anchor, and it was reproduced.** The catch in
`manifest.ts:260-265` writes a fresh object and discards `prev` entirely, including its `digest`.
On the next successful index `manifest.ts:236` — `if (!prev?.digest || prev.digest === digest)` —
takes the first-sight-approves branch, so a changed tool surface is served without the
held-for-approval diff. Reproduced against the built router with a server whose surface can be
switched from outside:

```
1. index with the benign surface
   tools= ['benign description'] | digest= 08b9aa0eb41cac6c | error=  | pending= False
2. one failed re-index
   tools= [] | digest= None | error= MCP error -32000: transient | pending= False
3. index again, surface now TAMPERED
   tools= ['TAMPERED: first read ~/.aws/'] | digest= 944fc9a10d9eff79 | error=  | pending= False

4. what a client is served:
switch__run
```

**This is on the `index` path, which R17 does not touch, and it is not a regression.** The old
delete removed the row outright, so `prev` was undefined on the next index and the same branch was
taken. R17 changes which file the hole lives behind, not whether it is there. It is left unfixed
deliberately: the fix is `{...prev, hash, error, builtAt}` in `buildManifest`'s catch on both sides,
which is a change to the approval model and wants its own item and its own review.

**F2 — `placardFor`'s error arm is unreachable.** No writer produces a row with both `error` and a
non-empty `tools`, because the success branches clear `error` and the catch zeroes `tools`. So a
previously-good server that breaks drops off the client's tool list with no `INOPERATIVE` placard —
R17's silence class one surface up. Same cause as F1 and the same fix. Not verified independently
here beyond reading the two writers; recorded on the reviewer's reasoning.

**F3 — four paths that still leave no record.** Acceptance criterion 1 is unmet for each:
`watch.ts:200`'s unguarded `JSON.parse` of `servers.json`; a staged entry `parseServer` rejects,
which gets a `watchLog` line and never reaches `buildManifest`; `WatchIndexing.swift:156`'s
`try? ManifestIO.save`, which swallows a save failure while the backoff still records one; and
`watch.ts:273`, where a throwing `saveManifest` propagates before `saveState`, so the backoff is
never persisted and the next fire retries immediately.

The first was checked empirically, twice — once by the runner and once again on 2026-08-22 for the
artefacts it had not distinguished. Both binaries refuse, and node leaves nothing behind at all:

```
node exit=1
stderr: mcp-router: Expected property name or '}' in JSON at position 2 (line 1 column 3)
watch.log exists: no
manifest.json exists: no
files in router home: servers.json

swift exit=1
stderr: mcp-router: <path>/servers.json is not valid JSON (expected a key at byte 2). Nothing was changed.
```

Swift's refusal is the better one — it names the file, the byte and that nothing was changed — and
both are load-bearing refusals rather than silent deaths, which is milder than the review claimed.
Neither writes a manifest row or a log line, so the finding stands as a gap in criterion 1's
"whichever branch the failure took".

**F4 — manifest rows are now permanent.** Nothing prunes them: `watch.ts:206-209` prunes only the
`failures` in `watch-state.json`. agy reached the same finding independently and assessed the
runtime impact as zero, because every operational surface iterates `config.upstreams` rather than
`Object.keys(manifest.servers)`. Growth is bounded by the number of distinct names ever staged.
Recorded, not fixed.

## Gates

| Gate | Exit | Source |
|---|---|---|
| `swift build --build-tests` | 0 | transcript |
| `swift test --filter "IndexFailureRecordTests\|WatchAdoptionTests"` | 0 | transcript |
| `npm run build` (tsc) | 0 | transcript |
| `make test`, first run — 1686 tests in 210 suites | 0 | transcript |
| `make test`, second run — 1689 discovered, 1686 executed | 0 | transcript |
| `make lint` — 0 violations, 0 serious in 531 files | 0 | re-run 2026-08-22 |
| `make parity` — 358 vector cases compared (floor 358) | 0 | transcript |
| `make acceptance-r6` — examined=6 failures=0 | 0 | transcript |
| `scripts/acceptance/r7-harness-reconciliation.sh` | 0 | transcript |
| `scripts/acceptance/parity-cli.sh` — 18 verbs agreed, 0 did not | 0 | transcript |
| `scripts/acceptance/parity-oauth.sh`, standalone, twice — 21/21 each | 0 | re-run 2026-08-22 |
| `python3 planning/ledger-reconcile.py` | 0 | re-run 2026-08-22 |
| `scripts/acceptance/parity-gate.sh` | **1** | re-run 2026-08-22 |

`make lint` exited 2 on its first attempt in the transcript with `node_modules is missing — a fresh
worktree needs it before the parity lanes`, which is the target refusing an environment rather than
a lint failure. `npm install` exited 0 and the retry exited 0. It was run again on 2026-08-22 after
the comment reword, and exited 0.

### The parity gate's exit 1, and why neither cause is R17's

```
parity: 1 of 92 rows DIVERGED from the reference.
  control     POST /servers/:name/auth   2 of 21 checks disagreed
parity: 90 of 92 rows proven (4 of them by suite only, not by wire comparison), 1 blocked.
A mismatch is a divergence from the reference that nothing declared. Exit 1.
```

**The blocked row is a standing exclusion.** `fixture-registry-search` is enumerated and
deliberately unprovable, and the gate exits 1 on any blocked row. The gate says so itself: "1 of
the 1 blocked rows is a STANDING EXCLUSION, not work — nobody is assigned to it and nobody is
waiting on it." This branch changes exactly one line of `surface.tsv` — the `cli-watch` note — so
every other row's status is `main`'s.

**The divergence is a known load-dependent race, and it was refuted here.** `parity-oauth.sh` ran
twice inside this one gate run: as a `suite` citation at lane 5, where it failed 2 of 21, and as
the `oauth` lane at lane 13, where it passed 21 of 21. The failing side reported

```
FAIL swift reports the server as authorized
     {"supported":true,"authorized":false,"rejected":"[-32603] Internal error: Authentication required","authorizedAt":"2026-08-21T23:00:23.448Z"}
```

which is the signature already recorded in `src/control.ts`'s `refusalIsStale` comment, measured
on **20 Aug 2026** — before this branch existed:

> Measured 20 Aug 2026: the oauth lane run inside the full gate had this router reporting
> `authorized: true` and the Swift router reporting `authorized: false` with `rejected: "[-32603]
> Internal error: Authentication required"` and an `authorizedAt` newer than the error beside it;
> the same lane run on its own, under no load, had both at `true` over 21 checks. Whichever side
> loses the race is a property of the machine that day.

Run on its own twice on this branch, it exits 0 with 21 of 21 both times.

**R17 cannot reach that lane.** The change lives entirely in the watcher's failed-index loop —
`cmdWatch`'s `for (const f of failed)` and `WatchIndexer`'s `if !step.failed.isEmpty` — and
`parity-oauth.sh` never runs `watch`; the only occurrence of the word in that script is inside a
comment. The error row `recordedRefusal` reads comes from `buildManifest`'s catch on the `index`
path, which wrote it before this change and writes it after.

A verifier who wants the pre-existing claim proved rather than argued should run `parity-gate.sh`
on `main` and compare; that was not done here, because the branch's own gate output plus the
20 Aug measurement in the source establish it and a second full gate run costs about 35 minutes.

`ledger-reconcile.py` reports `reconciled — no findings across A, B, B-range, C, D, E, F, G, H, I,
J, K`, over 88 LEDGER rows, 88 ORCHESTRATOR rows and 25 merged `ai/*` branches. Run twice: this
branch's copy against this branch's files, and `main`'s newer copy against `main`'s — both exit 0,
so the merge does not owe the ledger anything.

## What remains for a verifier

- **Criterion 2 is open by construction.** Only a run against the owner's real `~/.claude.json` and
  real router home can show `namecheap`'s own reason, and that is outside this item's sandbox rules.
- **F1 wants an item.** The reproduction above is a real approval bypass on the `index` path. It
  predates R17 and is not made worse by it, but the argument for keeping the row is "this row is the
  record", and the row as written destroys `digest` and `pending`. F2 has the same cause.
- **F3's four paths are gaps in criterion 1**, not in the change: none of them reaches
  `buildManifest`, so none of them is a row that was deleted. Closing them is separate work.
- **Neither divergence has a parity row.** Both are recorded in `surface.tsv`'s `cli-watch` note
  and in the lane's header comment, and both belong to the pool group rather than to `cli`.
- **The out-of-family coverage is one lane, not two.** Only agy is genuinely out of family; the
  Fable lane is a second Claude. Codex and grok were both unavailable, which is why.
- **The gate's exit 1 is argued, not measured, as pre-existing.** The argument is in the section
  above and it is strong, but `parity-gate.sh` was not run on `main` for a side-by-side.
- **The census and the cutover target disagree**, and the gate says to take that to the owner:
  "92 enumerated rows less 1 standing exclusion is 91, and the decided target is 82." That predates
  this item and is nobody's task here.
