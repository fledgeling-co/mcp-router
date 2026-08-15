# G1 — acceptance evidence

Item: **G1 — stop the acceptance checks blaming the app for being out of date**
Branch `ai/g1` · worktree `.worktrees/G1` · base `9b6077b` (main)

Append, never rewrite. One row per thing verified, with the command that verified it.

---

## 0 · The measurement this item exists to close, re-taken on this base

| What | Measured here | Load |
|---|---|---|
| `mac-shell.sh` on a freshly built tree, before any change | **exit 2**, 36 ok, then `no Release build … run 'make build-mac-release' first` | 13.8 |
| `mac-shell.sh` after `make build-mac-release`, before any change | **exit 0, 39 assertions**, app never frontmost | 14.1 |

**The OWED `mac-shell.sh` verification is discharged: exit 0, 39 assertions.** The gate is green on
`main` once a Release build exists.

### The brief's predicted mechanism did not reproduce, and the measurement wins

The brief predicted `mac-shell.sh` fails at the first check with *"the shell window never appeared"*
after 40 poll iterations find no PID. Measured with a `PATH` shim making `open` exit 1:

```
OLD mac-shell EXIT=1
  the three-zone shell
  kLSServerCommunicationErr -600
```

`set -euo pipefail` aborts **at `open`**, so the poll loop never runs and that sentence is never
printed. The old code answers a refused launch with exit 1 and LaunchServices' raw error code — no
`FAIL:` prefix, no sentence. Same wrong direction as the brief describes, by a different and
slightly worse route.

### `-600` is real, recurring, and NOT explained by "the old process is still terminating"

Observed **three times today** on this machine: once in `m2-activity`, once inside `mac-shell` right
after the restoration relaunch, plus the orchestrator's original. In both of mine the previous
instance had already been **confirmed gone** by an observable wait. LaunchServices needs a moment
after a process exits before it will accept the same bundle again, so waiting for death is
necessary and not sufficient. The launcher therefore retries a **transient** refusal, bounded
(4 attempts, measured 3.4s to exhaust), and never retries a bundle that says it cannot be executed.

---

## 1 · Freshness: content, never mtime

`scripts/acceptance/build-freshness.sh`, the only place freshness is decided.

| # | Claim | Injection | Result |
|---|---|---|---|
| M1 | reads a **recorded** digest, not two live ones | no stamp | **BLOCKED 2** — "no record of what this build was built from" |
| M2 | binds to the **product** | executable replaced, stamp untouched | **BLOCKED 2**; restored → 0 |
| M3 | covers **resources**, not only Swift | one `Control/Fixtures` JSON edited, no rebuild | **BLOCKED 2**; restored → 0 |
| M4 | a rebase does **not** block (inverse mutation) | `touch` all 217 inputs, no content change | **PASS (0)** |
| M10 | covers the whole **bundle**, not just the mach-o | `Info.plist` inside the `.app` altered, executable byte-identical | **BLOCKED 2**; restored → 0 |

M4 measured against the check it replaces, same input:

```
newer-than-binary sources now: 217        git status --porcelain app/ -> (empty)
NEW content check   : status=0  (PASS)
OLD M11 mtime check : BLOCKS — 4 sources 'newer' than the app
```

**That is `D-m11-a` closed.** M10 exists because the review found that hashing the mach-o alone let a
swapped resource read fresh.

### End to end, through a real script — the item's headline claim

One real source edit (`ControlAPIClient.swift`, the offline copy), **no rebuild** — exactly what a
merge or rebase produces:

```
NEW mac-shell.sh : EXIT=2
  BLOCKED: this Debug build is STALE: the sources it was built from hash bf5f13345f19
  and the tree now hashes 0a2ade578ac9. … Run 'make build-mac'.

OLD (main) mac-shell.sh, identical tree : EXIT=2
  <lists the 4 MENU_SOURCES by mtime>
```

The new message names **staleness** and the remedy and names no screen. The old one blocked on the
mtime of four files that **had not changed**, while being blind to the one that had —
`ControlAPIClient.swift` is not in its list.

