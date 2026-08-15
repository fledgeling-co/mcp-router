# plan-P1 — Make the two auth routes reachable

Spec: `planning/specs/spec-P1.md` · Branch `ai/p1` · Worktree `.worktrees/P1`
Tier: **Small** — two dispatch arms, one new port, and the harness edits that keep the gate honest.

Baseline measured before any edit, from `.worktrees/P1`: **parity 72 of 82 proven, 10 blocked,
exit 1**; `swift build` exit 0. (The orchestrator's repo-root figure is 71 — the one-row gap is
`D-o`, whose normaliser omits `-` from its character class, so `P1` normalises and `mcp-router`
does not. Every number below is from `.worktrees/P1`.)

---

## Step 1 — `ControlPorts.swift`: the flow-starter seam and the log

Two additions to `ControlDeps`, both defaulted in `init` so no existing call site changes:

```swift
public var log: RouterLog?
public var authFlow: (any AuthFlowStarting)?
```

`log` is what makes B94's `approved "<name>"'s new tool surface (N tools)` emittable —
`AuthRoutes.approve` already takes a `RouterLog?` and every caller has been passing nothing because
`ControlDeps` had nowhere to hold one. `RouterLogEvent.toolSurfaceApproved` and
`.authorizationIncomplete` already exist with the reference's exact strings, so no new log case is
written.

The new port, in the same file beside `UpstreamPoolPort` and `AuthStore`:

```swift
/// Beginning a browser authorization — the reference's `beginAuth(name, authTransportFor(u))`.
///
/// Optional on ``ControlDeps`` because the collaborator behind it does not exist yet: no type
/// conforms to ``AuthTransport`` (D-p1-a). A handler that constructed the coordinator itself could
/// not be told that, and would have to invent an answer for a flow it cannot drive.
public protocol AuthFlowStarting: Sendable {
    /// Returns once the authorization URL is known. Throws on either pre-flow failure (B84), which
    /// the route turns into a 502.
    func begin(server: JSString, upstream: UpstreamConfig) async throws -> LiveFlow

    /// Resolves when the flow terminates: returns on success, throws the rejection on failure, and
    /// throws ``AuthAbandoned`` when the flow was superseded (B85).
    ///
    /// **`begin` must arm this channel before it returns.** A flow that settles between the two
    /// calls must still be reported here as authorized. `AuthFlowCoordinator.awaitCompletion` does
    /// **not** satisfy that today — it throws `no authorization is in flight` once the flow has
    /// settled, which would turn a successful authorization into an `onIncomplete` warn with no
    /// `clearPending` and no re-index. Registered as **D-p1-c**; the constraint lives here so an
    /// implementer of D-p1-a meets it rather than rediscovering it.
    func awaitCompletion(server: JSString) async throws
}
```

## Step 2 — new file `Control/ControlAuthDispatch.swift`

`ControlHandler.swift` is 376 lines against SwiftLint's default 400-line file warning, so the two
arms' bodies go in their own file rather than inflating it. That is also the honest seam: this file
is the control API's *auth* surface, and the same-file `private` trick the usage routes use does not
reach across files, so these are `internal`.

It holds two things.

**`ControlAuthSink`** — `AuthRoutes.CompletionSink` over collaborators `ControlDeps` already has:

```swift
struct ControlAuthSink: AuthRoutes.CompletionSink {
    let pool: any UpstreamPoolPort
    let indexer: any UpstreamIndexerPort
    /// Captured at request time, exactly as the reference closes over `u` — a later config reload
    /// must not re-index a different server than the one that was authorized.
    let upstream: UpstreamConfig
    let log: RouterLog?

    func onAuthorized(server: JSString) async {
        // `deps.pool.clearPending(name)` THEN `await indexOne(u, deps.cfg)` — that order, and only
        // on success. The reference's `.then` body, statement for statement.
        pool.clearPending(server)
        _ = await indexer.index(upstream)
    }

    func onIncomplete(server: JSString, reason: String) async {
        await log?.log(.authorizationIncomplete(server: server.string, reason: reason))
    }
}
```

**The two dispatch bodies**, as an extension:

```swift
extension ControlHandler {
    /// `POST /servers/:name/approve`. Every argument is already on `deps`; the route was simply
    /// never dispatched.
    func approveToolSurface(name: JSString, deps: ControlDeps) async -> ControlAPIResponse {
        let result = await AuthRoutes.approve(
            server: name,
            manifestPath: deps.config.manifestPath,
            fileSystem: deps.fileSystem,
            nowMilliseconds: deps.clock.nowMilliseconds,
            log: deps.log
        )
        return .json(result.status, result.body)
    }

