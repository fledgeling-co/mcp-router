# M26 — the Checks board and the design's eval board are two different surfaces

**Category:** mac · **Found:** 2026-08-20, by the campaign's vocabulary differential
**Defect:** DEF-031 · **Surface:** SURF-006 · **Related:** M7 (Evals and Cleanup), DEF-011, DEF-012

## What was measured

The differential compares the accessible names of every `AXButton`, `AXCheckBox`,
`AXPopUpButton` and `AXTextField` on a running board against the same board in
`design/mocks/prototype.html`, with the shell and the fixture rows subtracted. On this board
it reported `Edit cases…` and `Run again` as in-design-not-build.

Neither is a missing button. Reading the two headers side by side, they describe different
boards:

| | Design (`prototype.html:885-891`) | Build (`EvalsBoard.swift:183`) |
|---|---|---|
| Subject | one skill — `pr-summariser · 8 cases` | every server and skill, one row each |
| Subtitle | `Ran 2 minutes ago against 0.4.1 in a scratch checkout` | `CheckCopy.evalsSubtitle` |
| Body | eight named cases, a verdict each, a pass bar and a duration | a reachability verdict per subject, with a filter and a search field |
| Actions | `Edit cases…`, `Run again` | `Re-check all…` |

The design's board runs an **eval suite** against one skill and shows what each case did. The
build's board **probes reachability** across everything the router fronts. They share a route
id — `prototype.html:600` declares `{id:'evals',t:'Checks'}` — and nothing else.

## Why the two buttons were not simply added

`Run again` re-runs the one suite on screen. `CheckCopy.runAllLabel` — `Re-check all…` —
already does that job for the board that is actually built, so drawing both would put two
names on one act. That is DEF-012, which this campaign has just spent a commit closing in two
other places.

`Edit cases…` opens an editor over a collection the app does not have. `EvalsBoardModel`
carries subjects and reachability readings; there is no eval case in it, no suite, no
`0.4.1`, no scratch checkout. A button drawn against that model would offer a reading of
something that does not exist — the same reason `Read first…` is recorded as a stated gap in
DEF-011 rather than drawn unconditionally.

## The decision, taken

**2026-08-20, by the owner: keep the reachability board and amend the design.** The first
of the three options below. `design/mocks/prototype.html`'s `PANES.evals` now draws the
board that ships — title `Checks`, the built subtitle, `Re-check all…`, the four filters
`All | Not met | Not observed | Unstamped`, and the columns `subject · kind · checks ·
checked against` over one row per server and skill. Rendered and read back through the
sanctioned engine: 14 rows, 4 columns, 5 controls, all matching. **DEF-031 closed.**

Three things worth recording about how it was done.

`DESIGN.md` needed no change. It already says there is no eval runner in this product —
"no eval endpoint on the control API, no eval field on any wire type" — so the mock was
the only design of record still carrying the eval board, and amending it made the two
agree rather than requiring a third edit.

**The explanatory comment nearly reintroduced the finding.** The first version of the
comment above `PANES.evals` named the two removed buttons, to say why they had gone. The
vocabulary differential greps this file for control names; prose explaining a removed
control puts it straight back into the in-design set. This is the inverse of the trap
recorded in `ShellDetailWidthTests` — there a predicate was satisfied by the prose
explaining it, here a predicate would have been *tripped* by it. The comment now points
at this file instead, and the labels appear nowhere in the mock.

**The board is drawn with no search field, and that is deliberate.** The built board has
one; so do Discover and Skills. No Mac board in this mock draws one. Adding a search field
to Checks alone would trade one differential finding for another and make Checks the odd
board out, so it matches the mock's own idiom. The missing search field is a pre-existing,
board-wide divergence that predates this item and is not M26's to fix.

The eval board is not withdrawn as an idea. It is a feature programme rather than a pane,
and the third option below is still the better long-term shape.

## The decision as it was framed

Which board does the product want? The two answers cost very different amounts.

**Keep the reachability board and amend the design.** Cheapest. The built board is coherent,
ships all nine `DESIGN.md` §5 states, and answers a question the router can actually answer
from its own observations. The cost is that `prototype.html` stops being the design of record
for this one pane, and the differential will keep reporting these two names until the mock is
amended.

**Build the eval board the design specifies.** Much larger. It needs an eval-case model, a
per-skill suite, a runner that executes cases against a skill version in a scratch checkout,
per-case verdicts, a duration, and an editor for the cases themselves. It also needs an answer
to what a "case" is for a skill, which nothing in this repository currently defines. That is a
feature programme, not a board.

**Or both, as two surfaces.** The reachability board keeps its route, and the eval board
becomes the detail view a subject opens into — which is closer to what the design's header
reads like, since it names one skill and a version.

Nothing here is guarded by an assertion, deliberately: there is nothing to assert until the
call is made, and a test pinning today's cross-subject board would make the divergence harder
to close rather than easier.
