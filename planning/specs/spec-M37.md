# spec-M37 — the action that switches a server off

| | |
|---|---|
| ID | M37 |
| Status | Ready for AI |
| Category | mac · the affordance M29 left with no route |
| Depends on | M29 ✓ (the `disabled` state, its wire field, its readers and its row copy) · K5 ✓ (`ControlDisableWriteTests`, the read-back shape this item owes too) |
| Related | M16 (the Servers board) · M18 (filed M29 while inventorying the gate table) · M20 (owns the menu bar, and its counted assertions) |
| Brief | `planning/features-to-triage/server-disable-toggle-action.md` |
| Source mock | `design/mcp-router-console.html` — the design of record, settled 2026-08-22 |
| Plan | `planning/plans/plan-M37.md` |
| Tree everything below is measured at | `49eae13` |

---

## 1 · Feature description (the brief, verbatim)

> ## What and why
> Users can temporarily pause or disable an upstream server without deleting its registered
> configuration, arguments, or authentication credentials. Currently, stopping an upstream from
> being exposed to connected AI clients requires removing the server entirely and re-entering its
> configuration later. Providing an explicit active or disabled toggle allows operators to
> troubleshoot flaky servers or isolate tools during testing without losing saved configuration.
>
> ## Acceptance sketch
> - Each server listed in the management view displays an active or paused toggle state alongside
>   its status.
> - Disabling a server immediately hides its tools from connected clients without terminating
>   active client sessions.
> - Re-enabling a disabled server restores its tools to the active catalog without requiring
>   re-entry of tokens or environment variables.
> - Disabled servers remain visible in the configuration list with a distinct paused indicator.
> - Clients attempting to call a tool from a disabled server receive an informative refusal
>   indicating the server is paused.

---

## 2 · What is already built, and the one thing that is not

Four of the five sketch lines are M29's and shipped. This item is the fifth thing — the one the
sketch does not separate out, because from outside the product it looks like it must already be
there.

| Sketch line | Where it lives already | Left to do |
|---|---|---|
| Tools hidden from clients | `upstream.disabled != true && visibleTo(upstream, cwd: cwd)`, `app/Sources/RouterCore/Manifest/ToolUnion.swift:40` at `49eae13` | nothing |
| Re-enable keeps tokens and env | `disabled` is outside `upstreamHash`, so the manifest row, digest and approved surface survive (spec-M29 §3.1, D10) | nothing |
| Visible with a distinct indicator | the row dims, its state cell reads `disabled by you`, its Tools cell is withheld — `tools = server.disabled ? nil : server.tools`, `app/Sources/MCPRouterKit/Servers/ServerRowModel.swift:62` at `49eae13` | the **inspector** still claims a served count; §4 D3 |
| An informative refusal on call | `MCPEndpointToolCall`'s own branch, spec-M29 D6 | nothing |
| **A toggle the operator can actually reach** | **nowhere for an ordinary server** | **this item** |

**The measurement.** The *disable* direction ships in exactly one place: the destructive footer
button on the held-schema-change sheet — `Task { await board.setDisabled(serverName, to: true) }`,
`app/Sources/MCPRouterUI/Boards/ServerSheets.swift:230` at `49eae13`. That sheet is reachable only
while the router is holding a changed tool description for that server. Every other server in the
product — healthy, dormant, tripped, unauthorised — has no route into `disabled` from the UI at
all.

The *enable* direction is reachable, because M29's D8 put it in the row's action slot:
`if server.disabled { return .enable }`,
`app/Sources/MCPRouterKit/Servers/ServerPresentation.swift:186` at `49eae13`. So the product ships
a one-way reversal with no forward.

The write itself already exists and needs no change:
`func setDisabled(_ name: String, to disabled: Bool) async {`,
`app/Sources/MCPRouterUI/Boards/ServersBoardWrites.swift:76` at `49eae13`. **This item adds a
control, not a capability**, and that is what makes its risk a UI-honesty risk rather than a
router one.

---

## 3 · The decision this item had to take, and how it was taken

**Where the affordance lives.** Four candidates, each defensible:

- **A** — a third `ToggleRow` in the inspector's **Behaviour** section, beside `Keep warm` and
  `Only load in named projects`.
