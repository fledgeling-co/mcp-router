# F3: Typed control-API client and models

**ID:** F3
**Status:** In Progress
**Created:** 2026-08-14
**Last updated:** 2026-08-14

## Feature description

*Verbatim from `planning/features-to-triage/F3-control-client.md`.*

> # F3 — Typed control-API client and models
>
> **Depends on:** F1.
>
> The Mac app talks to the router **only** over the loopback HTTP control API. That is
> what lets the router be swapped from TypeScript to Swift underneath without the app
> changing, so this boundary must stay the sole interface.
>
> - Typed models for servers, skills, marketplaces, registry entries, usage rows, held
>   schemas, pairing state.
> - An async client with a live-updating stream for the call log and breaker states.
> - **The offline state is a first-class case, not an error banner:** the router is
>   loopback, so unreachable means "the router is not running" — say that and offer to
>   start it (DESIGN.md §5).
> - Auth: the control token, its storage in the Keychain, and its rotation.
> - A recorded-fixture test double so every UI surface's tests run without a live router.
>
> Source of truth for the surface: `src/control.ts`.

---

## Acceptance criteria

The oracle for every later stage. Each clause is independently verifiable; evidence must be a
measurement, an exercised request, or a red-green test — never "it looks right".

| # | Clause | Evidence type |
|---|---|---|
| A1 | A live client conforming to F1's `ControlAPIClient` reaches a **running router** over loopback and returns decoded servers | exercised request against a real router process |
| A2 | Connection refused on the loopback port maps to `.routerNotRunning`, and to nothing else — it is never folded into a generic transport failure | red-green test against a closed port |
| A3 | A `401` maps to `.unauthorized`, distinctly from `.routerNotRunning` | exercised request with a wrong token |
| A4 | A response whose shape this version does not understand maps to `.malformedResponse`; **no decode path's failure mode is an empty collection** | red-green test, incl. the flat-shape trap that bit the TypeScript router |
| A5 | The control token is read from the router's own token file and stored in the **Keychain** — never `UserDefaults`, never a plist, never a file beside the app | red-green test incl. an assertion that no token-shaped value reaches `UserDefaults` |
| A6 | Token **rotation** is handled: a `401` on a previously-good token re-reads the source, replaces the stored copy, and retries the request exactly once (never a retry loop) | red-green test with a rotated token, asserting the retry count |
| A7 | No token value, `Authorization` header, or whole-config object is ever logged — the shape may be logged, the value never | red-green test over the logging seam |
| A8 | Mutating requests carry `Authorization: Bearer <token>` **and** `content-type: application/json`, which is what the router's CSRF defence requires | captured request at a stub server |
| A9 | **The callable surface is enumerated, not incidental.** The client exposes one operation per control-API endpoint the apps need: list servers, get one, add, remove, re-index, list held changes, approve, patch, begin auth, sign out, usage, usage summary, reset usage, registry search. Modelling a shape without a way to call it does not satisfy this | a test that invokes **every** listed operation against a stub, and the same list exercised through the double (A18) |
| A10 | The call-log stream yields decoded records as they arrive, rather than on completion | exercised against a stub emitting events over time |
| A11 | The stream's reconnect policy is **stated and bounded**: first retry within 1s, doubling to a 30s ceiling, and after a stated number of consecutive failures it reports `disconnected` and stops rather than retrying forever | red-green test asserting the delays, the ceiling, and that retrying stops |
| A12 | Stream heartbeat comment lines (`: ping`, `: connected`) are ignored rather than decoded as events | red-green test |
| A13 | **Live breaker state is honest about its source.** The router serves no server-state feed — only the call-log stream — so live state is a merge of a periodic `GET /servers` refresh with call records arriving on the stream, and the merge rule is specified and tested. No server is shown in a state neither source observed | red-green test over the merge, incl. a call record arriving for an idle server |
| A14 | Every shape `src/control.ts` serves has a typed model — servers, one server, usage, usage summary, held-change list, registry search, and each write response | one decode test per endpoint against recorded fixtures |
| A15 | Fixtures cover the **distinct body and status variants**, not one happy path per endpoint: the `422 {error, hint}` on add, the structured `{name, tools, error}` re-index failure, stdio versus HTTP forms of a server, a held change present and absent, and an in-flight authorization present and absent | one decode test per variant |
| A16 | The router's `hint` on a refused add survives into the error value rather than being dropped — the advice that tells the user how to proceed reaches them | red-green test on the 422 fixture |
| A17 | Fixtures are **captured from a real router**, not hand-authored, and each is proven to still decode | capture script + decode tests |
| A18 | A fixture-backed test double conforms to the same protocol and implements **every operation in A9**, so a UI surface's tests run with **no live router** | test exercising every operation through the double |
| A19 | The double exposes a **named scenario per state** — the nine in `DESIGN.md` §5 and the three stream phases — and each asserts a specific observable outcome rather than merely existing | test enumerating each named scenario and its assertion |
| A20 | F1's standing guarantee holds: an encoded patch can never carry `command`, `args` or `env` | the existing red-green test, still green |
| A21 | `approvePendingChange` matches what the router **actually returns** (`{server, approved}`), rather than the `MCPServer` F1's protocol assumed | decode test against the real response shape |
| A22 | The in-flight authorization the router reports on the servers response is modelled, not dropped | decode test against a fixture carrying it |
| A23 | Closed sets on the wire stay closed in Swift: an unrecognised transport or state **fails decoding** rather than defaulting | red-green test per enum |
| A24 | **Model fidelity:** no model carries a field the router does not send, and a fixture round-trip loses nothing. (Display provenance belongs to the items that render; F3 ships no UI to inspect) | round-trip test per fixture |
| A25 | Every user-facing error string is asserted against its **exact approved wording** — the strings in the connection-state mock — so a reworded failure is a test failure rather than a silent drift | red-green test on exact strings |

