# plan-R5: Swift router — OAuth and the authorization routes

**Spec:** `planning/specs/spec-R5.md` · **Plan size: Standard** · **Branch:** `ai/r5` · **Base:** `main` @ `7fa55c7`

Every clause the spec pins (B60–B66 inherited, B77–B100 added) is placed against a file and a test
here. Where R1 already ports something, this plan **consumes** it and says so.

---

## What already exists and is not rebuilt

Measured on `main`, not assumed:

| From R1 | Used here for |
|---|---|
| `JSString` (`[UInt16]`, code-unit equality/ordering) | every name key — B80 |
| `JSONValue` / `JSONMember` (ordered) | every response body and both on-disk formats — B87, B89, B91 |
| `JSStringify.compact` / `.prettyTwoSpace` | response bytes / record + manifest bytes |
| `JSONParser` | request bodies and on-disk JSON |
| `Manifest`, `CachedServer` (`members: [JSONMember]`, ordered), `ManifestIO.load/.save` | `/approve` — B78, B88, B89 |
| `FileSystem`, `RouterClock`, `JSDate.iso8601` | every side effect, injectable |
| `RouterLog`, `LogEvent` (closed enum) | B66, B94, B100 |

**Nothing here may reach for `JSONSerialization`, `JSONEncoder`, `Codable` or a Swift `Dictionary`
on a path that reaches the wire or a file.** That is how a delegated slice silently defeats the
byte contract.

### The one shared file this item touches

`Log/RouterLog.swift` — `LogEvent` is a **closed enum**, and B66 requires the no-secret guarantee to
be *type-level* rather than a convention. Auth cases must therefore be added to it. Verified safe:
`ai/r3` has **not** modified `LogEvent` (`diff` of the case list against `main` is empty), so this is
additive with no merge conflict against the in-flight sibling. No other R1 file is edited — in
particular `Manifest.entry(named:)` takes a Swift `String`, and rather than add a `JSString`
overload to R1's file, the auth code does its lookup over `Manifest.serverEntries`, which already
yields `JSString` keys.

---

## P1 · The record and the store

```
app/Sources/RouterCore/Auth/
  AuthPaths.swift        callback port + redirect URI, resolved ONCE; recordPath(for:)
  AuthRecord.swift       ordered members, merge-preserving write, 2-space pretty
  FileAuthStore.swift    hasTokens / authorizedAt / clear / save — JSString keyed
```

| Rule | Specification | Clause |
|---|---|---|
| record path | `<AUTH_DIR>/<server>.json`, the server's UTF-16 code units encoded to UTF-8 without normalization | B60, B80 |
| modes | directory `0700`, file `0600`, both set **at creation**, asserted by reading them back | B60 |
| `hasTokens` | false when the record has no `tokens.access_token`, including when `tokens` is absent entirely | B60 |
| unreadable record | emit the warn **verbatim** — `auth record for "<server>" unreadable (<reason>); treating as unauthorized` — and read unauthorized. Never `try?`-to-default | B61, B100 |
| `clear` | reports whether a record existed, by `fileExists` **before** removal | B62 |
| `authorizedAt` | the member verbatim, or nil | B97 |
| file bytes | `JSStringify.prettyTwoSpace`; writers merge over the existing members so key order is read-order-then-append, never a fresh literal order | B91 |
| key type | `JSString` throughout. `FileAuthStore` holds no Swift-`String`-keyed dictionary | B80 |

`AuthPaths` resolves the port from `MCP_ROUTER_AUTH_PORT` **once**, at type initialization, and
derives the redirect URI from it — a later environment mutation must not change either (B90). Test
proves the second read is unchanged after mutating the environment.

**B80's test is key-level only.** A filesystem round-trip is forbidden as evidence: default APFS
compares filenames normalisation-insensitively, so U+00E9 and U+0065 U+0301 resolve to one file for
*both* routers and the test would prove nothing about the port. The assertion is that a `JSString`
-keyed store holds two distinct entries and resolves neither from the other.

## P2 · The client metadata

```
  OAuthClientMetadata.swift   the dynamic-registration body, as ordered JSONValue
```

