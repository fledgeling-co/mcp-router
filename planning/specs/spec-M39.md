# spec-M39 — the expiry ring, and a fallback the Mac states rather than offers

| | |
|---|---|
| ID | M39 |
| Status | Developer Review — ready to verify |
| Category | mac · the pairing sheet's render half |
| Depends on | M6 ✓ (the sheet, the QR, the code, the countdown text, the reissue control) · I1 ✓ (the wire the QR carries) |
| Related | I5 (measured that no pairing transport exists) · M23 (owns converting this surface to the design of record) · DEF-001 · DEF-064 |
| Brief | `planning/features-to-triage/phone-pairing-qr-render-and-countdown.md` |
| Source mock | `design/mocks/prototype.html` — **the superseded prototype, and deliberately.** §3 |
| Plan | `planning/plans/plan-M39.md` |
| Tree everything below is measured at | `f0b6e0f` |

---

## 1 · Feature description (the brief, verbatim)

> ## What and why
> The desktop pairing sheet displays an interactive QR code and visual countdown ring that reflects
> pairing token validity. Currently, the pairing sheet displays a placeholder refusal indicating
> that pairing transport is unavailable. Rendering an active QR code with clear expiration
> countdowns enables mobile users to establish secure companion connections quickly.
>
> ## Acceptance sketch
> - Initiating a pairing session displays a high-contrast QR code alongside the alphanumeric
>   pairing string.
> - A visual progress ring indicates remaining validity time before the pairing code expires.
> - Expired codes automatically refresh with an updated token upon user request.
> - The pairing view provides clear fallback instructions for manual alphanumeric entry if the
>   camera cannot scan.

---

## 2 · The frame this item must not blur

**Pairing does not do anything outside this process, and nothing here changes that.**

`ShellPairingFactory.choice` returns `.noTransport` for any Release build and ignores the
environment while doing it — `return .noTransport`,
`app/Sources/MCPRouterUI/Shell/ShellPairingFactory.swift:43` at `f0b6e0f`. `PairingSessionModel`'s
own enum says the consequence: `case noEndpoint`,
`app/Sources/MCPRouterUI/Boards/PairingSessionModel.swift:18` at `f0b6e0f`, documented there as the
only phase a Release build reaches.

So `Phase.live` — the one phase that draws a QR, a code, a countdown, and now a ring and a fallback
line — is reachable only in a Debug build with `MCPROUTER_PAIRING` set to a named fixture. The phone
side is the same shape one device along: `FixturePairingService` is the only conformance of
`PairingService` in production source, and `MCPRouterIOSApp` wires it unconditionally.

**This item is presentation over a fixture. It is stated rather than implied, and it is not a
defect in the item** — the ledger row allocating M39 says so in its own words: *"This item is the
render half; the transport is not in it."*

Two consequences that bind everything below:

- **No case in this item is `effect-witness`, and none claims an effect.** There is no recorder, no
  effect class and no count, because nothing crosses a process boundary. `references/effect-boundary.md`
  §5 is what that rung would owe, and this item owes none of it because it claims none of it.
- **REQ-016 is `vacuous`, not contradicted, and M39 does not move it.** The guarantee *"stores a
  record only after that contact succeeds"* cannot be violated by a build that never contacts
  anything. Building a ring on top does not make the guarantee testable and must not be reported as
  progress against it. What M39 touches is REQ-015 — *the code and QR are rendered* — which is an
  affordance requirement with effect class `none`.

---

## 3 · Which design document governs this surface, and why it is the superseded one

`ORCHESTRATOR.md`'s Contract row makes `design/mcp-router-console.html` the design of record as of
2026-08-22 and says the prototype *"is cited only for surfaces not yet converted"*.

**This surface is not converted.** The sheet's lede is the prototype's word for word — the console
draws *"Scan this in MCP Router on your iPhone"* and a four-line grants list this sheet does not
have. Converting it is `M23`'s contract (five measurement layers, a breadth-before-depth ledger, a
third exit state), not something to do by eye inside a render item. So the prototype is the citable
design here, and the divergences below are stated against it rather than smuggled past it.

