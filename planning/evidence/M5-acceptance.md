# M5 — acceptance evidence

`Discover: the registry` · branch `ai/m5` · worktree `.worktrees/M5`
Spec `planning/specs/spec-M5.md` (A1–A10) · Plan `planning/plans/plan-M5.md` ·
Design `DESIGN.md` (authoritative) · Mock `design/mocks/prototype.html?only=mac&pane=discover`

Append to this file, never rewrite it. Read it **before** testing anything: if a row exists and
`git diff <that SHA>..HEAD` does not touch the files behind it, that row *is* the evidence, and the
right thing to do is skip the check and say so.

---

## What was verified, and what was deliberately not

**One surface changed in this item**: the Discover pane and its detail sheet, both new. Everything
below drives that pane and nothing else.

**Not re-verified, and why.** Servers, Skills, Activity and Settings are M3's, M4's, M2's and M8's,
and this branch does not touch the files behind them. Their evidence is
`planning/evidence/M3-acceptance.md`, `M4-acceptance.md`, `M2-acceptance.md` and
`M8-acceptance.md`. Re-running those against unchanged code has exactly one possible outcome, and
the shell's own clauses belong to `scripts/acceptance/mac-shell.sh`, which is not repeated here.

**Inbox, Evals and Cleanup were not driven at all.** They are still in `BoardRegistry.scaffolded`,
so driving them would prove only that a placeholder is a placeholder.

**What this branch does change outside its own files** is the board registry and its four
assertions, and those are covered by the unit suite rather than by the rendered pass: the exact
installed set, the exact-complement invariant in both directions, the scaffolded count (in the two
separate places that pin it), and `ShellTestSupport.boardFiles`.

## The pass was invisible, and that is measured rather than asserted

The app was launched with `open -g` and **never activated**: there is no `osascript … to activate`,
no `set frontmost to true`, no bare `open -a` and no `screencapture -R` anywhere in
`scripts/acceptance/m5-discover.sh`. Every read went over the accessibility plane by pid. The
frontmost app is recorded at the start, checked after every group of assertions, and checked again
at the end — and the invariant is specifically "**MCP Router** never comes to the front", not "the
frontmost app never changes", so the user switching windows mid-run cannot fail a gate for
something the gate did not do. Frontmost at start: `Ghostty`. Frontmost at end: `Proctor`. Neither
is this app.

---

## Behavioural evidence — the running app

Command: `./scripts/acceptance/m5-discover.sh` · commit `6c0018b` (+ this file) ·
scenarios `populated`, `offline`, `error`, `loading` · **32 passed, 0 failed**

