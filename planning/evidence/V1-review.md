# V1 — the out-of-family review of R3 and R2-W, re-run

**Item:** V1 · **Branch:** `ai/v1` · **Worktree:** `.worktrees/V1`
**Brief:** `planning/features-to-triage/V1-outside-review-router.md`
**Date:** 2026-08-15

This item is a review. It adds no product surface, so the design stage is empty by construction and
no mock exists. What it produces is this document, the dispositions below, the fixes the small
findings earned, and one acceptance file (`app/Tests/RouterCoreTests/OutsideReviewV1Tests.swift`)
covering only what changed.

---

## Why this ran

The pipeline routes three reviews out of family on purpose, because every other reviewer in it is
Claude auditing Claude. The two items reviewed here had the weakest coverage in the repository, and
the difference between them matters:

- **R3** — its **Phase D completeness critic never ran at all**. `planning/evidence/R3-acceptance.md`
  §"Phase D" records both lanes failing: codex hit an account limit, and *two* in-family `claude -p`
  critics were launched and **neither returned** — after 23 minutes the first had consumed 22 seconds
  of CPU against 96 resident `claude` processes. What reviewed the shipped code instead was, in that
  file's own words, "a systematic pass by the runner … the author checking the author, which is the
  exact weakness the out-of-family gate exists to remove."
  **Until this item, no independent reader had ever read R3's implementation.**
- **R2-W** — both its reviews ran **in family** and were logged as downgrades. A Claude wrote it, a
  Claude reviewed it, a Claude signed it off — on code that mutates the user's own configuration
  files, unattended, on a launchd timer.

## The lane

The owner's instruction, verbatim: *"Use grok cli and grok-4.6 high for the out-of-family reviews.
Codex is blocked"*.

```
grok --model grok-4.6 --effort high --cwd <worktree> \
     --disallowed-tools write,search_replace,run_terminal_command \
     --max-turns 200 --output-format json --prompt-file <brief>
```

**Model on the wire, captured per run** from the JSON envelope's `modelUsage`, alongside the
reasoning-token count that proves the effort setting took:

| Review | `modelUsage` | turns | reasoning tokens | cost | findings |
|---|---|---|---|---|---|
| R3 | `grok-4.6-build` | 22 | 33,581 | $0.397 | 15 |
| R2-W | `grok-4.6-build` | 30 | 49,498 | $0.524 | 6 |

**No downgrade. Both reviews ran out of family at the effort asked for.** The reviewer was given
read-only tools (`read_file`, `grep`, `list_dir`); `write`, `search_replace` and
`run_terminal_command` were removed so it could not modify the tree it was auditing.

### A lane trap worth carrying forward

**`grok` exits 0 when session initialisation fails.** The first dispatch of both reviews returned
**exit code 0** with a 337-byte body containing only:

```
{"type":"error","message":"Couldn't create session: Internal error: \"session initialization
 failed: tool error: Requirements unsatisfied: [RequirementError { tool:
 \"GrokBuild:scheduler_list\" … }]\""}
```

The cause was over-narrow tool removal: stripping `scheduler_create`/`scheduler_delete`/`monitor`
while leaving `scheduler_list` broke a dependency the harness validates at startup. A gate keyed on
`$?` would have recorded two passing reviews that never happened — the same shape as the
`codex exec` usage-limit trap R3 already recorded. **The only honest tells are the payload and the
`modelUsage`/`num_turns` fields.** Both are checked above.

---

## R3 — 15 findings

