# plan-M3 — Servers: the breaker board

- **Spec:** `planning/specs/spec-M3.md` · **Brief:** `planning/features-to-triage/M3-servers-board.md`
- **Branch:** `ai/m3` · **Worktree:** `.worktrees/M3`
- **Tier:** Standard — one board, five new files, four edited, ~33 acceptance clauses.
- **Done when:** `.servers` is in `BoardRegistry.installed`, `make all` is green, and
  `planning/evidence/M3-acceptance.md` carries behavioural evidence for the measured clauses.

---

## The shape of the change

Every operation this board needs already exists on F3's `ControlAPIClient`, and every failure state
it must render already exists on F4's `ServerStateTracker`. So this is almost entirely a *rendering*
change, and the risk sits in two places rather than across the whole diff:

1. **The presentation rules** — the subtitle precedence, the breaker mapping, the reap countdown,
   the filters. These are where the prototype failed twice, and they go in the **UI-free target** so
   they are testable without a host.
2. **The registration** — `BoardRegistry.installed`, the `ContentZone` branch, and the menu
   availability flip. This is the difference between a board that exists and a board the user sees.

Nothing is added to `ControlAPIClient`, `ServerPatch`, `BreakerState` or the design tokens.

---

## Phase A — the presentation rules, in `MCPRouterKit`

**New:** `app/Sources/MCPRouterKit/Servers/ServerPresentation.swift`

Pure, `Sendable`, no SwiftUI. Everything here is a function of `MCPServer` plus the two response-level
facts (`idleMs`, `pendingAuth`), so every rule is exercisable with a constructed value.

```
public struct ServerRowModel: Equatable, Sendable {
    public let id: String              // server.name — stable identity, never an index
    public let name: String
    public let subtitle: ServerSubtitle
    public let breaker: BreakerState
    public let transport: String
    public let tools: Int
    public let calls: Int
    public let errors: Int
    public let lastUsed: Date?
    public let action: ServerRowAction?
}

public struct ServerSubtitle: Equatable, Sendable {
    public let text: String
    public let tint: ColorToken        // .t2 / .t3 / .attention / .fail
}

public enum ServerRowAction: Equatable, Sendable {
    case reset(ResetKind)              // .reindex when indexError != nil, else .clearPlacard
    case reviewHeldChange
    case beginAuthorization
    case reopenAuthorizationPage(URL)
}
```

**A.1 — `ServerSubtitle.forServer(_:idleMs:)`.** The ten-row precedence table from the spec, as one
`switch`-shaped chain with `warm` **above** `running`. The countdown is
`max(0, idleMs / 1000 - server.idleSec)` and takes `idleMs` as a parameter — there is no default and
no literal 300 anywhere in the file, so the value can only come from the response.

**A.2 — `BreakerState.forServer(_:)`.** Running first, then placard, then `needsAttention`, then
dormant. Written as an extension in this file rather than as a change to `BreakerGeometry.swift`,
which is a merged base element.

**A.3 — `ServerFilter`.** `.all / .running / .idle / .needsYou`, each with a predicate and a title.
`needsYou` is `needsAttention || placard != nil`.

**A.4 — `ServerSearch.matches(_:query:)`.** Case- and diacritic-insensitive over `name` and
`toolNames`. An empty query matches everything.

**A.5 — `ServerRowAction.forServer(_:pendingAuth:)`.** The five-row table, including the
`pendingAuth?.server == name` branch that turns `Sign in…` into `Reopen the page`.

**A.6 — `ServersBoardHeader`.** `tools`, `servers` and an **optional** `running` — `nil` on a stale
load, which is what makes A9 a type-level guarantee rather than a discipline.

**Tests** (`app/Tests/MCPRouterKitTests/ServerPresentationTests.swift`) — A3, A4, A5, A6, A7, A24.
A4 is the important one and is written as a cross product rather than as examples: `warm` × the four
`ServerState` values × `inFlight ∈ {0, 1}` × `placard ∈ {nil, set}`, asserting that **no** case with
`warm == true` produces a string containing `reaps in`, and that every non-attention warm case reads
`warm · never reaped`.

