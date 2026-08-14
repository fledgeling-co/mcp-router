# spec-R2R — Router: the process that actually serves

**Status:** Ready for Work · **Category:** router · **Depends on:** R2 ✓ R3 ✓ R5 ✓ (merged)
**Blocks:** R4's cutover · **Brief:** `planning/features-to-triage/R2R-router-daemon.md`

Out-of-family gate: **codex is account-limited until 2026-08-20 and exits 0 on that limit**, so the
spec review ran in-family — a fresh adversarial `claude -p` opus-5 reviewer briefed to refute, and
told that finding nothing is a failed review. Recorded so the weakness travels with the evidence:
`codex: usage limit -> claude (downgrade)`.

**Revision 3.** Revision 1 was REJECTED with 3 blockers, 5 majors and 3 minors. Revision 2 was REJECTED
again with 3 blockers, 7 majors and 3 minors. §10 maps the first review, §12 the second. The three
that changed the shape of the item: fixing `D-j` would have forced an edit to
`control-differential.sh` (dropped); revision 1 left 12 of its 19 rows with no stated oracle (§9 now
names one per row); and revision 2's lane guards were prose rather than mechanism (there is now a
`parity-lane-selftest.sh` that seeds a defect per lane and requires the lane to go red).

---

## 1 · What this is

R2 delivered the pool, the process supervision and the passthrough value layer, and deferred the
process that uses them. `RouterCore` is a library: the only `NWListener` in it is R5's single-shot
OAuth callback, `Package.swift` declares three libraries and two one-shot oracles, and
`docs/install.sh` writes launchd agents running `node dist/index.js serve`. **There is no Swift
router process.**

That is why R4's parity gate refuses the cutover: five lanes — `mcp`, `cli`, `install`, `state`,
`log` — are blocked for a structural reason rather than for want of effort.

This item builds the thing that runs: a composition root, an HTTP listener, the MCP relay, the HTTP
upstream clients R2 deferred, the CLI verbs, and the lifecycle a launchd agent needs.

**The cutover stays out of scope.** Flipping the installer's default and deleting `src/*.ts` is
R4's, behind its gate and behind a decision the user takes.

## 2 · Acceptance, and the number

`scripts/acceptance/parity-gate.sh` is the acceptance test. It is merged, adversarially reviewed
three times, and **is not to be edited to make it pass**.

### 2.1 The baseline is re-measured, not quoted

The brief says 50 of 81 and carries no date, in an item that timestamps every other observation. So
it was re-run on this worktree with every change of this item's held out of the tree, on
**2026-08-14**:

```
control     11 of 15 proven, 4 blocked      mcp      0 of 5 blocked
fixture     23 of 24 proven, 1 blocked      cli      0 of 10 blocked
divergence  12 of 14 proven (4 by suite),   install  0 of 5 blocked
            2 blocked                       state    0 of 1 blocked
pool         4 of  6 proven, 2 blocked      log      0 of 1 blocked

parity: 50 of 81 rows proven (4 of them by suite only, not by wire comparison), 31 blocked.
exit=1
```

**The brief's number is confirmed: `P` = 50.**

One thing that run taught, and which the evidence file records because it will bite the next runner:
a first attempt reported **43 of 81 with 7 DIVERGED**, and every one of the seven was a
`proven-by-suite` row whose cited Swift test "failed". None had. The tree contained a
work-in-progress source file that did not compile, so `swift test` never built, and the suite lane
reported every citation it could not run as a failure. **A parity number measured over a tree that
does not compile is not a parity number.** Both the gate run that opens this item and the one that
closes it are taken with `swift build` green first, and the evidence file states so.


### 2.2 The rows this item owns

18 rows, not 19. `cli-auth` is removed from the budget by §8 A1.

| group | rows | ids |
|---|---|---|
| `mcp` | 5 | `mcp-endpoint`, `mcp-tools-list`, `mcp-tools-call`, `mcp-health`, `mcp-status` |
| `cli` | 8 | `cli-serve`, `cli-import`, `cli-index`, `cli-refresh`, `cli-status`, `cli-tools`, `cli-usage`, `cli-help` |
| `pool` | 2 | `pool-p4`, `pool-reap-traffic` |
| `install` | 1 | `install-launchd-serve` |
| `state` | 1 | `state-ondisk-compat` |
| `log` | 1 | `log-bytes` |

One row is **added**: `div-r2r-d8`, §7's declared divergence. So the target arithmetic, stated once:

> baseline `P` of 81 → **`P + 18 + 1` of 82**, if every owned row and the new divergence row proves.
> At the brief's `P = 50` that is **69 of 82**. Coverage moves 61.7% → 84.1%; without the added
> divergence row it would be 68 of 81, 84.0%. The added row is worth 0.1 points and is declared
> because §7 needs it, not because it moves the number.

The **13** rows this item leaves blocked belong to `D-j` (2), `D-k` (3), `D-l` (1), `D-m` (2),
`R2-R` (1 — `cli-auth`), `R2-W` (3) and `R4-C` (1). None of the capabilities behind them is built.
82 − 69 = 13, which is the cross-check revision 2 got wrong by writing 12.

### 2.3 What may change in the gate, and what may not

A row moves from `blocked` to `proven` only when the product gains the capability **and** a lane
records `ok` for it. A flipped verdict alone proves nothing: `parity-gate.sh:161` counts a `proven`
row no lane spoke for as **blocked**, and `parity-manifest-check.sh:60-62` additionally rejects a
non-blocked row that still carries an owner, so a half-flip fails the manifest check outright.

Changed in `parity-gate.sh`: **the `LANES` default on line 32, and nothing else.** That line is one
R4 anticipated — `parity-gate.sh:201` already prints coverage in the order
`control fixture divergence pool mcp cli install state log`, for five groups that had no lanes, and
`:73-78` already records a named-but-missing lane as an environment failure.

Not changed: any other line of `parity-gate.sh`, any line of `parity-manifest-check.sh`, and — the
blocker revision 1 missed — **any line of `control-differential.sh`, `parity-control.sh`,
`parity-fixture.sh`, `parity-divergence.sh`, `parity-pool.sh` or `parity-suite.sh`.** The
completion note carries `git diff` for all eight files, and seven of them must be empty.

### 2.4 The new lanes are gate surface, and are treated as such

Five scripts are added: `parity-mcp.sh`, `parity-cli.sh`, `parity-install.sh`, `parity-state.sh`,
`parity-log.sh`. Revision 1 presented them as product. They are not — a lane that stays green while
the product is broken is undetectable by anything else in this design. So each carries, and the
evidence file records the command and result for each:

1. **An explicit owned set.** Each lane declares the `(group, id)` **pairs** it may speak for, and
   `record()` refuses anything else. Revision 2 asserted only that the pair exists in `surface.tsv`,
   which every pair in `surface.tsv` does — that catches a typo, not authorship, and authorship is
   the exposure `parity-gate.sh:157-159` names. An owned set also handles a lane that legitimately
   writes more than one group: the mcp lane owns `pool` and `divergence` rows as well as its own,
   exactly as `parity-pool.sh` writes a `divergence` row through a second helper.
2. **A negative control with a mechanism.** `scripts/acceptance/parity-lane-selftest.sh` seeds a
   defect per lane, runs the lane, and exits non-zero if any lane stays green. Revision 2 promised
   this as a paragraph in an evidence file, which is re-run by nothing. The defect is injected
   through a shim on `$SWIFT_BIN`, never a hook in the router — a test-only branch inside the
   product is a branch that can ship.
3. **Its own caveat line, printed by the lane.** `parity-gate.sh:101` echoes each lane's log into
   the report, so a lane whose claim is weaker than a simultaneous byte diff says so there — the
   gate's own caveat block at `:214-217` names only the three older lanes and is not edited.
4. **A port that is refused if taken**, as `parity-pool.sh:64-68` does.

## 3 · The reference, measured

Every clause below was observed against `node dist/index.js` on 2026-08-14, not inferred from
`src/*.ts`. **Ports:** the probe that produced §3 used **8991**; the lanes use **8992–8999**;
`8879` is the reference's own default and appears only inside copy. 8975 and 8976 carry the user's
live sessions, were never contacted, and `lsof` confirmed 8975 still held by pid 11356 after the
probe run.

### 3.1 `/mcp` framing — the finding that shapes the endpoint

A POST is **not** answered with JSON. The reference answers with Server-Sent Events:

```
HTTP/1.1 200 OK
cache-control: no-cache, no-transform
connection: keep-alive
content-type: text/event-stream
x-accel-buffering: no
Transfer-Encoding: chunked

event: message
data: {"result":{…},"jsonrpc":"2.0","id":1}

```

Consequences:

- The SDK's `StatelessHTTPServerTransport` returns `.data(_, content-type: application/json)`. Using
  it as-is would diverge on the framing of every MCP response.