Every finding was re-derived against the source before disposition; none is taken on the reviewer's
word. Line numbers are the reviewer's and were each opened and confirmed.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| F1 | critical | `ServerParser.swift:81-82` — `Int($0)` on `idleMs`/`startupTimeoutMs` traps | **Accepted · fixed** |
| F2 | critical | `UsageRecord.swift:84` — `Int32($0)` on `pid` traps | **Accepted · fixed** |
| F3 | critical | A successful add/remove/patch never reaches the live process | **Accepted · deferred `D-v1a`** |
| F4 | high | `POST /servers/:name/approve` is 405 | **Accepted · already owned (`D-j`, P1 in flight)** |
| F5 | high | Usage aggregates are never debounce-flushed | **Accepted · deferred `D-v1b`** |
| F6 | high | `control.token` is not `0600` | **Accepted · fixed** |
| F7 | high | `servers.json` is not written `0600` | **Accepted · fixed** |
| F8 | high | Attribution starts after accept rather than completing inside it | **Accepted · deferred `D-v1d`** |
| F9 | medium | `firstSeen ??=` implemented as "key absent" | **Accepted · fixed** |
| F10 | medium | Registry `??` treats a JSON `null` as a value | **Accepted · fixed** |
| F11 | medium | `forget` compares ring servers with Swift `String ==` | **Accepted · fixed** |
| F12 | medium | `%ZZ` answers 400 where B23 requires a throw; undeclared | **Accepted as a register gap · recorded, not code-changed** |
| F13 | medium | **B44 is factually false**, and the 400 is an undeclared divergence | **Accepted as a spec defect · recorded** |
| F14 | medium | An unreadable stats file is a silent empty history | **Accepted · comment corrected, warning deferred `D-v1c`** |
| F15 | low | `Number("0x1"+16 zeros)` is 2⁶⁴ in JS and `NaN` here | **Accepted · deferred `D-v1e`** |

**Accepted 15 · rejected 0.** That is an unusual ratio for this fleet — earlier items rejected 5 of
11 and 2 of 16 — and it is the direct consequence of R3's implementation never having been read by
anyone but its author.

### The three that matter most

**F3 — the control API's writes never reach the running router.** `RouterServiceDispatch.swift:107`
builds a fresh `var deps` per request from `config`, hands `&deps` to the handler, and then
**discards it**. `ControlHandler` assigns `deps.upstreams = try ConfigEdit.reload(…)` at three
places (`:161`, `:255`, `:344`) — every one of them writes into a local that dies at the end of the
function. `RouterService.config` is a `let` (`:37`, assigned once at `:67`) and the pool is built
once from it (`:82`). So `POST /servers` answers **201**, the file on disk is correct, and
`GET /servers` still lists the old set; the pool cannot serve the new server until the daemon
restarts. The reference does this in-process (`src/control.ts:109-112`).

This is a **seam defect between R3 and R2-R**, which is exactly the class a per-item reviewer cannot
see: R3's tests pass `&deps` and correctly assert the mutation, and R2-R's tests never exercise the
control path's live-map effect. It is not in the deferred register (`D-j`/`D-k`/`D-l`/`D-m` are all
something else). Deferred rather than fixed here because the fix is not small: the actor's config
must become mutable *and* the pool must be told, which has in-flight-lease semantics this item has
no mandate to settle.

**F6 + F7 — two secrets written at the umask default.** The reference writes `control.token` at
`0600` inside a `0700` directory (`src/control.ts:51-53`) and commits `servers.json` through a
`0600` temporary (`src/control.ts:95`). Both Swift call sites used the mode-less `FileSystem`
overloads, so both landed at `0644`. `control.token` gates the endpoint that installs a server, and
installing a server runs an arbitrary command line with the user's environment — the type's own
documentation said the token "lives in a `0600` file no web page can read" while the code did not
make it so. `servers.json` holds every server's `env`, which is where API keys live; B10 keeps those
values off the wire, and nothing was keeping them off other accounts.

The codebase already had both the API and the precedent: `FileAuthStore.swift:64,66` writes its
records at `0700`/`0600` through `FileModeWriting`. That protocol landed with **R5, after R3**,
which explains the omission and does not excuse its survival — and **B18 never named a mode at
all**, so no reviewer had a clause to check against. Both reviews found F7 independently.

**F1 + F2 — a JSON number can halt the process.** `Int(_: Double)` and `Int32(_: Double)` are
trapping conversions. `JSONCursor.parseNumber`'s own comment records that `1e400` becomes an
infinity exactly as `JSON.parse` does, and `1e300` is finite and far past `Int.max`. Measured:

