# spec-M29 — a server that is present and not served

| | |
|---|---|
| ID | M29 |
| Status | Ready for AI |
| Category | router · mac · third server state |
| Depends on | R18 ✓ (digest retention across a failed index) · R20 ✓ (healthy-server preservation) · M8 ✓ (the held-change sheet this replaces a button on) |
| Related | M16 (the Servers board this adds a row state to) · M18 (filed this item while inventorying the gate table) · R7 / R16 / M22 (none of them claimed the behaviour) |
| Brief | `planning/features-to-triage/M29-disable-a-server-is-drawn-with-nothing-behind-it.md` |
| Source mock | `design/mcp-router-console.html` — the design of record, settled 2026-08-22 |
| Triage | 2026-08-25 (verdict in `planning/features-to-triage/LEDGER.md`, row M29) · §3 records the three decisions triage delegated to the planner |
| Plan | `planning/plans/plan-M29.md` |

---

## 1 · Feature description (the brief, verbatim)

> # "Disable a server" is a gate-table row with no action behind it, and no owner
>
> M18 inventoried every sheet in `design/mcp-router-console.html` and built the gate each
> destructive decision passes through. One row of that table has no implementation anywhere and
> no item claiming it.
>
> **The measurement.** `ServerPatch` carries no field that disables a server. The control API's
> PATCH is the only channel the Mac app has — `command`, `args` and `env` are never writable
> through it by standing constraint — and nothing in it expresses *present but not served*. No
> ledger row claims the behaviour: it is not R7's, not R16's, not M22's, and M18 declined to
> invent it rather than shipping a control that does nothing.
>
> **Why this is not simply "build it".** Disabling a server is a third state between adopted and
> removed, and the product currently has two. The router either serves a server's tools or does
> not know about it. A third state has to answer questions nobody has answered:
>
> - Does a disabled server keep its manifest row, its digest and its approved tool set? If it
>   does, `R18`'s failed-index handling and `R20` both write that row and need to agree with it.
> - Does `unionTools` skip it by a new `disabled` flag, or by the same emptiness test that
>   `R18`'s verdict has just established is doing a job the error field should do? Adding a third
>   reason for a server to serve nothing, into a function that currently infers the reason from
>   the data's shape, is how that defect got there.
> - Is it per-harness or global? The owner has just decided the product works **per-project**, so
>   a server disabled in one project and live in another is now expressible and probably
>   intended.
>
> **What this item is.** Not a build order — a decision plus the build that follows it. The
> sheet is drawn, so the design has already implied an answer; whoever triages this should read
> what the mock draws and say whether that is the intended semantics or an artifact of drawing a
> plausible-looking table.
>
> **Do not close this by removing the row from the gate table.** The table is generated from the
> sheets that exist in the design of record, and deleting a row to make an inventory agree with
> an implementation is the inverse of the check.

---

## 2 · What the design of record actually draws

The brief asks whoever triages this to read the mock rather than infer. Read, at
`design/mcp-router-console.html`:

| Line | What is drawn |
|---|---|
| `2066-2074` | A servers-table row for `sift`, `class="trow disabled"`, `aria-disabled="true"` on the row and on every cell |
| `2070` | Its state cell reads **`Disabled by you`** beside an unlit dot — the same cell that reads `Dormant`, `Needs sign-in` and `Live` on other rows |
| `2069` | Its **Tools** cell is an em-dash, **not `0`** — and the row two above it (`pocketsmith`, *Needs sign-in*, no working tools at all) reads `2`. The em-dash is therefore not a zero |
| `2073` | Its **Last** cell reads `4 d ago` — preserved, so the router still knows when it last answered |
| `3945` | The held-schema-change sheet's destructive footer button reads **`Disable mobbin`** |
| `2094` | The inspector's `⋯ More actions` button exists; **its menu is not drawn**, so where else disable lives is not specified by the mock |
| `1392-1404` | The Router menu is drawn in full and carries **no disable item** |

