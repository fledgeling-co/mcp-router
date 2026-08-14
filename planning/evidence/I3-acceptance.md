# I3 — iPhone Triage, Queue and Library · acceptance evidence

**Append, never rewrite.** One row per screen: screen · how it was verified · commit · result.
Read this before testing anything. A row whose SHA-to-HEAD diff does not touch the files behind that
screen **is** the evidence — re-running a check whose result you can predict is not.

Branch `ai/i3`, worktree `.worktrees/I3`, rebased onto `main` @ `6e4b7f9` (clean, 0 conflicts).

---

## Scope, and what was deliberately not re-tested

This item added three phone surfaces and touched three merged types. It tested **those and nothing
else**.

| Not re-tested | Why | Existing evidence |
|---|---|---|
| Phone shell, pairing, Settings | I1's, unchanged by this item apart from the `initialTab` seed, which has its own guard | `planning/evidence/I1-acceptance.md` |
| Discover and capability detail | I2's, unchanged | `planning/evidence/I2-acceptance.md` |
| All eight Mac boards | Another device entirely. This item's diff over `Shell/` and `Boards/` is empty | `M1`–`M8` evidence files |

The one cross-device check that *was* run is deliberate and narrow: the Queue's copy says *"Open MCP
Router on {mac} to review them"*, which is only true if the Mac installs the Inbox board that reviews
them. That is asked of the Mac's own registry through `scripts/acceptance/board-registry.sh` rather
than through a fourth copy of a reader.

---

## The rendered lane — `scripts/acceptance/i3-phone-triage.sh`

One script, three surfaces, **one simulator, reused** (iPhone 16 Pro `29FEA02E`, already booted).
Run once when the surfaces were complete, then re-run only after a change to the same surfaces.

Appearance is asserted **against the appearance actually set**: the harness leaves the interface
style `.unspecified` and the suite asserts geometry and copy, never a colour. An earlier iOS
assertion in this fleet pinned dark unconditionally and failed reporting `#ECECEE` — the light ground
rendering correctly.

| # | Screen | How it was verified | Result |
|---|---|---|---|
| A1 | Triage dispatch | `content(for:)` `.triage` arm read from source, whole `switch` body collected | `TriageScreen` ✅ |
| A2 | Queue dispatch | same reader, `.queue` arm | `QueueScreen` ✅ |
| A3 | Library dispatch | same reader, `.library` arm | `LibraryScreen` ✅ |
| A4 | The placeholder | `awaitingKey` / `AwaitingTab` absent from `PhoneShell.swift`, **comments stripped first** | deleted, not bypassed ✅ |
| A5 | Mac Inbox exists | `board_registry_installed` over `ScaffoldPane.swift` | `.inbox` installed ✅ |
| A6 | Triage row targets | `tappableFrames` over the accessibility tree, 393×852 | 2 targets, both ≥44pt ✅ |
| A7 | Capability line | row height at 393 vs 240 via `sizeThatFits` | grows when narrowed — wraps, never truncates ✅ |
| A8 | Capability line content | every clause found in the accessibility tree | rendered whole ✅ |
| A9 | Loading → populated | skeleton vs real row height, `sizeThatFits` | equal within 12pt — the list does not jump ✅ |
| A10 | Each tab is real | shell hosted on `.triage`/`.queue`/`.library`, each surface's own copy found | 3/3, none rendered Settings ✅ |

`bash scripts/acceptance/i3-phone-triage.sh` → **exit 0**, *"PASS: I3 Triage + Queue + Library — 5
assertions, one simulator, nothing else driven"*.

**Two defects this lane found, both real and both fixed:**

1. **A 22pt tap target on the primary act of the surface** (A3/A27). `TriageCheckbox` already ended
   in a 44pt frame, so the row *laid out* correctly — but a `Button`'s hit region defaults to its
   label's drawn content, which is the 22pt rounded rectangle. The geometry looked right in every
   screenshot; only a measurement of the **target** could see it. Fixed with `.contentShape`.
2. **The script's own first version matched its own documentation.** A naive
   `grep -qE "awaitingKey|AwaitingTab"` reported the placeholder alive, because `PhoneShell.swift`'s
   doc comment *explains the shape that was deleted*. Comments are stripped before the scan now —
   the same failure `PhoneSourceGuardTests.stripped` exists to prevent, met from the shell side.

---

## The host lane

`make test` → **exit 0, 1306 tests in 158 suites.**

Inherited state for comparison: the branch arrived with **1233 tests**, against `main`'s 1234 — three
thousand eight hundred lines of I3 code had landed with a *net loss* of one test. The five suites
below are what closed that.

