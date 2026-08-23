# M12 — acceptance evidence

*Staleness and an as-of time inside a destructive dialog* · branch `ai/m12` · worktree
`.worktrees/M12`
Brief `planning/features-to-triage/M12-staleness-in-destructive-dialogs.md` ·
Spec `planning/specs/spec-M12.md` (C1–C13) · Plan `planning/plans/plan-M12.md` ·
Design `DESIGN.md` §5, §6, §9, §3.4 (authoritative)

Append to this file, never rewrite it. Read it **before** testing anything: if a row exists and
`git diff <that SHA>..HEAD` does not touch the files behind it, that row *is* the evidence, and the
right thing to do is skip the check and say so.

---

## What was verified, and what was deliberately not

**One surface changed**: the Cleanup board's two destructive dialogs. Nothing else in the app was
driven. The Checks board shares `M7BoardMetrics.swift` with Cleanup, and the one line this branch
changes there is a documentation string inside `CleanupBoardStates` that nothing renders.

**Not re-verified, and why.** Servers, Skills, Activity, Settings, Discover, Inbox and the shell are
untouched by this branch: `git diff main...ai/m12 --stat` names seven files, three of them under
`planning/`, and none under those surfaces. Their evidence is `planning/evidence/M3-`, `M4-`, `M2-`,
`M8-`, `M5-`, `M6-` and `M27-acceptance.md`, and `scripts/acceptance/mac-shell.sh` owns the shell's
own clauses. Re-running them against unchanged code has one possible outcome.

**Activity's reset dialog was not driven**, because it is not changed. It offers the same act and it
is recorded in the spec as found-not-fixed, with the router source that says why dating its figure
would have made the dialog read as better disclosed than it is.

---

## The unit evidence

`swift test --filter CleanupProvenance`, 18 tests in 2 suites, **passed**, re-measured at
`876dc20` — `Test run with 18 tests in 2 suites passed`.

**This row used to be stamped `eaf4352`, and those 18 tests are red at that SHA.** `eaf4352` is
the commit that swept up the live M3 mutation (the section below tells that story and reverts it
in `3ab6fa7`), so `CleanupProvenance.swift:109` reads `.quiet` there and `aStaleReadingIsMarked`
and `aStaleReadingKeepsItsStamp` both fail. The stamp was left behind by the accident rather than
being a claim the item did not know was wrong, and the SHA is load-bearing here: this file's own
opening rule tells a later reader to skip a check when `git diff <that SHA>..HEAD` does not touch
the files behind the row.

| # | Clause | Test | Result |
|---|---|---|---|
| C1 | a reading is stamped from the model's own clock when it is taken | `aReadingIsStampedWhenItIsTaken` | pass |
| C4 | a stale reading keeps the stamp it was taken with, and both dialogs mark it | `aStaleReadingKeepsItsStamp` | pass |
| C2 | a current reading is dated, and says what accrues after it is discarded too | `aCurrentReadingIsDatedQuietly` | pass |
| C4 | the stale marker uses the board's own words | `aStaleReadingIsMarked` | pass |
| C6 · C11 | an observed zero is dated; an unobserved count is not | `zeroIsAFigureAndNilIsNot` | pass |
| C6 | a fresh reading the summary did not answer for carries no reset provenance, and its removal dialog still does | `anUnansweredSummaryCarriesNoProvenance` | pass |
| C6 | a board with no reading at all dates nothing | `aBoardWithNoReadingDatesNothing` | pass |
| C13 | a stale reading with no count says so rather than implying one | `aStaleReadingWithNoCountSaysSo` | pass |
| C3 | the removal dialog dates its reading and marks it when stale | `theRemovalDialogDatesItsReading` | pass |
| C12 | the removal line claims provenance over nothing the dialog may not have drawn | `theRemovalLineClaimsNothingAbsent` + `theRemovalLinesPremiseHolds` | pass |
| C7 | the stamp does not decay while the dialog stays open | `theStampIsAbsoluteRatherThanElapsed` | pass |
| C7 | a reading from another day is not stamped like one from today | `anotherDayCarriesItsDate` | pass |
| C9 | a stale reading does not refuse the destructive act | `aStaleReadingDoesNotRefuse` | pass |
| C9 | a candidate that has left the list still refuses, with its reason | `aGoneCandidateStillRefuses` | pass |
| C10 | provenance never restates the count and never invents a number | `provenanceRestatesNoFigure` | pass |
| C8 | the shared consequence sentence is untouched by the provenance layer | `theSharedConsequenceIsUntouched` | pass |
| C5 | both sheets render the note and neither branches on staleness itself | `bothSheetsRenderTheNote` | pass |

