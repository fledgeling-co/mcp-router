# plan-R4 — Differential parity harness and the held cutover

**Spec:** [`planning/specs/spec-R4.md`](../specs/spec-R4.md) · **Branch:** `ai/r4` · **Worktree:** `.worktrees/R4`
**Tier:** Standard. Six phases; no fan-out. The work is one harness, one manifest and one gate,
and splitting a gate across agents is how a gate ends up with two ideas of what "green" means.

---

## The shape of the work

The spec's finding — there is no Swift daemon — moves the centre of gravity. The valuable
artifact is not the diff, which R3 already built and which passes. It is the **census**: an
enumerated surface with a proven/blocked verdict per row, and a gate that cannot print green
while a row is unproven.

So the build order is manifest first, gate second, lanes third. Writing the lanes first would
produce a harness that reports what it happens to cover, which is the failure mode the item
exists to prevent.

Everything runs inside `.worktrees/R4`. Nothing touches ports 8975/8976, the user's
`MCP_ROUTER_HOME`, or `~/.claude.json`.

---

## P1 · The surface manifest

**Deliver:** `planning/parity/surface.tsv`, and `planning/parity/README.md` explaining what a row means.

TSV rather than JSON so a row is greppable and a diff is readable in a PR. Columns:

```
group   id   subject   verdict   owner   note
```

`verdict` ∈ `proven` | `blocked`. `owner` is the item that would unblock it, or `-` when proven.

Rows are derived, not invented:

| Group | Derived from |
|---|---|
| `control` | the dispatch table in `src/control.ts` — one row per `(path, method)` pair it answers |
| `fixture` | one row per file in `app/Sources/MCPRouterKit/Control/Fixtures/` (**24** — the count of 23 came from F3's WIP commit and misses `servers.json`, which entered through the F3 merge) |
| `divergence` | R1 D1–D5, R2 D6–D7, R3 D1–D5, R5 P7 |
| `mcp` | `/mcp`, `tools/list`, `tools/call`, `/health`, `/status` from `src/router.ts` |
| `cli` | the ten `case` arms in `src/index.ts` |
| `pool` | the spawn/reap decisions in `spec-R2.md` P1–P9 |
| `log` | one row: log bytes over a live run |

**A1 is the load-bearing clause and needs a real guard.** A manifest hand-maintained against
`control.ts` drifts the moment a route is added. `scripts/acceptance/parity-manifest-check.sh`
extracts the route table from `src/control.ts` mechanically and fails when a route has no row,
or a row has no route. That is the red-green test A1 asks for.

---

## P2 · The gate

**Deliver:** `scripts/acceptance/parity-gate.sh` — the single entry point.

Responsibilities, in order:

1. Run `parity-manifest-check.sh`. A manifest that has drifted invalidates every number below it.
2. Run each lane, capturing its per-row results to `$WORK/results.tsv`.
3. Reconcile: every manifest row must have a result. A row with **no** result is `blocked`,
   never absent — that is A7, and it is what stops a lane that failed to start from shrinking
   the denominator.
4. Print the report in the `DESIGN.md` §5 shape from the spec.
5. Exit `0` only when proven == total. Exit `1` on any blocked row or any mismatch. Exit `2` when
   the environment could not run a lane.

**The exit-code discipline is the whole gate.** Three specific traps, each guarded:

- A lane that exits non-zero must not be able to shrink the denominator. Reconciliation is
  against the manifest, never against what the lanes happened to report.
- `set -euo pipefail` with a lane in a pipeline swallows the lane's status. Lanes run
  unpiped, status captured explicitly.
- A `0` from a lane that printed nothing is a lane that did not run. Each lane must emit at
  least one result row or it is recorded as `blocked: produced no results`.

Coverage prints as `N of M`, always, in both the pass and fail paths. The success line may not
print a bare "parity" without the fraction — that sentence is what this item exists to retire.

---

## P3 · Control lane — full route coverage

**Deliver:** `scripts/acceptance/parity-control.sh`, adapted from `control-differential.sh`.

R3's script is good and is EXTENDED rather than rewritten — a second copy of its logic would be a second idea of what "green" means. It is modified in place, which is a cross-item edit and is called out as such in the affected-test sweep. Changes:

- Emit machine-readable rows (`control<TAB>id<TAB>ok|fail<TAB>detail`) alongside the human output,
  so the gate can reconcile.
- Extend from R3's 12 routes to **all 15**, adding `POST /servers/:n/approve`,
  `POST /servers/:n/auth`, `POST /usage/reset`, `GET /usage/stream`, and the `registry/search`
  declared divergence.
- `/usage/stream` is SSE, so bodies cannot be compared. Compare the **framing** — status and
  `content-type` — and record the body as a declared non-comparison, not as a pass.
- `POST /usage/reset` mutates. It runs last in its own scratch home, so it cannot move the
  state the earlier rows were compared against.

The two defects (D-j) are asserted with `diverges()`, R3's both-directions helper: the row passes
only when the reference really answers 409/400 **and** Swift really answers 405. If either side
changes, the row fails as stale. That is A9, and it is why the defects are recorded rather than
fixed here — a fixed defect would silently turn this row green with no one noticing the assertion
was about a bug.

---

## P4 · Fixture lane (D-a) and divergence lane (D-g)

**Deliver:** `scripts/acceptance/parity-fixture.sh`, `scripts/acceptance/parity-divergence.sh`. (Singular. The gate resolves lanes by path, so a lane named in a plan and absent on disk is the cheapest possible route to a shrunken denominator.)

**Fixtures.** Each of the 24 files is a recorded body. The recorded set carries no status — that
is exactly deferred child D-a. The lane replays the request each fixture was captured from against
the live reference and asserts body **and** status. The fixtures are never modified; they are the
wire contract, and a lane that edits its own oracle proves nothing.

A fixture whose originating request cannot be reconstructed from live state — `approve-conflict`,
`reindex-*`, `servers-pending-auth`, anything needing a live pool — is recorded as
`blocked: needs live pool state (R2-R)` rather than skipped. Skipping is what makes a subset look
like a pass.

**Divergences.** D1, D3 and D4 have suite tests but no vector, and `spec-R1.md` line 585 says so
explicitly. The lane asserts each directly: feed D1's trap fixture and require TS-empty +
Swift-error; for D3 write a `servers.json` carrying an unknown top-level key and require the Swift
writer to preserve it and the reference to drop it; D4 is not observable on the wire and is
recorded as `proven-by-suite` with the test named, which is a weaker verdict and is printed as such.

---

## P5 · Pool lane, and the blocked rows

**Deliver:** `scripts/acceptance/parity-pool.sh`.

Spawn/reap is the one behavioural corpus partially reachable without a daemon: `UpstreamPool` is a
library actor and can be driven in-process by a small oracle, the way `ControlDiff` drives the
control handler.

Provable now (4 rows): nothing spawns before the first lease; N concurrent leases spawn one child;
an idle child is reaped after the window; a child that exits is evicted and reopened. Each is
compared against the reference's own behaviour observed through `/status` on a live router.

Blocked (2 rows): reap-under-live-traffic and the call-outstanding guard both need traffic arriving
over an MCP endpoint. Recorded `blocked: R2-R`.

Writing a new oracle executable is justified here and nowhere else in this plan; if the in-process
drive turns out to need more than a thin `main.swift`, the honest move is to record all six rows
as blocked rather than build a second router to test the first.

---

## P6 · Evidence, and the cutover that does not happen

**Deliver:** `planning/evidence/R4-acceptance.md`, the Progress section in `spec-R4.md`, commits.

Evidence carries one row per acceptance clause with its evidence type — measurement, exercised
request, or red-green — per the standing rule. The gate's own output is pasted verbatim, including
its non-zero exit, because A15's evidence *is* the failure.

**The cutover is not performed.** `docs/install.sh` is not edited and `src/*.ts` is not deleted.
The spec's Cutover section specifies the commit for whoever holds the preconditions; this plan
ends with the branch tip being harness work.

The instruction to make the cutover a separate final commit stands and is honoured by there being
no such commit: the orchestrator can merge the harness with no cutover to hold back. Recorded as
deferred child **R4-C** so it is scheduled rather than forgotten.

### Gates

| Gate | Command |
|---|---|
| Swift build + tests | `make test` from `app/` |
| Lint | `make lint` — **assert the file count is non-zero**; `.swiftformat` excludes `.worktrees`, so a clean lint from inside the worktree can mean nothing was examined |
| Parity vectors | `make parity` — floor 358 |
| Shell | `shellcheck` on every new script |
| The gate itself | `scripts/acceptance/parity-gate.sh` — **expected to exit 1**, with **50 of 81** |

### Affected-test sweep

The harness adds scripts and one oracle target; it changes no shipped Swift behaviour. The sweep is
therefore: `make test` unchanged at 456/68, `make parity` unchanged at 358, and the new lanes. If
any existing test moves, something was changed that this item does not own — investigate rather
than re-baseline.

---

## What this plan deliberately does not do

- **Does not fix D-j.** The gate measures it; fixing it inside the same item destroys the measurement.
- **Does not build R2-R.** It is a router, not a harness, and it is several times this item's size.
- **Does not touch `install.sh`, `src/*.ts`, `package.json` or `dist/`.**
- **Does not add a second channel** between the app and the router — the harness talks to the
  reference over the loopback HTTP it already exposes, and to Swift in-process.
- **Does not stop, restart or reconfigure the user's running router.**
