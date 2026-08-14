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

- **Attribution's partial-identity path contradicts B69 — and it is a SPEC defect, not a code
  one.** B69 says every failure yields an empty identity, "never a partial one". The reference
  emits `{ pid, client, cwd: cwd || undefined }`, so a partial identity is the reference's own
  behaviour, and B71 requires equality with the reference; the two cannot both hold. Scope B69
  to its four enumerated peer-identification paths and name the cwd case as an explicit
  exception, in the same shape as B12's carve-out for its two 422 bodies. `spec-R3.md` was
  never amended, so you are the first to write this down. The half that genuinely was a code
  defect is already fixed on `ai/r3`: a pid whose `proc_name` fails used to escape as a bare
  `{pid}`, a state the reference cannot produce (it reads pid and command from one
  `lsof -Fpc` record); it is now `.unknown`.
- `isLive`/`clearPending` take Swift `String`, so canonical equivalence applies where the
  reference uses code units (S5/B24). Auth handles user-supplied names, so this is yours to
  close — but note the correction: it is **latent, not live**. `ServerParser` refuses any name
  outside `[A-Za-z0-9_-]+`, so two spellings of one name cannot both reach a port. Keep the
  `JSString` typing (that gate keeps names usable as tool namespaces; it is not a
  comparison-safety measure) and do not report a live bug fixed there.

## Constraints inherited from the router items

- The reference is `src/*.ts`. Where behaviour is not obvious, read the TypeScript rather than
  inferring it — R3 found five live defects that way, and rejected three review findings that
  would have edited correct code into a divergence.
- F3's 23 recorded fixtures are the wire contract R4 diffs against. Consume them; never alter them.
- **B76 is already met — do not plan work to satisfy it.** This brief originally said the
  corpus sat at exactly 224 and that auth was where it would clear R1's floor. It isn't:
  R3's later commits took `ai/r3` to **352 executed cases across 48 suites**, and
  `make parity-regen` against the reference `dist/` passes, so they are reference-derived
  rather than back-fitted. Add auth vectors because auth needs vectors; treat 352 as the
  floor to beat, not 224.
- The MCP SDK is pinned exact at `0.12.1` and lives only in `RouterCore`, which neither app links.
  Do not add a second dependency or widen the pin.

## Out of scope

- Anything outside auth and the two routes. R3's own close-out (P6 vectors, P7's
  `no-wire-codable.sh`, Phase 6 acceptance) stays with R3.
- The Mac and iPhone auth *surfaces*. M8 and I1 own those; this is the router half.

## Acceptance

Both routes answer with the reference's byte shape, every termination path is exercised by a test
rather than described, and the parity vector count clears 224 with auth vectors included.
