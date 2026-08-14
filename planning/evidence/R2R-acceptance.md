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

Each was found by a lane rather than by reading, and each is a real gap in merged code that no test
could reach while nothing ran the router as a process.

| # | Defect | Where | Found by |
|---|---|---|---|
| 1 | `PoolLogEvent.ready` was declared by R2 and **never fired** — the Swift router never logged `upstream "x" ready in Nms` | `UpstreamPool.commit` | the log lane's ordered diff |
| 2 | `ManifestStore` had no logger, so `manifest reloaded: N servers cached` was never emitted | `ManifestStore.current()` | the log lane |
| 3 | A missing command **hung for 60 seconds** and reported a timeout, where the reference reports `spawn <cmd> ENOENT` immediately. Cause: spawning through `/usr/bin/env`, which always exists | `StdioUpstreamTransport.open` | the cli lane's `import` comparison |
| 4 | A spawn failure's wire message was wrapped (`upstream "x" could not be started: …`) where the reference reports the raw message | `PoolError.message` | the same |
| 5 | The listener ignored `Connection: close`, so a client reading until the peer hangs up waited out the keep-alive window — the CLI's own `status` verb reported "no router answering" against a live router | `LoopbackHTTPServer.serve` | driving the CLI |
| 6 | Response header order differed from the reference (`Transfer-Encoding` before `Date`) | `HTTPWire.head` | the first live comparison |
| 7 | The startup log emitted the token line before the stale-manifest warning; the reference emits them the other way round | `RouterService.start` | the first live comparison |

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