- **B** — a quiet destructive text button in the inspector's **Danger** section, above
  `Remove this server…`, matching the held-change sheet's drawing.
- **C** — a `.disable` case in the table row's single action slot.
- **D** — the mock's inspector header action row (`Wake now` / `Trip breaker` / `⋯ More actions`),
  with disable inside the overflow menu.

**Decided: A.** Both referral lanes were given the four options with the real code and the binding
design rules, and both returned A independently, on the same three reasons.

Evidence: `planning/evidence/M37/referral-grok.md` (`grok-4.6 --effort xhigh`, out of family, run
from an empty working directory so it could not read the other lane's answer) and
`planning/evidence/M37/referral-fable.md` (`claude-fable-5 --effort high`, in family). The codex
lane stays unavailable per ORCHESTRATOR; `agy --new-project` returned a **zero-byte output file**
on this machine and is recorded as a lane failure rather than as agreement. So: two lanes, one of
them out of family, and a third down.

The three reasons, which are the argument rather than the vote:

1. **Disable is a behaviour setting, not a destructive act.** `DESIGN.md` §9 scales friction to
   blast radius, and disabling keeps the manifest row, the digest, the credentials and the approved
   tool surface — spec-M29 §3.1. Behaviour is the inspector's writable half and already holds
   `disabled`'s three siblings on the wire (`warm`, `projects`, `placard`). Putting it in Danger
   next to `Remove this server…` teaches an operator that disable is delete's sibling, which is
   the one thing it is not.
2. **The inspector reaches every server; the row's action slot does not.** That slot runs a strict
   precedence — enable, then reset, then review held change, then sign in — so it is *occupied*
   precisely on the tripped, held and unauthorised servers the brief is about. C would ship the
   affordance and have it disappear on the cases that motivated it.
3. **D would build speculative chrome to host one real action.** Two of the mock's three header
   buttons have no control-API operation behind them at all, and the `⋯ More actions` menu's
   contents are not drawn anywhere in the mock — which is exactly what DEF-M29-c parks. Nothing
   here closes DEF-M29-c, and A does not block a later migration into that menu.

**What the losing options are genuinely better at**, stated rather than dismissed. B signals
consequence harder, and matches the drawn idiom. C is one click from the table and pairs
symmetrically with `Enable`; it stays a reasonable *later addition* for healthy rows, and is filed
as DEF-M37-a. D is what the design of record will eventually look like.

---

## 4 · Recorded decisions and assumptions

| | Decision | Why, and what it beat |
|---|---|---|
| D1 | The control is a `ToggleRow` in Behaviour, titled **`Disable this server`**, bound `isOn: server.disabled` — the switch is on when the server is off | §3. Bound to the wire field directly rather than to its inverse: a `Serve to your sessions` toggle reads more naturally in isolation and adds a polarity flip between what the view shows and what the PATCH carries, which is one more place to get backwards. The section's other two toggles are both default-off and both named for what turning them on does |
| D2 | **The word stays `disabled`. `pause` is not introduced** | `DESIGN.md` §6 — one name per state, from one source. The state already has four shipped spellings of *disable*: the wire field, the row's `disabled by you`, the sheet's `Disable mobbin`, and the tool-call refusal's `Enable it in MCP Router`. The out-of-family lane named the real cost of this: *disabled* is also what this UI calls a dimmed control, and `pause` would have disambiguated. `by you` already does that work, and a fifth spelling for a state that has four is the failure the rule exists to prevent |
| D3 | The inspector stops claiming a served tool count on a disabled server, in **three** places on the pane the new control sits on: the header detail line, the project-scope toggle's help sentence, and the tool list's footnote | The control makes the disabled state reachable for every server, so three sentences that were previously only reachable through the held-change sheet become ordinary. `Text("\(server.transport.rawValue) · \(server.tools) tools")`, `app/Sources/MCPRouterUI/Boards/ServerInspector.swift:68` at `49eae13` claims a served capability; `? "Every session sees its \(server.tools) tools."`, `app/Sources/MCPRouterUI/Boards/ServerInspectorSections.swift:62` at `49eae13` is simply false while the server is off. The row model already withholds the same figure for the same reason (D9 of spec-M29); this is that rule reaching the pane the row opens |
| D4 | The scope toggle's disabled-state help states the **precedence**, not just the fact — *no session sees its tools while it is disabled, whatever this is set to* | `ToolUnion.isServed` tests `disabled` first and `visibleTo` second, and `ToolUnion.swift`'s own comment says the order is the message. The copy now says what the predicate does instead of leaving the reader to compose two toggles |
| D5 | The new control is **not** dimmed because the server is already disabled | It is the only way back off itself if the row's `Enable` is ever not showing, and a switch that cannot be switched back is not a switch. `disabledReason` stays what it is for the other two: writing in flight, or the router not answering |
| D6 | The row's action slot is untouched; `Enable` stays the fast reversal and no `.disable` case is added | §3, reason 2. The asymmetry is deliberate and is the right way round: reversal is cheaper than the act |
| D7 | No menu-bar command and no accelerator | Unchanged from spec-M29 D3. DEF-M29-b stays open |
| D8 | The held-change sheet is untouched | Its `Disable <server>` is a different speech act — refusing a rewritten tool surface from a decision sheet — and it is what the design of record draws there |
| D9 | The affordance's wire request is pinned in **one** file that both test targets read, and the router half of the witness drives that file's bytes through the real handler | §6. `MCPRouterUI` and `RouterCore` share no target, so nothing in the package can observe both halves at once; a literal repeated in two suites is two suites that can drift apart in agreement |
| D10 | The pin lives in a new `Pins/` resource directory, **not** in the parity corpus `Vectors/` | §6. `pin-class-gate.py` refused it there and was right to: that population is reference-derived vectors, and this one has no reference to derive from |

**Assumption A1.** A disabled server keeps its `Keep warm` and `Only load in named projects`
toggles live and writable. Disabling is not a modal state that freezes the pane — the operator may
well be setting a server up while it is switched off. Overturned by an owner who wants the rest of
Behaviour dimmed while a server is disabled.

**Assumption A2.** The toggle sits **first** in Behaviour, above `Keep warm`. It governs whether
the other two mean anything, and D4's help sentence only reads correctly if the reader has already
met it.

**Assumption A3.** The tool list still lists the tools on a disabled server, with a sentence
saying none is being served. Withholding the list itself would lose the one place an operator can
inspect what a server declares before switching it back on, which is the reading D4 of spec-M29
protects at the router.

No Essential Questions.

---

## 5 · State matrix

The surface is the Servers board's inspector pane. Real copy.

| State | What the Behaviour section shows |
|---|---|
| Default (live, unscoped) | `Disable this server` off · help *Stop serving its tools. Its configuration, credentials and approved tool list are kept, so switching it back on costs nothing.* |
| Disabled | toggle on · help *Its tools are withheld from every session. Its configuration, credentials and approved tool list are kept.* · header reads `stdio · tools withheld` · scope help reads *No session sees its tools while it is disabled, whatever this is set to.* · tool list carries *None of these is being served while this server is disabled.* |
| Write in flight | all three toggles dim in place, help replaced by `Applying…` — the existing `disabledReason`, unchanged |
| Router not answering | all three dim in place with *The router isn't answering, so this can't be changed right now.* |
| Refused write | the pane's existing row-error banner carries `ControlAPIError`'s own headline and advice; no new phrasing, and the toggle springs back because it is bound to the server rather than to local state |
| Disabled **and** holding a change | toggle on; the held-change banner still shows and its `Review the change` still works. `disabled by you` winning the row's precedence is spec-M29's ruling and is not re-decided here |
| Disabled **and** tripped | toggle on; the tripped banner and its `Reset` are unchanged |
| Disabled **and** unauthorised | toggle on; the sign-in banner is unchanged |
| Empty / loading / offline | the inspector is not rendered without a selected server; these are the board's states and M16 owns them |

---

## 6 · The witness, and why it is built this way

The dispatch's requirement: *a paused upstream must be provably not served, read back through a
different channel from the one that struck.*

K5 established why this matters at the router: deleting the whole `disabled` arm from
`ControlHandler.applyPatchFields` left **all 688 RouterCore tests in 106 suites passing**, because
every suite that mentioned the field started from a fixture that was already switched off. Seventeen
readers, no writer.

This item's control is one layer above that, and the same trap is available in a new shape: a test
that asserts `setDisabled` sends `{"disabled":true}` is asking the recording client to confirm what
the model handed it. The strike and the read-back are the same channel again.

**The seam, and the structural fact that shapes it.** `MCPRouterUITests` may import `MCPRouterUI`
and `MCPRouterKit`; `RouterCoreTests` may import `RouterCore`. No target links both, deliberately —
`Package.swift` records that the app never reads `servers.json` directly, and that boundary is what
makes the router swappable. So nothing in this package can watch the app's request arrive at the
router in one process.

What can be shared is **the request itself**, as a committed file:

1. `app/Tests/RouterCoreTests/Pins/pause-action.json` holds the method, the path template, the two
   bodies and, for each, whether the server is served afterwards.

   **`Pins/`, not `Vectors/`, and that is the gate's ruling rather than a preference.** `Vectors/`
   is the parity corpus, and `planning/pin-class-gate.py` refuses any file in it that is not
   produced by a generator region importing a named export of the TypeScript reference — because a
   parity vector exists to catch two implementations diverging, and one that re-types its reference
   cannot see the reference move. This file pins a request the **app** composes: there is no
   production export to import and no second implementation, so it is not a parity vector and does
   not belong in that population. It was written into `Vectors/` first and the gate refused it;
   the refusal was right. `Package.swift` declares `Pins` as a second resource directory of the
   same test target, so the bundle is the same and only the claim differs. What `VectorRegistry`
   gives the parity corpus — every case driven, and the consumer reporting its own execution count
   — is kept by `ControlPauseVectorTests.everyPinnedCaseIsDriven` rather than dropped.
2. The app half asserts that driving the inspector's own toggle closure produces exactly the
   vector's bytes. If the control stops sending what the vector says, this reddens.
3. The router half feeds the vector's bytes to the real `ControlHandler` against a real
   `servers.json` in a temporary directory, then re-reads that file **off the filesystem**, re-parses
   it through `ServerParser`, and asks `ToolUnion.isServed`. Never the response body — that is the
   handler confirming its own write.
4. A live sibling server is present in every fixture and asserted unchanged, so a handler that
   disabled the whole file cannot pass.

Neither half can drift alone, because the file they disagree with is the same file.

---

## 7 · Acceptance oracle

1. The inspector's Behaviour section offers a `Disable this server` control for a healthy server.
2. It offers it for a tripped, a held-change, an unauthorised and an already-disabled server —
   the four states whose row action slot is occupied. Asserted across the set, not on an example.
3. The control is bound to `server.disabled`: on when the server is off, off when it is live.
4. Flipping it on calls `setDisabled(name, to: true)`; flipping it off calls `setDisabled(name, to: false)`.
5. The control dims for a write in flight and for a router that is not answering, and **not** for a
   server that is already disabled.
6. The toggle is drawn from the named copy functions rather than from literals, asserted about the
   source the way spec-M29 oracle 12's binding is.
7. The word `pause` appears in no user-visible string this item adds.
8. The inspector header reads `tools withheld` for a disabled server and the count for a live one.
9. The project-scope toggle's help does not claim any session sees the tools of a disabled server,
   scoped or unscoped.
10. The tool list carries the not-served sentence exactly when the server is disabled.
11. The vector's disable body, driven through the real `ControlHandler` against a real
    `servers.json`, leaves the server **not served** as read back off the filesystem through
    `ServerParser` and `ToolUnion.isServed`.
12. The vector's enable body leaves it served, and removes the member rather than writing `false`.
13. The untouched sibling server in the same config is served throughout both.
14. The bytes the app sends and the bytes the router is driven with are read from one file, and a
    test fails if either half stops matching it.

---

## 8 · Deferred children

| Id | What | Why not now |
|---|---|---|
| DEF-M37-a | A `.disable` case in the table row's action slot, for rows whose slot is otherwise empty | §3. Real convenience, and it cannot be the home for the affordance because the slot is taken on exactly the servers the brief is about. Worth doing once the home exists |
| DEF-M37-b | Disable / enable from the menu-bar popover's attention rows | Not asked for, and the popover's row vocabulary is M27's |

DEF-M29-a, DEF-M29-b and DEF-M29-c are unchanged by this item and stay open.
