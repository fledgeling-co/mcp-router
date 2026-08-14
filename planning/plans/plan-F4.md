# plan-F4 — ServerStateTracker cannot report failure

**Spec:** `planning/specs/spec-F4.md` · **Branch:** `ai/f4` · **Worktree:** `.worktrees/F4`
**Size tier:** Small — one production file, its test file, one additive test file, one mock. No new
module, no dependency, no wire change.

---

## Files this touches, and nothing else

| File | Change |
|---|---|
| `app/Sources/MCPRouterKit/Control/ServerStateTracker.swift` | the fix: `LoadState`, `StreamCondition`, typed-catch poll loop, stream-aware init |
| `app/Tests/MCPRouterKitTests/ServerStateTrackerTests.swift` | existing tests updated to the corrected semantics; new tests for A1–A11 |
| `app/Tests/MCPRouterKitTests/TrackerStateMatrixTests.swift` | **new** — A12 totality, A13 copy parity against the F4 mock |
| `design/mocks/html/f4-tracker-states.html` | **done in Phase 1** — the nine-state derivation specimen |
| `planning/specs/spec-F4.md`, `planning/plans/plan-F4.md` | the pipeline record |

**Not touched, deliberately:** `ControlAPIError`, `StreamPhase`, `ControlEventStream`,
`ControlAPIClient`, anything under `app/Sources/MCPRouterKit/Control/Fixtures/`, `install.sh`,
`src/*.ts`, `DESIGN.md`, `DesignDocParser.swift`, and every file in `.worktrees/M1`. A15 asserts the
fixtures directory is untouched with `git diff --stat`.

---

## Step 1 — the type

Replace `TrackerState`'s `phase: StreamPhase` with two independent facts.

```swift
public enum LoadState: Equatable, Sendable {
    case loading
    case loaded
    case failed(ControlAPIError)
    case stale(ControlAPIError)
}

public enum StreamCondition: Equatable, Sendable {
    case notConfigured
    case phase(StreamPhase)
}

public struct TrackerState: Equatable, Sendable {
    public var servers: [MCPServer]
    public var load: LoadState
    public var stream: StreamCondition
}
```

Both enums get doc comments stating *why* the case exists, not what it is called. `.stale` in
particular records that collapsing it into `.failed` throws away data the user is reading, and that
collapsing it into `.loaded` hides that the data has stopped updating.

Internal storage on the actor gains `load: LoadState = .loading`, `hasLoaded: Bool = false`, and
replaces `phase: StreamPhase = .disconnected` with `streamCondition: StreamCondition`.

## Step 2 — the initialiser decides the stream condition once

```swift
self.streamCondition = stream == nil ? .notConfigured : .phase(.disconnected)
```

This is the whole of fault 2. A tracker with no stream can now never be mistaken for one whose
stream dropped, because the two are different values from the moment it is constructed. `.phase(.disconnected)`
remains correct for a configured-but-not-yet-connected stream: it is not connected, and `run()` will
move it.

## Step 3 — the poll loop stops discarding errors

```swift
private func pollLoop() async {
    while !Task.isCancelled {
        do {
            let response = try await client.servers()
            apply(poll: response)
        } catch {
            apply(pollFailure: error)   // typed: `client.servers()` is `throws(ControlAPIError)`
        }
        do { try await clock.sleep(for: pollInterval) } catch { return }
    }
}
```

Swift 6 typed throws binds `error` as `ControlAPIError` with no cast and no `as?`, so the whole of
F3's distinction arrives intact — including `.server(status:message:hint:)` with its hint, which A10
asserts.

The `clock.sleep` `do/catch` stays as it is: that `catch` means cancellation, and returning is
correct. It is not an error being swallowed.

## Step 4 — applying a failure, and the `.stale` rule

```swift
public func apply(pollFailure error: ControlAPIError) {
    load = hasLoaded ? .stale(error) : .failed(error)
    // `servers` and `order` are deliberately NOT cleared.
    publish()
}
```

and `apply(poll:)` gains `hasLoaded = true; load = .loaded` before its `publish()`.