**Red-green, per `SWIFT_PRACTICES.md` §7:** before trusting A4 and A5, invert the `warm`/`running`
precedence in the source, watch both go red, restore, record it in the evidence file. A guard that
has never failed is a decoration.

---

## Phase B — the board, in `MCPRouterUI`

**New:** `app/Sources/MCPRouterUI/Boards/ServersBoardModel.swift`

`@MainActor @Observable`. Owns: `selection: String?`, `searchQuery`, `filter`, `writesInFlight:
Set<String>`, `lastWriteError: ControlAPIError?`, and the sheet route. Reads server state from the
**shell's existing tracker** — it takes `ShellModel` rather than constructing a second
`ServerStateTracker`, because two poll loops against one router is exactly what F4 exists to remove.

One `perform` path per write, each: mark in flight → call the client → on success let the next poll
carry the truth (no local mutation, so the board cannot drift from the router) → on failure surface
the typed error **against the row**, not as a pane. `SWIFT_PRACTICES.md` §3: no `try?`, no swallowed
error.

**New:** `app/Sources/MCPRouterUI/Boards/ServersBoard.swift`

The pane. Switches over the tracker's `LoadState` into the nine states, exhaustively:

| `LoadState` | rendering |
|---|---|
| `.loading` | `SkeletonRows()` — F2's, at `MetricToken.serversRow` |
| `.loaded([])` | `MessageState(ServersBoardCopy.empty, …)` |
| `.loaded(servers)` | header + search + filter + table + footer; empty-in-filter when the predicate matches none |
| `.stale(servers, error)` | the same, with the Partial banner above it and `running` absent from the header |
| `.failed(.routerNotRunning)` | the Offline pane, copy from `ControlAPIError` |
| `.failed(error)` | the Error pane, copy from `ControlAPIError` |

Success, Disabled and Overflow are not load states — they are row- and control-level, and are
rendered by the row and the controls respectively. The spec's A19 is satisfied by an exhaustive
`switch` over `SurfaceState` in the board's own state-preview surface, so a tenth case fails to
compile.

`ServerRow` is a `Button` at a fixed `.frame(height: MetricToken.serversRow.leadingScalar)`, with
`selectionFill(_:)` and `focusRing(_:)` from F2. It renders `Breaker`, **not** `BreakerToggle`.

**New:** `app/Sources/MCPRouterUI/Boards/ServerInspector.swift` — the five sections and the three
banners. Configuration is read-only text; Environment and Headers render `envKeys`/`headerKeys` and
their count and take no other input.

**New:** `app/Sources/MCPRouterUI/Boards/ServerSheets.swift` — `AddServerSheet`,
`HeldChangeSheet`, `RemoveServerDialog`. The held sheet fetches through `heldChanges(for:)` and has
its own loading and error states, because it is a second request that can fail on its own.

**Tests** (`app/Tests/MCPRouterUITests/ServersBoardTests.swift`) — A8, A10, A16, A19, A20, A21, A22,
A23, A24, A25, A30, A31, A32. The rendering assertions run against the **row and section models**
rather than a view hierarchy, which is why Phase A puts them in values.

---

## Phase C — the writes

**Tests first** (`app/Tests/MCPRouterUITests/ServersBoardWriteTests.swift`) against a recording stub
that conforms to `ControlAPIClient` and captures method, path and **encoded body**:

- **A11** Reset → `reindex` when `indexError != nil`; otherwise `patch` whose body has `placard` as
  an explicit JSON `null`. Asserted on the bytes, since `encodeNil` is the only thing that produces
  it and a synthesised encoder would silently omit the key.
- **A12** Keep warm → body exactly `{"warm":…}`; scoping → exactly `{"projects":[…]}`. Both through
  `ServerPatch.encodedBody()`, so an unpermitted key throws before it ships.
- **A13** the command-line guarantee: every request the board can issue, asserted against the
  **encoded JSON** for the absence of `command`, `args`, `env`. Not reflection over the Swift type —
  `SWIFT_PRACTICES.md` §2 names why.