### 3.1 · The mock's ring is a spinner, and this item ships a different thing

`.ring` in the prototype is `animation:spin 2s linear infinite`,
`design/mocks/prototype.html:287` at `08a24ed` — an **indeterminate** indicator. Its head turns at
one rate with four minutes left and with four seconds left, so it carries no information about the
countdown beside it.

Three reasons the determinate arc is what ships:

1. **The brief asks for the determinate one.** *"A visual progress ring indicates remaining
   validity time"* is a description of a thing the spinner does not do.
2. **The fraction is observed.** This Mac issued the code and holds both ends of its window, so
   `DESIGN.md` §6 permits it on screen. A spinner is the case §6 refuses: a moving thing that stands
   for no reading.
3. **On this build the spinner would say something false.** Nothing in either app target binds a
   listener. A perpetual spinner on the pairing sheet reads as this Mac waiting for a phone, which
   is the one thing it is not doing.

**The design of record draws no ring at all** — it states the expiry as text, reading
`expires in 2:41`, `design/mcp-router-console.html:3853` at `08a24ed`. That is recorded here so
M23's conversion has the fork written down rather than rediscovering it: converting this sheet means
deciding whether the ring survives, and this item's answer is only that the *prototype's* ring should
not ship as drawn.

### 3.2 · The typed-code fallback is a sentence, not a control

The prototype draws `Can't scan? Type a code</button>`,
`design/mocks/prototype.html:1312` at `08a24ed` — a **button**, on the Mac sheet.

DEF-064 measured what that button is: the copy exists as `InboxCopy.Pairing.typeInstead` and the
only view that draws it is the **phone's** `PairingFlowView`, where it switches the flow from the
camera to a keypad. The Mac has no such screen to switch to. It already draws the eight characters
in full underneath the QR, and the device that does the typing is the other one. A button here
would change no state and reveal nothing.

So the fallback ships as the instruction the brief actually asks for — *"clear fallback
**instructions** for manual alphanumeric entry"* — in the design of record's own words for it:
`If the camera will not focus, type the code instead`,
`design/mcp-router-console.html:3857` at `08a24ed`, pointed at the phone.

`InboxCopy`'s own comments already argue this case twice on this surface — the removed Undo beside
"Installed", and the denied-notifications line that was written and deleted rather than rendered
into a phase nothing can enter. This is the same rule a third time.

---

## 4 · What was already built, and what this item added

| Sketch line | Where it lives | This item |
|---|---|---|
| QR beside the alphanumeric code | `PairingQRView` and `issued.code.formatted`, drawn in `live(issued:encoded:)`, `app/Sources/MCPRouterUI/Boards/PairingSheet.swift:209` at `f0b6e0f` | nothing — M6 shipped it |
| Expired codes refresh on request | `Button("Show a new code") { session.reissue() }` in the action bar, offered only in `.expired` | nothing — M6 shipped it |
| **A visual ring for remaining validity** | **nowhere** | **§4.1** |
| **Fallback instructions for typed entry** | **nowhere on the Mac** — DEF-064 | **§4.2** |

### 4.1 · The ring

- `public func fractionRemaining(at now: Date) -> Double?`,
  `app/Sources/MCPRouterKit/Pairing/MacPairing.swift:90` at `f0b6e0f` — on `IssuedPairingCode`.
- `public var fractionRemaining: Double?`,
  `app/Sources/MCPRouterUI/Boards/PairingSessionModel.swift:205` at `f0b6e0f` — read off the model's
  own `now`, so the ring and the text are two renderings of one reading and cannot disagree by a tick.
- `struct PairingExpiryRing: View`,
  `app/Sources/MCPRouterUI/Boards/PairingSheet.swift:99` at `f0b6e0f` — a `--line-strong` track and a
  `--attn` head, trimmed by `.trim(from: 0, to: fraction)`,
  `app/Sources/MCPRouterUI/Boards/PairingSheet.swift:111` at `f0b6e0f`.
