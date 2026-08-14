# plan-M7 — Evals and Cleanup

**Spec:** `planning/specs/spec-M7.md` (amended after its gate REJECTED the first draft — read the
gate section at its end before this file) · **Brief:** `planning/features-to-triage/M7-evals-cleanup.md`
**Design representation:** `design/mocks/html/m7-evals-cleanup.html`
**Branch:** `ai/m7` · **Worktree:** `.worktrees/M7`
**Tier:** Large — two boards, a new Kit subsystem, a persisted store, and a shared-registry edit that
breaks merged tests on purpose.

---

## 0. What this plan is answering

The spec decided *what* ships and *why it is honest*. This plan decides *where each line goes, in
what order, and what proves it*.

**This is the second draft.** The first was written against the first draft of the spec, whose
central mechanism the spec gate disproved by reading the router's source. The correction is recorded
in the spec; its consequence for this plan is one sentence:

> **The reading on screen is always live. The store holds history only.**

Every verdict a board renders is computed from the response it just fetched. Nothing on screen is
ever read back from the store. A stored run is *evidence*, stamped with the version it was gathered
against, and a stored run whose stamp no longer matches is labelled invalidated and never presented
as a reading of how things are now. That is the brief's one hard rule, stated exactly, and it is
simpler than the model it replaces.

---

## 1. Grounding — measured, not assumed

Every input the eleven checks name was verified present on the merged wire types before this plan was
written. The table is unchanged from the first draft **except** for the two rows the gate corrected.

| Check input | Type | File | Verified |
|---|---|---|---|
| `indexError`, `indexedAt`, `tools`, `hash`, `placard`, `pendingChange` | `MCPServer` | `Sources/MCPRouterKit/Control/Models.swift` | ✓ |
| `auth.supported`, `auth.authorized` | `ServerAuth` | same | ✓ |
| `usage.calls`, `usage.errors` | `ServerUsage` | same | ✓ |
| `callsServed` — **present but deliberately unused** | `MCPServer` | same:77 | ✓ |
| `presence: [String: SkillPresence]` — a dictionary, keys may be **absent** | `Skill` | `Control/SkillModels.swift` | ✓ |
| `SkillClient.status == .unreadable` — the per-**client** signal | `SkillClient` | same | ✓ |
| `source` closed enum, `.standalone` carrying **no version** | `SkillSource` | same | ✓ |
| `provenance`, `held`, `description` | `Skill` | same | ✓ |
| `since` | **`UsageSummary`** | `Control/Models.swift:186` | ✓ |
| `asControlAPIDate`, `shortAgo` | `String` / free fn | `Kit/Formatting/RelativeTime.swift` | ✓ |
| `reindex`, `remove(_:keepHistory:)`, `resetUsage`, `skills`, `servers`, `usageSummary` | `ControlAPIClient` — **F3's**, not M3's | `Control/ControlAPIClient.swift` | ✓ |
| `removeToolsConsequence`, `removeConsequence` | public statics | `MCPRouterUI/Boards/ServersBoardModel.swift:267,286` | ✓ |
| `BoardRegistry.installed = [.servers, .skills, .activity]` | | `MCPRouterUI/Shell/ScaffoldPane.swift:32` | ✓ |

### What `hash` actually is — quoted, because the first draft got it wrong

`src/control.ts:163` sends `hash: upstreamHash(u)`. `src/config.ts:98`:

```js
const material = isStdio(u)
  ? JSON.stringify(['stdio', u.command, u.args, u.cwd ?? null, Object.entries(u.env).sort(...)])
  : JSON.stringify([u.transport, u.url, Object.entries(u.headers).sort(...)]);
return createHash('sha256').update(material).digest('hex').slice(0, 16);
```

A digest of the **declaration**. It moves when the entry is edited and at no other time. It is a
perfectly good stamp for *evidence about a declared server* — which is what history is — and a
useless one for governing a live verdict, which is why live verdicts no longer read it.

### DESIGN.md rules the gate cited, verified in the file

