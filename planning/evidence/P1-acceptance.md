# P1 — acceptance evidence

**Item:** make the two auth routes reachable (`D-j`), and retire the stale defect assertions
(`D-r2r-c`) in the same change.
**Branch** `ai/p1` · **worktree** `.worktrees/P1` · **HEAD** `e154db9`, rebased onto `main`
`3ee40f3`, **0 commits behind** · tree clean.

Append, never rewrite. A row whose SHA-to-HEAD diff does not touch the files behind that surface
**is** the evidence, and re-running it is the waste the owner has asked runners to stop.

---

## 1. The review lanes

The owner's standing instruction of 2026-08-15 overrides the pipeline's default: **`codex` is
account-limited until 2026-08-20 and was not probed.** All three out-of-family gates ran on
**`grok --model grok-4.6 -p`**, exit 0 with non-empty output each time (the `-o`-file check that
catches codex's silent usage-limit pass does not apply, but output size was asserted: 11.4KB,
1.0KB, 8.4KB).

| Gate | Verdict | Findings | Disposition |
|---|---|---|---|
| Spec review | **AMEND** | 11 | 10 accepted, 1 (the 502 proposal) accepted *against* my draft. **Two were verified against the tree before acceptance rather than taken on the reviewer's word, and both held** |
| Plan review | **AMEND** | 14 | 5 had already been hit and fixed during implementation; 4 changed the delivered work; 5 were prose corrections or confirmations |
| Phase D completeness critic | **AMEND** | 13 | 6 fixed in this change, 6 registered as children, 1 rejected with a reason |

**No downgrade to log** — the grok lane worked on all three.

### What the reviews actually changed

| Finding | Effect on the delivered work |
|---|---|
| Spec #1: every acceptance criterion could be satisfied by a hardcoded 409/400 stub, because they were already green in `AuthRoutesTests` against functions the handler never calls | **The whole test design.** All 17 tests now run through `ControlHandler.handle` or the daemon socket. A test that calls `AuthRoutes` directly cannot fail when the dispatch arm is deleted — which is exactly why the existing suite stayed green for the entire life of `D-j` |
| Spec #2: the proposed 502 for non-stdio is worse than the 405 it replaces | 502 dropped. §4 below |
| Spec #3: "the router has no HTTP transport at all" is false — `HTTPUpstreamTransport` exists | **Verified against the tree; the reviewer was right and my measurement was wrong.** The scope argument was rebuilt on the real gap (the OAuth *client*), not on a transport that exists |
| Spec #4 / #6: `awaitCompletion` throws for an already-settled flow; `parity-cli.sh` seeds a **stdio** `probe` | **Both verified against the tree.** Became `D-p1-c` and `D-p1-d` |
| Plan #1: the two new arms take `dispatchServer` to cyclomatic complexity 12 against a cap of 10 | Hit exactly as predicted. Fixed by moving the **whole auth family** into `ControlAuthDispatch.swift`. **No limit raised** |
| Plan #4: a descriptive subject on the new manifest row fails `parity-manifest-check.sh`, which makes `parity-gate.sh` exit **before computing coverage at all** | **Reproduced it** (manifest-check exit 1), then fixed by reusing the exact route subject — the two rows genuinely are one route, and the check does `sort -u` |
| Plan #6: the daemon never passes `log:`, so B94 is unemittable in the only process that ships | **Real gap in the delivered code.** `RouterServiceDispatch` now passes it, `p1-auth-routes.sh` asserts the line, and mutation **M9** proves that assertion can fail |
| Critic #3: the HTTP half was unmeasured on every shipping process | An http upstream was added to `p1-auth-routes.sh`; the 405 is now asserted **on the daemon**, not only in a unit test that injects `starter: nil` into its own `ControlDeps` |
| Critic #5: `p1-auth-routes.sh` was not in any standing gate | Wired into `make acceptance`. A check nobody runs is not a gate |
| Critic #9/#10: three defect ids existed only as comments; `MCPRouterCLI.swift` and `parity-control.sh` still described `D-j` as open | Six children written into `planning/features-to-triage/D1-deferred-router.md`; both stale comments corrected — the same class as `D-r2r-c` |

