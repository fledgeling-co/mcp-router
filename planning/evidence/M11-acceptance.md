# M11 acceptance — the command-availability inventory, and the defect it was hiding

Branch `ai/m11`, worktree `.worktrees/M11`, measured on 2026-08-15.

M11 was scoped as a documentation repair: `scripts/acceptance/mac-shell.sh` was red on main at
`ba139d4` with

```
FAIL: File / Add server... carries no discoverable reason (AXHelp was '')
```

and the diagnosis was that `spec-M1.md`'s inventory listed seven commands as `surfaceAbsent` that
the shipped app, with all eight boards installed, correctly has enabled.

**Half of that diagnosis was wrong, and the wrong half was a live product defect.** The failing
line is `mac-shell.sh:512`, which is only reached after `:511` has already asserted the item
reports itself **disabled**. So the running app did not have `Add server…` enabled. It had it
dimmed *and* silent.

## What was actually broken

Two contexts, one menu:

| | source of truth | with eight boards installed |
|---|---|---|
| the item's `.disabled()` | `MenuCommand.availability` — the `CommandContext.none` shorthand | `surfaceAbsent` → dimmed |
| the item's `AXHelp` | `ShellMenuReasons` with `liveContext` | `enabled` → no reason written |

Measured on the built Debug app, backgrounded, before any fix:

```
File | Add server…       | enabled=0 | help=
File | Add marketplace…  | enabled=0 | help=
Edit | Find              | enabled=0 | help=
File | Pair iPhone…      | enabled=0 | help=This part of the app isn't built yet.
Edit | Reset server      | enabled=0 | help=Select a server first.
```

Three commands whose surfaces shipped at M3 (Servers) and M4 (Skills) were **permanently
unusable, with no explanation** — `DESIGN.md` §3.4 broken in both directions at once. `CommandItem`
read the `.none` shorthand, so the entire live-context mechanism reached the reason and never
reached the enabled state.

Nothing caught it because every test asked the rule rather than the rendering.
`SkillsMenuTests.liveInTheRealRegistry` asserts `MenuCommand.addMarketplace.availability(in:
real) == .enabled` and has passed since M4 — while the item on screen said otherwise. Its own
docstring records that M4 added it *because* the acceptance pass found the wrong reason on screen;
the fix went into the model and the rendering was never re-measured.

## Why the inventory itself was not regenerated

The column is headed *"Availability in M1"* and means it: the answer in `CommandContext.none`.
`MenuCommandTests.inventoryMatchesTheModelBothWays` compares it against `MenuCommand.availability`
in both directions and is green — verified on this branch, not assumed. Rewriting those seven rows
to the live answers would have turned a correct, tested table red.

What was wrong is that `mac-shell.sh` read a column meaning *"with no board installed"* as the
expectation for a build with eight. So the derivation went into the gate, where the live question
is actually asked: it compiles `MenuCommand.swift` and `Destination.swift` and asks
`availability(in:)` directly, with the installed set from `board_registry_installed` and no
selection. The spec table keeps the two oracles a model cannot supply about itself — which commands
exist, and which chords they carry.

That split also removed a second hand-copy: the old enabled check named `View/*`, `Help/*` and
`MCP Router/Settings` in shell, reaching 13 of the 20 app-declared commands and excluding every
File and Edit item — the exact set the defect was sitting in. It now derives that split from
`MenuCommand.isSystemProvided`, and checks all 20.

## The gate

| Clause | How verified | Result |
|---|---|---|
| A22 — availability, all 20 app-declared commands | `mac-shell.sh`: expected availability compiled from `MenuCommand.availability(in:)` with the real registry, compared against `AXEnabled` and `AXHelp` from the backgrounded app | pass — 16 enabled and silent, 4 dimmed carrying their reason |
| A19 / A20 — membership, both ways, and 26 chords | unchanged, still against `spec-M1.md`'s table | pass — 34 commands, 0 missing, 0 unlisted |
| `make lint` | exit code captured directly, never through a pipe | 0 |
| `make test` | whole suite | 0 — 1234 tests in 153 suites |
| `make build-mac` / `make build-mac-release` | | 0 / 0 |
| Invisibility | frontmost sampled after every phase | pass — MCP Router never frontmost; run began and ended on Ghostty |

### The gate was proven able to fail

A derived oracle has a specific weakness worth naming: mutating `availability(in:)` moves the
oracle *and* the app together, so that mutation proves nothing. What this gate asserts is the
crossing into AppKit, so the mutations break the crossing.