### The holes named rather than hidden

- If `xcodebuild` exits 0 having skipped work its dependency graph did not see, the stamp records
  the current tree beside a product that does not reflect it, asserting a *pairing* xcodebuild never
  claimed. Detecting it needs evidence the link ran, which xcodebuild does not expose here.
- The `Debug-iphonesimulator` stamp is written by `make build-ios` and **consumed by no caller**:
  `i2`/`i3` build their own product every run. It exists so no configuration is unstampable.
- The digest covers the Mac app's **linkage closure** (`MCPRouter/` + `MCPRouterKit` + `MCPRouterUI`
  + the three manifests). `project.yml` lists only those two products as its dependencies, so a
  `RouterCore`/`MCPRouterCLI` edit does not change this product. Digesting them would block every
  Mac acceptance run on a router edit — `D-m11-a` reintroduced in new clothes.

---

## 2 · One launcher, and a verdict per observation

`scripts/acceptance/mac-app.sh` replaces five copies and adopts `m8`'s bundle-bound pid.

| # | Claim | Injection | Result |
|---|---|---|---|
| M5 | `open` refusing is not the product's fault | `PATH` shim exiting 1, **shim asserted to have run** | **BLOCKED 2** naming LaunchServices, quoting its stderr; 4 bounded attempts |
| M6a | a launch that produces no process is the product's | stub bundle whose executable exits at once | **FAIL 1** |
| M6b | a bound process that dies is the product's | stub that lives, is bound, then exits | **FAIL 1** naming the pid |
| M9 | a previous instance that will not die blocks **before** `open` | immortal stub matching the bundle | **BLOCKED 2**; an `open` shim marker proves `open` was never called |
| M11 | a bundle that cannot be executed is the product | bundle with the executable removed | **FAIL 1** — "this bundle cannot be executed" |

### A bug in my own launcher, found by the mutation and not by reading

M6b first fired the wrong arm. Measured: `ps -o comm=` reports `/private/var/…` while the caller
passes `/var/…` — `/var` is a symlink — so the prefix match failed and a **running** app read as
"never appeared". A false product failure, in the file written to remove false product failures.
Both sides are now resolved to their physical path, after which M6b hits its own arm exactly.

### `pgrep -f` was killing other runners' apps

`pkill -f`/`pgrep -f 'MCPRouter.app/Contents/MacOS/MCPRouter'` matches **every** MCPRouter on the
machine, and this fleet runs several worktrees at once. `ps -o comm=` was verified to return the
full 120-character path untruncated rather than assumed.

### Speed had a cost, and it is paid here

Waiting on observables returns in **0.85s** where the old path floored at 4s (`sleep 1` + `sleep 3`).
That moved the app's own startup focus activity out of the sleep and **into the caller's
assertions**: one m7 run in three failed with *"the partial assertions brought MCP Router to the
front"*, where main's m7 on the same build did not. `mac_app_settle_behind` applies at hand-off the
correction `mac-shell` already did per check, so all five scripts get it. m7 then ran **3/3 green**.

---

## 3 · A build failure judged by its reason, not its phase

`scripts/acceptance/xcode-outcome.sh`. The first design called any build failure BLOCKED 2; the
review rejected that and was right — *"your code does not compile"* is a claim about the product.

10 synthetic logs, all correct: compile ×2, infra ×4 (destination, boot, lost connection, signing),
test ×2, unknown ×1, and the trap — `error:` **inside a test message** classifies as `test`, because
the pattern is anchored to `file.ext:line:col: error:`. `unknown` maps to BLOCKED 2, since guessing
"product" from an unrecognised log is how a harness invents a defect.

---

## 4 · `D-i2-guard`: the guard was deleted, not repaired

`i2` grepped `PhoneShell.swift` for `var awaitingKey: PairingCopy.Key?`. Item I3 **deleted** that
declaration — it survives only in a doc comment recording its removal — so the reader matched
nothing and took its own *"treat as a broken reader, not a pass"* branch: **permanently red against
a correct product**, and no rebuild could clear it.

