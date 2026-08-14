# plan-I3 — iPhone: Triage, Queue and Library

**Spec:** `planning/specs/spec-I3.md` (Ready for Work)
**Design representation:** `design/mocks/i3-phone-triage.html`
**Branch / worktree:** `ai/i3` in `.worktrees/I3`, from `main` @ `ba139d4`
**Size tier:** **Large.** Three data surfaces, two persisted stores, one new factory, three copy
manifests, and the retirement of a placeholder that four merged tests reference.

---

## The shape of the work, and the one thing that decides it

Every layer that can live in `MCPRouterKit` does, because the kit imports no UI framework
(`SWIFT_PRACTICES.md` §8) and is therefore testable by `swift test` on the macOS host without a
simulator. **The views under `MCPRouterUI/Phone/` are left holding no logic at all**: they render a
state value that a kit type computed. That is what M4 learned the hard way — it moved a view's
decision into `SkillPresentation` so the view became a `switch` with no logic, and that is the only
reason its guards could be proven without an accessibility grant.

So the split is:

| Layer | Holds | Proven by |
|---|---|---|
| `MCPRouterKit/Triage/` | models, stores, derivations, state resolution, three copy manifests | `swift test` on the host — the bulk of the assertions |
| `MCPRouterUI/Phone/{Triage,Queue,Library}/` | views that render a resolved state | host view-tree tests, then one simulator pass |
| `MCPRouterIOS/` | the client factory's wiring, the queue and dismissal directories | the device lane |

Views go in subdirectories **under `Phone/`** because `PhoneSourceGuardTests` enumerates that
directory recursively; a sibling root would be silently unscanned (A29).

---

## Phase A — the kit: stores, models and derivations

Nothing renders in this phase. It ends with `swift test` green and the two persistence failure modes
provably distinguishable from emptiness.

**A1 · `MCPRouterKit/Discover/CapabilityQueue.swift` — widen for the reader.**
Add `CapabilityQueueReader { func all() async throws -> [QueuedCapability]; func remove(_ id: String) async throws }`.
`FileCapabilityQueueWriter` conforms — it already reads the file; `all()` is `try read()` and
`remove` is read-filter-write through the same atomic path.
**`InMemoryCapabilityQueue.all()` becomes `async throws`** and throws its injected `failure`, which
is the change that makes A17's unreadable state drivable from a test at all (spec A19). Source-
breaking on a merged type; its callers are previews and tests and they move in this commit.

**A2 · `MCPRouterKit/Triage/DismissalStore.swift` — the second persisted set.**
`DismissedCapability { id, displayName, dismissedAt }`,
`DismissalStoreError { unreadable(String), writeFailed(String) }`,
`protocol DismissalStore`, `actor FileDismissalStore` over `dismissed-capabilities.json`, and
`actor InMemoryDismissalStore(failure:)`. **Written as a deliberate mirror of
`FileCapabilityQueueWriter`, case for case**: missing file → empty; present-and-undecodable →
`unreadable`; atomic write; error propagates. A9's whole point is that the dismissal set fails the
same way the queue does, so the two must not drift — a test asserts both stores treat a corrupt file
identically.

**A3 · `MCPRouterKit/Triage/CapabilitySummary.swift` — the row's one line.**
`CapabilitySummary.resolve(for: RegistryEntry) -> CapabilitySummary { clauses: [Clause], attn: Bool }`
over the **seven** `CapabilityPlate` derivations (spec A6), including the `host == nil` split and the
Smithery credential admission. **It calls into `CapabilityPlate`'s existing derivation rather than
restating it** where the shapes allow, so the row and the plate cannot come to disagree about the
same entry; where the plate's output is plate-shaped, the shared predicate is extracted and both
read it. Extraction, not duplication — a second copy of a security derivation is the defect.

**A4 · `MCPRouterKit/Triage/TriageBuckets.swift` — the derived sets.**
`Bucket { undecided, queued, dismissed }`; `TriageBuckets.resolve(results:queued:dismissed:)` with
`undecided = results − queued − dismissed`, **not** filtered on `installed` (A7, and D-i3-d records
why). Counts come off these sets and nowhere else.

**A5 · the three copy manifests.** `MCPRouterKit/Triage/TriageCopy.swift`,
`QueueCopy.swift`, `LibraryCopy.swift` — siblings of `PairingCopy`/`DiscoverCopy`, never extensions.
Each keyed by its own `Key` enum, `CaseIterable`, with `DiscoverCopy`'s **enumerated-`Token`**
substitution (A25) so a typo'd `{mack}` fails a test rather than rendering to the user.
`LibraryCopy` carries a `narrowing` key returning `PairingCopy.neverInstalls` **verbatim** (A30/F6).
Split from the start — three files, three vocabularies — because I2's single manifest hit the
400-line cap mid-item and a previous run silenced three lint rules at file scope rather than
splitting it.

