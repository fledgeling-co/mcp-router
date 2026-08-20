# R8 — an upstream that refuses our credentials must say so

**Status:** built on `ai/r8`, TypeScript half proven, Swift half outstanding.

## What happened

On 2026-08-20 the owner asked why an MCP server they had meant to use all day had not
been used. The answer was that nothing had told them it was unusable.

Measured on the running router, in this order:

- `mobbin`'s access token was granted at `10:56:39.710Z` with `expires_in: 3600`, so it
  expired at `11:56:39Z`.
- The upstream last served calls at `11:02:01.806Z` — `closing idle connection "mobbin"
  after 3 call(s), 323s alive`.
- A reconnect at `11:58:54.611Z` failed at `11:58:54.984Z`, 373ms later, with
  `[-32603] Internal error: Authentication required`. A working refresh does not fail
  that fast.
- From then on `tools/list` served 91 tools and none of them were `mobbin`'s.

Claude Code fetches `tools/list` once at session init. A session starting after that
point was never offered the server's tools, so no agent could report the capability
missing — it was never shown one. That is the whole failure: not an error the user
ignored, an absence they could not see.

What the surfaces said while this was true:

```
  idle      http   mobbin
```

`mcp-router status` printed `idle` — the same word as the eleven upstreams that were
working. Five of thirteen upstreams were contributing zero tools for four different
reasons and all five read `idle`:

| server | reason it contributed nothing |
|---|---|
| mobbin | token expired; refresh refused |
| atlas-admin | never authorized at all |
| sift | did not initialize within 60000ms |
| lifeline | did not initialize within 60000ms |
| namecheap | indexed cleanly, declares no tools |

`pendingAuth` was `null`. The log's last `needs authorization` line was from
2026-08-15, five days earlier. And `GET /servers` carried this, three lines apart in
one object:

```json
{ "tools": 0,
  "indexError": "[-32603] Internal error: Authentication required",
  "auth": { "supported": true, "authorized": true } }
```

## Why every detector missed it

Three separate auth-failure detectors existed and none matched.

1. `pool.open` caught the SDK's typed `UnauthorizedError`. That fires when the transport
   is refused with a 401. A server that has stopped honouring a refresh token does
   something else: the POST succeeds, the MCP handshake completes, and the first real
   call comes back as a JSON-RPC error inside a 200.
2. `index.ts` matched `/not authorized|unauthorized|401/i` against the recorded index
   error. The string a live server actually produces is `Authentication required`, which
   contains none of those three.
3. The indexer matched nothing at all. `manifest.ts` recorded the error, logged
   `failed to index`, and moved on.

And one structural cause underneath all three: `indexOne` re-indexes on a **scratch
pool** — correctly, so that a re-index cannot disturb the serving pool's connections —
and shuts it down four lines later. Everything the re-index learns dies with it. The
manifest keeps the error, which is why `describe` could still tell; the pool is what the
operator surfaces read, and it was being told nothing.

## What changed

- **One predicate, `isAuthFailure`, in `src/auth.ts`.** Matches `authentication
  required`, `unauthorized`, `not authorized`, `invalid_grant`, `invalid_token` and a
  word-bounded `401`. `403` is deliberately excluded: forbidden means the credential was
  understood and the account is not permitted, so offering `mcp-router auth` would send
  the user round a loop that cannot succeed. That case wants its own reporting and does
  not have it.
- **`PendingAuth.url` is now optional**, with a `reason`. Requiring a URL is what forced
  the index path to record nothing: an upstream that rejects a refresh never reaches the
  redirect callback, so there is no URL to offer and the server still needs authorizing.
- **`pool.noteAuthFailure`** records the rejection and writes the warning, from the paths
  that had no URL. **`pool.adoptPending`** hands a scratch pool's findings to the pool
  that outlives it, silently, because the observer has already written the line.
- **`authorized` means authorized.** It was `hasTokens(name)`, which reports that a
  *file exists*. It is now `hasTokens(name) && !authRejection`, and a new `rejected`
  field carries why. `authRejection` reads the manifest as well as the live pool,
  deliberately: `pendingAuth` is in-memory and empty on a fresh start, so a restarted
  router would otherwise report `authorized: true` again until something re-indexed.