| Screen / clause | How verified | Commit | Result |
|---|---|---|---|
| Discover — installed, not scaffolded | `axkit select <pid> Discover` then `axkit dump <pid> window`; asserted the sentinel `isn't built yet` is **absent** | `6c0018b` | pass (A1) |
| Discover — window title | `axkit title <pid>` → `Discover` | `6c0018b` | pass (A1, §3.7) |
| Discover — real rows | 3 `AXButton` rows whose label carries a `ProvenanceMark` clause | `6c0018b` | pass (A1) |
| Discover — subtitle counts the screen | rendered `Official registry · Smithery · 3 servers` — the 3 on screen, **not** the merged 5 | `6c0018b` | pass (A2) |
| Discover — figures carry units | `2,984 sessions` and `9 stars` both present in row labels — two different scales, each named | `6c0018b` | pass (A2) |
| Discover — no fabricated figure | 8 regexes over the whole rendered tree for `N installs`, `N downloads`, `N% up/down`, `↑/↓ N`, `#N of`, `Rank N`, `N/10 eval`, `eval score`: no match | `6c0018b` | pass (A2) |
| Discover — the absence is stated | `No trend or velocity figure is shown` present, which also proves the search above ran over a tree that discusses these words | `6c0018b` | pass (A2) |
| Discover — no rank numbers | regex `^#?[0-9]+[.)] ` over row labels: no match | `6c0018b` | pass (A2) |
| Discover — `updatedAt`'s two meanings | row labels carry **2** `added …` (Smithery-sourced) and **1** `updated …` (official registry), side by side in one list | `6c0018b` | pass (A3) |
| Discover — three orderings | `AXRadioGroup` with exactly 3 `AXRadioButton`/`AXSegment` children: `Best match`, `Most used on Smithery`, `Recently added to Smithery` | `6c0018b` | pass (A4, §3.6) |
| Discover — best match at rest | `AXValue` 1 on `Best match`, 0 on the scoped segments | `6c0018b` | pass (A4) |
| Discover — best match claims no exclusion | `not shown here` absent from the rendered tree at rest | `6c0018b` | pass (A4) |
| Discover — the list installs nothing | no `AXButton` whose title or description is `Add` or `Install` anywhere in the board | `6c0018b` | pass (A5) |
| Discover — the row opens detail | `axkit press <pid> GitHub`, then the sheet's own copy asserted present — **judged by effect, not by return code** | `6c0018b` | pass (A5/A6) |
| Discover — pressing a row installs nothing | after the press, no row label reads `Already installed` | `6c0018b` | pass (A5) |
| Detail sheet — the host, not the path | rendered `Connects to server.smithery.ai` for an install URL of `https://server.smithery.ai/github/mcp` | `6c0018b` | pass (A6) |
| Detail sheet — HTTP runs nothing locally | rendered `Nothing runs on this Mac` | `6c0018b` | pass (A6) |
| Detail sheet — the revealing press | `axkit press <pid> "Add GitHub"`; before it, `Add GitHub…` reports `AXEnabled 1` | `6c0018b` | pass (A5, §3.4) |
| Detail sheet — a blank credential cannot be sent | after revealing, `Add GitHub` reports `AXEnabled 0` | `6c0018b` | pass (A5) |
| Detail sheet — the disabled reason is adjacent | rendered `Authorization has no value yet, and an empty one would be stored as a blank credential.` | `6c0018b` | pass (§3.4) |
| Detail sheet — Escape dismisses it | `axkit key <pid> 53`; the sheet's copy gone, the 3 rows intact behind it | `6c0018b` | pass (§8) |
| Discover — the slice is stated | rendered `Showing 3 of 5 that matched` — 3 results against `sources.merged = 5` in the shipped fixture | `6c0018b` | pass (A7) |
| Discover — the ranking bias is disclosed | rendered `Only Smithery publishes a session count…` under best match | `6c0018b` | pass (A7) |
| Discover — offline | scenario `offline`: `The router isn't running` + `Start the router`, and **0 rows drawn** | `6c0018b` | pass (A8) |
| Discover — error ≠ offline | scenario `error`: `The router isn't running` asserted **absent**, so the two states are not conflated | `6c0018b` | pass (A8) |
| Discover — loading is a skeleton | scenario `loading`: no `AXProgressIndicator` in the tree, and `Searching the registries` announced | `6c0018b` | pass (A8) |

### The defect this pass found

The row carried `.accessibilityAddTraits(.isButton)` and a **named** accessibility action
("Show details") with no default one. Measured against the running app on 2026-08-15, it published:

```
actions=["AXScrollToVisible", "Name:Show details\nTarget:0x0\nSelector:(null)"]
```

— **no `AXPress`**. So the row announced itself as a button and could not be pressed as one:
assistive technology, automation, and this gate all got nothing while the trait promised otherwise.
Performing the custom action by its (mangled) name *did* open the sheet, so the named action was
never broken — what was missing is the default one that `.isButton` implies. Fixed in `6c0018b` by
adding `.accessibilityAction { onOpen() }` alongside the named one; after the fix the same probe
reports `["AXScrollToVisible", "AXPress", "Name:Show details…"]` and `axkit press` opens the sheet.

**Why it hid, and the rule that comes out of it.** `AXUIElementPerformAction(kAXPressAction)` on the
unpressable row still returned `.success`. A gate keyed on that return code would have recorded a
pass for a sheet that never opened — the same shape as M8's recorded finding that a menu item
reached through `@FocusedValue` succeeds and does nothing in a background app. Every action in
`m5-discover.sh` is therefore judged by its effect on the rendered tree, never by an exit status.


### What the completeness critic found, and what happened to it

The Phase D critic (fresh `claude -p` opus-5, adversarially briefed) returned 22 KB of findings
rather than a clean bill. Recorded here because a review that finds nothing is the failure mode
this gate exists to avoid, and because two of its findings were about tests that asserted
themselves — the kind of gap a passing suite cannot show you.

