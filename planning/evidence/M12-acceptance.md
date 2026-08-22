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

`swift test --filter CleanupProvenance`, 18 tests in 2 suites, **passed**, at `eaf4352`.

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
| A15c · C7 | the stamp is absolute, so it cannot decay while the dialog sits open | none of `just now`, `s ago`, `m ago`, `h ago`, `d ago`, `mo ago` follows `reading taken` | pass |
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
