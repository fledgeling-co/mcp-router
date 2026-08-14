# R2-R — Swift router: the process that actually serves

**Category:** router · **Depends on:** R2 (merged), R3 (merged), R5 (merged) · **Blocks:** R4's cutover

Registered by the orchestrator on 2026-08-14, after R4's parity gate refused the cutover and named
the reason. **This item existed as a deferral inside R2's plan and was in no ledger and owned by
nobody.** It is now the critical path: until it lands, the cutover is not risky, it is impossible.

## The finding, verified rather than reported

R4's gate exits 1 at **50 of 81 rows**, and the blocked lanes are not a matter of effort:

| Lane | Proven | Why the rest are blocked |
|---|---|---|
| `mcp` | 0/5 | `tools/list` and `tools/call` travel over an endpoint that exists on one side only |
| `cli` | 0/10 | there is no Swift binary to invoke |
| `install` | 0/5 | `docs/install.sh` writes launchd agents running `node dist/index.js serve` |
| `state`, `log` | 0/1 each | no long-lived process to hold state or write a log |

Independently confirmed against `main`: `grep -rl 'NWListener\|listen('` over `RouterCore` returns
**`Auth/CallbackListener.swift` alone** — R5's single-shot OAuth callback, not a router. Package.swift
declares three libraries and two one-shot oracles. There is no daemon.

R2 delivered Phases 0–2 — the pool, the process supervision, the passthrough value layer — and
deferred the rest to a name that never became an item.

## Scope

Build the thing that runs.

- **The composition root.** An `executableTarget` that assembles config, manifest, pool, control
  handler, usage store, registry and auth into one process.
- **The HTTP listener** the router serves on, with the same port and path surface the TypeScript
  reference uses. R5's `LoopbackCallbackListener` is a working, tested `NWListener` on loopback —
  read it before writing a second one, and reuse what generalises.
- **The relay and the MCP endpoint** — `tools/list` and `tools/call` over the SDK transport. These
  are the two corpora R4 cannot compare at all today.
- **The HTTP clients** R2 deferred.
- **Lifecycle**: start, graceful stop, and whatever `docs/install.sh` needs in order to point a
  launchd agent at a Swift binary instead of `node dist/index.js serve`.

## Acceptance

**R4's `scripts/acceptance/parity-gate.sh` is the acceptance test.** It is already built, already
merged, and already adversarially reviewed three times. You are done when it moves materially off
50 of 81 — and the honest target is that the five structurally-blocked lanes (`mcp`, `cli`,
`install`, `state`, `log`) become measurable rather than blocked.

Do not edit the gate to make it pass. Three independent reviews took the coverage number apart
once already — it had been overstated five ways, including a lane recording `blocked` being read
as proven — and the current number is the one that survived that. Moving the number by changing
the gate rather than the product is the single failure this item must not produce.

## Constraints

- The reference is `src/*.ts`. Where behaviour is not obvious, read the TypeScript rather than
  inferring it; R3 found eight live defects that way.
- F3's 23 recorded fixtures are the wire contract. Consume them, never alter them.
- **Do not stop or restart the user's running router.** Ports 8975 and 8976 are live and in use by
  their real Claude Code sessions. Bring your own instance up on a distinct port.
- The MCP SDK is pinned exact at `0.12.1` and lives only in `RouterCore`. Do not widen the pin or
  add a second dependency.
- Declared divergences that are deliberate and must not be "fixed": R5's callback framing sends
  `content-length` + `connection: close` where Node sends chunked keep-alive (plan-R5 P7), and
  R3's D1–D5, where Swift errors and the reference loads nothing.

## Out of scope

The cutover itself. Flipping the installer and deleting `src/*.ts` stays with R4, behind its gate,
and behind a decision the user takes — it changes the router their own live sessions depend on.
