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
