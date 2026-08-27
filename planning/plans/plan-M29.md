# plan-M29 — a server that is present and not served

Spec: `planning/specs/spec-M29.md` · brief
`planning/features-to-triage/M29-disable-a-server-is-drawn-with-nothing-behind-it.md`
Design of record: `design/mcp-router-console.html` (settled 2026-08-22)
Plan size: **Standard**. No new unit of architecture in either stack — every change is a field or a
branch added to a type that already exists, and `warm` is a complete working analogue of the whole
path, from `UpstreamBase` through the config hash, the PATCH allow-list, `describe()`, `MCPServer`,
the subtitle precedence and `ServersBoardWrites`. What makes it wider than a one-file change is
that the router has **two implementations held in byte-for-byte parity**, so every edit is made
twice and compared.

Baseline: `bbdc14b` on `ai/m29`, worktree `.worktrees/M29`, tree clean. That baseline carries R18
(`c6dd377`) and R20 (`b637adf`), both of which this item's §3.1 decision depends on.

---

## 1 · Task

Give the router a third state — declared, and not served — and make the two places the design of
record draws it real: the Servers row that reads `Disabled by you`, and the held-change sheet's
destructive `Disable <server>` button that the build currently ships as `Remove <server>`.

The item is **not** "add a boolean". The boolean is four lines. The work is (i) making the *serving
surface* a closed, enumerated set rather than one function, (ii) making the same change twice
under a gate that diffs bytes, and (iii) not disturbing the reference defect at
"if (!entry || entry.tools.length === 0) continue;", `src/manifest.ts:436` at `9c48d2d` that this feature is most likely to be absorbed into.

---

## 2 · Approach

One predicate, added at the top of the existing scoping predicate, adopted by every site that
decides whether a server runs.

```ts
/** Whether this server is served to a caller in `cwd` at all. */
export function isServed(u: UpstreamConfig, cwd: string | undefined): boolean {
  return !u.disabled && visibleTo(u, cwd);
}
```

**Why a predicate rather than an inline test.** `unionTools` is not the only place that decides.
There are five, they were enumerated by reading the code rather than recalled, and a disable that
covers only the first is a disable in name (spec §4, D5):

| # | Site (TS) | Site (Swift) | What leaks without the check |
|---|---|---|---|
| 1 | "if (!visibleTo(u, opts.cwd)) continue;", `src/manifest.ts:434` at `9c48d2d` (`unionTools`) | `ToolUnion.swift` `unionTools` | the tools stay on `tools/list` |
| 2 | `if (!visibleTo(upstream, who.cwd)) {`, `src/router.ts:196` at `9c48d2d` (`tools/call` guard) | `if !ToolUnion.visibleTo(upstream, cwd: identity.cwd) {`, `MCPEndpointToolCall.swift:60` at `9c48d2d` | the tools stay callable by name |
| 3 | "const warm = [...this.upstreams.values()].filter((u) => u.warm);", `src/pool.ts:453` at `9c48d2d` (`warmUp`) | `let warm = orderedNames.compactMap { upstreams[$0] }.filter { $0.warm == true }`, `UpstreamPoolReaping.swift:104` at `9c48d2d` | a warm+disabled server is spawned at boot |
| 4 | "if (u?.warm) return;", `src/pool.ts:435` at `9c48d2d` (reap skip) | `if config.warm == true { return }`, `UpstreamPoolReaping.swift:28` at `9c48d2d` | **a warm+disabled server is never reaped** — it stays resident forever, serving nobody |
| 5 | "const stale = upstreams.filter((u) => isStale(manifest, u));", `src/index.ts:199` at `9c48d2d` and `:228` + "if (isStale(manifest, upstream)) toIndex.push(upstream);", `src/watch.ts:233` at `9c48d2d` | the Swift index/watch sweeps | the automatic sweeps spawn it to index it |

Row 4 was not in the spec and is not cosmetic: `if (u?.warm) return;` skips the reap timer
entirely, so disabling a warm server today would produce a resident child process with no route to
it. It is added to the acceptance oracle as line 13.

**What is deliberately not touched.** `if (!entry || entry.tools.length === 0) continue;` at
`src/manifest.ts:436` and its Swift twin stay byte-identical, including the skip-order defect
`ToolUnion.swift` documents as a deliberately-ported reference behaviour. This item adds a check
*above* it and changes nothing below it. `upstreamHash` is not touched in either router, which is
what mechanically delivers spec §3.1.

