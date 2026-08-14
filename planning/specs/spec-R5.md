# R5: Swift router — OAuth and the authorization routes

**Status:** Ready for Plan · **Branch:** `ai/r5` · **Worktree:** `.worktrees/R5` · **Depends on:** R1 (merged), R3 (in flight) · **Blocks:** R4

---

## The original brief, verbatim

> # R5 — Swift router: OAuth and the authorization routes
>
> **Category:** router · **Depends on:** R3 (merged) · **Blocks:** R4
>
> Split out of R3 by the orchestrator. R3 asked the question directly — take R3 as-is and finish
> P4+P6+P7, or let auth become its own item — and the evidence says split: R3 had already blocked
> twice, once on an interrupt and once on scope, and its remaining work was P4/auth plus three
> smaller closes. A slice that large is what made the turn unfinishable.
>
> ## Scope — R3's plan phase P4, verbatim in intent
>
> - **B60–B66**, none of which are delivered: no `Auth/` sources exist in `RouterCore`.
> - `POST /servers/:name/auth` and `/approve`, both still missing from the control surface.
> - The SDK OAuth stack, the fixed-port callback listener, the two rendered pages, and all five
>   termination paths.
>
> ## What R3 already established that you inherit
>
> `ai/r3` at merge carries the control API's value layer, the registry port, the byte contract, and
> 273 passing tests. Read `planning/specs/spec-R3.md` and `planning/plans/plan-R3.md` before
> starting — P4 is specified there and the spec has already been through an out-of-family review
> that produced 86 findings, 82 accepted.
>
> Also inherit two open items R3 named against auth specifically:
>
> - **Attribution's partial-identity path contradicts B69.** Resolve it rather than working around
>   it; R3 flagged it as open, not decided.
> - `isLive`/`clearPending` take Swift `String`, so canonical equivalence applies where the
>   reference uses code units (S5/B24). Auth handles user-supplied names, so this is yours to close.
>
> ## Constraints inherited from the router items
>
> - The reference is `src/*.ts`. Where behaviour is not obvious, read the TypeScript rather than
>   inferring it — R3 found five live defects that way, and rejected three review findings that
>   would have edited correct code into a divergence.
> - F3's 23 recorded fixtures are the wire contract R4 diffs against. Consume them; never alter them.
> - **B76: parity vectors must exceed R1's 224.** R3 left this unmet at exactly 224. Every auth
>   route you add is a vector, so this item is where it gets met.
> - The MCP SDK is pinned exact at `0.12.1` and lives only in `RouterCore`, which neither app links.
>   Do not add a second dependency or widen the pin.
>
> ## Out of scope
>
> - Anything outside auth and the two routes. R3's own close-out (P6 vectors, P7's
>   `no-wire-codable.sh`, Phase 6 acceptance) stays with R3.
> - The Mac and iPhone auth *surfaces*. M8 and I1 own those; this is the router half.
>
> ## Acceptance
>
> Both routes answer with the reference's byte shape, every termination path is exercised by a test
> rather than described, and the parity vector count clears 224 with auth vectors included.

---

## 1 · The premise correction this spec makes

The brief says *“Depends on: R3 (merged)”*. **R3 is not merged.** It is in flight on `ai/r3`, and
the orchestrator's dispatch instructs branching `ai/r5` from `main`. That is not a nuance — it
decides the shape of half this item, so it is recorded here rather than absorbed silently.

Measured on `main` at `7fa55c7`:

| Symbol R5 would otherwise call | Where it actually lives | Consequence |
|---|---|---|
| `ControlHandler`, its dispatch `switch` | `ai/r3` only | R5 cannot add a `case` to a file that does not exist on its base |
| `ControlResponse`, `ControlRequest`, `ControlPorts.AuthStore` | `ai/r3` only | Declaring them here would duplicate an R3 symbol and collide at merge |
| `Manifest`, `ManifestIO`, `DiffTools`, `JSONValue`, `JSString`, `JSStringify`, `JSDate`, `FileSystem` | `main` (R1) | Available; the route bodies need nothing else |

