# plan-R3: Swift router — control API, auth, usage, registry

**Spec:** `planning/specs/spec-R3.md` · **Plan size: Large** · **Branch:** `ai/r3`

Every rule the spec names as load-bearing is written out here as a table, because the review of
R1's plan established that a plan naming a mechanism without specifying it is a plan that gets
implemented from the reader's assumptions. Where R1 already ported something, this plan **consumes**
it and says so rather than restating it.

---

## What already exists, and is not rebuilt

`RouterCore` from R1 supplies the whole value layer this item needs:

| From R1 | Used here for |
|---|---|
| `JSString` (`[UInt16]`, code-unit equality and ordering) | every object key, every map key, `envKeys`/`headerKeys` sorting — S5 |
| `JSONValue` / `JSONMember` (ordered) | every request body and response body — S3, S4 |
| `JSStringify.compact` / `.prettyTwoSpace` | response bytes and `servers.json` bytes; fuzz-proven against Node |
| `JSONParser` | request bodies and on-disk JSON, preserving duplicate-key and index-ordering semantics |
| `ServerParser`, `UpstreamHash`, `ToolUnion.placardFor`, `DiffTools`, `ManifestIO`, `Manifest*` | `describe()`, `/changes`, `/approve` |
| `JSDate.iso8601`, `RouterClock`, `FileSystem` | timestamps and every injectable side effect |
| `ConfigWriter`, `ConfigLoader` | the `servers.json` read/modify/write path |

**Nothing in this item may reach for `JSONSerialization`, `JSONEncoder`, `Codable` or a Swift
`Dictionary` on a path that reaches the wire.** That is the single most likely way a delegated
slice silently defeats S3–S5, so P7 carries a lint that fails on it.

---

## P1 · The seams and the response model

Ports R2 will conform to, plus the request/response value types. Nothing here does I/O.

```
Sources/RouterCore/Control/
  ControlRequest.swift      method, encoded pathname, query items (ordered, first-wins), headers, raw body
  ControlResponse.swift     status, headers, body bytes, handled: Bool, or .stream(ControlStream)
  ControlPorts.swift        UpstreamPoolPort, UpstreamIndexerPort, AuthStore, and their doubles
```

**`ControlResponse` carries `handled`** rather than returning `Bool?` separately, so S8's
disposition cannot be dropped by a caller that only looks at the body.

| Port | Methods | Why it is a port |
|---|---|---|
| `UpstreamPoolPort` | `status() -> [LiveUpstream]`, `pending() -> [PendingAuth]`, `isLive(String) -> Bool`, `warmUp()`, `clearPending(String)` | R2 owns the pool |
| `UpstreamIndexerPort` | `index(UpstreamConfig) async -> IndexOutcome` | R2 owns spawning; this is `indexOne`'s seam |
| `AuthStore` | `hasTokens`, `authorizedAt`, `clear`, `record`/`save` | file-backed here, injectable for tests |

`status()` and `pending()` are searched **first-match** at every call site (B6, B7).

---

## P2 · Usage, and deterministic attribution

```
Sources/RouterCore/Usage/
  UsageRecord.swift     record + ServerStat as ordered JSONValue builders, not Codable structs
  UsageStore.swift      ring, aggregate, rotation, debounce, subscribe, reset, forget
  PeerResolver.swift    [landed] libproc attribution
  AttributionCache.swift pid-keyed, bounded at 512, cleared wholesale on overflow
```

**`ServerStat` is built in assignment order**, because that order is on the wire (B3):

| Step | Field | Rule |
|---|---|---|
| on first sight | `calls`, `errors`, `projects` | created together, in that order |
| every record | `calls` +1; `errors` +1 iff `!ok` | |
| first record only | `firstSeen` | `??=` — nullish, so an existing `""` survives |
| every record | `lastUsed` | assigned, so it lands after `firstSeen` on first sight |
| when `cwd` truthy | `projects[cwd]` +1 | key order per S4 |