- The envelope member order is `result, jsonrpc, id`, and `jsonrpc, id, error` on the error path.
  Neither the Swift SDK's `Codable` encoder nor `JSONSerialization` produces that order by accident.

Both are why §4.3 serves `/mcp` over **R1's JSON value layer**. `MCP` stays a dependency for the
*client* half — upstream transports — which is what it is pinned for.

### 3.2 The measured corpus

| request | status | body / framing |
|---|---|---|
| `initialize` | 200 SSE | `{"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"mcp-router","version":"0.1.0"}},"jsonrpc":"2.0","id":1}` |
| `notifications/initialized` | **202** | no body |
| `ping` | 200 SSE | `{"result":{},"jsonrpc":"2.0","id":2}` |
| unknown method | 200 SSE | `{"jsonrpc":"2.0","id":3,"error":{"code":-32601,"message":"Method not found"}}` |
| `tools/list` | 200 SSE | `{"result":{"tools":[…]},"jsonrpc":"2.0","id":N}`, namespaced `server__tool`, description prefixed `[server] ` |
| `tools/call` ok | 200 SSE | upstream result passed through |
| `tools/call` un-namespaced | 200 SSE | `isError:true`, `Tool "bare" is not namespaced <server>__<tool>.` |
| `tools/call` unknown server | 200 SSE | `isError:true`, `Upstream "ghost" failed to handle "x": unknown upstream server "ghost"` |
| `GET /mcp` | 200 | SSE headers, then nothing; the connection stays open |
| `DELETE /mcp` | 200 | chunked, empty body |
| POST, no `content-type` | 415 | `-32000` `Unsupported Media Type: Content-Type must be application/json` |
| POST, `Accept: application/json` only | 406 | `-32000` `Not Acceptable: Client must accept both application/json and text/event-stream` |
| POST, `Host: evil.example.com` | 403 | `-32000` `Invalid Host header: evil.example.com` |
| POST, empty body | 400 | `-32700` `Parse error: Invalid JSON` |
| POST, `not json` | **500** | `-32603` `invalid JSON body: Unexpected token 'o', "not json" is not valid JSON` |

The 406 text is byte-identical to the Swift SDK's own `AcceptHeaderValidator(.sseRequired)` message,
because both implement the same spec sentence — reproduced rather than coincidental, and §4.3 reuses
the SDK's validator to get it.

### 3.3 `/health`, `/status`, 404

```
GET /health  → 200 {"ok":true,"upstreams":1}
GET /status  → 200 {"ok":true,"port":8991,"idleMs":60000,"children":[{"name":…,"transport":"stdio",
                    "state":"idle","callsServed":0,"inFlight":0,"idleSec":0}],"pendingAuth":[],"tools":0}
GET /nope    → 404 {"error":"not found; MCP endpoint is /mcp"}
```

All three carry `content-type: application/json` and an explicit `content-length`. **None requires a
token** — `src/router.ts:239-242` answers them before the control block at `:253-263`, deliberately.
G11 pins that.

### 3.4 The CLI, measured per stream

Run against `MCP_ROUTER_HOME` = a scratch directory with an empty `mcpServers`, port 8993 with
nothing listening:

| verb | stream | bytes | exit |
|---|---|---|---|
| `status`, no router | **stdout** | `no router answering on 127.0.0.1:8993 (fetch failed)` | 1 |
| `usage`, no router | **stderr** | `mcp-router: no router answering on 127.0.0.1:8993 (fetch failed)` | 1 |
| `tools`, no servers | stdout | `\n0 tools from 0 upstreams\n` | 0 |
| unknown verb | stdout | the usage block | 1 |
| `--port abc` | stderr | `--port expects a number, got "abc"` | 2 |

`(fetch failed)` is Node's own `TypeError` text, not a connection-refused string. `status` and
`usage` differ in **stream** and in the `mcp-router: ` prefix because `cmdStatus` catches and writes
while `cmdUsage` throws to `run().catch` at `index.ts:370-372`. `cmdTools` has **no empty branch**.

### 3.5 The log

```
2026-08-14T09:31:09.071Z info  mcp-router listening on http://127.0.0.1:8991/mcp
2026-08-14T09:31:14.139Z info  upstream "probe" ready in 291ms
2026-08-14T09:35:10.909Z info  SIGTERM received; closing upstreams
```

ISO-8601 with milliseconds, a space, the level left-padded to five characters, a space, the message.

## 4 · What is built

### 4.1 `LoopbackHTTPServer`