| Mutation | Gate |
|---|---|
| `CommandItem.resolvedAvailability` → `command.availability` (the original defect, reintroduced) | **red** — `FAIL: File / Add server… is usable in this build, but the menu bar reports it disabled` |
| `ShellMenuReasons.apply` annotates from `.none` instead of the passed context | **red** — `FAIL: File / Add server… is usable but still carries the reason 'This part of the app isn't built yet.'` |
| `touch MenuCommand.swift` without rebuilding | **blocked (exit 2)** — the freshness check names the stale file |
| all restored by re-applying the original edit | **green** at A22 |

And the three unit guards, each proven able to fail:

| Mutation | Test |
|---|---|
| `CommandItem.resolvedAvailability` → `command.availability` | `commandItemsReadTheLiveContext` red — `(… → .surfaceAbsent) == .enabled` |
| `@Observable` removed from `ContextSource` | `liveContextIsObservable` red on the registration leg only — the selection leg still passed, which is the discrimination expected |
| `find` repointed from `.servers` to `.evals` | `gatingMapIsPerCommand` red — every other test in the repo stayed green |

`MenuCommand.swift` is byte-identical to `main` on the final tree (`git diff main` over it is empty),
so `availability(in:)`'s behaviour is unchanged, as the item required.

Both acceptance mutation runs exited at A22, before the scroll-edge section below, so neither red is
confused with it.

## What the completeness critic found, and what was done

Run in-family: **`codex: usage limit → claude (downgrade)`** — the out-of-family lane is
account-limited until 2026-08-20. A logged downgrade, not a pass. Six findings, all dispositioned:

| # | Finding | Disposition |
|---|---|---|
| H1 | The Observation claim was asserted in prose and exercised nowhere — the gate measures one static end state, and the unit test called `resolvedAvailability` directly, bypassing tracking entirely. The defect fixed here *was* a state-transition failure and the transition stayed unmeasured. | **Accepted and closed.** `liveContextIsObservable` drives `withObservationTracking` — the same machinery SwiftUI uses — over both legs: a provider registering after the menu was built, and the server selection moving under an already-registered one. Proven red by removing `@Observable`. |
| H2 | With the window closed but the app running (M8's normal state), the provider is never unregistered, so these commands now render **enabled but dead** — `@FocusedValue` is nil and `ShellCommandRouter` no-ops. | **Accepted as a finding, deliberately not "fixed".** Reverting to `.none` on window close would dim `Add server…` and claim its surface was never built, which is false and a worse §3.4 answer. The residue — enabled with no focused scene to receive it — is **pre-existing for the sixteen commands that were always enabled** (every View destination, Settings, all three Help items); this change adds three more to that set rather than creating the class. It belongs to `ShellCommandRouter`'s inability to reach the model without a focused scene. Recorded in the source at `ShellMenuReasons.ContextSource` and left for its owner. |
| M1 | Oracle/binary skew: the oracle compiles source at run time while the app was built earlier, so a forgotten rebuild could certify a tree that is not what shipped. | **Accepted and closed.** The gate now blocks when any of the four menu sources is newer than the built executable. Proven by `touch`ing `MenuCommand.swift`: exit 2, naming the file. |
| M2 | The derived oracle gave up a third externally-checkable fact the evidence did not admit — **which board each command gates on**. With all eight installed, any required destination yields `.enabled`, so repointing `find` at `.evals` would have gone red nowhere. | **Accepted and closed.** `MenuCommandTests.gatingMapIsPerCommand` asserts the map against *partial* contexts, where it is falsifiable. Proven red by that exact mutation. |
| M3 | `[ "$AVAIL_CHECKED" -eq "$APP_ROWS" ]` **cannot fail** — the loop counts the rows it iterates — and the prose around it called a tautology an assertion. | **Accepted.** Removed, and the comment now says where completeness actually comes from: the per-row lookup inside the loop plus A19's two-way membership. An assertion that cannot fail is the failure mode this item exists to correct. |
| M4 | Every menu item would re-evaluate on the 2s poll forever, because `menuContext` reads `trackerState` and the poll assigns it unconditionally. | **Partly rejected, on the code.** `menuContext` reaches `trackerState` inside `serversBoard.selection.flatMap { … }`, and `Optional.flatMap` does not call its closure on nil — so with no server selected, which is the ordinary state and the gate's, the items take no dependency on the poll at all. While a server *is* selected they re-evaluate per tick, and that is semantically warranted (its tripped-ness is exactly what `Reset server` branches on) though it fires on assignment rather than on change. The unconditional assignment is `ShellModel`'s, untouched here, and noted for its owner. |
| L1 | `apply()`'s doc comment and its inline comment both described a count the code no longer produces. | **Accepted.** Both corrected; the count is owned items *currently carrying a reason*, which is legitimately 0 in a fully-live context. |
| L2 | A ≤100 ms window where an item is enabled and still carries a stale reason, between SwiftUI flipping it and the walker's next tick. | **Accepted as bounded, not fixed.** Unreachable by the gate (it settles for 1.5 s) and a VoiceOver user would have to land inside one tick. Recorded rather than engineered away. |
| L3 | The oracle `compactMap`ped unparseable destination names away, so a broken caller would read as an availability defect in the app. | **Accepted and closed.** It now exits 2 naming the unknown tokens. |
| L4 | An oracle build failure maps to BLOCKED (exit 2), so a refactor moving `CommandAvailability` to a third file parks the gate rather than reddening it. | **Rejected, with reason.** That is the script's own documented doctrine (`mac-shell.sh:23-25`): 2 means the harness could not run, and collapsing it into 1 is how a missing permission gets reported as a broken app. A CI that treats blocked as skip is a CI problem. |

The critic also confirmed it had no attack on the A34-independence argument below.

## What was fixed

- `ShellCommands.swift` — `CommandItem` resolves availability from the live context.
- `ShellMenuReasons.swift` — the provider moved behind an `@Observable` holder, so SwiftUI
  re-evaluates the items when a window registers and when the server selection moves; and the
  walker now *clears* an annotation that has stopped being true, rather than only ever writing one.
- `mac-shell.sh` — A22 derives its expectation; the hand-written system-item list is gone; the
  oracle and the binary are checked to be one tree; the tautological assertion removed.
- `ShellMenuContextTests.swift` — new suite. The A22 section moved out of `ShellIntegrationTests`
  because M11 roughly doubled it and the file passed its 400-line limit. **Split on the seam, not
  by raising the limit**: everything in the new suite answers one question — what a command says
  about its own availability and where that answer comes from.
- `spec-M1.md` — the column's meaning is stated where it is read, and the episode recorded.
- `M1-acceptance.md` — the two rows measured against the stale oracle marked superseded.

`MenuCommand.availability(in:)`'s behaviour is unchanged. The rule was right throughout.

### What this still does not prove

Stated because the alternative is letting silence read as coverage:

- The walker taking an annotation **back** is unit-tested against a hand-built `NSMenu`; the gate
  never observes that transition in the running app. Acceptance mutation 2 exercises the gate's
  stale-reason *assertion*, which is a different claim.
- `selectedServerIsTripped` is hardcoded nil in the oracle, so the `needsServerSelection → enabled`
  flip is outside the acceptance walk. Closing it means driving a selection inside the Servers
  board's table over the accessibility API, which the harness cannot currently do — `axkit select`
  addresses sidebar rows. `liveContextIsObservable` covers the model half.

## Not fixed, and not mine: A34, the scroll edge

With A22 green the run reaches a clause main never got to, and fails:

```
FAIL: the top row is not one colour once scrolled (#2F2F2F covers 0.707) — that is content, not a separator
```

It is independent of this work, and that is measured rather than asserted:

- `git diff main` over `ScrollEdge.swift`, `ShellWindow.swift` and `app/Sources/MCPRouterUI/Boards`
  is **empty**.
- the `mac-shell.sh` diff is a single hunk at `:496`, with **zero** lines touching the scroll
  section.
- both mutation runs above exited before reaching it.

The mechanism is the one the script's own comment predicted. A34 is driven on Servers, chosen as
"the first destination still using the shell's scroll view" while boards were still landing, and
the comment says in full: *"When the last board lands this needs the assertion moved onto a board's
own list instead."* M6 landed the last board. Servers' rows now scroll under the sampled row, so
the band that must be uniformly the separator is 70.7% one colour and 29.3% content.

What that measurement cannot distinguish is whether the separator still renders correctly and is
merely being sampled through content, or has genuinely stopped appearing. Settling it means
choosing a new measurement site across boards this item did not touch, which is a decision for
whoever owns the scroll edge. Left for a separate item rather than answered by relaxing the
assertion — an assertion loosened until it passes is the failure mode M11 exists to correct.