Repointing the grep at `content(for tab:)` was rejected: it rebuilds the same defect. A grep matches
a comment, a preview or a dead arm as happily as live code, and still cannot show that `.discover`
*routes* anywhere. The XCTest suite constructs the surface on a simulator and asserts against it.

**Stated rather than claimed:** that the suite reddens if Discover were replaced by a placeholder is
asserted by construction and **not proven by a mutation here** — an iOS mutation needs a simulator
build this run did not spend. Registered below.

---

## 5 · `D-p3-a`: a lane script that nothing dispatches

`parity-manifest-check.sh` now asserts every `parity-*.sh` on disk is either in `parity-gate.sh`'s
`LANES` (read out of the gate, never copied) or named in `NOT_LANES` with a reason — and that each
exemption names a script that exists **and is referenced by the Makefile or the gate**, so "not a
lane" cannot mean "not run".

| Injection | Result |
|---|---|
| remove `stream` from `LANES` (the historical state, exactly) | **1 problem** naming `parity-stream.sh`; restored → 0 |

**The guard immediately found a live instance on `main`:** `parity-lane-selftest.sh` — R2-R's proof
that the five new lanes can go red, written as a script rather than a paragraph *"for one reason: a
paragraph is re-run by nothing"* — was executable, passing, and **run by nothing**. Measured: exit 0
in 4m35s, and it reports failability per row (**11 of 19 demonstrated**, naming 8 rows "recorded
proven by a lane whose ability to fail on THAT row is unproven"). Now wired into a `make` target
that `parity-selftest` invokes, running it when `dist/` exists and printing a loud SKIP otherwise.

---

## 6 · `D-p4-e`: one problem counted once

`note()` printed **and** counted, so a multi-line finding counted itself per line: 8 multi-line
sites, 23 `note` calls for 8 findings. `note` now opens a finding, `detail` continues one; 15
continuation lines converted, 12 findings countable. Demonstrated in §5: a four-line finding reports
**1 problem** where the old code reported 4. No finding, threshold or verdict changed.

---

## 7 · `D-p4-b`: the register's premise was wrong

The register says a fresh worktree "cannot run the parity gate unbuilt". Measured: it **does** —
exit 2, every affected row correctly blocked, the remedy named. The real defect is that it printed
the same environment fact **22 times** (11 lanes, then 11 again in the summary) and only after
walking the whole manifest. One notice now precedes the lanes. Nothing that computes coverage was
touched.

---

## 8 · `D-p1-e`: the row is blocked, deliberately

Two real mechanisms found and both fixed in the lane:

1. `oneshot` was sampled the instant the state file became non-empty — and that file is written *by*
   the still-running process, so whether `agent_pid` had stopped answering was decided by how fast
   the binary tore down, which differs between `node` and Swift and moves under load. It now waits
   for the job to be gone. (The old comment claimed the early sample prevented exactly the confusion
   it caused.)
2. `reran` was decided by a WatchPaths event staged while the first run might still be alive, and
   launchd does not queue a start for a job it considers running — so the event can be legitimately
   dropped and `reran` reads `no` for a correct watcher. Staging now follows the wait, and the staged
   file is written temp-then-rename.

**The row is still `blocked`.** P1's six runs show the two terms varying *independently*
(`yes,yes,no` ×2; `yes,no,yes` ×3), so a single-cause explanation was refuted by its own data, and
promoting on a green streak after a partial fix is re-running until green with extra steps. The lane
still runs and prints its observation every time, so evidence keeps accruing for whoever promotes
it. Row count unchanged at 83; the `# rows: 83` pin did not move. **Not called flaky.**

---

## 9 · Two defects found in other scripts, and how each was settled

**m8 was silently driving the RELEASE bundle.** Its `find … -name MCPRouter.app | head -1` returns
Release first, so once a Release build existed it reported **7 failures naming missing Settings
rows** — `Endpoint`, `Home`, `Idle reaper`, `Counting since`, the composed endpoint, the disabled
control's reason, the warm-set summary — on a completely correct app, because the binary under test
was never given the Debug scenario. Measured in the same minute: 14 passed / 7 failed on Release,
**20 passed / 1 failed** on Debug. Fixed by preferring Debug explicitly.

**m8's remaining `A9` failure is pre-existing, and that was established by control rather than
assumed.** Main's unmodified m8 against the same Debug bundle reads **19 passed / 2 failed** with
the same A9 failure — plus one this branch does not have: `focus moved from 'Proctor' to
'MCP Router'`, main's launcher taking the screen.

---

## 10 · A regression I introduced, found by the gate and fixed

`make parity-selftest` went **red**: *"35 behaved, 1 did not"*. The new NOT_LANES referenced-check
greps `$REPO_ROOT/Makefile`, and `parity-manifest-selftest.sh` builds a **minimal scratch repo with
no Makefile** — so it errored, reported 3 spurious problems, and took the unmutated baseline red,
which makes every red below it prove nothing. The sub-check is now skipped where there is no
Makefile (there is no wiring to have an opinion about); the LANES membership check still runs there.
**36 behaved, 0 did not, exit 0.**

---

## 11 · Gates

Recorded in the report. `parity-gate.sh` exits 1 by design until 83 of 83; the number is reported,
not the exit code.

**Parity is not a single number on this tree, and saying so is the honest result.** BEFORE read
**79 of 83 proven, 4 blocked, 0 DIVERGED**, with `install-launchd-watch` *agreeing* that run — where
the brief said 78/83 with 1 DIVERGED. Two AFTER runs then disagreed with each other, and the
difference was the machine, not the tree:

| AFTER run | conditions | result |
|---|---|---|
| first | a second parity chain in flight, holding `:8982` and `:8957` | 69 of 83, 14 blocked |
| second | one concurrent chain, `control` racing | 77 of 83, 5 blocked, 1 DIVERGED |
| **final** | **serial, nothing else in flight** | **78 of 83, 5 blocked, 0 DIVERGED** |

The final run is the one to read, and §13 gives it in full. The single row that moved from BEFORE
is the watch row, blocked deliberately. The `control GET /usage/stream` divergence seen in the
middle run — `D-d`, the known lsof-raced caller attribution, green in BEFORE on identical code and
outside this diff — did not reproduce serially, and is registered rather than closed.

The other two runs are recorded here rather than discarded because a gate whose number moves with
the load on the machine is itself the subject of this item.

---

## 12 · The orphan I wired in had the same defect I was sent to remove

Wiring `parity-lane-selftest.sh` into `make parity-selftest` (§5) made its exit code load-bearing
for the first time, and the first serial run after that turned `make parity-selftest` red.

**What it said:** `2 lane(s) did not notice their seeded defect. A lane that cannot go red is not a
check` — exit 1, a claim that two parity lanes are inert.

**What was true:** those two lanes never ran. The script's own line above said
`could not run (exit 2) — inconclusive, not a pass`, naming
`environment: something is already listening on :8982`, and then counted that inconclusive result
into the same `failures` total as a lane that ran and stayed green. An environment fact, reported as
a verdict on the check. That is precisely the class this item exists to remove, in a script I had
just made a gate depend on.

**Mechanism of the port itself, named rather than called flaky:** I had two parity chains in flight
at once — a long gate chain still inside its own `make parity-selftest` when I started a second.
The harness binds fixed ports per lane and says in its own message that it never shares one, so the
second run found `:8982` (mcp) and `:8957` (registry) held by the first. Both were free
immediately afterwards, and only one worktree exists, so no other fleet member was involved. The
same contention is what drove the parity gate to 69 of 83 with 14 blocked on that run.

**The fix** separates `blocked` from `failures` and gives the summary the same taxonomy as
everything else in this item: exit 1 only for a lane that ran and did not notice, exit 2 when lanes
could not run, and the blocked count reported alongside rather than folded in. The `demonstrated:`
line now says when a shortfall is unmeasured rather than inert.

**Proof of the taxonomy**, exercising the real tail block with synthetic counters:

| failures | blocked | exit | first line |
|---|---|---|---|
| 0 | 0 | 0 | `every new lane went red against a broken router.` |
| 0 | 2 | **2** | `BLOCKED: 2 lane(s) could not run…` |
| 1 | 0 | **1** | `1 lane(s) did not notice their seeded defect…` |
| 1 | 2 | **1** | `1 lane(s) did not notice their seeded defect…` |

The last row is the one that matters: a genuinely inert lane still wins over a blocked one, so the
fix cannot hide a real defect behind an environment excuse.

**Proof end to end**, holding `:8982` with a listener of my own:

- port held → `make parity-selftest` **exit 2**, `BLOCKED: 2 lane(s) could not run`, and the
  "did not notice" sentence absent. Deterministic — it reproduced the original failure on demand,
  which is also what rules out flakiness.
- port released → **exit 0**, `36 behaved / 0 did not`, `14 behaved / 0 did not`,
  `demonstrated: 11 of 19`, `every new lane went red against a broken router`.

## 13 · Parity, measured serially on an idle machine

| | proven | blocked | DIVERGED |
|---|---|---|---|
| BEFORE (main) | 79 of 83 | 4 | 0 |
| AFTER (`ai/g1`) | **78 of 83** | **5** | **0** |

The single row that moved is `install-launchd-watch`, moved from `proven` to `blocked` deliberately
(§8). Row count unchanged at 83 and the `# rows: 83` pin did not move. `parity-gate.sh` exits 1 by
design until 83 of 83.

`D-g1-a` — the one-off `control GET /usage/stream` divergence on caller attribution — **did not
reproduce** on this serial run; control measured 15 of 16. It stays registered rather than closed,
because a single non-reproduction is not a fix and `parity-stream.sh` is outside this diff.

## 14 · Deferred, with a mechanism each

| Child | Mechanism |
|---|---|
| `D-g1-a` | **`control GET /usage/stream` is nondeterministic on caller attribution.** Same class as `D-p1-e`, different lane: `cwd`/`project`/`client` differ between runs because the reference's caller lookup races (`D-d`). Green in one run and DIVERGED in the next on identical code. Either give the lane a deterministic client or declare attribution uncomparable — not left proven and racy. |
| `D-g1-b` | **`m8`'s A9 asserts a reason string that is absent.** Pre-existing on main (19/2 there, 20/1 here). "There is no stored token to forget." is not rendered, and no token exists at `~/.mcp-router/control.token`, so the token store the app reads is elsewhere. Needs its own measurement. |
| `D-g1-c` | **`m8` fails on any focus change, not on this app taking the screen.** `mac-shell` and `m2` deliberately assert only "MCP Router never came to the front", because the user switching windows must not fail a gate for something it did not do. m8 asserts frontmost-unchanged and so reddens on a macOS `SecurityAgent` dialog. |
| `D-g1-d` | **i2's placeholder claim is asserted, not mutation-proven.** §4: no iOS mutation was run to show the suite reddens if Discover were a placeholder. |
| `D-g1-e` | **8 parity rows have never been shown able to fail.** From the newly-wired `parity-lane-selftest`: `mcp-endpoint`, `mcp-tools-call`, `mcp-health`, `pool-p4`, `div-r2r-d8`, `cli-serve`, `cli-import`, `cli-status` are "recorded proven by a lane whose ability to fail on THAT row is unproven". |
| `D-g1-f` | **The iOS stamp has no consumer.** Written by `make build-ios`, read by nobody, because i2/i3 build their own product. Harmless today; a trap if a future caller assumes it is checked. |
| `D-g1-g` | **Two parity runs on one machine corrupt each other silently.** Every lane binds a fixed port, and the harness says in its own message that it never shares one — but nothing detects that the holder is another copy of the harness. A second run reports the first run's ports as an environment fault and blocks up to 9 extra rows (69 of 83 here, against 78 serial). The block is now honest (§12) and still invisible in the number a reader sees. Wants either a lockfile refusing a concurrent run outright, or per-run ephemeral ports. |