| Finding | Verdict | Where it went |
|---|---|---|
| `declaration` sent `command`/`args`/`url` raw while the sheet displayed them sanitised | **real, highest severity** | Fixed in `6c0018b`; `statementMatchesWhatIsDeclared` now asserts the drawn tokens *are* the command line sent |
| The sanitiser missed U+200E/U+200F, U+061C, U+2028/U+2029, U+200B–U+200D, U+206A–U+206F | **real** — U+2028 is the newline the argv comment claims to block | Filter widened; `hostileTextBeyondTheObviousFamilies` tests the families the code did **not** already handle |
| `missingRequirements` was dead code, so Add with blank fields sent a credential-less declaration | **real** | Wired into `action(for:)`; proven in the rendered app (three rows above) |
| The env key was the raw requirement name, not the sanitised label; `id: \.name` made an attacker string SwiftUI's identity | **real** | Key sanitised at both ends; `ForEach` identity moved to the offset |
| `FlowingTokens` announced the argv as one joined shell line to VoiceOver | **real** | `spokenCommand` announces tokens with their roles and a count |
| Arrow keys returned `.handled` unconditionally, swallowing scroll on an empty board | **real** | `moveSelection(by:)` reports whether it moved |
| `expand(_:)` inferred "everything here came from the other index alone" from a substring | **real** — false under a partial-unreachable warning | Sentence narrowed to what follows whatever the warning's scope |
| `noFabricatedFieldsInDiscoverSources` read four Kit paths and none of the five UI files | **real** — the constraint is about what reaches the screen | All nine paths, plus rendered-literal needles and a vacuity guard |
| `dateMeaningMappingIsLoadBearing` "is a constant asserted against a constant" | **wrong** | Both entries carry `source: .official`, so only the id varies and a `source`-reading implementation *does* fail it. The property was implicit; it is now stated |
| `everyStateIsAccountedFor` is a `switch` asserting its own arms are non-empty | **right, and not fully closed** | It is a tautology. Four of the nine states are now driven in the running app instead (`populated`, `offline`, `error`, `loading`); the rest stay Kit-level. Left as a known weakness rather than papered over |
| `rankingNote` states the router's sort key from the app's knowledge of the router's source | **right, and deliberately kept** | The alternative is saying nothing about a bias the board would then be hiding. Reported, not changed |
| The light appearance has never been looked at for this board | **right** | Not closed. `ProvenanceMark`'s outline-vs-fill is two white alphas over a dark surface, and its own comment records that the first attempt was indistinguishable until someone rendered it. Whether the correction survives inversion is unverified |

### What the rendered pass could NOT prove, and where its evidence is instead

Stated rather than quietly omitted, so a reader can tell a deliberate gap from an oversight.

| Clause | Why not rendered | Evidence instead |
|---|---|---|
| A4 — switching to a scoped ordering filters and states its exclusion count | A segment is an `AXRadioButton`; `axkit press` matches `AXButton` only, so there is no background-safe way to switch it. The alternative is bringing the window to the front, which outranks the extra coverage. | `RegistryPresentationTests`: *a scoped ordering filters to the universe it can speak about*; *the exclusion note names the count and appears only when something was excluded*; *an ordering whose universe is empty says why, and best match never does* |
| §8 — `↓`/`↑`/`Return` inside the table | Posting `↓` to a backgrounded app moves the **sidebar** selection (observed: Discover → Evals), because focus is in the sidebar. That is §8's own focus order (sidebar → search → ordering → table) working, not a defect — Escape lands only because an open sheet takes key focus. Reaching the table needs focus in the table, which needs the window in front. | `DiscoverBoardTests`: *Return opens the detail sheet and is left unhandled when nothing is selected*; *the selection moves through the visible rows, not the whole response*; *Escape dismisses the sheet first and clears the selection second, never both* |
| A6 — the **stdio** capability statement (verbatim argv, "runs with your user account") | All three rows in `registry-search.json` are HTTP installs, so no stdio row exists to render. | `RegistryCapabilityTests`: *the three install shapes each get their own statement*; *a newline in an argument cannot inject a second line into the command block* |
| A6 — the two-cell provenance mark with **both** cells filled | The fixture's only `source: "both"` row is `smithery:github`, whose id prefix says Smithery — which is the honesty decision working, and is why `dateMeaning` reads the prefix rather than `source`. No row in the shipped fixture is genuinely in both indexes. | `RegistryPresentationTests`: *a `both`-stamped row whose id is Smithery's still reads as first-published* |
| A10 — the debounce, and a re-query keeping its rows | Request counting needs a recording client; the rendered app has no observable request count. | `DiscoverBoardTests`: *a typed burst is one request, not one per keystroke*; *Return searches now and cancels the debounce rather than racing it*; *a re-query keeps the rows that are already on screen*; *a failed re-query keeps the last good rows and marks them stale* |
| A9 — token parity, light and dark | A source-level property, not a rendered one. | `DiscoverSurfaceTests`: *no Discover source names a colour or a size literally*; *attention colour is used for the archived warning and nothing else*; plus the repo's `no-raw-design-values` lint over 51 files |
| A1 — the four board-registry tripwires | Unit-level invariants about a `Set`, with no rendered surface. | `ShellIntegrationTests` (exact installed set, exact-complement both ways, scaffolded count) and `ActivityBoardContractTests` (same set, count, and the still-scaffolded example) |