- **A14** a refused `add` with a hint → the hint is surfaced and `Add it anyway` re-issues with
  `force: true`.
- **A15** remove → `keepHistory` reflects the checkbox.
- **A17** accept → `approve`; keep-the-old-text → **zero requests**.
- **A18** sign in → `beginAuthorization`; `pendingAuth` present → no new authorisation begun.
- **A29** `Space` → the warm PATCH.

---

## Phase D — registration, and the menu

This is the phase that decides whether the user sees anything.

**D.1 — `ScaffoldPane.swift`:** `installed = [.servers]`. The merged complement test in
`ShellIntegrationTests` then requires `.servers` to be absent from `scaffolded`, which it will be.

**D.2 — `ShellWindow.swift`:** replace the `EmptyView()` else-branch with the board. The comment
there already says this is the branch M2–M8 fill in.

**D.3 — `MenuCommand.swift`, additive only:**

```
public struct CommandContext: Hashable, Sendable {
    public let installedDestinations: Set<Destination>
    public let selectedServerIsTripped: Bool?   // nil = nothing selected
    public static let none = CommandContext(installedDestinations: [], selectedServerIsTripped: nil)
}
public func availability(in context: CommandContext) -> CommandAvailability
public var availability: CommandAvailability { availability(in: .none) }   // unchanged meaning
```

The parameterless property keeps returning exactly what it returns today, so `spec-M1.md`'s
inventory table and `MenuCommandTests` pass **without edit** (A27). Only the live app passes a real
context.

**D.4 — `ShellMenuReasons.apply(to:context:)`** gains a defaulted context parameter, and
`ShellCommandRouter` gains the four operations (`addServer`, `find`, `resetServer`, `removeServer`)
as `Operation` cases performed against `ServersBoardModel`.

**Risk, and how it is contained:** `ShellIntegrationTests` currently asserts every disabled item's
tool tip is `surfaceAbsent.reason`, derived from the parameterless `availability`. Because that
property is unchanged, the assertion still holds. If it does not, the correct fix is to give the
test an explicit `.none` context — never to weaken the assertion.

---

## Phase E — gates and evidence

1. `make lint` · `make build-mac` · `make test` · `make all`. Report the output; do not assert it.
2. **Red-green proof** for A4, A5, A11 and A13 — break each guard, watch it fail, restore, record.
3. **Affected-test sweep:** `ShellIntegrationTests`, `ShellDestinationTests`, `MenuCommandTests`,
   `ShellCommandRouterTests`, `DesignTokenParityTests`, `BreakerParityTests` all touch surfaces this
   change moves. Run the whole suite, not the new files.
4. **Behavioural evidence, invisibly** (`UI_VERIFICATION.md` rule 1): `open -g -a` only, `proctor`
   attached by pid, process-directed step kinds (`press`, `menu`, `setValue`, `focus`) — never
   `click`/`key`/`hover`, never `activate`, never `screencapture -R`. One launch, one pass:
   - **A2** the Servers pane renders the board and not `isn't built yet`
   - **A28** File ▸ `Add server…` reports `AXEnabled` true with no help tag
   - **A33** row height 56, breaker housing 30×48, sidebar 256
   Then quit.
5. **Only the Servers pane is verified.** The other six destinations are still placeholders and
   there is nothing in them to test; the skip is stated in the report.
6. `planning/evidence/M3-acceptance.md` — one row per screen: screen · how verified (the actual AX
   path or command) · commit SHA · result. Appended, never rewritten.
7. Commit on `ai/m3`. **No rebase, no merge, no push.**

---

## What this plan deliberately does not do

- **No change to `BreakerState`.** A running server that also holds a description shows green. The
  wanted change is recorded in the spec's shared-surface section.
- **No change to `ServersBoardCopy`.** Its offline wording differs from `ControlAPIError`'s by one
  contraction; the board uses the error's, and the divergence is reported.
- **No `idleMs` control.** Writable, not readable back.
- **No second control-API channel and no second poll loop.**
- **No edit to `install.sh` or `src/*.ts`.** That is R4's cutover.