    /// `POST /servers/:name/auth`.
    ///
    /// `nil` — falling through to the 405 — for exactly one case: a non-stdio upstream with no flow
    /// starter configured. That is the truthful answer while D-p1-a is open. A 502 would say the
    /// upstream was tried and failed, which is the reference's meaning for that status and is not
    /// what happened; it is also the retryable class, so a client would retry something that can
    /// never succeed. The stdio refusal needs no starter — it is `authStart`'s own first branch and
    /// returns before any flow begins — so it is answered either way.
    func authorize(
        upstream: UpstreamConfig, name: JSString, deps: ControlDeps
    ) async -> ControlAPIResponse? {
        guard upstream.isStdio || deps.authFlow != nil else { return nil }
        let starter = deps.authFlow
        let result = await AuthRoutes.authStart(
            server: name,
            isStdio: upstream.isStdio,
            sink: ControlAuthSink(
                pool: deps.pool, indexer: deps.indexer, upstream: upstream, log: deps.log
            ),
            begin: {
                guard let starter else { throw AuthFailure(Self.noStarter) }
                return try await starter.begin(server: name, upstream: upstream)
            },
            awaitCompletion: {
                guard let starter else { throw AuthFailure(Self.noStarter) }
                try await starter.awaitCompletion(server: name)
            }
        )
        return .json(result.status, result.body)
    }
}
```

The two `guard let starter` arms are unreachable from `authorize` (the outer guard already returned
for that case) and exist because the closures outlive it; they are written to throw rather than
force-unwrap, since `force_unwrapping` is an opt-in lint rule here.

## Step 3 — `ControlHandler.swift`: two case arms, six lines

Into `dispatchServer`'s switch, placed to match the reference's own order in `src/control.ts` —
`/approve` after `/changes`, `/auth` POST before `/auth` DELETE:

```swift
case ("/approve", "POST"):
    return await approveToolSurface(name: name, deps: deps)

case ("/auth", "POST"):
    return await authorize(upstream: upstream, name: name, deps: deps)