Six members, in this order, byte-asserted (B87): `client_name` = `mcp-router (<server>)`,
`client_uri` = `https://mcp-router.fledgeling.app`, `redirect_uris` = `[<redirect URI>]`,
`grant_types` = `["authorization_code","refresh_token"]`, `response_types` = `["code"]`,
`token_endpoint_auth_method` = `"none"`. Built as `[JSONMember]`, never a Swift dictionary.

## P3 · The flow and its terminations

```
  AuthTransport.swift     protocol: connect() / finishAuth(code:) / close()  + a test double
  AuthFlow.swift          beginAuth, currentFlow, cancel, cleanup, the timers
  CallbackListener.swift  the fixed-port loopback listener and PAGE
```

The transport stays a **parameter** (`makeTransport:`), exactly as the reference has it, so R2's
SDK-backed transport lands without editing this module. R5 ships the protocol and a double.

**The termination table — this is the contract:**

| # | Trigger | Response | Settles | Cleans up | Clause |
|---|---|---|---|---|---|
| 1 | code, exchange succeeds | 200 page `<server> is connected` | resolve | yes | B65 |
| 2 | `error` param present | 400 page, detail = the param **verbatim** | reject(error) | yes | B65 |
| 3 | no code, no error | 400 page, detail `the provider returned no code`; rejection carries the **different** string `no authorization code returned` | reject | yes | B65, B86 |
| 4 | `finishAuth` throws | 500 page, detail = the thrown message | reject(err) | yes (in `finally`) | B65 |
| 5 | 300 000 ms elapses | **no response is ever written** | reject(`authorization timed out`) | yes | B65, B99 |
| — | path ≠ `/callback` | 404, **zero-length** body, no `content-type` | **no** | **no** | B82 |
| — | superseded by a second flow | — | **never settles** | yes | B85 |
| — | `listen` fails (EADDRINUSE) | surfaces as B77's 502 | reject | **no** — timer armed, transport unclosed | B84 |
| — | 20 000 ms with no URL | surfaces as B77's 502, `the server never produced an authorization URL` | reject | yes | B84 |

Two rows carry the findings that would otherwise have shipped wrong:

- **B85.** `beginAuth` opens with `current?.close()`, and `close` is `cleanup`, which never calls
  `settle`. The superseded flow's completion therefore *never resolves or rejects* — its side-effect
  and its warn never run. A Swift port that cancels the prior task with an error emits a spurious
  `did not complete: cancelled` and diverges. Implemented as: supersession runs cleanup and leaves
  the continuation un-resumed. Proven by a bounded wait asserting silence.
- **B96.** `cleanup`'s last step is guarded — `if current?.flow.server == serverName`. An
  unconditional clear lets a superseded flow's late callback null the flow that replaced it.

`PAGE(title, detail)` renders `title` into **both** `<title>` and `<h1>`; both 400s and the 500 pass
the literal `Authorization failed` (B99). The emitted bytes are pinned against the five files under
`design/mocks/auth-pages/`, which were generated from the reference's own template literal.

**B66 is type-level.** `LogEvent` gains only these cases, and none of them can carry a token, a
header or a record — the enum's associated values are server names, counts and reasons:
`upstreamAuthorized(server:)`, `authorizationIncomplete(server:reason:)`,
`authRecordUnreadable(server:reason:)`, `toolSurfaceApproved(server:toolCount:)`. A log-capture test
drives a whole flow carrying a token and asserts the token's bytes appear nowhere in the sink.

## P4 · The two routes

```
  AuthRoutes.swift    authStart, approve — each -> (status: Int, body: JSONValue)
```

Value-layer functions over R1 types only. **No `ControlResponse`, no `ControlRequest`, no
`AuthStore` protocol** — those are R3's symbols and declaring them here would collide at merge
(spec §1). R3's dispatch wires each in two lines.

| Route | Outcomes | Clause |
|---|---|---|
| `POST …/auth` | 400 `{error:"stdio servers do not authorize; their credentials are env vars"}` when `u.transport == "stdio"`, **before** any port is bound; else 200 `{server, authorizationUrl}`; 502 `{error:<thrown message>}` | B77, B84 |
| ~~`DELETE …/auth`~~ | **Out of scope.** Already shipped on `ai/r3`; R5 does not reimplement it | B92 |
| `POST …/approve` | 409 `{error:"no pending change for \"<name>\""}` when the entry has no `pending`; else 200 `{server, approved:<count>}` | B78 |