| Claim | Line | Verified |
|---|---|---|
| `--t4` is "disabled controls only — never live text" | `DESIGN.md:81` | ✓ — invalidated history renders `--t3` |
| `⌘R` is "Reset the selected server" | `DESIGN.md:319` | ✓ — re-check takes `⇧⌘R` |
| §6 mandates a "not evaluated" skill string | `DESIGN.md:279–280` | ✓ — **reported, not edited**; see §9 |

### The merged tests this item must edit, and why that is the designed action

| File:line | Asserts | Becomes |
|---|---|---|
| `ShellIntegrationTests.swift:260` | `installed == [.servers, .activity, .skills]` | `+ .evals, .cleanup` |
| `ShellIntegrationTests.swift:263` | `scaffolded.count == 5` | `== 3` |
| `ActivityBoardContractTests.swift:191–192` | the same pair | the same edit |
| `ShellIntegrationTests.swift:304` | `#require(BoardRegistry.scaffolded.first)` | unchanged — `.discover` is still scaffolded |

M5 (`.discover`) and M8 (`.settings`) edit the same two lines on their own branches. Textual conflict
at merge is expected and is the orchestrator's to serialize; the resolution is a set union.

---

## 2. Architecture

M4's best move, copied wholesale: **a view's decision moves into a Kit function returning an enum,
and the view becomes a `switch` with no logic.** Nothing below needs SwiftUI, a window, or a running
router to be proven.

```
MCPRouterKit  (no UI frameworks — SWIFT_PRACTICES §8)
  Checks/CheckModels.swift        verdict, id, result, stamp, stored run, subject key
  Checks/CheckCopy.swift          every statement, reason and disclosure string
  Checks/ServerChecks.swift       6 pure functions over MCPServer
  Checks/SkillChecks.swift        5 pure functions over Skill + [SkillClient]
  Checks/CheckPresentation.swift  tally, filter, stamp rendering, history invalidation
  Cleanup/CleanupPresentation.swift  candidacy, observation window, track geometry, copy

MCPRouterUI  (macOS only)
  Checks/CheckHistoryStore.swift  the bounded local store — HISTORY ONLY
  Boards/EvalsBoard*.swift        board, model, row, inspector, metrics
  Boards/CleanupBoard*.swift      board, model, row, inspector, sheets, track
```

### 2.1 The vocabulary is observation, not grading

```swift
public enum CheckVerdict { case passed, failed, unknown, notApplicable }
```

Rendered as **confirmed · not met · not observed · not applicable**. The cases keep engineering names;
the *words on screen* carry no grading verb, which is the gate's strongest single correction: it is
the vocabulary, not the subtitle, that makes a re-tabulation read as a grade.

The filter segments use the same four words, so nothing on screen has two names — the first draft had
a segment reading *Unchecked* beside a tally reading *unknown*.

### 2.2 The checks are total functions, and three of them were reporting vacuous confirmations

Signature: `(MCPServer) -> CheckResult` / `(Skill, [SkillClient]) -> CheckResult`. No optionals, no
throwing, no ordering dependence.

The four the gate corrected, each of which is the `callsSucceed` defect in a new place — a
confirmation reported for a question nobody asked:

| Check | Was | Now |
|---|---|---|
| `callsSucceed` | `.unknown` when `calls == 0` (correct from the start) | unchanged — this is the one the first draft got right |
| `declaresTools` | confirmed from a `tools` count left over from a since-failed index | **`.unknown` whenever `indexError != nil`** |
| `updateWantsNoMore` | vacuously confirmed for every skill with `held == nil`, which is most | **`.notApplicable` when `held == nil`** |
| `originUnchanged` | asserted an unmoved origin for a `.standalone` skill, which has none | **`.notApplicable` for `.standalone`** |
| `described` | claimed an `unknown` for an unreadable directory — **no such field exists** | binary over `description` |

`.notApplicable` rather than `.unknown` for the middle two, matching how `authorized` already treats a
transport that carries no credentials: the question does not arise, which is a different sentence from
"we could not tell".

**`reachable` reads two types**, and the first draft conflated them. `SkillPresence.unreadable` is
per-skill-per-client in `Skill.presence`; `SkillClientStatus.unreadable` is per-client in
`SkillClient.status`. `presence` is a **dictionary** whose key for a given client may be absent, and
an absent key is not evidence of absence. So:

```
.present anywhere                                        -> passed
else, any skills-capable client unreadable by EITHER signal -> unknown, naming the client
else (every capable client read, none has it)            -> failed
.unsupported clients never contribute to either branch
```

**`usage.calls`, never `callsServed`.** Both exist on `MCPServer`. `callsServed` is the process's
lifetime tally; `usage.calls` is the resettable recorded window that `since` describes. Every sentence
on both panes is scoped to that window, so it is the only field consistent with what is said.

### 2.3 Stamps govern history, not the screen

```swift
public struct Stamp: Codable, Hashable, Sendable {
    public let value: String
    public init?(_ value: String?)            // failable — the ScaffoldedDestination idiom
    public static func forServer(_: MCPServer) -> Stamp?   // hash — the DECLARATION digest
    public static func forSkill(_: Skill) -> Stamp?        // plugin version
}
```

A `.standalone` skill has no `pluginOrigin`, so `forSkill` returns nil and there is nothing to hand
the store — the refusal is a type, not a rule a caller remembers (A12).

```swift
public enum HistoryRowState: Equatable, Sendable {
    case current(Stamp)
    case invalidated(stored: String, live: String)   // "gathered against X · now Y", at --t3
}
public static func historyRowState(run: StoredRun, live: Stamp?) -> HistoryRowState
```

`--t3`, not `--t4`: DESIGN.md:81 binds `--t4` to disabled controls only and an invalidated history row
is live text.

**A10 is now structural rather than universally quantified.** The first draft asserted "there is no
input for which a stale verdict renders as a current pass", which is unbounded, untestable — and, per
the gate, false. It is replaced by: *the board's row type has no path to `CheckHistoryStore`*, asserted
by a source guard. A property nothing can violate beats a claim nothing can check.

### 2.4 The tally is a list of segments, and cannot be collapsed

`CheckPresentation.tally(_:) -> [TallySegment]`, a segment being `{ count, noun, tinted }`. Only *not
met* is tinted (`--fail`). `CheckResult` carries its own `statement`, so **a verdict and the sentence
it judges are the same value** — there is no call site holding one without the other. That is A17,
restated against the row model after the gate showed the first draft's four-literal ban let
`4 passed · 1 failed · 1 unknown` through.

### 2.5 The store (`CheckHistoryStore.swift`)

`@MainActor`, one JSON file in Application Support, directory injected so tests use a temp dir.

```swift
@discardableResult
func record(subject: SubjectKey, stamp: Stamp?, results: [CheckResult], at: Date) -> Bool
func history(for subject: SubjectKey) -> [StoredRun]      // newest first, ≤ 20
```

Returns `false` and writes nothing when `stamp` is nil — the test asserts the file's bytes are
unchanged. Cap 20 per subject, oldest evicted. A corrupt or unreadable file starts empty and the pane
says the history could not be read; it does not claim the checks never ran, and it does not fail the
board.

**Not a second channel:** it stores the app's record of the router's own observations. It sends
nothing and asks for nothing the router does not already serve.

### 2.6 Cleanup

```swift
public enum CleanupCandidacy { case candidate(reason: String), notACandidate, heldOut(reason: String) }
```

- **server:** candidate iff `usage.calls == 0` **or** `indexError != nil` **or**
  (`indexedAt != nil && tools == 0`). Never a time threshold.
- **skill:** `heldOut` for **every** skill when *any* skills-capable client is `.unreadable`;
  otherwise candidate iff every capable client reports `.absent`.

**Badge reconciliation.** `Destination.badgeSource` binds `.cleanup` to `.serversNeverUsed` only, and
this pane lists more. A line under the header states the relationship rather than leaving a badge of 3
to be reconciled against a list of 9. `BadgeSource` itself is a merged shared surface: reported, not
changed.

**Window:** `UsageSummary.since` → `asControlAPIDate` → `window(since:now:) -> {days, label, isWeak}`,
`isWeak` under 7 days. Unparseable ⇒ the subtitle drops the clause and the banner does not fire; no
number is substituted.