**Explicitly out of scope for F3** — models for skills, marketplaces and pairing state. See the
first assumption below: the router serves no such data today, so a model for it could only be
invented, and the items that add those surfaces own their shapes. Also out of scope: the pairing
UI itself, the servers and activity boards, and any change to the TypeScript router.

---

## Triage — 2026-08-14

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** **nothing customer-facing ships in this item on its own.** This is the
  layer the Mac and iPhone surfaces are later built on. What it *does* fix is the set of
  conditions those surfaces show when things are not normal — so the states below are specified
  and mocked here, and every later screen inherits them rather than inventing its own wording.
- **What users will see — per surface:**
  - Connection-state kit (new, shared by every later screen): the "router isn't running" pane
    with a start action and the address it tried; the "not authorised" pane with a re-pair
    action; a first-run empty pane; a loading placeholder shaped like the real rows; a
    "some of it didn't arrive" summary with the reason on each affected row; a failure message
    that sits next to the row it belongs to; a control that dims in place and says why; and long
    names that shorten without the row changing height.
  - Live activity strip (new, shared): a small line saying whether updates are arriving, and if
    not, whether it is retrying or has given up — with a reconnect action only in the second case.
- **Behaviour changes:**
  - Screens can tell "the router is switched off" apart from "something went wrong", so the
    advice they give is the advice that actually fixes it.
  - Every later screen can be tested against all nine conditions without a router running.
- **Design reference:** `design/mocks/html/f3-connection-states.html` mocks every state above
  with its real wording — match its layout, states and copy.

