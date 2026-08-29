# M39 — the arming pass

Every assertion this item added was watched to fail with the behaviour it guards removed, and
restored afterwards. Verdict lines only: the producing command is in each header, and no raw gate
capture is committed here.

Produced by a harness that, per arm, applied one edit to production source, ran

```
swift test --filter 'PairingSheetTests|MacPairingTests|PairingExpiryTests'
```

from `app/`, recorded the exit code and the names Swift Testing reported an issue against, and
rewrote the original bytes in a `finally` — so a red run cannot leave a mutation behind.

Product tree: `f0b6e0f`. Suite at that tree: 38 tests in 4 suites, exit 0.

## The arms

| # | Mutation | File | Verdict | Assertion that fired |
|---|---|---|---|---|
| A1 | the fraction's denominator becomes `MacPairing.lifetime` | `app/Sources/MCPRouterKit/Pairing/MacPairing.swift` | RED exit 1 | a code with a shorter window still spans one to nil |
| A2 | the fraction is hard-wired to 1 | `app/Sources/MCPRouterKit/Pairing/MacPairing.swift` | RED exit 1 | a code with a shorter window still spans one to nil · the fraction spans the issued window, one to nil · the fraction the ring draws is observed, and it falls as the clock runs |
| A3 | the upper clamp is dropped | `app/Sources/MCPRouterKit/Pairing/MacPairing.swift` | RED exit 1 | a backwards clock clamps and a degenerate window has no fraction |
| A4 | the zero-window guard is dropped | `app/Sources/MCPRouterKit/Pairing/MacPairing.swift` | RED exit 1 | a backwards clock clamps and a degenerate window has no fraction |
| A5 | the countdown stops drawing the ring | `app/Sources/MCPRouterUI/Boards/PairingSheet.swift` | RED exit 1 | the countdown draws the ring from the session's own fraction |
| A6 | the arc is drawn full rather than trimmed to the fraction | `app/Sources/MCPRouterUI/Boards/PairingSheet.swift` | RED exit 1 | the ring trims to the fraction it is handed and is hidden from VoiceOver |
| A7 | the ring is exposed to VoiceOver a second time | `app/Sources/MCPRouterUI/Boards/PairingSheet.swift` | RED exit 1 | the ring trims to the fraction it is handed and is hidden from VoiceOver |
| A8 | the arc's head loses the attention token | `app/Sources/MCPRouterUI/Boards/PairingSheet.swift` | RED exit 1 | the ring trims to the fraction it is handed and is hidden from VoiceOver |
| A9 | the model's fraction is renamed on both sides | `app/Sources/MCPRouterUI/Boards/PairingSessionModel.swift`, `app/Sources/MCPRouterUI/Boards/PairingSheet.swift` | RED exit 1 | **build refused** — see A9b |
| A9b | the model's fraction declaration is reformatted; compiles, behaviour identical | `app/Sources/MCPRouterUI/Boards/PairingSessionModel.swift` | RED exit 1 | the ring's scanned names are the ones the product declares |
| A10 | the ring's size stops being the mini-control token | `app/Sources/MCPRouterUI/Boards/InboxBoardMetrics.swift` | RED exit 1 | the ring's size and weight are tokens rather than picked numbers |
| A11 | the live state stops drawing the fallback | `app/Sources/MCPRouterUI/Boards/PairingSheet.swift` | RED exit 1 | the live state states the typed fallback, and adds no control for it |
| A12 | the Mac's fallback copy becomes the phone's button | `app/Sources/MCPRouterKit/Inbox/InboxCopy.swift` | RED exit 1 | the Mac's fallback copy points at the phone and is not the phone's own button |
| A13 | the ring's type declaration is reformatted; compiles, behaviour identical | `app/Sources/MCPRouterUI/Boards/PairingSheet.swift` | RED exit 1 | the ring trims to the fraction it is handed and is hidden from VoiceOver · the ring's scanned names are the ones the product declares |

Fourteen arms, fourteen red. Nothing here was accepted on a first reading.

## The two the first pass got wrong, and what changed

**A4 came back STILL-GREEN, and the assertion was rewritten rather than the arm.** Deleting
`guard window > 0` left every test passing. The reason is that `timeRemaining(at:)` already returns
nil for a zero-length window read at or after its issue instant, so both readings the test made
short-circuited before the guard was reached — a guard the suite claimed to cover and could not
reach. The reading that does reach it is a zero-length window read from *before* it was issued:
`timeRemaining` answers sixty seconds there, the division is by zero, and `min(_:, 1)` returns the
infinity as a full ring. That case was added and A4 then went red. The alternative — deleting the
guard as unreachable — was rejected because the input is representable and the failure it prevents
is a silent full ring rather than a crash.

**A9 reddened only by refusing to build, which is not the same as the assertion firing.** Renaming
`fractionRemaining` breaks the test file that reads it, so the run never reached the source scan the
arm was aimed at. A9b arms the same assertion with an edit that compiles and changes no behaviour —
a line break inside the declaration — and the named scan fires on its own. A13 is the same
correction applied to the ring's type declaration. The residual weakness is stated: these two scans
read declaration text, so a reformat reddens them. That is the safe direction — they fail loudly
rather than going quiet — and it is why `theRingSymbolsAreReal` exists at all.

## What this pass does not establish

- Nothing here was drawn on glass. Every arm ran in-process against compiled views and pure
  functions; no window was opened and no pixel was photographed.
- Nothing here crosses a process boundary. No arm involves a recorder, an effect class or a count,
  because the item claims no effect — `Phase.live` is unreachable in a Release build and DEF-001 is
  unchanged.
- An arm proves an assertion can fail. It does not prove the assertion is the right one, and the
  source-binding rung these six view assertions stand on is weaker than a rendered frame.