REQ-007 — "numbers the router does not observe are never displayed" — is the rule this
was breaking. A field named `authorized` reporting a fact about the filesystem is
exactly what it forbids.

## The gate

`scripts/acceptance/auth-rejection-visible.sh`, 8 checks, `examined=8 failures=0`.

It reproduces the shape rather than the string: `scripts/fixtures/mcp-fixture-server.mjs`
gains a `staletoken` mode whose transport connects, whose MCP handshake succeeds, and
whose first real call returns `-32603 Internal error: Authentication required` in a 200.
The home is seeded with a credential file, because a token on disk that the server has
stopped honouring is the exact condition that made the old `authorized` report true.

It was watched to fail. Before the fix, on the same fixture, 6 of the 8 checks were red
and the status line read:

```
  idle      http   staleserver
```

Two of those reds were the gate's own fault and are recorded because they are the kind of
mistake that produces a false green elsewhere. It demanded HTTP 200 from
`POST /servers/<name>/reindex`, where 422 is the right answer and 200 would be the wrong
one — the route reports the index it just ran, and the index failed, which is the state
under test. And it read `pendingAuth` off `/servers`, where the field means
`currentFlow()` — a browser authorization happening right now — rather than off
`/status`, where it means `pool.pending()` and is what `status` prints its `!` line from.
Both names are right; they are different things.

## The Swift half, and the SDK defect blocking it

`AuthRefusal.isRefusal`, the widened `PendingAuth`, `pool.noteAuthFailure`,
`pool.adoptPending`, the `authRefused` log event and the `authorized` fix are all built
and the package compiles. `authorized` reads the recorded index error through
`AuthRefusal.isRefusal`, so it is durable across a restart exactly as the TypeScript
half is.

Running the gate against the Swift binary stops before it can measure anything, and the
reason is worth recording precisely because it is not in this repository.

```
body: {"name":"staleserver","tools":0,"error":"[-32603] Internal error"}
```

The reference records `MCP error -32603: Internal error: Authentication required` for
the same response. The Swift router records `[-32603] Internal error`. The upstream's
own message is gone, so there is no text for `isRefusal` to match and the refusal is
undetectable on this path.

The cause is `modelcontextprotocol/swift-sdk` 0.12.1,
`Sources/MCP/Base/Error.swift:217-240`. Its decoder reads the server's `message`, then
maps the code:

```swift
case -32700: self = .parseError(unwrapDetail(message))
case -32600: self = .invalidRequest(unwrapDetail(message))
case -32601: self = .methodNotFound(unwrapDetail(message))
case -32602: self = .invalidParams(unwrapDetail(message))
case -32603: self = .internalError(unwrapDetail(nil))
```

`unwrapDetail(fallback)` returns `data.detail` when present and the fallback otherwise.
Every code passes `message` as that fallback. **`-32603` alone passes `nil`**, so a
server that returns `-32603` with a message and no `data.detail` has its message
discarded, and `description` renders the bare canonical name — `Error.swift:91` is
`"Internal error" + (detail.map { ": \($0)" } ?? "")`, which appends nothing because
`detail` is nil.

This is the code servers most often use for an arbitrary application error, so it is the
one that loses the most. It is a one-token inconsistency against its four neighbours,
which is what makes it read as a defect rather than a decision.

Consequences beyond this item: **for the whole class of `-32603` upstream errors the
Swift router tells the user strictly less than the reference does**, and no parity
scenario had exercised one, so the harness had never seen it. That is a coverage gap in
the parity suite as much as a defect in the SDK.

Remedies, none taken here: report it upstream and take a fixed release; pin a patched
fork; or read the JSON-RPC error before the SDK types it, which means a seam below the
client and is the largest of the three. Until one of them lands, the Swift router cannot
detect this refusal shape, and the item is blocked rather than incomplete.

## Outstanding
- **`mcp-router status` still prints `idle` for the other four zero-tool upstreams.** A
  server that never initialized, and one that simply declares no tools, are still
  indistinguishable from a working one at a glance. Only the auth case is fixed here.
  The `undefined calls` display bug on running children is a separate known divergence.
- **403 has no reporting.** Named above; not built.