```
$ swift /tmp/v1-trap.swift        # Int(Double("1e400")!)
Fatal error: Double value cannot be converted to Int because it is either infinite or NaN
exit 133
```

`ServerParser` is on the path of every config load, every `ConfigEdit.reload` after a control-API
write, and every watcher fire, so `{"idleMs": 1e20}` — which the reference stores and serves — takes
the daemon down *after* the write has landed, and again on every restart. `UsageRecord` is on
`UsageStore.init`'s `readTail`, so one line of `usage.jsonl` decided whether the daemon could start.

The telling detail: **`UsageStore.swift:184` already carried a comment explaining this exact trap**
("`Int(1e300)` traps, so converting first would let any caller halt the router with a query string")
and clamps correctly, as does `RegistrySearch.jsSlice`. The lesson was learned inside R3 and not
applied to its two neighbours. All four sites now share one guard, `JSNumber.int` / `JSNumber.int32`.

### F12 and F13 — two register/spec defects, recorded rather than coded around

Neither is a code change; both are places the **documents** are wrong, which R4 consumes as its
expected-difference rules.

- **F12** — B23 requires a malformed escape such as `/servers/%ZZ` to propagate a `URIError` as the
  reference does. The port answers `400 {"error":"URI malformed"}`. That is the better behaviour and
  it is **not in the D1–D5 table**, so by this spec's own rule ("a difference not listed here is a
  regression") R4 must read it as one.
- **F13** — **B44 is false as written.** It says a primitive body "coerces to `{}` per `body ?? {}`,
  so a null-bodied PATCH still edits, reloads and returns 200". But `??` is nullish — the spec's own
  S2 — so `42 ?? {}` is `42`, and `'projects' in 42` is a `TypeError` that kills the reference
  process. `ControlHandler.swift:289-297` answers 400 with V8's own TypeError text and documents the
  reasoning at length; that is right, and it is also an undeclared divergence.

Both are reported to the orchestrator for R4's register rather than edited into `spec-R3.md` here,
because the divergence table is the artefact R4 reads and changing it is R4's call, not a reviewer's.

---

## R2-W — 6 findings

| # | Sev | Finding | Disposition |
|---|---|---|---|
| F1 | high | `startupTimeoutMs()`'s guard is a tautology | **Artefact of the review racing this branch — see below** |
| F2 | high | Unlocked rewrite of `~/.claude.json` can drop live session state | **Accepted · deferred `D-v1f`** |
| F3 | high | `ServerParser.swift:82` traps on a staged `~/.claude.json` entry | **Accepted · fixed (same fix as R3 F1)** |
| F4 | medium | X2 is false: `import` writes `servers.json` with no lock | **Accepted · already owned (P2)** |
| F5 | medium | A `~/.claude.json` deleted after the W5 re-read is recreated | **Accepted · fixed** |
| F6 | low | X2a's "`edit` writes mode 0600" is not what the code does | **Accepted · fixed (same fix as R3 F7)** |

### F1 is not a finding about shipped code, and saying so matters

The R2-W review ran **while this branch was being edited**, and its transcript says so: *"The
sources changed after the first pass — I'll re-read the implementation as it is now so findings match
the disk."* What it then read at `WatchRun.swift:314` was `value.isFinite || !value.isFinite` — a
**deliberately broken mutation I had applied moments earlier to prove the test went red**, and which
was restored immediately afterwards.

The reviewer was right about the code in front of it: that guard is always true. It is recorded here
as an artefact rather than a defect because the shipped guard is not that. Two things follow, and
both are worth keeping:

1. **An independent reviewer caught a tautological guard on sight**, which is a real (if accidental)
   validation of the lane.
2. Its remark that **`ConfigLoader.intMember` does the `isFinite` check correctly** sent me to
   `ConfigLoader.swift:143` — where the check is `isFinite` **only**, with no range test, so
   `1e300` traps there too. That is a third site the review did not claim and would not have been
   found without it. It now uses the shared guard.