**Assumptions**
- `[Data & scope]` Skills, marketplaces and pairing state are **not** modelled here. *(the router reports none of them today; a shape invented now is one the later items must contradict.)*
- `[Data & scope]` Everything the router does report is modelled, including the parts the foundation item missed. *(the boundary is only swappable if it is complete.)*
- `[Operations]` The saved credential is refreshed by re-reading the file the router itself writes, and the request retried once. *(a rotation is normal; making the user re-pair for it is not.)*
- `[Operations]` A retry happens once, never in a loop. *(a loop turns a wrong credential into a hang.)*
- `[Experience]` "Not running" and "not authorised" each replace the whole screen; every other failure stays beside the thing that failed. *(only those two make everything on screen untrustworthy.)*
- `[Experience]` A dropped live connection dims the rows already received rather than clearing them. *(deleting history to report a connection problem destroys data.)*
- `[Experience]` Retrying is automatic and silent; the reconnect action appears only once retrying has stopped. *(a button that duplicates what is already happening invites a pointless click.)*
- `[Layout]` The mocked kit is the reference for later screens; those screens supply their own content. *(one wording per condition across both devices.)*
- `[Compliance]` The saved credential goes to the system keychain and is never written to a log or a settings file. *(it authorises anything the router can do.)*
- `[Operations]` Test material is captured from the **installed TypeScript router**, which is the wire the Swift one must later match. *(hand-written samples record what we believe it sends, not what it sends.)*
- `[Experience]` Live "which servers are running" is refreshed on a timer and corrected the instant a call arrives, because the router publishes no running-state feed. *(the only two things it actually observes.)*
- `[Operations]` Retrying a dropped live connection stops after a stated number of attempts rather than continuing forever. *(an endless retry hides a router that has gone for good.)*

*If any of these are wrong, edit the answer inline (or correct an assumption) in this file and re-run `/triage F3` before the planner picks this up.*

**Cross-family review** — `gpt-5.6-sol` at `max` effort, read-only, grounded in the codebase.
Verdict on the first draft: **MATERIAL DEFECTS**. Five findings: **4 accepted, 1 accepted in part,
0 rejected.**

- *Accepted (High)* — modelling a shape without a way to call it satisfied the old wording; the
  callable surface is now enumerated and must be exercised end to end.
- *Accepted (Medium)* — one sample per endpoint cannot stand for every reply; samples now cover the
  distinct variants, and the advice the router attaches to a refused add must survive to the user.
- *Accepted (Medium)* — **the real one.** The description asks for live running-state as well as the
  live call log, and the router publishes no running-state feed at all. The old wording let that pass
  unexamined. Now stated: running-state is a timed refresh corrected by arriving calls, and nothing is
  shown that neither source observed.
- *Accepted (Medium)* — "the double can produce all nine states" had no way to be checked; each state
  is now a named scenario with its own assertion, and the "no invented figure" clause is limited to
  the data itself, since this item renders nothing.
- *Accepted in part (Low)* — error wording is now asserted against exact approved strings. The
  reviewer also reported the mock file missing; it is present, on this item's own branch rather than
  in the checkout it read, so that half is a checkout artefact rather than a defect.

The first attempt at this gate returned nothing: the CLI's cached model list was stale
(`missing field base_instructions`), which burns the whole budget and writes no output while still
printing a correct model and effort header. Cleared the cache, smoke-tested the lane, re-ran at the
specified effort. Recorded because it is a machine-level fault that silently degrades any gate.

## Plan — 2026-08-14

Implementation plan: `planning/plans/plan-F3.md` (Plan size: Standard).

No scope narrowing: every clause A1–A25 and every triage assumption is carried by a step. The plan's
"Out of scope" list repeats only what the spec already excluded — skills, marketplaces and pairing
models, the UI itself, and any change to the TypeScript router.


---

## Pause checkpoint — 2026-08-14

Written by the ORCHESTRATOR, not the runner: the runner died mid-turn on a gateway 503
(`no-eligible-account`, 9 of 11 accounts over reserve) and could not write its own.

**Pipeline position.** Phases 1-3 DONE. Phase 4 implementation COMPLETE and green — the
runner's last words before the 503 were: *"`make all` green — lint, both app builds, 93
tests. Now the red-green pass: every new guard has to be seen to fail, or it isn't a
guard."* It died entering the red-green proving pass.

