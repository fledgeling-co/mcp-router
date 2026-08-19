# P7 — `control-auth-post-http`: a real OAuth client, and the row it unblocks

`POST /servers/:name/auth` against a non-stdio upstream answered **405** where the reference
answers **200 with an authorization URL**. The row was blocked under `D-p1-a`. This document
records what was measured, what was not, and what could not be.

---

## 1. The triage's two facts, re-checked rather than inherited

| Claim | How it was checked | Result |
|---|---|---|
| The only conformer to `AuthTransport` is a test fake | `grep -rn "AuthTransport" --include="*.swift"` | True. `FakeAuthTransport` in `app/Tests/RouterCoreTests/AuthParityTests.swift:99` was the only one; `RouterServiceDispatch` passed `authFlow: nil` and `ControlAuthDispatch.authorize` returned `nil`, leaving the 405 |
| The vendored Swift SDK cannot produce the reference's byte string | read `node_modules/@modelcontextprotocol/sdk/dist/esm/client/auth.js:689` (`startAuthorization`) against the SDK's `OAuthAuthorizationCodeFlow` | True. The reference sets `response_type, client_id, code_challenge, code_challenge_method, redirect_uri`, then `state` **only if the provider implements it**, then `resource`. `FileOAuthProvider` implements no `state`, so none is emitted |

Both stand. The route needed a client written for it.

## 2. What the reference actually does, measured before any Swift was written

A scratch harness ran the reference end to end against the repo's own OAuth fixture upstream on
2026-08-19 and captured every byte. Three facts came out of it that no amount of reading would have
settled, and all three are in the shipped client:

1. **The probe changes the cascade.** The reference POSTs the MCP `initialize` request first, takes
   the 401, and reads `resource_metadata` off the `WWW-Authenticate` challenge. Protected-resource
   discovery is then **one** request at the advertised URL, not the path-aware-then-root pair.
2. **The token response and the registration response are reordered and stripped before they reach
   disk.** The SDK parses both through zod schemas that emit members in the **schema's** order and
   drop every member the schema does not name. The fixture was then changed to answer in a
   deliberately different order carrying an unknown member, and the reference's credential file came
   back in schema order with the unknown member gone. A port that wrote the provider's bytes through
   would diverge in the file that holds the user's tokens.
3. **A second authorization on an authorized server never opens a browser.** The reference tries the
   refresh grant, the fixture refuses it, no URL is produced, and the route answers **502** after
   the 20-second URL race. Both routers now do this, and it is compared.

## 3. What was built

| File | What it is |
|---|---|
| `app/Sources/RouterCore/Auth/OAuthWire.swift` | The `URLSearchParams` serializer, URL arithmetic, `checkResourceAllowed`, and the `WWW-Authenticate` field reader |
| `app/Sources/RouterCore/Auth/OAuthPKCE.swift` | A 43-character verifier over `pkce-challenge`'s own mask, and the unpadded base64url S256 challenge |
| `app/Sources/RouterCore/Auth/OAuthMetadata.swift` | The two metadata documents, and the schema reorder-and-strip for the two responses that reach disk |
| `app/Sources/RouterCore/Auth/OAuthDiscovery.swift` | RFC 9728 then RFC 8414, with the reference's fallbacks and candidate order |
| `app/Sources/RouterCore/Auth/OAuthHTTP.swift` | The request/response types and the ephemeral `URLSession` client |
| `app/Sources/RouterCore/Auth/OAuthTokenRequest.swift` | Dynamic registration, the code exchange, the refresh grant, client authentication |
| `app/Sources/RouterCore/Auth/OAuthClient.swift` | The `AuthTransport` conformer — the first outside the test target |
| `app/Sources/RouterCore/Auth/OAuthFlowStarter.swift` | The `AuthFlowStarting` conformer the daemon supplies, and the authorization-URL box |
| `scripts/acceptance/parity-oauth.sh` | The lane |
| `scripts/acceptance/p7-mutations.sh` | The mutation gate over that lane |

## 4. The lane, and what it compares

`scripts/acceptance/parity-oauth.sh` starts a fixture provider, runs the **reference** router
through one whole authorization, stops it, waits for the ports to become bindable again, and runs
the **Swift** router through the same one. 21 checks, `examined=21 failures=0`:

- seven guards per side that the comparison has something to compare (a 200, a 43-character
  challenge, a well-formed verifier on disk, a token in the credential file, a 200 from the
  callback, `"authorized":true` in the describe output, and at least six provider requests);
- the 200 and its `authorizationUrl`, PKCE challenge normalised;
- **every request the provider was sent**, in order, with headers and bodies;
- the credential file on disk;
- the page the browser lands on;
- `GET /servers/:name`'s `auth` sub-object;
- a second authorization on the now-authorized server, body and status.