---

## 3 · Slices

**Gating order, not merely file order.** Slices A, B, C and E are **one gating unit** and are
built before any gate is believed: `make parity` and `parity-control.sh` run both binaries against
each other, so a TypeScript `describe()` that reports `disabled` while the Swift port does not is a
red that means nothing. Slice C re-records the Kit fixtures from the reference, so it runs after A.
Slice D depends on C's `MCPServer.disabled` and is built last. Within A+B the files are disjoint
and may be written in parallel; they are gated together.

### Slice A — the TypeScript reference

| File | Change |
|---|---|
| `src/config.ts` | `UpstreamBase.disabled?: boolean` with the doc comment saying what it means and that it is not hashed; `RawServer.disabled?: boolean`; both `parseServer` branches pass `disabled: s.disabled` through. **`upstreamHash` untouched** |
| `src/manifest.ts` | export `isServed(u, cwd)`; `unionTools` calls it in place of `visibleTo`. Lines 436 onward unchanged |
| `src/router.ts` | the guard at 196 becomes two branches: `u.disabled` answers *"Upstream "x" is disabled. Enable it in MCP Router to use its tools."*; the existing scoped message is otherwise unchanged, verbatim |
| `src/pool.ts` | `warmUp` filters `u.warm && !u.disabled`; the reap skip at 435 becomes `if (u?.warm && !u.disabled) return;` |
| `src/index.ts`, `src/watch.ts` | the three automatic sweeps filter `!u.disabled` before `isStale`. **`isStale` itself is not changed** — it answers a question about the cache, and a disabled server's cache really is stale or not on its own terms |
| `src/control.ts` | `describe()` gains `disabled: !!u.disabled`, positioned beside `warm`; PATCH accepts `disabled` **last** in the field order, as `if ('disabled' in b) s.disabled = b.disabled \|\| undefined;` |

**Two ordering constraints, both load-bearing and both discovered by reading the Swift port.**
`disabled` goes **last** in PATCH's field order because `ConfigEdit` appends an unknown member at
the end, so the member order in the user's `servers.json` is compared byte for byte; and because
`ControlAPIRequest` hardcodes the 400 text *"Cannot use 'in' operator to search for **'projects'**
in …"*, which is the reference's *first* `in` test — putting `disabled` first would change that
message and redden a row that has nothing to do with this feature.

`describe()`'s `disabled` is `!!u.disabled` — JS truthiness over the raw value, matching `warm`,
because `key: "warm", value: .bool(upstream.raw.member("warm")?.isTruthy ?? false)`, `Describe.swift:133` at `9c48d2d` reports `warm` as `.bool(upstream.raw.member("warm")?.isTruthy ?? false)`
and a typed read would diverge on `"disabled": "yes"`.

### Slice B — the Swift router (RouterCore)