## Red-green — every guard was seen to fail

`SWIFT_PRACTICES.md` §7: a test that has never failed is not known to work. Six mutations, each
applied to the tree, run, and reverted with `git checkout --`. The suite is
`--filter CleanupProvenance`, 18 tests, green at both ends.

| # | Mutation | Result | What went red |
|---|---|---|---|
| M2 | the figure branch reads `calls > 0` rather than `calls != nil` | **RED**, 2 issues | `zeroIsAFigureAndNilIsNot` — an observed zero left undated, which is M7's finding 1 rebuilt one layer up |
| M3 | the stale treatment returns `.quiet` rather than `.marked` | **RED**, 2 issues | `aStaleReadingIsMarked`, `aStaleReadingKeepsItsStamp` |
| M4 | `load()` restamps `observedAt` on the `.stale` path | **RED**, 1 issue | `aStaleReadingKeepsItsStamp` — a stale reading dated to the poll that failed |
| M5 | `removalRefusalReason` returns the refusal when `isStale` | **RED**, 1 issue | `aStaleReadingDoesNotRefuse` |
| M6 | `asOfLabel` returns `shortAgo(...) + " ago"` — the relative form the plan review killed | **RED**, 3 issues | `theStampIsAbsoluteRatherThanElapsed`, `anotherDayCarriesItsDate`, and the sentence assertions that name `taken at` |
| M7 | the reset sheet drops its `ProvenanceNote` call | **RED**, 3 issues | `bothSheetsRenderTheNote` |

**One mutation escaped into a commit, and the pass is what caught it.** A `git add -A` issued
between M3's apply and its revert committed the mutation as `eaf4352`; the script's own
`git checkout --` then restored the file to the state it had just been told was HEAD, and the
baseline that follows the table came back **red with exactly M3's two issues** on a working tree
`git status` called clean. Reverted in `3ab6fa7`, and the baseline is green there: **18 tests in 2
suites passed**. Recorded rather than re-run and quietly re-reported — a mutation pass whose log
reads red-then-green either way is exactly the shape this discipline exists to catch.

## The rendered evidence

`scripts/acceptance/m7-evals-cleanup.sh`, section **A15c**, added by this branch. Before it, the
script walked the Cleanup board and never opened a sheet: every claim about either dialog was a
source read.

Run against the Debug product built at `cbe60bc`+`dbed29f` (`BUILD SUCCEEDED`, freshness stamped),
launched with `open -g`, every read an accessibility query by pid. **Green twice**, `24 passed,
0 failed`, exit 0, `final frontmost: Ghostty (started at: Ghostty)` on both.

| # | Clause | What was driven | Result |
|---|---|---|---|
| A15c | the reset dialog opens from the pane header, backgrounded | `axkit press` on `Reset history`, then the window dump speaks `Reset the recorded call history` | pass |
| A15c · C2 | it names when its figure was read | the dump speaks `reading taken at` | pass |
| A15c · C2 | the figure is disclosed as a floor | the dump speaks `recorded after that is discarded as well` | pass |
| A15c · C7 | the stamp is absolute, so it cannot decay while the dialog sits open | none of `just now`, `s ago`, `m ago`, `h ago`, `d ago`, `mo ago` follows `reading taken` | **VACUOUS — the row could not fail. Replaced in gap-fix 1, below** |
| A15c · C8 | the shared consequence is still on screen beside the provenance line | one of the three consequence sentences is spoken | pass |
| A15c | the removal dialog opens from a row, backgrounded | `axkit press` on `Remove…`, then the dump speaks `Keep its recorded calls` | pass |
| A15c · C3 | it names when its tool count and key names were read | the dump speaks `was read at` | pass |
| A15c | the named consequence is still on screen beside the provenance line | the dump speaks one of the two tool-list sentences | pass |
| — | the whole run never took the screen | `axkit front` at every step and at the end | pass |

**A15c did not exist before this branch.** The script walked the Cleanup board and never opened a
sheet, so every prior claim about either dialog was a source read.

### The one failure, and why it is recorded as unattributed

