# M12: staleness and an as-of time inside a destructive dialog

| | |
|---|---|
| Status | **In progress** — `ai/m12` |
| Item | M12 — M7's Phase D findings 4 and 8, both VALID, both deferred rather than fixed |
| Deps | M7 ✓ (the Cleanup board and its three sheets) · F4 ✓ (`LoadState.stale`) · M2 ✓ (Activity, for the scope decision only) |
| Brief | `planning/features-to-triage/M12-staleness-in-destructive-dialogs.md` — written by this item; M12 was allocated without one |
| Branch | `ai/m12` · worktree `.worktrees/M12` |
| Design authority | `DESIGN.md` §5 (Partial), §6 (words, and the last bullet), §9 (escalation), §3.4 (disabled) |
| Out-of-family gate | `agy --model gemini-3.7-flash-high` — **the only out-of-family lane that answered.** `codex -m gpt-5.6-sol` returned `You've hit your usage limit … try again at Aug 27th`; `grok -m grok-4.6` returned `402 Payment Required: Grok Build usage balance exhausted` with an empty output file. Both recorded as down, not skipped. `claude --model claude-fable-5 --effort high` answered as well and is recorded as **in-family**, which is a weaker gate and is not counted as the second family. |

---

## Feature description

Two dialogs in `app/Sources/MCPRouterUI/Boards/CleanupSheets.swift` state a consequence figure taken
from the last successful poll, in the present tense, with no marker when that reading is stale and
no as-of time. The figure is therefore a lower bound presented as a count, and — in
`CleanupBoardModel.LoadState.stale` — an old reading presented as a current one.

This item makes both dialogs disclose the provenance of the figures they state. It does not change
what either act does, does not change the shared consequence sentence, and adds no number the router
does not report.

## What is wrong, measured on this tree

`RemoveServerSheet` and `ResetHistorySheet` both render from `board.state.reading`, and
`LoadState.reading` returns the kept reading in `.stale` as well as in `.loaded`:

```swift
public var reading: Reading? {
    switch self {
    case let .loaded(reading), let .stale(reading, _): reading
    case .loading, .failed: nil
    }
}
```

`CleanupBoard.boardColumn` draws `StaleReadingBanner` above the table for `.stale`
(`CleanupBoard.swift:79`). The sheet is presented by `.sheet(item:)` on the same view
(`CleanupBoard.swift:34`) and inherits none of it — a modal covers the banner it would otherwise sit
under.

**`Reading` carries no timestamp.** Its four fields are `servers`, `skills`, `since` and
`recordedCalls`. So the as-of time finding 8 asks for cannot be stated today at all; nothing stamps
the reading. That single missing field is the whole of the model change.

## The design decision this item exists to settle

M7's critic deferred findings 4 and 8 with: *"Marking staleness inside a modal is a design decision,
not a defect this item may settle alone."* `DESIGN.md` §5 governs a **surface** and a modal is not
one of the nine states, so there was nothing to implement against. Settled here as follows.

### D1 · A provenance line below the consequence, not a rewritten consequence

The consequence sentence is untouched. `CleanupPresentation.resetConsequence(calls:window:)` is
called by two boards precisely so they cannot tell the user different things about the same
irreversible act, and it carries five red-green assertions from M7's finding 1. Provenance is a
different claim from consequence — *when this was observed* against *what this destroys* — and
folding them produces one sentence with four combinatorial branches where two independent functions
do.

### D2 · Stale is marked with the board's own marker, fresh is a quiet caption

`Banner(icon: .warn, tint: .attention)` when the reading is stale — the same component, glyph and
tint `StaleReadingBanner` uses for the same fact, so §6's one-name-per-state holds across the board
and the dialog opened over it. A `--t3` caption at `.caption` when it is not, which is §6's "helper
text is one quiet secondary sentence under its control".