Mirrors slice A exactly. `UpstreamConfig.swift` (`disabled: Bool?`),
`projects: raw.member("projects")?.asArray?.map(\.jsDisplayString)`, `ServerParser.swift:84-86` at `9c48d2d` (`disabled: raw.member("disabled")?.asBool`, beside `warm`),
`ToolUnion.swift` (`isServed`), `if !ToolUnion.visibleTo(upstream, cwd: identity.cwd) {`, `MCPEndpointToolCall.swift:60` at `9c48d2d`,
`if config.warm == true { return }`, `UpstreamPoolReaping.swift:28` at `9c48d2d` and `:104`, the Swift index/watch sweeps,
`ControlHandler.swift` `patch(_:name:deps:)` (a fifth `supplied("disabled")` arm **after**
`placard`, shaped exactly like the `warm` arm's truthiness coercion), and
"/// `projects` and `warm` — one nullish default and one truthiness coercion, deliberately", `Describe.swift:123-134` at `9c48d2d` (`disabled` beside `warm`, read from `raw` with `isTruthy`).

`UpstreamHash.swift` is not touched. Confirm by diff that it is not.

### Slice C — the Kit contract

| File | Change |
|---|---|
| `ServerPatch.swift` | `disabled: Bool?`; `permittedWireKeys` gains exactly `"disabled"`; `forbiddenWireKeys` unchanged; `encode(to:)` gains one `encodeIfPresent`, `init(from:)` one `decodeIfPresent`. `ControlContractTests` already asserts all three ways and must be extended, not relaxed |
| `Models.swift` | `MCPServer.disabled: Bool` — **non-optional**, beside `warm`, per spec D1 |
| `Fixtures/*.json` (8 files) | re-recorded, not hand-edited, via `scripts/capture-control-fixtures.sh` after `npm run build`. It runs a real router against a scratch `HOME` with no network, so this is reproducible |

Non-optional is the decision with a consequence: every recorded fixture must carry the key or
decoding throws. That is the point — a router that stopped reporting `disabled` should fail loudly
rather than render a disabled server as live.

### Slice D — the Mac app

| File | Change |
|---|---|
| `ServerPresentation.swift` | `ServerSubtitle.forServer` gains `if server.disabled { return ServerSubtitle(text: "disabled by you", tint: .t3) }` **first**, above `inFlight`. First because a disabled server that is also holding a change, also unauthorised and also index-errored is, before any of that, not serving anything |
| `ServerPresentation.swift` | `ServerRowAction` gains `case enable` (label `Enable`), returned first in `forServer`; `ServerRowModel.tools` becomes `Int?`, nil exactly when disabled |
| `JackPresentation.swift` | a disabled server's jack is `.dormant`; its word is `disabled` rather than `dormant`/`warm` |
| `cell("\(row.tools)", width: ServersBoardMetrics.toolsColumn, tint: .t2)`, `ServersBoardRow.swift:79` at `9c48d2d` and `:113` | the tools cell renders `—` for nil; the accessibility label says `tools withheld` rather than an empty string, so the row is not silently ambiguous to VoiceOver |
| `ServersBoardWrites.swift` | `setDisabled(_ name: String, to: Bool)` beside `setWarm`; `perform(_:on:)` gains the `.enable` arm |
| `board.request(.removeInstalledCapability, subject: serverName)`, `ServerSheets.swift:181` at `9c48d2d` | the held-change sheet's destructive button becomes `Disable \(serverName)` calling `board.setDisabled(serverName, to: true)`, dimmed with `This server is already disabled.` when it is. Replaces `Remove \(serverName)` — which stays reachable at `board.request(.removeInstalledCapability, subject: server.name)`, `ServerInspectorSections.swift:155` at `9c48d2d` and `model.serversBoard.request(.removeInstalledCapability, subject: selection)`, `ShellCommandRouter.swift:282` at `9c48d2d`, verified by grep before and after |

`MenuCommand` is not touched (spec D3).

**`needsAttention` must change, and the plan previously said it need not.** The out-of-family
review caught this and it is the largest correction in the plan. `ServerFilter.needsYou` is
`server.needsAttention || server.placard != nil`, and `MCPServer.needsAttention`
(`public var needsAttention: Bool {`, `Models.swift:109-111` at `9c48d2d`) is `pendingChange != nil || (auth.supported && !auth.authorized) ||
indexError != nil`. A disabled server holding a schema change satisfies all of it, so spec A1
does **not** fall out of the existing cases. The blast radius is wider than the board: the same
property feeds `case .serversNeedingAttention: servers.filter(\.needsAttention).count`, `ReadoutModel.swift:218` at `9c48d2d`, `waiting > 0 || servers.contains(where: \.needsAttention)`, `MenuBarPresentation.swift:137` at `9c48d2d` and `:150` and the Servers
sidebar badge, so without this a disabled server would put a count on the menu bar for a decision
nothing can act on and nothing is exposed to.

| File | Change |
|---|---|
| `public var needsAttention: Bool {`, `Models.swift:109` at `9c48d2d` | `needsAttention` becomes `!disabled && (pendingChange != nil \|\| (auth.supported && !auth.authorized) \|\| indexError != nil)` — one edit, five consumers corrected |
| `ServerPresentation.swift` | `ServerFilter.needsYou` becomes `!server.disabled && (server.needsAttention \|\| server.placard != nil)`, because the `placard` limb sits outside `needsAttention` |

The record is not lost, only the summons: the held change stays on `MCPServer.pendingChange` and
stays visible in the inspector. Suppressing the badge while keeping the record is what *disabled by
you* means — the user already made the decision the badge would be asking for. Recorded as spec D11.

### Slice E — the gates' own inputs

`app/Tests/RouterCoreTests/Vectors/parse-server.json` and `upstream-hash.json` gain disabled cases
(the hash vector's job here is to prove the digest does **not** move). `planning/parity/surface.tsv`
row `control-server-patch` has its note extended to name the new field; **the census pin does not
move**, because no row is added or removed — `disabled` is a field on an existing route, not a new
route, and `parity-manifest-check.sh` derives control rows from route strings.

---

## 4 · Test strategy

**Seams, agreed here so the worker never picks one.** All existing:

- `app/Tests/RouterCoreTests/*ParityTests.swift` + `Vectors/*.json` — the vector registry, for
  anything that is a pure function of config (`isServed`, the hash, `parseServer`).
- `app/Tests/MCPRouterKitTests/ControlContractTests.swift` — the `ServerPatch` wire contract.
- `app/Tests/MCPRouterKitTests/ServerPresentationTests.swift` — the row rules, over the cross
  product rather than examples, which is how the warm-above-running rule is already asserted.
- `app/Tests/MCPRouterUITests/ServersBoardWriteTests.swift` — the write path.
- `scripts/acceptance/parity-control.sh` — the two routers on the wire.
- The TypeScript reference has **no unit harness in this repo** (`package.json` declares no test
  script and there is no `test/`). Its behaviour is gated by `tsc`, by the parity lane comparing it
  against the Swift port, and by `scripts/e2e.mjs`. This is stated rather than worked around: TS
  changes here are covered *through* the parity lane, and a TS-only regression that the Swift port
  reproduces identically would pass. That is a real limit of this repo's gates and it is not
  M29's to close.

**Falsifiable at the base commit.** Each acceptance line names the observation that shows it false
at `bbdc14b`, and each fails there today because no `disabled` concept exists — grep for `disabled`
across `src/*.ts` and `app/Sources/RouterCore/` returns nothing, so lines 1-8 and 13 fail by
construction, and 9-12 fail to compile.

| Oracle line (spec §7) | Test |
|---|---|
| 1 tools withheld, manifest intact | `ToolUnionParityTests` vector: manifest with 3 tools + `disabled: true` → 0 tools out, `manifest.servers[x].tools.count == 3` after |
| 2 digest unmoved | `upstream-hash.json` vector: the same upstream with and without `disabled` hashes identically |
| 3 call refused, own reason | `MCPEndpointToolCallTests` asserts the *text*, and a negative control asserts a scoped-and-not-disabled server still gets the project message |
| 4 not warmed | `UpstreamPoolReapingTests`: `warm: true, disabled: true` → `warmUp` opens nothing |
| 13 **reaped despite warm** | same suite: the reap timer is armed for `warm: true, disabled: true` and not for `warm: true` alone |
| 5 sweeps skip, reindex does not | the index-sweep test plus a `POST /servers/:name/reindex` acceptance case |
| 6 PATCH round-trips | `parity-control.sh` scenario + `ControlBoardRoutesTests` |
| 7 command/args/env still refused | `ControlContractTests` — the existing three assertions, plus `permittedWireKeys == ["projects","warm","idleMs","placard","disabled"]` exactly |
| 8 both routers agree byte for byte | `parity-control.sh`, scenarios: describe a disabled server, PATCH it true, PATCH it false, PATCH a malformed `disabled` |
| 9 subtitle wins the precedence | `ServerPresentationTests` over the cross product of `disabled × pendingChange × auth × placard × indexError × warm × state` |
| 10 tools withheld in the model | same suite, both directions |
| 11 the action is `Enable` | same suite, and a negative control that a non-disabled server never returns `.enable` |
| 12 the sheet's button | `ServersBoardWriteTests` + `MockButtonFidelityTests` |
| 14 A1: a disabled server is in `all` and `idle`, never in `needsYou` | `ServerPresentationTests`, asserted **with** `pendingChange`, `indexError`, an unauthorised credential and a placard set, since those are the four inputs that would otherwise carry it there |
| 15 a disabled server contributes 0 to `needsAttention` | `MenuBarPresentationTests` and `ReadoutModel`'s own suite — the badge, not just the filter |
| 16 the enable action dims in place while in flight and the row never disappears | `ServersBoardWriteTests` |
| 17 a failed enable renders `ControlAPIError`'s own wording, no new phrasing | `ServersBoardWriteTests`, asserting the string comes from the error rather than a literal |
| 18 the row's accessibility label carries `disabled by you` and `tools withheld` | `ServersBoardRow`'s existing accessibility test — the mock marks `aria-disabled` on the row and every cell (`2066-2074`), and the app's analogue is the spoken label, not `.disabled(true)`, which would make the row unselectable and strand the `Enable` action |

**Red-green.** `scripts/red-green.py` is this repo's mutation record. Six arms, each run against
only the test it names, required green before the mutation and issue-recorded by name after — the
discipline M20's gap-fix established. **Ids must not be `M29`**: `scripts/red-green.py` already
uses `"M20"` as a *mutation index*, a different namespace with the same spelling, and M19 found
four `M29`s in those tables. Use `DIS-1`…`DIS-6`.

| Arm | Mutation | Kills |
|---|---|---|
| DIS-1 | `isServed` returns `visibleTo(u, cwd)` (drops the disable term) | the unionTools vector |
| DIS-2 | the reap skip reverts to `if (u?.warm) return;` | the reap-timer test |
| DIS-3 | `disabled` added to `upstreamHash`'s material | the hash vector |
| DIS-4 | the subtitle branch moved below `pendingChange` | the cross-product test |
| DIS-5 | `permittedWireKeys` gains `"command"` | `ControlContractTests` |
| DIS-6 | `needsAttention` drops its `!disabled` term | the `needsYou` filter test **and** the menu-bar badge test — one mutation, two suites, which is what proves the fix landed at the shared seam rather than in the board alone |

DIS-5 exists because the standing constraint it guards is the one a `permittedWireKeys` edit is
most likely to break by accident, and an arm that only proves the new field works would not see it.

**Visual / state coverage.** Read off spec §5. `make mock-fidelity SURFACE=servers` runs on the
`ideal` frame, which is the frame the mock's disabled row lives in. The build does not draw that
row today, so the census may move. **The floors in `planning/fidelity/servers.layers.json` are a
ratchet and are raised only with the measured before/after in the commit message** — never lowered,
and never adjusted to make the gate pass.

## 5 · Parity inventory

This routes an existing flow (server visibility) through a new predicate, so every behaviour of
the old path is marked.

| Behaviour of `visibleTo` / `unionTools` today | Disposition |
|---|---|
| Empty or absent `projects` means everywhere | **keep** — untouched inside `visibleTo` |
| Scoped server + unidentifiable caller = not served | **keep** — untouched |
| Lexical prefix match, no path normalisation, case-sensitive | **keep** — `ToolUnion.swift` documents why; not entered |
| `if (!entry \|\| entry.tools.length === 0) continue;` and its three meanings | **keep, unchanged, and unfixed** — spec §3.2. The new check sits above it |
| Skip-order defect: a zero-tool entry is dropped before the placard is considered | **keep** — a deliberately-ported reference defect with its own deferred child; fixing it here would diverge the two routers |
| `placardFor` prefers a declared placard over `entry.error` | **keep** — disable is a fourth thing, not a placard. Placard keeps tools *listed* and answering; disable unlists them |
| `isStale` treats a non-empty error as stale | **keep** — not entered; the sweeps filter around it instead |
| PATCH's fixed field order and its `'projects'` 400 text | **keep** — `disabled` is appended last precisely to preserve both |
| `tools/call` refuses an out-of-scope server with the project message | **keep, and ordered** — `disabled` is tested **first**, so a server that is both disabled and out of scope is refused as *disabled*. Evaluating `visibleTo` first would emit a true-but-misleading sentence about the project, and spec D6 is the rule it would break |
| `needsAttention` summons the user for a hold, a refused credential or a failed index | **narrowed, deliberately** — a disabled server summons nobody. See the table above; this is the one old behaviour this item changes rather than preserves |

## 6 · Audit coverage

This repo has no audit-emit surface — no `emitAuditRecord`-equivalent, no coverage registry, no
tenant data and no multi-user surface. The router writes a usage log (`src/usage.ts`) which is
telemetry the user reads, not an audit trail, and this feature adds no row to it. Stated in one
line rather than omitted, so the silence is not read as forgotten.

## 7 · Out of scope

Everything here is already an accepted assumption or a filed child in the spec, so there is no
narrowing: DEF-M29-a (per-project deny-list, spec §3.3), DEF-M29-b (the Router-menu commands, spec
D3), DEF-M29-c (the inspector's `⋯` menu, which the mock does not draw). Killing a running child
process on disable is assumption A3 and is deliberately not done. The "if (!entry || entry.tools.length === 0) continue;", `manifest.ts:436` at `9c48d2d` defect is
explicitly not fixed (spec §3.2). No requirement of the brief is left uncarried.

## 8 · Gates

`make lint`, `make test`, `make build-mac`, `npm run build`, `make parity`,
`scripts/acceptance/parity-control.sh`, `make mock-fidelity SURFACE=servers`,
`scripts/red-green.py` for the six arms. Each reported with its exit code, and a gate that could
not run is reported as that rather than as a pass.


---

## 9 · Gate note

**Mechanical path check — pass.** 35 backtick-quoted paths extracted; every directory-qualified
one resolves. Thirteen are bare basenames used inside a table whose directory its own row
establishes, and each resolves to exactly one file in the tree. Separately, **all 17 line-number
citations were read back** ("if (!visibleTo(u, opts.cwd)) continue;", `src/manifest.ts:434` at `9c48d2d`, `if (!visibleTo(upstream, who.cwd)) {`, `src/router.ts:196` at `9c48d2d`, "if (u?.warm) return;", `src/pool.ts:435` at `9c48d2d` and `:453`,
`if !ToolUnion.visibleTo(upstream, cwd: identity.cwd) {`, `MCPEndpointToolCall.swift:60` at `9c48d2d`, `if config.warm == true { return }`, `UpstreamPoolReaping.swift:28` at `9c48d2d` and `:104`, "const stale = upstreams.filter((u) => isStale(manifest, u));", `src/index.ts:199` at `9c48d2d` and `:228`,
"if (isStale(manifest, upstream)) toIndex.push(upstream);", `src/watch.ts:233` at `9c48d2d`, `warm: raw.member("warm")?.asBool`, `ServerParser.swift:85` at `9c48d2d`, `key: "warm", value: .bool(upstream.raw.member("warm")?.isTruthy ?? false)`, `Describe.swift:133` at `9c48d2d`, `cell("\(row.tools)", width: ServersBoardMetrics.toolsColumn, tint: .t2)`, `ServersBoardRow.swift:79` at `9c48d2d` and `:113`,
`board.request(.removeInstalledCapability, subject: serverName)`, `ServerSheets.swift:181` at `9c48d2d`, `board.request(.removeInstalledCapability, subject: server.name)`, `ServerInspectorSections.swift:155` at `9c48d2d`, `model.serversBoard.request(.removeInstalledCapability, subject: selection)`, `ShellCommandRouter.swift:282` at `9c48d2d`) and
each contains the text the plan attributes to it.

**Out-of-family review — `gemini-3.7-flash-high` via `agy --new-project`, bounded 540s, exit 0,
on-subject.** The codex lane is unavailable in this repo by standing instruction, so it was not
probed; `grok-4.6 --effort xhigh` had already answered the decision fork out of family
(`planning/evidence/M29-decisions-grok.md`), so the item carries two families. Six findings,
dispositioned:

| # | Finding | Disposition |
|---|---|---|
| 1 | `ServerFilter`/`needsAttention` claim is false — a disabled server holding a change still matches `needsYou` | **Accepted, and widened.** The reviewer named the board; reading `needsAttention`'s consumers showed the badge, the menu-bar band and the readout model too. §3 slice D and spec D11 now carry it, with arm DIS-6 |
| 2 | Missing tests: A1's filter, the enable-in-flight state, the error banner, the accessibility label | **Accepted.** Oracle lines 14-18 |
| 3 | Parity inventory omits the disabled-vs-scoped precedence in `tools/call` | **Accepted.** Two rows added to §5 |
| 4 | Slices are lettered A-E but the text said "3 and 4" | **Accepted.** Rewritten as an explicit gating order, which was the real gap the typo hid |
| 5 | `disabled` above `inFlight` in the subtitle hides an in-flight enable | **Rejected, with reason.** `MCPServer.inFlight` is the router's count of in-flight *tool calls* on that server, not the app's mutation state; a disabled server has none by construction. The `Enabling…` state the reviewer means lives in the action slot, which oracle line 16 covers. Ordering unchanged |
| 6 | No enforcement site missed | **Confirmed**, independently of the plan's own reading |

Status → **Ready for AI**.
