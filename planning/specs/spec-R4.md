# R4: Differential parity harness and the installer cutover

**Status:** Ready for Work
**Depends on:** R2 ✓, R3 ✓, R5 ✓ (all merged)
**Plan:** [`planning/plans/plan-R4.md`](../plans/plan-R4.md)

---

## Feature description — as briefed

> The gate that decides whether Swift replaces TypeScript.
>
> Build a harness that runs both routers against the same recorded MCP traffic and diffs:
> every tool-list response, every call result, every control-API response, spawn and reap
> timing, and the log. Parity means byte-identical control responses and behaviourally
> identical spawn/reap decisions over the full corpus.
>
> Only once green: one commit flips `install.sh` to the Swift binary, deletes `src/*.ts`
> and its Node dependency, and updates the README and the marketing site's install copy.
> Until then both ship and TypeScript is the default.
>
> **This item may not be marked done on a partial pass.** A parity gate that reports green
> on a subset is the exact failure this harness exists to prevent.

---

## What this item is really for

Every other check in this repo compares the Swift port against *something we wrote*. The 23
recorded fixtures are bytes captured once; the 358-case vector corpus is generated from the
reference but consumed by assertions we authored; the 456-test suite is our belief about the
contract. All three agree with the model by construction, which is exactly the property that
makes them unable to notice a route nobody thought to check.

R4 exists to replace belief with measurement, and — more importantly — **to make the size of
what has not been measured impossible to overlook**. The brief's last paragraph is the real
requirement. A harness that diffs thirty rows and prints "parity" is worse than no harness,
because it converts an unknown into a false certainty that a cutover is then justified by.

So the central deliverable is not the diff. It is the **surface manifest**: an enumerated,
machine-checked census of everything the cutover requires to be equivalent, each row carrying
`proven` or `blocked` with a reason and an owner. The gate reads the manifest and refuses to
print green while a single row is unproven. Coverage is reported as a fraction, always, so
"32 rows passed" can never again be read as "the routers are equivalent".

---

## The finding that determines this item's shape

**There is no Swift router process.** `RouterCore` is a library. It is complete and good — config,
manifest, discovery, the lazy pool, the control *handler*, usage, registry, OAuth — but nothing
wraps it in a daemon.

Established by direct measurement, not inference:

| Probe | Result |
|---|---|
| `grep -rn "NWListener\|import Network" app/Sources/RouterCore` | one hit: `Auth/CallbackListener.swift`, R5's single-shot OAuth callback |
| executables in `app/.build/debug` | `ControlDiff`, `ControlProbe` — both one-shot oracles, neither a daemon |
| `find app/Sources/RouterCore -iname "*relay*" -o -iname "*http*" -o -iname "*server*"` | no relay, no HTTP client, no listener |
| `planning/specs/spec-R2.md` §Progress | *"The relay, the HTTP listener, HTTP upstream clients and the composition root remain with child spec **R2-R**; the config watcher remains with **R2-W**."* |
| `spec-R2.md` clause table | `T1–T4, R-1…R-10, H1–H8, C1–C2` → **not delivered**; `W1–W10` → **not delivered**; `S2` → **not delivered** |

The fleet brief handed to this runner states the Swift router "carries … relay, passthrough".
It does not. R2 delivered Phases 0–2 of its plan — the frozen seams and the lazy pool — and
deferred the rest. That is recorded honestly inside `spec-R2.md`; it simply did not travel.

**`R2-R` is registered nowhere.** `spec-R2.md`'s deferred-children table registers `R2-W`, `D-h`
and `D-i`, but not `R2-R` — the single largest missing piece of the Swift router is named only
in prose, has no id in `ORCHESTRATOR.md` or `LEDGER.md`, and is owned by no one. Reporting that
is part of this item's job.

### What follows

1. **The cutover is not risky; it is impossible.** `docs/install.sh` writes launchd agents that
   run `node dist/index.js serve` and `… watch`, calls `node dist/index.js import` and `… index`,
   and verifies over `/health` and `/status`. Replacing that requires a Swift binary answering
   ten CLI verbs and three HTTP surfaces. None exists. There is nothing to point the installer at.
2. **The parity gate cannot pass in full**, and this item may not be marked done on a partial
   pass. Two of the brief's five corpora — tool-list responses and call results — travel over an
   MCP endpoint that exists on one side only. Spawn/reap timing is partially drivable in-process.