### 4.1 The recorded objection is answered in the fixture, not in prose

The register entry for this row says a fixture answering every well-known path *"cannot distinguish
a correct discovery cascade from one that hardcodes an endpoint — a `proven` bought that way would
be a green row over an oracle its own author wrote."*

So the authorization server's endpoints move. `FIXTURE_OAUTH_PREFIX` puts `/authorize`, `/token` and
`/register` behind a path nothing can guess, advertised **only** in the metadata document, and the
lane sets it. Mutation 3 below is the demonstration: a client that guesses `/authorize` gets the
fixture's catch-all 401 and the lane goes red.

The same objection applied to the credential file, so the fixture's registration and token responses
answer in a scrambled member order carrying an unknown member.

### 4.2 What is NOT compared, stated rather than implied

- **The MCP `initialize` body of the probe.** That is the MCP handshake and the `mcp` rows own it.
  The fixture refuses every request to `/mcp` whatever it says, so it changes nothing downstream.
  The lane compares that the probe was **made**, its method, path and headers — not its body.
- **Everything after the token exchange.** Authorizing triggers a re-index, the fixture refuses that
  too, and the reference's SDK then retries the refresh grant a number of times it does not make
  deterministic. The provider-log comparison is therefore of the **prefix ending at the token
  request**, and the truncation is asserted (`truncate_log` exits 3 if no token request is present,
  which the lane turns into a failure or an environment failure depending on which side it was).
- **One observed difference outside this row, recorded rather than folded in.** After authorization,
  `GET /servers/fx` differs: the reference reports `indexError: ""` and no placard, and Swift reports
  `indexError: "[-32603] Internal error: Authentication required"` and a placard carrying the same
  text. That is the re-index of an upstream the fixture refuses, it is the pool's surface rather than
  this route's, and it predates this item. The lane compares the `auth` sub-object only, and says so.

### 4.3 A pinned constant that will move

`OAuthDiscovery.protocolVersion` is `2025-11-25`, the reference SDK's `LATEST_PROTOCOL_VERSION`, and
it is sent as `MCP-Protocol-Version` on every metadata request — so it is compared. A minor bump in
`node_modules` moves the reference and reddens this lane. That is the intended failure: the lane
prints what each side sent, and the fix is one line.

## 5. Two defects found on the way, neither visible to a build or a green suite

**The authorization-URL box could not be resumed by cancellation.** `AuthFlowCoordinator` races the
URL against a 20-second sleep inside a `withThrowingTaskGroup`. When the sleep wins, the group
cancels the remaining child and then **awaits** it — and a `CheckedContinuation` that cancellation
cannot resume is never resumed. Measured on the second-authorization branch: the control request was
still open at **91 seconds** against a route whose own budget is 20, and it would never have
returned. Every path where the provider produces no URL runs through that: an unreachable
authorization server, a refused registration, and the refresh branch. `AuthorizationURLBoxTests`
carries the reproduction, and it fails against the first version.

**`p1-auth-routes.sh` bound the developer's real `:8880`.** The script's http upstream became a live
flow the moment the route started working, and the callback port is fixed. It now pins a scratch
port, and its `405` assertion is replaced by the 502 both routers answer for an unreachable
provider.

## 6. Mutation proof — the lane can go red

`scripts/acceptance/p7-mutations.sh`. Each mutation is one exact-string edit to production source,
asserted to have matched; the tree is rebuilt, the lane is run **5 times**, and the tree is restored.
A mutation that reddens the lane four times in five is a failure here, not a pass — that is the
shape of the defect that withdrew `install-launchd-watch` under `D-p1-e`.

The gate runs the **unmutated** lane first and refuses to proceed unless it is green, so a mutation
cannot be credited to a lane that was broken all along.

| # | What it breaks | Trials red | What went red |
|---|---|---|---|
| 1 | `code_challenge` and `code_challenge_method` are not sent | **5 of 5** | the URL differs, and the fixture's authorization endpoint refuses a request with no challenge, so no code is ever issued |
| 2 | a `state` parameter is emitted — exactly what the vendored Swift SDK does unconditionally, and the recorded reason it cannot serve this route | **5 of 5** | one extra parameter in the URL |
| 3 | the authorization endpoint is guessed at `/authorize` instead of read from the metadata document | **5 of 5** | the provider's endpoints are behind an unguessable prefix, so the guess hits the catch-all 401 |
| 4 | dynamic client registration is skipped and a `client_id` is invented | **5 of 5** | the registration request disappears from the provider's log, and the `client_id` differs in the URL and the token request |
| 5 | the token request carries no `code_verifier` | **5 of 5** | the provider's PKCE check refuses the exchange, so no credential file is written |
| 6 | the callback listener binds a port the redirect URI does not name | **5 of 5** | everything up to the browser hop is correct; only a lane that follows the redirect through to the router's own socket sees this |

