# spec-P1 — Make the two auth routes reachable

| | |
|---|---|
| Status | Ready for Work |
| Category | router |
| Depends on | R3 ✓ (owns `ControlHandler`'s dispatch) · R5 ✓ (built `AuthRoutes`) |
| Defects closed | `D-j` · `D-r2r-c` |
| Branch | `ai/p1` |
| Brief | `planning/features-to-triage/P1-auth-routes-reachable.md` |
| Review | grok-4.6, adversarial. **AMEND**, 11 findings, 10 accepted. §9 |

---

## 1. The brief, verbatim

> `AuthRoutes.approve` and `AuthRoutes.authStart` are both implemented and both unreachable over the
> wire: `ControlHandler`'s dispatch never routes to them, so they answer 405 where the reference
> answers 409 and 400. Registered as `D-j`. **Blocks 2 parity rows.**
>
> Fixing it also retires `control-differential.sh`'s known-defect assertions for those two routes
> (`D-r2r-c`) in the same change. Do both together or the differential goes red on a defect that has
> just been fixed, which is the worst kind of red.
>
> **Done means:** both routes reachable over a real socket, the differential's stale assertions gone,
> and the parity gate's proven count risen by 2 measured from the same directory before and after
> (`D-o` makes the figure depend on the directory name).

## 2. What is actually there — measured

| # | Measurement | Where |
|---|---|---|
| M1 | `dispatchServer`'s switch carries `(nil, GET/DELETE/PATCH)`, `("/reindex","POST")`, `("/changes","GET")`, `("/auth","DELETE")`. **No `/approve` arm and no `("/auth","POST")` arm.** Everything else falls to `default: nil` and then to the 405 at the end of `handle` | "// The auth family — `/approve`, `/auth` POST and `/auth` DELETE — lives in", `ControlHandler.swift:188-243` at `30b3ec0`, `:74` |
| M2 | `AuthRoutes.approve` needs `server`, `manifestPath`, `fileSystem`, `nowMilliseconds`, `log`. `ControlDeps` carries `config.manifestPath`, `fileSystem`, `clock.nowMilliseconds`. **It carries no log**, so B94's `approved "<name>"'s new tool surface` line is currently unemittable | `public static func approve(`, `AuthRoutes.swift:80-86` at `30b3ec0`, "/// conforms to ``AuthTransport``, so nothing can drive an OAuth exchange (`D-p1-a`). A", `ControlPorts.swift:130-148` at `30b3ec0` |
| M3 | `AuthRoutes.authStart` needs `isStdio`, a `CompletionSink`, a `begin` closure, an `awaitCompletion`. `UpstreamConfig.isStdio` exists; `pool` and `indexer` (the two things the sink must drive) are already in `ControlDeps`. **The flow starter is not** | `public static func authStart(`, `AuthRoutes.swift:32-38` at `30b3ec0`, `public var isStdio: Bool { transport == .stdio }`, `UpstreamConfig.swift:71` at `30b3ec0` |
| M4 | `AuthFlowCoordinator` is complete and **constructed by nothing in `app/Sources/`** — every reference is in `app/Tests/`. `ControlDeps.currentFlow` is therefore always nil in the daemon | `public actor AuthFlowCoordinator {`, `AuthFlow.swift:37` at `30b3ec0`, `RouterService.swift:45,80` |
| M5 | **The HTTP transport exists.** `HTTPUpstreamTransport` wraps the pinned SDK's `HTTPClientTransport`, `RoutingUpstreamTransport` selects it, and `UpstreamAuthorizing`/`HTTPClientAuthorizer` is the documented attach point. What does **not** exist is an OAuth *client*: nothing performs discovery, nothing POSTs `OAuthClientMetadata` for dynamic registration, nothing does the PKCE `authorization_code` exchange, and no type conforms to `AuthTransport`. R5's own comment: *"R5 ships the protocol and a double, not a live transport."* An `HTTPClientAuthorizer` attaches a bearer token; it does not obtain one | `public struct RoutingUpstreamTransport: UpstreamTransporting {`, `ServicePorts.swift:106-165` at `30b3ec0`, "/// The authorizer is the pinned SDK's own `HTTPClientAuthorizer` rather than an opaque", `RouterSeams.swift:230-247` at `30b3ec0`, `import Foundation`, `AuthFlow.swift:1-12` at `30b3ec0` |
| M6 | `AuthFlowCoordinator.awaitCompletion` throws `AuthFailure("no authorization is in flight")` whenever `current` is nil or names another server. A flow that settles **between** `begin` returning and `awaitCompletion` being called therefore reports a **successful** authorization as `onIncomplete` — a warn line, no `clearPending`, no re-index | `public func awaitCompletion(server: JSString) async throws {`, `AuthFlow.swift:240-249` at `30b3ec0` |
| M7 | `parity-cli.sh` seeds `"probe": { "command": "node", … }` — a **stdio** server. `mcp-router auth probe` therefore drives the stdio refusal, not the browser flow | `parity-cli.sh:86,166,305,324` |
| M8 | `control-differential.sh` drives `ControlDiff`, an in-process oracle, not a socket. Registered as `D-r2r-b` | `control-differential.sh`, `ControlDiff/main.swift` |

## 3. Three parity rows key on D-j, and the surface enumerates the route as one row when it is two

`planning/parity/surface.tsv`:

| Row | Blocker column | What its note says |
|---|---|---|
| `control-approve-post` | `D-j` | reference 409, Swift 405 |
| `control-auth-post` | `D-j` | *"The reference answers 400 **for a stdio server**; Swift answers 405"* |
| `cli-auth` | `R2-R` | *"cannot be compared because the Swift router answers 405 … — **defect D-j**"* |

Two consequences the brief's "+2" does not capture, and both are recorded rather than absorbed:

- **`cli-auth` becomes genuinely comparable** (M7): its fixture is a stdio server, so after this change
  both binaries answer `400` with the same sentence and the verb's stdout/stderr/exit agree. Holding
  it blocked to keep the arithmetic at "+2" would be `D-n`'s failure in reverse — a provable row held
  down. It is claimed **only if measured green**, never on this reasoning alone.
- **`control-auth-post` describes the stdio half only.** Proving it on stdio is faithful to the row as
  enumerated, but it would leave the non-stdio half — where the reference answers 200 with an
  authorization URL — proven by nothing and counted by nobody. A new row `control-auth-post-http` is
  added as **blocked on `D-p1-a`**. This **raises the denominator to 83** and moves R4-C's cutover
  target from 82/82 to 83/83. That consequence is stated loudly rather than avoided: the alternative
  is a row that reads `proven` for a route half of which the router cannot serve, which is precisely
  what the parity gate exists to prevent.

## 4. The scope fork, settled

**Q: does P1 build the OAuth client so the non-stdio `/auth` path reaches full parity?**

No — but not for the reason the first draft of this spec gave. That draft claimed the router had no
HTTP transport at all; M5 measures that it does. The corrected reason is narrower and still holds:
the missing piece is authorization-server discovery, dynamic client registration, the PKCE
`authorization_code` exchange and token persistence — an OAuth client, sitting behind the
`AuthTransport` protocol R5 deliberately left unimplemented. That is an item, not a dispatch arm, and
this item is called "make the two auth routes reachable".

**Q: what does a non-stdio `POST /servers/:name/auth` answer until then?**

**405, unchanged.** Not 502. The first draft proposed 502 on the grounds that it is the reference's
own "the flow could not begin" status; the review defeated that and the defeat is accepted:

- The reference's 502 means `beginAuth` *ran and threw* — a bind failure, or the 20-second URL race.
  Reusing it for "no starter was ever constructed" makes two different failures indistinguishable to
  the one reader who needs them apart.
- 502 is the retryable gateway class. `LiveControlAPIClient.beginAuthorization` and `mcp-router auth`
  would tell a user to try again at something that can never succeed. 405 says the router does not
  serve this here, which is true.
- It would be a **new** divergence on every http and oauth upstream — including `diff-http` and
  `diff-oauth`, which the harness already has and does not compare — introduced by a change whose
  purpose is removing divergences.

So the arm is wired for real, with real collaborators, and the **only** guarded case is "non-stdio
with no flow starter configured", which returns `nil` and lets the existing 405 stand. When
`D-p1-a` lands and supplies a starter, the full path works with **no further change to dispatch**.

## 5. Acceptance criteria

Every criterion below is proven **through `ControlHandler.handle` or over the daemon's socket**. The
review's first finding was that the previous draft could be satisfied by a hardcoded stub, because
its criteria were already green in `AuthRoutesTests` against functions the handler never calls. Any
criterion a stub can pass is not a criterion.

| # | Criterion | Oracle |
|---|---|---|
| **A1** | `POST /servers/diff-stdio/approve` with no pending change → **409** `{"error":"no pending change for \"diff-stdio\""}`, byte-identical to the reference | `control-differential.sh` `compare control-approve-post` |
| **A2** | `POST /servers/:name/approve` **with** a pending change, driven through `handle`, → **200** `{"server":…,"approved":N}` **and** the on-disk `manifest.json` afterwards has `tools` == the former `pending.tools`, a fresh `builtAt`, and **no `pending` member**; a following `GET /servers/:name/changes` through `handle` reports `pending:false` | Swift test over a real temp manifest, asserting the file's bytes **and** the follow-up response |
| **A3** | A2's `approved` count is the **pre-write** `pending.tools.length`, and the manifest is read **fresh from disk** — an entry mutated on disk after `deps.manifest` was snapshotted is still promoted (B88) | Swift test through `handle` that writes the manifest after building deps |
| **A4** | When the manifest write **fails**, approve does not claim success it did not achieve | Swift test through `handle` with a refusing `FileSystem`. Records the measured behaviour; if `try?` currently swallows it, that is registered, not hidden |
| **A5** | `POST /servers/diff-stdio/auth` → **400** `{"error":"stdio servers do not authorize; their credentials are env vars"}`, byte-identical to the reference, **and no port is bound and the flow starter is never called** | `compare control-auth-post` + a Swift test through `handle` with a recording starter and a `FakeListener` |
| **A6** | `POST /servers/:name/auth` on a **non-stdio** server **with a starter** → **200** `{"server":…,"authorizationUrl":…}`, and the completion handler is registered **before** the 200 is built | Swift test through `handle` with a starter that settles the flow before the response is read; the side effect must still land |
| **A7** | On success the sink runs `pool.clearPending(name)` **then** re-indexes **the upstream captured at request time**, in that order and only on success | Swift test through `handle` with a recording pool + indexer asserting order and identity |
| **A8** | On rejection: exactly one warn line, text `authorization for "<name>" did not complete: <message>` (B79), and **neither** `clearPending` nor re-index | Swift test through `handle` |
| **A9** | On `AuthAbandoned` (superseded, B85): **no** log line, **no** `clearPending`, **no** re-index — and the abandonment is not wrapped into an `AuthFailure` on the way | Swift test through `handle` |
| **A10** | A non-stdio `/auth` with **no starter** → **405**, the same status as before this change. Never 200, never 502, never a fabricated URL | Swift test through `handle` |
| **A11** | An **unknown** server on either new route → **404** before the route runs; an **unauthenticated** POST to either → **401** before the 404 | Two new `compare` rows in the differential, issued against both routes — not inherited from the DELETE sibling |
| **A12** | Both routes answer over a **real socket** on the running daemon: `POST /servers/<stdio>/approve` → 409 and `POST /servers/<stdio>/auth` → 400, with the exact bodies above | `scripts/acceptance/p1-auth-routes.sh`, starting `MCPRouterCLI serve` and curling it. This is the D-r2r-b half the differential cannot give |
| **A13** | `control-differential.sh`'s `known_defect` calls for these two rows are replaced by real `compare` rows and the `known_defect` **function is deleted**, not left dead | Read the script; the two rows report `ok` |
| **A14** | `surface.tsv`: `control-approve-post` and `control-auth-post` → `proven`; `control-auth-post-http` added as `blocked D-p1-a`; `cli-auth`'s note corrected to name its real blocker | Gate reconciliation |
| **A15** | Parity measured **from `.worktrees/P1` before and after**. Before: 72 of 82, 10 blocked, exit 1. After: the proven count rises by the rows actually measured green and the denominator rises by 1, and **every** delta is attributed to a named row | `parity-gate.sh`, twice, same directory |

## 6. Out of scope

- **`parity-gate.sh` and `parity-fixture.sh`** — P4 owns them; `D-o`'s normaliser moves the coverage
  number and must be reviewed by someone who does not benefit from it.
- **The OAuth client** — §4, registered as `D-p1-a`.
- **Fixing `AuthFlowCoordinator.awaitCompletion`'s race (M6)** — registered as `D-p1-c`, not fixed.
  It is R5's file, it is unreachable today (no production starter), and the fix sits on the same
  `CheckedContinuation` that already trapped and killed the daemon once during R5. The port's
  contract names the requirement so an implementer of `D-p1-a` cannot miss it, and A6 pins the
  handler's side of the boundary.
- **Wiring `AuthFlowCoordinator` into `RouterService`** — it needs a transport to drive; wiring it
  without one adds a collaborator that can only fail.

## 7. Deferred children

| # | Child | Owner | Mechanism |
|---|---|---|---|
| `D-p1-a` | The OAuth client behind `AuthTransport`: authorization-server discovery, dynamic registration POSTing `OAuthClientMetadata`, the PKCE `authorization_code` exchange, and token persistence into `FileAuthStore` | **New item — R9.** *Not* R2 (merged `a8091bb`) and *not* R4-C (the installer cutover, which will not grow an OAuth client) | Until it lands, non-stdio `POST /servers/:name/auth` answers 405 where the reference answers 200 with an authorization URL. `AuthFlowCoordinator`, `LoopbackCallbackListener`, `OAuthClientMetadata` and `FileAuthStore` are all complete and unused; the transport is the missing piece. Blocks `control-auth-post-http` |
| `D-p1-c` | `AuthFlowCoordinator.awaitCompletion` reports a settled flow as "no authorization is in flight" | R9, with `D-p1-a` | M6. A flow completing between `begin` returning and `awaitCompletion` being called turns a **successful** authorization into an `onIncomplete` warn with no `clearPending` and no re-index — the tokens are written but the tools never appear. Fix by recording the settled outcome so a late await returns it, taking care not to resume a superseded flow's continuation (B85) |

## 8. Not fixed, deliberately

- **`AuthRoutes.approve` uses `try? ManifestIO.save`** and returns 200 regardless. A4 measures it
  rather than assuming; whatever it measures is recorded. Changing the status would be a wire change
  outside this item's remit, and the reference's own `saveManifest` throws rather than returning 500.
- **`ControlDeps.currentFlow` is not populated from a coordinator.** `GET /servers` will keep omitting
  `pendingAuth` after a 200 `/auth`. Unreachable today (M4) and it belongs with `D-p1-a`.

## 9. Review — grok-4.6, adversarial, AMEND

Lane: `grok --model grok-4.6 -p` (exit 0, 11.4KB). `codex` not probed — account-limited to
2026-08-20 by the owner's standing instruction.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | CRITICAL | Every AC passed vacuously; a hardcoded 409/400/502 stub satisfied the table, and A2/A4–A7 were already green in `AuthRoutesTests` against functions the handler never calls | **Accepted.** §5 rewritten — every criterion now runs through `handle` or the socket |
| 2 | CRITICAL | The proposed 502 for non-stdio is worse than the 405 it replaces: collides with the reference's real 502, misleads the clients into retrying, and is a new divergence on `diff-http`/`diff-oauth` | **Accepted.** §4 — non-stdio stays 405 |
| 3 | HIGH | M5's "no HTTP transport at all" is false; `HTTPUpstreamTransport`/`RoutingUpstreamTransport` are in `ServicePorts.swift` | **Accepted and verified against the tree.** M5 rewritten; the scope call now rests on the OAuth client, not on a transport that exists |
| 4 | HIGH | Completion semantics under-specified, and `awaitCompletion` throws for an already-settled flow — a successful auth reported as incomplete | **Accepted and verified.** M6, A6–A9, `D-p1-c` |
| 5 | HIGH | A7/A10/A12 fight: no divergence helper fits TS-200/Swift-502, and `D-p1-a` was registered only in the spec, not on `surface.tsv` — the exact `D-g` failure the spec cites | **Accepted.** 502 dropped, `control-auth-post-http` added to `surface.tsv` as blocked |
| 6 | HIGH | `cli-auth` IS comparable after the stdio arm, because `parity-cli.sh` seeds a stdio `probe` | **Accepted and verified** (M7). Claimed only if measured green |
| 7 | HIGH | A2's proof already existed and never entered `ControlHandler`; approve's `try?` swallows a save failure; no log seam | **Accepted.** A2–A4; `log` added to `ControlDeps` |
| 8 | MEDIUM | A8 named no server, method or status, so a 405 on a listening port satisfied it | **Accepted.** A12 names all three |
| 9 | MEDIUM | `D-p1-a` had no living owner — R2 is merged, R4-C will not grow an OAuth client | **Accepted.** Owner is a new item, R9 |
| 10 | MEDIUM | A9's 404/401 inherited from the DELETE sibling; no new probes, so it was an essay | **Accepted.** A11 adds two real differential rows |
| 11 | LOW | A3's "starter never called" is a proxy; an arm that binds first and then calls `AuthRoutes` still passes | **Accepted.** A5 asserts the `FakeListener` bound nothing *and* the starter was not called |

Nothing rejected. Finding 3 and finding 6 were each checked against the tree before acceptance
rather than taken on the reviewer's word, and both held.

---

## 10. Delivered — status `Ready to merge`

Full evidence in `planning/evidence/P1-acceptance.md`. HEAD `e154db9`, rebased onto `main`
`3ee40f3`, 0 behind, tree clean.

**Gates:** `swift build` 0 · `make lint` 0 (0 violations / 438 files, **no limit raised**) ·
`make test` 0 (**1379 tests / 169 suites**) · `control-differential.sh` 0 (**53 of 53 rows**, was 49
ok + 2 known-defect failures) · `parity-manifest-check.sh` 0 (83 rows) · `p1-auth-routes.sh` 0 (13
assertions on the daemon's socket) · `parity-gate.sh` 1 by design.

**Parity, both from `.worktrees/P1`:** before **72 of 82** proven / 10 blocked / 0 diverged; after
**73 of 83** proven / 9 blocked / **1 diverged**. P1's own delta is **+2 proven, +1 denominator,
−1 blocked**; the shortfall to 74 is `install-launchd-watch`, which is nondeterministic (1 of 6 runs
agreed), sits outside this diff at file level, and is registered as `D-p1-e`.

**9 mutations** proven red then reverted. **3 grok-4.6 reviews**, all AMEND, no downgrade to log.

### Where §5's criteria stand

A1, A3, A5, A9, A10, A11, A12, A13, A14, A15 met as written. Three amended by evidence rather than
quietly dropped:

- **A2/A4** — the approve **200** path is proven Swift-side (through `handle`, with the post-write
  manifest bytes asserted) and over the daemon socket, but **not two-router compared**: the
  differential's `compare_mutating` snapshots `servers.json` while approve writes `manifest.json`,
  and no helper covers that. Recorded in the manifest row's own note so the census cannot be
  skim-read as more than it is. A4 additionally **measured** `try? ManifestIO.save` answering 200
  after a refused write rather than assuming a status.
- **A6** — proven as far as this layer can: the 200 carries the URL and the completion handler's
  side effects land. That the handler is registered *before* the 200 is built (B95) is
  `AuthRoutes`' own internal ordering and is proven in `AuthRoutesTests`; the dispatch layer cannot
  distinguish it.
- **A7/A8** — the earlier draft's "no port is bound" assertion was **removed as vacuous**: it
  allocated a listener, passed it to nothing, and asserted it had bound nothing, which is true
  against any implementation whatsoever. The claim is now structural, with `beginCount == 0` as the
  observable a binding implementation would have to break first.

### Children this item registered

`D-p1-a` · `D-p1-c` · `D-p1-d` · `D-p1-e` · `D-p1-f` · `D-p1-g`, all in
`planning/features-to-triage/D1-deferred-router.md` with mechanisms. `D-p1-b` was folded into
`D-p1-d`.

### Two things the orchestrator should decide, not me

1. **`install-launchd-watch` is marked `proven` and agrees 1 run in 6.** A proven row whose lane
   disagrees reports as DIVERGED, which is worse than blocked, and R4-C cannot reach a stable 83/83
   while it is there. Recommendation: mark it `blocked D-p1-e`. Not done here because it is another
   lane's verdict.
2. **The denominator moved 82 → 83**, so R4-C's cutover target is now **83/83**. That is deliberate:
   `control-auth-post` reading `proven` for a route half of which this router cannot serve is the
   false certainty the gate exists to prevent (`D-g`). The items that still say 82 have not been
   touched — `ORCHESTRATOR.md` is the orchestrator's to write.
