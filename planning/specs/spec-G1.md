# spec-G1 — Stop the acceptance checks blaming the app for being out of date

Status: **Ready for Work** · Item: G1 · Category: harness · Deps: M11 ✓ I3 ✓
Branch: `ai/g1` · Worktree: `.worktrees/G1`

---

## 0 · What was measured, before anything was designed

Every number below was taken on `ai/g1` at `7babd97` (main's head) in a **fresh worktree**,
built once with `make build-mac`. The machine was **not** quiet: the P3 runner was building
throughout and `uptime` read between **16.19 and 76.56** on 16 cores. Load is recorded against
each measurement rather than absorbed, because two of the defects here are races and a race
measured under load is a different measurement.

### 0.1 The five Mac checks are GREEN on a tree whose binary matches its source

| Check | Exit | Result | Load at run |
|---|---|---|---|
| `m2-activity.sh` | **0** | every assertion passed, app never frontmost | 76 → 36 |
| `m5-discover.sh` | **0** | 32 passed, 0 failed | 76 → 36 |
| `m7-evals-cleanup.sh` | **0** | 16 passed, 0 failed | 76 → 36 |
| `m8-settings-menubar.sh` | **0** | 21 passed, 0 failed | 76 → 36 |
| `m6-inbox-pairing.sh` | **0** | 20 passed, 0 failed | 65 |

That is the diagnosis confirmed from the green side: **the redness on a clean main was the
build, not the product.** No source changed between the orchestrator's red runs and these
green ones — only a rebuild.

### 0.2 The orchestrator's mac-shell diagnosis did NOT reproduce, and the measurement wins

The brief predicts `mac-shell.sh` fails at the first check with *"the shell window never
appeared"*. It did not. On this tree it ran the **entire** pass — sidebar, toolbar, all eight
destinations, menus, restoration across a relaunch, the scroll edge, the offline and
unauthorised copy — and then:

```
BLOCKED: no Release build at …/Build/Products/Release/MCPRouter.app — run 'make build-mac-release' first
EXIT=2
```

Two facts follow, and both change the work:

1. **`launch_app` is a real race, not a permanent failure.** It launched here at load 76 and
   failed for the orchestrator at load 18–27. A defect that appears under *less* load is a
   race whose timing is not load-monotone, which is what a fixed `sleep` plus an unchecked
   `open` produces. It cannot be proven by re-running until it fails; it is proven by
   injection (§3.1).
2. **A precondition is checked ~1,200 lines after it is needed.** `REL_APP` is assigned at
   line 32 and first tested at the end of the run. The Release build is needed by one late
   block, so a missing one costs a full four-minute pass before it says so. That is a defect
   of the same family — the harness knew at second one and reported at minute four.

### 0.3 The stale-build class, reproduced deliberately

One real source edit, no rebuild — exactly what a merge or a rebase produces:

```
app/Sources/MCPRouterKit/Control/ControlAPIClient.swift:44
-  case .routerNotRunning: "The router isn't running"
+  case .routerNotRunning: "The router is not currently running"
```

`mac-shell.sh` then:

```
FAIL: the running app in the offline state does not carry ControlAPIError's own words:
      'The router is not currently running'
EXIT=1
```

**Exit 1, and the sentence names the app.** The tree is correct; the binary is four minutes
old. A runner reading that goes and edits code that is already right. This is the whole item
in one line.

M11's freshness check did **not** catch it, and could not have: it compares mtimes of four
named `MENU_SOURCES` against the binary, and `ControlAPIClient.swift` is not one of them.

### 0.4 The other four Mac launchers are worse than mac-shell's, in four copies

`m2`, `m5`, `m6`, `m7` each carry a byte-identical launcher:

```bash
[ -n "$PID" ] && { kill "$PID" 2>/dev/null || true; sleep 1; }
open -g -a "$MAC_APP" --env "MCPROUTER_SCENARIO=$scenario"
sleep 3
PID="$(pgrep -n -f 'MCPRouter.app/Contents/MacOS/MCPRouter' || true)"
[ -n "$PID" ] || blocked "the app did not start under scenario '$scenario'"
```

No poll at all — a flat `sleep 3` — and `open`'s exit status is discarded in all four. They
block rather than fail, which is the honest half; they simply have less time to get lucky in.
Five copies of one launcher is five chances to be wrong about the same fact, which is the
argument `board-registry.sh` already records for the registry reader.

### 0.5 `i2` and `i3` cannot tell a compile error from a failing test

Both run `xcodebuild … test` into one status and branch on it once:

```bash
if [ "$status" -ne 0 ]; then
    fail "the Discover acceptance pass is red (xcodebuild exit $status). Log: …"
```

A build failure and an assertion failure produce the same sentence and the same exit 1, and
the sentence names the surface. These two scripts build the product themselves, so they are
immune to a stale *binary* — and maximally exposed to a broken *build* being reported as a
broken screen.

### 0.6 `D-p4-b` — the register's premise is wrong, measured

`parity-gate.sh` in a fresh unbuilt worktree does **not** fail to run. It exits **2** and every
one of nine lanes prints its own environment message naming `npm run build`. The exit code,
the classification (blocked, not proven) and the remedy are all already correct. What is
actually wrong is that the same fact is printed nine times and only after the whole gate has
walked the manifest. This is an ergonomics defect, not a dishonesty defect, and the spec says
so rather than inventing a fault to justify the row.

### 0.7 `D-p4-e` — one problem counted as up to four

`parity-manifest-check.sh:40` is `note() { printf …; problems=$((problems + 1)); }`, and a
multi-line finding calls it once per line. Measured call sites: lines 102–104 (three calls,
one finding), 238–241 (four, one), 320–322 (three, one), 183–184, 436–437, 468–469 (two
each). The gate whose entire subject is that numbers are not inflated inflates its own.

### 0.8 `D-p1-e` — the mechanism, named

`observe_watch` in `parity-install.sh` is not a fixed-delay lane in the way the register
implies. It already polls observables for two of its four terms. The nondeterminism is
narrower and has two coupled causes, both from **one** missing wait:

- **`oneshot` is sampled once, at the wrong moment.** `[ -z "$(agent_pid "$label")" ] && oneshot=yes`
  runs the instant the state file becomes non-empty. The state file is written *by the running
  process*; the process is still alive when it lands. Whether `agent_pid` still answers is a
  coin toss decided by how fast the binary tears down after its last write — which differs
  between `node` and Swift and moves under load.
- **`reran` is decided by a WatchPaths event that launchd may legitimately drop.** launchd does
  not queue a start for a job that is already running. `stage … two` fires while the first run
  may still be alive, so the event that should cause the re-run can be discarded, and `reran`
  reads `no` for a lane that is behaving correctly.

Both terms therefore go unstable **together**, on **both** binaries, with the losing side
alternating — which is precisely the shape P1 measured over six runs (agreed 1 in 6). One
missing wait explains the whole signature, and that is a testable claim rather than a story.

---

## 1 · The problem, stated once

A gate that reports a stale build as a product defect is worse than no gate: it sends runners
to fix code that is correct. Seven of eight checks were red on a clean main and six went green
on a rebuild with no source change. Every one of those six spent a runner's turn.

The three failures are one failure wearing three costumes:

- the harness cannot establish **that the thing it is testing is the thing in the tree**;
- the harness cannot establish **that it launched at all** before it starts judging;
- the harness cannot **say which of those two it is**, so it says the product is broken.

---

## 2 · What is delivered

### A1 — One reader for "is this build the tree's build"

A new sourced helper, `scripts/acceptance/build-freshness.sh`, decides freshness on **content**,
never on mtime, and is the only place that decides it. A rebase rewrites mtimes and changes no
content, so a rebased tree is fresh and stays fresh — closing `D-m11-a`, whose whole failure was
that `make build-mac` exiting 0 could not clear it.

The recorded side of the comparison is written by the **build**, so the check answers "what was
this product built from" rather than "when was this file touched".

### A2 — Freshness blocks, and says the word

A stale build exits **2** with a message naming staleness and the command that fixes it. It
never exits 1 and it never names a screen, a string or a board.

### A3 — One launcher for the Mac lane

`mac_app_launch` replaces five copies. It waits on observables at every step, checks `open`'s
exit status, and reports a **five-way** outcome rather than the brief's three, because two of
the five are genuinely the product's fault and collapsing them would swap one lie for another:

| Observation | Verdict | Why |
|---|---|---|
| `open` exits non-zero | **BLOCKED 2** | LaunchServices refused. Nothing ran; there is nothing to judge |
| `open` exits 0, no process ever appears | **BLOCKED 2** | Nothing ran |
| a process appeared, then exited with no window | **FAIL 1** | The app started and died. That is the product |
| a process is alive and shows no window | **FAIL 1** | The app is running and not drawing. That is the product |
| a window exists, the AX tree cannot be read | **BLOCKED 2** | Permission or harness |

The brief asked for three; three would report an app that crashes on launch as an environment
problem. This is a **deliberate deviation, flagged**, and the extra two are the ones that keep
the gate able to catch a real launch crash.

### A4 — The previous instance is waited out, not slept over

`pkill` followed by `sleep 1` is replaced by a bounded poll until no matching process remains.
This is the specific mechanism behind the orchestrator's `-600`: LaunchServices refuses a
relaunch while the old instance is still terminating.

### A5 — Preconditions are checked before the work, not after it

`mac-shell.sh` tests for the Release build in its preflight, next to the Debug one.

### A6 — `i2`/`i3` separate the build from the test

`build-for-testing` runs first; a non-zero status there is **BLOCKED 2** naming the build.
`test-without-building` runs second; a non-zero status there is **FAIL 1** naming the surface.

### A7 — `install-launchd-watch` waits on a launchd observable

`observe_watch` waits for the first run's process to be **gone** before judging one-shot and
before staging the second file, so neither term can be decided by a coin toss. The row stays
`proven` only if the lane is then measured stable over consecutive runs; if it is not, the row
is marked `blocked` with the mechanism in its note. **Not calling it flaky either way** — that
label invites re-running until green, which is how `D-p` preserved a real race.

### A8 — `parity-manifest-check.sh` counts findings, not lines

`note` counts and prints; a new `detail` prints only. No finding changes, no threshold moves,
and the reported number equals the number of problems.

### A9 — `parity-gate.sh` says the environment fact once, up front

One notice before the lanes, naming the missing reference and the command. The lanes keep
their own messages and their own blocked classification; nothing about the coverage number
changes.

---

## 3 · How each claim is proven

### 3.1 The launch taxonomy — by injection, since the race cannot be summoned

A race is not proven by re-running until it fires. Each arm is forced:

- **`open` refuses** — a `PATH` shim ahead of `/usr/bin/open` that exits 1. Expect BLOCKED 2,
  message naming LaunchServices, not the window.
- **process appears and dies** — launch a scenario, kill it inside the window-wait. Expect
  FAIL 1 naming the app exiting.
- **the old instance will not die** — a stub process matching the pattern that ignores TERM.
  Expect BLOCKED 2 naming the previous instance, and — critically — **before** any `open`.

The old code's answer to arm 1 is the same sentence as arm 4 (`the shell window never
appeared`, exit 1), which is the defect.

### 3.2 Freshness — red for stale, green for clean, and green across a rebase

Three runs, in order:

1. clean tree, built → the check passes and the pass proceeds (already measured green, §0.1);
2. the §0.3 edit, no rebuild → **BLOCKED 2**, message names staleness (was FAIL 1 naming the app);
3. **`touch` every Swift source** so every mtime is newer than the binary, with no content
   change → the check still passes. This is the rebase, simulated exactly, and it is the run
   M11's mtime check fails and this one must not.

### 3.3 The counter — arithmetic, on a manifest deliberately broken

Introduce one multi-line finding, count the reported number. Expect 1, measure the old code's
answer for the same input, and report both.

### 3.4 The watch lane — repetition, and the honest reading of it

Consecutive runs, before and after, on the same machine with load recorded per run. Agreement
is the measurement; a single green run is not. The before-number is P1's 1-in-6 and is not
re-measured from scratch — re-running a known race to watch it fail is the spend this fleet
already declined once.

---

## 4 · What is explicitly NOT done

- **No lint limit is raised.** If a file crosses 400 lines it is split on a seam.
- **`parity-gate.sh` and `parity-fixture.sh` are not touched in any way that moves the
  coverage number.** A9 adds a notice and nothing else.
- **No UI acceptance pass is run over a placeholder**, and no check is re-run to make it green.
- **`surface.tsv` is edited on the `install-launchd-watch` row only.** The census pin moves only
  if the row *count* changes, and it does not.
- **The `DESIGN.md` 33pt-vs-32pt titlebar note** printed by `mac-shell.sh` is a pre-existing
  shared-surface finding belonging to the design system. It is left alone and named here.

---

## 5 · State matrix — the harness's own states

`DESIGN.md` §5 asks every surface to ship its unhappy paths. A gate's surface is its exit code
and its sentence, and this is that matrix.

| State | Exit | The sentence must name |
|---|---|---|
| Product defect | 1 | the screen, the string, the assertion |
| Build is stale | 2 | staleness, and `make build-mac` |
| Build is absent | 2 | absence, and `make build-mac` |
| Launch refused | 2 | LaunchServices, and that nothing ran |
| App died on launch | 1 | the app exiting — this one *is* the product |
| No AX grant | 2 | the permission and where to grant it |
| No console session | 2 | the session |
| Reference not built | 2 | `npm run build` |
| Lane could not run | 2 | the lane, and that its rows stay blocked |

The single rule underneath: **exit 1 is a claim about the product. Everything the harness
could not establish is exit 2.**

---

# ADDENDUM — corrections to §0, from the re-run's own measurements

- **§0.2's launch diagnosis is confirmed in direction and wrong in mechanism.** Under a `PATH` shim
  making `open` exit 1, the old `mac-shell.sh` exits 1 printing only `kLSServerCommunicationErr
  -600`: `set -e` aborts at `open`, so neither the poll loop nor "the shell window never appeared"
  is ever reached.
- **§0.6 understated `D-p4-b`.** The same environment fact prints **22** times (11 lanes at the
  point of failure, 11 again in the summary), not nine.
- **§0.8's single-cause claim was already withdrawn in the plan and stays withdrawn.** Both
  mechanisms were fixed; the row is still marked `blocked`, because P1's terms vary independently
  and a green streak after a partial fix is not determinism.
- **A9 in `m8` fails on `main` too.** Measured by running main's unmodified m8 against the same
  Debug bundle: 19 passed / 2 failed there against 20 / 1 here. Registered as `D-g1-b`.
- **The launch taxonomy grew a sixth arm the spec did not have.** A bundle that cannot be executed
  is the PRODUCT (exit 1), not LaunchServices refusing (exit 2). The spec's table had both under
  "open exits non-zero".
