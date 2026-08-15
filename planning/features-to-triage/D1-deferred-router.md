# D1 — The deferred register: router side

**Source:** `deferred-plan` = `schedule-all` (confirmed). The owner **chose differently from the
recommendation**: I suggested picking off the handful that are real gaps, and the answer was to
schedule the lot. So this is a batch, not a triage.

Twelve children, all router side. Take them in this order; the first four are real gaps and the rest
are smaller.

| Child | What |
|---|---|
| `D-w1` | Nothing renders `watch.log`, so a server that keeps failing to be adopted is **invisible**. The adoption protocol is the one part of the product with no window onto it |
| `D-w3` | `manifest.json`'s other writers are still unlocked. R2-W closed the seconds-wide window; the **microsecond** one between R3's and R5's writers remains, and it is the harder half |
| `R7` | Skills write endpoint (remove, disable) with preconditions and undo. Cleanup lists absent skills and can offer no action, because the control API is read-only for skills. M7's A16 asserts that gap rather than hiding it |
| `R8` | Server soft-delete with a restore endpoint. Removal is irreversible today, which is why it needs a named-consequence dialog |
| `R6` | Router-side behavioural eval runner, **servers only**. The router can start a server and call a tool; it cannot execute a skill, and a runner promising both would promise something the product does not do |
| `D-h` | Rename `callsServed` to what it measures. It is an **acquisition** counter, not a served-call count, and it is wire-visible, so the client and the Mac surfaces move with it |
| `D-d` | Make caller attribution deterministic rather than `lsof`-raced |
| `D-a` | Record the HTTP status alongside each recorded fixture |
| `D-g` | Parity vectors for divergences D1, D3 and D4. R1 recorded three deliberate divergences with **no vector**, so their absence currently reads as agreement |
| `D-r2r-b` | The control API has never been compared **over a socket**. Eleven `control` rows are proven against an in-process oracle that is not the wire |
| `D-r2r-a` | `mcp-router tools` has no empty state |
| `D-i` | The lost router restart in the TypeScript watcher. Declared so the Swift watcher does not reproduce it; R2-W already diverged deliberately, so **check whether this is now moot before doing anything** |

Two of these overlap the parity work (`D-g`, `D-r2r-b` both move rows), so coordinate with P1 to P4
rather than racing them on the same files.

---

## Registered by P1 (2026-08-15) — six children the auth-route work produced or uncovered

P1 fixed `D-j` and retired `D-r2r-c`. These are what it found on the way and deliberately did not
fix, each with the mechanism rather than a label. `D-p1-b` is folded into `D-p1-d`.

| Child | Owner | What, and why P1 did not do it |
|---|---|---|
| **`D-p1-a`** | **new item, R9** | **The OAuth client behind `AuthTransport`.** Nothing conforms to that protocol, so a **non-stdio** `POST /servers/:name/auth` has no flow to begin and answers 405 where the reference answers 200 with an authorization URL. The pieces that DO exist and are unused: `AuthFlowCoordinator`, `LoopbackCallbackListener`, `OAuthClientMetadata`, `FileAuthStore`, and `HTTPUpstreamTransport` (the SDK `HTTPClientTransport` wrapper, with `UpstreamAuthorizing`/`HTTPClientAuthorizer` as the attach point). What is missing is the OAuth *client*: authorization-server discovery, dynamic registration POSTing `OAuthClientMetadata`, the PKCE `authorization_code` exchange, and token persistence. An `HTTPClientAuthorizer` attaches a bearer token; it does not obtain one. **Not R2 (merged `a8091bb`) and not R4-C (the installer cutover, which will not grow an OAuth client).** Blocks the manifest row `control-auth-post-http` |
| **`D-p1-c`** | R9, with `D-p1-a` | **`AuthFlowCoordinator.awaitCompletion` reports a settled flow as "no authorization is in flight".** `AuthFlow.swift:240-249` throws when `current` is nil or names another server, so a flow that completes **between** `begin` returning and `awaitCompletion` being called turns a **successful** authorization into an `onIncomplete` warn — no `clearPending`, no re-index. The tokens land on disk and the tools never appear. Unreachable today (no production starter), which is the only reason P1 left it: the fix sits on the same `CheckedContinuation` that already trapped and killed the daemon once during R5, and it must not resume a superseded flow's continuation (B85). The requirement is written on the `AuthFlowStarting` protocol so whoever implements `D-p1-a` meets it rather than rediscovering it |
| **`D-p1-d`** | P4, or whoever next owns `parity-cli.sh` | **`cli-auth` needs a serve-backed row.** `D-j` no longer blocks it — the control lane compares both routes green. `mcp-router auth <server>` POSTs to a **running** router and then polls the auth dir, and `run_both` starts none, so comparing the verb today compares two connection failures agreeing with each other. Two pieces of work, and the second is the one that was skipped rather than impossible: build the row on the lane's existing `serve_side`, **and add `cli-auth` to the `OWNED` allow-list** (`parity-cli.sh:50-57`), which otherwise prints `LANE BUG: refusing to record` and the gate counts the row blocked anyway. The **stdio** half is provable this way today; the http half additionally needs `D-p1-a` |
| **`D-p1-e`** | R4 / P4 — **and it is a live gate problem, not a nicety** | **`parity-install.sh`'s watch row is nondeterministic, and it is currently marked `proven`.** Measured over six consecutive runs on one machine, `install-launchd-watch` produced `yes,yes,yes` / `yes,no,no` / `yes,yes,no` / `yes,no,yes` / `yes,yes,no` — the "reran" and "one-shot" terms are both unstable, on **both** binaries, and **which side loses the term alternates**, so it is launchd `WatchPaths` timing rather than a defect in either. **1 of 6 runs agreed.** Consequences: the row is coverage in name only; a `proven` row whose lane disagrees is reported as **DIVERGED**, which is worse than blocked; and R4-C cannot reach a stable 83/83 while it is there. P1 measured it and deliberately did **not** flip the row itself — that is another item's lane and changing a `proven` row's status changes the cutover gate's meaning. **Recommendation: mark it `blocked D-p1-e` until the lane waits on a launchd observable instead of a fixed delay.** Filing it as "flaky" would be the `D-p` mistake again: flaky invites re-running until green |
| **`D-p1-f`** | P4, with the parity harness | **The status a non-stdio `/auth` answers while `D-p1-a` is open is contested, and both reviews of it disagreed.** P1 ships **405** — the status the route already answered, so the change introduces **no new divergence** on any http or oauth upstream, which is what makes it safe to land into a parity effort mid-count. The counter-argument, raised by the completeness critic and recorded rather than dismissed: POST **is** allowed on that path (stdio answers 400, unknown answers 404), so 405 is semantically false, and it is the one status that makes `D-j` and `D-p1-a` indistinguishable to a client. `501 Not Implemented` carrying `ControlAuthSink.noStarter` would be more truthful. It was not taken because it is a **new** wire value the reference never sends there, so it needs a declared parity vector and a differential divergence row — P4/R4 work, not a dispatch fix. Settle it with the owner when `D-p1-a` is scheduled |
| **`D-p1-g`** | R9, with `D-p1-a` | **`ControlDeps.currentFlow` is never populated in the daemon.** `RouterServiceDispatch.controlResponse` does not pass it, so `GET /servers` will omit `pendingAuth` even after a successful `POST /auth` once a starter exists. Harmless today because no flow can start; it becomes a visible wrong answer the moment `D-p1-a` lands, and the Mac and phone surfaces read that member |