**The resolution.** R5 delivers the two routes as *value-layer functions* over R1 types only —
each returns `(status: Int, body: JSONValue)` — plus the whole `Auth/` module. That satisfies the
brief's acceptance (“both routes answer with the reference's byte shape”), is provable against F3's
recorded fixtures, and duplicates no R3 symbol. What R5 does **not** deliver is the two `case` lines
in R3's dispatch `switch`; those are named in §8 as the integration R3 or R4 performs, two lines
each, against a function that already exists and is already tested.

This is the brief's own instruction followed — *“if you need a symbol it owns, say so in your report
rather than duplicating it or reaching into its worktree.”*

## 2 · What is inherited, not re-specified

`planning/specs/spec-R3.md` §G already specifies this work as **B60–B66**, and that spec has been
through an out-of-family review (86 findings, 82 accepted). Those clauses are **binding here
unchanged** and are not restated. This spec adds only what R3's §G does not cover: the two routes,
the completion side-effect, the name-equivalence close R3 left open, and the state matrix.

R3's §G clauses, by id, so a reader knows what is in force: **B60** record path + `0700`/`0600` +
`hasTokens` false without `access_token`; **B61** unreadable record warns and reads unauthorized,
never `try?`-to-default; **B62** `clearAuth` reports prior existence and `DELETE …/auth` answers
`{server, signedOut}`; **B63** `POST …/auth` refuses stdio 400, else 200 `{server, authorizationUrl}`,
502 on failure; **B64** a second flow cancels the first, `currentFlow()` tracks it, cleared on all
terminations; **B65** the listener answers only `/callback`, renders the recorded pages, and always
cleans up; **B66** no token, `Authorization` header or whole record is ever logged.

**One correction to R3's §G.** B65 says the listener settles the flow and always cleans up “on
success, provider error, missing code, exchange failure and timeout” — five paths. Read against
`src/auth.ts`, a sixth reachable request outcome exists and is **not** a termination: a request to
any path other than `/callback` answers `404` with a zero-length body, does **not** settle, and does
**not** clean up (`res.writeHead(404).end(); return;` — before any `settle`/`cleanup`). B65's “per
termination” tests must therefore be joined by a test asserting the non-termination, or a port that
cleans up on a stray `GET /favicon.ico` passes B65 while diverging. Recorded as **B82**.

## 3 · New clauses

| # | Clause | Evidence type |
|---|---|---|
| B77 | `POST /servers/:name/auth` answers **400** `{error:"stdio servers do not authorize; their credentials are env vars"}` for a stdio upstream, **200** `{server, authorizationUrl}` in that key order otherwise, and **502** `{error:<the thrown message>}` when `beginAuth` throws. The stdio check runs **before** any flow is begun, so a stdio request binds no port. `isStdio` is `u.transport === "stdio"` (`config.ts:55`) — a discriminant on the config union, never “has a command” or “has no url” | fixture test against `auth-start.json` + a branch test each, plus a spy asserting no listener binds on the stdio path |
| B78 | `POST /servers/:name/approve` answers **409** `{error:"no pending change for \"<name>\""}` when the manifest entry exists but has no `pending`, and **200** `{server, approved:<count>}` otherwise. `approved` is `pending.tools.length`, counted **before** the write. An *unconfigured* name never reaches this route — see B83 | fixture test against `approve.json` and `approve-conflict.json` + a round-trip asserting the post-write entry, incl. the present-but-unpending branch |
| B79 | The completion side-effect runs **only** on the flow resolving: `clearPending(name)` then re-index, in that order. It is attached **before** the 200 is written (`control.ts:399-405`), so a Swift port must not assume the response has already been sent. A rejection from **either** the flow **or** the re-index logs `authorization for "<name>" did not complete: <message>` at **warn** — one message, two sources — and is never surfaced as a request failure | ordered spy trace on the success path, **plus** a separate test rejecting from the re-index rather than the flow, both asserting the same warn and an unchanged request outcome |
| B80 | Every server name used as a **lookup or map key** by the auth store and both routes is keyed on **UTF-16 code units** (`JSString`), never Swift `String`, whose equality is canonical. The reference's mechanisms are `Map.get` (`control.ts:301`), object-key lookup (`manifest.servers[name]`) and `===` (`auth.ts:242`) — there is no `!==` name comparison, and the earlier draft citing one was wrong. **This divergence is latent, not live**: `ServerParser.isAdoptableName` refuses any name outside `[A-Za-z0-9_-]+` (verified at `Config/ServerParser.swift:106-112`), so two spellings of one name cannot both reach a port and no cross-record read is reachable today. The `JSString` typing stands anyway — it is what stops the gate's removal or relaxation from silently becoming a divergence — but R5 claims **no live bug fixed here** | red-green test at the **key level only**: a `JSString` map holding U+00E9 and U+0065 U+0301 keeps two entries and resolves neither from the other. **Not** asserted through the filesystem — default macOS APFS volumes compare filenames normalisation-insensitively, so a disk round-trip conflates the two for *both* routers and would prove nothing |
| B81 | Auth and approve carry their own registered parity vectors, each counted by a `compare` closure that reports how many cases it actually compared. The vector total on this branch rises above `main`'s floor of **224**, and the auth subtotal is asserted **separately by name**. The floor is **not** the point and the brief's framing of it is stale: the corpus is already at **352 executed cases on `ai/r3`**, so auth vectors exist because auth needs vectors, not to clear a threshold. Whichever branch merges second raises the floor to the combined total | the suite prints the total and the tagged auth subtotal; both are asserted, so unrelated vectors cannot satisfy the clause |
| B82 | A request to a path other than `/callback` answers 404 with a **zero-length** body and no `content-type`, and is **not** a termination: the flow stays unsettled, the timer stays armed, the listener stays bound | red-green test issuing a stray request mid-flow, then completing the flow normally afterwards |