**State on disk.** Branch `ai/f3`, 1 commit `2e7d9f3` — a RESCUE commit written by the
orchestrator, because the runner died with **28 files uncommitted and nothing on the
branch**. That commit is not a completed phase; it is preservation. `make test` exit 0
with **93 tests**.

Landed in it: `LiveControlAPIClient`, `ControlEventStream`, `ControlTokenStore`,
`FixtureControlAPIClient` + fixtures, `RegistryModels`, `ServerStateTracker`, a
`ControlProbe` target, and seven test files (client, copy, fixture, stream, token,
fixture-client, `HTTPStub`).

**Diagnosed but unfixed.** None recorded — the implementation was green when it died.

**Next three steps.**
1. The red-green proving pass it was entering: every new guard must be SEEN to fail. A
   suite that cannot fail is not evidence, and 93 green tests prove nothing until this runs.
2. Phase 5 gap-fix against the spec, then the Phase D out-of-family critic.
3. Phase 6 acceptance evidence, then Phase 7 commit and STOP before merge.

**Gotchas.** The gateway pool is shared with another live fleet in `~/Dev/hopper`; a 503
here is capacity, not your code. The `ServerPatch` test proving `command`/`args`/`env` can
never be encoded is a STANDING CONSTRAINT — keep it green.

**Re-read before continuing** (paths only): `planning/features-to-triage/F3-control-client.md`,
`planning/specs/spec-F3.md`, `planning/plans/plan-F3.md`, `src/control.ts` (the wire
authority), `planning/practices/SWIFT_PRACTICES.md`.

---

## Red-green proving pass — 2026-08-14

The pass the previous runner died entering. 93 green tests proved nothing until each guard had
been *seen to fail* (`SWIFT_PRACTICES.md` §7), so every guarded behaviour was broken one at a time
and the suite re-run. The harness is committed as `scripts/red-green.py` and is re-runnable:
`python3 scripts/red-green.py --json out.json`. It mutates **implementation only** — a mutation
that edits a test proves nothing — and restores the file afterwards.

**Result: 38 mutations, 38 killed.** First run killed only 17 of 29, and the twelve survivors are
the reason this pass exists. Three were real holes in the tests, three were my expectations being
wrong about which test owns a clause, three were equivalent mutants, and three were harness faults.

### The three real holes, and what closed them

| # | Clause | The hole | Fix |
|---|---|---|---|
| G1 | A11 | Every stream test built a `ReconnectPolicy` with **explicit** values, so the stated defaults were unasserted. The ceiling could move to 30000s and the attempt cap to 600 with the whole suite green — and A11's numbers are the clause. | New test `the stated policy is the one you get without asking` pins 500ms / 30s / 6 and re-checks the curve through the defaults. |
| G2 | A5 | The "no token in `UserDefaults`" test drove only `InMemoryTokenStore`, so `KeychainTokenStore.write` — the implementation that ships — was never called. A `UserDefaults.standard.set(token, …)` added to it left the suite green. A negative assertion that never runs the code it negates is worse than none, because it reports having checked. | The test now drives the real store through write/read/delete before sweeping `UserDefaults`, and the key-name check strips hyphens (the literal key `control-token` slipped the old `contains("controltoken")` test). |
| G3 | A13 | `a call record for a server the router never listed invents nothing` asserted only that no **row was added**. A merge resolving an unknown name onto a different server adds no row, and would have marked the wrong server running unnoticed. | The test now also asserts the listed server's state is untouched. |
| G4 | A12 | `heartbeat and greeting comments are ignored` collected **records only**, so a comment line made to emit `.phase(.live)` produced three spurious events and the test still passed. "Ignored" has to mean no event of any kind. | The test now asserts the whole event sequence — records, phases and total count. |

### Findings that were not defects