Three things follow, and each closes a question rather than leaving it open.

**The em-dash is load-bearing.** A disabled row whose Tools cell showed a number would be
claiming a served capability. A disabled row whose Tools cell showed `0` would be claiming the
server has no tools, which is false and is what `pocketsmith` above it correctly does not claim.
An em-dash claims nothing, which is the only honest reading, and it is only *available* as a
reading if the router still knows the count. That is §2's answer to the brief's first question
arriving through the drawing rather than through argument.

**`Last: 4 d ago` cannot be drawn if the row is discarded.** The usage log survives independently
of the manifest, but the row is dimmed and still populated on every axis the router observes.

**The menu bar is drawn in full and does not carry this command.** `DESIGN.md`'s kit rule 9 says
the menu bar is the complete command surface. The design of record disagrees with that rule for
this command specifically, and this item takes the design of record — see §4, D3.

---

## 3 · The three decisions

Triage (2026-08-25) recorded that all three are the planner's, not the owner's. Both out-of-family
lanes were consulted with the real code in the prompt and the option order swapped between them;
`gemini-3.7-flash-high` (via `agy --new-project`) and `grok-4.6 --effort xhigh` returned the same
three answers independently. Evidence: `planning/evidence/M29-decisions-agy.md`,
`planning/evidence/M29-decisions-grok.md`.

### 3.1 · (a) A disabled server keeps its manifest row, its digest and its approved tool set

**Decided: it keeps all of it.** Disabling never writes to `manifest.json`, and `disabled` is
absent from `upstreamHash`, so the cache is not invalidated by the toggle.

The mechanism is already in the codebase and needs no new rule: `upstreamHash` (`src/config.ts:98`)
hashes only transport identity — `['stdio', command, args, cwd ?? null, sorted env]` or
`[transport, url, sorted headers]`. `projects`, `warm` and `placard` are all outside it for the
same reason, because none of them changes what the upstream advertises. `disabled` is the fourth
member of that family, and putting it in the hash is the only way to get the wrong answer here.

Three reasons this is the right direction rather than the convenient one:

1. **The alternative launders an approval.** The action that motivates the feature is the
   held-schema sheet: a server rewrote a tool description, the router is holding it, and the
   user's response is *disable this*. If disabling discarded the manifest row, re-enabling would
   re-index against nothing and the surface the user just refused would arrive as a first sight
   and be approved on the spot. R18 exists so that a missing digest cannot do this; discarding the
   row on disable would recreate the same hole through a different door.
2. **The em-dash requires it.** §2 above.
3. **Re-enabling would otherwise spawn the process the user turned off**, to learn something the
   router already knew, which is the cost the router exists to avoid.

What the losing option is genuinely better at, stated rather than dismissed: **A2 forces a cold
probe on re-enable**, so an upstream that changed its tools while dark cannot be served from a
stale approved set. That is a real property and this item does not have it. It is not lost,
though — it is relocated: `POST /servers/:name/reindex` is the explicit user-driven route and
stays available on a disabled server (§4, D4), and the kept digest is what the next index compares
against, which is R18's whole subject. The difference is that the probe is asked for rather than
implied by a toggle.

### 3.2 · (b) `unionTools` skips a disabled server by an explicit config check, before the manifest is read

**Decided: a new predicate over `UpstreamConfig`, in the same position and shape as `visibleTo`.**
Not the emptiness test.

`src/manifest.ts:436` is `if (!entry || entry.tools.length === 0) continue;`. Since R18 landed,
that one expression carries three distinct meanings — never indexed, index failed with the digest
preserved, and genuinely serves nothing — and the function does not read `entry.error` at all. The
brief names the hazard exactly: a third reason for a server to serve nothing, pushed into a test
that infers the reason from the data's shape, is how that defect got there. Taking B1 would also
force A2, which §3.1 has already refused.

The change is one predicate that both routers share:

