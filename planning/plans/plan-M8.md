# plan-M8 — Settings, the menu-bar popover, and the quarantine's missing half

**Spec:** `planning/specs/spec-M8.md` (A1–A33, incl. A16b, A19b, A27a–A27f)
**Design representation:** `design/mocks/html/m8-settings-popover.html`
**Branch:** `ai/m8` · **Worktree:** `.worktrees/M8`
**Tier:** Standard.

**Revised after the spec gate.** The first version of this plan was written against a spec that
certified the quarantine surface as complete and assumed the shell's poller kept running with the
window closed. Both were wrong; the spec now says so and this plan follows it. The two new pieces
of work are the schema half of the tool diff and an app-lifetime poll.

---

## The shape of the change

The pattern M3 established is the pattern here: **decisions** live in `MCPRouterKit` (no UI
framework, reachable by `swift test`), **views** live in `MCPRouterUI`, and `app/MCPRouter` gets
assembly only — because nothing in that directory is a SwiftPM target, so a decision written next to
the `MenuBarExtra` scene is a decision with no evidence lane.

That split is what makes the criteria testable. A17 (no skills count), A12 (the dot is never
`--fail`), A18 (the band is absent rather than empty) and A27a–A27d (the schema diff) are all
assertions about a *value*, so each value is computed somewhere a test can call it.

---

## Phase A — the presentation rules, in `MCPRouterKit`

### A.1 `Shell/MenuBarPresentation.swift`

`AttentionCause` (`heldChange`, `needsAuthorization`, `indexFailed`), ordered so declaration order
*is* precedence, with `sentence`, `iconName`, `tintToken` and `opensHeldChangeSheet` per case;
`attentionRows(from:)`; `statusItemNeedsAttention`, `statusItemLabel`, `statusItemDotToken`;
`counts(from:)`; `recentCallLimit`; the copy constants.

Two things in it are structural rather than conventional, and both are load-bearing:

- **`statusItemDotToken` is a separate value from `AttentionCause.tintToken`.** The row's glyph may
  be `--fail`; the bar's dot never is. Collapsing them is the tidy-looking edit that puts a red dot
  in the menu bar, and A12 fails if it happens.
- **`Counts` has no skills field.** A structural absence survives an edit that a comment does not
  (A17).

**`counts(from:)` defines idle as *not running*** so the two buckets always sum to the declared
total (A16b). `ServerState` has four cases and reading "idle" as `state == .idle` would drop
`starting` and `stopping` — which is every cold start, which is exactly when someone is watching.

### A.2 `Shell/PopoverContent.swift`

The popover's whole render, as one value:

```
public struct PopoverContent: Equatable, Sendable {
    public let counts: Counts?              // nil when nothing has ever loaded
    public let stale: StaleNotice?          // its own row, above the band
    public let band: [AttentionRow]?        // nil — never [] — when nothing wants a decision
    public let calls: [CallRow]
    public let message: Message?            // offline / empty log
}
```

`band` being `[AttentionRow]?` rather than `[AttentionRow]` is what makes A18 falsifiable at all: a
view-level test cannot distinguish a hidden band from a band rendering zero rows, and a
nil-versus-empty assertion can. The view's only rule is `if let band`.

`stale` is a **sibling of** the band, not a modifier on it (A19b). A failed refresh is not three
servers failing, and recolouring their rows `--fail` would assert that it was — which §2's
exclusivity forbids.

### A.3 `Shell/SettingsPresentation.swift`

`RouterFacts` (`endpoint` composed from the observed port, `reaper`, `homeDisplay`, `sinceDisplay`),
`TokenStatus` (four cases, **no case carrying a token** — that is how A7 is structural),
`WarmSet` (**no memory field** — A5), `Group`, and the copy.

### A.4 `Shell/SchemaDiff.swift` — the half that was missing

The router holds a change when the description **or** the input schema differs
(`src/manifest.ts:80-93`) and ships both on `ToolShape`. Nothing rendered the schema.

```
public enum SchemaDiff {
    public struct ParameterChange: Equatable, Sendable, Identifiable {
        public enum Kind: Sendable { case added, removed, altered }
        public let name: String
        public let kind: Kind
    }
    public enum Result: Equatable, Sendable {
        case identical
        case changed(parameters: [ParameterChange], beforePretty: String, afterPretty: String)
        case unreadable(beforeRaw: String, afterRaw: String, reason: String)
    }
    public static func compare(before: String?, after: String?) -> Result
}
```