- **A12's comment skip is over-determined.** Deleting `if line.hasPrefix(":")` changes nothing
  observable, because the `data:` guard drops comment lines anyway and a comment that reached the
  decoder would fail it and be skipped. Heartbeats cannot become records by any single edit. The
  reachable regression is a comment emitting a *phase*, which is what G4 now catches.
- **`allowlistRejectsForbiddenKeys` deliberately never calls `encodedBody()`** — its own doc
  comment says so — so mutating that check cannot reach it. `encodedBody`'s two guards are proven
  instead by M27b (a forbidden key on the wire) and M28 (a merely-unpermitted one).
- **A nil `command` field is omitted by the encoder**, which is precisely the hole the
  stored-property check exists to close. One mutation cannot trip both halves; M27 and M27b are
  the two halves.
- **The tracker cannot invent a row by construction** — no code path builds an `MCPServer`; it only
  ever moves ones a poll supplied. That is stronger than a test, and the test covers the reachable
  corruption instead.

### Harness note worth keeping

The `UserDefaults` mutation writes to the test host's own domain
(`swiftpm-testing-helper`), which **survives the file restore** and then fails the *next* run for a
reason belonging to the previous one. The harness now scrubs it after every run. It cost a
confusing red; a mutation that touches a store outliving the process needs an explicit undo.

### The ledger

Every row: the mutation was applied, the suite ran, the named test went red, the file was restored.