**examined=6 mutations × 5 trials = 30 lane runs, 30 red, 0 not red.**

Two things about that run rather than only its number.

**Mutation 5 did not apply on the first pass, and the gate called that a failure rather than
crediting it.** Its snippet had been written before the token request took a `CodeExchange` value,
so the exact-string edit matched nothing. The assertion inside `mutate` caught it
(*"the mutation matched nothing, so it is not breaking what it names"*), the gate reported
`FAIL … (unapplied)` and exited 1. The snippet was then **re-aimed at what the code says now**
rather than swapped for an easier one, and `P7_MUTATION_ONLY` was added so it could be re-proved
without re-running the five that held. Its re-run observed its own green baseline first.

**The five earlier mutations were run against a 19-check lane and the sixth against a 21-check
one**, because the `describe` guard was added between them. That does not weaken them: a guard is
an additional failure condition, so it can turn a green lane red and can never turn a red lane
green. The trials that were red stay red.


## 7. Gates

All run in this worktree, with `node_modules` and `dist` symlinked to the main checkout (the
repo's `.gitignore` already anticipates the first; the second was added in the same shape).

| Gate | Result |
|---|---|
| `make lint` | **0 violations / 471 files**; `no-raw-design-values` clean; `no-wire-codable` clean over Control, Registry, Usage and Auth, 2 exemptions recorded |
| `make test` | **1490 tests / 184 suites**, 0 failures. `main` is 1467/178, so this adds 23 |
| `make parity` | 358 vector cases compared, floor 358 |
| `make build-mac` | `** BUILD SUCCEEDED **` |
| `scripts/acceptance/parity-oauth.sh` | **21 checks passed, 0 failed** — `examined=21 failures=0` |
| `scripts/acceptance/p7-mutations.sh` | **6 mutations × 5 trials = 30 lane runs, 30 red** |
| `scripts/acceptance/p1-auth-routes.sh` | 13 passed, 0 failed |
| `scripts/acceptance/parity-manifest-check.sh` | 83 rows, consistent with source, exit 0 |
| `scripts/acceptance/parity-manifest-selftest.sh` | 36 behaved, 0 did not |
| `scripts/acceptance/parity-lock-selftest.sh` | 12 held, 0 did not |
| `scripts/acceptance/parity-normalise-selftest.sh` | 14 behaved, 0 did not |
| `scripts/acceptance/parity-lane-selftest.sh` | exit 0, every seeded lane went red, failability **16 of 19** — unchanged, and the roll-up now names where this row's failability is proved instead |
| `scripts/acceptance/parity-gate.sh` | **80 of 83 proven, 3 blocked, 0 DIVERGED.** Exits 1 by design while any row is blocked |

### The gate's own count moved with the row

**79 → 80 of 83.** The `oauth` lane appears as lane 13 of 13 and records one row; the `fixture`
lane still reports **23 match the live reference, 0 drifted**, which is the check that would have
caught the fixture-server change moving a captured byte.

Two rows now stand between 80 and the owner's target of 82, and neither is this item's:

    install     install-launchd-watch    D-p1-e   (P8)
    install     install-rollback         R4-C

The third blocked row is `fixture-registry-search`, the standing exclusion.

### One false notice fixed on the way

The gate printed *"the TypeScript reference is not built, so every lane that compares against it
will report an environment failure"* — and then all thirteen lanes ran and every one reached the
reference. `MCP_ROUTER_DIST` names the **directory** everywhere else in the harness, and the notice
tested it as a file, so it fired on every run that set the variable. The branch it lives in
contains nothing but `echo`, so the fix cannot reach any coverage arithmetic.


## 8. What could not be measured here, and why

- **`parity-manifest-selftest.sh`** — `environment: the MCP SDK is not installed. Run npm install.`
  A git worktree has no `node_modules`; the check reads the MCP method names from the SDK. Run it
  from the main checkout at merge. Inconclusive, not passing.
- **`make test-ios`** — not run. This item changed no iOS source, and `X1` records the iOS harness
  as red on `main` for reasons of its own (19 cases of the shape *rendered nothing*, an accessibility
  tree published a turn later than the fixed 50 ms pass). Running it here would measure `X1`.
- **`make acceptance`'s Mac scripts** — not run. No Mac surface changed. `p1-auth-routes.sh` was
  changed and IS run above.