A review racing an edit is a methodology fault of mine, not the reviewer's: the review should have
been finished before the fixes began.

### F2 — the window this item declared for one file and not the other

X4b applied W10's argument to `manifest.json` and refused to hold a snapshot across indexing. The
same argument reaches `~/.claude.json` and no clause covers it: `WatchRunStaging.swift:20` re-reads
the file, and `:50` writes the **whole ~268 KB document** back from that snapshot, unlocked. Claude
Code rewrites that file constantly, so any of its writes landing in between is lost — including the
`projects` and session state the watcher has no interest in.

**Deferred rather than fixed**, and the reason is the one that governs this whole port: the
reference has the identical window (`src/watch.ts:288`), so closing it is a *new declared
divergence* on the file the item's own header calls "live session state for every project on the
machine". That is a design decision with an R4 consequence, not a review's to take unilaterally.
The reviewer's second interleaving — a write landing between the rename and the post-write hash,
sealing a foreign hash so every later fire takes the W1 fast path and the entry stays in user scope
forever — is the sharper half and is carried into the child.

---

## What was fixed, with the red proof

Nine findings earned code. Every guard was proved by applying a mutation, watching it go red, and
restoring **by re-applying the original edit** — never `git checkout --`, which destroyed a fix
earlier in this fleet. A `grep` for mutation residue afterwards is clean.

| # | Mutation | Guard | Red evidence |
|---|---|---|---|
| A | `home ?? RouterHome()` — the shape it shipped as | `routerHomeFollowsTheSameHome` | `runner.home.root → "/Users/lukerhodes/.claude/mcp-router"` against a scratch `HOME` |
| B | Drop the range guard on `startupTimeoutMs` | `hostileStartupTimeoutDoesNotAbort` | **signal 5** · `Fatal error: Double value cannot be converted to Int` |
| C | Remove the token's mode arguments | `controlTokenIsWrittenPrivately` | `fileMode(root) == 0o700` failed |
| D | Remove `ConfigEdit`'s temporary mode | `editedConfigIsPrivate` | `fileMode(servers.json) == 0o600` failed |
| E | `ServerParser` back to `map { Int($0) }` | `hostileServerNumbersDoNotAbort` | **signal 5** · same fatal error |
| F | `.preserveExisting` falls back to `0o600` | `deletedStagingFileIsNotRecreated` | no error thrown; the deleted file was recreated |
| G | `firstSeen` tested with `== nil` only | `nullFirstSeenIsReplaced` | `seen → nil` — the null survived |
| H | `forget` back to Swift `String ==` | `forgetDoesNotDropAnEquivalentName` | `survivors → []` — **both** servers' history dropped |
| I | `nullish` reduced to absent-only | `registryMergeTreatsNullAsAbsent` | `merged → nil` — a null overwrote a real `useCount` of 42 |

**Mutation B did not bite on its first attempt, and that is recorded rather than replaced.** The
first fixture built its config through `JSStringify`, which serialises an infinity as `null` exactly
as `JSON.stringify` does — so the file said `"startupTimeoutMs": null` and the test silently
exercised the absent-key path instead. The vector only works when `1e400` reaches the parser as the
characters a user's editor would leave in the file. A mutation that fails to bite is information:
this one located a fixture that proved nothing.

### Three findings this runner made independently, before the reviews returned

Recorded separately because they are evidence about the lane rather than from it.

1. **The watcher ran with two different homes.** `WatchPaths` resolves `$HOME` (X10, W-D2);
   `WatchRunner.init` defaulted `home:` to `RouterHome()`, which reads `NSHomeDirectory()` and
   **ignores `$HOME`**. `WatchVerb.swift:14` — the only production caller — took both defaults. So
   under a scratch `HOME` with no `MCP_ROUTER_HOME`, the watcher read the scratch `~/.claude.json`
   and wrote the **real account's** `servers.json`, which is precisely the hazard X10's own comment
   says it prevents. The reference cannot produce it: one `homedir()` feeds both
   (`src/config.ts:79`, `src/watch.ts:45`).

   **No test could see it.** `homeComesFromTheEnvironment` asserts only the `WatchPaths`-derived
   paths, and `WatchTestSupport.swift:35-36` passes `routerHome:` and `paths:` explicitly, always as
   a matching pair. The harness supplied the agreement that production lacked — which is the same
   shape as every other finding here.

