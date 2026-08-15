# plan-M14 — separate "no destination" from "no feature"

Spec: `planning/specs/spec-M14.md` · branch `ai/m14` · worktree `.worktrees/M14`
Size tier: **Small**. One enum case, one `switch` arm split, four gate assertions, four rotted test
sites, one inventory row.

Baseline: `317d957`, 0 behind `main`, tree clean. `make build-mac-release` exit 0 measured before
any edit (§1 of the spec records the byte counts taken from it).

---

## Phase A — the model

### A1 · `MenuCommand.swift` — the third refusal

`CommandAvailability` (`:74-94`):

- add `case featureUnbuilt` between `.surfaceAbsent` and `.needsServerSelection`;
- `reason` gains `case .featureUnbuilt: "This feature hasn't been built yet."`;
- the type docstring's *"Exactly two reasons exist"* becomes three, and says what the third means
  and why it is distinct: `.surfaceAbsent` is about **this build** lacking a surface the product
  has, `.featureUnbuilt` about the **product** lacking the feature. The rule the sentence protects
  — that reasons live on the type so none is invented at a call site — is restated, since it is
  what makes adding one here legitimate and adding one at a call site not.

### A2 · `MenuCommand.swift` — the availability arms (`:319-321`)

Replace the shared arm and its now-false comment:

```swift
// Pairing's sheet is hosted by the Inbox board, and `ShellCommandRouter` selects `.inbox`
// before opening it — the same call the board's own always-enabled `Pairing…` button makes.
// So this follows `addServer`'s rule with `.inbox` in place of `.servers`. It reports that the
// command opens the pairing view, which is true; whether a phone can actually reach this Mac is
// the sheet's own `noEndpoint` state to state, and it does.
case .pairPhone:
    return context.installedDestinations.contains(.inbox) ? .enabled : .surfaceAbsent
// No context makes an unwritten feature exist, so this one does not ask.
case .exportLibrary:
    return .featureUnbuilt
```

**Not done here:** gating on `PairingAvailability`. The board's own button is not gated on it
either, and changing both is a decision about pairing rather than about a menu (spec §6).

---

## Phase B — the four rotted test sites

Each of these is currently **green while asserting a falsehood**, which is why the suite never
caught M14. Each is re-pointed at the new truth rather than relaxed.

| # | Site | What it asserts today | Becomes |
|---|---|---|---|
| B1 | `SkillsMenuTests.othersStillAbsent:53-62` | `.pairPhone` and `.exportLibrary` are `.surfaceAbsent` against the real registry | split: `.pairPhone` is `.enabled` against the real registry **and** `.surfaceAbsent` in a context without `.inbox`; `.exportLibrary` is `.featureUnbuilt`. Renamed and re-docstringed — its title says "the two commands whose surfaces have not shipped", which is now true of one |
| B2 | `MenuCommandTests.gatingMapIsPerCommand:259-262` | both are `.surfaceAbsent` with every destination installed | `.pairPhone` gates on `.inbox` specifically — `.enabled` in `[.inbox]`, `.surfaceAbsent` in `[.servers]` — which is the partial-context form this test exists for; `.exportLibrary` is `.featureUnbuilt` in every context |
| B3 | `MenuCommandTests` reason block `:221-223` | "Exactly two reasons exist" + two string assertions | three, with `.featureUnbuilt`'s sentence pinned and asserted **distinct from** `.surfaceAbsent`'s (spec A4) |
| B4 | `ShellMenuContextTests.commandItemsReadTheLiveContext:87-90` | both are `.surfaceAbsent` in the live context | `.pairPhone` → `.enabled` with `reason == nil`; `.exportLibrary` → `.featureUnbuilt` |

### B5 · the walker test's hidden assumption

`ShellMenuContextTests:24-40` builds a menu from every command whose `.none` reason is non-nil, then
asserts **every** item's `toolTip == CommandAvailability.surfaceAbsent.reason`. That passes today
only because every disabled command happens to share one reason. `.exportLibrary` stops sharing it,
so the assertion is re-pointed at **each command's own** reason:

```swift
for (item, command) in zip(menu.items, disabled) {
    #expect(item.toolTip == command.availability.reason)
    #expect(item.accessibilityHelp() == command.availability.reason)
}
```

with the foreign item still asserted untouched. This is strictly stronger: the old form could not
tell a walker that wrote the *right* string from one that wrote *a* string.

### B6 · `MenuCommandTests.modelRows()` (`:88-92`)