**B83 — the precondition neither route owns.** Both sit behind
`/^\/servers\/([^/]+)(\/[a-z]+)?$/` and `upstreams.get(name)`, which answers 404
`{error:"no server named \"<name>\""}` first. R5's functions take an **already-resolved upstream**,
so the 404 cannot be their responsibility — and the test asserts that calling with an unknown name
is impossible by type, with the 404 itself proven in R3's dispatch tests after wiring.

**B78's write, precisely (B89).** `/approve` reads the manifest **fresh from disk**
(`ManifestIO.load`), where `/changes` uses the cached one. `approved` is `pending.tools.count`
**counted before the write**. The new entry updates `tools`, `digest` and `builtAt` **in place** at
their existing member positions and appends only genuinely-new keys, and **removes** `pending`
rather than emitting it as null — `CachedServer.members` being an ordered `[JSONMember]` is what
makes this expressible. A corrupt manifest degrades to empty, so approve answers 409, never a throw
(B88).

**B95 — the side-effect channel.** `authStart` cannot express B79 through its return value: the
completion continuation outlives the response. It therefore takes an injected
`AuthCompletionSink` parameter and registers the continuation on it. The order is `clearPending`
then re-index; a rejection from **either** the flow or the re-index produces the same warn,
`authorization for "<name>" did not complete: <message>` (B79). The continuation is registered
**before** the 200 is constructed, matching `control.ts:399-405` — a port that assumes the response
is already sent sequences wrongly where the flow can complete first.

## P5 · Vectors and the gates

New vector files under `Tests/RouterCoreTests/Vectors/`: `auth-record.json`, `auth-pages.json`,
`auth-routes.json`, `approve.json`, `client-metadata.json`. Each is registered in `VectorRegistry`
with a `compare` closure that **returns how many cases it actually compared**, which is the existing
mechanism that stops a decoded-but-unchecked vector from passing.

**B81.** `VectorRegistryTests.executedFloor` rises from `main`'s 224 to this branch's new total, and
a **second** assertion names the auth subtotal separately — the gate found that a bare floor is
satisfied by any 40 unrelated vectors, so a count alone is not evidence. The floor is not the goal:
the corpus already stands at **352 executed cases on `ai/r3`**, so the brief's "must exceed 224" is
stale. Auth vectors exist because auth needs vectors. Whichever of R3/R5 merges second raises the
floor to the combined total, and that raise is part of the merge, not of this item.

Gates, all actually executed: `swift build`, `swift test`, `swiftformat --lint`, `swiftlint`, and
the repo's `make parity` which reads `PARITY-VECTORS-EXECUTED:`.

---

## P6 · Revisions forced by the plan-review gate

The substitute out-of-family gate (§ below) returned **35 findings**. These are the ones that change
the build, recorded here because a plan that quietly absorbs them teaches the next reader nothing.

### Swift 6 makes the reference's shape illegal — three decisions

| Finding | The problem | The decision |
|---|---|---|
| #13 | The reference's `let current` is module-level mutable state (`auth.ts:150`), read-modify-written by `beginAuth`, `cleanup` and `cancel`. A file-scope `var` does not compile under `.swiftLanguageMode(.v6)` | `AuthFlowRegistry` is an **actor**. `currentFlow()` becomes `async`. Every call site in P4 already `await`s, so this costs nothing there — it is recorded because it changes the signature R2 and R3 will call |
| #14 | B85 requires a superseded flow to **never settle**, and the spec forbids the escape of cancelling with an error. A `CheckedContinuation` that is never resumed is `SWIFT TASK CONTINUATION MISUSE`; an unsafe one leaks silently | **The completion is not a continuation.** It is a registered sink (B95's `AuthCompletionSink`) held by the flow. Supersession *detaches* the sink and invokes nothing — which is exactly what the reference's dangling promise does — with no continuation to misuse. `completed` is never modelled as an awaitable |
| #15, #16, #35 | `RouterLog` is an `actor`, so B94's log line sits at a suspension point inside a path the reference runs synchronously in a `finally`; `timer.unref()` has no Swift equivalent; `void transport.close().catch(…)` is fire-and-forget and must **not** become `try await` | Cleanup is an `async` function that emits its log **before** detaching, awaits nothing it need not, and closes the transport in a detached task whose failure is discarded — matching the reference's swallow |

