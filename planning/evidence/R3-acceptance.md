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
| 4 | Every named behaviour is **load-bearing**: break it in the source, the gate must go red, restore | `scripts/parity/mutation-gate.sh` — 31 mutations at `cfb9ecb`, 34 at `1c96484`, 35 at `0ef3cf2` | `cfb9ecb` → `0ef3cf2` | **35/35 red.** 17 caught by the vector corpus (N1–N13, R1, R2, R4, R5), 18 by the suite (D1, D3, D4, R3, R6–R19). Zero decorations, zero misapplied |
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
| 16 | **B51 / N5** — a non-ASCII log is cut where the *reference* cuts it: the byte-derived offset applied to a UTF-16 string, overshooting the end and keeping nothing, where a byte-correct implementation would keep half the log | `UsageLogTests.byteOffsetIsAppliedToUTF16` (+ a paired ASCII case so it cannot be passed by returning nothing for any large log), red-green proven by mutation R16 | `1c96484` | red under R16, green restored |
| 17 | **B50** — the log rotates at *exactly* 8 MiB: asserted at the boundary, one byte below and one above, which is the only trio separating `>=` from `>` | `UsageLogTests.rotatesAtTheBoundary`, red-green proven by mutation R17 | `1c96484` | red under R17, green restored |
| 18 | **B50** — the ring warms from the **last** 500 records of a longer log, in order, and a torn final line is skipped rather than losing the read | `UsageLogTests.ringKeepsTheLastFiveHundred` + `tornFinalLineIsSkipped`, red-green proven by mutation R18 | `1c96484` | red under R18, green restored |
| 19 | **S7 on the log write** — a *refused* rotation skips the append, matching the reference's single `try`, so the record is not written into a log that should have been rotated away | `UsageLogTests.failedRotationSkipsTheAppend` (injects a refused `moveItem`, asserts the file is byte-identical afterwards), red-green proven by mutation R19 | `0ef3cf2` | red under R19, green restored |

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

| `1c96484` | `UsageLogTests.swift` added; three mutations added to the gate. No change under `app/Sources/`. | `make test`, then `scripts/parity/mutation-gate.sh R16 R17 R18` | `358 tests in 57 suites passed` · all three red under mutation, green restored |

### How rows 16–18 were found

Not by the critic and not by the fixtures — by sweeping the clause table for **evidence** rather
than for mentions. `for n in $(seq 1 76); do grep -rqE "B$n\b" app/Tests app/Sources/RouterCore; done`
listed twenty clauses named nowhere in the tree. Most turned out to be covered by tests that simply
did not cite the clause number, which is why a missing mention is a signal and not a finding. Three
did not: B50's ring and rotation boundary and B51's byte-offset cut had no test of any kind, and
`maxLogBytes` carried a doc comment asserting it was "tested at the boundary" — a claim about
evidence that did not exist. That comment is the reason this was worth sweeping for: it is the kind
of statement that stops the next reader checking.

| `0ef3cf2` | `UsageStore.record` / `rotateIfBig` — a **source** change: a failed rotation now skips the append. | `make all`, `scripts/acceptance/control-differential.sh`, `mutation-gate.sh R16 R17 R18 R19` | `0 violations` · `359 tests in 57 suites passed` · `parity: 352` · **differential re-run: 32 rows, 32 ok, 0 failed** · R16–R19 all red under mutation |

The differential (row 1) **was** re-run here, unlike at `04b978e`, because this commit changes
`app/Sources/` and the `/usage` endpoints are in the compared matrix. That is the rule working in
both directions: a doc or formatting change reuses the evidence, a behaviour change re-earns it.

## Phase D — the completeness critic, and what actually reviewed this item

This is recorded in full because the gate **degraded twice**, and a degraded gate that is not
written down reads afterwards as a gate that passed.

### Lane 1 — codex `gpt-5.6-sol`, the out-of-family reviewer: UNAVAILABLE

The pipeline's three out-of-family gates exist because every other reviewer here is Claude auditing
Claude. This one could not run: the account is at its usage limit until 20 Aug 2026, verified by the
orchestrator, and the limit is account-level rather than per-session, so no retry inside this fleet's
horizon would clear it.

Recorded exactly as the fleet requires: **`codex: usage limit -> claude (downgrade)`**.

The trap worth carrying forward: `codex exec` **exits 0 on a usage limit**. A gate keyed on `$?`
records a pass for a review that never ran. The only honest tells are the ERROR line in the log and
a missing or empty `-o` file.

### Lane 2 — an in-family `claude -p` opus-5 critic, briefed to refute: STARVED

Two were launched against this branch — one over the whole clause table and tree, one narrowed to
S1–S8 and B1–B44 with four named files — both told that finding nothing counts as a **failed
review** rather than a pass.

Neither returned. Measured rather than assumed: after 23 minutes the first had consumed **22 seconds
of CPU** and written no output, and 96 `claude` processes were resident on this machine — the rest of
the fleet. They were blocked on API contention, not thinking. Left running; if either lands, its
findings belong in a follow-up rather than being back-dated into this file.

### What reviewed this item instead, and what it found

A systematic pass by the runner. This is **weaker** than an independent reviewer and is labelled as
such: it is the author checking the author, which is the exact weakness the out-of-family gate
exists to remove. It is not offered as equivalent. What it did:

**1 — every clause swept for evidence rather than for mentions.**
`for n in $(seq 1 76); do grep -rqE "B$n\b" app/Tests app/Sources/RouterCore; done` returned twenty
clauses named nowhere. Most were covered by tests that simply did not cite the number. Three were
not covered at all: **B50 and B51** — the ring, the rotation boundary, the byte-offset cut — closed
by rows 17, 18 and 16.

**2 — the mutation table extended, which is the one instrument that finds this class.**
Six mutations added for behaviours the plan named; **three stayed green**, meaning the behaviour was
unguarded despite a passing fixture: **B2**'s null `cwd`, **B17**'s `Bearer` shadowing, and
**B40**'s command-line guarantee. Closed by rows 7, 8 and 6.

**3 — the Swift read against `src/*.ts` line by line, for divergences the register does not list.**
Checked directly: B6 (`!isStdio && oauth !== false`, and the stdio branch's `authorized: true`),
B9 (`stat ?? {calls:0,errors:0,projects:{}}` passed through unchanged), B14/B22 (`isControlPath`
before the token gate, token before the route lookup — statement for statement against
`control.ts:228-243`), B21 (`startsWith`, so `application/jsonp` is accepted), B29
(`{added, tools, error, needsAuth}` with `error` omitted when undefined), B33 (`error ? 422 : 200`
as ToBoolean, so `error: ""` is 200 *carrying* `"error":""`), B45 (`if (opts.server)` is ToBoolean,
so `?server=` skips the filter rather than matching nothing), B50 (`size < MAX` → return, so `>=`
rotates). **All eight matched.**

One did not, and it is row 19: `UsageStore.record` swallowed a failed rotation and appended anyway,
where the reference's single `try` skips the append. An unlisted divergence, therefore a regression
by this spec's own rule. Found by reading the reference to check that a *new test* asserted parity
rather than merely this port's behaviour — which is the habit worth keeping, not the finding.

**Net: six coverage gaps closed, one live divergence fixed, zero findings outstanding.** Every one
is red-green proven by a mutation. That is a real result, and it is still not a substitute for a
reviewer who did not write the code.