## 3b · Clauses the substitute out-of-family gate added

Every one of these is reference behaviour a builder would otherwise omit or invent. All were
verified against the cited lines before acceptance.

| # | Clause | Evidence type |
|---|---|---|
| B83 | Both routes sit **inside** the `/^\/servers\/([^/]+)(\/[a-z]+)?$/` block, behind `deps.upstreams.get(name)`: an unconfigured name answers **404** `{error:"no server named \"<name>\""}` and never reaches the sub-route (`control.ts:297-305`) | fixture-shaped test per route with an unknown name asserting 404 and that no manifest read or flow begin occurred |
| B84 | `beginAuth` has **two** pre-flow failures, both surfacing as B77's 502, with different semantics: a `listen` error on the fixed port (EADDRINUSE) rejects **without** any cleanup — timer armed, transport unclosed (`auth.ts:245-251`) — while the **20 000 ms** URL race (separate from `timeoutMs`) rejects `the server never produced an authorization URL` **after** `cleanup()` (`auth.ts:257-265) | test per path asserting the 502 body and, for each, whether a timer/transport survives |
| B85 | Starting a second flow calls `current?.close()`, which is `cleanup` — and `cleanup` **never calls `settle`** (`auth.ts:181, 238-243, 276`). The superseded flow's `completed` therefore **never settles**: neither its side-effect nor its warn ever runs. Only `cancel()` settles-with-error (`auth.ts:271-274`) | red-green test: supersede a flow, then assert over a bounded wait that neither `clearPending`, re-index nor the warn fired. A port that cancels the prior task with an error fails this |
| B86 | On the missing-code path the **page** renders `the provider returned no code` while the **rejection** carries `no authorization code returned` (`auth.ts:211-212`) — two different strings, and B79's `<message>` is the latter | test asserting both strings from one exercise of the path |
| B87 | `clientMetadata` is the dynamic-registration request body and is byte-visible: `client_name` = `mcp-router (<server>)`, `client_uri` = `https://mcp-router.fledgeling.app`, `redirect_uris` = `[<AUTH_REDIRECT_URI>]`, `grant_types` = `["authorization_code","refresh_token"]`, `response_types` = `["code"]`, `token_endpoint_auth_method` = `"none"`, **in that key order** (`auth.ts:87-98`) | serialized-bytes test against the literal expected JSON |
| B88 | `/approve` reads the manifest **fresh from disk** via `loadManifest(cfg.manifestPath)` and writes with `saveManifest` (`control.ts:348,361`), where `/changes` uses the **cached** `deps.manifest.current()` (`control.ts:337`). A corrupt manifest degrades to `{version:1,servers:{}}` with a warn (`manifest.ts:115-122`), so approve against one answers 409, never a throw | a stale-cache test proving the read is from disk, plus a corrupt-manifest test asserting 409 |
| B89 | The written entry follows JS spread order: keys already on `entry` keep their existing positions and only genuinely new keys append; `pending: undefined` is **dropped** by serialization, not emitted as null (`control.ts:354-360`). `saveManifest` writes `JSON.stringify(manifest, null, 2)` through temp+rename (`manifest.ts:134-140`) | byte test over an entry whose original key order differs from the literal's, asserting the file bytes |
| B90 | `AUTH_CALLBACK_PORT` is `Number(process.env.MCP_ROUTER_AUTH_PORT ?? 8880)` and `AUTH_REDIRECT_URI` is derived from it **once at module load**, not per call (`auth.ts:21-22`). It is byte-visible inside `authorizationUrl` (`…%3A8880%2Fcallback` in `auth-start.json`) | test asserting the override is honoured and that a later environment mutation does **not** change the derived URI |
| B91 | The auth record file is `JSON.stringify(rec, null, 2)` — 2-space pretty (`auth.ts:49`) — and every writer merges `{...readRecord(server), …}`, so key order is read-order-then-append | byte test over a record written by two successive partial writes |
| B92 | **Dropped from R5's scope.** `DELETE /servers/:name/auth` is already implemented on `ai/r3` (`ControlHandler`, `case ("/auth","DELETE")`: `clear`, then `clearPending`, then 200 `{server, signedOut}`). R5 does **not** reimplement it — two implementations of one route that can silently disagree is a worse outcome than a gap, and the orchestrator has recorded the ownership. B62's `clear` semantics remain R5's, because the store is R5's; the *route* is R3's | none in R5 — R3's fixture test against `signout.json` covers it |
| B93 | *(merged into B79 — the re-index rejection source)* | — |
| B94 | Two `log.info` lines are required verbatim: `authorized upstream "<name>"`, emitted **between** the 200 page write and `settle()` (`auth.ts:220`), and `approved "<name>"'s new tool surface (<n> tools)`, emitted **before** the 200 (`control.ts:362`) | log-capture test asserting text and ordering |
| B95 | The completion side-effect of B79 reaches the router through an **injected port**, not through the route function's `(status, body)` return — a value-returning function has no channel for a continuation that outlives the response, and §1's shape would otherwise be unsatisfiable together with B79 | type-level: the route function takes the port as a parameter; a spy proves the continuation is registered |
| B96 | `cleanup`'s final step is guarded: `if (current?.flow.server === serverName) current = undefined` (`auth.ts:242`). Clearing unconditionally diverges — a superseded flow's late callback would null the flow that replaced it | red-green test: supersede A with B, then drive A's callback, then assert `currentFlow()` still reports B |
| B97 | `authorizedAt(server)` returns the record's `authorizedAt` verbatim or undefined (`auth.ts:56-58`), and `codeVerifier()` **throws** `no PKCE code verifier saved for "<server>"` when absent (`auth.ts:126) — a reachable path with a fixed message | test per function incl. the throw's message |
| B98 | *(folded into B77 — `isStdio` definition)* | — |
| B99 | Both 400 paths and the 500 path pass the literal `Authorization failed` as `title`, which `PAGE` renders into **both** `<title>` and `<h1>` (`auth.ts:156-161`). The timeout's rejection message is `authorization timed out` (`auth.ts:233`) | byte test per page asserting the full emitted string |
| B100 | B61's warning is verbatim `auth record for "<server>" unreadable (<err.message>); treating as unauthorized` (`auth.ts:40`) — pinned to the character, as B79's is | log-capture test |


