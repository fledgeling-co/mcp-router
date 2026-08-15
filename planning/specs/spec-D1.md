# spec-D1 — the router deferred register

**Status:** In Progress · **Lane:** Opus · **Branch:** `ai/d1` · **Base:** `main` @ `600f1f8`

D1 is a **register, not a feature**. Its deliverable is a triage decision on every router-side
deferred child, each backed by a measurement, plus implementation of the subset that earns it.
Doing all of them because they are listed is the failure mode this spec is written against; so is
skipping one silently.

This is a **relaunch**. An earlier D1 attempt died on a 503 leaving zero commits and one artifact:
a draft of this spec. That draft is treated here as a colleague's unreviewed work — every claim in
it was re-measured against the code before being carried forward, and **three of its claims did not
survive**. They are corrected in §2 and §3 rather than quietly dropped.

---

## 1. The measurement this item starts from

`parity-gate.sh`, this worktree, rebased onto `main` @ `600f1f8`, 2026-08-15T15:29:41Z → 15:34:36Z,
1-minute load average 246.82 (another session's Xcode builds):

```
control     15 of 16 proven, 1 blocked      cli       9 of 10 proven, 1 blocked
fixture     23 of 24 proven, 1 blocked      install   3 of  5 proven, 2 blocked
divergence  15 of 15 proven (4 by suite)    state     1 of  1 proven
pool         6 of  6 proven                 log       1 of  1 proven
mcp          5 of  5 proven
parity: 78 of 83 rows proven (4 by suite only), 5 blocked. exit 1, 0 DIVERGED.
```

That reproduces main's recorded 78/83/5/0 exactly, and it did so at load 246 — which is itself
evidence that the router-side lanes are not load-sensitive the way the AX-driven Mac scripts are.
The 5 blocked rows and their owners are `control-auth-post-http` (D-p1-a), `cli-auth` (D-p1-d),
`install-launchd-watch` (G1), `install-rollback` (R4-C), `fixture-registry-search`
(accepted-uncomparable).

`parity-lane-selftest.sh`, same tree, 15:35:56Z → 15:40:54Z: exit 0, every seeded lane went red,
failability roll-up **demonstrated 11 of 19**.

**No other parity run was live for any measurement in this document.** The full 8957–8998 range was
confirmed empty of listeners immediately before the BEFORE gate, and every reproduction below holds
its own port deliberately and releases it.

---

## 2. Triage — every child, with the measurement behind the verdict

| Child | Verdict | Measurement |
|---|---|---|
| **D-g1-g** two parity runs corrupt each other | **DOING — premise true, stated mechanism FALSE** | See §2.1. Reproduced. But the row says runs corrupt each other *silently*, and that is not what happens: **every** collision path measured exits 2 and names the port |
| **D-g1-e** eight rows never shown able to fail | **DOING** | Reproduced exactly: `demonstrated: 11 of 19`, and the eight named are precisely `mcp-endpoint`, `mcp-tools-call`, `mcp-health`, `pool-p4`, `div-r2r-d8`, `cli-serve`, `cli-import`, `cli-status`. All eight are reachable from lanes the selftest already seeds — they were not attempted, not structurally unreachable |
| **D-p1-c** `awaitCompletion` reports a settled flow as absent | **DOING** | Confirmed by reading `AuthFlow.swift:240–249` against the contract at `ControlPorts.swift:141–148`. `settle` resumes the observer then `cleanup` sets `current = nil`; an observer arriving after that hits the `guard` and is told `no authorization is in flight` |
| **D-g** parity vectors for R1 D1/D3/D4 | **CLOSED — not a defect** | All four vectors exist in `planning/parity/surface.tsv` and all four are proven: `div-r1-d1` (81), `div-r1-d3` (83), `div-r1-d3-control` (84), `div-r1-d4` (85, `proven-by-suite`). The work was delivered and the register entry was never retired |
| **D-p4-b** a fresh worktree cannot run the parity gate unbuilt | **CLOSED — premise FALSE** | Measured: `dist/index.js` moved aside, gate run. It **did** run — walked the whole manifest, classified every affected row blocked (`control 0 of 16 proven, 16 blocked`), exited 2 and named the remedy. The repetition half was already discharged by G1: 5 mentions across a 2-lane run, against the 22 the row was written about |
| **D-p4-c** derive the install rows from source | **CLOSED — premise superseded** | The hole it names (deleting a hand-maintained row raises coverage) is already shut by a better instrument: `surface.tsv` carries `# rows: 83` and `parity-manifest-check.sh` fails when the census size moves, which catches *any* row leaving whether derivable or not. `docs/install.sh` additionally states its five steps in a prose header, not in an extractable table like `control.ts`'s routes |
| **D-r2r-b** the control API has never been compared over a socket | **CONFIRMED, PROMOTED — not done here** | Real, and worse than recorded. All 16 `control` rows compare curl against the reference using `ControlDiff`, an in-process oracle, on the Swift side. `parity-gate.sh:280` prints *"control compares both routers on the wire"*, which is false for the Swift half. Rebuilding a 16-row differential onto a socket is R2-R-sized; half-doing it inside a register is how a real gap gets marked closed |
| **D-p1-a** OAuth client behind `AuthTransport` | **NOT DOING** | P1's own note requires a new item. It is a whole OAuth 2.1 client and cannot be parity-proven without an OAuth server fixture |
| **D-p1-d** `cli-auth` needs a serve-backed row | **NOT DOING** | Its manifest note ends *"the non-stdio path additionally needs D-p1-a"*. The reachable half would prove a stdio server needs no auth, which is not the row's claim — buying a green row for a weaker claim is the substitution the gate exists to refuse |
| **D-p2-a** neither Swift writer locks `~/.claude.json` | **NOT DOING** | P2's reasoning holds on re-reading: the lock would exclude nothing (Claude Code will never take it, the watcher's rewrite is unlocked by `D-v1f`, nothing in the app writes the file) while leaving a permanent lockfile in the user's home |
| **D-p2-c / D-p2-d / D-p4-a / D-p1-f / D-p1-g / D-v1b–e / D-w3 / D-d / D-g1-a** | **NOT DOING — stay registered** | Each is a genuine residue with a recorded mechanism, none blocks a parity row, and none is in the two classes this item exists to close (harness integrity; a defect laid in a future item's path). `D-p1-f` is explicitly the owner's call, not a runner's |

### 2.1 D-g1-g, measured rather than assumed

The row's premise is **true**: 13 scripts bind fixed 89xx ports, and two of those port sets overlap
between entry points (`parity-lane-selftest.sh` passes `MCP_HUB_PORT=8996`/`8997`, which are
`parity-state.sh`'s and `parity-install.sh`'s defaults; it passes `MCP_SWIFT_PORT=8983`, which is
`p1-auth-routes.sh`'s default).

The row's stated **mechanism is false**. Three reproductions, all with the port held deliberately:

1. **Guarded lanes** (10 of 13 scripts carry an `lsof -nP -iTCP` pre-guard). Holding `:8995` and
   `:8996` and running the gate over `state log`: both lanes exit 2, their rows are recorded
   **blocked**, and the gate prints `state — environment: something is already listening on :8996`
   and exits 2. Loud, and the port is named.
2. **Unguarded scripts.** `p1-auth-routes.sh` and `control-client.sh` have **no** pre-guard at all.
   Holding `:8983` and running `p1-auth-routes.sh`: it exits **2** with
   `environment: the Swift daemon never answered /health on :8983` and the daemon's own
   `listen EADDRINUSE: address already in use 127.0.0.1:8983`. Also loud — the post-bind health
   check catches what the missing pre-guard did not.
3. No path was found on which a collision produces a wrong *comparison* rather than a refusal.

So the real defect is not silent corruption. It is that **a run which could not measure the surface
still prints a coverage fraction** — `parity: 69 of 83`, `77 of 83` — and a fraction is the thing
that gets copied into a ledger while the tail that explains it gets skimmed. The honest behaviour
when another run holds the harness is to **refuse to start**, not to start and under-report.

That reframing changes the fix's acceptance criterion: it is not "make concurrent runs safe", it is
"make a second run impossible to mistake for a low score".

**Lock, not ephemeral ports.** Ephemeral ports would let two runs proceed, which is not a state
anyone wants on this machine: they would contend for CPU on a host already at load 100+, and they
would have to allocate from a range that must never include `8975`/`8976` (the user's live router)
— a constraint every current script states explicitly and a random allocator cannot honour without
a retry loop that reintroduces the same race. A lock also makes the fleet's "one parity runner"
rule mechanical instead of a sentence in a runner's brief, which is the form it has already been
lost in.

---

## 3. What is built

### A — `D-g1-g`: one lock over the fixed-port harness

`scripts/acceptance/parity-lock.sh`, a sourced helper built on **`mkdir` plus a pidfile**, not on
`/usr/bin/shlock`. `shlock` is present on this machine and would work, but it is BSD-only, and a
gate whose entire purpose is that numbers are not quietly wrong should not depend on a binary whose
absence would have to be turned into a loud failure anyway. `mkdir` is atomic on every POSIX
filesystem, has no dependency, and makes the staleness rule explicit and testable rather than
opaque.

- **A1** Every entry point that binds a fixed 89xx port takes the lock before binding:
  `parity-gate.sh`, `parity-lane-selftest.sh`, `p1-auth-routes.sh`, `control-differential.sh`,
  `control-client.sh`.
- **A2** The lock is **re-entrant within one process tree**. The gate exports a token; a lane it
  dispatches sees the token and proceeds. Without this the gate deadlocks against its own lanes.
- **A3** A run that cannot take the lock **exits 2 naming the holding pid and its command line**,
  and binds nothing. 2 is already this gate's "the environment could not run a lane" code, and a run
  that refused to start is much closer to that than to a failure of the product. Critically it
  prints **no coverage fraction**, which is the whole point.
- **A4** The lock is released on every exit path, including `INT`/`TERM`/`HUP`.
- **A5** A lock whose recorded pid is **dead** is stale, and is cleared with a printed notice. This
  fleet has already had two runners killed mid-run by 503s; a lock that outlived them would be worse
  than the defect.
- **A6** `PARITY_NO_LOCK=1` disables it for a deliberate operator override. Absent by default.

### B — `D-g1-e`: seeded defects for the eight undemonstrated rows

Each of the eight gets a defect its own oracle must notice, injected through the existing
`$SWIFT_BIN` shim so **no test-only branch enters the product**. A row that cannot be reddened after
a genuine attempt is **reported as still undemonstrated**, not re-aimed at something easier and
counted — the re-aiming failure is the one G1 recorded.

**Result: the roll-up moved from 11 of 19 to 16 of 19.** Five of the six new seeds hit the row they
were written for (`mcp-health`, `mcp-tools-call`, `cli-status`, `cli-import`, `cli-serve`), and each
`check` now names its target row and FAILS if that row does not go red — so a seed can no longer be
counted for reddening the lane through some other row.

**Three rows remain undemonstrated, all three attempted:**

| Row | What was tried | Why it did not move |
|---|---|---|
| `pool/pool-p4` | `--idle-ms 50`, the mirror of the existing 999999 seed | The router withholds reaping on a call being OUTSTANDING, not on the timer, so no idle window can break it. The seed is kept because it reddens `pool-reap-traffic` from the opposite direction, and it is declared against that row rather than the one it was aimed at |
| `mcp/mcp-endpoint` | — | The four framing refusals and the 404 are decided entirely inside the HTTP layer |
| `divergence/div-r2r-d8` | — | It asserts the two parser texts DIFFER, so reddening it means making them agree |

All three need a fault injected into a response the router has already composed. Every seed here
works through the shim — arguments, `$MCP_ROUTER_HOME` files, or refusing to start — and none of
those reaches a composed response. Closing them needs a mangling proxy in front of the Swift router
or a fault-injection hook in the product, and a hook in the product is what this harness has refused
to add throughout. Registered rather than half-done, and the script prints all of this itself so the
next runner does not repeat the attempt blind.

### C — `D-p1-c`: a settled flow is reported as authorized

`AuthFlowCoordinator` records the outcome of a flow that settles, so `awaitCompletion` returns for a
success that landed before the observer arrived, per the contract at `ControlPorts.swift:141–148`.
Today it throws `no authorization is in flight`, which the route turns into an `onIncomplete` warn
with no `clearPending` and no re-index: the tokens land on disk and the tools never appear.

**Reachability, stated rather than implied:** the HTTP arm is unreachable today because nothing
conforms to `AuthTransport` (`D-p1-a`, and why `control-auth-post-http` is blocked). This is proven
at the **unit boundary and not at the wire**, and this spec says so rather than claiming a wire
proof it cannot take.

---

## 4. The out-of-family review, and what it changed

Two grok passes ran: one on the plan before implementation, one as a completeness critic on the
finished diff. Both are recorded here including where they were **wrong**, because a review whose
misses go unrecorded reads as a rubber stamp.

**Taken, and each one changed the code:**

| Finding | What it was | What changed |
|---|---|---|
| The reclaim race | Two waiters could both `rm -rf` a stale lock and both `mkdir` it | Reclaim is by `mv` to a one-shot aside name, so exactly one reclaimer wins |
| `kill -0` is not liveness | It fails with EPERM for a live process owned by another uid, and the shell cannot tell that from ESRCH — so a live holder's lock would be stolen | Liveness is asked of `ps -p`; only absence from `ps` reads as death |
| PID reuse | At load 100+ a recycled pid makes a dead lock look live forever, and the lock becomes a worse outage than the contention | The owner's start time is recorded and compared; a pid whose start time disagrees is stale (`L7`) |
| The subshell release | `x="$(...)"` forks a subshell that inherits the variables AND the EXIT trap, so the first command substitution would have released the lock mid-run — `control-differential.sh` has already paid for exactly this once | Release is guarded on `BASHPID`, and proven by `L3` |
| The `mkdir`→pid window | A winner descheduled between `mkdir` and its pid write could have its directory `mv`d away, and its later write would land in the NEW holder's directory — two holders, both binding | A pidless lock is only reclaimable once it is `PARITY_LOCK_ORPHAN_SECONDS` old, and a claimer verifies the directory inode and pid after writing, refusing if displaced (`L8`, `L10`) |
| **A seed can hit the wrong row** | A seed aimed at `mcp-health` that trips `mcp-status` reddens the lane, passes every check, and is still counted — the item's own miscount, one level down | `check` now takes the row it is aimed at and FAILS if that row does not go red |
| **`D-p1-c` was not closed for the real caller** | The first fix cleared the recorded outcome on every `begin`. `AuthRoutes.authStart` runs `awaitCompletion` in a detached `Task`, so a second server's authorization can begin — and settle — before the first server's observer is scheduled, erasing it and reinstating the defect | Outcomes are keyed **per server** and consumed on read. The critic's exact scenario is now a test, and it reddens against the old behaviour |
| Stale `11 of 19` in the Makefile | A comment describing the number this item moved | Updated to 16 of 19 with the reason |

**Not taken, with the measurement:**

- *"`control-differential.sh` takes a global lock but does not share the gate's ports, so it blocks
  runs needlessly."* **False.** `parity-control.sh:19` dispatches `control-differential.sh`, so
  :8973 is inside a gate run's own port set. The lock is correctly scoped and re-entrancy covers the
  dispatch.
- *"Spec A1 is not done — the ten lane scripts still bind without the lock."* A1 names five entry
  points and covers all five. The ten lanes are dispatched by the gate, which holds the lock, and
  each carries its own `lsof` pre-guard that exits 2 loudly when run standalone. Registered below
  rather than done, because widening the lock to ten more scripts at the end of an item is how a
  green gate gets destabilised.
- *"`src/control.ts:399`, `AuthRoutes.swift:53`, `D1-deferred-router.md:38`."* Two of those three
  paths do not exist in this repo. The underlying mechanism was real and was fixed; the citations
  were not checked before being quoted, which is the standing reason this fleet verifies a review's
  claims rather than applying them.

**Recorded, not fixed:**

- The fraction is now withheld whenever a lane exits 2 — including when a lane exits 2 for a
  **product** failure it classifies as environmental (`parity-mcp.sh:223` treats a Swift `/health`
  with no body that way). The run still exits 2 and still prints the failing lane, so nothing is
  hidden except a number that was never a measurement. The real defect there is the
  misclassification, and it belongs to whoever owns that lane.
- `D-g1-g-b`: the ten dispatched lane scripts take no lock of their own.

---

## 5. The AFTER measurement, including the run that went red

`parity-gate.sh` on the final tree, 2026-08-15T17:08:59Z → 17:12:59Z, load average **545**:

```
parity: 78 of 83 rows proven (4 by suite only), 5 blocked. exit 1, 0 DIVERGED.
```

Identical to the BEFORE run in §1 — same numerator, same denominator, same five blocked rows, same
owners. The lock was released cleanly and the harness left nothing behind.

**The run before it did not read that, and pretending otherwise would be the exact dishonesty this
item is about.** At 17:03:40Z, load **612**, the same tree reported:

```
parity: 1 of 83 rows DIVERGED from the reference.
  divergence  R2 D6 callsServed counts acquisitions   callsServed=3 — neither the declared 1 nor a call count of 5
parity: 77 of 83 rows proven, 5 blocked.
```

What was done about it, rather than re-running until it went green:

1. The divergence lane was run **three times in isolation** on that same tree, with every change of
   this item in place: `4 as declared, 0 stale`, exit 0, three times out of three.
2. The full gate was then re-run once and read 78/83/0.

So the observation is contention, not a regression, and the fixture change made in this item is not
implicated — the three isolated runs carried it. **This upgrades `D-p4-a`**, which records pool D6
contention with "8/8 isolated reads correct; **not** filed as flaky". It has now been seen to move a
FULL GATE run to `1 DIVERGED` on a machine under load 612, which is a stronger claim than the row
currently carries, and the cutover's 83/83 target cannot be read as stable while it stands.

`make parity-selftest` on the final tree: exit 0 — manifest selftest green, **lock selftest 12 held
0 did not**, normalise selftest 14 behaved 0 did not, every seeded lane went red, and the failability
roll-up reads **16 of 19** with each seed confirmed against the row it was aimed at.

---

## 6. What this item must not do

- Not mark any row proven that this lane cannot measure deterministically. `install-launchd-watch`
  stays blocked; an accepted-as-uncomparable row is a legitimate outcome. Main's `0 DIVERGED` was
  bought by that honesty and must survive this item.
- Not move the denominator. `# rows: 83` is unchanged; the cutover target stays 83.
- Not edit `parity-gate.sh`'s coverage arithmetic or the manifest to move the number.
- Not touch any Mac surface. D2 is concurrent and owns those.
- Not run the AX-driven Mac acceptance scripts: this machine is at load 100+ from another session,
  and above ~42 they manufacture false reds.
