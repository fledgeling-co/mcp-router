# R3 — acceptance evidence

One row per surface, per the fleet rule: **screen · how it was verified · commit SHA · result**.
Append, never rewrite. Read this before testing anything — a row whose files
`git diff <SHA>..HEAD` does not touch **is** the evidence, and the test is skipped rather than
repeated.

## Surfaces

**R3 renders nothing.** It is the control API: no view, no window, no interaction, no overlay.
`planning/specs/spec-R3.md` §"Design representation" states this, and `design/mocks/prototype.html`
carries no surface this item builds. So there is no screen row here, and that is a finding rather
than an omission — a UI row in this file would be fabricated.

What R3 owes instead is the **values** every later surface renders. `DESIGN.md` §5's nine states are
each decided by a value this item emits, and the differential run below exercises the ones that are
observable without a live pool. The surfaces themselves are M3, M5 and M8's, and their evidence
belongs in their own files.

## Evidence rows

Every row is a measurement, an exercised request, or a red-green test. No row is a build gate:
`make build` succeeding is recorded at the bottom as a precondition, not as acceptance.

| # | What was verified | How — the actual command | Commit | Result |
|---|---|---|---|---|
| 1 | The Swift handler answers **what the running TypeScript reference answers**, byte for byte, over a 32-row matrix: the acceptance rows, fault injection, data-shape stress, and the security surface | `bash scripts/acceptance/control-differential.sh` (starts `dist/` on 8973 against a scratch MCPR home, issues each request to both, diffs bytes) | `cfb9ecb` | **32 rows compared, 32 ok, 0 failed** |
| 2 | The parity corpus is **reference-derived, not back-fitted** — regenerating every vector from the built reference reproduces the committed files exactly | `make parity-regen` (runs `scripts/parity/generate-vectors.mjs` against `dist/`, `diff -ru` against the committed corpus) | `cfb9ecb` | `parity-regen: the committed vectors match the reference exactly` |
| 3 | The corpus is **executed**, not merely present — the attestation prints a count and the floor refuses a shrinking corpus | `make parity` | `cfb9ecb` | `parity: 352 vector cases compared (floor 352)` |
| 4 | Every named behaviour is **load-bearing**: break it in the source, the gate must go red, restore | `scripts/parity/mutation-gate.sh` (31 mutations) | `cfb9ecb` | **31/31 red.** 17 caught by the vector corpus (N1–N13, R1, R2, R4, R5), 14 by the suite (D1, D3, D4, R3, R6–R15). Zero decorations, zero misapplied |
| 5 | **B10** — no env or header **value** is reachable through any response the API can emit | the canary sweep inside row 1: a planted env value, scanned for across every compared response body | `cfb9ecb` | `no env value appears in any compared response` |
| 6 | **B40** — a PATCH carrying `command`, `args`, `env` is *ignored, not rejected*: status, response bytes and the config file on disk all equal the same request with those three members deleted | `WireGuaranteeTests.commandLineMembersAreIgnoredNotRejected`, red-green proven by mutation R12 | `cfb9ecb` | red under R12, green restored |
| 7 | **B2 / S3** — an explicit `cwd: null` is emitted as `"cwd":null`; an absent `cwd` emits no key at all; a value emits the value | `WireGuaranteeTests.nullCwdIsEmitted` + `cwdTriState`, red-green proven by mutation R10 | `cfb9ecb` | red under R10, green restored |
| 8 | **B17** — an exact `Bearer ` prefix shadows `x-mcpr-token` even when the bearer is empty or wrong, and `x-mcpr-token` *is* consulted when the prefix is absent | `WireGuaranteeTests.bearerShadows` + `tokenHeaderUsedWithoutPrefix`, red-green proven by mutation R13 | `cfb9ecb` | red under R13, green restored |
| 9 | **B14 / B22** — ownership runs before the token gate, so an unauthenticated `POST /mcp` falls through rather than being answered 401; and `DELETE /servers/ghost` without a token is 401, not 404 | `ControlFixtureTests` ordered-trace tests, red-green proven by mutation R11 | `cfb9ecb` | red under R11, green restored |
| 10 | **B67 / B71** — attribution resolves in-process against a **real loopback connection**, returning the same pid, name and cwd the reference resolves | `AttributionTests.realProbeSeesOwnSocket` / `realProbeHandlesDeadPid` (real sockets and real pids, not doubles) | `cfb9ecb` | pass |
| 11 | **B69 (as amended)** — each of the four peer-identification failure paths yields a wholly empty identity; a resolved pid with an unreadable `cwd` keeps pid and name, matching the reference | `AttributionTests` — one test per path, plus `cwdFailureKeepsIdentity` | `cfb9ecb` | pass |
| 12 | **B70** — the identity cache is pid-keyed, bounded at 512, and cleared **wholesale** on overflow, with the bound checked *after* the insert | `AttributionTests.cacheBoundary`, red-green proven by mutation R14 | `cfb9ecb` | red under R14, green restored |
| 13 | The recorded fixtures are reproduced from **constructed dependencies**, never from a lookup table (S6) | `ControlFixtureTests` — 15 tests over the recorded responses, each building the row from config + manifest + pool + usage doubles | `cfb9ecb` | pass |
| 14 | The **declared divergences** are real and directional: five inputs kill the reference process and this port answers 400 instead | rows in the row-1 matrix, which assert the reference **died** and Swift answered | `cfb9ecb` | `reference DIED (TypeError) · swift 400` ×3, `(URIError) · swift 400` ×2 |
| 15 | **B74** — the TypeScript reference is untouched | `git diff main -- src/ install.sh package.json` | `cfb9ecb` | empty |