## 4 · The two open items R3 handed over

**`isLive`/`clearPending` take Swift `String` (closed here as B80, and downgraded).** Swift `String`
equality is canonical: `"\u{00E9}" == "\u{0065}\u{0301}"` is `true`; JavaScript's is code-unit, and
the same pair is `!==`. The brief presents this as live. **It is not.** `ServerParser` refuses any
name outside `[A-Za-z0-9_-]+` (`Config/ServerParser.swift:106-112`), and additionally refuses `__`,
so no name carrying a combining mark is ever adopted and the two spellings cannot both reach a port.
B80 keeps the `JSString` typing because that gate exists to make names usable as tool namespaces,
not to make them comparison-safe — relax it and the divergence becomes live with nothing to catch it
— but **R5 reports no live bug fixed here**, and the earlier draft's claim that this would let one
request read another's record is withdrawn.

**B69 vs B71 — resolved here, as a spec defect.** These two clauses cannot both hold, and this spec
is where that is written down, `spec-R3.md` never having been amended.

- **B69** requires every attribution failure path to yield an *empty* identity, "never a partial one".
- **B71** requires resolved values to **equal** what the reference resolves for the same connection.
- The reference emits `{ pid, client, cwd: cwd || undefined }` — a **partial identity is the
  reference's own behaviour** when `cwd` is falsy. Satisfying B69 therefore breaks B71 by
  construction.

