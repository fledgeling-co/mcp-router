# R4-C1 — the installer points at Swift, and the TypeScript tree stays

**Status:** done (ai/r4c). The second half, `R4-C2`, is deliberately not scheduled.

## What changed

`docs/install.sh` builds both routers and points both launchd agents — `serve` and `watch` — at
the Swift binary by default. `MCPR_ROUTER=node` reinstalls onto the TypeScript router, which is
still built and still on disk. `MCPR_ROUTER_BINARY` still overrides which Swift binary is used,
which is what the install parity lanes drive.

Nothing was deleted.

## Why this is half of R4-C

`spec-R4.md` §Cutover specifies one commit that does two things: point the agents at Swift, and
delete `src/*.ts`, `tsconfig.json`, `package.json`, `package-lock.json` and `dist/`. The owner took
the first and held the second on 20 Aug 2026.

The reason is not caution in general, it is one specific instrument. The differential parity
harness runs the TypeScript router as its reference — `node dist/index.js`, driven on the wire
beside the Swift router and byte-compared across 83 rows. Step 2 deletes `package.json` and
`dist/`, so performing it ends the harness. That would retire the only thing that can answer "has
the Swift router changed behaviour" at the moment the Swift router starts serving the owner's live
sessions, which is when the question starts mattering.

`DEF-033` sharpened it. On the same day parity reached the target, one whole-gate run reported
`control-auth-post-http` DIVERGED — the reference completed an OAuth authorization and the Swift
router did not — and it has not reproduced in eight standalone runs of that lane or in a second
whole gate. The failing invocation's output had been discarded, so the cause is unrecoverable.

The out-of-family review (grok-4.6, xhigh) put it in one line, and it is the line this item is
named after: *"you may serve Swift; you do not destroy the instrument that would tell you if it
happens again."*

## What R4-C2 waits on

Not a green streak. This repository has already paid once for reading agreement as evidence —
`install-launchd-watch`, whose term agreed 1 in 6 with the losing side alternating, which is why
G1 says to name a fix per term and fix a bound **in advance**. So the deletion waits on one of:

- a captured reproduction of DEF-033, at which point it is a bug to fix rather than an unknown; or
- a bound somebody states before the runs happen — a number of consecutive whole gates including
  the cold port-reuse path — and then meets.

Both are decisions, and both are the owner's.

## Also corrected here

`spec-R4.md`'s stated precondition is "`parity-gate.sh` exits 0 — 81 of 81". That is unmeetable
by construction and has been since `fixture-registry-search` became a standing exclusion: the gate
exits 1 while any row is blocked, and that row is permanently blocked. The owner's 82-of-83
decision superseded the number on 2026-08-16 and nobody rewrote the precondition. It now reads as
the owner set it.

## The assertion

`scripts/acceptance/install-router-default.sh`, wired into `make all` as `install-default`. Six
checks: the default is the Swift binary; `MCPR_ROUTER=node` writes `node dist/index.js`;
`MCPR_ROUTER=node` names no Swift binary anywhere, so the fallback cannot be half-applied; an
unrecognised `MCPR_ROUTER` is refused; `MCPR_ROUTER_BINARY` overrides the built path; and a
non-executable one is refused.

It **extracts** the selector, the binary choice and `program_args` out of `install.sh` and drives
them. It never runs the installer, for the reason `parity-install.sh` already gives in its own
header: that would rewrite the caller's `~/.claude.json` and bootstrap agents into their session.

Two things about the lane are worth knowing because both were found by arming it:

- **A stale anchor exits 2, not 0.** An extraction that finds nothing would otherwise leave every
  assertion running against a function that does not exist, and the lane would report a clean
  sweep of nothing.
- **That bound is checked in the parent shell.** The first version checked it inside the command
  substitution that captured the block, so its `exit 2` ended the subshell and the refusal text was
  captured into the variable it was refusing to fill. The script carried on and the arms failed
  with bash syntax errors — a red for the wrong reason, hiding a gate that could not stop itself.

Armed 20 Aug 2026, four ways, each red for its own stated reason: inverting the seam's condition so
the selected binary never wins (3 failures); making the choice ignore `MCPR_ROUTER` so `node` still
runs Swift (2 failures); accepting an unrecognised value (1 failure); and moving the `program_args`
anchor by one space (exit 2, locator failure).