The **first** run of this section failed its last step:
`FAIL: the removal dialog brought MCP Router to the front — the run took the user's screen`, after
all eight A15c assertions had passed. Two things are true about it and neither is a verdict.

It **did not reproduce**: two consecutive runs since are exit 0 with the frontmost app never
becoming MCP Router, including the step-level check added afterwards.

And it **could not have been attributed even if it had.** `axkit front` prints
`NSWorkspace.frontmostApplication?.localizedName` — an app **name**, not a pid. Any MCP Router build
on this machine reads as `MCP Router`, and this fleet runs several worktrees at once; the script's
own header records the sibling hazard, where a `pgrep -f` matching any MCPRouter attached to another
runner's build. So a rival worktree's app coming forward fails this gate identically to this run's
app doing it, and the gate cannot tell the two apart. The first run coincided with a load average
above 130 and other Mac worktrees building.

What was changed in response: `open_sheet` now runs `check_invisible` itself, so a future failure
names the step that took the screen rather than leaving the whole open-assert-close sequence as one
suspect. **Making the check pid-aware is not done here** — it is `axkit`'s `front` verb and every
script that calls `check_invisible`, which is a shared harness surface well outside a copy item.
Recorded for whoever owns the harness.

## What is not proved, and why

**The stale marker has no rendered proof.** `CleanupBoardModel.LoadState.stale` is reached only when
a poll fails *after* one has succeeded, and the app's Cleanup board loads once from `.task` and again
after a write — so producing it in a running build needs a fixture that answers and then refuses.
`FixtureControlAPIClient` is a stateless `struct` with a scenario-per-response shape
(`FixtureControlAPIClient.swift:13`), and giving it a call counter is a change to the fixture layer
every board's acceptance script runs against, with a parity row of its own. That is a feature, not a
line of this item.

So the marked treatment is proved at the model layer (`aStaleReadingKeepsItsStamp`,
`aStaleReadingIsMarked`) and at the value layer (`CleanupPresentation.Provenance.marked`), and the
claim that it *renders* as a banner rather than a caption is **unproven by a rendered pass**. The
`cleanupSkills` scenario is the precedent for adding one — its doc comment says it exists precisely
so a state unit tests could only reach by building a reading directly could be photographed — and
the same argument applies here. Recorded as follow-on rather than claimed.

**The rendered pass covers the fresh treatment only**, which is the state a reader meets in every
run where the router is answering.

---

# Gap-fix 1 — 2026-08-23

Verified **Needs More Work** at `3367f72` (`planning/verification/M12-verdict.md` in `.worktrees/M12W`).
Five findings, all in the record layer: the product was not broken and no line of `app/Sources`
behaviour changed here. Every figure below came from a command run in this session on `ai/m12` after
`main` was merged at `9d4da76`; nothing is carried forward from the verdict or from the runner's log.

Base for this pass: merge commit `37fac85`, then `ed549b9` (the assertion) and `876dc20` (the doc
comment). `git diff --stat 87e16dc 9d4da76 -- app/ src/ scripts/ Makefile` is empty, so the merge
brought no code and the gates below are statements about the branch's code as well as the merged
tree's.

## Finding 1 — the A15c row that could not fail

The C7 row published *the as-of stamp is absolute, so it cannot decay while the dialog sits open*
and swept six relative shapes as `reading taken $shape`. It could match none of them: the sentence
hardcodes `at ` after `taken`, and `shortAgo` puts a digit where the pattern wanted the unit.

**Replaced, then armed by planting.** The row now extracts the text after `reading taken at ` and
requires a clock time, with a non-empty check above it so an empty extraction cannot read as
agreement.

| Tree | `asOfLabel` returns | The row reads | Gate |
|---|---|---|---|
| clean | `formatter.string(from: date)` | `'1:09 am'` | `25 passed, 0 failed`, exit 0 |
| planted | `shortAgo(date, from: now) + " ago"` | `'now ago'` | `FAIL: … states no clock time`, **exit 1** |
| reverted | `formatter.string(from: date)` | `'1:11 am'` | `25 passed, 0 failed`, exit 0 |

The plant was `CleanupProvenance.swift` line 65, anchor `return formatter.string(from: date)`. The
file is sha256 `44bc6250b28f73ab24daa32d3b3142c7ed784972713254f1c7a82c3019333628` before the plant
and again after the revert, and `git diff -- app/Sources/MCPRouterKit/Cleanup/CleanupProvenance.swift`
is empty — the mutation was reverted before anything was committed, which is the hazard `eaf4352`
recorded on this branch.