| Suite | Tests | Covers |
|---|---|---|
| `TriageBucketTests` | 18 | A6 seven clauses + the colour rule, A7 derivation, row/plate agreement |
| `DismissalStoreTests` | 12 | A9/A17 persistence, the two stores failing identically, A19 stored format |
| `TriageCopyManifestTests` | 14 | A8/A15/A20/A21/A25/A26, tokens, stray whitespace |
| `TriageModelTests` | 20 | A2/A12/A13/A14/A23/A24, selection, refused writes, state precedence |
| `TriageSourceGuardTests` | 9 | A1 no gesture, A22 read-only, A30 dispatch, A32 Release branch |

---

## Mutations — every guard seen to fail

`SWIFT_PRACTICES.md` §7: a test that has never failed is not known to work. Each mutation was
applied, measured, then **restored by re-applying the original edit** — never `git checkout` — and the
file's SHA-256 verified identical to its pre-mutation value. Every filter was confirmed to match the
intended test before any red or green from it was believed, because `swift test --filter` takes the
function name and a display-name filter reports *"0 tests passed"*.

| # | Mutation | Killed by | Mutated | Restored |
|---|---|---|---|---|
| M1 | selection set starts populated | `selectionStartsEmpty` | exit 1 | exit 0, hash ✅ |
| M2 | capability line gains `.lineLimit(1)` | `testCapabilityLineWrapsRatherThanTruncating` (iOS) | exit 65 | exit 0, hash ✅ |
| M3 | `DismissalStore.read` returns `[]` on a decode failure | `corruptDismissalFileIsUnreadable` | exit 1 | exit 0, hash ✅ |
| M4 | queue's decode failure returns `[]` | `bothStoresFailTheSameWay` | exit 1 | exit 0, hash ✅ |
| M5 | Smithery credential unconditionally `--attn` | `smitheryCredentialIsNotNoise` | **already live** | fixed |
| M6 | `PhoneClientFactory` honours the environment in Release | `releaseIgnoresTheEnvironment` | exit 1 | exit 0, hash ✅ |
| M7 | `content(for:)` `.library` returns `PhoneSettingsScreen` | `dispatchArmsAreCorrect` | exit 1 | exit 0, hash ✅ |
| M8 | `neverUsed` renders as an idle duration | `neverStartedIsNotAFreshness` | exit 1 | exit 0, hash ✅ |

**M5 was not a mutation — it was the shipped behaviour.** `CapabilitySummary.resolve` took its
attention severity from `CapabilityPlate.severity(of:)`, which marks the credential line `.attention`
for Smithery and non-Smithery hosts alike and separates them only by copy key. Every Smithery-hosted
install declares an `Authorization` unconditionally (`src/registry.ts:172-179`) and Smithery is a
majority of the corpus, so the attention colour fired on most rows — precisely the noise A6 exists to
prevent, and the opposite of what the type's own documentation claimed it did. Found by writing the
assertion the plan named and watching it go red against unmutated code.

`CapabilityPlate` itself was **left alone**: it is I2's merged surface, and its blanket severity is
defensible for a detail plate the user opened deliberately. The reduction to one line is
`CapabilitySummary`'s job, so the rule lives in the reduction.

---

## Gates

Each captured as `cmd > /tmp/f.txt 2>&1; echo $?`, never through a pipeline — `make ... | tail`
reports `tail`'s exit code, and a log in this repo has read *"lint exit: 0"* while every target
failed.

| Gate | Exit | Detail |
|---|---|---|
| `make lint` | **0** | 0 violations, 0 serious, 411 files |
| `make test` | **0** | 1306 tests, 158 suites |
| `scripts/acceptance/i3-phone-triage.sh` | **0** | 5 assertions, one simulator |

`make lint` was red twice before it was green, and neither was worked around. The first was
`swiftformat`'s `trailingCommas` / `indent` on the new files; `make format` fixed it, and every file
was re-counted afterwards because the repo has watched formatting **add** lines and push a file past
the 400-line cap. The second was a real `for_where` violation, fixed on the seam. **No limit was
raised and no rule was disabled.**

The `indent` failures were the interesting half: they collided with the copy fix. Swift strips a
multiline literal's indentation relative to its **closing** delimiter, and every closing `"""` in the
three manifests sat four columns left of its content — so **16 shipped strings began with four
spaces**. `swiftformat` wants content and delimiter at the same column, which produces the same
correct result in the house style, so the formatter settled it. `noStrayWhitespace` guards the whole
class rather than the sixteen strings.

---

## Phase D — the completeness critic