The `switch` mapping availability to the inventory's vocabulary gains `case .featureUnbuilt:
"featureUnbuilt"`. Exhaustive, so omitting it fails to compile rather than silently mis-mapping.

---

## Phase C — the gate (`scripts/acceptance/mac-shell.sh`)

### C1 · the oracle's `switch` (`:553-557`)

Add `case .featureUnbuilt: "featureUnbuilt"`. **Spec assumption 3 applies:** this `switch` is
exhaustive, so forgetting it is a compile failure, which the script maps to BLOCKED (exit 2) rather
than a red gate. That is the script's documented doctrine, not a defect, and it is why this edit is
listed first.

### C2 · replace the sentinel block (`:1047-1129`) with G1–G4

The `SENTINEL` read from `ScaffoldPane.swift`'s comment is retired along with the block that used
it. `DEST_TOTAL` / `INSTALLED_COUNT` / `SCAFFOLDS_REMAIN` are kept — they are the registry half of
G1. `bundle_contains` is kept unchanged and re-aimed.

**G1 — structural, derived.** Count `surfaceAbsent` rows in `$WORK/expected.tsv` (already produced
by the A22 oracle, so no second compile):

- `SCAFFOLDS_REMAIN == 0` ⟹ the count must be **0**. Failure text names the offending commands,
  because "some command is wrong" is not actionable.
- `SCAFFOLDS_REMAIN == 1` ⟹ the count must be **≥ 1**, and the pass line says how many
  destinations lack a board. Recorded in the spec as **unexercised on `main`**.

**G2 — named, rendered, hand-written.** Look up `File` / `Pair iPhone…` in `$WORK/items.tsv`
(already collected) and require `enabled == 1` and empty `AXHelp`. Its comment states why it is
hand-written where the rest is derived: M11's M2 finding — a derived oracle moves its expectation
with the app, so G1 alone is satisfied by re-classifying the command, which leaves the bug on
screen.

**G3 — rendered, derived, conditional.** Count `featureUnbuilt` rows. When ≥ 1, assert each is
present in the menu bar, `enabled == 0`, and its `AXHelp` equals the oracle's reason for it — then
report how many were exercised. When 0, **skip and say so**: an unconditional tripwire would make
shipping export a gate failure.

**G4 — bytes.** `bundle_contains "$REL_APP" "ScaffoldCopy"` and `"ScaffoldedDestination"` must both
be false. Comment records the measurement behind the needle choice: both are 0 in the shipping
binary while `ScaffoldPane` is **2**, because the file path survives in metadata, so the file name
is not a usable needle. The Debug-probe check below it is untouched.

The A22 loop itself needs no change: it is written over `availability != "enabled"` generically, so
a `featureUnbuilt` row already flows through its disabled branch and gets its reason compared. G3
adds the count and the naming that keep that branch from being vacuous.

---

## Phase D — the documents (main tree, uncommitted, per the fleet rule)

### D1 · `spec-M1.md`

- inventory row `| File | Export library… | ⌘E | surfaceAbsent |` → `featureUnbuilt`. This row is
  parsed by `MenuCommandTests.inventoryMatchesTheModelBothWays`, so it is **required**, not
  cosmetic: `.exportLibrary`'s answer in `CommandContext.none` genuinely changes.
- `Pair iPhone…`'s row is **unchanged** — under `.none` no board is installed, so it is still
  `surfaceAbsent`. Stated in the plan because "M14 changed pairing" invites editing it wrongly.
- the prose at `:119` naming *"Two disabled reasons exist and no third may be invented at a call
  site"* becomes three, keeping the call-site rule intact.

### D2 · `planning/evidence/M14-acceptance.md`

New, per `UI_VERIFICATION.md` rule 2. Appended, never rewritten; records screen, the actual command
or AX path, commit, result — including the skips and why.

---

## Phase E — proving the gate can still fail

Five mutations, each naming the assertion that should kill it. Restored by **re-applying the
original edit**, never `git checkout --`.

| # | Mutation | Expected |
|---|---|---|
| M1 | `.pairPhone` back to unconditional `.surfaceAbsent` (the shipped defect) | **G1 red** — a `.surfaceAbsent` report with every board installed; and B1/B4 red |
| M2 | `.pairPhone` → `.featureUnbuilt` (the mutation that defeats G1 alone) | **G2 red** — G1 is *green*, which is the whole reason G2 exists. If G2 does not redden here it is not doing its job |
| M3 | `.exportLibrary` → `.enabled` | **G3 red** on the count, or the A22 loop red on an item dimmed while the oracle says enabled |
| M4 | reintroduce `enum ScaffoldCopy` with the sentinel as a `let` in `ScaffoldPane.swift` | **G4 red**, and `ShellScaffoldRetirementTests.scaffoldTypesStayDeleted` red |
| M5 | `.pairPhone` gated on `.servers` instead of `.inbox` | **B2 red** (`gatingMapIsPerCommand`) — the partial-context form; every full-set assertion stays green, which is the point |

M2 is the load-bearing one. A mutation that cannot redden is a finding about the test design and
gets **re-aimed, not swapped** for an easier one.

---

## Phase F — gates

Run from the worktree root, exit codes captured directly (`cmd > f 2>&1; echo $?`), never through a
pipeline.

| Gate | Note |
|---|---|
| `make lint` | swiftformat runs first and short-circuits; the exit code is the oracle, not "0 violations" from the swiftlint half |
| `make test` | whole suite; the count must not drop |
| `make build-mac` | |
| `make build-mac-release` | G4 reads its output |
| `scripts/acceptance/mac-shell.sh` | must exit 0. Before believing any red, rebuild — and if the A22 freshness check blocks after a rebase, clear it with `rm -rf app/.derived/Build/Products/Debug/MCPRouter.app && make build-mac` (`D-m11-a`) |

**Acceptance scope:** `mac-shell.sh` only, and within it only the menu-bar and Release assertions
this item changes. No other item's script is run. The app is launched backgrounded and never comes
frontmost; the run ends with it terminated.

`swift test --filter` takes the **function name**, not the `@Test` display string — any filter is
confirmed to match before a red or green from it is believed.

---

## Phase G — out-of-family completeness critic

`grok-4.6`, briefed adversarially and told that finding nothing is a failed review. Exit code **and**
real content both asserted (V1: grok exits 0 on a failed session init). A grok failure falls back
in-family **with the downgrade logged**.

## Phase H — commit on `ai/m14`, stop

Source, tests, script and the evidence file commit on the branch. `spec-M14.md`, `plan-M14.md` and
`spec-M1.md` stay **uncommitted in the main tree**. No push, no merge.