2. **`WatchRun.swift:294`'s `Int(value)`** — found by grepping the two items for the trap class, and
   found *because* `UsageStore.swift:184` documents it. The grok R3 review then found the same class
   at two further sites.

3. **`control.token` was not `0600`** — independently the same as R3 F6.

---

## Gates

Exit codes captured on their own line, never through a pipeline.

| Gate | Result | Exit |
|---|---|---|
| `make lint` | `Found 0 violations, 0 serious in 434 files` · `no-raw-design-values: clean` · `no-wire-codable: clean` | **0** |
| `make test` | `Test run with 1362 tests in 167 suites passed` · `executed 1362 tests` | **0** |
| `swift test --filter OutsideReviewV1Tests` | `Test run with 12 tests in 1 suite passed` | **0** |
| `scripts/acceptance/control-differential.sh` | `compared 49 rows: 47 ok, 2 failed` — both failures are the script's own named `D-j` rows | 1 |
| `scripts/acceptance/parity-install.sh` | `both binaries answer the watch agent's supervision identically` | **0** |
| `scripts/acceptance/parity-gate.sh` | `parity: 70 of 82 rows proven, 11 blocked` | 1 |

**Three tests failed once each across the full-suite runs and none of them survives scrutiny as a
regression.** `searchIsDebounced` and `reconnectIsNotDeadAfterItsFirstSuccess` failed on the first
`make test` and `perServerIdleWins` on a later one; each was then re-run in isolation three times and
passed every time, and each subsequent full run passed clean. All three are wall-clock timing tests
— `perServerIdleWins` gives a 25 ms idle window 150 ms to be reaped — on a machine running the rest
of the fleet. This diff touches **zero** files under `MCPRouterKit`, and `perServerIdleWins` builds
its `UpstreamConfig` through `stdioUpstream` (`PoolTestSupport.swift:186`), which never calls
`ServerParser` — so the one changed thing that could plausibly reach it provably does not.

Recorded rather than quietly re-run, because "it passed the second time" is exactly the claim that
needs its evidence attached.

**The differential's 2 failures are pre-existing and are `D-j`**, the defect P1 is fixing right now;
the script labels them itself. That all 47 other rows pass — including every `POST`/`PATCH`/`DELETE`
row, which all run through the `ConfigEdit` this item changed — is the evidence that the mode fix
moved no response bytes.

**The parity number is not comparable to R2-W's recorded 72 of 82.** Defect `D-o` makes the figure
depend on the name of the directory the gate runs from, this run is from `.worktrees/V1`, and the
`pool` lane could not run at all here (`the MCP client SDK is not installed` — `npm install` has not
been run in this worktree), so its rows are counted blocked rather than proven. Stated so the two
numbers are not mistaken for a regression.

### One lane that went red, and the measurement that settled it

`parity-install.sh` reported **FAIL** on the watch-agent row on its first run from this branch: the
two binaries disagreed on `one-shot-not-resident` (reference `no`, Swift `yes`). It was measured
rather than argued, on three runs:

| Tree | Run | reference | swift | Result |
|---|---|---|---|---|
| `.worktrees/V1` | inside `parity-gate.sh` | `yes,yes,no,--` | `yes,yes,yes,--` | FAIL |
| `.worktrees/V1` | standalone | `yes,no,no,--` | `yes,yes,yes,--` | FAIL |
| **detached `main`** (`/tmp/v1-baseline`, built from scratch) | standalone | `yes,yes,yes,--` | `yes,yes,yes,--` | **ok, exit 0** |
| `.worktrees/V1` | standalone, re-run | `yes,yes,yes,--` | `yes,yes,yes,--` | **ok, exit 0** |