**Track:** `trackFraction(days:reference:)` clamped to `0...1`, so beyond the 30-day reference the bar
is pegged full and the mono figure carries the real value. Tinted `--attn` under 7 days — the same
condition as the banner, shown twice, which A22 now names explicitly.

---

## 3. Build order

### Phase A — Kit *(no UI, no dependencies)*
- A1 `CheckModels.swift` — verdict, id, result, `SubjectKey`, `Stamp`, `StoredRun`. **written**
- A2 `CheckCopy.swift` — statements, reasons, subtitles, footers, disabled reasons. **written**
- A3 `ServerChecks.swift` — six functions + `all(_:)`, with the `declaresTools` correction.
- A4 `SkillChecks.swift` — five functions + `all(_:clients:)`, with the three corrections.
- A5 `CheckPresentation.swift` — `historyRowState`, `tally`, `Filter` (all/not met/not observed/
  unstamped) + `count(...)` returning nil for zero, and the input-field descriptor for A20b.
- A6 `CleanupPresentation.swift` — candidacy, window, track fraction, banner + subtitle copy.

**Gate A:** `swift build`, plus `CheckTests` and `CleanupPresentationTests` green.

### Phase B — the store
- B1 `CheckHistoryStore.swift` + tests (cap, eviction, refusal-to-write, corrupt-file recovery).

### Phase C — Evals *(depends on A, B)*
- C1 `EvalsBoardMetrics.swift` + `EvalsBoardStates` (exhaustive over `SurfaceState`).
- C2 `EvalsBoardModel.swift` — M4's four `LoadState` shapes, reading **both** `servers()` and
  `skills()`; filter, **search**, selection, sheet, `recheck()`, `recheckAll()`, key intents.
- C3 `EvalsBoardRow.swift` — tile, kind, tally segments, live stamp.
- C4 `EvalsInspector.swift` — per-check rows **each rendering the field name and value it was computed
  from** (A20b), then the live stamp, then history newest-first with per-row invalidation.
- C5 `EvalsBoard.swift` — assembly, header, segmented filter + `SearchField`, footer, sheet, keys.

### Phase D — Cleanup *(depends on A, B; file-disjoint from C)*
- D1 `CleanupBoardMetrics.swift` + `CleanupBoardStates`.
- D2 `CleanupBoardModel.swift` — load, candidacy, held-out count, window, `remove`, `resetUsage`.
- D3 `CleanupObservationTrack.swift` — drawing only.
- D4 `CleanupBoardRow.swift`, D5 `CleanupInspector.swift`,
  D6 `CleanupSheets.swift` — the removal dialog calling M3's two consequence functions, **and** the
  reset-history dialog naming what is lost (A15b).
- D7 `CleanupBoard.swift` — assembly, segmented filter + `SearchField`, badge-reconciliation line.

### Phase E — Registration *(last, deliberately)*
- E1 `ScaffoldPane.swift:32` — `installed` gains `.evals, .cleanup`.
- E2 `ShellWindow.swift` — two real cases; `.discover, .inbox, .settings` stay the `EmptyView()`
  branch with its comment updated.
- E3 `ShellModel.swift` — two `lazy var` board models.
- E4 The merged assertions in §1.
- E5 Menu bar commands, re-check on **`⇧⌘R`** — `⌘R` remains DESIGN.md §8's reset.

Until E, `ScaffoldedDestination(.evals)` still constructs and the placeholder still renders, so C and
D build and unit-test against a surface the user cannot yet reach and registration is one reviewable
commit.

---

## 4. Tests — one row per acceptance criterion

Kit tests need no host. UI tests use a recording double conforming to `ControlAPIClient`, which must
implement `skills()` and `marketplaces()` (M4 added both); the house idiom for the ones a given double
does not serve is `throw .malformedResponse(detail: "this double serves no skills")`.