| # | Clause | Guarded behaviour broken | File | Test that caught it |
|---|---|---|---|---|
| M01 | A2 | a refused loopback connection is its own case, not a generic transport error | `LiveControlAPIClient.swift` | a refused connection is routerNotRunning |
| M02 | A3 | a 401 is unauthorized and nothing else | `LiveControlAPIClient.swift` | a 401 is unauthorized (+1) |
| M03 | A4 | an unreadable shape fails loudly rather than as any other error | `LiveControlAPIClient.swift` | a shape this version doesn't understand fails loudly |
| M04 | A8 | a mutating request announces a JSON body — the router's CSRF defence | `LiveControlAPIClient.swift` | a mutating request carries the bearer token and the JSON content type |
| M05 | A8 | every request carries the bearer token | `LiveControlAPIClient.swift` | a mutating request carries the bearer token and the JSON content type |
| M06 | A8 | a read does not announce a body it is not sending | `LiveControlAPIClient.swift` | a read does not need to announce a JSON body |
| M07 | A6 | an unchanged token is not retried — the loop guard | `LiveControlAPIClient.swift` | an unchanged token is not retried |
| M08 | A6 | the retry happens exactly once, tracked per call | `LiveControlAPIClient.swift` | a rotated token is re-read and the request retried exactly once |
| M09 | A16 | the router's advice on a refused add survives into the error | `LiveControlAPIClient.swift` | a router error carries its status, its message, and the hint |
| M10 | A9 | a server name needing encoding still reaches its route | `LiveControlAPIClient.swift` | a server name needing encoding still reaches the right route |
| M11 | A12 | heartbeat and greeting comments are skipped rather than decoded | `ControlEventStream.swift` | heartbeat and greeting comments are ignored |
| M12 | A11 | the backoff doubles | `ControlEventStream.swift` | the delay doubles from the first retry |
| M13 | A11 | the backoff holds at a 30s ceiling | `ControlEventStream.swift` | the stated policy is the one you get without asking |
| M14 | A11 | retrying stops after the stated number of consecutive failures | `ControlEventStream.swift` | the stated policy is the one you get without asking |
| M15 | A11 | a connection that delivered anything resets the consecutive count | `ControlEventStream.swift` | a connection that delivered anything resets |
| M16 | A10 | records are yielded as they arrive, not batched at the end | `ControlEventStream.swift` | events arrive as they happen |
| M17 | A13 | an arriving call corrects an idle server to running | `ServerStateTracker.swift` | a call record marks an idle server running |
| M18 | A13 | a call for a server the router never listed invents nothing | `ServerStateTracker.swift` | a call record for a server the router never listed invents nothing |
| M19 | A13 | a poll is authoritative — a dropped server leaves no stale row | `ServerStateTracker.swift` | a poll removing a server removes it |
| M20 | A13 | the router's own ordering is preserved | `ServerStateTracker.swift` | the router's own ordering is preserved |
| M21 | A7 | a token is logged by its shape, never its value | `ControlTokenStore.swift` | the log records that a token exists and its length |
| M22 | A7 | an absent token is described as absent, not as an empty one | `ControlTokenStore.swift` | redaction describes an absent token as absent |
| M23 | A5 | the token goes to the Keychain and never to UserDefaults | `ControlTokenStore.swift` | no token-shaped value is ever written to UserDefaults |
| M24 | A5 | the token file is read as the router writes it | `ControlTokenStore.swift` | the token file is read as the router writes it |
| M25 | A5 | MCP_ROUTER_HOME moves the token file | `ControlTokenStore.swift` | MCP_ROUTER_HOME moves the token file |
| M26 | A23 | an unrecognised registry source fails decoding rather than defaulting | `RegistryModels.swift` | an unrecognised registry source fails decoding |
| M27 | A20 | a patch can never carry command, args or env | `ServerPatch.swift` | no stored property is named after a forbidden wire key (+1) |
| M27b | A20 | a non-nil forbidden field reaches the encoded JSON and is caught there | `ServerPatch.swift` | an encoded ServerPatch can never carry command (+2) |
| M28 | A20 | encodedBody's allowlist rejects a key that is merely unexpected | `ServerPatch.swift` | encodedBody emits only permitted keys (+1) |
| M30 | A15 | a recording nothing decodes is a failure, not an unused file | `orphan-shape.json` | no recording exists that nothing decodes |
| M29 | A19 | the offline scenario refuses in the one way that has its own surface | `FixtureControlAPIClient.swift` | the offline scenario refuses in the one way |
| M31 | A25 | the approved wording is the wording the client returns | `ControlAPIClient.swift` | the two whole-screen conditions read exactly as approved (+1) |
| M32 | A22 | an in-flight authorization on the servers response is modelled, not dropped | `Models.swift` | every fixture round-trips without losing or inventing a field (+1) |
| M33 | A21 | approve returns a count, not a server — F1's protocol assumed wrong | `Models.swift` | every fixture round-trips without losing or inventing a field (+1) |
| M34 | A15 | a failed re-index returns its structured outcome, not a collapsed error | `LiveControlAPIClient.swift` | a failed re-index returns its structured outcome |
| M35 | A16 | the typed-failure allowlist is per call site, so add's 422 stays a refusal | `LiveControlAPIClient.swift` | a router error carries its status, its message, and the hint |
| M36 | A6 | rotation compares against the token that was SENT, not the cached copy | `LiveControlAPIClient.swift` | two calls racing a rotation each retry once |
| M37 | A8 | a bodyless DELETE announces no body — the router exempts it by name | `LiveControlAPIClient.swift` | a bodyless DELETE carries the token and announces no body |

**Gate after the pass:** `make all` exit **0** — tools, lint, macOS build, iOS build, and
`executed 98 tests` (93 at the pause, plus five the pass and the gap-fix added).

---

## Gap-fix — 2026-08-14

Audited the delivered code against A1–A25, then put it through the out-of-family completeness
critic (`gpt-5.6-sol`, `max` effort, read-only). The critic found the one real contract break; the
rest came from following its narrower-claim observations to their end.

### The contract break (High) — a failed re-index could never be returned

`POST /servers/:name/reindex` answers **`422 {name, tools, error}`** when indexing fails
(`src/control.ts` ~line 326) — the *same* shape as its success, with `error` filled in. The client
routed every non-2xx through the generic `{error, hint}` path, so `reindex()` threw
`.server(status:message:hint:)` and `name` and `tools` were destroyed on the way out. A surface
could say "something went wrong" but not "0 of them indexed, fetch failed, on this row".