**`readTail` reproduces the reference's defect (N5).** The reference computes a cut point from
`statSync().size` — a **byte** count — and applies it to `raw.indexOf('\n', offset)`, where `raw` is
a UTF-16 string. For a log containing non-ASCII text the two disagree. The port takes the same
byte-derived offset and indexes the same UTF-16 sequence, so it cuts where the reference cuts.

| Constant | Value |
|---|---|
| ring size | 500 |
| rotation threshold | 8 388 608 bytes, `>=` at the boundary |
| tail window | 524 288 bytes |
| flush debounce | 3 000 ms, on the injected clock |
| generations kept | 1 (`<path>.1`) |

**Attribution** (B67–B71): resolve at accept, synchronously, cache on the connection.

| Step | Call | Failure |
|---|---|---|
| 1 | `proc_listpids(PROC_ALL_PIDS)` | empty → unknown |
| 2 | per pid ≠ self: `proc_pidinfo(PROC_PIDLISTFDS)` | skip this pid, keep scanning |
| 3 | per socket fd: `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)`, require `SOCKINFO_TCP`, compare `insi_lport` (big-endian) | skip this fd |
| 4 | `proc_pidinfo(PROC_PIDVNODEPATHINFO)` → `pvi_cdir.vip_path` | cwd nil, identity still returned |
| 5 | `proc_name` → `client` | client nil, identity still returned |

Every step degrades to a *partial or empty identity*, never a throw (B69) — a process exiting
between step 1 and step 2 is the common case on a busy machine.

---

## P3 · Registry

```
Sources/RouterCore/Registry/
  RegistryEntry.swift   ordered JSONValue construction, official-shape and smithery-shape decoders
  RegistryMerge.swift   repoKey, dedupe, merge, rank
  GitHubEnrichment.swift cache, budget, rate-limit stop
  RegistrySearch.swift  the two fetches, warning collection, 502 boundary
  HTTPFetching.swift    protocol + stub, so no test touches the network
```

| Rule | Specification |
|---|---|
| `repoKey` | `/github\.com[/:]([^/]+)\/([^/.?#]+)/i` → `"<owner>/<repo>"` lowercased; no match → nil |
| dedupe key | `repoKey(repository) ?? displayName.lowercased().replacingOccurrences(of: /[^a-z0-9]/)` |
| merge | official row's members and order retained; `source` → `both`; `useCount`/`verified`/`iconUrl` take Smithery's when non-nullish; `install` keeps the official one when non-nullish |
| rank | `useCount` desc → `stars` desc → `updatedAt` via `localeCompare` desc; **stable**, so ties keep arrival order |
| `limit` | `min(Number(q ?? 30) || 30, 60)` — `0`→30, `NaN`→30, `500`→60, `-5`→`-5` |
| GH budget | 10 fetches per search; cache TTL 86 400 000 ms; first `403`/`429` sets `rateLimited` and stops further fetches |
| official install | first remote with a url → `{type: sse|http, url, requires}`; else first package: `npm` → `npx -y <id>[@ver]`, `pypi` → `uvx <id>`; else nil |
| smithery install | only when `remote && isDeployed` → the fixed URL shape with the Authorization requirement |
| failure | a throwing index adds a warning and yields `[]`; only a throw from the merge is 502 |

Sorting is implemented as a **stable merge sort over the arrival-ordered array**, never
`Array.sort` — Swift's sort is not guaranteed stable and B56 depends on stability.

---

## P4 · Auth

```
Sources/RouterCore/Auth/
  AuthRecord.swift      ordered read/write, 0700 dir, 0600 file
  FileTokenStorage.swift conforms to the SDK's TokenStorage
  AuthFlow.swift        beginAuth, currentFlow, cancel, timeouts
  CallbackListener.swift the fixed-port loopback listener + the two pages
```

