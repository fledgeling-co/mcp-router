# spec-M16 — the Signal Path replaces the Breaker Column

| | |
|---|---|
| ID | M16 |
| Status | Needs More Info |
| Category | mac · mock conversion |
| Depends on | M3 ✓ · M23 ✓ |
| Blocked by | one essential question in §2, which is the same fork M21 carries |
| Brief | `planning/features-to-triage/M16-signal-path.md` |
| Source mock | `design/mcp-router-console.html` — the design-authority question is §2's question |
| Triage | 2026-08-22 · §2 is owner-facing · §3 is the pipeline record |

---

## 1 · Feature description (the brief, verbatim)

> # M16 — the Signal Path replaces the Breaker Column
>
> **Depends on:** M3. **Supersedes:** M3's signature element only; M3's state-correctness rules
> stand unchanged.
> **Source:** `design/mcp-router-console.html`, PRD §9.2.
>
> `DESIGN.md` and M3 specify a Breaker Column — one physical lever per server, snapping up when
> live. The mock replaces it with a patchbay that reads left to right, because a breaker answers
> "is this on" and the question this product exists to answer is "what is wired to what, and what
> is it costing right now".
>
> ## What it is
>
> Three parts on one rail:
>
> 1. **Harnesses** — the wired clients, each with a state dot: routed over HTTP, routed through a
>    stdio shim, or not routed. This is R7's finding stated as a picture.
> 2. **The hub** — `Router :8879 · 0 at rest`. The product's central claim as a live readout.
> 3. **The jacks** — one per upstream, on a 44px lane, packed into as many columns as the width
>    allows.
>
> A jack carries a plug, the server name, and its condition **in words**: `3:41 left`,
> `tripped`, `2 held changes`, `dormant`, `needs sign-in`. The plug colour and the jack's border
> change with the state; neither is the only signal. The plug lights the moment something calls
> the server and goes dark when the reaper closes the child.
>
> Selecting a jack selects that server in the table below and in the inspector, and the reverse
> holds. One selection, three representations.
>
> ## Why the metaphor is allowed to be here
>
> A metaphor that stops matching its data becomes decoration. This one is bound to observed
> state at every point: the plug states are the real child lifecycle, the arrow count is the
> measured topology, and `0 at rest` is a number the router reports rather than a slogan. If the
> pooling model changes, the signature changes with it rather than being kept for its looks.
>
> ## Constraints found by building it
>
> **It must not grow with the server count.** Laid out as a single column, eleven upstreams ran
> the band 500px deep and pushed the table off the board. It is a grid of tracks that packs to
> the width available, and the rail's gutters are tight enough that two jacks fit beside an open
> inspector.
>
> **The sub-label must fit.** Truncating `3:41 left` to `3:41 …` removes the only part of the
> label that was carrying information. Where the width is tight, drop the redundant word — the
> plug colour already says "awake" — rather than clipping the countdown.
>
> Deep link: `?only=mac&pane=servers`.
>
> ## Converting this to SwiftUI
>
> The jack field is a `LazyVGrid` with `GridItem(.adaptive(minimum: 132, maximum: .infinity))`,
> which is the direct translation of the mock's `repeat(auto-fill, minmax(132px, 1fr))` and gives
> the same packing behaviour at every width. Do not lay the jacks out with a fixed column count;
> the mock's one-column failure at the real window width is what that produces.
>
> - A jack is one `View` with a `JackState` enum driving plug fill, border and label. One view,
>   five states, so a new state cannot be added to the model without the view failing to compile.
> - The rail is an `HStack` of harness column, arrow, hub, arrow, jack grid. The arrows are
>   `Image(systemName: "arrow.right")` at a fixed 20pt width.
> - The plug transition is `.animation(.easeOut(duration: 0.2), value: state)` on the fill and the
>   ring. The mock specifies the duration and curve; motion is the one layer the mock's own capture
>   engine could not execute, so this is a spec to implement rather than a measurement to match.
> - Selection is shared state across the jack grid, the table and the inspector — one
>   `@Binding var selectedServer: ServerID?`, three readers.
>
> Acceptance: a structure dump at the target window width shows the jacks in two or more columns,
> and each jack node carries its state word in its accessibility label (M23). Colour alone is not
> the state, on screen or in the tree.

