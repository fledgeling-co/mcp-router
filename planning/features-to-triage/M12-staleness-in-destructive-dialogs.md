# M12 — Staleness and an as-of time inside a destructive dialog

**Source:** M7's Phase D critic, findings 4 and 8, both graded VALID and deferred rather than fixed
(`planning/evidence/M7-acceptance.md:313`, `:317`, `:335`). Written on 2026-08-22 because the item
was allocated with no brief: `ORCHESTRATOR.md:522` and `planning/features-to-triage/LEDGER.md:110`
are its whole record.

## What is wrong

Two dialogs in `app/Sources/MCPRouterUI/Boards/CleanupSheets.swift` state a consequence figure taken
from the last successful poll, in the present tense, with no marker when that reading is stale and
no as-of time.

**`ResetHistorySheet`** draws `CleanupPresentation.resetConsequence(calls:window:)` from
`board.state.reading?.recordedCalls` — the figure `usageSummary()` gave when `load()` last
succeeded. Two things are unsaid:

- **Finding 4 — no staleness marker.** `CleanupBoardModel.LoadState.stale(Reading, error)` keeps the
  previous reading when a poll throws, and `state.reading` returns it. The board draws
  `StaleReadingBanner` above the table in that state; the dialog draws the same reading with
  nothing. A reader who opens the sheet from a stale board is told a count in the present tense.
- **Finding 8 — no as-of time.** Calls recorded between the load and the `POST /usage/reset` are
  discarded too and are not in the figure. So the number is a lower bound presented as a count.

**`RemoveServerSheet`** has the same shape and is what `ORCHESTRATOR.md:522` names when it says the
item is still open, measured 2026-08-21: it draws `Remove <name>?` with the candidate's tool count
and its env and header **key names**, all from the same reading, with no marker and no as-of.

## Why it was deferred rather than fixed under M7

Verbatim from the critic's disposition: *"Marking staleness inside a modal is a design decision, not
a defect this item may settle alone."* Nothing in `DESIGN.md` or in either mock says what a stale
reading looks like inside a sheet. §5 governs a **surface**; a modal is not one of the nine states.
So this item's first job is to settle that treatment, not to write code.

## What the router actually observes

Every figure needed here already exists. Nothing new is asked of the router, and no new number is
invented — `DESIGN.md` §6's last bullet and `SWIFT_PRACTICES.md` §5 both forbid that.

| Figure | Where it comes from |
|---|---|
| the call count | `UsageSummary.servers.reduce(0) { $0 + $1.calls }`, already held as `Reading.recordedCalls: Int?` |
| the window label | `UsageSummary.since`, already parsed by `CleanupPresentation.window(since:now:)` |
| the tool count and key names | `MCPServer.tools`, `.envKeys`, `.headerKeys`, already on `Candidate` |
| **when the reading was taken** | **not recorded anywhere today** — this is the one new field |

`Reading` carries no timestamp. That is the gap: an as-of time cannot be stated because nothing
stamps the reading.

## What a fix has to hold

1. A destructive dialog on this board discloses **when** the figure it states was observed.
2. When the reading behind that figure is `.stale`, the dialog says so, in the wording the board
   already uses for the same fact (§6: one name per state, from one source).
3. The reset sentence stops reading as a live count: what accrues between the load and the POST is
   discarded too and is not in the figure.
4. Nothing about the shared `resetConsequence` string changes. Two boards call it so that they
   cannot disagree about the same irreversible act, and it carries five red-green assertions from
   M7's finding 1.
5. No number appears that the router did not report, and an as-of time is not a licence to imply
   the reading is current.

## Open questions this brief does not settle

- **The treatment.** A note below the consequence versus folding it into the sentence; and whether
  the stale case reuses `Banner(icon: .warn, tint: .attention)` — the board's own marker — or a
  quieter caption.
- **Whether a stale reading should dim the destructive button** (§3.4) or only disclose. The
  `Remove` button is already dimmed when the candidate has left the list entirely, which is a
  different condition: there the disclosure is *absent*, here it is *old*.
- **Scope.** `ActivityResetHistorySheet` offers the same act and calls the same shared string, but
  its count is a live SSE-topped window rather than a snapshot and its model has no `.stale` case.
  Either it is in this item or it is recorded as found-not-fixed with the reason.

## Out of scope

- Changing what `POST /usage/reset` does, or asking the router for a fresher figure when a dialog
  opens. A dialog that re-polls is a different item with its own failure states.
- `SkillProvenanceSheet`. It is the one sheet on this board that asks for nothing and ends in the
  reader knowing something, so it has no destructive act to disclose against.