| Rule | Specification |
|---|---|
| record path | `<AUTH_DIR>/<server>.json` |
| modes | directory `0700`, file `0600`, both on creation |
| unreadable record | warn, treat as unauthorized; never `try?`-to-default (B61) |
| callback port | `MCP_ROUTER_AUTH_PORT ?? 8880`, fixed — a registered `redirect_uri` must survive restarts |
| redirect uri | `http://127.0.0.1:<port>/callback` |
| second flow | cancels the first rather than failing to bind (B64) |
| url timeout | 20 000 ms waiting for the authorization URL |
| flow timeout | 300 000 ms overall |
| cleanup | on **every** termination: timer cleared, listener closed, transport closed, `current` cleared iff it is this flow |

The transport factory stays a **parameter**, exactly as the reference has it, so the SDK-backed
implementation can land with R2 without changing this file.

---

## P5 · The control handler

```
Sources/RouterCore/Control/
  ControlPaths.swift    isControlPath over the ENCODED pathname
  ControlToken.swift    controlToken, tokenOk
  Describe.swift        the describe() row
  ConfigEdit.swift      editConfigFile + reload, with D1/D2's refusal
  ControlHandler.swift  dispatch and every endpoint
```

**Dispatch order is the contract** (B22, S7):

| # | Stage | On failure |
|---|---|---|
| 1 | `isControlPath(encodedPathname)` | return **not handled**, touch no header, send nothing (B14) |
| 2 | if method ∈ {`POST`,`DELETE`,`PATCH`} (exact case): token | 401, handled |
| 3 | if mutating and method ≠ `DELETE`: content-type prefix | 415, handled |
| 4 | route regex `^/servers/([^/]+)(/[a-z]+)?$` | fall to step 7 |
| 5 | `decodeURIComponent(name)` | **throws** — propagates, no JSON reply (B23) |
| 6 | live-map lookup by JavaScript string identity | 404, handled |
| 7 | method dispatch; anything unmatched | 405 `<METHOD> not allowed on <pathname>`, handled |

**`describe()`**, field by field — the table the review said was missing:

| Field | Source | Coercion / omission |
|---|---|---|
| `name` | `u.name` | — |
| `transport` | `u.transport` | — |
| `state` | first pool row | `?? "idle"` (nullish) |
| `inFlight`, `callsServed`, `idleSec` | first pool row | `?? 0` — a live `0` survives |
| stdio: `command`, `args`, `cwd`, `envKeys` | `u` | `cwd` omitted iff undefined, `null` iff null; `envKeys` = key names sorted by UTF-16 code unit |
| http: `url`, `headerKeys` | `u` | same sort |
| `hash` | `UpstreamHash.hash(u)` | R1's |
| `tools`, `toolNames` | manifest entry | `ToBoolean(entry.error)` → `0` / `[]`, else cached count and names |
| `indexedAt`, `indexError` | `entry.builtAt`, `entry.error` | verbatim; omitted iff undefined |
| `projects` | `u.projects ?? []` | order and duplicates preserved |
| `warm` | `ToBoolean(u.warm)` | |
| `placard` | `ToolUnion.placardFor(u, entry)` | omitted iff nil |
| `pendingChange` | `{seenAt, count: DiffTools.diff(entry.tools, entry.pending.tools).count}` | omitted unless `ToBoolean(entry.pending)` |
| `auth` | `!isStdio && oauth !== false` | supported → `authorized`, `authorizedAt`, `pendingUrl` (first pending row), each omitted iff undefined |
| `usage` | `statFor(name)` **passed through unchanged** | else exactly `{calls:0,errors:0,projects:{}}` |

**Env and header values are unreachable by construction**: `Describe` builds from `envKeys`
only and never receives the pair arrays' values, and B10's canary sweep proves it (S8).

**`editConfigFile`** — one contract, used by all three call sites (B31):

| Step | Rule |
|---|---|
| 1 | read the file when it exists, else start from `{}` |
| 2 | **if the parsed root has no object-valued `mcpServers`, refuse** — D1, with the spec's copy. The reference creates an empty one and destroys the file |
| 3 | call the mutator on the ordered members in place; ignore its return |
| 4 | serialise `prettyTwoSpace`, **no trailing newline** |
| 5 | write `<path>.tmp-<pid>` at `0600`, then rename |
| 6 | a throwing mutator writes nothing |

