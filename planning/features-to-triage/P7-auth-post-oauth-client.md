# P7 — `control-auth-post-http` needs a real OAuth client

**Category:** router · parity **Parent:** D-p1-a (triage verified by P5, not inherited)
**Blocks:** R4-C, which needs 82 of 83 and currently has 80.

One of two rows standing between the parity gate and the cutover target. It is not a harness
change, which is what the first triage assumed and what P5 disproved by looking.

## What is actually wrong

Two independent facts, either of which alone blocks the row:

- **The only conformer to `AuthTransport` anywhere is `FakeAuthTransport`, and it lives in the
  test target.** So a POST against the auth route answers 405 in any configuration a lane can
  build. The 405 is real rather than a harness artefact.
- **The vendored swift-sdk cannot produce the reference's byte string, and cannot work without
  it.** It emits `state` unconditionally, while `extractCode(from:expectedRedirectURI:expectedState:)`
  hard-guards on `state`. Those two together mean no configuration of the SDK reaches agreement
  with the TypeScript reference.

## What closing it costs

A hand-written OAuth client: discovery, dynamic client registration, PKCE, and a callback
listener on `:8880`. That is router work rather than lane work, and it is why this is its own
item rather than a fix inside `parity-gate.sh`.

## Acceptance

- A production conformer to `AuthTransport` exists outside the test target, and the auth route
  answers a POST rather than 405.
- The parity lane for `control-auth-post-http` runs against the running Swift router and the
  running TypeScript reference, and both answer identically on the normalised body, the status
  and the redirect.
- The row moves `blocked → proven` in `planning/parity/surface.tsv` with its evidence, and the
  gate's own count moves with it.
- **The lane is mutation-proven before the row is promoted.** Break the client — drop PKCE,
  change the `state` handling, point the callback at a dead port — and the lane must go red on
  every trial, not most of them. D-p1-e is the standing example of a term that agreed for
  sixteen observations and still measured the wrong thing; a series bounds the agreement rate
  and never finds that.