```ts
/** Whether this server is served to a caller in `cwd` at all. */
export function isServed(u: UpstreamConfig, cwd: string | undefined): boolean {
  return !u.disabled && visibleTo(u, cwd);
}
```

`unionTools` then reads `if (!isServed(u, opts.cwd)) continue;` where it read `if (!visibleTo(...))`,
and the existing manifest checks below it are **left byte-identical** — including the ported skip
order that `ToolUnion.swift` documents as a deliberately-preserved reference defect. This item
does not fix that defect and does not disturb it.

What B1 is genuinely better at: making the disable true in the *data*, so a later call site that
forgets the config check still serves nothing. That is real, and the answer is that the serving
surface is small and enumerated (§4, D5) rather than open-ended.

### 3.3 · (c) `disabled` is a global boolean; per-project off-ness stays `projects`' job

**Decided: `disabled?: boolean`.** Not a per-project deny-list, and not both.

The brief's reasoning is that the per-project decision makes "disabled here, live there"
expressible. It is — and it is *already* expressible, through `projects`, which is the allow-list
that says exactly this and which both routers already enforce on listing and on call. The question
a deny-list answers that an allow-list does not is "everywhere **except** this one repo, without
enumerating the others". That need is real and currently inexpressible, and this item deliberately
does not close it (§6, DEF-M29-a).

Three reasons the global boolean is right here:

1. **The action that motivates the feature is a kill switch.** A server whose tool descriptions
   changed under the user is not untrusted in one directory. `Disable mobbin` on the held-change
   sheet has to mean everywhere or it means very little.
2. **The surface that shows the state is global.** The Servers board is a whole-router table with
   no project selector anywhere in the design of record. A per-project disable would have to be
   rendered as a count in a table that has no column for it, or drawn as flatly "Disabled by you"
   when it is only partly true — which is §6's defect in its literal form.
3. **A deny-list beside an allow-list needs a composition rule that nothing in the product can
   show.** `projects: [A]` together with disabled-in `[A]` has an answer, and no surface in the
   design of record can display which answer it took.

What the losing option is genuinely better at, again stated: a deny-list expresses "off in this
one repo" without listing the rest, and per-project disable is what a machine holding several
clients' work would eventually want. It wants its own surface first — a project selector on the
Servers board — and that surface does not exist.

---

## 4 · Recorded decisions and assumptions