**A6 · `MCPRouterKit/Triage/TriageSurfaceState.swift`, `QueueSurfaceState.swift`,
`LibrarySurfaceState.swift`.** One enum per surface covering that surface's states from the matrices,
including `dismissalsUnreadable` on Triage and `unreadable` on Queue. Exhaustive `switch` to copy, so
a tenth state fails to compile rather than shipping blank (A25). Triage inherits I2's three warning
classes by calling I2's existing classifier rather than re-implementing the prefix match.

**Gate A:** `make test` exit 0, captured as `cmd > /tmp/f.txt 2>&1; echo $?` — never through a pipe.

---

## Phase B — the views

**B1 · `Phone/Triage/`** — `TriageScreen`, `BucketSegments`, `TriageRow`, `TriageRowDetail`,
`TriageCommitBar`, `UndoBar`.
The row is **two buttons**, not one (A3): a leading `Button` wrapping a 22pt box in a 44pt frame, and
a second `Button` over the meta block toggling expansion. The capability line uses
`.fixedSize(horizontal: false, vertical: true)` and no `lineLimit`; **the name uses
`.lineLimit(1)` with `.truncationMode(.tail)`** — that asymmetry is the whole of the two prototype-bug
fixes and it is one assertion each.
Selection lives in one `@State private var selected: Set<String>` on `TriageScreen`, cleared on
appearance and on bucket change (A2). The commit bar is a conditional subview — **absent**, not
`.disabled()`, when the set is empty and a Mac is paired; **present and dimmed from first
appearance** when no Mac is paired (A2's named cell).

**B2 · `Phone/Queue/`** — `QueueScreen`, `QueueRow`.
No send control (A16). No section header (A15/F14). Remove is a 44pt trailing button; the undo bar is
`UndoBar` reused from B1.

**B3 · `Phone/Library/`** — `LibraryScreen`, `LibraryRow`, `SkillsAbsentBlock`.
`LibraryRow` renders `neverUsed` as "never started" and an idle duration only where
`usage.calls > 0` (A21) — the criterion exists because `idleSec == 0` is byte-identical for "idle
this instant" and "never started". The screen holds **no reference to any mutating client method**
(A22), which is asserted by scanning its sources.

**B4 · `PhoneMetric` additions** under `// MARK: - Triage, Queue, Library (I3)`. Every new value
derived or cited, never picked: the checkbox box from the existing radius formula, the segment height
from the control ladder.

**B5 · `PhoneShell.content(for:)` becomes an exhaustive `switch`** over `Tab`, one case per surface,
`.settings` last (A30). `awaitingKey`, `AwaitingTab` and **all four** `PairingCopy` awaiting keys are
deleted — `.discoverAwaiting` included, which has had no caller since I2.
`PhoneCopyTests.narrowingPlacement` moves to `[.settingsNeverPaired, .pairedSuccess]` with a sibling
assertion that `LibraryCopy.narrowing == PairingCopy.neverInstalls`, so the invariant it protects
survives the move.

**Gate B:** `make test` exit 0; `make build-mac` and the iOS build both succeed.

---

## Phase C — the app wiring

**C1 · `MCPRouterIOS/PhoneClientFactory.swift`** (A32). The iOS analogue of `ShellClientFactory`,
same two-branch shape and same reason: `choice(isDebugBuild:environment:)`, Release takes `.live` and
**ignores the environment**, Debug reads `MCPROUTER_SCENARIO`. `isDebugBuild` is a parameter rather
than a read, so a Debug test run can assert the Release branch — the only way the rule is checkable.

**C2 · `MCPRouterIOSApp` injects the real things**: the client from C1, and
`FileCapabilityQueueWriter` / `FileDismissalStore` over Application Support (A18). Those initializers
throw; the failure is **handled and surfaced**, never `try?`-ed into an in-memory fallback — a
fallback there would silently reproduce the exact bug A18 exists to fix.

**Gate C:** both builds succeed; the Release-branch test is green.

---

## Phase D — proving, and the critic

**D1 · Red-green the guards.** Every test whose job is to catch drift is *seen to fail*
(`SWIFT_PRACTICES.md` §7). Planned mutations, each with the assertion that should kill it:

| # | Mutation | Must be killed by |
|---|---|---|
| M1 | selection set starts populated instead of empty | the A2 default-state assertion |
| M2 | capability line gains `.lineLimit(1)` | the A5 no-truncation assertion |
| M3 | `DismissalStore.read` returns `[]` on a decode failure | the A9 unreadable-vs-empty test |
| M4 | `CapabilityQueueReader.all` returns `[]` on a decode failure | the A17 unreadable-vs-empty test |
| M5 | the Smithery credential clause is made unconditionally `--attn` | the A6 no-noise assertion |
| M6 | `PhoneClientFactory` honours the environment in Release | the A32 Release-branch test |
| M7 | `content(for:)`'s `.library` case returns `PhoneSettingsScreen` | the A30 per-tab copy assertion |
| M8 | `neverUsed` renders as "idle 0s" | the A21 never-started assertion |

M7 is there specifically because it is the failure the spec's first draft would have shipped, and a
test that cannot fail on it is not a test.

**Filter discipline:** `swift test --filter` takes the **function name**, never the `@Test` display
string. A display-name filter matches nothing and reports *"Test run with 0 tests in 0 suites
passed"* — a green that means nothing. Every filter used is confirmed to match the intended test
before any red or green from it is believed.

**D2 · In-family completeness critic.** `codex: usage limit → claude (downgrade)` — the lane is
account-limited to 20 Aug and **exits 0 on the limit**, so it is neither probed nor keyed on. A fresh
`claude -p` opus-5 reviewer, briefed to refute, told that finding nothing is a failed review. Every
finding dispositioned: fixed, rejected with a citation, or registered as a child.

---

## Phase E — acceptance, and only what changed

**One script, `scripts/acceptance/i3-phone-triage.sh`, covering my three surfaces and nothing else.**
Run **once**, when the surfaces are complete; re-run only after a change to the same surface.

- **It does not re-test Discover, pairing or Settings.** Those are I1's and I2's, evidenced in
  `planning/evidence/I1-acceptance.md` and `I2-acceptance.md`. Re-running a passing check against
  unchanged code has one possible outcome, and a check whose result you can predict is not evidence.
- **It does not source `scripts/acceptance/board-registry.sh`.** That reader answers a question about
  the **Mac** — whether a destination renders its board or the placeholder. The brief is right that
  the Mac's scaffolded set is now empty and derived; it is also the wrong device. The phone's
  equivalent guard is the `content(for:)` dispatch, and the script reads **that**, written the way
  `board-registry.sh` is written and for the same reason: it collects the whole `switch` body rather
  than matching one line, so reformatting cannot make it quietly match nothing and read as a pass.
- **One simulator, reused**, as I1 and I2 did. One boot, one pass, quit.
- **Appearance is asserted against the appearance actually set.** An earlier iOS assertion in this
  fleet pinned dark unconditionally and failed reporting `#ECECEE` — the *light* ground rendering
  perfectly correctly. The script sets the appearance and asserts the matching column.

**Evidence** appended to `planning/evidence/I3-acceptance.md`: one row per screen — screen, the actual
command or AX path, the commit SHA, result. Append, never rewrite.

---

## Phase F — gates and stop

`make lint`, `make test`, `make build-mac`, the iOS build, the acceptance script, the parity gate.
Each captured as `cmd > /tmp/f.txt 2>&1; echo $?`.

**Three measured traps this repo has already paid for, applied here:**
1. `make lint` runs `swiftformat --lint` **first and short-circuits**, so a "0 violations" line from
   the swiftlint half does not mean the target passed. Only the **exit code** is believed.
2. `make format`'s wrapping **adds lines** and has pushed files past the 400-line cap, turning one
   red gate into another. Any format run is followed by a re-count, not by an assumption.
3. **No lint limit is raised, ever.** If a file is too long it splits on a real seam. That is why the
   copy manifests are three files from the start rather than one that grows into the problem.

Then **commit on `ai/i3` and stop.** No push, no merge — the orchestrator serializes merges.

---

## Risks, and what each one would look like

| Risk | Signal | Response |
|---|---|---|
| `CapabilitySummary` duplicating `CapabilityPlate`'s derivation instead of sharing it | two places to change when a clause changes | extract the predicate; a test asserts row and plate agree on every fixture entry |
| The four merged tests that reference the placeholder | red on a rebase, not on the branch | they are found and moved in Phase B, not discovered at merge — the M2/M4 merge-only defect is this fleet's most repeated lesson |
| Three new copy manifests plus three state files pushing the 400-line cap | `make lint` exit 2 | already split on the real seam; if one still grows, it splits again |
| The simulator lane being slow or memory-starved under a concurrent fleet | `Killed: 9`, as I1 hit | one simulator, one pass; if it dies, report it as a blocked check rather than faking a pass |