New, in `app/Sources/RouterCore/HTTP/`. R5's `LoopbackCallbackListener` was read first and three of
its decisions are carried over — the loopback pin through `requiredLocalEndpoint` rather than
`NWListener(using:on:)`, a bind failure that **throws** in the reference's `listen EADDRINUSE:
address already in use 127.0.0.1:<port>` wording, and a head deadline so a silent client cannot pin
a socket. It is not reused: it binds once per instance and refuses reuse, reads only a request line,
answers one request per connection and has no streaming. The router needs all four, and bending a
single-shot OAuth callback into a general server would risk that flow's proven termination behaviour
for no gain.

Added: `Content-Length` bodies, keep-alive, chunked streaming responses, concurrent connections —
each connection in its own `Task`, so the router is not serialised behind its slowest tool call.

### 4.2 `RouterService`

`app/Sources/RouterCore/Service/`. Assembles config, manifest store, pool, control handler, usage
store, auth and registry, with `start()` / `stop()`, dispatching in `src/router.ts`'s order: identity
prefetch → `/health` → `/status` → control paths → `/mcp` → 404. The body is read once and only on
the paths that own it, for the reason `src/router.ts` records: a stream drained for a `/mcp` POST
leaves the MCP transport waiting forever.

Executable target `mcp-router-swift` in `Sources/MCPRouterCLI` is the argv shell over it.

### 4.3 `MCPEndpoint`

JSON-RPC over R1's `JSONValue` / `JSStringify`, for §3.1's two reasons. It reuses the SDK's
`HTTPRequest` and validators — `OriginValidator`, `AcceptHeaderValidator(.sseRequired)`,
`ContentTypeValidator` — so the 403/406/415 bodies are the SDK's own strings, then handles the
method itself: `tools/list` through the manifest **store** (so an `index` run reaches the next client
without a restart) and scoped by the caller's directory; `tools/call` with the name split, the
un-namespaced refusal, project scoping that *refuses to run* rather than merely hiding, the placard
answer that never spawns, then `pool.lease` → call → `release`; `initialize`, `ping`,
`notifications/*` and unknown exactly as §3.2 records.

### 4.4 Upstream calling

`UpstreamSession` exposes only `processIdentifier`, `waitUntilEnded()` and `shutdown()` — there is no
way to *call* a leased upstream. Two requirements are added:

```swift
func listTools() async throws -> JSONValue
func callTool(name: String, arguments: JSONValue) async throws -> JSONValue
```

`JSONValue` rather than the SDK's `CallTool.Result`: the reference passes the upstream's object
through, and a typed decode drops any member the SDK does not model. `FakeSession` in
`Tests/RouterCoreTests/PoolTestSupport.swift` is updated in the same change.

### 4.5 `HTTPUpstreamTransport`

The client R2 deferred. `MCP.HTTPClientTransport` on the pinned SDK, wired to R5's
`UpstreamAuthorizing` seam so an `oauth: false` upstream suppresses authorization entirely rather
than failing it, and a 401 records a challenge instead of opening a browser — the router runs under
launchd with no user attached.

### 4.6 `ManifestIndexer`

`UpstreamIndexerPort` for real: lease, `listTools()`, write the entry, save. What both
`POST /servers/:name/reindex` and `mcp-router index` run.

### 4.7 The CLI

Nine verbs, `src/index.ts` as the reference for each: `serve`, `import`, `index`, `refresh`,
`status`, `tools`, `usage`, `help`, and `--help`/`-h` as aliases of one arm. `auth` is implemented
so the verb exists, but it is **not claimed as parity** — §8 A1. `watch` is not built; it is
`R2-W`'s and `cli-watch` stays blocked with that owner.

**Every string is the reference's, on the reference's stream, with the reference's exit code**, per
§3.4 and §5. No verb gains a tail, a hint or an empty-state sentence the reference does not have.

### 4.8 Lifecycle and the installer

`SIGINT`/`SIGTERM` → log `<sig> received; closing upstreams`, flush usage, stop the listener, shut
the pool down, exit 0. `docs/install.sh` gains a documented, **non-default** `MCPR_ROUTER_BINARY`
so a launchd agent can be pointed at a Swift binary; `node dist/index.js serve` stays what the
installer writes unless it is set. The default is R4's to flip.

## 5 · The state matrix

This item renders no SwiftUI; its user-facing surface is the CLI's two streams and the log, and
`DESIGN.md` §5 and §6 govern both — as R4's own gate output does.

Revision 1 invented copy here and claimed parity on it. Every row below is now either **measured**
(§3.4 or the reference's source, cited) or explicitly marked as a **gap in the reference that this
item does not fill**, because filling it would be an undeclared divergence on a row in this item's
own budget.

| State | Surface | Copy | Source |
|---|---|---|---|
| Default | `serve` | `serving 12 tools from 4 upstreams; 0 open, idle window 300s` | `index.ts:220-223`, verbatim |
| Empty | `tools`, no servers | `\n0 tools from 0 upstreams\n`, exit 0 | measured §3.4. **The reference has no empty branch.** DESIGN.md §5 wants one sentence and one action here; adding it is a divergence on `cli-tools`, so it is **reported as deferred child D-r2r-a** and not built |
| Loading | `index` | `4 upstreams, 2 need indexing` before any spawn, then a line per server | `index.ts:177-178` |
| Partial | `index`, some failed | `  ok    fs (12 tools)` / `  FAIL  broken: …`, then the closing count | `manifest.ts:242`, `index.ts:186-190` |
| Error | `serve`, port taken | `listen EADDRINUSE: address already in use 127.0.0.1:8879`, exit 1 | the reference's wording, **with no tail added** |
| Success | `auth` | `✓ github is authorized` | `index.ts:295`. Not claimed as parity — A1 |
| Offline | `status` | **stdout** `no router answering on 127.0.0.1:8879 (fetch failed)`, exit 1 | measured §3.4 |
| Offline | `usage` | **stderr** `mcp-router: no router answering on 127.0.0.1:8879 (fetch failed)`, exit 1 | measured §3.4 |
| Offline | `auth` | stderr, same text plus ` — start it first` | `index.ts:279`. Not claimed — A1 |
| Disabled | `auth <stdio>` | `stdio servers do not authorize; their credentials are env vars` | `control.ts:392`. Not claimed — A1 |
| Overflow | `status`, long names | padded, never truncated: `padEnd(20)` widens, it does not elide | `index.ts:247`. A truncated server name is unactionable in a terminal |

Three of the nine states are therefore **the reference's own gaps**, recorded here rather than
quietly improved. That is the correct answer for a port whose acceptance test is a byte comparison,
and D-r2r-a is where the improvement goes once the cutover has happened.

## 6 · Guarantees

| # | Guarantee | Why |
|---|---|---|
| G1 | The control API's PATCH never reads `command`, `args` or `env`, and this item adds no second write path | standing constraint |
| G2 | The listener binds **loopback only**, pinned in the bind parameters | this endpoint runs every MCP server the user owns with their environment |
| G3 | A `Host` that is not an allowed loopback authority is **403** | a page the user visits can point a hostname it controls at 127.0.0.1; loopback binding alone does not keep a browser out |
| G4 | No credential, token or `Authorization` header reaches a log line | `SWIFT_PRACTICES.md` §6; enforced by `ServiceLogEvent` being a closed enum with no case that can carry one |
| G5 | The Swift binary ships **alongside** the TypeScript one; `install.sh`'s default is unchanged | the user's live sessions depend on the installed router |
| G6 | The MCP SDK pin stays `exact: "0.12.1"` and stays in `RouterCore` only | pre-1.0; its README warns minor bumps break |
| G7 | A call is recorded **after** the result is on its way, and attribution failure never fails a call | `src/router.ts`'s `finally` |
| G8 | One broken upstream is a tool error, never a router crash | one broken server must not take the other nine down |
| G9 | No displayed number is one the router does not observe | `DESIGN.md` §6 |
| **G10** | The control token check travels with the control paths onto the socket: **both** `Authorization: Bearer <t>` and `x-mcpr-token: <t>` are honoured (`control.ts:58-60`), and an unauthorized mutation is 401 with a body naming the token path (`control.ts:233-234`) | this item is what first makes `ControlHandler` reachable over a socket; until now it was only ever called in-process |
| **G11** | `/health` and `/status` stay **unauthenticated**, and are dispatched **before** the control block | `src/router.ts:239-242`; both are rows in this item's own budget, and gating them would be a divergence dressed as hardening |
| **G12** | F3's recorded fixtures are consumed, never altered. No lane this item adds writes to `app/Sources/MCPRouterKit/Control/Fixtures/`, and `git status` on that directory is part of the completion note | brief:57-58 |

## 7 · Declared divergences

Asserted in **both** directions by the divergence lane, so one fixed upstream fails as stale rather
than passing quietly.

| id | Divergence |
|---|---|
| `div-r2r-d8` | A POST body that is not JSON. Both routers answer **500** with code **-32603** and a message beginning `invalid JSON body: `; only the text after that prefix differs, because the reference's is V8's own parser output (`Unexpected token 'o', "not json" is not valid JSON`) and Swift's is its own parser's. Status and code are **not** divergent — revision 1 had Swift answering 400 `-32700`, which was a second, unjustified divergence riding along on the first, and which additionally collapsed the reference's distinction between an empty body (400 `-32700`) and an unparseable one. Both are preserved. |

Inherited and untouched: R3's D1–D5, R5's P7 callback framing, R2's D6 acquisition counter.

**Stated plainly, because it is the one lever that turns red into green:**
`parity-manifest-check.sh` derives only control rows (`:103-115`) and fixture rows (`:118-131`) from
source. The other 42 rows — divergence, mcp, cli, pool, install, state, log — are checked against
nothing, so adding a row there is unchecked by construction. This item adds exactly one, its
justification is above, and the completion note carries the one-line diff.

## 8 · Assumptions

- **A1 — `D-j` is NOT fixed, and `cli-auth` leaves this item's budget.** Revision 1 proposed wiring
  `AuthRoutes` into `ControlHandler`'s dispatch. That is wrong for a decisive mechanical reason:
  `control-differential.sh:465-479` asserts the defect in both directions, so fixing it makes that
  lane `record "$id" fail "stale defect record: …"` — and the gate goes red whether the manifest row
  is left `blocked` (`:141` matches `^stale`) or flipped to `proven` (`:172` matches `fail`). The
  only route to green would be editing a 637-line lane that has been adversarially reviewed three
  times, which is the failure this item must not produce. So `AuthRoutes` stays undispatched.
  `mcp-router auth` is implemented as a verb, but the Swift router answers 405 where the reference
  answers 400, so the verb cannot be byte-compared. **`cli-auth`'s owner is left as `R2-R`.** Revision 2 proposed
  moving it to `D-j` and calling that a concession; it is not one — the row was unprovable either
  way, `parity-gate.sh:134` reads the owner only to print it, and the sole observable effect would
  have been which item's name sits beside a row it failed to prove. The row stays this item's, and
  is reported as owed. Its **note** is corrected, because the original said "No Swift entry point"
  and the entry point now exists; the note states the measured reason instead.
- **A2 — the `mcp` lane diffs bodies BYTE FOR BYTE.** Revision 1 proposed canonicalised (key-sorted)
  comparison; that was refuted with two concrete misses, and the first was fatal — §3.1 identifies
  envelope member order as the most likely divergence, and sorting keys is exactly what makes it
  invisible. Byte comparison is achievable here because §4.3 serialises with R1's `JSStringify` from
  values parsed by R1's `JSONParser`, which is the machinery built to reproduce
  `JSON.stringify`, so member order, number rendering (`1.0` → `1`), unicode escaping and exponent
  form are all under this router's control rather than an encoder's. Framing — status line,
  application headers, SSE event framing — is diffed byte for byte too, with `Date` normalised as
  the only exception, because it is a clock reading. **If a byte diff proves unachievable on some
  request, that request becomes a declared divergence with its measurement, never a relaxed
  comparison.**
- **A3 — `state-ondisk-compat` is proven against a real TypeScript run's leftovers.** The lane runs
  the reference until it has written `servers.json`, `manifest.json`, `usage.jsonl` and `stats.json`,
  stops it, then starts the Swift router on the same home and requires the same `tools/list` corpus
  and the same `/usage` body. Files the harness wrote itself would prove nothing.
- **A4 — `install-launchd-serve` is two-sided.** Revision 1 supervised only the Swift binary and
  asserted plist text, which is not a differential and would have been counted as one. The lane now
  writes **two** scratch launchd agents with identical `RunAtLoad`,
  `KeepAlive/SuccessfulExit=false` and log paths, in a scratch `LaunchAgents` directory under
  scratch labels, one per router, and compares the same four observations on each: it comes up at
  load, `kill -9` relaunches it, a clean `exit 0` does not, and both log paths are written. A plist
  that parses is not a binary that survives being killed.
- **A5 — ports.** Lanes bind 8992–8999 and refuse to start if the port is listening. 8975/8976 are
  the user's; 8966 is `parity-pool.sh`'s; 8991 was §3's probe; 8879 is the reference's default and
  appears only in copy.
- **A6 — new row ids stay group-prefixed.** `parity-gate.sh:141` matches the stale-assertion lookup
  on id alone where `:160` matches group and id. Five new lanes writing many rows raise the chance
  of a cross-group collision producing a spurious mismatch. Every id this item adds or reports
  against already begins with its group name, and §2.4's assertion enforces it. The exposure can
  only make the gate redder, never greener, and is recorded rather than fixed in the gate.
- **A7 — the fixture count discrepancy is reported, not resolved.** The brief says "F3's 23 recorded
  fixtures"; `surface.tsv:40` says 24 and carries 24 fixture rows; the directory holds 24. Nothing
  in this item touches either, and the discrepancy goes in the completion note for whoever owns the
  brief.

## 9 · The oracle for every owned row

Revision 1 stated a comparison rule for 7 of 19 rows. Every row now names what is compared, on which
two sides, and what would make it red.

| row | lane | both sides | oracle |
|---|---|---|---|
| `mcp-endpoint` | mcp | live TS, live Swift | the four framing refusals — 403 bad Host, 406 wrong Accept, 415 no content-type, 400 empty body — status line and body byte-diffed |
| `mcp-tools-list` | mcp | live TS, live Swift | one `servers.json` and one `manifest.json`, both routers started on **copies** of it; `tools/list` response byte-diffed whole, envelope included |
| `mcp-tools-call` | mcp | live TS, live Swift | four calls against the same fixture upstream: ok, un-namespaced, unknown server, tool-reported error. Bodies byte-diffed |
| `mcp-health` | mcp | live TS, live Swift | `GET /health` status, application headers and body byte-diffed |
| `mcp-status` | mcp | live TS, live Swift | `GET /status` after an **identical** call sequence, so `callsServed` and `inFlight` are comparable rather than incidental. `port` is normalised (two routers cannot share one) and `idleSec` is normalised (a clock reading). Nothing else |
| `cli-serve` | cli | both binaries | started with the same flags on the same scratch home: both bind, both answer `/health`, both write the same **three** log lines — `listening on`, `serving N tools…`, `<sig> received` — and both exit 0 on SIGTERM |
| `cli-import` | cli | both binaries | run against one `~/.claude.json` copy; the resulting `servers.json` byte-diffed, and stdout byte-diffed |
| `cli-index` | cli | both binaries | same home copy; resulting `manifest.json` byte-diffed and stdout byte-diffed |
| `cli-refresh` | cli | both binaries | Swift `refresh` against the **reference's** `refresh` on the same input. Revision 2 compared Swift `refresh` against Swift `index`, which two identically wrong implementations pass |
| `cli-status` | cli | both binaries | against a running reference, and with nothing listening; **stdout, stderr and exit code** each compared (§3.4 — the streams differ per verb and a combined capture hides it) |
| `cli-tools` | cli | both binaries | same manifest copy; stdout byte-diffed, including the empty case |
| `cli-usage` | cli | both binaries | same `usage.jsonl` copy; stdout, stderr and exit code compared, offline case included |
| `cli-help` | cli | both binaries | `help`, `--help`, `-h` and an unknown verb: stdout byte-diffed and exit codes compared |
| `pool-p4` | mcp | live TS, live Swift | a call held open longer than a short `idleMs` against **both** routers, `/status` polled throughout: neither may report the child gone while `inFlight > 0`. Revision 1 left this with no oracle; it becomes measurable precisely because there is now a Swift endpoint to put under load |
| `pool-reap-traffic` | mcp | live TS, live Swift | the same traffic pattern on both — burst, idle past the window, burst again — with the spawn/reap sequence read off `/status` and compared as a sequence |
| `install-launchd-serve` | install | both binaries | A4's four observations under identical scratch agents |
| `state-ondisk-compat` | state | TS writes, Swift reads | A3 |
| `log-bytes` | log | both binaries | the same scripted session driven at both routers; `router.log` diffed line by line with the ISO timestamp and any duration in ms normalised, since both are clock readings. Everything else — level padding, quoting, `call(s)` plurals — byte-compared |
| `div-r2r-d8` | divergence-in-mcp-lane | live TS, live Swift | asserted **both** ways: the reference must still answer 500/-32603 with V8 text, and Swift must still answer 500/-32603 with its own. Either side moving records `stale` |

## 10 · Where each review finding is answered

| finding | severity | answered in |
|---|---|---|
| 1 · A1 forces a `control-differential.sh` edit | blocker | §8 A1 — A1 dropped, `cli-auth` reassigned to D-j, budget 19 → 18 |
| 2 · lanes are unreviewed gate surface; 12 rows with no oracle | blocker | §2.4 (group assertion, negative control, per-lane caveat) and §9 (an oracle for all 19 rows) |
| 3 · `install-launchd-serve` one-sided, caveat unprintable | blocker | §8 A4 (two-sided) and §2.4 item 3 (the lane prints its own caveat, which `:101` echoes) |
| 4 · canonicalisation hides envelope order and number rendering | major | §8 A2 — byte diff throughout |
| 5 · `div-r2r-d8` over-declared | major | §7 — narrowed to the message text; status and code now match; the denominator mechanism stated |
| 6 · ceiling contradicts §7 and §8; baseline unmeasured | major | §2.1 (baseline re-measured) and §2.2 (one arithmetic statement, 18 + 1) |
| 7 · no guarantee for the control token on a socket | major | §6 G10, G11 |
| 8 · invented CLI copy on owned rows | major | §3.4 (measured per stream) and §5 (rewritten; three states recorded as the reference's own gaps, D-r2r-a raised) |
| 9 · F3 fixture contract dropped | minor | §6 G12 and §8 A7 |
| 10 · citation drift, three port regimes | minor | `:201` corrected in §2.3; ports stated in §3 |
| 11 · new false-red surface on id-alone matching | minor | §8 A6 |

## 11 · Deferred children raised, not built

| id | Title | Depends on |
|---|---|---|
| `D-r2r-a` | `mcp-router tools` has no empty state; DESIGN.md §5 wants one sentence and one action | the cutover (R4-C) — until then it is a divergence |
| `D-r2r-b` | The Swift `watch` verb and its launchd agent | already `R2-W`; named here only because `cli-watch` and `install-launchd-watch` stay blocked on it |

## 12 · Where each finding of the second review is answered

| finding | severity | answered in |
|---|---|---|
| F1 · G10 guarantees a property no lane can reach; `control-differential.sh` drives `ControlDiff` in-process, not a socket | blocker | **Not closed.** Reported as deferred child `D-r2r-b` and stated plainly in plan-R2R §8. Closing it means editing a lane this item may not touch, or adding rows to the one group nothing audits. The 11 proven `control` rows describe a handler, not a served endpoint, and this item says so rather than letting the number imply otherwise |
| F2 · `cli-import` and `cli-index` stdout carry an epoch and an absolute path, so a byte diff is impossible | blocker | Both normalisations are now named per row, in the same class as `Date` and `idleSec`: `<epoch>` for `servers.json.bak-<Date.now()>`, `<home>` for the two scratch directories. Neither becomes a divergence row |
| F3 · the lane guards do not bind; the negative control is a prose promise | blocker | `scripts/acceptance/parity-lane-selftest.sh` — a script, one seeded defect per lane, non-zero exit if any lane stays green. It has already found two holes in itself. Each lane also declares an explicit owned `(group, id)` set that `record()` enforces |
| F4 · the `cli-auth` reassignment costs nothing and is presented as a cost | major | §8 A1 — the reassignment is withdrawn; only the stale note is corrected |
| F5 · `cli-refresh`'s oracle is same-side | major | §9 — it compares against the reference's `refresh` |
| F6 · "first four log lines" when §3.5 records three | major | §9 — three, enumerated |
| F7 · `mcp-status` needs more than `idleSec` normalised | major | §9 — `port` and `idleSec`, each named, with the sequence driven identically |
| F8 · the framing byte-diff reaches below what Swift controls | major | §8 A2 — narrowed to status line, application headers and de-framed SSE events |
| F9 · §2.2's cross-check says 12 where the numbers say 13 | major | §2.2 — corrected, with the subtraction shown |
| F10 · `status` prints `undefined calls` and §5 never recorded it; `--force` omitted | major | **Measured and reproduced.** `running   stdio  probe   undefined calls, idle 2s` was confirmed on 2026-08-14, and the CLI reproduces it through the same mechanism rather than by hard-coding the word. `index --force` emits ` (forced: all)` and does |
| F11 · eight fresh citation drifts | minor | Line-number citations in §5 are replaced by the measured output itself; where a line is still cited it was re-read |
| F12 · A6's enforcement claim points at an assertion that does not enforce it | minor | §8 A6 — the claim is now that ids are group-prefixed **by convention** and that `record()` enforces membership of an explicit owned set, which is the property that actually closes authorship |
| F13 · a lane may need to stamp more than one group | minor | Each lane declares an owned set of `(group, id)` **pairs**, which handles the mcp lane owning `pool` and `divergence` rows without weakening the check |

**Not closed: F1.** It is the one finding this item leaves open, and it is open because closing it
inside this item would require exactly the kind of edit the item exists to avoid.