## Preconditions, recorded so they are not mistaken for acceptance

| Gate | Command | Result |
|---|---|---|
| Format + lint | `make lint` | `0/127 files require formatting` · `0 violations, 0 serious in 126 files` |
| Build, macOS + iOS | `make build` | pass |
| Unit + parity suite | `make test` | `353 tests in 56 suites passed` |

**On the lint exclusion.** The fleet brief warns that `.swiftformat` excludes `.worktrees`, so
linting from inside a worktree examines nothing and reports clean. **Measured here on 2026-08-14:
that does not hold in this worktree.** `make lint` run from `.worktrees/R3` examined 127 files and
*failed*, on two real wrap violations this branch introduced — which is conclusive, because a linter
that examined nothing cannot report a violation. The reason is that swiftformat resolves
`--exclude .worktrees` relative to the config file it loaded, and the config it loads here is the
worktree's own, under which no path contains `.worktrees`. Recorded because the warning is worth
re-testing per worktree rather than trusted or dismissed.

## What was deliberately not tested, and why

- **No UI, so no screen was driven.** There is nothing to drive. See above.
- **Live-pool-dependent endpoints are excluded from the differential by construction**, not by
  omission: both sides run with an empty pool and the upstreams are never called, so a row whose
  answer depends on a live upstream would be comparing two different worlds rather than two
  implementations. Those clauses are covered by the unit suite against doubles instead.
- **Section G (auth, B60–B66) is not R3's.** It was split out into R5 after the spec was written.
  Its absence here is scope, not a gap.

## Re-verification log

Appended rather than rewritten, per the rule at the top of this file.

| When | What changed since the rows above | What was re-run | Result |
|---|---|---|---|
| `04b978e` | `WireGuaranteeTests.swift` only — a redundant type annotation and one 111-character assertion message, both formatting. No behaviour, no source under `app/Sources/`. | `make all` (lint + build + test + parity) | `0 violations` · `353 tests in 56 suites passed` · `parity: 352 vector cases compared (floor 352)` |

Rows 1–15 were verified at `cfb9ecb` and are **not** re-run here: `git diff cfb9ecb..04b978e`
touches one test file's formatting and nothing else, so the behavioural evidence stands. The
differential (row 1), `parity-regen` (row 2) and the 31-mutation gate (row 4) each cost a full
reference run or a full rebuild per mutation, and repeating them for a whitespace change would be
the exact repetition this file exists to prevent.
