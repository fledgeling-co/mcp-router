# plan-M13 — the scroll-edge separator, A34

Spec: `planning/specs/spec-M13.md`. Branch `ai/m13`, worktree `.worktrees/M13`.

**Size: Small.** One file changes — `scripts/acceptance/mac-shell.sh`, A34's rendered half. No
application source is touched (clause C6), because the diagnosis found the application correct.

---

## P1 · Replace the oracle in A34's rendered half

The assertion keeps its shape — *nothing at rest, a line once scrolled, cleared on the way back* —
and changes what it means by "a line". Today it asks the sampled row to be **one colour**, which is
only a fair question while whatever sits behind the row is itself one flat colour across the whole
content width. Over a real board it is not, and that is the whole failure.

### The compositing test

A translucent white line over a background B renders `A = a·255 + (1 − a)·B`, so
`a = (A − B) / (255 − B)` can be solved at every x whose background is legible. A hairline drawn
across the row yields the **same** `a` everywhere, whatever each x is drawn over; content yields
scattered values, because content is not a uniform veil over the row beneath it.

`ScrollEdgeSeparator` is 1pt tall — two image rows at 2× — so B is read from the row immediately
below it, and only where three consecutive rows there agree, so the stand-in for "what is underneath
the line" is used only where the background is genuinely flat in y. Channels already near white
cannot resolve an alpha and are skipped.

This is a new `axkit veil` subcommand: additive, called by nothing else, printing the readable share
of the band, the median opacity, the share agreeing with it, and the pixel count. The opacity is
never asserted against a constant — the scrolled reading is compared to the at-rest reading — so the
appearance stays free to change, which the previous comment was right to insist on.

### The offset puts content under the edge, deliberately

The measurement walks **outward** — 0.6, 0.85, 0.95 — and takes the first offset at which the row
below the line is *not* a single flat colour, i.e. the board's own content has arrived under the top
edge. That is the moment the separator exists for. Walking inward instead, toward the empty region
above a centred board, would prove only the easy case and would stop testing the state that is on
screen today. If no offset qualifies, that is a **FAIL** — the clause cannot be evidenced — never a
skip.

### Liveness

At the chosen offset, `axkit banddiff` over a band well below the edge must show real change.
Without it, a scroll bar that accepts a value and moves nothing renders a top row identical to rest,
and the run reports "no separator appeared" — a confident wrong diagnosis of the same species as the
one this item exists to remove.

### No layout-dependent quiet exit

Every way the clause can go unproven — no qualifying offset, too little readable background, an
unevenly-lightened row — is a FAIL with the measured numbers in the message. Exit 2 stays reserved
for the harness conditions the script already reserved it for: permissions, the session, a capture
that produced no image. A gate that can be silenced by a layout change is not a gate.

### What stays exactly as it is

The destination stays **Servers** — verified against source, not assumed:
`ShellWindow.ContentZone.boardsThatScrollThemselves` is `[.activity]` alone, so Servers is still
drawn inside the shell's `outerScroll` and its geometry is still what drives `ScrollEdgeState`. The
band's x-inset (8pt in from the left, 24pt off the right so the scroll bar is outside it) stays. The
return-to-zero leg stays — A34 is two claims and the second one needs it.

## P2 · Correct the stale comment (C5)

The block above the assertion tells its reader that A34 is driven on Servers because Servers is "the
first destination still using the shell's scroll view", and that "when the last board lands this
needs the assertion moved onto a board's own list instead". The second half is false — the last
board landed at M6 and seven of eight destinations still use the shell's scroll view — and it is
what sent this item's brief toward the wrong diagnosis. Replace it with what the source does, and
record the real fragility (the oracle's dependence on a flat background) in its place.

## P3 · Prove it red, both ways

A gate that has only ever been seen green is not evidence. Two mutations to the application source,
each built and run, each reverted **by re-applying the original text** (never `git checkout --`,
which destroyed a fix earlier in this fleet):

| # | Mutation | Expected |
|---|---|---|
| D1 | `ScrollEdgeSeparator(isVisible: false)` in `ShellWindow.ContentZone` — the separator can never show | FAIL, "the top row rendered … both at rest and scrolled — no separator appeared" |
| D2 | `isSeparatorVisible = true` unconditionally in `ScrollEdgeState.observe` — the separator can never hide | FAIL, at rest and scrolled being the same colour |

D1 proves the assertion still catches an absent separator; D2 proves it still catches one that never
clears. Between them they cover both halves of A34's clause.

## P4 · Gates

`make lint` (exit code read directly, never through a pipeline — `swiftformat --lint` runs first and
short-circuits), `make build-mac`, `swift test`, and `scripts/acceptance/mac-shell.sh` end to end.
The acceptance run covers A34 and the assertions that share its launch; no other item's script is
run, and no surface this item did not change is re-tested.

## P5 · Review

The spec and this plan go through `grok --model grok-4.6` (the owner's replacement for the
account-limited codex lane), and a completeness critic reads the finished assertion against the
clause. The lane and any downgrade are recorded in `planning/evidence/M13-acceptance.md`.

## Risks

- **The chosen offset is board-dependent.** Mitigated by the search plus the BLOCKED path: the run
  can fail to measure, but it cannot quietly measure the wrong thing.
- **Top-aligning the boards later** (the found-not-fixed defect in the spec) removes the flat gap
  this measurement uses. The result is a loud BLOCKED naming the missing flat region, not a false
  green and not a false red.
- **A capture taken mid-animation.** `ScrollEdgeSeparator` animates nothing of its own and §7
  restricts motion to transform and opacity; the existing settle sleeps are kept.