**The comparison, on the same text.** Both forms were run against the sentence the planted app
actually spoke, `This figure is from the reading taken at now ago.`:

```
the form that stood here   no shape matched -> the assertion PASSES with the regression live
the form now committed     stamp read: "now ago" -> FAILS
on the correct sentence    stamp read: "1:09 am" -> PASSES, so it is not a blanket refusal
```

**What this row still does not cover, said rather than implied.** The removal dialog's stamp keeps
its presence assertion (`was read at`) and gains no absoluteness assertion, because `fail` exits and
one plant can therefore arm one row; a second assertion added here would be one nobody had seen fail,
which is the defect being fixed. `asOfLabel` is the single source of both stamps and it is armed at
the unit layer by mutation M6.

## Finding 2 — a green unit run stamped to a tree where it is red

Restamped in *The unit evidence* above, with the contamination stated in the row rather than left to
the section below it. Re-measured rather than re-stamped from the verdict: `CleanupProvenance.swift`
line 109 reads `return .quiet(…)` at `eaf4352` and `return .marked(…)` at `3ab6fa7` and at `876dc20`,
and `aStaleReadingIsMarked` requires `case let .marked(text)` — so the 18 tests are red at the SHA
the row used to carry.

## Finding 3 — three citations landing on plausible wrong text

Swept with the regex
`` `([A-Za-z0-9_+./-]+\.(?:swift|ts|sh|py|md|yml|yaml|json))[:]([0-9]+)(?:\s*[-–—]\s*([0-9]+))?` ``
over the five M12 documents, resolving each basename through `git ls-files` and reading the cited
line. A second pass with a looser grep (`\.(swift|ts|sh|py|md|yml|json):[0-9]+|line [0-9]+`) is the
control on the first, and found only the two elided continuations `` `:317` `` and `` `:335` ``,
which the strict regex cannot see. Population: **22 citations**, of which six were wrong.

| Site | Was | Landed on | Now |
|---|---|---|---|
| `spec-M12.md` §what is wrong | `CleanupBoard.swift:79` | `case let .stale(_, error):` | `:95`, anchor `StaleReadingBanner(error: staleError)` |
| `spec-M12.md` §what is wrong | `CleanupBoard.swift:34` | `.task { await board.load() }` | `:35`, anchor `.sheet(item: $board.sheet)` |
| `spec-M12.md` §out of scope 2 | `CleanupSheets.swift:232` | `.buttonStyle(StandardButtonStyle())` | `:255`, anchor `CheckCopy.ownerChanged(` |
| `spec-M12.md` §out of scope 1 | `src/control.ts:495` | `records: deps.usage.recent({` | `:496`, anchor `limit: Number(url.searchParams.get('limit') ?? 200)` |
| brief ×2, progress ×2 | `ORCHESTRATOR.md:522`, `LEDGER.md:110` | a register heading; M32's row | the line numbers are gone — both files are appended to hourly |

**The `Was` column above is six pointers that do not resolve, kept on purpose.** A sweep over this
file will find them; they are the record of what was wrong, each one sitting beside the text it
actually lands on, and there is no way to describe a broken citation without writing it down. Nothing
outside that column cites those numbers.

`CleanupBoard.swift` is blob `2ce0d71` at `87e16dc` and at `0f5f118` alike, so `:79` and `:34` were
**wrong when written**, not drifted. `CheckCopy.ownerChanged` sat at `:241` at `87e16dc` and `7a2f1e0`
and moved to `:255` at `4952afb`, this branch's own commit — so `:232` was wrong when written and
then drifted further. `src/control.ts` reads `limit: Number(…?? 200)` at `:496` at `87e16dc` too.

Every repointed citation now carries **anchor, tree and line**, which is `G7`'s form: the anchor
survives a line shift but not a re-wrap, the line survives a re-wrap but not a shift, and the tree
makes either checkable. The M7-acceptance citations `:313`, `:317` and `:335` resolve exactly and
keep their numbers, with their anchors and tree added.

## Finding 4 — a state the product cannot be in

