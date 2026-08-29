# plan-M37 — the action that switches a server off

Spec: `planning/specs/spec-M37.md`. Branch `ai/l5`, worktree `.worktrees/L5`, cut at `49eae13`.

---

## Tier

**Small.** One new control, three copy corrections on the pane it sits on, and a two-target
witness. No router change, no wire change, no new endpoint, no migration. `ServerPatch(disabled:)`
and `ServersBoardModel.setDisabled` already exist and are not touched.

Design is **not** skipped: the surface is user-facing. It is served by the design of record plus
spec-M29's own reading of it, and the state matrix is §5 of the spec rather than a new mock —
this item adds one row to a section that already has two, in the same component.

---

## Slices

### S1 · The copy, named so a surface cannot re-phrase it

Four functions, statics on `ServerInspector`, following the idiom `HeldChangeSheet.disableLabel`
and `HeldChangeSheet.disableReason` set under M29:

| Function | Returns |
|---|---|
| `disableToggleTitle` | `Disable this server` |
| `disableToggleHelp(disabled:)` | the two sentences of §5, one per direction |
| `headerDetail(_:)` | `stdio · 41 tools`, or `stdio · tools withheld` when disabled |
| `projectScopeHelp(_:)` | the three-way sentence of D4 |
| `toolsNotServedNote(_:)` | the sentence, or `nil` when the server is live |

Named functions rather than literals for the reason M29's gap-fix found the hard way: a static that
returns the right string proves nothing if the view stopped calling it, and there is no accessor
for a SwiftUI label on this host — so the binding has to be a fact about the source, and the source
has to have one place to read.

### S2 · The control

`ServerInspectorSections.swift`, `behaviour`: a third `ToggleRow`, **first** in the section
(spec A2), `isOn: server.disabled`, `disabledReason: disabledReason` — the existing one, which
covers write-in-flight and router-not-answering and deliberately does not cover already-disabled
(D5). Its setter calls `board.setDisabled(server.name, to:)`.

### S3 · The three claims the control makes ordinary

`ServerInspector.swift` header detail → `headerDetail(_:)`.
`ServerInspectorSections.swift` scope help → `projectScopeHelp(_:)`.
`ServerInspectorSections.swift` tools section → the note, rendered only when disabled.

### S4 · The witness

`app/Tests/RouterCoreTests/Pins/pause-action.json` — the pinned request, in a new
resource directory beside the parity corpus rather than inside it (spec D10).

`app/Tests/MCPRouterUITests/ServersPauseAffordanceTests.swift` — the app half: the control exists
across all five server states, is bound to `server.disabled`, drives `setDisabled` both ways,
produces the vector's bytes, dims on the two reasons and not on the third, reads its copy from S1's
functions rather than from literals, and says `pause` nowhere.

`app/Tests/RouterCoreTests/ControlPauseVectorTests.swift` — the router half: the vector's bytes
through the real `ControlHandler`, read back off the filesystem through `ServerParser` and
`ToolUnion.isServed`, with a live sibling as the control.

---

## Test strategy

**The oracle rung each line stands on**, so verify is not handed a table of code reads:

| Oracle | Rung | Instrument |
|---|---|---|
| 1, 2, 5 | outcome | `ToggleRow` values resolved from a real `MCPServer` per state |
| 3, 4 | effect-witness | the toggle's own setter closure invoked; the recording client's calls read |
| 6, 7 | source-binding | `ShellTestSupport.declarationBody` over the two view files |
| 8, 9, 10 | outcome | the S1 functions over the cross product of disabled × scoped |
| 11, 12, 13 | effect-witness, **cross-channel** | `ControlHandler` → `servers.json` on disk → `ServerParser` → `ToolUnion.isServed` |
| 14 | metamorphic | one file, two readers; changing it must redden both halves |

**Why oracle 6 is a source assertion and not a render.** The same reason spec-M29 records for its
oracle 12: `make mock-fidelity SURFACE=servers` exits 3 on a break inherited from `main`, and there
is no accessor for a SwiftUI control's label on this host. A source-binding assertion is weaker
than a render and is labelled as such rather than dressed up.

### Mutation arms — what must redden, and it is checked by running them

| Id | The mutation | What must go red |
|---|---|---|
| PAU-1 | Delete the new `ToggleRow` from `behaviour` | the existence and binding tests |
| PAU-2 | Invert the toggle's polarity (`isOn: !server.disabled`) | the binding test |
| PAU-3 | Swap the setter's argument to a constant `true` | the both-directions effect test |
| PAU-4 | Add `.disabled(server.disabled)` to the toggle | D5's arm |
| PAU-5 | Replace the toggle's title with the literal `"Disable this server"` | the source-binding test |
| PAU-6 | Revert `headerDetail` to the interpolated count | oracle 8 |
| PAU-7 | Revert `projectScopeHelp` to the two-way version | oracle 9 |
| PAU-8 | Change the vector's disable body to `{"disabled":"yes"}` | **both halves**, which is what makes 14 a claim rather than a hope |
| PAU-9 | Delete the `disabled` arm from `applyPatchFields` (K5's mutation) | the router half of the witness — already covered by `ControlDisableWriteTests`, re-run here to prove the new file is not a second copy of an existing green |

PAU-8 is the arm that matters most: it is the only one that fails if the two halves have quietly
stopped reading the same file.

---

## What this plan explicitly does not do

- No change to `RouterCore`. The router already implements every serving consequence of `disabled`
  and this item adds no behaviour there. The new RouterCore *test* drives existing code.
- No change to `ServerRowAction`, `ServerSubtitle`, `JackState` or `ServerRowModel`.
- No change to the held-change sheet.
- No menu item, no accelerator — `MenuCommand` untouched, so M20's counted assertions do not move.
- No change to `design/mcp-router-console.html`. The design of record does not draw this control,
  and D1 is recorded as an addition to it, exactly as M29's D8 recorded `Enable`.

---

## Gate list this branch owes

`make lint` whole · `make test` whole · the two new suites run in isolation · every mutation arm
above run red-then-green with a rebuild between, because without a rebuild each reports BLOCKED
rather than red.