| | Decision | Why, and what it beat |
|---|---|---|
| D1 | `disabled: boolean` is reported on `GET /servers` for **every** server, non-optional on the wire, exactly as `warm` is | The alternative is an optional the client defaults to `false`. A silently-false `disabled` renders a disabled server as live, which is precisely the class of claim §6 forbids. Non-optional means a router that stopped sending it fails to decode instead |
| D2 | The router sends `disabled` as a fact; the app's existing precedence chain gains one branch. **No derived `status` enum on the wire** | `ServerSubtitle.forServer` / `JackState.forServer` already resolve seven conditions into a row state, UI-free and host-free. A router-side enum would be a second precedence, computed in both routers under a byte-for-byte parity gate, and it cannot encode the overlap this feature creates — the sheet disables a server *that has a hold*, so `disabled` and `pendingChange` are true at once. Both out-of-family lanes reached this independently |
| D3 | **No menu-bar command and no accelerator.** `MenuCommand` is untouched | `DESIGN.md` kit rule 9 asks for one; the design of record draws the Router menu in full (`1392-1404`) and does not carry it. This item takes the design of record over the rule, because inventing a menu item the mock does not draw is the failure the brief's closing paragraph names, and it would redden M20's counted menu assertions on a surface M29 does not own. Filed as DEF-M29-b rather than silently skipped |
| D4 | `POST /servers/:name/reindex` still works on a disabled server. The **automatic** index sweeps skip it | Re-index is the user asking; the sweeps are the router deciding. A disabled server that is never indexable cannot be inspected before re-enabling, and one the startup sweep still spawns is not "not served" in the only sense that costs anything |
| D5 | The serving surface is enumerated, not assumed: `unionTools` (list), the `tools/call` guard, `pool.warmUp()`, and the two automatic index sweeps. Each takes the check | This is the answer to what B1 was better at (§3.2). A closed list is checkable; "the predicate exists" is not |
| D6 | A disabled server's `tools/call` is refused with **its own reason**, not the scoped-server message | `Upstream "x" is not available in this project` is a false statement about a globally disabled server. Two branches, two sentences |
| D7 | The held-change sheet's destructive button becomes `Disable <server>`, replacing `Remove <server>` | The mock draws `Disable mobbin` at `3945`; the build shipped `Remove` because disable did not exist. Remove has a strictly larger blast radius — it deletes the config entry and its unrecoverable secrets, which `RemoveServerDialog` documents at length. Remove stays reachable from the inspector (`ServerInspectorSections.swift:155`) and the shell command router, so no path is orphaned |
| D8 | A disabled row's one action is **`Enable`** | The mock draws no enable control, and shipping a one-way disable whose only reversal is hand-editing `servers.json` is a defect rather than a design decision. The row-action slot is the app's own mechanism and already carries `Reset` in the same shape. Recorded as an addition to the mock rather than a reading of it |
| D9 | A disabled row's Tools cell is withheld (`ServerRowModel.tools` becomes `Int?`), not zeroed | §2. The model carries the withholding so it is unit-testable without a host, which is where every other row rule in this app lives |
| D10 | `disabled` does not enter `upstreamHash`, in either router | §3.1. This is what mechanically guarantees the manifest row survives |
| D11 | A disabled server **summons nobody**: `MCPServer.needsAttention` gains a `!disabled` term, and `ServerFilter.needsYou` gains one for the `placard` limb that sits outside it | Found by the out-of-family plan review, which correctly said A1 does not fall out of the existing cases; reading `needsAttention`'s consumers widened it from the board to the sidebar badge (`Destination.swift`), the menu-bar band (`MenuBarPresentation.swift:137,150`) and `ReadoutModel.swift:218`. A disabled server holding a schema change would otherwise put a count on the menu bar for a decision nothing can act on and nothing is exposed to. The **record survives and only the summons is dropped** — the hold stays on `pendingChange` and stays visible in the inspector, which is what *disabled by you* means |

**Assumption A1.** A disabled server still appears in the Servers board's `All` and `Idle`
filters and does **not** appear in `Needs you`, nor in any attention count. It is a state the user
chose, not one asking for them. This costs a real edit rather than falling out of the existing
cases — see D11. Overturned by an owner who wants disabled servers hidden from the default view,
or who wants a held change to keep summoning while the server is off.

**Assumption A2.** The subtitle text is `disabled by you`, lower case, tint `--t3`. The mock's
state cell is `Disabled by you`; §6 asks for sentence case and this cell is a subtitle rather than
a sentence start, matching `dormant` and `warm · never reaped` beside it. `--t4` is refused
because `DESIGN.md:138` reserves it for disabled *controls* and never live text; the row-level dim
is the view's job.

**Assumption A3.** Disabling does not close a server's live child process. The reaper closes it
on the ordinary idle path, and killing a process from a config edit is a second behaviour the mock
does not draw. A disabled server that is currently running is served to nobody from the moment the
config reloads, which is what the state means.

No Essential Questions. Nothing here needs the owner before the build starts.

---

## 5 · State matrix

The surface is the Servers board (`ideal` frame) and the held-change sheet. Real copy, not
placeholder.