**`codex: usage limit -> claude (downgrade)`.** The out-of-family lane is account-limited until
2026-08-20, which is past this fleet's horizon, and `codex exec` **exits 0 on a usage limit** — so a
gate keyed on `$?` would have recorded a pass for a review that never ran. It was neither probed nor
keyed on. A fresh `claude -p` opus-5 reviewer ran instead, briefed adversarially: told to refute, and
told that finding nothing is a failed review rather than a pass. This is a logged in-family
downgrade, not a skipped gate, and the weakness travels with the evidence.

**Verdict: AMEND.** 18 findings — 3 HIGH, 10 MEDIUM, 5 LOW. **15 fixed, 2 rejected with a citation,
1 registered as a child.** The critic also checked and explicitly cleared the three fixes from the
earlier pass at the mechanism rather than at the comment, and confirmed the storage layer itself is
sound — every defect it found was at a call site that discarded the errors the layer raises.

### The three that changed what a user sees

| # | Finding | Disposition |
|---|---|---|
| 1 | **The Queue's Undo did not undo.** `clearUndo()` was `undo = nil`, so a button labelled "Undo" in the accent colour on a 44pt target dismissed the message saying the row had been removed and left it removed. | **Fixed.** `QueueModel` takes the writer and `undoLast()` re-enqueues. This is the defect M6 recorded — *"an Undo that undid neither half of what it named"* — repeating one item later. |
| 2 | **A refused removal rendered as a success.** `try? await queue.remove(...)` then `undo = item` unconditionally. `QueueSurfaceState.writeRefused`, its copy and its render arm all existed and **nothing ever set the flag**, so all three were unreachable. | **Fixed.** `do`/`catch`, `lastWriteFailed` threaded into `resolve`. |
| 3 | **Triage's queue read degraded to "nothing is queued".** `try? await queue.all()` meant an unreadable queue silently returned every already-queued entry to Undecided and offered it again — while the Queue tab one tap away reported the same file correctly. | **Fixed.** Taken as a `Result` like the dismissal read, with its own `.queueUnreadable` state and copy. A9's argument is that the two persisted sets fail alike; they now do. |

### Six gates that could not fail

The critic's sharpest category, and all six were **mine**, written in this pass:

| # | The gate | Why it could not fail | Fix |
|---|---|---|---|
| 7 | `vocabularyIsClosed` | `allCases.contains(clause)` is true for every value of a `CaseIterable` enum | asserts the vocabulary is seven and every clause renders non-empty and token-free |
| 8 | `countsComeOffTheSets` loop | `count(in:)` is *defined* as `entries(in:).count` | asserts the three buckets partition the results |
| 9 | `rowAndPlateAgree` | both sides are the same array through the same filter, so counts are equal by construction — including when the mapping is wrong, the one thing it existed to catch | compares correspondence against an explicit key→clause table |
| 10 | A30's dispatch guard | `#require(components.last)` is never nil, so "the guard went blind" could never print; on a rename it would pass with the whole file as the body | asserts `parts.count > 1` |
| 11 | `unsuppliedTokenStaysVisible` | `resolved([:])` is the identity function — the dictionary is never entered | substitutes a partial dictionary, which is what the surfaces construct |
| 14 | `queueBatchThenUndo` | the `|| ids.count == 2` disjunct passed for `.dismissed`, for any two ids, for two different servers | asserts the case and the id set |

### Also fixed

- **5** — `undoLast` and `restore` swallowed refusals with `try?`, and `undoLast` *cleared* the
  failure banner: a wholly refused undo returned a clean list with nothing said, reporting success
  for the user's last act precisely when it failed. Both count refusals now.
- **12** — the acceptance script's Guard 2 printed a note and continued where Guard 1 fails on the
  same condition, so a Mac-side rename would have left every run printing PASS with the question
  unasked. Fails closed now.
- **13** — `.partial` fell through the empty-bucket derivation, so a degraded search with everything
  already queued rendered segments, a warning and nothing beneath them.
- **15** — the A1 gesture scan missed `simultaneousGesture(`, `highPriorityGesture(` (capital G, so
  `gesture(` does not match), `draggable(` and `dropDestination(`.
- **16** — `noRecencyClaims` needed a space either side of `" new "`, missing "What's new" and a
  sentence-initial "New". Word boundaries now.
- **17** — a `DiscoverFailureReason` was threaded through two signatures and bound to `_`, which
  reads as a wiring bug. The parameter is deleted so the omission is visible; rendering the reason
  is a copy change and is registered.
