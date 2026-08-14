# plan-M5 — Discover: the registry

**Spec:** `planning/specs/spec-M5.md` · **Branch:** `ai/m5` · **Worktree:** `.worktrees/M5`

**Tier: Standard.** Seven new files, one shared file touched (`BoardRegistry`), three merged
tripwire tests updated deliberately, no router change, no new dependency, no schema change.

---

## The shape, and why it is M4's

M4's best decision was moving a view's *decision* into a testable Kit function returning an enum,
leaving the view a `switch` with no logic — which is what let it prove behaviour it could not
render. M5 copies that exactly, and it matters more here than it did there: Discover's decisions
are honesty decisions (which universe a number is true over, what a date means, whether an argv
gets shown), and an honesty decision buried in a `body` is one nobody can test.

**Kit decides. The view draws. The view has no `if` that is not a `switch` over a Kit answer.**

---

## P1 — `MCPRouterKit/Registry/RegistryPresentation.swift`

No SwiftUI import. Everything reachable from a test with no host.

```
public enum RegistryPresentation
```

| Symbol | Returns | Rule |
|---|---|---|
| `Ordering` (enum: `bestMatch`, `mostUsed`, `recentlyAdded`) | — | `CaseIterable`, `Identifiable`; `title` gives `Best match` / `Most used on Smithery` / `Recently added to Smithery` |
| `Ordering.universe` | `Universe` (`.all`, `.smitheryOnly`) | The stated scope. `bestMatch` is `.all`. |
| `rows(_:ordering:)` | `[RegistryEntry]` | Filters to the universe, then orders. **`bestMatch` returns the response order untouched** — no client-side sort at all. |
| `excludedCount(_:ordering:)` | `Int` | Rows the universe set aside. |
| `exclusionNote(_:ordering:)` | `String?` | `nil` for `.all`. Otherwise the computed sentence naming the count and the reason. |
| `disabledReason(_:ordering:)` | `String?` | Non-nil when the universe is empty — the segment dims in place with this. |
| `DateMeaning` (enum: `entryUpdated`, `firstPublished`) | — | |
| `dateMeaning(for:)` | `DateMeaning` | **`official`/`both` → `.entryUpdated`; `smithery` → `.firstPublished`.** The single most important function in the item. |
| `dateCell(for:now:)` | `DateCell?` | `nil` when `updatedAt` is absent or unparseable. Text is `added 9 Oct 2025` or `updated 14 Sep 2025` per the meaning. |
| `Figure` (struct: `value`, `unit`, `source`) | — | |
| `figure(for:)` | `Figure?` | `useCount` → `sessions` (Smithery); else `stars` → `stars` (GitHub); else **`nil`, never zero**. |
| `subtitle(for:)` | `String` | `Official registry · Smithery · 47 servers`. Empty while loading is the *caller's* branch, as M4 does it. |
| `footerNotes(for:)` | `[String]` | The four sentences, each included only when its condition holds; sentence 4 always. |
| `emptyMessage(query:ordering:response:)` | `EmptyMessage?` | The three distinct empties, keyed on the trimmed query AND the ordering — M4's `emptyInFilter` lesson, which is that keying on one of the two produces a board with headers over blank space. Carries `clearsSearch` / `resetsOrdering` so the action does what its label says. |

**Ordering is a stable sort.** `useCount` and `updatedAt` tie constantly (both are frequently
absent). Swift's `sort` is not documented stable, and an unstable sort over a response whose own
order is already non-deterministic gives a list that reshuffles between renders of *the same
data*. Implemented as a decorate-sort-undecorate on `(key, originalIndex)`, which is stable by
construction and testable as such.

## P2 — `MCPRouterKit/Registry/RegistryCapability.swift`

```
public enum RegistryCapability
```

| Symbol | Returns | Rule |
|---|---|---|
| `Statement` (struct: `headline`, `detail`, `argv`, `host`) | — | `argv` non-nil only for stdio; renders in the instrument face. |
| `statement(for:)` | `Statement` | Three shapes: stdio (runs a program, verbatim argv, "with your user account"), http (connects to *host*, nothing runs locally), absent (`Neither index says how to run this`). |
| `host(of:)` | `String?` | The authority from `install.url`, parsed — not the whole URL, and never the path, which is where a misleading string would hide. |
| `Action` (struct: `label`, `isEnabled`, `disabledReason`, `revealsRequirements`) | — | |
| `action(for:)` | `Action` | The §3.4 ellipsis rule as a decision: `…` iff `requires` is non-empty. Disabled with a stated reason when `installed` or `install == nil`. |
| `secretCount(for:)` | `Int` | For the requirement list's summary line. |
| `derivationNote` | `String` | The one quiet sentence saying this is a reading of the install block, not an author's manifest. |

**Hostile-input hardening lives here, not in the view.** Every string on this surface comes from
a third-party index and is attacker-controlled:

- `sanitized(_:)` strips control characters and bidirectional-override codepoints from
  `displayName`, `name` and `description` before they reach any view. A right-to-left override in
  a `displayName` can make `evil-server` render as `revres-live`, and this is a surface whose
  whole job is helping a user decide whether to run something.
- The argv is rendered as **separate, individually-escaped tokens**, never joined into one string
  that could be misread as a shell line. `command` and each element of `args` are distinct.
- `displayName` collision with an already-declared server is surfaced by the existing `installed`
  flag; the router refuses a duplicate name and its refusal is rendered as-is.

## P3 — `MCPRouterUI/Boards/DiscoverBoardModel.swift`

`@MainActor @Observable`, M4's `LoadState` shape adopted wholesale (`loading` / `loaded` /
`stale` / `failed`), because those four are what §5 needs and two merged boards have proved them
sufficient.