| State | Servers row | Held-change sheet |
|---|---|---|
| Default (live) | unchanged | destructive button reads `Disable mobbin` |
| Disabled | row dims in place; state cell `disabled by you`; Tools `—`; Calls and Last preserved; action `Enable` | n/a |
| Disabled **and** holding a change | `disabled by you` wins the precedence — the hold is still recorded and still visible in the inspector, but the row says the thing that is true of the whole server | reachable, and its `Disable` button is dimmed with the reason `This server is already disabled.` |
| Disabled and index-errored | `disabled by you` wins; the error stays on `MCPServer.indexError` and is not lost | n/a |
| Enable in flight | the action dims in place with `Enabling…`, per `DESIGN.md`'s Disabled rule — dims, never disappears | n/a |
| Enable refused | the board's existing write-error banner carries `ControlAPIError`'s wording verbatim; no new phrasing | n/a |
| Router not answering | the row is part of the last reading and says so through the existing stale-reading path; `disabled` is configuration and survives a failed refresh, exactly as `all` and `needsYou` do | n/a |

---

## 6 · Deferred children

| Id | What | Why not now |
|---|---|---|
| DEF-M29-a | A per-project deny-list, so a server can be off in one repo without enumerating the others | §3.3. Needs a project selector on the Servers board before it has anywhere to be displayed honestly |
| DEF-M29-b | A `Disable Selected Server` / `Enable Selected Server` pair in the Router menu, satisfying `DESIGN.md` kit rule 9 | D3. The design of record draws the Router menu in full without them; adding them is M20's surface and its counted assertions |
| DEF-M29-c | The inspector's `⋯ More actions` menu, whose contents the mock does not draw | Out of scope for this item in both directions — nothing to be faithful to, and inventing it is what the brief forbids |

---

## 7 · Acceptance oracle

Every line is a behaviour, and each names what would witness it.

1. A server with `"disabled": true` in `servers.json` contributes **no tools** to `tools/list`, in
   both routers, with its manifest entry still present and its `tools` array still populated.
2. Its `hash` in `manifest.json` is byte-identical before and after the toggle, in both routers.
3. `tools/call` on one of its tools is refused, and the refusal names *disabled* rather than
   *not available in this project*.
4. `pool.warmUp()` does not open it, even with `"warm": true` alongside.
5. The automatic index sweeps skip it; `POST /servers/:name/reindex` does not.
6. `PATCH /servers/:name` with `{"disabled": true}` writes the field to `servers.json`, reloads,
   and the response body reports `disabled: true`.
7. `PATCH` still refuses `command`, `args` and `env` — `ServerPatch.forbiddenWireKeys` unchanged,
   `permittedWireKeys` gains exactly `disabled`.
8. Both routers answer the same bytes for a disabled server on `GET /servers`, `GET /servers/:name`
   and `PATCH`, under the existing control parity lane.
9. `ServerSubtitle.forServer` returns `disabled by you` for a disabled server whichever other
   conditions are also true, asserted across the cross product rather than on examples.
10. `ServerRowModel.tools` is `nil` exactly when the server is disabled.
11. `ServerRowAction.forServer` returns `.enable` for a disabled server and never `.reset`,
    `.reviewHeldChange` or `.beginAuthorization`.
12. The held-change sheet's destructive button reads `Disable <server>` and its dimmed reason is
    readable when the server is already disabled.
13. A `warm` server that is disabled **is reaped**. Today `src/pool.ts:435` returns before arming
    the reap timer for any warm server, so a disabled warm server would stay resident forever with
    no route to it. Found while enumerating the serving surface for the plan, not by the spec.
14. A disabled server appears under `All` and `Idle` and never under `Needs you`, asserted with
    `pendingChange`, `indexError`, an unauthorised credential and a placard each set in turn.
15. A disabled server contributes zero to `needsAttention` — the sidebar badge and the menu-bar
    band, not only the filter.
16. The `Enable` action dims in place while in flight; the row never disappears.
17. A refused enable renders `ControlAPIError`'s own wording rather than a second phrasing.
18. The row's accessibility label carries `disabled by you` and `tools withheld`. The app's
    analogue of the mock's `aria-disabled` is the spoken label, not `.disabled(true)`, which would
    make the row unselectable and strand the `Enable` action on it.
