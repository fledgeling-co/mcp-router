# R2-W — acceptance evidence

**Item:** R2-W, the `~/.claude.json` watcher and its adoption protocol
**Spec:** `planning/specs/spec-R2W.md` · **Plan:** `planning/plans/plan-R2W.md`
**Branch:** `ai/r2w` · **Worktree:** `.worktrees/R2W`

R2-W renders nothing — no view, no surface, no interaction — so `UI_VERIFICATION.md`'s screen
ledger has no rows here and no app was launched. What follows is the behavioural evidence in its
place. Append only.

## Gates, each exit code captured on its own line, never through a pipe

| Gate | Result | Exit |
|---|---|---|
| `make test` | `Test run with 1263 tests in 158 suites passed` · `executed 1263 tests` | 0 |
| `make lint` | `Found 0 violations, 0 serious in 402 files` · `no-raw-design-values: clean` · `no-wire-codable: clean` | 0 |
| `bash scripts/acceptance/parity-gate.sh` | `parity: 72 of 82 rows proven, 10 blocked` | 1 |
| `bash scripts/acceptance/parity-cli.sh` | `cli: 15 verbs agreed, 0 did not` | 0 |
| `bash scripts/acceptance/parity-divergence.sh` | `divergences: 3 as declared, 0 stale` | 0 |
| `bash scripts/acceptance/parity-install.sh` | `four real agents under real launchd supervision, two per binary` | 0 |

The parity gate exits 1 by design and will until the cutover: the 10 rows still blocked belong to
D-j, D-k, D-l, D-m and R4-C, none of them this item's.

### The parity number, before and after

| | Measured | Exit |
|---|---|---|
| Before (`main`, in this worktree) | **69 of 82 proven, 13 blocked** | 1 |
| After | **72 of 82 proven, 10 blocked** | 1 |

The three rows are `cli/cli-watch`, `divergence/div-r2-d7` and `install/install-launchd-watch`, and
each moved because a lane compared two binaries and reported it — not because a verdict was edited.
`planning/parity/surface.tsv` now contains no row owned by `R2-W`.

Both measurements were taken **from `.worktrees/R2W`**. Defect D-o applies: `parity-fixture.sh:121`
normalises `"project":"[A-Za-z0-9]+"`, a class omitting `-` and `_`, so the number depends on the
name of the directory the gate runs from. `R2W` has no hyphen and normalises; the same tree read
from the repo root reports a different figure. Not this item's to fix, and stated so the two numbers
above are comparable to each other and to nothing else.

## X0 — which clause has which kind of evidence

X0 says a clause may not be discharged by a double standing in for the thing under test. Every
watcher test runs against a real scratch `HOME` on a real filesystem; the cross-process ones run a
second real process; the lock ones use real `flock` and real `SIGKILL`.

| Clause | Evidence | Type |
|---|---|---|
| W1 | `fastPathSpawnsNothing` — a second run over an untouched file spawns no child and leaves mtime, config and state byte-identical | real process + real files |
| W2 | `unparseableInitialReadWritesNothing` — all four files unchanged | real files |
| W3 | `failureBackoffIsHashSensitive`, `staleFailureRecordsArePruned` — a real failing command, a manual clock across the five-minute boundary, and an edit that retries at once | real process + clock |
| W4 | `modesAreHonoured`, `backupsArePrunedToTen`, and `adoptionEndToEnd`'s mode assertion on the real file | real files |
| W5 | `editedWhileIndexingIsLeftAlone`, `deletedWhileIndexingIsNotResurrected` — a sentinel-gated child, edited while held at the door | real process, deterministic |
| W6, X13 | `reservedAndSelfReferenceAreSkipped` — `router`, `mcp-router` and a loopback self-URL on 8879 | real files |
| W7 | `adoptionEndToEnd` — the sealed hash equals the hash of what is on disk after our own write | real files |
| W8 | `missingInputsWriteNothing`, `corruptStateRecovers`, and the pending path in `editedWhileIndexingIsLeftAlone` | real files |
| W9 | `httpEntriesAreAdopted` — an `http` entry reaches the indexer | real files |
| **W10** | `concurrentPatchSurvivesAdoption` — a second **real process** PATCHes `servers.json` while a real child is held mid-index; both the PATCH and the adoption survive | **two real processes** |
| X1, X4 | `lockingTheConfigItselfIsNotALock`, `boundedWait`, `killedHolderReleases` | real flock, real SIGKILL |
| X2, X2b | `configEditIsUnchanged`, `reentrantAcquireThrows` | real files + timing |
| X3 | `concurrentPatchSurvivesAdoption` — the other process completes its write *while* indexing is in flight | two real processes |
| X4b | `concurrentManifestApprovalSurvives` — an approval written to `manifest.json` mid-index is still there | two real writers |
| X6, X7, W-D1 | `restartIsIssuedBeforeTheStagingWrite`, `failedRestartIsOwedAndRetried`, `restartIsOwedBeforeTheWriteLands` | real files, injected kickstart |
| X9, X10 | `cli-watch` over the built binary; `homeComesFromTheEnvironment` | built executable |
| X11 | `install-launchd-watch` — a real scratch agent per binary | real launchd |
| X12a–d | the three lanes themselves | two binaries |
| X14, W-D7 | `flatRouterConfigIsRefused` — the flat file is byte-identical afterwards | real files |
| W-D9 | `sameNameDeletionIsReversed` — asserted so the behaviour is defined rather than discovered | two real processes |

