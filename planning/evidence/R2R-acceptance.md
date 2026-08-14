# R2R — acceptance evidence

**Item:** R2R — Router: the process that actually serves · **Branch:** `ai/r2r`
**Worktree:** `.worktrees/R2R` · **Date:** 2026-08-14

Append-only. Each row names how a thing was verified, the commit it was verified at, and the result.
A later runner reads this **before** re-testing: a row whose files have not changed since its SHA is
the evidence, and re-running it proves nothing new.

This item has **no SwiftUI surface**. Its user-facing surfaces are the CLI's two streams and
`router.log`, and both are verified behaviourally against the live reference rather than by reading
source. No app was launched, no window was driven, and nothing took the user's screen.

---

## 0 · The ports, and the user's router

The user's live sessions are served on **8975** and **8976**. Neither was contacted at any point.
`lsof -nP -iTCP:8975 -sTCP:LISTEN` reported `node 11356` holding it before the first probe and after
the last one. Everything here ran on **8981–8997**, and every lane refuses to start if its port is
already listening.

One stray was created and cleared during development: the self-test's first shim piped `serve`
through `sed`, which made the real router a *child* of the shim, so killing the shim orphaned a
listener on 8981. Found because the next self-test run reported the cli lane as "could not run",
killed, and fixed at source — the shim now `exec`s for `serve`.

## 1 · The baseline, and a lesson about measuring it

| # | What | Command | Result |
|---|---|---|---|
| 0.1 | Baseline, **contaminated** | `bash scripts/acceptance/parity-gate.sh` with an uncompilable WIP file in the tree | **43 of 81, 7 DIVERGED** — every one a `proven-by-suite` row whose cited test "failed". None had |
| 0.2 | Baseline, clean | same, with this item's sources held out of the tree | **50 of 81 proven, 31 blocked, exit 1** |

0.1 is recorded because it will bite the next runner. `swift test` never built, so the suite lane
reported every citation it could not run as a failure, and the number moved by seven for a reason
that had nothing to do with either router. **A parity number measured over a tree that does not
compile is not a parity number.** Both gate runs in this file were taken with `swift build` green
first.

## 2 · The reference, measured before anything was built

Every parity clause in `spec-R2R.md` §3 was observed rather than inferred, on a scratch home on port
8991. The findings that changed the design:

| Observation | Consequence |
|---|---|
| `POST /mcp` is answered with **SSE** (`text/event-stream`, chunked, `event: message`), not JSON | the SDK's `StatelessHTTPServerTransport` returns `application/json`, so it is not used for the server half |
| the envelope order is `result, jsonrpc, id` on success and `jsonrpc, id, error` on failure | two different orders; no `Codable` encoder produces either by accident, so the relay serialises through R1's `JSStringify` |
| `OriginValidator` (SDK) answers `421 Misdirected Request` where the reference answers `403 Invalid Host header: <host>` | the framing refusals are hand-written and asserted against the live reference every run |
| `mcp-router status` prints `running   stdio  probe   undefined calls, idle 2s` | `cmdStatus` reads `c.calls`; `/status` emits `callsServed`. Reproduced through the same mechanism, not by hard-coding the word |
| `status` writes offline to **stdout** (exit 1); `usage` **throws**, so the same sentence lands on **stderr** behind `mcp-router: ` | the CLI keeps the streams apart and the lane compares them separately |

## 3 · Gates