**Rejected, with the reason:** critic #7's claim that `spec-P1.md` does not exist. It exists at
`planning/specs/spec-P1.md` in the **main working tree**, which is where the pipeline puts docs
(`ship-feature`: docs stay in the main tree, code rides the branch). The reviewer was reading the
worktree and could not see it.

---

## 2. Gates, on the final rebased tree

Every exit code captured directly (`cmd > /tmp/f 2>&1; echo $?`), never through a pipeline — a pipe
reports the last command's status, and a log in this repo has read `lint exit: 0` while every target
failed.

| Gate | Exit | Result |
|---|---|---|
| `swift build --package-path app` | **0** | no Swift-6 concurrency warnings |
| `make lint` | **0** | **0 violations / 438 files.** `swiftformat --lint` runs first and short-circuits, so the exit code is the only honest read |
| `make test` | **0** | **1379 tests / 169 suites** (main after V1: 1362; this item adds 17) |
| `scripts/acceptance/control-differential.sh` | **0** | **53 of 53 rows ok**, against the *running* TypeScript reference. Was 49 ok + 2 known-defect failures |
| `scripts/acceptance/parity-manifest-check.sh` | **0** | 83 rows, consistent with `control.ts` and the fixture directory |
| `scripts/acceptance/p1-auth-routes.sh` | **0** | **13 assertions** over the real daemon's socket |
| `scripts/acceptance/parity-gate.sh` | **1** | by design — it exits 0 only at 100%, which the cutover needs and this item does not deliver |

**Not run, deliberately:** `make build-mac`, `make test-ios`, and every Mac and phone acceptance
script. This item's diff touches `RouterCore/Control`, `RouterCore/Service`, `MCPRouterCLI` doc
comments, `scripts/acceptance/` and `planning/` — **no UI surface of any kind**. Re-testing screens
this item did not change is the specific waste the owner has called out.

---

## 3. Parity, before and after, from the same directory

Both readings taken from `.worktrees/P1`. `D-o` makes the absolute figure depend on the directory
name — its normaliser's character class omits `-`, so `P1` normalises and `mcp-router` does not —
so the repo-root figure differs by one and only the **delta** is comparable across directories.

| | proven | blocked | diverged | exit |
|---|---|---|---|---|
| **Before** (pre-change) | **72 of 82** | 10 | 0 | 1 |
| **After** (final, rebased) | **73 of 83** | 9 | **1** | 1 |

### The attribution, row by row

| Row | Before | After | By |
|---|---|---|---|
| `control-approve-post` | blocked `D-j` | **proven** | P1 |
| `control-auth-post` | blocked `D-j` | **proven** (stdio refusal — the half the row always described) | P1 |
| `control-auth-post-http` | *did not exist* | **blocked `D-p1-a`** (new row; denominator 82 → 83) | P1 |
| `cli-auth` | blocked `R2-R`, note naming `D-j` | blocked **`D-p1-d`**, note corrected | P1 |
| `install-launchd-watch` | proven | **DIVERGED** | **not P1 — see below** |

**P1's own contribution is +2 proven, +1 denominator, −1 blocked.** On a run where the install row
behaves as it did in the baseline, the figure is **74 of 83**.

### The one diverged row is not this item's, and it is not a flake to shrug at

`install / the watch launchd agent`. Proven at file level to be outside this diff: the change
touches no `src/`, no `docs/install.sh`, no `RouterCore/Watch/`, no `MCPRouterCLI/` source, and no
`parity-install.sh`.

Measured over **six consecutive runs** on this machine:

| run | reference | swift | verdict |
|---|---|---|---|
| baseline (in gate) | `yes,yes,yes` | `yes,yes,yes` | ok |
| after #1 (in gate) | `yes,no,no` | `yes,yes,yes` | DIVERGED |
| isolated #2 | `yes,yes,yes` | `yes,no,yes` | FAIL |
| isolated #3 | `yes,yes,no` | — | FAIL |
| isolated #4 | `yes,no,yes` | — | FAIL |
| isolated #5 | `yes,yes,no` | — | FAIL |
| rebased (in gate) | `yes,yes,yes` | `yes,no,yes` | DIVERGED |