- Both sides are decoded and **compared structurally**, so a serialisation-order change is
  `identical` rather than a reported change (A27c).
- `beforePretty` / `afterPretty` are re-encoded with **sorted keys and indentation**, so a real
  change lands on its own line instead of inside one long string.
- Top-level `properties` are compared by name to produce `ParameterChange`s, so the card can say
  *"adds `context`"* rather than handing over two JSON documents (A27b).
- Undecodable JSON is `.unreadable` with the raw strings and a reason — **never `.identical`**.
  A decode path whose failure mode is "no change" is the silent-empty shape `SWIFT_PRACTICES.md` §2
  names as the worst available, and here it would silently pass an unreviewable schema (A27d).

**Phase A tests** (`Tests/MCPRouterKitTests/`) cover A5–A9, A11–A14, A16, A16b, A17, A18, A19,
A27a–A27d.

A5 is a **source-level** assertion over the presentation files: the failure mode is not a bug in
today's code but a plausible megabyte figure added later by someone who has not read §6, and a test
over today's output cannot see that coming.

---

## Phase B — the two shared-data changes

### B.1 `TrackerState` gains `port` and `since`

Two additive `let`s beside `idleMs`, from the same successful poll, **retained across a failure**
for the reason already written in that type: a failure to refresh is not evidence the router's
configuration changed (A4).

Red-green: clear them on failure, watch A4 go red, restore.

### B.2 `ShellModel` gains an app-lifetime poll

`ShellModel.run()` is driven only by `ShellWindow.swift:45`'s `.task`, which is cancelled when the
window goes away. **A menu-bar app's normal state is window-closed**, so the status item and popover
would freeze or blank.

```
@ObservationIgnored private var pollTask: Task<Void, Never>?

/// Idempotent. Retained on the model, whose lifetime is the app's — deliberately not owned by any
/// scene, because the surface that needs it outlives the window.
public func startPolling() {
    guard pollTask == nil else { return }
    pollTask = Task { [weak self] in await self?.run() }
}
```

`ShellWindow`'s `.task` calls `startPolling()` instead of `await model.run()`. The `MenuBarExtra`'s
label does the same, so the poll starts whichever surface appears first.

This reverses M1's stated rationale for scene-owned polling, and the reversal is recorded in the
spec rather than made quietly. Red-green for A27e/A27f: call it twice against a scripted client and
count polls; cancel a scene-shaped task and assert the tracker still advances.

---

## Phase C — the views, in `MCPRouterUI`

### C.1 Geometry that has no token

`MetricToken` tokenises only the **leading** scalar of each documented cell, so "10–14" yields 10
and "24–28" yields 24. The concentric child radius of 14, the 26pt popover row, the 32pt settings
row and the 150pt label column therefore have no token to read, and `SWIFT_PRACTICES.md` §5 forbids
scattering them as literals.

Following `ServersBoardMetrics`, which M3 created for exactly this: `SettingsMetrics` and
`PopoverMetrics`, each a small `enum` of named constants derived from a token where one exists. A31
then asserts what it can actually assert — that the **views** contain no bare number.

### C.2 `Boards/SettingsBoard.swift` (+ `SettingsBoardModel.swift`)

Reads `shell.trackerState` and `shell.servers`; starts no poll of its own. The model is
`@MainActor @Observable` and owns only the `TokenStatus`, loaded in `.task` from an **injected**
`ControlTokenStore` defaulting to `KeychainTokenStore()` — so no test touches the real keychain and
A7/A8/A10 can run against `InMemoryTokenStore`.

Truncated warm-set chips and the token path carry their full value in `.help` **and**
`.accessibilityValue`, which is the recorded answer to §5's "the full value in the inspector" in a
pane that has no inspector.

### C.3 `Shell/MenuBarPopover.swift`, `Shell/MenuBarStatusItem.swift`

The popover renders `PopoverContent` and decides nothing. The status item is a template
`Image(systemName:)` plus the conditional dot, labelled from `statusItemLabel`.