| Gate | Command | Result | SHA |
|---|---|---|---|
| Build | `cd app && swift build` | green, 0 errors | `398d0c1` |
| Unit tests, new | `swift test --filter 'HTTPWireTests\|MCPEndpointTests\|ListenerFailureTests'` | **21 tests in 3 suites passed** | `398d0c1` |
| Unit tests, full suite | `swift test` | **692 tests in 100 suites passed** | `398d0c1` |
| SwiftLint (this item's files) | `swiftlint lint` | **0 new errors**; the repo carries 70 pre-existing ones in files this item does not touch | `398d0c1` |
| Manifest census | `bash scripts/acceptance/parity-manifest-check.sh` | `82 rows, consistent with control.ts and the fixture directory` | `398d0c1` |
| Lane negative control | `bash scripts/acceptance/parity-lane-selftest.sh` | **every new lane went red**, exit 0 | `398d0c1` |
| Parity gate | `bash scripts/acceptance/parity-gate.sh` | see §5 | `398d0c1` |

## 4 · The five new lanes, and their negative controls

Each lane is a **simultaneous two-router comparison**: both routers live, the same request or verb at
each, answers diffed. Each declares the `(group, id)` pairs it may write and refuses anything else.

| Lane | Rows | Seeded defect | Did it go red? |
|---|---|---|---|
| `parity-mcp.sh` | `mcp-endpoint`, `mcp-tools-list`, `mcp-tools-call`, `mcp-health`, `mcp-status`, `pool-p4`, `pool-reap-traffic`, `div-r2r-d8` | `--idle-ms` forced to 999999 | **yes** — `mcp-status` and `pool-reap-traffic` failed (`reference reported running,idle,running, Swift reported running,running,running`) |
| `parity-cli.sh` | the 8 `cli` rows | one word of stdout altered | **yes** — `cli-tools` failed (`0 tools from` vs `0 toolz from`) |
| `parity-log.sh` | `log-bytes` | `--idle-ms` forced to 999999 | **yes** — the idle-window line and the reap lines differed |
| `parity-state.sh` | `state-ondisk-compat` | served from an empty config | **yes** — the `tools/list` corpus differed |
| `parity-install.sh` | `install-launchd-serve` | the binary exits immediately | **yes** — `swift=no,no,yes,yes` against `reference=yes,yes,yes,yes` |

The self-test found two holes in **itself** before it found anything in a lane: the seed was read
from an environment variable, which a launchd agent does not inherit (so the install lane passed a
router that exits immediately), and the `stdout` mode leaked a listener. Both fixed.

### What each lane actually compared

- **mcp** — `/health` head and body; four framing refusals plus the 404; the whole `tools/list`
  envelope byte for byte; six `tools/call` shapes (ok, un-namespaced, unknown server, unknown
  method, `initialize`, `ping`); `/status` after an identical call sequence with `port` and
  `idleSec` normalised; a 6-second call held across a 3-second idle window at both routers; and a
  burst/idle/burst sequence read off `/servers` and compared as a sequence.
- **cli** — eight verbs, each run at both binaries over identical scratch homes, with **stdout,
  stderr and the exit code compared separately**. `import` additionally diffs the `servers.json` it
  wrote. `serve` compares binding, `/health`, the three log lines and the exit code on SIGTERM.
- **log** — one scripted session at each router; 13 lines diffed **in order**, normalised only for
  the ISO timestamp, measured durations and paths.
- **state** — the reference ran for real and left `servers.json`, `manifest.json`, `usage.jsonl` and
  `usage-stats.json`; the Swift router was then started on exactly those files, having written none
  of them, and served an identical `tools/list` and `/usage`.
- **install** — two real launchd agents under the installer's own contract (`RunAtLoad`,
  `ThrottleInterval 10`, `KeepAlive/SuccessfulExit=false`, both log paths): started at load,
  relaunched after `kill -9`, stayed down after `bootout`, wrote both log paths. `launchctl list`
  showed **0** stray agents afterwards.

## 5 · The parity gate

Run on 2026-08-14 with `swift build` green first, from `.worktrees/R2R`:

```
coverage by group — these are not all the same claim:
  control     11 of 15 proven, 4 blocked
  fixture     23 of 24 proven, 1 blocked
  divergence  13 of 15 proven (4 by suite only), 2 blocked
  pool         6 of  6 proven
  mcp          5 of  5 proven
  cli          8 of 10 proven, 2 blocked
  install      1 of  5 proven, 4 blocked
  state        1 of  1 proven
  log          1 of  1 proven

  control compares both routers on the wire. fixture compares the live reference against
  its own recording — reference currency, not two-router parity. pool compares a live
  reference measurement against a Swift real-process test, taken at different times.

parity: 69 of 82 rows proven (4 of them by suite only, not by wire comparison), 13 blocked. This is NOT a pass.

blocked, grouped by the item that would unblock them:

  D-j
    control     POST /servers/:name/approve                    AuthRoutes.approve exists and is never wired into ControlHandler's dispatc
    control     POST /servers/:name/auth                       AuthRoutes.authStart exists and is never wired into dispatch. The referenc

  D-k
    divergence  R1 D3 atomic servers.json writer preserves unk spec-R1 line 148 scopes this to the non-atomic four-key writer in src/inde
    install     import stdio servers out of ~/.claude.json     install.sh:77 runs `node dist/index.js import`. The CLI verb is counted se
    install     rewrite ~/.claude.json to point at the router  install.sh:141 rewrites the user's own config through a node -e script, ad

  D-l
    control     GET /usage/stream                              SSE. The response body is an open stream, so there is no byte oracle to di

  D-m
    control     GET /registry/search                           The reference calls live registries; two runs a second apart return differ
    fixture     registry-search                                The recording is one moment of a live registry call. Re-capturing it produ

  R2-R
    cli         auth                                           The Swift entry point now exists, so the original note is stale. The verb 

  R2-W
    cli         watch                                          The second launchd agent. The Swift config watcher is R2-W and does not ex
    divergence  R2 D7 reference loses a restart on an unparsea A latent bug in the reference, declared so the Swift watcher does not repr
    install     the watch launchd agent                        The second agent, same supervision contract, and there is no Swift watcher

  R4-C
    install     putting a cut-over machine back on TypeScript  docs/uninstall.sh restores the ~/.claude.json backup, but nothing has esta

The cutover requires 82 of 82. It has 69.
Flipping the installer on this evidence is the one outcome this gate exists to prevent.

exit=1
```