3. Therefore R4 delivers **the harness, the manifest and the census**, and **does not perform the
   cutover**. The gate's own output is the evidence for that refusal, rather than this prose.

This is the outcome the item was written to produce. A cutover recommended on a subset is the one
failure it exists to prevent, and the subset here is far smaller than it appeared.

---

## Scope

### Delivered

| # | Deliverable |
|---|---|
| 1 | `planning/parity/surface.tsv` — the enumerated cutover surface, one row per capability, machine-readable |
| 2 | `scripts/acceptance/parity-gate.sh` — the single entry point; runs every lane, reconciles against the manifest, refuses green on any unproven row |
| 3 | Extended control differential — **every** control route, up from R3's 32 rows |
| 4 | Fixture status + body differential over all 23 recorded fixtures (deferred child **D-a**) |
| 5 | Divergence assertions for **D1 / D3 / D4** so their absence is not read as agreement (deferred child **D-g**) |
| 6 | Pool spawn/reap differential, to the depth the absent daemon allows, with the rest declared blocked |

### Not delivered, deliberately

| # | Not delivered | Why |
|---|---|---|
| 7 | The installer flip and `src/*.ts` deletion | The gate does not pass. There is also no Swift binary to flip to. See **Cutover**, below |
| 8 | `tools/list` and `tools/call` differential | Requires the MCP endpoint. Blocked on `R2-R` |
| 9 | Log-byte differential over a live run | Requires a Swift daemon that emits a log. Blocked on `R2-R` |

R4 does **not** fix the parity defects it finds. A gate that repairs what it measures cannot be
trusted to have measured honestly, and the two defects found (below) are `R3`-owned wiring, not
harness work. They are reported as deferred children with their evidence.

---

## Parity defects found while specifying

Both are wire-visible, both were invisible to R3's 32-row differential, and both are recorded
here so the harness can assert them rather than rediscover them.

| Route | TypeScript reference | Swift | Verdict |
|---|---|---|---|
| `POST /servers/:name/approve` | `409 {"error":"no pending change for \"s1\""}` | `405 {"error":"POST not allowed on /servers/s1/approve"}` | **defect** |
| `POST /servers/:name/auth` | `400 {"error":"stdio servers do not authorize; their credentials are env vars"}` | `405 {"error":"POST not allowed on /servers/s1/auth"}` | **defect** |

`AuthRoutes.approve` and `AuthRoutes.authStart` are implemented in `RouterCore/Auth/AuthRoutes.swift`
and are **never wired into `ControlHandler`'s dispatch**, which carries only `("/auth", "DELETE")`.
The functions exist, are tested in isolation, and are unreachable over the wire. That is the exact
shape of defect a fixture suite and a unit suite both pass while the port is broken — and the
reason this item's central deliverable is a census rather than a diff.

Reported as deferred child **D-j**. Not fixed here.

---

## Acceptance criteria

| # | Criterion | Evidence type |
|---|---|---|
| **A1** | The manifest enumerates every control route the TypeScript reference dispatches, derived from `src/control.ts`, with no row absent | red-green: a test that fails when a route in `control.ts` has no manifest row |
| **A2** | The manifest enumerates the MCP surface (`tools/list`, `tools/call`, `/mcp`, `/health`, `/status`), the ten CLI verbs, spawn/reap, and the log | inspection against `src/index.ts` and `src/router.ts` |
| **A3** | Every manifest row carries exactly one of `proven` / `blocked`, and every `blocked` row names a reason and an owning item | red-green: malformed row fails the gate |
| **A4** | `parity-gate.sh` exits **non-zero** while any row is `blocked`, and says so in words | exercised: run it now; it must fail |
| **A5** | The gate prints coverage as a fraction of the enumerated surface, never as a bare pass count | exercised request |
| **A6** | The gate exits **2**, distinctly, when the environment cannot run a lane, so a skipped lane is never a pass | exercised: run with `dist/` absent |
| **A7** | A lane that fails to run is recorded as `blocked`, never silently dropped | red-green |
| **A8** | Every control route reachable on the reference is compared byte-for-byte with the Swift handler, status included | exercised request per route |
| **A9** | The two defects above are asserted as **known divergences with an owner**, and the assertion fails if either side changes — so the record cannot outlive its reason | red-green, both directions |
| **A10** | All 23 recorded fixtures are replayed against the live reference; body **and** HTTP status must match | exercised request (**D-a**) |
| **A11** | D1, D3 and D4 each carry an explicit assertion; the corpus may not treat their absence as agreement | red-green (**D-g**) |
| **A12** | Declared divergences D6, D7, R5-P7 and R1 D1–D5 are asserted as *expected*, and a row goes red if a divergence becomes stale | red-green, both directions |
| **A13** | The gate never contacts the network, and never touches the user's real `MCP_ROUTER_HOME`, `~/.claude.json` or ports 8975/8976 | measurement: scratch home guard + port refusal |
| **A14** | The harness does not stop, restart or mutate any router it did not start | inspection + the existing port-occupied refusal |
| **A15** | The cutover is **not** performed, and the gate's own output is the stated reason | the gate's exit code |