| AC | Test | Kind |
|---|---|---|
| A1–A3 | registry contains both; both `ScaffoldedDestination`s nil; complement holds | red→green |
| A4 | source guard over **all four** locations for run-count/duration/byte/memory tokens | source scan |
| A5 | `callsSucceed` over `calls ∈ {0,1,7}` × `errors ∈ {0,1,9}` | exhaustive |
| A5b | `updateWantsNoMore(held: nil)`, `originUnchanged(.standalone)`, `authorized(!supported)` all `.notApplicable` | per case |
| A5c | `declaresTools` `.unknown` for every `tools` value when `indexError != nil` | exhaustive |
| A6 | `reachable` over both unreadable signals independently **and** a missing `presence` key | exhaustive |
| A7 | one unreadable capable client ⇒ zero skill candidates + banner count | behavioural |
| A8 | window from `UsageSummary.since`; unparseable ⇒ clause dropped, banner silent | behavioural |
| A8b | `callsServed > 0, usage.calls == 0` ⇒ listed | measurement |
| A9 | weak banner iff `< 7d`, boundary asserted at exactly 7d | boundary |
| A10 | **source guard: no board row type references `CheckHistoryStore`** | structural |
| A10b | `historyRowState` over stored × live stamp cross product | exhaustive |
| A11 | invalidated run still in `history(for:)` | behavioural |
| A12 | `record(stamp: nil)` returns false **and file bytes unchanged** | measurement |
| A13 | 21 runs ⇒ 20 kept, oldest gone | behavioural |
| A13b | unstamped subject under `Unstamped`; cell renders `CheckCopy.unstampable`; history sentence present | behavioural |
| A14 | re-check on a server ⇒ exactly one `reindex`, no other write | exercised request |
| A14b | re-check on a skill ⇒ exactly one `skills()`, **zero writes** | exercised request |
| A15 | dialog strings `==` the two `ServersBoardModel` statics, compared to the functions | equality-to-source |
| A15b | reset dialog opens before any `resetUsage()`; cancel issues nothing | exercised request |
| A16 | skill remove disabled in every state; reason non-empty; no path to a skill write | behavioural + source |
| A17 | tally is ≥1 `(count, noun)` segment; `CheckResult.statement` non-empty for every id | structural |
| A17b | no grading verb in the four verdict nouns, over `CheckVerdict.allCases` | exhaustive |
| A18 | subtitle contains the disclosure, returned unconditionally incl. loading | behavioural |
| A19 | footer states skills are never executed by the router | string |
| A20 | forbidden phrases absent from all four locations, disclosure exempted by exact match | source scan |
| A20b | every check's inspector detail contains its field name and value | per check id |
| A21 | token test over `CheckVerdict.allCases` **and** source guard for `.live` | token + source |
| A22 | `--attn` only for the three named conditions incl. both track and banner | token |
| A23 | Cleanup zero accent-filled; Evals ≤1 | source scan |
| A24 | `scripts/lint/no-raw-design-values.sh` | lint |
| A25 | sentence case, no tracked uppercase | source scan |
| A25b | invalidated rendering resolves `--t3`, never `--t4` | token |
| A26 | nine states × two panes, **named fixtures** (§4.1) | exhaustive switch |
| A27 | skeleton row height == populated row height | measurement |
| A27b | `trackFraction` pegs at 1.0 beyond the reference | boundary |
| A28 | `⌘F` focuses a real `SearchField`; arrows/Return/Esc over the defined order; Return ≠ remove | behavioural |
| A29 | `⌘⌫` opens the sheet for a server, no-op for a skill | behavioural |
| A30 | every command in the menu bar with matching reason; re-check on `⇧⌘R` | behavioural |

### 4.1 The nine states — named fixtures, because A26 was untestable without them

| State | Evals fixture | Cleanup fixture |
|---|---|---|
| Default | 2 servers + 2 skills, mixed verdicts | 1 never-used server, 1 absent skill |
| Empty | `servers: [], skills: []` | all servers used, all skills present |
| Loading | `LoadState.loading` | same |
| Partial | one `SkillClient.status == .unreadable` | same, banner counts held-out |
| Error | `.failed(.server(status: 500, …))` | a refused `remove` leaves the row |
| Success | a re-check lands, tally + stamp update, history +1, no toast | row leaves, counts decrement, **nothing tallied** |
| Offline | `.failed(.routerNotRunning)` | same strings |
| Disabled | re-check with no selection | skill *Remove*, with its reason |
| Overflow | 120-char server name, fixed row height | same + a 400-day window pegging the track |