### C.4 `Boards/ServerSheets.swift` — inside `ToolChangeCard` only

Render `SchemaDiff.compare(before:after:)` beneath the description fields:

- `.identical` → nothing, unless the description is also identical, in which case the card says the
  change is elsewhere rather than showing two identical fields with no explanation (A27a).
- `.changed` → the parameter list first (added parameters in `--attn`), then the two pretty-printed
  schemas.
- `.unreadable` → the reason and the raw strings.

**Nothing else in this file is touched**, and A26 measures that as a reviewed diff.

### C.5 `Icon.swift` — one case

The cold-start marker, as an `Icon` case mapping to a monochrome SF Symbol. `DESIGN.md` §4 is
"drawn, never unicode", and a literal ❄ in a status-adjacent surface is the web tell §3 exists to
remove.

**Phase C tests** cover A20, A21, A27, A28, A29, A31, A32.

---

## Phase D — registration, the route, and the app scene

1. `BoardRegistry.installed` gains `.settings` (A1).
2. One branch in `ShellWindow.pane` for `.settings`.
3. **The route.** `ShellModel` gains:

   ```
   public func reveal(server name: String, openingHeldChange: Bool) async
   ```

   which sets `selection = .servers`, sets the board's selection, and — when
   `openingHeldChange` — sets `serversBoard.sheet = .heldChange(server:)` **and awaits
   `serversBoard.loadHeldChanges(name)`**.

   The `await` is the point. Opening the sheet takes two operations, and an implementation that sets
   the sheet alone renders "Reading the held descriptions…" forever with a dimmed accept button —
   the one press this whole item exists for landing on a dead sheet. A24 asserts the loaded diff, not
   just the sheet case.
4. `MCPRouterApp.swift` — a `MenuBarExtra(.window)` gated on the `UserDefaults` flag. Assembly only.
   A band row calls `NSApp.activate` then `model.reveal(...)`: the one legitimate activation in the
   app, kept here because `NSApp` is AppKit and the shared module stays free of it.

---

## Phase E — gates and evidence

1. `make generate && make all` — typecheck, format, lint, full suite with a non-zero test count
   (A33); `swift test list` is counted before the run.
2. **Red-green proving pass**, recorded: B.1 retention, A5 (` MB` in a string), A11/A12 (flip the
   dot's tint), A17 (add a skills count), A18 (return `[]` instead of `nil`), A24 (drop the
   `loadHeldChanges` await), A27c (compare schemas as raw strings), A27d (return `.identical` on a
   decode failure). A guard that has never failed is a decoration.
3. **The behavioural pass, invisible.** One launch, backgrounded (`open -g -a`), driven over the
   accessibility plane by pid. **Only the Settings pane, the menu-bar item and the held-change sheet
   are exercised** — they are what changed. Servers' board, Activity and the shell's own rows are
   cited from the existing evidence files rather than re-run, and each skip is named. The app is
   never activated and is quit at the end.
4. `planning/evidence/M8-acceptance.md`, appended never rewritten.

---

## What this plan deliberately does not do

- **It does not rebuild `HeldChangeSheet`.** It adds one missing field inside `ToolChangeCard`.
- **It adds no `MenuCommand`.** Menu-bar visibility is a checkbox in Settings.
- **It writes nothing to `servers.json`** and opens no second channel.
- **It does not implement "Start the router"** — recorded as a deviation, consistent with M3.
- **It displays no memory figure**, and A5 keeps that true after this item ships.

## Risks

| Risk | Handling |
|---|---|
| `open -g -a` attaches to another fleet runner's build | M3 hit this. Resolve the pid explicitly and assert the bundle path before reading. |
| Two poll loops if `startPolling` is not actually idempotent | A27e counts polls against a scripted client rather than trusting the guard. |
| SwiftLint file length on `SettingsBoard.swift` / `ServerSheets.swift` | Split rather than raise a limit — R2R's lesson. `ServerSheets.swift` is already 17KB, so the schema card goes in its own file if it pushes the limit. |
| Merge conflict on `BoardRegistry.installed` with M2/M4 | A one-line set literal, anticipated. Resolve by union. |
| Keychain prompting during tests | The store is injected everywhere; no test constructs `KeychainTokenStore`. |