**`reload`** re-parses, builds the full next map, then mutates the live containers in place —
map first, then the config array — so a holder of either sees the same instances (B31, D2's refusal
on an unrecognisable shape).

**PATCH** applies in fixed order `projects, warm, idleMs, placard`, each on key presence:

| Field | Rule |
|---|---|
| `projects` | `b.projects?.length ? b.projects : undefined` — a **property read**, so a string with a length is stored unchanged; a zero/absent length → **remove the member** (not null) |
| `warm` | `b.warm \|\| undefined` — a truthy value is stored **as given** (`warm: 1` writes `1`); falsy → **remove** |
| `idleMs` | assigned as given, including `0` and `null` (P2's ported inconsistency) |
| `placard` | assigned as given |

Then reload, then `warmUp()` **unawaited** iff `ToBoolean(b.warm)`, then reply 200 with the reloaded
row. `command`, `args`, `env` are simply not read — B40 proves the equivalence against the same
request with them deleted.

**Coercions**, one table so no slice invents its own:

| Input | Rule |
|---|---|
| `?force` | first value, `=== "1"` |
| `?keepHistory` | first value, `=== "1"` |
| `/usage?limit` | `Number(v ?? 200)`; `NaN` → `slice(-NaN)` → everything; negative → from the front |
| `/registry/search?limit` | `min(Number(v ?? 30) || 30, 60)` |
| body | `body ?? {}` is **nullish only**: `null`/absent become `{}`, while an array or primitive survives. A primitive body then throws on `'k' in b` rather than editing |

---

## P6 · Vectors, fixtures and the mutation gate

1. Extend `scripts/parity/generate-vectors.mjs` to drive `dist/control.js`, `dist/usage.js` and
   `dist/registry.js`, emitting vectors for every N-row and every coercion above.
2. Register the new vector files in `VectorRegistryFiles.swift` so A41's attestation counts them,
   and raise `executedFloor` — B76 requires the count to rise, so this item cannot pass by leaving
   the corpus where R1 left it.
3. Add the 23 fixtures as a **byte** oracle: each recorded response reproduced from constructed
   dependencies, never from a lookup (S6).
4. Extend `scripts/parity/mutation-gate.sh` with one mutation per new named behaviour — the
   *plausible* wrong implementation, not arbitrary damage: `!= nil` for `ToBoolean(error)`, Swift
   `<` for the code-unit sort, omitting `null` as if undefined, insertion order for S4, last-match
   for first-match, gating before `isControlPath`, rejecting rather than ignoring a PATCH's
   `command`. A mutation that fails to *apply* is reported as a failure, never a pass.

---

## P7 · Wiring, guardrails, gates

- `scripts/lint/no-wire-codable.sh` — fails on `JSONSerialization`, `JSONEncoder`, `JSONDecoder` or
  `[String:` under `Sources/RouterCore/{Control,Registry,Usage,Auth}`. The review's most repeated
  defeat was a reasonable Swift default; a lint is what stops a delegated slice reintroducing it.
- `make all` green; `make parity` reporting a count above R1's 224; `make mutation` green.
- `git diff main -- src/ install.sh package.json` empty (B74).

---

## Delegation

Phases P2, P3 and P4 are file-disjoint and may run in parallel. **P1 must land first** (everything
depends on the ports and the response model) and **P5 must land last** (it consumes all three).
P6 and P7 follow P5. Cap: three concurrent implementation agents, none of which may edit
`ControlHandler.swift`.

---

## Codex cross-family plan review — 2026-08-14

Reviewer: `gpt-5.6-sol`, read-only, `max` effort, one call over the spec, this plan and all four
reference files — `/tmp/gate-R3-plan.md`. **Wire header captured and verified**
(`model: gpt-5.6-sol`, `reasoning effort: max`, workdir `.worktrees/R3`); 12,739 bytes returned.
**Verdict: MATERIAL DEFECTS — 29 findings.**

Every finding asserting a fact about the reference was checked against `src/*.ts` before being
accepted, because a reviewer defending against a wrong port can also be wrong about it. Three were
**rejected on that check**: the code already did the right thing and only this plan's wording was
loose. That distinction matters — accepting them would have "fixed" working code into a divergence.

**Accepted 23 · rejected 3 · already-correct-in-code 3 · escalated 0.**

### Confirmed live defects, fixed on this branch

| # | Defect | Reference | Fix |
|---|---|---|---|
| 3 | `projects` was gated with `asArray`, so `PATCH {"projects":"x"}` **removed** the member | `s.projects = b.projects?.length ? b.projects : undefined` — a **property read**: `"x".length` is 1, so the reference stores it | `JSONValue.jsLengthIsTruthy`, red-green proven (B42) |
| 10 | `limit` used `Double(x) ?? .nan`, so `?limit=` was NaN and `?limit=%2012%20` was NaN | `Number("")` is `0`; `Number(" 12 ")` is `12` | `JSToNumber`, a real StrDecimalLiteral/radix implementation, red-green proven (B46, B54) |
| 9 | `localeCompare` had no implementation and `<` was the obvious substitute | ICU root collation: `"a".localeCompare("B")` is `-1` and `"A".localeCompare("a")` is `1`, both the reverse of code-unit order | `JSLocaleCompare` over ICU, pinned against **Node's own output** for the ISO domain plus the letter cases (N8) |
| 13 | Warning order and the merge pipeline were unstated | `Promise.all` plus two `.catch` pushes | Both fetches are issued before either is awaited; warnings are collected in **source order**. The reference's own order is whichever index rejects first in wall-clock time, which is not a reproducible contract — recorded as a timing-only divergence |

### Rejected — the finding is wrong about this branch's code

| # | Claim | Why it is rejected |
|---|---|---|
| 2 | "`warm` stores `true`, losing `warm: 1`" | The plan's table said that; `ControlHandler.patch` already does `set("warm", isTruthy ? warm : nil)`, storing the **raw** value. Plan table corrected instead |
| 7 | "a missing `servers.json` becomes `{}` and is then refused by D1, breaking the first add" | `ConfigEdit` already narrows the refusal to the trap shape — no `mcpServers` **and** other top-level members. An absent or empty config initialises normally |
| 12 | "an absent method cannot stringify to `undefined`" | The dispatcher already interpolates `request.method ?? "undefined"` (B25) |

### Accepted and still open

Carried into the completion note rather than silently closed. Findings 1, 4, 5, 6, 8, 11, 14, 15,
16, 17 and the Q2 block 18–29 are **completeness gaps**, and most name behaviour this plan failed to
specify even where the handler implements it. The ones that are genuinely undone:

- **17 — a real spec defect, not a plan defect.** B12 requires every error body to be exactly
  `{"error": …}`, but the reference answers a refused add with 422 `{error, hint}` and a failed
  reindex with 422 `{name, tools, error}`. B12 must be scoped to the generic `jsonError` branches
  with those two enumerated as exceptions; as written the three clauses cannot all hold.
- **1 — `isLive`/`clearPending` still take Swift `String`**, which is canonical-equivalence
  comparison where JavaScript uses code units. The map lookups already use `JSString`; these two
  port methods do not, so a composed/decomposed name can disagree across the seam (S5, B24).
- **5 and 27 — attribution.** The plan's failure table yields a *partial* identity where B69
  requires an empty one, and there is no differential measurement against `lsof` (B71).
- **6 — B68 needs R2's accept hook.** Nothing in `RouterCore` can install the resolver in an accept
  handler, so the timing half of the deferred child is a boundary item, not a `PeerResolver` one.
- **14, 26 — auth has no differential oracle and P4 is unbuilt.** See the completion note.
- **29 — B75's vector/mutation manifest is not written**, and `PARITY-VECTORS-EXECUTED` is still
  224, so **B76 is not met**.

### Phase D completeness critic — LANE FAILURE, downgraded in-family

Two attempts, both `gpt-5.6-sol` at `max`, both with the wire header verified and both returning
**no `-o` file**: `/tmp/gate-R3-phaseD{,2}.log`. The cause is diagnosed rather than guessed — the
model announced *"I'm using the code-review skill"* and emitted that skill's own workflow
documentation instead of the audit. The second attempt prefixed an explicit instruction to ignore
every `AGENTS.md`, `CLAUDE.md` and skill file in the repository, and it was hijacked the same way.
An empty `-o` is a lane failure, never a pass, so **the gate is recorded as failed and downgraded
in-family**, which is materially weaker evidence: it is Claude auditing Claude, exactly the thing
the out-of-family gate exists to avoid. Anyone re-running this item should treat R3 as **not
having had an independent completeness review**.

The in-family pass read `RegistrySearch.swift` against `src/registry.ts` and found three real
divergences, all fixed and red-green proven:

| Divergence | Reference | Was |
|---|---|---|
| `new URL('/v0/servers', base)` — an **absolute** path discards the base's own path | `https://h/x` → `https://h/v0/servers` | string concatenation kept `/x`, so a base carrying a path queried the wrong URL |
| An empty base **throws** `TypeError: Invalid URL` rather than defaulting | B59 preserves `""`; `new URL('/v0/servers','')` throws, and the message reaches the warning | `""` produced a relative URL and a stub-dependent failure |
| `cache[key] = rec` overwrites **in place** | the refreshed key keeps its slot | remove-and-append moved it to the end, rewriting the cache file's order every run |


---

## Close-out — 2026-08-14

What this plan asked for, and what shipped. Written for R4's reader, who needs to know which parts
of the port are proven and by what.

| Phase | State | Evidence |
|---|---|---|
| P1 seams and response model | delivered | `Control/ControlPorts.swift`, `ControlAPIRequest.swift` |
| P2 usage and attribution | delivered | `Usage/*`, `AttributionTests`, `UsageLogTests` |
| P3 registry | delivered | `Registry/*`, `RegistryTests`, `RegistryEnrichmentTests` |
| **P4 auth** | **moved to R5** | split out after this plan was written; `Auth/` is R5's |
| P5 the control handler | delivered | `ControlHandler.swift`, `ControlFixtureTests` |
| P6 vectors, fixtures, mutation gate | delivered | 352 vector cases · 35 mutations, all load-bearing |
| P7 wiring, guardrails, gates | delivered | `no-wire-codable.sh` wired into `make lint`; `make all` green |

**P6.4 finished here, and it was worth finishing.** The table had 24 mutations covering the
behaviours the earlier passes named. Adding the three this plan enumerated but the table lacked —
null-as-undefined, gating before `isControlPath`, rejecting rather than ignoring a PATCH's
`command` — and three more for behaviours nothing broke took it to 30, and **three of the six
stayed green**: B2's null `cwd`, B17's `Bearer` shadowing, and B40's command-line guarantee were
each unguarded. All had passing fixture tests. That is exactly the S6 failure the spec warned about,
and only this gate could have surfaced it.

A clause-by-clause sweep for *evidence* rather than for mentions then found B50 and B51 with no test
of any kind, and reading `src/usage.ts` to check the new rotation test asserted parity turned up one
live divergence: a failed rotation swallowed its error and appended anyway, where the reference's
single `try` skips the append. Five more mutations (R15–R19) close all of it.

**Final counts:** 359 tests in 57 suites · `parity: 352 vector cases (floor 352)` · `parity-regen`
reproduces the committed corpus from the reference exactly · 35/35 mutations red · the live
differential compares 32 rows against the running TypeScript router with 0 failures.

Full evidence, one row per clause with the commit it was verified at:
`planning/evidence/R3-acceptance.md`.