```

`dispatchServer` takes `deps` as `inout`; both helpers read only, so they take a value copy. The
`default: nil` arm is unchanged and still carries every genuinely unrouted case to the 405.

## Step 4 — tests: `ControlAuthDispatchTests.swift`, all through `handle`

The spec's first review finding was that the previous criteria were already green in
`AuthRoutesTests` against functions the handler never calls. **Every test here builds a
`ControlDeps`, calls `ControlHandler.handle`, and asserts on the `ControlAPIResponse`** — nothing
calls `AuthRoutes` directly.

| Test | Asserts | AC |
|---|---|---|
| `approveWithNoPendingIs409` | status 409, body `{"error":"no pending change for \"s1\""}` | A1 |
| `approvePromotesThroughTheHandler` | 200 `{"server":"s1","approved":2}`; then re-reads `manifest.json` **from disk**: `tools` == former `pending.tools`, `builtAt` fresh, **no `pending` member**; then a second `handle` call for `GET /servers/s1/changes` reports `pending:false` | A2 |
| `approveCountsBeforeTheWriteAndReadsFresh` | the manifest is rewritten on disk *after* deps are built; the promoted entry is the disk one and `approved` is its pre-write count | A3 |
| `approveWithARefusingFileSystem` | records the measured status and whether the disk state changed. Written to **document** whatever `try? ManifestIO.save` does, not to assert a status this item chose | A4 |
| `stdioAuthIs400AndStartsNothing` | 400 with the exact sentence; the recording starter's `begin` count is 0 and the `FakeListener` bound nothing | A5, A11 |
| `httpAuthWithAStarterIs200` | 200 `{"server":…,"authorizationUrl":…}`; the starter settles the flow *before* the response is read and the side effect still lands | A6 |
| `successClearsPendingThenReindexes` | recording pool + indexer: `clearPending` precedes `index`, and `index` receives **the upstream captured at request time** | A7 |
| `rejectionWarnsAndDoesNothingElse` | one `authorizationIncomplete` line with B79's text; `clearPending` count 0, `index` count 0 | A8 |
| `abandonmentIsSilent` | `AuthAbandoned`: no log line, no `clearPending`, no `index` | A9 |
| `httpAuthWithNoStarterIs405` | 405, the status this route answered before the change | A10 |
| `unknownServerOnBothNewRoutesIs404` | both POSTs to `/servers/ghost/...` → 404, before either route runs | A11 |
| `untokenedPostToBothNewRoutesIs401` | both → 401, ahead of the 404 | A11 |

Doubles: `RecordingStarter` (counts `begin`, can settle before `awaitCompletion` to exercise the
D-p1-c boundary), `RecordingPool`, `RecordingIndexer`, and a log sink reading `RouterLog`'s output.

## Step 5 — mutations, proven red then green

Each is applied, the named test is run and must go **red**, then reverted by re-applying the original
text (never `git checkout --`, which destroyed a fix earlier in this fleet):

| # | Mutation | Must redden |
|---|---|---|
| P1-M1 | Delete the `("/approve","POST")` arm | `approveWithNoPendingIs409` |
| P1-M2 | Delete the `("/auth","POST")` arm | `stdioAuthIs400AndStartsNothing` |
| P1-M3 | Swap `clearPending`/`index` order in the sink | `successClearsPendingThenReindexes` |
| P1-M4 | Run the sink's body on `onIncomplete` too | `rejectionWarnsAndDoesNothingElse` |
| P1-M5 | Log a line in `onIncomplete` for `AuthAbandoned` | `abandonmentIsSilent` |
| P1-M6 | Return `.json(502, …)` instead of `nil` for non-stdio-without-starter | `httpAuthWithNoStarterIs405` |
| P1-M7 | Pass `deps.manifest`'s snapshot instead of reading `manifestPath` fresh | `approveCountsBeforeTheWriteAndReadsFresh` |
| P1-M8 | Capture the reloaded upstream instead of the request-time one in the sink | `successClearsPendingThenReindexes` |

A mutation that does **not** redden is reported as a coverage gap and the missing test written —
never swapped for one that happens to bite.

## Step 6 — `control-differential.sh`: retire D-r2r-c in this change

1. Delete the `known_defect` function (lines ~446–472) **and** its 12-line preamble; both exist only
   to describe D-j.
2. Replace the two `known_defect` calls with real rows. Neither route mutates on the path issued —
   approve returns 409 before any write, auth returns 400 before any flow — so `compare` is correct
   and `compare_mutating` would be misleading:
   ```
   compare control-approve-post "POST /servers/:name/approve"  POST "/servers/diff-stdio/approve" '{}'
   compare control-auth-post    "POST /servers/:name/auth"     POST "/servers/diff-stdio/auth"    '{}'
   ```
3. Add the 404 probes beside the existing unknown-server rows:
   ```
   compare control-approve-post "approve on an unknown server"  POST "/servers/nope/approve" '{}'
   compare control-auth-post    "POST auth on an unknown server" POST "/servers/nope/auth"   '{}'
   ```
4. Extend the 6f token-gate loop's list with `"POST /servers/diff-stdio/approve"` and
   `"POST /servers/diff-stdio/auth"` — a one-line edit to a list that already probes three routes.

## Step 7 — `surface.tsv`

| Row | Before | After |
|---|---|---|
| `control-approve-post` | `blocked D-j` | `proven` |
| `control-auth-post` | `blocked D-j` | `proven` — note narrowed to say it covers **the stdio refusal**, which is what the row always described |
| `control-auth-post-http` | *absent* | **new**, `blocked D-p1-a` — the non-stdio half, reference 200 with an authorization URL, Swift 405 |
| `cli-auth` | `blocked R2-R` | measured; see step 8 |

Adding a row takes the denominator **82 → 83** and moves R4-C's cutover target to 83/83. That is
deliberate and is reported to the orchestrator rather than absorbed: a `control-auth-post` reading
`proven` for a route half of which this router cannot serve is exactly the false certainty the gate
exists to prevent, and the conservative direction (declare the gap) is the one this repo's own notes
demand — `D-g`: an absent vector must not be read as parity.

`parity-gate.sh` and `parity-fixture.sh` are **not touched**; P4 owns them.

## Step 8 — `cli-auth`, claimed only if measured

`parity-cli.sh` seeds `probe` as a stdio server, so after step 3 `mcp-router auth probe` drives the
stdio refusal on both binaries and should agree on stdout, stderr and exit. **Run the lane and read
the result.** If it agrees, claim the row and replace the hardcoded
`"cli-auth stays blocked on D-j and is not claimed here"` line with the comparison; if it does not,
leave the row blocked and correct its note to name what actually blocks it. The row is never claimed
on the reasoning above alone.

## Step 9 — `scripts/acceptance/p1-auth-routes.sh`, the socket half (D-r2r-b)

One script, this item's surfaces only — no sweep. It starts a real `MCPRouterCLI serve` on an
ephemeral port against a temp home with one stdio server, waits for `/health`, then asserts:

| # | Request | Expect |
|---|---|---|
| 1 | `POST /servers/<stdio>/approve` + token | `409` `{"error":"no pending change for \"<stdio>\""}` |
| 2 | `POST /servers/<stdio>/auth` + token | `400` `{"error":"stdio servers do not authorize; their credentials are env vars"}` |
| 3 | same two, **no token** | `401` both |
| 4 | `POST /servers/ghost/approve` + token | `404` |
| 5 | approve with a **pending** manifest entry | `200` `{"server":…,"approved":N}` and `pending` gone from the file on disk |

It exits 2 on an environment failure (the daemon did not bind) and 1 on a wrong answer, matching the
house pattern — a daemon that never started must not read as a passing check. It is the only place
the two routes are proven over a socket rather than through `ControlDiff`.

## Step 10 — gates, each with its exit code captured directly

Never through a pipeline (a pipe reports the last command's status, and a log here has read
`lint exit: 0` while every target failed). `make lint` runs `swiftformat --lint` first and
short-circuits, so a "0 violations" line from the swiftlint half is not a pass — only `$?` is.

```
swift build --package-path app   > /tmp/f 2>&1; echo $?
make lint                        > /tmp/f 2>&1; echo $?
make test                        > /tmp/f 2>&1; echo $?
bash scripts/acceptance/p1-auth-routes.sh    > /tmp/f 2>&1; echo $?
bash scripts/acceptance/control-differential.sh > /tmp/f 2>&1; echo $?
bash scripts/acceptance/parity-cli.sh        > /tmp/f 2>&1; echo $?
bash scripts/acceptance/parity-gate.sh       > /tmp/f 2>&1; echo $?
```

A `swift test --filter` uses the **function name**, never the `@Test` display string — a display-name
filter matches nothing and reports *"Test run with 0 tests in 0 suites passed"*, a green that means
nothing. Any filter is confirmed to match before a red or a green from it is believed.

`make build-mac` and the Mac acceptance scripts are **not run**: this item's diff touches
`RouterCore`, `ControlDiff` and `scripts/acceptance/` only, and no Mac surface. Re-testing screens
this item did not change is the specific waste the owner has called out.

## Step 11 — parity after, from `.worktrees/P1`

Re-run `parity-gate.sh` from the same directory as the baseline and report before/after with exit
codes. Expected movement, each attributed to a named row:

- `control-approve-post` blocked → proven **(+1)**
- `control-auth-post` blocked → proven **(+1)**
- `cli-auth` blocked → proven **(+1, only if step 8 measures green)**
- `control-auth-post-http` **new blocked row (denominator +1)**

so **72 of 82 → 75 of 83**, blocked 10 → 8, exit still **1** by design (the gate exits 0 only at
100%, which the cutover requires and this item does not deliver). If any figure differs from this,
the measured figure is reported and the difference explained — the prediction is not the evidence.

## Step 12 — evidence and commit

`planning/evidence/P1-acceptance.md`: one row per surface with the exact command, the exit code, the
HEAD SHA, and the review lane (`grok-4.6`, `codex` not probed — account-limited to 2026-08-20 by
the owner's standing instruction). Both reviews' verdicts and every finding's disposition recorded.

Commit on `ai/p1` via `git commit -F` (backticks inside a double-quoted shell string are command
substitution and have eaten a word out of a commit message in this repo before). **No push, no
merge** — the orchestrator serialises merges.