---

## The parity surface — what the cutover actually requires

The manifest ships as `planning/parity/surface.tsv`. This is its census, and the number that
matters is the last row.

| Group | Rows | Proven by R4 | Blocked |
|---|---|---|---|
| Control API routes | 15 | 13 | 2 — `approve`, `auth` POST (**D-j**); `registry/search` proven only as a declared divergence |
| Recorded fixtures (D-a) | 23 | 23 | 0 |
| Declared divergences | 11 | 11 | 0 |
| MCP endpoint — `tools/list`, `tools/call`, `/mcp`, `/health`, `/status` | 5 | 0 | 5 — **R2-R** |
| CLI verbs — `serve watch import index refresh status tools auth usage help` | 10 | 0 | 10 — **R2-R**, **R2-W** |
| Pool spawn/reap decisions | 6 | 4 | 2 — reap-under-live-traffic needs a daemon (**R2-R**) |
| Log bytes over a live run | 1 | 0 | 1 — **R2-R** |
| **Total** | **71** | **51** | **20** |

The gate reports this fraction on every run. It is why "the differential passed" is not a
sentence this repo can print any more.

---

## Design representation — 2026-08-14

R4 ships no GUI. Its user-facing surface is the gate's terminal report, and that report is a
data surface, so `DESIGN.md` §5 applies to it: nine states, real copy for the unhappy paths. A
gate whose failure output is worse than its success output is a gate people learn to skim.

`DESIGN.md` §6 governs the words — sentence case, non-blaming errors that say what happened and
how to fix it, and **no number the harness does not observe**. The coverage fraction is counted
from the manifest, never estimated.

| §5 state | In the gate | Real copy |
|---|---|---|
| Default | every row proven | `parity: 71 of 71 rows proven. The Swift router answers what the reference answers.` |
| Empty | manifest present, no lane has run | `parity: no lane has reported. Run scripts/acceptance/parity-gate.sh — an unrun gate is not a passing one.` |
| Loading | a lane is mid-run | `running control-differential (3 of 6 lanes)` — named lanes, never a bare spinner |
| **Partial** | the live state, and the one that matters | `parity: 51 of 71 rows proven, 20 blocked. This is NOT a pass.` then the blocked rows grouped by owning item |
| Error | a lane failed to run | `control-differential could not run: no built reference at dist/index.js. Run npm run build. A skipped lane is recorded as blocked, not as a pass.` |
| Success | a previously blocked row goes green | the fraction moves; no celebration line, and the total never disappears |
| Offline | the reference is not running | `the reference is not answering on :8961 — this harness starts its own and never uses the one on 8975/8976.` |
| Disabled | a lane blocked by a missing prerequisite | `mcp-differential — blocked on R2-R (no Swift MCP endpoint exists). Not run.` — dimmed in place, reason adjacent |
| Overflow | a route name longer than the column | truncates in the row, printed in full in the failure detail below it; rows never change height |

The single copy decision worth recording: the partial state says **"This is NOT a pass"** in
words rather than relying on the exit code. Exit codes are read by CI; the sentence is for the
person who ran it in a terminal and would otherwise see 51 green rows and stop reading.

---

## Declared divergences carried in — not rediscovered as bugs

The harness asserts each of these as *expected*, in both directions, so a divergence that is
fixed upstream fails the gate as stale rather than passing quietly.