The **"reran"** and **"one-shot"** terms are both unstable, on **both** binaries, and **which side
loses the term alternates** — that is launchd `WatchPaths` timing, not a defect in either router.
**1 of 6 runs agreed.** Four full gate runs on this branch gave 73 / 73 / 72 / 73 proven, and the
control lane was **53 of 53 in every one**; all the variance is this row.

Registered as **`D-p1-e`** with the recommendation to mark it `blocked` until the lane waits on a
launchd observable rather than a fixed delay. **P1 measured it and did not flip it** — that is
another lane's verdict, and changing a `proven` row's status changes what R4-C's cutover gate means.
Calling it "flaky" and moving on would be the `D-p` mistake again: flaky invites re-running until
green, which is how a real problem survives.

---

## 4. The design decision worth re-reading before `D-p1-a`

A **non-stdio** `POST /servers/:name/auth` answers **405**, because nothing conforms to
`AuthTransport` and there is no flow to begin.

- **Not 502.** The reference's 502 means `beginAuth` *ran and threw* — a bind failure, or the
  20-second URL race. Reusing it for "no starter was ever constructed" makes two different failures
  indistinguishable, and 502 is the retryable class, so `LiveControlAPIClient.beginAuthorization`
  and `mcp-router auth` would invite a user to retry what can never succeed.
- **405 is what the route already answered**, so this change introduces **no new divergence** on any
  http or oauth upstream. That property is what makes it safe to land into a parity effort mid-count.
- **The counter-argument is recorded rather than dismissed.** The completeness critic pointed out
  that POST *is* allowed on that path (stdio answers 400, unknown answers 404), so 405 is
  semantically false and is the one status that makes `D-j` and `D-p1-a` indistinguishable to a
  client; `501` carrying `ControlAuthSink.noStarter` would be more truthful. It was not taken
  because 501 is a **new** wire value the reference never sends there, needing a declared parity
  vector and a differential divergence row — P4/R4 work. **Two reviews disagreed on this**, so it is
  registered as **`D-p1-f`** for the owner rather than silently settled.

---

## 5. Mutations — 9, each proven red then reverted

Applied, the named check run and confirmed **red**, then reverted by **re-applying the original
file** — never `git checkout --`, which destroyed a fix earlier in this fleet.

| # | Mutation | Reddened |
|---|---|---|
| M1 | delete the `("/approve","POST")` arm | `approveWithNoPendingIs409` (+3 more) |
| M2 | delete the `("/auth","POST")` arm | `stdioAuthIs400AndStartsNothing` (+5 more) |
| M3 | swap `clearPending`/`index` order in the sink | `successClearsPendingThenReindexes` |
| M4 | run the success body on `onIncomplete` too | `rejectionWarnsAndDoesNothingElse` |
| M5 | make `AuthRoutes`' `AuthAbandoned` branch call `onIncomplete` | `abandonmentIsSilent` |
| M6 | return 502 instead of `nil` for non-stdio-without-starter | `httpAuthWithNoStarterIs405` |
| M7 | read `deps.configPath` instead of `config.manifestPath` | `approveCountsBeforeTheWriteAndReadsFresh` (+2) |
| M8 | capture the wrong upstream in the sink | `successClearsPendingThenReindexes` |
| M9 | set the daemon's `log:` to nil | `p1-auth-routes.sh` — B94 line absent |

**Two mutation-process defects worth carrying forward, both found here:**

- **M5 as planned could not have reddened anything.** `authStart` swallows `AuthAbandoned` without
  calling `onIncomplete`, so logging inside `onIncomplete` is not on the abandonment path. It was
  re-aimed at `AuthRoutes.authStart`'s own `catch` — the seam that actually carries B85 — rather
  than swapped for a mutation that happened to bite.
