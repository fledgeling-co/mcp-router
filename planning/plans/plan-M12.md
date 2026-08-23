# plan-M12 — staleness and an as-of time inside a destructive dialog

Spec: `planning/specs/spec-M12.md`. Brief:
`planning/features-to-triage/M12-staleness-in-destructive-dialogs.md`. Branch `ai/m12`, worktree
`.worktrees/M12`.

**Size: Small.** Four source files, one of them by one line. No wire type changes, no new request, no
new dependency, and nothing under `src/`. The work is one model field, two pure functions, one small
view, and the tests that make each of them a gate rather than a decoration.

| File | Change |
|---|---|
| `app/Sources/MCPRouterKit/Cleanup/CleanupPresentation.swift` | `agoPhrase`, `resetFigureProvenance`, `removeFigureProvenance` — three additions; `resetConsequence` untouched |
| `app/Sources/MCPRouterUI/Boards/CleanupBoardModel.swift` | `Reading.observedAt`, an injected `clock`, `isStale`, and the two provenance accessors the sheets read |
| `app/Sources/MCPRouterUI/Boards/CleanupSheets.swift` | the `FigureProvenance` view, and one call site in each of the two destructive sheets |
| `app/Sources/MCPRouterUI/Boards/M7BoardMetrics.swift` | one line: `CleanupBoardStates.partial` names the dialog treatment as well as the held-out banner |

---

## P1 · Stamp the reading

`Reading` gains `observedAt: Date`, and `CleanupBoardModel` gains
`clock: @MainActor () -> Date = { Date() }`, injected in `init` exactly as `ActivityModel`'s is and
for the same stated reason: every relative time here is measured from *now*, and a test that has to
sleep to reach a boundary proves nothing.

The stamp is taken where the `Reading` is constructed — immediately after `servers()` returns, before
`skills()` and `usageSummary()` are attempted. `skills()` and `usageSummary()` can only land later,
so the age this reports is never younger than the truth. That direction is deliberate and is written
into the doc comment: a staleness disclosure that errs must err old.

`.stale(previous, error)` keeps the previous `Reading` unchanged, so `observedAt` stays the moment
that reading was taken and ages naturally on screen — which is the whole mechanism. Nothing needs to
zero it or refresh it.

**The four `Reading(...)` construction sites** — one in `load()`, the rest in tests — take the new
argument. There is no default value: a reading with an implicit "now" would be a reading that lies
about its own age the moment anyone constructs one from a fixture.

## P2 · The three pure functions

All in `CleanupPresentation`, beside the copy they serve, because that enum is already where every
sentence this pane says lives and where a reader checking an honesty claim will look.

**`agoPhrase(_ date: Date, from now: Date) -> String`.** `shortAgo` returns `"now"` under five
seconds, so the obvious `"\(shortAgo(d)) ago"` renders **"now ago"**. This wraps it: `"just now"`
under the boundary, `"\(shortAgo(d)) ago"` above it. Boundary-tested at 4s and 5s, per
`SWIFT_PRACTICES.md` §7 — test the boundary, not the middle. (`EvalsInspector.swift:146` has the
un-wrapped bug live; it is not this item's line and is recorded in the spec's found-not-fixed only
where this item touched it, which is nowhere. Left alone.)

**`resetFigureProvenance(observedAt:isStale:statesACount:now:) -> String?`** — four branches:

| stale | figure | sentence |
|---|---|---|
| no | yes | `This figure is from the reading taken {ago}. Whatever the router has recorded since is discarded as well, and is not in it.` |
| no | no | `nil` — the consequence already says the router did not give a number, and dating an absent figure is worse than saying nothing |
| yes | yes | `This is the last reading the router gave, taken {ago}, and nothing about it is current. Whatever the router has recorded since is discarded as well, and is not in the figure above.` |
| yes | no | the first sentence of the row above, alone |

The `statesACount` argument is `recordedCalls != nil` and nothing else. It is deliberately **not**
`calls > 0`: an observed zero is a figure, and it is the figure most in need of an as-of, because
"nothing to discard" is the claim likeliest to have gone false since the reading was taken.

**`removeFigureProvenance(observedAt:isStale:now:) -> String?`** — two branches, always non-nil,
because a removal sheet with a candidate always has a tool count and key names to date:

- fresh: `The tool count and the key names above are from the reading taken {ago}.`
- stale: `This is the last reading the router gave, taken {ago}, and nothing about it is current — what removing this server takes with it may have changed since.`