`ControlFixtureTests` decoded `reindex-failure.json` into `ReindexResult` and passed — because it
decodes the file directly and never goes near the client. **Modelling a shape without a path that
returns it** is the same defect the triage gate already caught once for the callable surface; it
recurred here for an error variant, where it is harder to see.

Fixed with a per-call-site `typedFailureStatuses` allowlist: `reindex` passes `[422]`, nothing else
passes anything. Deliberately not "422 is fine everywhere" — a 422 from `add` is a genuine refusal
whose `hint` is the sentence telling the user how to proceed, and decoding that as a typed success
would swallow exactly the advice A16 exists to preserve. Both directions are now tested (M34, M35).

### A real concurrency defect, found by taking the critic's question seriously

The critic asked whether A6's "retry exactly once" survives *concurrent* calls. It did — but the
answer was worse than a loop. `rotatedToken()` compared the re-read file against the client's own
`cachedToken`, so with two panes refreshing at the same moment: both send token A, the router
rotates to B, both get a 401, the first re-reads and stores B — and the second then finds B == B,
concludes nothing had rotated, and reports **`.unauthorized` for a credential that was fine**. A
spurious "re-pair" prompt that vanishes on the next refresh is close to the worst bug to be told
about, because it never reproduces for whoever reads the report.

Now compared against the token *that call actually sent*, so both retry once and both succeed. The
loop guard is unchanged: an unchanged file still means the credential is simply wrong (M07, M36).

### A19 was not met — `disabled` had no scenario

`DESIGN.md` §5's nine states include **Disabled**. The double had twelve scenarios and a test
asserting `count == 12`, described as "nine states plus three phases" — but the nine were only nine
because `unauthorized`, which is *not* one of them, was silently standing in for the missing
`disabled`. The arithmetic balanced, so the meta-guard passed.

Fixed properly rather than by renaming something: a placard is the router's own declaration that a
server is inoperative, carrying the reason and the substitute — exactly "dims in place with a
discoverable reason". `scripts/capture-control-fixtures.sh` now PATCHes a placard and records
`server-placarded.json` (captured from a real router, per A17), and `.disabled` serves it. The
count is now 13 with the arithmetic spelled out, so the next omission cannot hide inside it.

Adding the fixture immediately tripped the "no recording exists that nothing decodes" guard, which
is the guard working: a recording with no decode test is dead weight that agrees with everything.

### Two narrower-claim observations closed

- **DELETE headers.** The router exempts `DELETE` from its content-type requirement by name
  (`req.method !== 'DELETE' && !ct.startsWith('application/json')`). The client's branch was right,
  but only GET was asserted, so the branch that decides it was untested. Now covered (M37).
- **Fixture freshness.** All 24 committed fixtures were compared, key-path by key-path, against a
  fresh capture from a live router: **24/24 shape-identical**. Values differ (timestamps, ports,
  counters) and shapes do not, which is the A17 claim stated as a measurement rather than a hope.

### Assessed and deliberately not changed

- **Fixtures record bodies, not statuses.** A15's evidence type is a decode test per variant, which
  the bodies satisfy; the status pairing is asserted separately in the client tests against
  `src/control.ts`. Recording the status alongside each body would make the fixtures
  self-describing, and is filed as a deferred child rather than done here.
- **`RegistryInstall` carries `command` and `args`.** It is a *response* shape from
  `/registry/search` — what a third-party index said about how to run something. No client
  operation encodes it, and the only path to a command line on the wire is `NewServer` on
  `POST /servers`, which is the endpoint whose entire purpose is to accept one. A20 holds.

**Gates after the gap-fix:** `make all` exit **0**, `executed 98 tests`, zero compiler warnings in
F3's own sources; red-green **38/38 killed**; `scripts/acceptance/control-client.sh` **3/3 against a
real router**, and exit **2** (not 1) when the environment cannot run it.