---

## Gate evidence — the merged tree, verbatim

Run from `.worktrees/M5` with `make -C`, so a lint run cannot silently lint the main checkout.
`make lint` runs swiftformat before swiftlint and short-circuits, so this is the full target
reaching its end rather than a formatter pass standing in for one.

```
===== LINT =====
Done linting! Found 0 violations, 0 serious in 313 files.
no-raw-design-values: scanning 72 files
no-raw-design-values: 51 files under the geometry and boundary rules
no-raw-design-values: clean
no-wire-codable: clean over app/Sources/RouterCore/Control app/Sources/RouterCore/Registry app/Sources/RouterCore/Usage app/Sources/RouterCore/Auth
no-wire-codable: 1 exemption(s) recorded
===== TEST =====
Test run with 1021 tests in 131 suites passed after 1.857 seconds.
===== PARITY =====
parity: 358 vector cases compared (floor 358)
===== BUILD-MAC =====
** BUILD SUCCEEDED **
```


### One test in this suite is flaky, and it is not this item's

`SettingsAndMenuBarTests.pollingIsIdempotent` (M8's) fails roughly four runs in five under the
full parallel suite:

```
Test "startPolling is idempotent — two calls run one loop" recorded an issue at
SettingsAndMenuBarTests.swift:117: Expectation failed: (model.trackerState → nil) != nil
```

**Measured, not assumed, and measured to be independent of this branch:**

- It passes **5 of 5** runs in isolation (`swift test --filter pollingIsIdempotent`) and fails
  under full-suite load, so it is load sensitivity rather than a logic error.
- It fails identically at `96aac93` with this item's gap-fix stashed — 3 of 3 runs — so it predates
  every change in `6c0018b`.
- Nothing on this branch touches the polling path. `ShellModel` gains one member (`discoverBoard`);
  `startPolling`, `stopPolling` and `trackerState` are untouched.

The cause is line 117: `try await Task.sleep(for: .milliseconds(120))` and then an assertion that a
poll has run. It is the same defect class M5 fixed in its own suite in `3e92c0b` —
`aFailedRequeryKeepsItsRows` fired a task, slept 100 ms, and reported the machine rather than the
code — and the fix is the same shape: await the condition instead of a duration.

**Not fixed here, deliberately.** It is another item's file, and the standing rule is to report a
change outside this item's surface rather than make it. Reported to the orchestrator with the
reproduction above so it can be scheduled as a one-line change; left as-is, every runner's gate
after this one has a ~80% chance of a red suite for a reason unrelated to their work.

### The rebase, and the tripwire that the conflict did not mark

Rebasing onto main across M8's merge produced the expected union conflicts in
`ScaffoldPane.swift` and `ShellWindow.swift`, plus three in the test files — all resolved as unions,
never by picking a side.

One assertion was **not** marked as a conflict and still failed:

```
Test "this build installs exactly the boards that have shipped" recorded an issue at
ShellIntegrationTests.swift:263: Expectation failed: (BoardRegistry.scaffolded.count → 3) == 4
```

`ShellIntegrationTests` pins the scaffolded count in a second place, outside the region git marked,
so the rebase was clean and the suite was still red. That is the tripwire doing its job: a board
landing has to be a deliberate edit in every place that counts boards, and a clean rebase is not
evidence that it was.

The `mac-shell.sh` Release gate still parses the declaration correctly at five members —
`INSTALLED_LIST` reads `.servers, .skills, .activity, .settings, .discover`, `INSTALLED_COUNT` is 5
against a `DEST_TOTAL` of 8, so scaffolds correctly still remain. The line is 108 characters
against the repo's 110 limit, which is the constraint the next board to land will break: it needs a
different parse, not a longer line.

## Out-of-family gate

`codex` was unavailable for this fleet — the account is at its usage limit until 2026-08-20, which
is past this fleet's horizon. Recorded here so the weakness travels with the evidence:

**codex: usage limit → claude (downgrade).**

The Phase D completeness critic ran instead as a fresh `claude -p` opus-5 session with no shared
context, briefed adversarially: told to refute rather than confirm, and told that an inability to
find defects is a failed review rather than a pass. Its prompt and output are recorded in the
completion note. The weakness this leaves is real and worth naming: every reviewer in this item's
pipeline is Claude auditing Claude.

The trap that makes the downgrade necessary rather than optional: `codex exec` **exits 0** on a
usage limit, so a gate keyed on `$?` records a pass for a review that never ran. The honest tells
are the `ERROR` line in the log and a missing or empty `-o` file.
