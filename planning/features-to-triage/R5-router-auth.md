# R5 — Swift router: OAuth and the authorization routes

**Category:** router · **Depends on:** R3 (merged) · **Blocks:** R4

Split out of R3 by the orchestrator. R3 asked the question directly — take R3 as-is and finish
P4+P6+P7, or let auth become its own item — and the evidence says split: R3 had already blocked
twice, once on an interrupt and once on scope, and its remaining work was P4/auth plus three
smaller closes. A slice that large is what made the turn unfinishable.

## Scope — R3's plan phase P4, verbatim in intent

- **B60–B66**, none of which are delivered: no `Auth/` sources exist in `RouterCore`.
- `POST /servers/:name/auth` and `/approve`, both still missing from the control surface.
- The SDK OAuth stack, the fixed-port callback listener, the two rendered pages, and all five
  termination paths.

## What R3 already established that you inherit

`ai/r3` at merge carries the control API's value layer, the registry port, the byte contract, and
273 passing tests. Read `planning/specs/spec-R3.md` and `planning/plans/plan-R3.md` before
starting — P4 is specified there and the spec has already been through an out-of-family review
that produced 86 findings, 82 accepted.

Also inherit two open items R3 named against auth specifically:

- **Attribution's partial-identity path contradicts B69.** Resolve it rather than working around
  it; R3 flagged it as open, not decided.
- `isLive`/`clearPending` take Swift `String`, so canonical equivalence applies where the
  reference uses code units (S5/B24). Auth handles user-supplied names, so this is yours to close.

## Constraints inherited from the router items

- The reference is `src/*.ts`. Where behaviour is not obvious, read the TypeScript rather than
  inferring it — R3 found five live defects that way, and rejected three review findings that
  would have edited correct code into a divergence.
- F3's 23 recorded fixtures are the wire contract R4 diffs against. Consume them; never alter them.
- **B76: parity vectors must exceed R1's 224.** R3 left this unmet at exactly 224. Every auth
  route you add is a vector, so this item is where it gets met.
- The MCP SDK is pinned exact at `0.12.1` and lives only in `RouterCore`, which neither app links.
  Do not add a second dependency or widen the pin.

## Out of scope

- Anything outside auth and the two routes. R3's own close-out (P6 vectors, P7's
  `no-wire-codable.sh`, Phase 6 acceptance) stays with R3.
- The Mac and iPhone auth *surfaces*. M8 and I1 own those; this is the router half.

## Acceptance

Both routes answer with the reference's byte shape, every termination path is exercised by a test
rather than described, and the parity vector count clears 224 with auth vectors included.