The stale half of both functions opens with the board's own words. `StaleReadingBanner` says *"the
last reading the router gave, kept rather than cleared. Nothing about them is current."* — §6 asks
for one name per state from one source, and this is the same state.

## P3 · One small view, two call sites

```swift
struct FigureProvenance: View {
    let text: String
    let isStale: Bool
}
```

Stale renders `Banner(icon: .warn, tint: .attention) { Text(text) }` — the component
`StaleReadingBanner` and `PartialIndexNote` already use, so the tint reaches only the glyph and the
text is `--t2` at `.body`, which keeps `--attn` in its declared `pairedWithAWord` role. Fresh renders
a `.caption` in `--t3` with `fixedSize(horizontal: false, vertical: true)`, matching
`provenanceLimit` two structs down in the same file.

The branch lives in the view rather than at each call site so the two sheets cannot drift into
different treatments of the same state.

Both sheets place it as the last element before the toggle/error/button stack, so it sits under the
figure it is about and above the act. In `RemoveServerSheet` it goes inside the `if let candidate`
branch: the `else` branch is `consequenceUnavailable`, which states no figure and needs no date.

## P4 · The state matrix line

`CleanupBoardStates.partial` currently reads `"an unreadable client holds every skill out —
CleanupPresentation.heldOutBanner"`. It gains the dialog's treatment, because a stale reading marked
inside a modal is §5's Partial in the same sense `StaleReadingBanner`'s own doc comment claims for
the board.

---

## Test strategy

Three seams, and each is a different kind of claim.

### Seam 1 — the copy, as pure functions (`MCPRouterKitTests/CleanupPresentationTests.swift`)

No view, no model, no clock: two `Date`s in, a string out. This is where every branch is enumerated.

| Test | Asserts |
|---|---|
| `agoPhraseReadsAtTheFiveSecondBoundary` | 4s → `just now`; 5s → `5s ago`; 90s → `1m ago`. Never the substring `now ago` |
| `resetProvenanceNamesWhenTheFigureWasRead` | fresh + count contains `taken 3m ago` and the accrual clause |
| `resetProvenanceMarksAStaleReading` | stale + count carries `the last reading the router gave` and `nothing about it is current` |
| `resetProvenanceStatesNoDateForAFigureThatDoesNotExist` | fresh + no count → `nil`; stale + no count → the marker alone, and **no** accrual clause about a figure that is not there |
| `anObservedZeroStillGetsItsAsOfTime` | `statesACount` is driven by `recordedCalls != nil`, so zero is dated. This is the branch M7's finding 1 was about, one layer up |
| `removeProvenanceDatesTheToolCountAndTheKeyNames` | both branches; the stale one says what removing it takes may have changed |
| `provenanceInventsNoNumber` | neither function's output contains a digit that is not part of the elapsed-time phrase — the §6 last-bullet guard |
| `theSharedConsequenceIsUnchanged` | `resetConsequence`'s five existing assertions still hold, and no provenance string is a substring of any of them (C8) |

### Seam 2 — the model (`MCPRouterUITests/CleanupProvenanceTests.swift`, new)

Drives `CleanupBoardModel` with the existing recording clients and an injected clock.

| Test | Asserts |
|---|---|
| `observedAtIsStampedFromTheInjectedClock` | a clock pinned at T gives `reading.observedAt == T` after `load()` |
| `aStaleReadingKeepsTheOlderObservedAt` | load at T, fail the second load, and `state.reading?.observedAt` is still T while `isStale` is true — the age grows because the clock moves, not because anything was restamped |
| `aFailedFirstLoadHasNoProvenanceToState` | `.failed` → both accessors `nil`; nothing is dated when nothing was read |
| `aStaleReadingDoesNotDimTheDestructiveButton` | `removeDisabledReason` is unchanged by staleness, and is still non-nil for a skill and for no selection (C9) |
| `theRemoveSheetStillRefusesWhenTheCandidateIsGone` | the pre-existing `candidate == nil` disable is not weakened by the new branch (C9) |

### Seam 3 — the rendering (`MCPRouterUITests/CleanupProvenanceTests.swift`, same file)

`FigureProvenance` is constructed in both modes and the two are asserted to differ **structurally**,
not by colour — C5's claim is that the distinction survives
`accessibilityDifferentiateWithoutColor`, and an assertion on a hue would not test it.

### Red-green

`SWIFT_PRACTICES.md` §7: a drift guard that has never failed is not known to work. Four mutations,
each run to red and restored, recorded in `planning/evidence/M12-acceptance.md` with the failing
assertion quoted:

| # | Mutation | Must red |
|---|---|---|
| M1 | `agoPhrase` returns `"\(shortAgo(date, from: now)) ago"` unconditionally | `agoPhraseReadsAtTheFiveSecondBoundary` — `"now ago"` |
| M2 | `statesACount` computed as `calls > 0` rather than `calls != nil` | `anObservedZeroStillGetsItsAsOfTime` |
| M3 | `FigureProvenance` renders the caption in both modes | `staleAndFreshDifferInStructure` |
| M4 | `load()` restamps `observedAt` on the `.stale` path | `aStaleReadingKeepsTheOlderObservedAt` |

### Gates this change actually needs

`make lint` (swiftlint plus `no-raw-design-values.sh` — this diff adds no dimension, so the second
should be a no-op and is run to prove it), and `make test`. `make build-mac` because SwiftUI
compiles differently from the SwiftPM target. Not `make all`: it takes 30–40 minutes, the
orchestrator runs the whole-repo gate, and two runners have already ended a turn owing a commit to
it.

Not run, and why: `make test-ios` and `make test-ios-glass` — this diff touches no file under
`app/MCPRouterIOS`, `app/MCPRouterIOSTests` or `app/MCPRouterIOSUITests`, and `#if os(macOS)` fences
two of the three changed sources. `make parity` — no token, no `DESIGN.md` value and no colour moves.
`make acceptance` — `mac-shell.sh` asserts against the shell and the boards, and this item changes
neither; the dialog evidence is a single scoped UI pass instead, per `UI_VERIFICATION.md` rule 2.

### The UI pass

One launch, backgrounded, one sweep, quit — `UI_VERIFICATION.md` rules 1 and 2. Only the Cleanup
board's two dialogs, which are the only screens this diff changes. Driven through `proctor` by pid
over the accessibility plane, never frontmost, and captured with `proctor_capture` rather than
`screencapture -R`. Evidence appended to `planning/evidence/M12-acceptance.md`.

The stale state is reachable without a fixture: load the board against a live router, stop the
router, let the next poll throw, and `LoadState.stale` is what the board holds. If the router cannot
be driven into that state within the one pass, the state is proved at seam 2 and the report says the
rendered half is unproven — a named gap beats a green nobody checked.

---

## What the plan review changed, and what the build actually did

The plan above is the one that went to `agy --model gemini-3.7-flash-high` for the adversarial
review. Ten findings came back and five of them changed the design, so this section records the
delta rather than leaving the plan reading as though it had been followed. The dispositions in full
are in `planning/specs/spec-M12.md` §"The second out-of-family review".

| The plan said | What shipped, and why |
|---|---|
| `agoPhrase` — "just now" / "3m ago", boundary-tested at 4s and 5s | **Gone.** A relative age is computed when a view body runs, and a modal's body does not re-run while it sits open; the phrase would freeze at whatever it said when the sheet opened. `asOfLabel` states a clock time instead, and adds the date when the reading is not from today |
| `resetFigureProvenance(… statesACount: Bool …)` | **`calls: Int?`**, the same parameter `resetConsequence` takes. The `!= nil` versus `> 0` decision was the mutation the plan wanted red, and with a `Bool` it lived in the model where the pure-function test could not see it |
| both functions return `String?` | **`CleanupPresentation.Provenance`** — `.none`, `.quiet`, `.marked`. The plan put the stale-versus-quiet branch inside the view, which is the one layer this repo cannot assert against, and it was the whole subject of the item |
| one new view, `FigureProvenance`, branching on `isStale` | **`ProvenanceNote`**, switching over the value above. The sheets carry no staleness branch at all, and a test fails if `board.isStale` reappears in that file |
| the removal line names "the tool count and the key names above" | **It names neither.** `removeConsequence` prints no key names for a server with no env or header keys, so the line would have claimed provenance over something not on screen |
| four files change | **Seven.** Three are splits forced by SwiftLint: `CleanupPresentation.swift` and `CleanupBoardModel.swift` both crossed the 400-line file limit and the class crossed the 250-line type-body limit, so the provenance functions, the two state types and the model's provenance accessors each took a file. `M7ExercisedRequestTests.swift` gained two failure knobs, because `LoadState.stale` is unreachable against a double that always answers |
| `Reading(...)` has four construction sites | **One**, in `load()`. The rest were a guess and the tree says otherwise |
| mutations M1–M4 | M1 (`agoPhrase`) no longer applies; the other three stand, plus one for the refusal reason. The table in `planning/evidence/M12-acceptance.md` is the one that was run |