## Mutations proved red, then restored green

A test that has never failed is not known to work. Each mutation was applied to the source, the
guard was watched to go red, and the source was restored **by re-applying the original edit** —
never `git checkout --`, which destroyed a fix earlier in this fleet. `grep` over the module
afterwards confirms no mutation residue.

| # | Mutation | Guard | Red evidence |
|---|---|---|---|
| 1 | Read `servers.json` before the lock inside `merge` | `concurrentPatchSurvivesAdoption` | **Did not bite** — exit 0. The stale read has to be taken *before indexing*, which lives in the runner. Recorded because a mutation that fails to bite is information: it located the real seam. |
| 1b | Hold `servers.json` from before indexing and write it back afterwards — the reference's actual shape | `concurrentPatchSurvivesAdoption` | red: `(names → ["probe"]) == ["patched", "probe"]` — the concurrent PATCH erased |
| 2 | Hold a `manifest.json` snapshot across indexing, as the reference does | `concurrentManifestApprovalSurvives` | red: `approvedByTheUser → nil` — the approval erased |
| 3 | Move the restart after the staging write | `restartIsIssuedBeforeTheStagingWrite` | **Did not bite** — the early return still fell through to the restart. Too weak a mutation; recorded rather than counted. |
| 3b | Put the restart *inside* the post-re-read block — `watch.ts`'s real shape | `restartIsIssuedBeforeTheStagingWrite` | red: `(kicks.issued → []) == ["scratch-label"]` — D7 reproduced exactly |
| L3 | Lock `servers.json` itself instead of the sidecar | inline red-green in `lockingTheConfigItselfIsNotALock` | the second writer takes an "exclusive" lock the first still holds |
| L6 | Nested acquire | `reentrantAcquireThrows` | asserted on elapsed time, so a guard that merely errored after the full timeout would fail it |
| 4 | Remove the early `requireParseableRouterConfig()` guard | `unparseableRouterConfigSpawnsNothing` | red: the `started` sentinel exists — a child was spawned for a config that could never be written |

Mutation 4 was added after the Phase D critic found the ordering divergence it guards.

Two of the eight mutations did **not** produce a red. Both are recorded above rather than quietly
replaced with ones that did, because "the mutation I first wrote was too weak" is the most common
way a mutation gate becomes decoration.

## Two things the gates caught that review did not

- **`RouterCore` may never name stdout.** `LogParityTests.stdoutIsNeverNamed` failed on
  `WatchRunner`'s default `emit`, which wrote the two `--verbose` lines to `FileHandle.standardOutput`.
  That target is linked into a process whose stdout **is** an MCP transport, so a stray byte there
  corrupts the protocol. The default is now a no-op and `WatchVerb` passes `Out.print`.
- **The hash oracle was lying.** `hashAgreesWithReference` reported a divergence on `{"k":"héllo"}`
  that turned out to be the harness: a non-ASCII codepoint does not survive `Process.arguments`
  here. Measured both sides byte for byte — `d3352a19…` on each — and moved the input to stdin. The
  12 cases now agree, including `1e400 → null`, `-0`, U+2028, a control escape and a surrogate pair.

## Out-of-family lane — measured unavailable, downgraded in-family

```
codex exec -m gpt-5.6-sol -c model_reasoning_effort=high -s read-only -o /tmp/r2w-codex-probe.md
  → exit 1, "You've hit your usage limit … try again at Aug 20th, 2026 1:29 PM", no -o file written
```

Logged as `codex: usage limit -> claude (downgrade)` for both the plan gate and the Phase D critic.
A logged downgrade carried into the pre-merge evidence — not a pass. The in-family plan review
returned **REJECT** with 2 critical, 3 high, 6 medium and 2 low; every finding is dispositioned in
`spec-R2W.md` §Triage, and two of them (the `ConfigEdit.edit` composition, and `manifest.json` being
a second contended file) changed the design rather than the prose.

## Phase D completeness critic — in-family, ACCEPT

`/tmp/r2w-phased.md` (gone). No critical and no high finding; the critic ran the suites itself (33 tests,
6 suites) and searched specifically for a path that could damage a real machine, finding none.
Four of its findings changed code:

- an unparseable `servers.json` was discovered only at the merge, so real children were spawned
  that the reference never spawns — now parsed before indexing, with mutation 4 above;
- `still pending` was logged on a path the reference logs nothing on;
- `WatchAdoption`'s header cited a `cli-watch` byte check that structurally cannot run under X12b;
- the lock's re-entrancy key was the path as spelled, and an flock-less filesystem would newly fail
  a control-API PATCH.

Full dispositions, including the four declared rather than changed, are in `spec-R2W.md` §Triage.

## Deliberately not done

- **No cutover.** R4-C is a separate item and needs a decision from the owner.
- **No `src/*.ts` change**, so D-i stays open on the TypeScript side as registered.
- **No reload endpoint** — refused by the parent's Phase D finding 6.
- **No lock on `manifest.json`'s other writers** — deferred child D-w3, declared as W-D6.

---

## V1 — the out-of-family review, re-run 2026-08-15

**Verdict: 6 findings — 3 fixed, 2 accepted and deferred/owned elsewhere, 1 an artefact of the
review racing the branch.** Full dispositions in `planning/evidence/V1-review.md`.

**Lane: `grok-4.6` at `high` effort, out of family, no downgrade** — `modelUsage: grok-4.6-build`,
30 turns, 49,498 reasoning tokens. This replaces the `codex: usage limit -> claude (downgrade)`
recorded above for both the plan gate and the Phase D critic: those reviews were in family, and this
one was not.

| Finding | Sev | Disposition |
|---|---|---|
| F3 | high | **Fixed.** `ServerParser.swift:82` traps on a staged `~/.claude.json` entry carrying `"idleMs": 1e400`, so a single staged server could abort the one-shot before indexing, on every launchd fire. Now `JSNumber.int` |
| F5 | medium | **Fixed.** A `~/.claude.json` deleted between the W5 re-read and the write was **recreated** from the stale snapshot, restoring session state the user had just discarded. The reference cannot: `statSync(CLAUDE_JSON)` at `watch.ts:328` throws. `ModeRule.preserveExisting` no longer carries a fallback, so the mode read is the throw |
| F6 | low | **Fixed.** X2a justifies not sharing `ConfigEdit.edit` partly because "it writes mode 0600" — it did not; the call was the mode-less overload. Now it does |
| F2 | high | **Accepted, deferred `D-v1f`.** `WatchRunStaging.swift:20→50` rewrites the whole ~268 KB document from a snapshot with no lock, so a concurrent Claude Code write is lost — X4b's own argument applied to the file the clause table never named. And a write landing between the rename and the post-write hash seals a foreign hash, after which every fire takes the W1 fast path and the entry never leaves user scope. Deferred because the reference has the identical window (`watch.ts:288`), so closing it is a **new declared divergence** and an R4 decision |
| F4 | medium | **Accepted, already owned by P2.** X2 claims `ConfigEdit.edit` is the only path into `servers.json`; `ImportVerb.swift:128` writes it unlocked. The ORCHESTRATOR already requires P2's rewrite to "use R2-W's sidecar flock rather than inventing a second scheme" |
| F1 | high | **Artefact.** It described `value.isFinite \|\| !value.isFinite` at `WatchRun.swift:314` — a deliberately broken mutation applied moments earlier to prove a test went red, and restored immediately after. The reviewer read the disk mid-edit and said so. Its by-product was real: it pointed at `ConfigLoader.intMember`, where the check is `isFinite` **only** with no range test, so `1e300` trapped there too — a third site now on the shared guard |

**Two further defects in this item were found by this runner before the reviews returned**, and both
are the same shape — a guarantee the tests could not observe:

- **The watcher ran with two homes.** `WatchPaths` honours `$HOME` (X10, W-D2) while
  `WatchRunner.init` defaulted `home:` to `RouterHome()`, which reads `NSHomeDirectory()` and ignores
  it. `WatchVerb.swift:14`, the only production caller, took both defaults — so under a scratch
  `HOME` the watcher read the scratch `~/.claude.json` and wrote the **real account's**
  `servers.json`, the exact hazard X10 exists to prevent. `homeComesFromTheEnvironment` asserts only
  the `WatchPaths` half, and `WatchTestSupport.swift:35-36` always passes a matching pair, so no test
  could see it. Fixed: the default is now `paths.routerHome`.
- **`WatchRun.swift:294`'s `Int(value)`** on `startupTimeoutMs`, unguarded, where `UsageStore.swift:184`
  in the neighbouring item already documents this exact trap and clamps for it.

Gates on the changed tree: `make lint` **0**, `make test` **0** (1359 tests, 167 suites),
`parity-install.sh` **0** — with the watch-agent row's one red run measured against a freshly built
detached `main` before it was dismissed; the Swift side answered identically on both trees and the
reference side was what flapped.