- **M9's first form did not compile, and the acceptance script ran against a stale binary and
  reported 11/11 green.** A mutation whose build fails is a *false* green, not a survived mutation.
  The rebuild's exit code is checked before any mutation result is believed now. Its second form
  hit the wrong `log: log` (there are four in that file; the first is `ManifestIndexer`'s) and also
  passed. Only the third, anchored on the surrounding comment, was the real test.

---

## 6. Surfaces proven, and how

| Surface | How verified | Result |
|---|---|---|
| `POST /servers/:name/approve`, 409 no-pending | `control-differential.sh` vs the running reference | byte-identical |
| `POST /servers/:name/auth`, 400 stdio refusal | `control-differential.sh` vs the running reference | byte-identical |
| both routes, unknown server → 404 | `control-differential.sh`, two new rows | byte-identical |
| both routes, untokened → 401 | differential 6f loop (reference) + `p1-auth-routes.sh` (Swift daemon) | 401 both |
| approve **200 promotion** | `ControlApproveDispatchTests` through `handle`, manifest bytes asserted; `p1-auth-routes.sh` over the socket | **Swift-side only — NOT two-router compared.** `compare_mutating` snapshots `servers.json`; approve writes `manifest.json`, and no helper covers that. Recorded in the manifest note, not hidden |
| B94 approval log line | `p1-auth-routes.sh` on the daemon's own output | logged; M9 proves it can fail |
| non-stdio `/auth` → 405 | `httpAuthWithNoStarterIs405` **and** `p1-auth-routes.sh` against a real http upstream on the daemon | 405 both |
| `DELETE /servers/:name/auth` after moving files | `control-differential.sh` (3 rows, unchanged) + `deleteAuthSurvivedTheMove` | unchanged |

---

## 7. Found and deliberately not fixed

| What | Why |
|---|---|
| `AuthRoutes.approve` uses `try? ManifestIO.save` and answers **200 whether or not the bytes landed**; the reference's `saveManifest` throws | A wire-status change outside this item's remit. **Measured rather than assumed** — `approveWithARefusingFileSystem` pins the current behaviour with a refusing filesystem, so the day someone changes it the change is deliberate. Spec §8 |
| `ControlDeps.currentFlow` is never populated in the daemon | Unreachable today (no starter can run). Becomes a visible wrong answer the moment `D-p1-a` lands — `GET /servers` would omit `pendingAuth` after a successful `POST /auth`. Registered **`D-p1-g`** |
| `cli-auth` not claimed | Two independent reasons: `mcp-router auth` POSTs to a **running** router and `run_both` starts none, so a comparison today compares two connection failures agreeing; and `parity-cli.sh`'s `OWNED` allow-list would refuse to record the id anyway. The **stdio half is provable** with the lane's existing `serve_side` — that is a scope call, not an impossibility, and `D-p1-d` says so |
| `install-launchd-watch` left `proven` | §3. Another lane's verdict; flagged in the manifest note and registered as `D-p1-e` with a recommendation |
| `deleteAuthSurvivedTheMove` cannot catch a `signedOut: true` regression | `NoAuth.clear` always returns false. The real guard is the differential's three DELETE rows against the live reference, which would catch it |

---

## 8. Children registered

Written into `planning/features-to-triage/D1-deferred-router.md` with the mechanism, not just a
label: **`D-p1-a`** (the OAuth client behind `AuthTransport`; owner is a new item, **not** R2 which
is merged and **not** R4-C which will not grow one), **`D-p1-c`** (`awaitCompletion` reports a
settled flow as absent, turning a successful authorization into a warn with no re-index),
**`D-p1-d`** (`cli-auth` needs a serve-backed row *and* the `OWNED` entry), **`D-p1-e`** (the
nondeterministic install watch row), **`D-p1-f`** (405 vs 501, contested), **`D-p1-g`**
(`currentFlow` unset in the daemon).

---

## 9. The merge-only defect this item hit

The branch was green alone and the **rebased tree did not compile**. V1 merged while P1 was in
flight and tightened `ControlDeps.fileSystem` from `any FileSystem` to
`any FileSystem & FileModeWriting`; `ControlAuthSupport.makeDeps` declared the loose type and passed
it through. `AuthTestFileSystem` already conformed to both, so the fix was the parameter type — but
**nothing on either branch could have caught it**, which is the whole argument for gating the merged
tree rather than the branch. Fixed and re-gated; the rebase itself was clean, 0 conflicts.