| # | Origin | Divergence |
|---|---|---|
| D1 | R1 | Unrecognisable `mcpServers` is an error in Swift; the reference loads zero servers silently |
| D2 | R1 | `loadManifest` reports that it degraded and why; the reference returns an ordinary empty manifest |
| D3 | R1 | The `servers.json` writer is atomic and preserves unknown top-level keys |
| D4 | R1 | A directory-creation or stderr failure in logging is contained rather than propagated |
| D5 | R1 | The log API takes a structured event; no call accepts a whole config or env dictionary |
| D6 | R2 | `callsServed` counts acquisitions, not served calls — reproduced **exactly**, because this gate diffs it |
| D7 | R2 | The reference loses a router restart when `~/.claude.json` becomes unparseable mid-watch |
| R3 D1–D5 | R3 | Five inputs that terminate the reference process; Swift answers 400 |
| R5 P7 | R5 | The callback response sends `content-length` + `connection: close`; Node sends chunked keep-alive |

---

## Cutover — specified, and deliberately not performed

The cutover remains a **single commit at the tip of the branch**, so it can be held while the
harness merges. Its content, when a Swift daemon exists:

1. `docs/install.sh` — replace the `npm install && npm run build` step with a `swift build -c release`,
   point both launchd `ProgramArguments` at the built binary, drop the Node 20 prerequisite check,
   and keep the `/health` + `/status` verification exactly as it is.
2. Delete `src/*.ts`, `tsconfig.json`, `package.json`, `package-lock.json`, `dist/`.
3. `README.md` and `docs/` install copy.

**Preconditions, none of which hold today:**

- `R2-R` delivered — the relay, the HTTP listener, HTTP upstream clients, the composition root.
- `R2-W` delivered — the config watcher, for the `watch` launchd agent.
- The ten CLI verbs implemented in Swift.
- **`parity-gate.sh` exits 0** — 71 of 71.

Step 2 deletes the router the user's own live Claude Code sessions depend on. Performing it
while step 1 has nothing to point at would leave the machine with no router at all.

---

## Triage — 2026-08-14

### Out-of-family spec review

`codex: usage limit -> claude (downgrade)`. Every `codex exec` call, down to a one-word probe,
returns `You've hit your usage limit … try again at Aug 20th, 2026 1:29 PM` — account-level, past
this fleet's horizon, verified by the orchestrator. `codex exec` **exits 0** on a usage limit, so
an exit-code-keyed gate records a pass for a review that never ran; the honest tells are the ERROR
line and an empty `-o` file.

The three gates ran in-family instead: a fresh `claude -p` opus-5 reviewer per gate, briefed
adversarially — told to refute, and that finding nothing counts as a failed review. Verdicts and
tallies are recorded in the Progress section. The weakness travels with the evidence: every
reviewer in this pipeline is now Claude auditing Claude.

### Assumptions carried forward

| # | Assumption | If wrong |
|---|---|---|
| 1 | The absence of a Swift daemon is a genuine gap, not a file this runner failed to find | Four independent probes agree, and `spec-R2.md` states it in its own words. If a daemon exists elsewhere, the manifest's blocked rows become provable and the fraction moves — the gate does not need rewriting |
| 2 | `registry/search` has no stable oracle, so byte-diffing it is not meaningful | R3 established this; the reference calls live registries and two runs a second apart differ. Recorded as a declared divergence rather than as proven |
| 3 | The two `405` defects are R3-owned wiring, not harness scope | Fixing them inside the gate that measures them would compromise the measurement |
| 4 | Port 8961/8962 are free and the user's 8975/8976 are untouched | The harness refuses a busy port rather than sharing one |

### Deferred children discovered

Reported to the orchestrator, not registered here.

| Suggested id | Title | Deps | Why |
|---|---|---|---|
| **R2-R** | Swift router: the relay, the HTTP listener, HTTP upstream clients and the composition root | R2 | Named in `spec-R2.md`'s prose as owning the deferred half of R2, but **registered in no ledger**. It is the single largest missing piece of the Swift router and the hard blocker on 20 of the 71 manifest rows |
| **R4-C** | The installer cutover | R2-R, R2-W, R4 | The commit is specified above; it needs a binary to point at and a green gate |
| **D-j** | Wire `AuthRoutes.approve` and `AuthRoutes.authStart` into `ControlHandler`'s dispatch | R3 | Both implemented, both unreachable over the wire, both answering 405 where the reference answers 409/400 |
| **D-k** | Swift implementations of the ten CLI verbs | R2-R | `serve watch import index refresh status tools auth usage help` — the installer calls four of them directly |
