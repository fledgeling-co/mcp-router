---
status: to-triage
found-by: deploying R29 and measuring which router answers, 2026-08-28
---

# R33 — Four merged features shipped into the router that does not run

- origin: measured while deploying R29, 2026-08-28
- audience: whoever believes the 2026-08-28 goal is delivered
- platforms: n/a
- proposed-by-ai: true

## What and why

The goal set on 2026-08-28 — the router as the sole home for marketplaces, skills, plugins and
MCPs — was built. Most of it does not run.

Measured on this machine, 2026-08-28, after deploying R29:

- **The router that serves is TypeScript.** Both launchd agents run
  `node ~/.local/share/mcp-router/dist/index.js`. `lsof` confirms that process owns `:8879`.
- **R28** (the extension store), **R30** (ingest), **R31** (cache invalidation) and **R32**
  (Desktop entry) are **Swift only** — 17, 6 and 4 files under `app/Sources/RouterCore/` plus a
  CLI verb, with no TypeScript counterpart.
- The consequence is directly observable: `GET /caches` answers **404** on the running router
  while `GET /sessions` answers **200**, because R29 is the one item of the five built in
  TypeScript.

So four of the five items delivered for this goal are unreachable in production, and the fifth
is the only reason any part of the goal is live.

**This is not a defect in those items.** Each was built where its subject lives, and the parity
harness exists precisely because the two implementations are meant to converge. It is a gap
between "merged" and "running" that no gate in this repo currently measures, which is why it took
a deployment to find.

## What it waits on, stated rather than guessed

`REQ-020` is class `deferred`: *"install.sh flips to the Swift binary and retires src/*.ts once
parity is 82 of 83 and the owner decides."* `R4-C2` records the hold as **owner: not on a green
streak** — the TypeScript reference stays until several consecutive whole-gate passes including a
cold port-reuse path.

Both halves of that are measurable and neither is measured today. The cutover target of 82 of 83
was decided 2026-08-16; `fixture-registry-search` is a standing exclusion, and the denominator
stays 83 deliberately, because deleting the row would shrink the denominator while leaving the
numerator alone.

## Acceptance sketch

- The current parity figure is reported against the 82-of-83 target, derived rather than quoted.
- The green-streak condition is given a definition somebody can check — how many consecutive
  whole-gate passes, over which gates, including the cold port-reuse path R4-C2 names.
- A reader can see, per merged item, which router carries it and whether it is reachable in
  production.
- Something fails when a feature is merged into one implementation and not the other without that
  being recorded — the gap that made this invisible until a deploy.
- No cutover is performed. This item measures readiness and reports it; flipping the installer is
  the owner's decision under REQ-020 and stays theirs.

## Assumptions made writing this

- Assuming the answer is to measure and report rather than to port the four items, because porting
  four features to a reference implementation that REQ-020 plans to retire is work with a stated
  expiry date.
- Assuming the divergence gate belongs beside the parity harness rather than inside it, since the
  harness compares behaviour of rows that exist on both sides and this is about a row existing on
  only one.