- `static var expiryRing: Double { MetricToken.controlMini.leadingScalar }`,
  `app/Sources/MCPRouterUI/Boards/InboxBoardMetrics.swift:60` at `f0b6e0f` — size and stroke from
  documented tokens. `no-raw-design-values.sh` cannot see this on its own: its rule forbids
  `lineWidth: <digit>`, and a `lineWidth:` naming a property passes whatever the property holds. The
  suite asserts the two tokens by identity instead.

**The denominator is the issued window, never `MacPairing.lifetime`.** `PairingSessionModel.issue`
takes its lifetime from the service precisely so a transport minting shorter-lived codes is described
accurately; a fraction read off the constant would draw a ring that starts part full and never
empties for any such code. That is the single most load-bearing decision in the item and it has an
arm of its own (A1).

Three shapes are answered rather than left to `Shape.trim`: a clock earlier than `issuedAt` clamps to
1, a window of zero or less has no fraction, and a dead code returns nil rather than zero so the ring
and the countdown vanish together.

**The ring is hidden from the accessibility tree.** The line beside it says the same thing in words
and always does; VoiceOver reading one countdown twice is noise. The consequence for verification is
stated in §6: this addition is not visible to an AX-tree oracle, and a glass case for it has to be
raster.

**No animation.** The arc changes once a second because `PairingSessionModel.now` changes, which is a
redraw and not motion, so Reduce Motion has nothing here to switch off.

### 4.2 · The fallback

- `public static let typeInsteadDetail`,
  `app/Sources/MCPRouterKit/Inbox/InboxCopy.swift:250` at `f0b6e0f` — *"Can't scan? Type those eight
  characters into your phone instead — it is the same pairing."*
- `private var typedFallback: some View`,
  `app/Sources/MCPRouterUI/Boards/PairingSheet.swift:254` at `f0b6e0f`, rendered in the live state.
- The suite asserts the action bar did **not** gain a fourth control, because the failure this
  closes is a declared control with nothing behind it and adding one would be that failure again.

---

## 5 · State matrix

`PairingSheetStates.treatment(for:)` is the exhaustive declaration and it is updated for
`.populated`: *"Phase.live — the QR, the code, the countdown with its depleting ring, and the
typed-code fallback sentence"*. The other eight cells are unchanged; neither addition renders outside
`.live`.

| Reading | What the ring draws | What the text says |
|---|---|---|
| at issue | full | `expires in 5:00` |
| midway | half | `expires in 2:30` |
| final second | a hairline arc | `expires in 0:01` |
| expired | nothing | nothing — the sheet is in `.expired` |
| no endpoint | nothing | nothing — the sheet is in `.noEndpoint` |
| window unreadable | nothing | the countdown still renders |

The last row is the one worth stating: the ring is drawn only where the model hands over a fraction
rather than defaulted to full, so a window that could not be read draws no arc instead of drawing a
lie about how much time is left.

---

## 6 · What this item does not verify, stated as a limit rather than left quiet

- **No glass evidence.** The sheet was not opened on a running Mac app in this item. The machine's
  load average ran 114–700 across 16 cores with eight runners live, and the run's stop rule is
  before verify. `SURF-010`'s existing capture is from 2026-08-20 and predates both additions.
- **The ring cannot be proven by the accessibility tree**, by construction (§4.1). A glass case for
  it is `raster-visual` and owes a capture method and a frame status.
- **The oracle rung here is `structural`.** The behaviour of `fractionRemaining` is proven directly;
  everything about what the *view* draws is a source-binding read through
  `ShellTestSupport.declarationBody`, which strips comments so a paragraph discussing a modifier
  cannot satisfy an assertion about it. That is a weaker rung than a rendered frame and it is
  recorded as such on every case rather than dressed up.
- **REQ-016 is untouched.** Nothing here contacts a device.