**The amendment.** B69 is scoped to its four enumerated *peer-identification* paths — no such pid, a
pid exiting mid-scan, a non-TCP socket, unlistable descriptors — each of which must still yield a
wholly empty identity. The **`cwd` case is named as an explicit exception**: a resolved pid and
client with an absent `cwd` is a *complete* identity by the reference's definition, not a partial
one, and B71 governs it. This is the same shape as B12's carve-out for its two 422 bodies, and is
adopted for the same reason: the general rule is right and one enumerated case is genuinely outside
it. Whichever item builds attribution inherits B69 in this scoped form.

Two attribution facts inherited from `ai/r3`, recorded so R5's reader does not rediscover them:
a pid whose `proc_name` lookup fails used to escape as a bare `{pid}` — which the reference cannot
produce, since it reads pid and command from a single `lsof -Fpc` record — and is now `.unknown`;
and B70's cache, previously unimplemented, exists as `AttributionCache` following the reference's
order exactly: consulted after pid resolution and **before** the cwd lookup, with `set` then
`if size > 512 { clear() }` — checked *after* the insert, so the 513th pid empties the cache
wholesale rather than evicting one entry.

## 5 · The state matrix — real copy for the unhappy paths

Design representation: `design/mocks/auth-callback-pages.html`, with the emitted pages as byte-exact
files under `design/mocks/auth-pages/`. Verified rendering (see §7).

| State | Surface and the copy that carries it |
|---|---|
| Default | Success page — `<h1>` *“linear is connected”*, `<p>` *“You can close this tab and return to mcp-router.”* |
| Empty | Structurally impossible: the page renders one outcome for one flow and has no collection. Recorded, not invented. |
| Loading | Real but unowned. `finishAuth` is awaited **before** the first response byte, so the browser's own indicator covers the whole exchange. No skeleton without reordering the response, which parity forbids. |
| Partial | Unreachable. `saveTokens` writes `tokens` and `authorizedAt` in one write; there is no half-authorized record. |
| Error | Three pages: the provider's `error` value verbatim (400); *“the provider returned no code”* (400); the exchange exception's message (500). All name what happened; none blames; none emotes. |
| Success | In place — the page **is** the state change. The app learns separately, via `completed` clearing pending and re-indexing (B79). |
| Offline | The router is not running ⇒ nothing binds 8880 ⇒ the browser's own refusal page. Not ours to render; the recoverable surface is M8's. |
| Disabled | Stdio cannot authorize: **400** *“stdio servers do not authorize; their credentials are env vars”* (B77). The reason travels with the refusal; no page is served. |
| Overflow | A long name is interpolated into `<h1>` untruncated and wraps. Reference behaviour, kept for parity, recorded as a defect rather than presented as a design. |

## 6 · Two security findings in the reference — reported, not patched here

Both are **cross-cutting**: fixing either in Swift alone makes the Swift router diverge from the
TypeScript one, which is exactly what R4's differential gate exists to catch. R5 implements to
parity and escalates.

- **Reflected HTML injection.** `PAGE(title, detail)` interpolates without escaping, and on the
  provider-refused path `detail` is the raw `error` query parameter. During a flow, any page the
  user is browsing can reach `http://127.0.0.1:8880/callback?error=<markup>` and have it rendered on
  that origin, and can settle the flow as failed. Bounded — the listener exists only during a flow
  and that origin holds nothing else — but it is script execution from an untrusted parameter.