`hasLoaded` is what makes `.failed` and `.stale` decidable. `servers.isEmpty` cannot do it: a
successful poll returning zero servers is the genuine Empty state, and using emptiness as the test
would render a first-run empty router as a hard failure. That is the same class of bug the
TypeScript router already shipped once — a flat `servers.json` read as zero servers with no error —
and `SWIFT_PRACTICES.md` §2 names it as the failure mode never to write.

**Illegal states are unrepresentable by construction:** `.stale` is only ever assigned when
`hasLoaded` is true, and `hasLoaded` is only ever set by a successful poll. `.loaded` carries no
error. The four cases are mutually exclusive and the switch over them is compiler-checked exhaustive.

## Step 5 — `apply(phase:)` cannot fabricate a stream

```swift
public func apply(phase newPhase: StreamPhase) {
    guard case .phase(let current) = streamCondition else { return }  // polling-only: nothing to report
    guard current != newPhase else { return }
    streamCondition = .phase(newPhase)
    publish()
}
```

Without the first guard a caller could put a polling-only tracker into `.phase(.live)`, which would
be the same lie in the other direction — a surface drawing a live stream indicator for a stream that
does not exist. A8 asserts the guard holds.

## Step 6 — publish on failure

`publish()` already fans out to every continuation; the only change needed is that
`apply(pollFailure:)` calls it. A11 exists because a tracker that notifies only on success leaves a
subscribed surface frozen on the last good frame with no way to learn the feed has died — which is
the same invisible-failure shape as the original `try?`.

## Step 7 — tests

**Updated (not weakened).** `phaseIsTracked` currently asserts `state.phase == .disconnected` on a
stream-less tracker, which is an assertion *of the defect*. It splits into two tests: a stream-less
tracker asserting `.notConfigured`, and a stream-carrying tracker asserting phase movement. Assertion
count goes up. The other five existing tests need only the `TrackerState` field rename.

**New**, one per criterion, using `FixtureControlAPIClient` and the existing `server(_:state:)` /
`response(_:)` helpers:

- A1/A2 — failure with no prior success → `.failed(.routerNotRunning)`; and `.failed(.unauthorized)`
  asserted `!=` it. Two errors, one assertion each way.
- A3 — poll, then fail → `.stale`, servers still present and equal to the earlier snapshot.
- A4/A5 — `.loaded` with order preserved; `.loading` initial and `!= .loaded` with `[]`.
- A6/A7/A8 — the three stream-condition facts.
- A9 — `.stale` → success → `.loaded`, observed through `updates()`.
- A10 — `.server(status: 503, message:, hint:)` survives the loop with its hint intact.
- A11 — a subscriber receives a state whose `load` is a failure.

**A12/A13** in the new `TrackerStateMatrixTests.swift`: parse `DESIGN.md` §5's nine state names with
`DesignDocParser.designDocURL` + `cells(of:)` (both already internal statics — the shared parser is
**not** modified), parse the F4 mock's derivation table, and assert every §5 state name appears in
it. Then assert the mock contains `ControlAPIError.headline` / `.advice` / `.actionLabel` verbatim
for `.routerNotRunning` and `.unauthorized`, reusing `ControlCopyTests`'s normalisation approach.

**A14 — the red-green ledger.** Every guard is observed failing before it counts. The named one the
brief demands: reintroduce `try?` in `pollLoop()`, watch the A1/A2/A3/A11 tests go red, restore.
Recorded in the spec's ledger with the observed failure message.

## Step 8 — the loop that must actually run

`make test` counts `swift test list` before running and fails on zero. The full gate is `make all`
(tools → lint → build → test → parity); it is run and its output reported, never asserted.

---

## Risks

| Risk | Handling |
|---|---|
| Reshaping `TrackerState` breaks a consumer | Verified zero consumers outside the tracker and its tests. Re-grep after the edit. |
| `.stale` collapses to `.failed` under review pressure | A3 asserts servers survive; the mock and spec both state why. |
| Touching `StreamPhase` moves F3's contract R4 diffs against | `StreamCondition` wraps it; A15 asserts the fixtures directory is byte-identical. |
| A concurrent runner's build breaks | All work in `.worktrees/F4`; M1's worktree and its workaround untouched. |
| A test passes without the fix | A14's red-green pass is the check, and it is recorded, not claimed. |
