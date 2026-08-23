# M22 — acceptance evidence

`planning/practices/UI_VERIFICATION.md` rule 2: append, never rewrite. Record the actual command
or accessibility path, not "verified".

**Both boards are new in this item**, so nothing here can be skipped against an earlier row —
there is no earlier row. The other seven boards are evidenced under `M2-`, `M3-`, `M4-`, `M5-`,
`M7-` and `M8-acceptance.md`; their files are untouched by this branch's diff and are cited rather
than re-driven, per rule 3.

**One launch, one pass, quit.** `scripts/acceptance/m22-boards.sh` covers both panes in a single
backgrounded launch and never brings the app to the front — `open -g`, every read an accessibility
query by pid, and `axkit front` asserted after each pane's block. Rule 1 is a hard requirement
here rather than a courtesy: a gate that steals the screen fails itself.

---

## What each screen's evidence rests on

| Screen | How verified | Commit | Result |
|---|---|---|---|
| `mcp-router harnesses --json` (CLI, not a screen) | `scripts/acceptance/r7-harness-reconciliation.sh` — 2026-08-22, exit 0. Included because M22 **refactored the encoder behind it**: `HarnessesVerb.json` now delegates to `HarnessReportJSON`, which `GET /harnesses` shares, so the CLI's output was at risk of moving under a route it does not use. Every assertion in R7's own lane still passes, including the two-spellings-disagree and stale-endpoint arms | `1f5c3a4` | pass |
| Harnesses (board) | `scripts/acceptance/m22-boards.sh` — 2026-08-22, **green twice**, exit 0 both times. One backgrounded launch under `MCPROUTER_SCENARIO=populated`, selected over the accessibility API (`axkit select <pid> Harnesses`), read with `axkit dump <pid> window`. Eight assertions: the board's own header; the window title (§3.7); all four readings each in its own words; the shim row naming `mcp-remote` **and** calling it one extra process per session; the reading stamped with when it was taken; the scope it does not cover; the finding phrased as a count; and **4 Reconcile controls drawn, disabled, each carrying its reason** (§3.4). `axkit front` asserted after the block — read `Ghostty` / `Google Chrome`, never MCP Router | `15185eb` | pass |
| Insights (board) | Same launch, same pass — `axkit select <pid> Insights`. Eight assertions: the window title; **`Gemini CLI, 0` present in the accessibility tree as one announcement**, which is the brief's own acceptance criterion — the zero row's label and its zero together; an unattributable row drawing neither a count nor a zero and saying why (`calls arrive as node`); `measured, not modelled` on the memory figure; the failure rate carrying both its terms; the duty-cycle caption stating the mechanism and its window; and **no saving, no unrouted comparison, no `99.8`/`99.7`** anywhere. That last search is proven non-vacuous before it is trusted: it BLOCKS unless `Resident, all children` is on screen, so a clean result is a measurement rather than a grep over a tree with no numbers in it | `15185eb` | pass |

## What the run found, and what it says about the other two instruments

**One product defect, and the lane is the only thing that could have found it.** The freshness line
rendered **`Read now ago`** — `shortAgo` returns the *word* `now` under five seconds and a duration
above it, and the composition assumed a duration. Fixed at `15185eb`, guarded at both sides of that
five-second boundary, and the guard armed by reintroducing the defect (three expectations red).

It survived three green instruments. `swift test` asserted no exact string. M23's fidelity gate
compares the build's copy against the mock — and **the mock has no freshness line at all**, because
it is one of M22's own additions, so there was nothing on the other side to disagree with. Only
reading what the shipped window speaks could see it.

**Two defects in this lane itself**, both recorded in the script at the line that was wrong, because
a gate that reads the wrong thing reports the product as broken:

- Its first assertion grepped the window for `isn't built yet`, copied from the sibling scripts where
  that was the scaffold's sentence. The scaffold is deleted and that sentence is now
  `CommandAvailability.surfaceAbsent`'s live help tag — which this board's own disabled controls
  carry, correctly, because §6 asks for one name per state. Replaced by a positive assertion.
- Its disabled-control count read fields 5 and 7. SwiftUI puts a `Button`'s label in
  **AXDescription (6)** and `enabled` is **field 8**, so it reported "no Reconcile control is drawn
  disabled" about four that were.

---

## The three instruments, and what each cannot see

Stated because the three are easy to read as one, and a reader who takes them as one will
over-trust the set.

| Instrument | What it establishes | What it cannot see |
|---|---|---|
| `swift test` (1767 in 221 suites) | the models, the wire types, the copy and the four readings, as values | nothing rendered. A board that constructs correctly and draws nothing passes every one |
| `mock-fidelity-gate.sh` (M23) | the drawn tree against the design of record — tokens, structure, geometry, type metrics, copy — over four states per surface | it renders into a hosted view in a window that is never shown, with a fixture client. It is not the shipped app, and it drives nothing |
| `m22-boards.sh` | that the honesty rules survive into the **shipped bundle**: the four readings, the shim's named cost, the stamped reading, the zero row's label and zero, an unattributable row's refusal, and no fabricated saving anywhere | one scenario (`populated`) and two panes. It asserts what the window *speaks*, so a rule broken in a state this fixture does not reach is outside it |

The third exists because the first two share a blind spot: neither runs the product. A figure the
router does not observe reaching the screen is a defect the unit suite cannot express and the
fidelity harness would compare against a mock that draws the same figure.
