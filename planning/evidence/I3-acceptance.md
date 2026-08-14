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