**The Swift side answered `yes,yes,yes,--` in every single run, on both trees.** Every term that
moved moved on the **reference** side — a node binary this diff cannot reach, since nothing here
touches `src/*.ts`, `docs/install.sh` or any plist. It is a launchd/timing flake on a machine running
the rest of the fleet, and the lane is green on this branch.

Recorded in full rather than as "re-ran and it passed", because a red that clears on a re-run is
exactly the kind that gets waved through, and the thing that makes it safe to wave through is the
baseline column — not the re-run.

---

## Deferred children

Reported to the orchestrator, not registered here.

| Suggested id | Title | Deps | Mechanism |
|---|---|---|---|
| **D-v1a** | The control API's writes never reach the live process | R2-R, R3 | `RouterServiceDispatch.controlResponse` discards the `deps` it passed `inout`. `RouterService.config` must become mutable and the reloaded upstream list written back to it *and* to the pool, which needs a defined answer for leases already in flight. `POST /servers` then 201s and `GET /servers` lists it, as `src/control.ts:109-112` does |
| **D-v1b** | Usage aggregates are never debounce-flushed | R3 | `UsageStore.flushDebounceMilliseconds` is declared and never read; `record()` sets `dirty` and starts no timer, so `flush()` runs only from `reset`/`forget`/`stop`. Needs a 3 s debounce matching `src/usage.ts:203,232-240`. `UsageLogTests.rotatesAtTheBoundary` calls `flush()` itself, so it cannot go red on this |
| **D-v1c** | An unreadable `usage-stats.json` warns as B52 requires | R3 | `UsageStore` holds no log seam; the warning costs a logger threaded from `RouterService`. The misleading comment is already corrected |
| **D-v1d** | Attribution completes inside the accept handler, as B68 requires | R2-R, R3 | `RouterService.swift:131` spawns `Task.detached` and returns, so the handler can record a call before the identity is stored. `LibProcPeerResolver` is synchronous and answers in ~104 µs; the fix is to resolve on the accept path rather than hop off it |
| **D-v1e** | `JSToNumber` radix literals beyond `UInt64` | R3 | `JSToNumber.swift:47` returns `NaN` where `Number("0x1"+16 zeros)` is a finite 2⁶⁴. Parse the magnitude as a `Double` when it overflows `UInt64` |
| **D-v1f** | The watcher's unlocked `~/.claude.json` rewrite | R2-W | `WatchRunStaging.swift:20→50` writes the whole document from a snapshot, so a concurrent Claude Code write is lost; and a write landing between the rename and the post-write hash seals a foreign hash, after which every fire takes the W1 fast path and the entry never leaves user scope. Matches the reference (`watch.ts:288`), so closing it is a **new declared divergence** and an R4 decision |
| **D-v1g** | B23 and B44 are wrong in `spec-R3.md`; two undeclared divergences | R4 | F12 and F13 above. `%ZZ` answers 400 rather than propagating a `URIError`, and B44 states a `body ?? {}` coercion that nullish semantics make impossible. Both belong in R3's divergence table before R4 diffs against it |

Already owned, and **not** re-registered: **F4/`D-j`** (P1, in flight) and **R2-W F4** (P2 — the
ORCHESTRATOR already says `import`'s rewrite must "use R2-W's sidecar flock rather than inventing a
second scheme").

---

## What this says about the pipeline, in one line

Fifteen findings on R3 with **zero rejections**, on an item whose clause table is the most rigorous
in the repository and whose *spec* was reviewed out of family at `max` effort across three calls.
The spec review caught the spec. Nothing caught the code, because the gate that reads code is the
one that never ran — and the failure mode is legible in the findings themselves: a clause with no
mode in it (B18), a comment asserting a property the code lacks (the token, the stats warning), a
test that supplies the agreement production lacks (`WatchWorld.runner`), and a lesson learned in one
file (`UsageStore.swift:184`) and not applied to the file next to it.