Plus **stale** — `LoadState.stale`, M3/M4's banner.

---

## 5. Gates

| Gate | Command |
|---|---|
| build | `swift build --package-path app` |
| tests | `swift test --package-path app` |
| lint | `scripts/lint/no-raw-design-values.sh`, swiftformat, swiftlint |
| acceptance | one Release launch, `open -g -a`, AX by PID / `proctor`, **Evals and Cleanup only**, quit |

Servers, Skills and Activity are merged, have their own evidence rows, and `git diff` over their files
is empty on this branch — cited, not re-run. Evidence appends to `planning/evidence/M7-acceptance.md`.

---

## 6. Risks

| Risk | Mitigation |
|---|---|
| The naming objection — a user reads a check as a test suite result | Vocabulary carries no grading verb (A17b); every check row shows the field and value it came from (A20b); verbs match the calls (A14/A14b); disclosure is the permanent subtitle (A18). **Residual and unmitigated:** the word "Evals" in the sidebar, window title, menu and deep link. That needs M9, which is a merged shared surface. Flagged in the report, not hidden here. |
| Registry edit collides with M5/M8 | Expected; resolution is a set union; not this branch's to resolve. |
| Local persistence read as a second channel | History of router-served observations only; no new endpoint, no write to the router. |
| History file corrupt | Start empty, keep the board working, say so. Tested. |
| Two boards in one item is a large diff | C and D are file-disjoint; E is one small commit. |

---

## 7. Stated deviations from the spec

1. **Row height** is `MetricToken.tableRows × 2` (48pt at the current token), not the spec's literal
   44pt. A literal would be a hardcoded size (`SWIFT_PRACTICES.md` §5) and would make M7's rows a
   different height from every other board. A27's binding requirement — skeleton equals populated —
   holds either way and is what the test asserts. *(The amended spec now says "fixed", not "44pt".)*
2. **`CheckPresentation.swift` is added** to the spec's file table: the decision functions belong
   neither with the copy nor with the checks, and putting them in the view is the mistake M4's
   precedent exists to prevent.
3. **`.notApplicable` is a verdict case**, which the spec's tables mark as "—". Making it a case
   rather than a nil keeps every check total.

---

## 8. Deferred children

| Suggested id | Title | Deps |
|---|---|---|
| R6 | Router-side behavioural eval runner — **servers only** | R3, R4 |
| R7 | Skills write endpoint (remove/disable) with preconditions and undo | R3 |
| R8 | Server soft-delete with a restore endpoint | R3 |
| **M9** | **Rename the `Evals` destination to `Checks`** — promoted: the spec gate's finding 29 makes this the difference between a structural disclosure and a footnote | M1, M7 |
| M10 | Amend `DESIGN.md` §6:279–280, whose "not evaluated" example describes a state that no longer exists | M7 |

## 9. Shared-surface changes wanted and deliberately skipped

- `Destination.title` `.evals` → "Checks". **Reported, not made** — M9.
- `DESIGN.md` §6:279–280's mandated "not evaluated" string. **Reported, not made** — DESIGN.md is
  authoritative and merged; a runner editing it unilaterally is how a design authority stops being
  one. M10.
- A `BadgeSource` case for Cleanup's actual predicate. Not added — it would be a count the router does
  not serve as such; the pane states the relationship in words instead.

---

## 10. The plan gate — in-family, and why

**codex: usage limit → claude (downgrade).** Every `codex exec` call returns an account-level usage
limit until 20 August, and `codex exec` **exits 0** on that limit, so a gate keyed on its exit code
would record a pass for a review that never ran. Run in-family instead: a fresh `claude -p` Opus 5
reviewer, briefed adversarially and told that finding no defects is a failed review. **Every reviewer
in this item's pipeline is Claude auditing Claude.**

Two lane failures were caught and rerun rather than recorded as passes: `timeout` does not exist on
macOS (38-byte output), and a missing `< /dev/null` aborted a run on a stdin warning (157-byte
output). Both are the empty-`-o`-file trap in a different costume — an exit code would have called
both a pass.

Verdict and tallies are appended below by the gate run.