- **18** — `.partialUnrecognised`'s body is the bare `{warning}` token, so an unrecognised warning
  with empty raw text rendered a headline over nothing.

### Rejected, with the citation

- **4 — "Send {count} to Mac" should read "Queue…".** The critic is right that the code was
  scrupulously renamed away from the verb (`canQueue`, never `canSend`) while the button was not.
  **But A11 specifies this string exactly** — *"`Send {n} to Mac`, verb-first, no ellipsis"* — and it
  went through the spec gate. A runner does not rewrite approved copy on its own reading, and the
  hint beneath the button already says *"Queues them for review on {mac}"* with the narrowing
  verbatim. Registered as **D-i3-g** for the owner, because the critic's underlying point — that the
  guard forbids nine paraphrases of a promise and not the verb itself — is sound.
- **6 — Queued and Dismissed are the intersection with the current results page.** True, and it
  follows directly from A7's `Undecided = results − queued − dismissed`. The sets are complete on
  disk; the buckets show the page. The critic's sharp half is that the Dismissed empty-state copy
  claims durability across searches (*"a decision made on a train is still readable at your desk"*)
  which the intersection does not deliver. That is a **spec-level** change — either render the
  buckets from the stores directly, or change approved copy — so it is registered as **D-i3-h**
  rather than taken unilaterally.

### Mutations for the critic fixes

Three more, same discipline — applied, measured, restored by re-applying the original edit, hash
verified identical, filter confirmed to match first.

| # | Mutation | Killed by | Mutated | Restored |
|---|---|---|---|---|
| M9 | `undoLast` becomes a banner-dismiss again | `undoRestoresTheItem` | exit 1 | exit 0, hash ✅ |
| M10 | refused removal reported as a success | `refusedRemovalIsSurfaced` | exit 1 | exit 0, hash ✅ |
| M11 | Triage's queue read degrades to empty | `unreadableQueueIsItsOwnState` | exit 1 | exit 0, hash ✅ |

**Eleven mutations in total, all red-green.**

### Gates, re-run on the amended tree

| Gate | Exit | Detail |
|---|---|---|
| `make lint` | **0** | 0 violations, 0 serious, **413 files** |
| `make test` | **0** | **1317 tests, 160 suites** |
| `make build-mac` | **0** | — |
| `make test-ios` | **0** | `TEST SUCCEEDED`, **28 tests**, one reused simulator |
| `make parity` | **0** | 358 vector cases (floor 358) |
| `scripts/acceptance/i3-phone-triage.sh` | **0** | 5 assertions, the three I3 surfaces only |

Lint went red once more on the amendment and was cleared **by splitting on two real seams, not by
raising a limit**: `TriageCopyStates.degradedState` grew past the 60-line function cap when
`.queueUnreadable` was added and split into `partialState` (results arrived, something is missing —
all four render rows) and `failureState` (nothing arrived, or a store failed — none of them do);
`TriageModelTests` passed the 400-line file cap and split into `TriageModelTests` (what the surface
offers) and `TriageFailureTests` (what it admits when storage says no), sharing one model builder so
the two cannot drift.

---

## Rebased onto the fresh `main`, and re-gated there

`main` moved while this item was in flight — **R2-W merged** (`bb056e7`), bringing the
`~/.claude.json` watcher and its cross-process adoption protocol. Rebased onto that tip: **6 commits,
0 conflicts, 0 behind**.

Re-gated on the rebased tree rather than taken on report, because a merge-only defect is this fleet's
most repeated lesson — M2 and M4 each compiled and passed alone and together did not compile at all.

| Gate | Exit | On the rebased tree |
|---|---|---|
| `make lint` | **0** | 0 violations, 0 serious, **433 files** (was 413) |
| `make test` | **0** | **1350 tests, 166 suites** (was 1317 / 160) |
| `make build-mac` | **0** | — |
| `make test-ios` | **0** | `TEST SUCCEEDED`, 28 tests, one reused simulator |
| `make parity` | **0** | 358 vector cases (floor 358) |
| `scripts/acceptance/i3-phone-triage.sh` | **0** | 5 assertions, the three I3 surfaces only |

**No merge-only defect.** R2-W is router-side and this item is iOS, so the surfaces do not overlap —
but that was *measured* rather than assumed, which is the only form the claim is worth making in.

One thing worth stating plainly for whoever merges: `git diff main --name-only` now lists
`ORCHESTRATOR.md`, and that is **main's** change, not this branch's. The files this item's own commits
touch contain neither `ORCHESTRATOR.md` nor `scripts/acceptance/parity-gate.sh`, verified against the
merge base rather than against a moving tip.