### The vector plan was wrong; P5 is replaced

Findings #26–#28, each verified against the repo:

- **#27 is decisive.** `make parity` (Makefile:118-131) greps `PARITY-VECTORS-EXECUTED: [0-9]+`,
  takes **`tail -1`**, and compares *that* to `executedFloor`. A second marker under the same prefix
  would be read as the total and fail the gate; under a different prefix nothing reads it. **P5's
  "second printed assertion" is withdrawn.** One marker, as today.
- **#28.** The claim that the harness already prevents a decoded-but-unchecked vector is false:
  18 consumers in `VectorRegistryFiles.swift` end `return cases.count` while `continue`-ing past
  cases they never compare. R5's own consumers therefore **increment a counter per case actually
  compared** and return that, rather than `cases.count`.
- **#26.** Auth coverage is proven by the registry's real anti-shrink machinery — the id-level
  `namedVectors`, `clauseVectors` and `pinnedInputs` tables — with the coverage test's hardcoded
  `N1…N13`/`D1…D5` loop extended to the auth clause ids. `executedFloor` rises to the new total.

### Clauses the plan had specified but not placed — now placed

**B63** and **B64** appeared nowhere in the plan (#18, #19). B64's `cancel()` is a **distinct
termination** — `settle(new Error('cancelled'))` then `cleanup()` (`auth.ts:271-274`) — and is added
as a tenth row of P3's table, settling where supersession does not. B63's three branches get their
own fixture test rather than being covered incidentally by B77.

P1 gains the rest of `FileOAuthProvider` (#20–#22): `clientInformation()`, `saveClientInformation`,
`tokens()`, `saveCodeVerifier`, `codeVerifier()` **with its throw** `no PKCE code verifier saved for
"<server>"`, and the `authorizedAt` **write** that `saveTokens` performs from the injected clock.

### Byte-divergence corrections

- **#33.** `{...entry, …, pending: undefined}` drops **every** member whose value is `undefined`, not
  only `pending`. An absent `pending.digest` omits `digest` from the written entry entirely. The
  write is specified as: drop any member whose source is absent; never substitute `.null`.
- **#34, recorded not fixed.** `entry.pending.tools.length` raises a `TypeError` in the reference
  when `pending.tools` is absent, where R1's `CachedServer.pendingTools` returns `[]` by deliberate
  design (`Manifest.swift:43-45`). Swift answers `200 {approved:0}` where the reference crashes.
  This is an **inherited R1 divergence**, not one R5 introduces; it is written into B78's notes so
  R4 sees it declared rather than discovering it.
- **#23.** Page responses set `content-type: text/html` and **no** `content-length`; the 404 sets
  neither and sends no body. Header assertions join the body assertions.

### Findings accepted as scope escalations, not built here

**#29** — B66's "type-level" guarantee is weaker than claimed: `authorizationIncomplete(reason:)`
carries a free `String` sourced from a thrown error, which on B86's path is the provider's raw
`error` query parameter. A token embedded in a provider error string would be logged, and the
planned test (which injects the token *as a token*) passes anyway. The test is strengthened to inject
a token-shaped string **inside a provider error**; the deeper fix — a redacting reason type — is
escalated, because it changes R1's `LogEvent` contract that R3 also depends on.

**#30, #31** — B90's and B80's tests prove the wrong component. B90 is re-specified to assert
resolution happens at **type initialization** by observing a mutation made *before* first access is
honoured and one made *after* is not, with the env mutation isolated to a serialized test. B80's
assertion moves onto `recordPath` — the one place the distinction reaches a filename — rather than
onto `JSString: Hashable`, which is R1's code, not R5's.

**#24** — `decodeURIComponent`'s `URIError` on a malformed percent sequence belongs to R3's
dispatch, which is out of scope here; escalated to the wiring item rather than silently unowned.


P1 → P2 → P3 → P4 → P5. P1 and P2 are file-disjoint and independent; P3 depends on P1; P4 depends on
P1 and P3; P5 depends on all. The `LogEvent` edit lands in P1 so every later phase compiles against
the final enum.

## P7 · The listener the double stood in for

P3 named `CallbackListener.swift` and the first pass did not write it: `CallbackListening` shipped as
a protocol plus a test double, so all five terminations, the non-termination and both pre-flow
failures were proven against something that binds no port. Delivered now as
`app/Sources/RouterCore/Auth/CallbackListener.swift` — `LoopbackCallbackListener`, an `NWListener` on
IPv4 loopback, no new dependency. The request semantics stay in `CallbackResponder`; this type reads
a request target off the wire, hands it to the flow's handler and writes back the `CallbackReply`.

Three properties are load-bearing, and each has its own assertion:

| Property | Why it is not incidental |
|---|---|
| the bind is pinned to `127.0.0.1` through `requiredLocalEndpoint` | `NWListener(using:on:)` binds **every** interface, which would put the callback — and the unescaped page it renders from a provider-supplied `error`, spec §6 — on the LAN |
| a bind failure **throws**, in the reference's own message shape | B84's first pre-flow failure. `.waiting` counts as a failure too: a fixed loopback port has no legitimate transient wait, and `NWListener` would otherwise retry in the background while `start` hangs |
| `stop()` leaves in-flight connections alone | the reference's `cleanup` calls `callback.close()`, which stops accepting and lets an open response finish. The flow settles *inside* the handler, so cancelling connections there would mean the browser never receives the page it just earned |

`stop()` also **keeps the handler**, for the same reason one layer down: a connection accepted before
the stop can still send its request afterwards, and `server.close()` hands that request to the
handler as usual. Dropping it would be a divergence on a path a slow browser reaches. It cannot
exchange a code twice — `AuthFlowCoordinator.exchange` refuses any request that is not for the flow
in flight, so a late one renders the 500 it earns.

**The defect a double could not have found.** `stop()` first returned as soon as it had asked
`NWListener` to cancel. Cancellation is asynchronous, and supersession rebinds the **fixed** port
immediately after cleanup — so the second authorization failed with `EADDRINUSE` roughly half the
time, leaving the user with a browser tab that could never land. `stop()` now waits for the socket,
bounded by a 2 s deadline so a listener that never reports `.cancelled` ends the flow rather than
hanging it. Every termination path runs cleanup, so an unbounded wait there would hang all five.

**Declared framing divergence, for R4.** The reference sets `content-type` and leaves Node to frame
the page with `Transfer-Encoding: chunked` and keep the connection alive; this sends `content-length`
and `connection: close`. Both are valid HTTP/1.1 and a browser renders them identically. The
application-visible contract — status, `content-type`, body — is byte-identical, which is what B65
through B99 are written against. Closing is the honest framing for a listener that is torn down the
moment the flow settles. Recorded here so R4's differential gate sees it declared rather than
discovers it.

**The wiring, for R3 and R2.** `AuthRoutes.authStart` takes `begin:` as a closure, so the dispatch
supplies the listener rather than this module doing it:

```swift
try await coordinator.begin(
    server: name, listener: LoopbackCallbackListener(), transport: <R2's SDK transport>,
    port: AuthPaths.bindablePort, authorizationURL: { … }
)
```

One instance per flow — `start` refuses a second bind on the same instance.

**One rebase collision, resolved toward main.** R2 merged its own `FakeTransport` (an
`UpstreamTransporting` for the pool) into `RouterCoreTests`. R5's auth double renamed to
`FakeAuthTransport`. Worth knowing that `swift build` does **not** build the test target, so this
surfaced only at `make test` — a build-only gate after a rebase proves less than it appears to.

## Out of scope, restated so a slice cannot drift into it

The two `case` lines in R3's `ControlHandler` dispatch; the Mac and iPhone auth surfaces (M8, I1); a
live SDK transport (R2); restyling the callback pages to DESIGN.md, escaping `PAGE`, or validating
the `state` nonce — all three are parity-coupled and escalated in spec §8, not done here.