---

## 2 · Triage — 2026-08-22

**Sentinel review:** S1 — Block pending the one essential question below.

Everything else in this item is settled and buildable. What is not settled is whether the thing it
replaces is meant to be replaced, and that is not a question the code, the closest analogue, or the
safer option can answer, because the two documents that would answer it say opposite things and both
are yours.

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*

- **Where it shows up:** the Servers board *(customer-facing — existing surface, its signature element is exchanged)*. Nothing else changes.
- **What users will see — per surface:**
  - Servers: a band across the top of the board reading left to right — the AI tools wired to the router, each with a word for how it reaches it; then the router itself with a live count of what is awake; then one socket per server, laid out in as many columns as the window is wide. A socket carries a plug, the server's name, and its condition in words: how long before it goes to sleep, that it is tripped, that it is holding changes, that it needs signing in. Selecting a socket selects that server in the table and in the panel beside it, and the other way round.
- **Behaviour changes:**
  - The plug lights the moment something calls a server and goes dark when the router closes it, which is what the levers do today.
  - The band packs to the window width rather than growing a column downward, so eleven servers do not push the table off the board.
- **Design reference:** the console mock's Servers board draws the band; the current design document draws the lever column instead, which is the question below.

**Essential Questions**

1. *[Layout]* **Does the row of physical levers on Servers stay?**

   The design document that governs the app today names the lever column as the app's signature
   element, records nineteen of its measurements, and says it is *"the only loud thing in the app"*.
   The newer console mock every brief in this programme is drawn from replaces it with the band
   described above. The product requirements say the mock supersedes the design document. The
   design document itself separately records that *"a second subject-mined element"* is still owed
   and that the lever is the only one there is. Nothing in the repository joins those up, and the
   only decision recorded on the subject keeps the older document.

   a) Build the band and retire the levers, and re-write the design document to match. This is what
      the brief, the mock and the product requirements all describe. It removes a built, measured
      element and is the expensive one to reverse.
   b) Keep the levers and add the band beside them as the second signature the design document says
      is owed. *(reversible — nothing built is removed, and (a) stays available afterwards)* The
      cost is two pictures of the same state on one board, which is the redundancy the mock removed
      on purpose.
   c) Keep the levers and treat the console mock as an exploration. This item closes with no work,
      and M21 closes the same way.

   My lean is (a), because it is what three documents describe and because every other item in this
   programme is drawn from the same mock — but the losing options are genuinely better at something:
   (b) keeps a built element and honours a gap the design document names itself, and (c) is the only
   answer consistent with the one decision actually recorded. Which of those matters more is yours.

   **One thing worth knowing before you answer.** The conversion instrument that merged yesterday is
   already pointed at the console mock: its only manifest names that file and the section of it that
   draws the band. So the pipeline's one measured route to calling this board finished already
   assumes (a). That may be a vote you have already cast, or it may be a default nobody chose.

   **This is one question, not two.** M21 asks it in its general form — which document is the design
   authority. Answering either settles both, and the six other items in this programme are recorded
   as proceeding under the mock in the meantime.

*Easy reply — edit your answer under the question (or correct an assumption), then re-run `/triage M16`:*

> `1. <a | b | c>`

**Assumptions** *(these hold under answer (a); (b) narrows them and (c) voids them)*

