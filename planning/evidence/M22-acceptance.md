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
| Harnesses (board) | — | — | **not yet driven** |
| Insights (board) | — | — | **not yet driven** |

Rows two and three are deliberately present and empty rather than absent. An evidence file whose
missing rows are invisible reads as a file with nothing left to do, which is the failure this
ledger exists to prevent; a row saying *not yet driven* is a measurement of the gap.

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
