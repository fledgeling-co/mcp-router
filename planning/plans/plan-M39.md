# plan-M39 — the expiry ring and the typed-code fallback

| | |
|---|---|
| Spec | `planning/specs/spec-M39.md` |
| Branch | `ai/n6` · worktree `.worktrees/N6` |
| Tree | `f0b6e0f` |
| Scope | the Mac pairing sheet's live state, and the two things in the brief's sketch that were not already built |

---

## Steps, and what each was measured by

| # | Step | Landed | Proven by |
|---|---|---|---|
| 1 | Read the sketch against what M6 shipped; two of four lines were already built | spec §4 | source read, cited by path and tree |
| 2 | An observed fraction on `IssuedPairingCode`, denominated by the issued window | `MacPairing.swift` | `fractionSpansTheWindow`, `theDenominatorIsTheIssuedWindow`, `theFractionIsBounded`, `theFractionAgreesWithTheCountdown` |
| 3 | The same reading published on the session model, off its own clock | `PairingSessionModel.swift` | `theFractionFalls` |
| 4 | Ring geometry from `MetricToken`, not from picked numbers | `InboxBoardMetrics.swift` | `theRingGeometryIsTokenised` |
| 5 | `PairingExpiryRing` — determinate arc, `--line-strong` track, `--attn` head, hidden from VoiceOver | `PairingSheet.swift` | `theRingDrawsTheFraction`, `theRingSymbolsAreReal` |
| 6 | The countdown carries the ring beside its words | `PairingSheet.swift` | `theCountdownBindsTheRing` |
| 7 | The typed fallback as copy, and as a line in the live state, with no control | `InboxCopy.swift`, `PairingSheet.swift` | `theTypedFallbackIsStated`, `theFallbackCopyIsTheMacs` |
| 8 | `.populated`'s state-matrix cell restated | `InboxBoardMetrics.swift` | compiles exhaustively; read in spec §5 |
| 9 | Fourteen arms, each watched red | `planning/evidence/M39/arming.md` | the arming pass itself |

## The forks, and how each was settled

**Determinate arc or the mock's spinner.** Settled from the repository rather than referred: the
brief asks for a ring that *indicates remaining validity*, `DESIGN.md` §6 forbids drawing what was
not observed, and the fraction is observed. The losing option is better at literal mock fidelity and
at nothing else, and the mock it would be faithful to is the superseded one. Recorded in spec §3.1
with the design of record's own treatment beside it, so M23 inherits the fork stated.

**A button or a sentence for the typed fallback.** Settled by what the control would do: nothing.
The Mac already draws the code and the phone does the typing. DEF-064 is the same finding reached
from the registry side. Spec §3.2.

**Whether to build at all, given DEF-001.** Not this item's to reopen — the ledger row allocating
M39 says the transport is not in it. What the item owes instead is saying so everywhere it could be
read otherwise: spec §2, the suite's own doc comment, and the note on every case row.

## Deferred, and to whom

- **Glass evidence for both additions.** `SURF-010` has one capture, taken 2026-08-20, predating
  them. A raster case is the only rung that can see the ring at all (§6). Owed to verify.
- **`SURF-010`'s `controlsUnactuatable` row for `Can't scan? Type a code`.** Updated in this item to
  say what is now true; the control is still not present and deliberately so.
- **The conversion of this sheet to the design of record.** M23's, and now with the ring fork
  written down for it.