- `[Layout]` The band packs to the window width rather than to a fixed number of columns. *(a single column ran 500px deep at eleven servers and pushed the table off the board — the brief measured it)*
- `[Layout]` Where a socket is too narrow for its condition, the redundant word is dropped and the countdown kept. *(the countdown is the part carrying information)*
- `[Experience]` Every state has a word as well as a colour, in what is drawn and in what a screen reader announces. *(already this app's rule, and it is why one amber dot means something)*
- `[Experience]` One selection shared by the band, the table and the panel. *(three pictures of one thing, not three states)*
- `[Operations]` The wording for how each AI tool reaches the router comes from the reading the router already produces, not from a second phrasing invented here. *(one name per state, taken from one source)*

*If any of these are wrong, edit it inline in this file and re-run `/triage M16` before the planner picks this up.*

---

## 3 · Grounding record — pipeline note, not owner-facing

Measured on the main checkout at `7b730ee`, 2026-08-22.

### 3.1 The fork, quotable in both directions

| Document | What it says |
|---|---|
| `DESIGN.md` §1 | *"Signature element: the breaker column on Servers … it is the only loud thing in the app."* Direction is *Instrument Panel*, Terminal Dark |
| `DESIGN.md` §2 | a 19-row `Breaker geometry (specified)` table plus two springs in §7, written because *"two prototype rounds failed on construction"* |
| `DESIGN.md` §10 | *"A second subject-mined element. The breaker is the only one."* — recorded as the next design work |
| `DESIGN.md`:8 / `ORCHESTRATOR.md`:18 | the reference implementation and design authority is `design/mocks/prototype.html` |
| `PRD.md` §9.1 / §9.2 | Patchbay supersedes Instrument Panel; the Signal Path is the signature; *"until it is re-authored, the mock and this section are the authority and `DESIGN.md` is historical. Resolving that is tracked as M21."* |
| `planning/test-campaign/` DEF-016, DEF-012 closures | *"Closed 20 Aug 2026, on the owner's decision that `design/mocks/prototype.html` remains the design of record for the Mac console."* `campaign.json`'s `designOfRecord` is that file |
| `design/mcp-router-console-spec.md`:3 | the console mock was built *"deliberately ignoring the project's existing `DESIGN.md` and `design/mocks/prototype.html` per the brief"* |

The owner's recorded decision and the PRD's claim are about different artifacts and were never
joined; neither names the other. That is why this is a real fork rather than a stale row, and why it
cannot be closed from inside the repository.

### 3.2 What is built, and what is absent

- Built and cited as the signature in source: `app/Sources/MCPRouterUI/Breaker.swift:4` — *"The breaker — the app's signature element"*; `app/Sources/MCPRouterKit/Design/BreakerGeometry.swift:5` — *"the breaker is the app's signature element and `DESIGN.md` §1 says so"*. `BreakerState` has four cases; `ServersBoardRow.swift:46` draws it; `ServersBoardTable.swift:20` sizes the row gutter from `BreakerGeometry.standard.housingWidth`.
- Absent: no `Jack`, `SignalPath`, `Patchbay`, `Hub` or `Rail` type exists anywhere in `app/Sources`. `LazyVGrid` with `GridItem(.adaptive` exists in three places, none of them on Servers.
- The breaker vocabulary survives inside the console mock itself: its Router menu draws `Trip Selected Breaker ⌃T`, and `tripped` is one of the jack's own state words. So the mock retires the lever *drawing*, not the concept — which is what makes option (b) coherent and also what makes it redundant.

### 3.3 M23 has already enumerated this item's work

`planning/fidelity/servers.ledger.md` is the filled breadth ledger from M23's gate, and its citations
point at this brief by name. Rows already recorded `absent` against the build include
`v-ideal/card/signal-path-5-harnesses-1-endpoint-11-upstreams-` and `v-ideal/indicator/unlabelled`
(the harness state dots), each cited to `planning/features-to-triage/M16-signal-path.md`. The
`servers.pairing.tsv` header states the cause outright: *"the Servers board in the build was written
against DESIGN.md (Instrument Panel, breaker column) and the mock draws Patchbay (signal path, jack
lane, inspector)."*

The gate currently returns exit 1 on `servers` with 116 breadth findings and 16 copy findings. A
large share of those close only under answer (a); under (c) the manifest is re-keyed to
`prototype.html` and most of them evaporate. **This is the measurement that makes the question
expensive rather than academic.**

### 3.4 What the campaign measured, and what it did not

`SURF-002` (*"Mac Servers board"*) passes its structural witness against `prototype.html` —
*"Everything the design specifies as chrome is drawn … five columns server/transport/tools/calls/last
used, the per-row health tile"* — and fails `raster-visual` on a trailing evaluation pill the build
omits, which is DEF-042's class and M28's docket rather than this item's. **Nothing in the campaign
measures the band, the sockets or the packing behaviour**, because they do not exist and the campaign
never pointed at the console mock. Do not read `SURF-002 | pass` as evidence about this item.

### 3.5 What this item still owes M23's gate

`servers.layers.json` and `servers.pairing.tsv` exist and `MeasureDump` already carries
`case servers`, so Servers is the one surface in the programme that inherits a working instrument
rather than having to author one. Under answer (a) the pairing file gains rows for the band and the
sockets; under (c) the manifest's `mock` field is what changes.

### 3.6 Gate record

- Codebase grounding: source read across `app/Sources`, `design/`, `PRD.md`, `DESIGN.md`, `planning/fidelity/`, `planning/test-campaign/`.
- Second-opinion lane: `agy` / `gemini-3.7-flash-high`, read-only, asked whether blocking both M16 and M21 on one shared question is right or whether M16 should proceed on an assumption. `codex` is down until 2026-08-27. Disposition in §3.7.
- The three-part essential bar: no internal source yields a safe default (the two documents contradict), guessing wrong destroys a built and measured element or wastes the whole programme's source, and the decision is a direction call that only the owner makes. All three hold, so this is a question rather than an assumption.

### Out-of-family review — record and disposition

Three out-of-family lanes were attempted for the required review. `codex` / `gpt-5.6-sol` is recorded
down until 2026-08-27 and was not attempted. `grok-4.6` refused with `API error (status 402 Payment
Required): Grok Build usage balance exhausted` and wrote a zero-byte report. `agy` /
`gemini-3.7-flash-high` timed out on its first invocation with `Error: timeout waiting for response`
and a zero-byte report, and **answered on one retry** — so the out-of-family gate did run, on the
Google family, and is not a downgrade. A fourth lane, `claude-fable-5` at high effort, was started in
parallel as the in-family fallback and also answered; it is recorded as a second reading rather than
as the gate, and where the two disagreed the repository settled it.

Both lanes were briefed adversarially over all eight verdicts at once, told to refute, and told that
finding nothing is a failed review. Verdict: **AMEND** from both. The dispositions that touch this
item are below; the full set is repeated in each spec it changes.

- **Accepted, and it is the strongest single argument for blocking.** `app/Tests/MCPRouterKitTests/BreakerParityTests.swift` declares `BreakerGeometryParityTests`, which reads `DesignDocParser.breakerRows(in:)` out of `DESIGN.md` and compares the name set against `BreakerGeometry.standard.documentedValues` for **exact equality in both directions**, then checks every value. Verified in the file. So removing the levers reddens a parity test whose oracle is the very document the answer decides the fate of. **This item cannot start under answer (a) without the `DESIGN.md` edit that is M21's contested act** — which is a mechanical reason for the block, on top of the direction reason.
- **Accepted and folded into the question.** M23's merged manifest is already keyed to the console mock — `planning/fidelity/servers.layers.json` carries `"mock": "design/mcp-router-console.html"` and `"section": "b-servers"`, the Signal Path's own section — so the pipeline's only measured route to Done for this board already presupposes answer (a). That is evidence the owner may have voted with the M23 merge, and it makes the question answerable in one line. Added to §2.
- **Accepted in part — the framing, not the verdict.** One lane argued M16 should carry `Depends on: M21` rather than a question of its own. The header now names M21 as what blocks it and §2 says one answer settles both, but the question stays here because M16 adds an option M21's general form does not surface: keeping the levers *and* adding the band as the second signature the design document says is owed.
- **Accepted:** the brief's `minimum: 132`, its 20pt arrow width and its 0.2s duration are geometry and motion literals the lint rule described under M15 would reject in a board file. They route through `MetricToken`.