The two differ **structurally** and not only by colour, so the distinction survives
`accessibilityDifferentiateWithoutColor`. The tint reaches only the glyph: `Banner` renders its
content at `--t2` and applies `tint` to the `IconView` alone, so `--attn` is used here in its
declared `pairedWithAWord` role and never as a text colour.

### D3 · An as-of time is exact here, and the Servers board's argument against one does not carry

`StaleReadingBanner`'s doc comment says: *"The copy deliberately does not call the rows a snapshot.
`ServerStateTracker` records that stale servers are the last poll **as corrected by any call records
seen since**, so 'as of {time}' would overstate what is on screen."*

That reasoning is about the tracker, and the Cleanup board has none. `CleanupBoardModel.Reading` is a
plain snapshot of one `load()` with no correction applied, so an as-of time on this board states
exactly what it claims. The two surfaces differ in fact, not in policy.

`observedAt` is stamped at the moment `servers()` returns, before `skills()` and `usageSummary()` are
attempted. The two later responses can only be newer, so the age this reports is **never younger than
the truth** — the conservative direction for a staleness disclosure.

### D4 · A stale reading discloses; it does not dim the button

`.stale` means the last *read* threw. It does not mean the write will. Dimming the destructive
control would refuse an act the router may well accept, and would be worst in the case a reader most
wants it — a wedged router whose history someone is trying to reset. The typed write error already
lands in place beside the control (§5 Error), and `RemoveServerSheet`'s existing `disabled(candidate
== nil)` stays: that condition is different in kind, because there the disclosure is *absent* rather
than *old*, and §9 does not allow an irreversible act to be offered with no consequence stated.

What the rejected option would have been better at: guaranteeing no reader ever fires a destructive
POST against a router whose state was last read successfully some time ago.

### D5 · Scope is Cleanup's two dialogs. Activity is recorded, not fixed — see below

## Clauses

| # | Clause | Evidence |
|---|---|---|
| C1 | `CleanupBoardModel.Reading` carries `observedAt`, stamped from an injected clock at the instant the reading's first response lands | `CleanupBoardModel.swift`; `CleanupProvenanceTests.observedAtIsStampedFromTheInjectedClock` |
| C2 | The reset dialog states when its figure was observed, and says that whatever the router has recorded since is discarded as well and is not in it | `CleanupPresentation.resetFigureProvenance`; `CleanupPresentationTests` |
| C3 | The removal dialog states when its tool count and key names were observed | `CleanupPresentation.removeFigureProvenance`; `CleanupPresentationTests` |
| C4 | In `.stale`, both dialogs carry the board's own stale wording — the last reading the router gave, and nothing about it is current | `CleanupPresentation`, both provenance functions; `CleanupProvenanceTests` |
| C5 | The stale line renders as `Banner(icon: .warn, tint: .attention)` and the fresh line as a `--t3` `.caption`, so the two differ structurally and not only by hue | `FigureProvenance` in `CleanupSheets.swift`; `CleanupProvenanceTests.staleAndFreshDifferInStructure` |
| C6 | Where there is no figure to date — the router did not answer `usageSummary()`, or no reading has landed — the fresh case says nothing rather than dating an absent number | both provenance functions return `String?`; `CleanupPresentationTests` |
| C7 | An age under five seconds reads "just now" and never "now ago" | `CleanupPresentation.agoPhrase`; boundary test at 4s / 5s |
| C8 | `resetConsequence` is byte-identical to `main`, and both boards still call it | `git diff main -- CleanupPresentation.swift` shows no change inside that function; its five existing assertions still pass |
| C9 | The destructive buttons keep the enablement they had: `Remove` disabled only when the candidate has left the list, `Reset history` never disabled | `CleanupSheets.swift`; `CleanupProvenanceTests.aStaleReadingDoesNotDimTheDestructiveButton` |
| C10 | No new number reaches the UI. Every figure in both dialogs is one the router reported, and `observedAt` is a device clock reading about the app's own act of reading, not a claim about the router | `SWIFT_PRACTICES.md` §5 self-review; no new field is read from the wire |

## The dialogs' state matrix

`DESIGN.md` §5 asks each spec for its own matrix with real copy for the unhappy paths. §5 governs
surfaces and a modal is not one of the nine, so this is the matrix for the **figure inside** the two
dialogs — which is what the item changes.

| Condition | Reset dialog | Removal dialog |
|---|---|---|
| Loaded, count observed | consequence + `--t3` caption: *"This figure is from the reading taken 3m ago. Whatever the router has recorded since is discarded as well, and is not in it."* | consequence + caption: *"The tool count and the key names above are from the reading taken 3m ago."* |
| Loaded, count **not** observed (`usageSummary()` threw) | consequence drops the number ("the router has not said how many"); **no provenance line** — there is no figure to date | n/a: the tool count and key names come from `servers()`, which must have succeeded for a reading to exist |
| Loaded, observed **zero** | the zero sentence ("nothing to discard") + the same caption, which is what makes the zero honest: it may already be false | n/a |
| **Stale** | `Banner(.warn, .attention)`: *"This is the last reading the router gave, taken 3m ago, and nothing about it is current. Whatever the router has recorded since is discarded as well, and is not in the figure above."* | `Banner(.warn, .attention)`: *"… and nothing about it is current — what removing this server takes with it may have changed since."* |
| Stale, count not observed | `Banner` with the first sentence only | n/a |
| No reading at all (`.loading` / `.failed`) | the header's `Reset history…` is reachable in `.loading`; the consequence drops the number and there is no provenance line | the sheet is opened from a row, so there is no reading-free path to it |
| Candidate gone from the list | n/a | `CleanupPresentation.consequenceUnavailable`, `Remove` dimmed — unchanged by this item |
| Under five seconds old | *"…the reading taken just now."* | *"…the reading taken just now."* |

## Out of scope, and found-not-fixed

**1 · `ActivityResetHistorySheet` has the same shape and a second, larger defect underneath it. Not
fixed here; it needs its own item.**

Activity offers the same act and calls the same shared consequence string, so the obvious reading is
that it belongs in this item. Measuring the figure it passes says otherwise:

```swift
CleanupPresentation.resetConsequence(calls: model.records?.count, window: nil)
```

`records` is `ActivityRecords`, whose `capacity` is **500** — matched deliberately to the router's
`RING_SIZE` (`src/usage.ts:52`), and `GET /usage` returns `recent({ limit: 500 })`, which slices the
ring (`src/control.ts:495`, `src/usage.ts:259`). But `usage.reset()` clears the ring **and** the
unbounded per-server tallies **and** the two on-disk log files (`src/usage.ts:281–293`), while
`summary()` counts those tallies with no cap (`src/usage.ts:262`).

So on a router that has recorded 812 calls since `since`, Cleanup's dialog says **812** and
Activity's says **500**, for the same button, against the same endpoint. Activity's figure is a lower
bound for a *structural* reason, and it understates by an unbounded margin.

Adding an as-of line to that number would be the worse outcome: the dialog would read as more
thoroughly disclosed than it is, while the larger understatement stayed unsaid. The fix Activity
needs is a different one — either state what the figure actually is (the window this board holds) or
fetch the summary tally, which means a new request on a board whose design deliberately makes
exactly two. That is a feature with its own state matrix, not a line of copy.

Recorded for the orchestrator to route. **The out-of-family lane recommended extending scope to
Activity and this item does not take that recommendation**; the disposition table below says why, and
the measurement above is the whole of the reason.

**2 · `SkillProvenanceSheet` renders `CheckCopy.ownerChanged` as body text in `ColorToken.attention`**
(`CleanupSheets.swift:232`). `ColorToken+Role.swift:95` declares `--attn` as `pairedWithAWord`, whose
claim is *"never the only carrier of its meaning"* and whose recorded ratio on the light ground is
**2.31:1** — a fine dot and an unreadable label. `--attn-ink` is the `text`-role twin that exists for
this. Found while choosing the tint for C5; it is M7's line, it is not a destructive dialog, and
changing it is a contrast fix for whoever owns the per-surface sweep `DESIGN.md` §10 asks for.

**3 · Re-polling when a dialog opens.** A dialog that refreshes its own figure would make the as-of
time almost always "just now", but it introduces a loading state, a failure state and a race with the
POST inside a modal. Deliberately not done: disclosure is this item, freshness is a feature.

## The out-of-family review, and what it changed

**Two of the three lanes were down.** `codex -m gpt-5.6-sol -c model_reasoning_effort=high` exited on
`You've hit your usage limit … try again at Aug 27th, 2026`; `grok -m grok-4.6 --effort xhigh`
returned `402 Payment Required: Grok Build usage balance exhausted` with an empty output file. Both
were attempted with the prompt below and neither produced a verdict. Recorded rather than quietly
downgraded — a lane that did not run and a lane that agreed look identical in a report that does not
say which.