- **No `state` validation.** The callback reads `code` and `error` and never checks the CSRF `state`
  nonce, so a forged callback can drive `finishAuth` with an injected authorization code. PKCE binds
  the verifier and blunts it. Worth knowing: the Swift SDK's
  `OAuthAuthorizationCodeFlow.extractCode` **does** enforce `expectedState`, so an R2 transport built
  on it acquires the check for free — and thereby diverges from the reference. That collision needs
  deciding before R4, not during it.

## 7 · Assumptions carried forward

1. **The callback pages are a byte contract, not a design surface.** They use `#141220`/`#eae8f5`/
   `#a6a2c4`, which are not DESIGN.md tokens (`--ground #1E1E1E`, `--t1`, `--t2`). DESIGN.md is
   authoritative for UI decisions, but R3 B65 calls these *the recorded pages* and R4 diffs them.
   Restyling inside R5 would fail the gate that proves the port faithful. **Deferred child** (§8),
   scheduled after R4's cutover and changing both routers in one commit.
2. **The transport stays injected.** `beginAuth(name, makeTransport:, timeoutMs:)` keeps the
   reference's seam, so R2's SDK-backed transport lands without editing this module. R5 ships a
   protocol plus a test double, not a live transport.
3. **`AuthStore` conformance is one line, deferred.** `FileAuthStore` is written with the exact
   signatures R3's `ControlPorts.AuthStore` declares. After R3 merges, `extension FileAuthStore:
   AuthStore {}` completes it. R5 does not declare the protocol.
4. **Render verification.** obscura's rasterizer does not composite nested browsing contexts, so the
   contact sheet's frames photograph flat; `contentDocument` assertions prove all five hold the right
   DOM, and each page was additionally captured as a top-level document, which is how a user meets it.

## 8 · Escalations and deferred children — for the orchestrator, not registered here

| Item | Suggested deps | Why it is not R5 |
|---|---|---|
| Wire `POST …/auth` and `POST …/approve` into `ControlHandler`'s dispatch (2 `case` lines each) | after R3 merges | The file exists only on `ai/r3` |
| Restyle both callback pages to DESIGN.md tokens, in **both** routers, one commit | after R4 | Changing them before parity fails R4's own gate |
| Escape `PAGE`'s interpolations, in both routers | after R4, or expedited by decision | Security; parity-coupled |
| Validate the `state` nonce on the callback, in both routers | after R4, coupled to R2 | The Swift SDK enforces it and the reference does not — a decision, not a port |
| Amend `spec-R3.md` §H B69 to the scoped form written in §4 | with R3 | R5 records the resolution; only R3 can edit its own spec |

## 9 · The out-of-family gate — a logged downgrade

**`codex gpt-5.6-sol` was unavailable.** Two probes, including a one-word liveness check, both
returned `You've hit your usage limit … try again at Aug 20th, 2026 1:29 PM` with an empty `-o`
file. That is an account-level limit past this fleet's horizon, not a per-call failure. Recorded as
**`codex: usage limit → claude (downgrade)`** and reported to the orchestrator, because it degrades
the same three gates for every runner in the fleet.

The substitute was a fresh `claude-opus-5` reviewer sharing no context with this spec's author,
briefed adversarially and told a reviewer who finds nothing has not reviewed. Reviewer ≥ writer
holds (opus reviewing opus). It returned **22 findings; 22 accepted, 0 rejected** — every one
verified against the cited reference line before acceptance. Three would have shipped as defects:
B85 (a superseded flow is cleaned up but never settled, so structured cancellation diverges), B83
(the 404 precondition, which made the original B78 answer 409 for an unconfigured server), and B80's
evidence, which asserted through a filesystem that conflates the two cases on APFS and so proved
nothing.

The residual weakness is real and travels with this spec: **every reviewer on R5 has been Claude.**
The family's shared blind spot is unmeasured here. Re-running the three gates against `gpt-5.6-sol`
after Aug 20, before R4's cutover, is the cheapest way to close it.

## 10 · Acceptance

Both routes emit the reference's byte shape, proven against F3's recorded fixtures without altering
them; all five terminations, the non-termination (B82) and the two pre-flow 502s (B84) are each
exercised by a test rather than described; the superseded-flow non-settlement (B85) is proven by a
bounded wait; no record, token or `Authorization` header appears in any log; names are code-unit
keyed at the key level (B80); and the parity vector total clears 224 with the auth vectors
individually tagged (B81).