Both places corrected: `spec-M12.md`'s state-matrix row and the shipped doc comment on
`CleanupBoardModel+Provenance.resetFigureProvenance` (`876dc20`). `CleanupBoard.swift:179` disables
the only button that opens the sheet while `state.reading` is nil, and `state.reading` is nil in
exactly `.loading` and `.failed` (`CleanupBoardState.swift:21-26`).

`grep -rn "\.resetHistory" app/Sources app/Tests --include="*.swift"` returns **13** matches: four
assign the case — `CleanupBoard.swift:177` (the disabled button), `ActivityBoard.swift:102` (the other
board's sheet), and `ActivityResetEntryPointTests.swift:115` and `M7ExercisedRequestTests.swift:274`,
which set it from a test rather than from a view — four call `resetHistory()`, three are `switch`
arms, one is a doc comment and one is a string inside a test assertion. The `guard` itself is
unchanged and still exercised by `aBoardWithNoReadingDatesNothing`.

## Finding 5 — a route default of 200 written as 500

`src/control.ts:496` reads `limit: Number(url.searchParams.get('limit') ?? 200)` and `src/usage.ts:259`
slices `-(opts.limit ?? 200)`. The 500 is the board's: `ActivityModel.swift:162` passes
`limit: ActivityRecords.capacity`, and `ActivityRecords.swift:18` sets `capacity = 500`, matched to
`RING_SIZE` at `src/usage.ts:52`. The argument built on it is unchanged, because the ring holds 500
either way.

## The gates, re-run

| Gate | Command | Result |
|---|---|---|
| Suite | `make test` | exit 0 — `Test run with 1743 tests in 217 suites passed`, `executed 1743 tests` |
| Scoped suite | `swift test --filter CleanupProvenance` | `Test run with 18 tests in 2 suites passed` |
| Lint | `make lint` | exit 0 — **as one target**, which the verifier's worktree could not do |
| ├ swiftformat | inside `make lint` | `0/561 files require formatting, 298 files skipped` |
| ├ swiftlint | inside `make lint` | `Found 0 violations, 0 serious in 554 files` |
| ├ raw design values | inside `make lint` | `scanning 127 files` … `clean` |
| ├ wire codable | inside `make lint` | `clean over` four directories, `2 exemption(s) recorded` |
| ├ harness config writes | inside `make lint` | `340 file(s) examined, 8 name a harness config, 22 write a file, 8 in the seam — none writes one` |
| ├ its selftest | inside `make lint` | `27 case(s) held` — 24 `P`-numbered plants each at its declared exit, `P10` the declared blind spot among them, plus 3 unnumbered cases (a clean tree, and two that must exit 2) |
| ├ reader accounting | inside `make lint` | `1351 paths` enumerated, `22 Python files, 0 unparsed`, `unaccounted 0` |
| └ null-run gate | inside `make lint` | `armed 28 assertions, 28 changed verdict`, `held green 0`, `blocked 0`, `not armed 4 populations` |
| Mac build | `make build-mac` | `** BUILD SUCCEEDED **`, freshness stamped, `build_freshness_check Debug` exit 0 |
| Rendered | `scripts/acceptance/m7-evals-cleanup.sh` | `25 passed, 0 failed`, exit 0, **twice**; one run in three blocked |
| Reconciler | `python3 planning/ledger-reconcile.py` | exit 0 — `no findings across A, B, B-range, C, D, E, F, G, H, I, J, K, L` |

**`make lint` and `make build-mac` both run here as composed targets.** `node_modules` and
`dist/index.js` are present in this worktree, so the `tools` prerequisite that blocked the verifier
is satisfied. That closes the composition the verdict left explicitly unproven.

`app/Package.resolved` did not move across four builds — `git diff --stat -- app/Package.resolved` is
empty at each — so the float recorded under *A dependency bump this item refused to carry* did not
recur.

**The intermittent block reproduced once in three runs**, and it is the same shape the verdict
attributed: `BLOCKED: LaunchServices refused to open this bundle (open exited 1) … error -609`, at
the relaunch for the `partial` scenario, **after** the whole A15c section had passed in that run. Not
chased: the verdict already measured the cause of the frontmost-collision family with a pid-aware
readback, and the machine's load average was between 321 and 452 across this pass.

**Not run:** `make all` (the brief forbids it), `make parity`, `make test-ios`, `make test-ios-glass`
— no file under `app/MCPRouterIOS*`, no token and no `DESIGN.md` value moved in this pass, and the
only source change is a documentation comment.