**69 of 82, 13 blocked, 0 DIVERGED**, against a baseline of 50 of 81. Every one of the five lanes
that was structurally blocked is now measurable rather than blocked:

| group | before | after |
|---|---|---|
| `mcp` | 0 of 5, all blocked | **5 of 5 proven** |
| `cli` | 0 of 10, all blocked | **8 of 10 proven** (`cli-watch` is R2-W's, `cli-auth` is on D-j) |
| `install` | 0 of 5, all blocked | **1 of 5 proven** (the other four are D-k's and R4-C's) |
| `state` | 0 of 1, blocked | **1 of 1 proven** |
| `log` | 0 of 1, blocked | **1 of 1 proven** |
| `pool` | 4 of 6, 2 blocked | **6 of 6 proven** — both rows needed traffic at a Swift endpoint |

The gate still exits 1, and correctly: 13 rows remain blocked and the cutover requires all 82. What
changed is that the five lanes are no longer blocked *for want of a product*.

**The gate was not edited to produce this.** `git diff` against `main` for the eight scripts §2.3
names is empty for seven of them, and one line for `parity-gate.sh` — the `LANES` default, which now
lists the five lane names R4's report at `:201` already printed headings for.

## 6 · Defects this work found and fixed

Each was found by a lane rather than by reading. **Four are gaps in merged code that no test could
reach while nothing ran the router as a process; three are bugs in this item's own new code, caught
by the lanes before they were committed.** The distinction matters and the original wording lost it
by framing all seven as pre-existing.

| # | Defect | Where | Pre-existing or new here | Found by |
|---|---|---|---|---|
| 1 | `PoolLogEvent.ready` was declared by R2 and **never fired** — the Swift router never logged `upstream "x" ready in Nms` | `UpstreamPool.commit` | pre-existing (R2) | the log lane's ordered diff |
| 2 | `ManifestStore` had no logger, so `manifest reloaded: N servers cached` was never emitted | `ManifestStore.current()` | pre-existing (R2) | the log lane |
| 3 | A missing command **hung for 60 seconds** and reported a timeout, where the reference reports `spawn <cmd> ENOENT` immediately. Cause: spawning through `/usr/bin/env`, which always exists | `StdioUpstreamTransport.open` | pre-existing (R2) | the cli lane's `import` comparison |
| 4 | A spawn failure's wire message was wrapped (`upstream "x" could not be started: …`) where the reference reports the raw message | `PoolError.message` | pre-existing (R2) | the same |
| 5 | The listener ignored `Connection: close`, so a client reading until the peer hangs up waited out the keep-alive window — the CLI's own `status` verb reported "no router answering" against a live router | `LoopbackHTTPServer.serve` | **new in this item** | driving the CLI |
| 6 | Response header order differed from the reference (`Transfer-Encoding` before `Date`) | `HTTPWire.head` | **new in this item** | the first live comparison |
| 7 | The startup log emitted the token line before the stale-manifest warning; the reference emits them the other way round | `RouterService.start` | **new in this item** | the first live comparison |

## 7 · What is owed, and not claimed

| Row | Why it is still blocked |
|---|---|
| `cli-auth` (owner `R2-R`) | the verb exists on both sides, but the Swift router answers 405 on `POST /servers/:name/auth` where the reference answers 400, because `AuthRoutes` is never reached from `ControlHandler`'s dispatch — defect `D-j`. Fixing it makes `control-differential.sh:465-479` record a stale-defect failure, so the gate goes red on a **fixed** defect. Its manifest note was corrected (the old one said "No Swift entry point", which is no longer true); its owner was **not** moved |
| `control-*` over a socket | `control-differential.sh` drives `ControlDiff`, an in-process oracle. This item makes `ControlHandler` reachable over a socket for the first time and that surface has no lane. Raised as `D-r2r-b` |

## 8 · Skipped deliberately

- **No UI acceptance pass.** This item renders nothing. `BoardRegistry.installed` is untouched and
  no destination was added, so there was no screen to drive and none was driven.
- **`docs/install.sh` was not executed.** It rewrites the user's own `~/.claude.json`. Its two plist
  modes were verified by extracting the writer and running it against a scratch directory: with
  `MCPR_ROUTER_BINARY` unset both agents run `node dist/index.js`; with it set, **only** the `serve`
  agent runs the Swift binary and `watch` stays on node.
- **The user's router was never stopped, restarted or contacted.**

---

## 9 · Independent re-run, and the hole it closed

A second runner picked this item up at `4309392` and re-measured rather than trusting §5. Two things
came out of it.

### 9.1 The HTTP upstream clients were compiled and never executed

§4's `mcp` lane seeded **stdio upstreams only**. `HTTPUpstreamTransport`, `HTTPUpstreamSession` and
`listTools`/`callTool` on an HTTP session were therefore built, linked, and never once run — on
either side. "The HTTP clients R2 deferred" is a named scope item of this brief, so a lane that never
reached them was claiming a delivery it had not measured.

The lane now stands a **third router** up on `:8998` and registers it as an HTTP-type upstream on
*both* sides, so the seventh `tools/call` shape travels **router → HTTP → router → stdio**. A
reference router is itself an MCP server over HTTP, which makes it the honest upstream to point at.
The case additionally asserts `fixture:ping` appears in the Swift answer, so both sides agreeing on
an *error* cannot pass it.

Three smaller holes closed in the same pass:

| Hole | Fix |
|---|---|
| `/health` compared two bodies that were never required to *be* anything — two empty answers diff clean | both sides must contain `"ok":true` before the comparison is believed |
| `tools/list` compared only the de-framed SSE payload, leaving the status line and every header uncompared on the row carrying the largest corpus | the SSE **head** is diffed as well as the body |
| `div-r2r-d8` asserted status and code only, so a Swift router that had stopped emitting a message at all would still have recorded the divergence intact | both messages must carry the `invalid JSON body: ` prefix **and** the suffixes must actually differ — it now goes stale from either end |

A dead `both()` helper that took arguments it never used was deleted.

### 9.2 The number, re-measured rather than inherited

Run from `.worktrees/R2R` with `swift build` green first, with the strengthened lane above:

```
  control     11 of 15 proven, 4 blocked      mcp          5 of  5 proven
  fixture     23 of 24 proven, 1 blocked      cli          8 of 10 proven, 2 blocked
  divergence  13 of 15 proven (4 by suite), 2 blocked   install      1 of  5 proven, 4 blocked
  pool         6 of  6 proven                 state        1 of  1 proven
                                              log          1 of  1 proven

parity: 69 of 82 rows proven (4 of them by suite only, not by wire comparison), 13 blocked.
The cutover requires 82 of 82. It has 69.
exit=1
```

**69 of 82, 13 blocked, 0 mismatched** — the same number §5 reported, reproduced independently and
now over a *stricter* mcp lane. The mcp lane itself reported `8 comparisons agreed, 0 did not`.

`exit=1` is the designed outcome and is **not** this item's failure: the gate returns 0 only at 82 of
82, which is the cutover's bar, and the cutover is R4's behind a decision the user takes. This item's
bar was that the five structurally-blocked lanes become measurable. They did.

### 9.3 Standing product constraints, checked directly

| Constraint | Verified |
|---|---|
| `command`, `args`, `env` never writable through the control API's PATCH | `ControlHandler.swift:268` — they are not read. R3 code; this item does not touch `ControlHandler` |
| MCP SDK pinned to an exact version, never a range | `Package.swift:29` — `exact: "0.12.1"` |
| TypeScript stays the installed default until R4's gate passes | `docs/install.sh` — `MCPR_ROUTER_BINARY` defaults to empty, so both agents run node. Setting it moves the **`serve`** agent only; `watch` stays on node because no Swift watcher exists |
| The Mac app talks to the router only over loopback HTTP | no second channel added; this item adds one listener, on loopback |

### 9.4 Normalisation, audited as an adversary

Every `sed` in all five lanes was read on the assumption it was hiding a real difference. What is
normalised: the ISO timestamp, measured durations (`<ms>ms`, `<s>s alive`), the scratch home, the
repo path, the port, and `import`'s `.bak-<epoch>` stamp. **No message text, level, ordering or count
is touched anywhere.** `mcp-status` additionally normalises `port` and `idleSec`, each named as a
coordinate or a clock, with the call sequence driven identically first so the counters stay
comparable. Empty-versus-empty is guarded explicitly in `mcp` (health body, list body) and `log`
(a `router.log` that does not exist records `fail`, never a clean diff).

The gate's own aggregation was checked for the double-write the §9.1 guard introduces:
`parity-gate.sh:172` treats **any** `fail` for a `(group, id)` as a mismatch regardless of a later
`ok`, so a row can never be rescued by a second verdict. The strengthening is fail-safe.

---

## 10 · The completeness critic, and what it changed

The third out-of-family gate was owed and had never run. codex is account-limited until 2026-08-20
and **exits 0 on that limit**, so it ran in-family: a fresh adversarial `claude -p` opus-5 reviewer,
briefed to refute and told that finding nothing is a failed review.
`codex: usage limit -> claude (downgrade)`.

**Verdict: REJECT — 0 blockers, 5 majors, 5 minors.** Two further blockers it had drafted died at
`64d0057` before it reported. Its own summary of the headline: *"No finding touches the headline
claim: the Swift router exists, all five lanes measure, the gate was not weakened, and 69 of 82 with
0 mismatches is the number the current tree produces."*

It refuted the gate-tampering charge on evidence rather than assertion: `parity-gate.sh` differs from
`main` by exactly one line, and `control-differential.sh`, `parity-control.sh`, `parity-fixture.sh`,
`parity-divergence.sh`, `parity-pool.sh`, `parity-suite.sh` and `parity-manifest-check.sh` have zero
diff lines each.

What it found was narrower and correct: **four rows recorded `proven` under notes describing an
oracle stronger than the one that executes.** Every major is fixed below.

| # | Finding | Fix |
|---|---|---|
| M1 | the negative control demonstrated failability for ~8 of 19 rows while reading as if it covered all of them; and `check()` scored a lane exiting non-zero with **no failing row** as "went red" | `check()` now requires at least one `fail`; two new seeded defects (`streams`, `toolset`); and the self-test prints a per-row roll-up **naming every row it has not shown able to fail**. 8 → **11 of 19 demonstrated**, with the other 8 named in its own output |
| M2 | `cli-help`'s note claimed `help`, `--help`, `-h` and an unknown verb; the lane ran `help` alone. Three of four arms in `src/index.ts:360-365` never executed | all four arms now run at both binaries. All four agree |
| M3 | `cli-tools` only ever saw an **empty** manifest (`run_both` re-seeds per verb); `cli-usage`'s note claimed "same store" when the verb throws before reading any store | a `PREP` hook adds a populated `tools` case built by each binary's own `index`; `cli-usage`'s note narrowed to what it proves — the offline error path |
| M4 | `install`'s observation 4 was `[ -f out ] && [ -f err ]`. **launchd creates both files at bootstrap**, so it was `yes` for any agent that loaded and could not tell the binaries apart | it now records **which streams carry bytes** as a pattern (`o`/`e`/`-`/`none`) and compares the pattern. Measured: both routers report `-e` — stdout is empty on both, so the old note "wrote both log paths" was false |
| M5 | `cli-serve` compared a three-literal `grep -oE` allowlist, discarding every other line either binary wrote — the one place normalisation removed content rather than a clock | the **whole** normalised stdout is diffed. It was concealing a real line: both routers open with `wrote a new control token -> <path>` |
| m1 | `parity-state.sh`'s `capture()` had no non-empty guard — the hazard `64d0057` fixed in the mcp lane, not carried across | both captured files must be non-empty or the lane exits 2 |
| m2 | the seven defects in §6 were framed as all pre-existing; three are bugs in this item's own new code | §6 now states which are which: 4 pre-existing, 3 new-here |
| m5 | §9.2's number carried no SHA, breaking this file's own contract at `:6-7` | §10.2 below carries one |

Not fixed, and why: **m3** (the Swift daemon serves `/health`, `/status` and `/mcp` and no control
routes) is a scope boundary the plan states in §8 and the spec never promised — reported, not
silently closed. **m4** (`RouterService`, `ServicePorts`, `UpstreamCalling` and the CLI carry no unit
tests of their own; their coverage is the five shell lanes) is real and is raised as a deferred
child rather than absorbed here.

### 10.1 A flaky row, found by re-running rather than by reading

`pool-reap-traffic` passed, then failed, then passed again across three runs with no code change
between them, reporting Swift `running,unknown,unknown`. `unknown` is a **failed read**, not an
observed state: the state probe's `curl`/`python3` missed its 5s budget under load. The read is now
retried up to five times, and — stricter than before — **any** `unknown` on either side now fails the
row, where previously only an all-unknown *reference* sequence did. Retrying an absent answer cannot
mask a divergence, because a real divergence reports a definite state that differs.

### 10.2 The gate, re-measured with every strengthened oracle in place

Run from `.worktrees/R2R` at `64d0057` plus the working tree committed as this section's commit,
`swift build` green first:

```
  control     11 of 15 proven, 4 blocked      mcp          5 of  5 proven
  fixture     23 of 24 proven, 1 blocked      cli          8 of 10 proven, 2 blocked
  divergence  13 of 15 proven (4 by suite), 2 blocked   install      1 of  5 proven, 4 blocked
  pool         6 of  6 proven                 state        1 of  1 proven
                                              log          1 of  1 proven

parity: 69 of 82 rows proven (4 of them by suite only, not by wire comparison), 13 blocked.
The cutover requires 82 of 82. It has 69.
exit=1
```

**69 of 82, 13 blocked, 0 DIVERGED.** The number did not move when the oracles were tightened, which
is the outcome that matters: the strengthening removed overstatement without inflating the count.

### 10.3 A contaminated run, recorded because it will bite the next runner

One gate run in this pass reported **7 rows DIVERGED**. Every one was a `proven-by-suite` citation
(`RealProcessTests`, `CallbackWireTests`, `ManifestIOParityTests`, `LogParityTests`). The tree
compiled (`swift build --build-tests` green in 2.1s) and all **43 tests in those 6 suites passed when
run directly**. The cause was load: `uptime` reported load averages of **10.86 / 18.80 / 22.06** with
an unrelated `proctor-mcp` whole-module release build saturating 16 cores, and the suite lane runs one
`swift test --filter` per citation.

This is §1's lesson in a second form. §1 recorded that a tree that does not **compile** produces a
meaningless parity number; this run shows a tree that compiles perfectly can produce one too, when
the machine is too busy to run the tests inside their budget. **Check `uptime` before believing a
DIVERGED row in the suite lane, and re-run the citation directly before treating it as a regression.**

### 10.4 The user's router, throughout

`8975` was held by `node 11356` before, during and after every run in this pass, and was never
contacted. Ports used: 8981–8998. After the final run: no stray listener on any harness port, no
stray `MCPRouterCLI`, and `launchctl list` showed **0** scratch agents.

---

## 11. Lint close-out: `make lint` red -> green without moving a limit

`make lint` was red at the end of the previous pass and nobody had seen the half that mattered.
`swiftformat --lint` runs **first** in that target and short-circuits on failure, so `swiftlint` never
ran: formatting was dirty, and 29 swiftlint violations sat behind it unreported. Running `make format`
first is what makes the second half visible.

Formatting itself then **grew** three files past the 400-line cap — `wrapFunctionBodies`,
`wrapLoopBodies` and `wrap` all add lines — so the violation count went **31** after formatting, not
the 29 counted before it. That is the order dependency worth remembering: format, then count.

### 11.1 What was measured, at what commit

| Gate | Command | Result |
|---|---|---|
| format + lint | `make lint` | **exit 0** — `Found 0 violations, 0 serious in 243 files`; `no-raw-design-values: clean`; `no-wire-codable: clean` |
| tests | `make test` | **exit 0** — `750 tests in 106 suites passed`, `executed 750 tests` (count guard) |
| vectors | `make parity` | **exit 0** — `358 vector cases compared (floor 358)` |
| parity gate | `scripts/acceptance/parity-gate.sh` | **69 of 82 proven, 13 blocked, 0 DIVERGED** (exit 1 by design; the cutover needs 82/82 and is R4-C's) |

The gate ran against a tree whose source hash was **identical before and after** the run
(`c522810737f8795abe12f49fc6fa656587a9e897` over `app/Sources` + `app/Tests`), so the number describes
the committed tree rather than a tree that moved during the measurement.

### 11.2 The limits were not moved, and the harness was not touched

No length, complexity or body-size limit in `.swiftlint.yml` was raised. Every structural violation
was closed by splitting along a seam:

| File | Was | Seam taken | Now |
|---|---|---|---|
| `LoopbackHTTPServer.swift` | 418 lines | the `NWConnection`-callback-to-`async` layer is not HTTP -> `HTTPSocket.swift` | 346 + 93 |
| `RouterService.swift` | 452 lines, actor body 308 | composition root vs request-to-response vs collaborator types | 169 + 229 + 67 |
| `MCPEndpoint.swift` | 445 lines, struct 315, one func 81 | pure wire shapes -> `Framing`; `tools/call` -> its own file, then split **refuse / invoke / record** | 255 + 80 + 158 |
| `StdioUpstreamTransport.swift` | 415 lines, `open` 63 | `open` split into `spawn` (command line -> running child) and the MCP handshake half | see §11.3 |

`git diff --stat -- scripts/` against `HEAD` is **empty**: this pass changed no harness script. Against
`main`, `parity-gate.sh` still differs by exactly one line, and that line adds five lane names to
`LANES`, which makes the gate broader rather than weaker.

### 11.3 One config change, and why it is not a loosened limit

`opening_brace` gained `ignore_multiline_statement_conditions: true`. This is a genuine deadlock
between the two tools rather than a violation being excused: SwiftFormat's
`wrapMultilineStatementBraces` puts the opening brace of a wrapped multi-line condition on its own
line, and SwiftLint's `opening_brace` wants it on the same line. **Verified rather than assumed** —
moving the brace by hand and re-running `swiftformat` put it straight back, so no source text
satisfies both and the gate was unsatisfiable without a decision.

It is settled the same way this repo already settled `trailing_comma` ("SwiftFormat owns comma style;
two tools fighting is worse than either"), but narrowed to the one construct rather than by disabling
the rule: brace position on declarations, function signatures and type headers is still enforced, and
`ignore_multiline_function_signatures` was deliberately **left false** — the one signature that hit it
was shortened to fit instead.

### 11.4 Two assertions got stronger, not weaker

`optional_data_string_conversion` fired on seven `String(decoding:as:)` sites. That initialiser
substitutes U+FFFD for invalid UTF-8, so a wire assertion built on it passes on bytes no peer could
decode. All seven moved to the failable `String(bytes:encoding:)`:

- in `HTTPWireTests`, through a `#require`-backed `utf8(_:)` helper, so the decode fails at the line
  that produced the bytes instead of resurfacing as a confusing string mismatch;
- in `Loopback.isWhole`, a head that is not valid UTF-8 is now treated as not-yet-whole rather than
  having a `content-length` read out of replacement characters.

The test count did not drop: 750 before, 750 after.

### 11.5 Two writers were in this worktree at once

Recorded because it will bite whoever reads this next. While this pass was running, a second live
agent — a workflow **resume** (`wf_48b3dafa-109`, "the lost item is TICKET-123") re-dispatching
`planning/fleet-runner.js` — was writing into `.worktrees/R2R` at the same time, and created
`AuthVerb.swift` and `StdioUpstreamSession.swift` unprompted at 22:00:26 and 22:00:50. One `Edit` in
this session landed on a file that agent had rewritten seconds earlier.

The two sets of changes turned out **complementary** rather than conflicting, and the combined tree is
what the table in §11.1 measures. But the near-miss is the point: a resume that believes a runner is
lost will re-dispatch it into the same worktree, and a runner that looks idle from outside is
indistinguishable from a dead one. Nothing here should be read as evidence that concurrent writers are
safe — this one happened to land clean.