`agy --model gemini-3.7-flash-high` answered, briefed with §5/§6/§9/§3.4, the two dialogs' current
copy, `LoadState`, the `StaleReadingBanner` precedent and its doc comment, and the three questions
with the candidate options presented in **both** orders across the two lanes.

| Finding | Disposition |
|---|---|
| **Accepted.** Q1 → the separate provenance line. *"Consequence (what will be destroyed) and provenance (when the observation was taken and its reliability) represent distinct cognitive layers. Combining them into one sentence creates awkward, combinatorial phrasing, breaks §6's mandate that helper text remain a quiet secondary element under its control, and risks invalidating existing assertion suites."* | Taken as D1. What the rejected option would have been better at, in its words: *"keeping vertical modal height strictly minimal and avoiding visual fragmentation by delivering the count and its temporal qualification in a single uninterrupted phrase."* |
| **Accepted.** Q2 → disclose, do not dim. *"A `.stale` state indicates that the background read poll failed, not that the router daemon is dead or incapable of handling mutations. Disabling the destructive action conflates a failed observation with an invalid operation, creating an artificial deadlock when a user specifically opens cleanup tools to flush or reset a wedged router."* | Taken as D4, including its statement of what dimming would have bought. |
| **Rejected — refuted by measurement.** Q3 → *"Extend to Activity's reset dialog in the same item … patching only Cleanup forces an awkward divergence in the shared presentation contract."* | The premise is that the two dialogs state the same kind of figure. They do not: Cleanup passes the unbounded summary tally and Activity passes the size of a 500-capped ring window, for the same endpoint, which discards both. Extending scope would date a figure that is wrong for a reason this item is not fixing. Recorded as found-not-fixed 1 above, with the router source that settles it. The lane was not given `src/usage.ts`, which is why it could not have reached this. |

### The in-family second read, recorded as what it is

`claude --model claude-fable-5 --effort high`, given the same brief with the options in the opposite
order and told explicitly that a better third approach was wanted more than a vote. It reached the
same three answers, and one of them is worth recording because it was reached **without** the router
source that settles it:

> *"Activity doesn't have M12's defect, it has a different one. Its figure can't be stale — the SSE
> feed makes it the freshest number in the app — but `model.records?.count` is the size of a live
> capped window presented as the discard total, when the reset discards all recorded history,
> visible window or not. That's not a provenance problem, it's a wrong-denominator problem."*

It also named what the scope this item did **not** take would have bought, which is the part worth
keeping in front of whoever routes the follow-up: *"for one release, the two dialogs for the same
irreversible act now disclose with different honesty, Cleanup dated and marked, Activity bare."*

Two Claudes agreeing is not two families agreeing. This is logged as corroboration of a decision the
measurement already carried, not as the second gate — the two lanes that would have been the second
gate are down until 27 August.