- `load()` from `.task`, cancellation-aware, and **keeps the previous good reading under a live
  failure** rather than blanking (`.stale`).
- `search` debounced at 400 ms. Implemented as a generation counter plus a cancellable task, not
  a timer: the in-flight task is cancelled when a newer keystroke arrives, so a slow first
  response cannot land after a faster second one and overwrite it. `submitSearch()` bypasses the
  debounce for `Return`.
- **A re-query keeps the current rows on screen** while it is in flight.
- `install(entry:values:)` calls `add(NewServer)` — `env` for stdio, `headers` for HTTP — and on
  success mutates the entry's `installed` in place. No refetch, because a refetch of a
  non-deterministic route would reorder the board under the user at the moment they acted.
- `commitDefaultAction()` opens the **detail sheet** for the selection and returns `false` when
  there is no selection, so `Return` is not swallowed when it has nothing to do.
- `escape()` — sheet first, then selection. Never both.
- `moveSelection(by:)` over the *visible* rows.

## P4 — The views

| File | Contents |
|---|---|
| `DiscoverBoardMetrics.swift` | Column widths and paddings as multiples of documented tokens, M4's construction. `rowHeight` fixed and shared with the skeleton. |
| `DiscoverBoardRow.swift` | The row, the provenance mark, the skeleton at the identical height. |
| `DiscoverBoard.swift` | Header, search, ordering segments, footer, the `switch` over `LoadState`. |
| `DiscoverDetailSheet.swift` | Identity, description, capability statement, requirement fields, action bar. |

Reused, not rebuilt: `MessageState`, `StateMessage`, `ConnectionFailurePane`, `StaleReadingBanner`,
`PartialIndexNote`, `Banner`, `DisabledAction`, `SearchField`, `ProminentButtonStyle`,
`StandardButtonStyle`, `IconView`.

**The provenance mark** is board-local, built from `ColorToken.f2`/`f3` and `MetricToken`, drawn
as two cells with the breaker's recess vocabulary for the unfilled one. No new shared token.

## P5 — Registration, and the three tripwires

`BoardRegistry.installed` becomes `[.servers, .skills, .activity, .discover]`, and
`ShellWindow.board`'s `.discover` case renders `DiscoverBoard`. Three merged tests are
deliberate tripwires and are updated in the same change — that is the designed action, not a
workaround:

1. the exact-complement assertion (both directions),
2. the exact installed set,
3. the scaffolded count.

`ScaffoldedDestination(.discover)` becomes `nil` structurally, which is the proof the placeholder
can no longer be constructed for this destination.

`boardsThatScrollThemselves` gains `.discover`: the board has a sticky header, search, ordering
control and column headers, and one outer scroll would carry all four off the top.

## P6 — Tests

`MCPRouterKitTests/RegistryPresentationTests.swift` and
`MCPRouterUITests/DiscoverBoardTests.swift`.

| Clause | Test |
|---|---|
| A1 | `.discover` in `installed`; `ScaffoldedDestination(.discover) == nil`; the three tripwires |
| A2 | Source grep for the fabricated field names (`installs`, `trend`, `velocity`, `eval`, `licence`, `category`, rank) across the Discover sources |
| A3 | `dateMeaning` for all three `source` values; **red-green: flip the mapping, watch it fail, restore** |
| A4 | Universe filtering; exclusion counts; disabled-when-empty; **`bestMatch` order identical to the response's own sequence** |
| A5 | A recording client proves exercising every row affordance issues **zero** `add` calls; the ellipsis rule; disabled reasons |
| A6 | The three capability shapes; argv tokens kept separate; the host parse |
| A7 | Each footer sentence appears iff its condition holds, computed from `sources`/`warnings` |
| A8 | Each of the nine states renders its own copy; offline ≠ error |
| A9 | Token parity — no literal colour/size; `--attn` only on `archived` |
| A10 | Request count across a typed burst is 1, not N; a re-query keeps rows; a failed re-query keeps rows |
| hostile | Control characters and RTL overrides stripped; a 4 kB `displayName` truncates without changing row height |

**Stability of the sort is its own test**: the same response ordered twice yields an identical
sequence, and ties keep arrival order.

## P7 — Gates and evidence

`make all` (build, test, lint, format) green and reported verbatim, never asserted. Then the
acceptance pass, per `planning/practices/UI_VERIFICATION.md`:

- **Discover pane only.** Servers, Skills and Activity are merged and evidenced in
  `planning/evidence/M3-`, `M4-` and `M2-acceptance.md`; those rows are cited, not re-driven.
- **Invisible**: `open -g -a`, proctor by pid, `proctor_capture` for a window-scoped shot, the
  process-directed step kinds only. Never `activate`, never `set frontmost`, never
  `screencapture -R`.
- One launch, one pass, quit.
- `planning/evidence/M5-acceptance.md`, appended, one row per screen with the actual command.

## Risks

1. **A concurrent runner also edits `BoardRegistry.installed`.** M8 registers `.settings` on its
   own branch. This is a one-line conflict at merge, resolved by taking both members. Flagged for
   the orchestrator rather than coordinated around.
2. **The fixture has three rows and no `warnings`,** so the partial states need authored fixtures.
   These are authored as *test* fixtures under `Tests/`, never added to the recordings directory —
   M2 was corrected for exactly that.
3. **`RelativeTime`'s existing formatter may not cover an absolute date.** If it does not, the
   date cell formats via a `DateFormatter` held once, not per row.

## Out of scope, and reported instead

Router-side snapshot store (M5-a), skills in the registry (M5-b), a GitHub token setting (M5-c),
a shared `Badge` component, a shared honesty-footer component, and the `--attn`-on-`--raised`
contrast shortfall `DESIGN.md` §10 already records.
