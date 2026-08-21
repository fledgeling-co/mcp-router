# spec-M22 — the Harnesses and Insights boards

| | |
|---|---|
| ID | M22 |
| Status | To Do |
| Category | mac · mock conversion · new surfaces |
| Depends on | M1 ✓ · R6 ✓ · R7 ✓ · M23 ✓ · M21 (the bar-fill colours, and only those) |
| Absorbs | R7-C1 — the Harnesses board and the route behind it. See §3.4: R7-C1 waits on M22 and M22 needs R7-C1, so this item takes both halves |
| Related | M17 (two of its ten surfaces are these) · M18 (the reconcile and analyzer panels open from these boards) · M20 (the View menu's nine boards) |
| Brief | `planning/features-to-triage/M22-harnesses-and-insights-boards.md` |
| Source mock | `design/mcp-router-console.html` — the design-authority question is M21's, recorded in §3.1 |
| Triage | 2026-08-22 · §2 is owner-facing · §3 is the pipeline record |

---

## 1 · Feature description (the brief, verbatim)

> # M22 — the Harnesses and Insights boards
>
> **Depends on:** M1. **Related:** R6, R7 (Harnesses); PRD §8 (Insights).
> **Source:** `design/mcp-router-console.html`, PRD §9.4.
>
> Two boards the mock draws that have no prior brief. Both are surfaces for work already
> specified elsewhere; what is missing is the Mac side of it.
>
> ## Harnesses
>
> The surface R7 argues for. Every harness detected on the machine, and — the part that matters —
> **how each one currently reaches the router, and what it duplicates**.
>
> A row carries the harness name, its config path and version, and a status that is one of four
> readings rather than a boolean: routed over HTTP, routed through a stdio shim, routed but still
> declaring direct upstreams, or not routed. Each reading gets its own honest sentence. Grok's
> row says it reaches the router through `mcp-remote`, that this is one extra process per session,
> and that this is a real cost being named rather than hidden behind a tick.
>
> Above the list sits the finding, when there is one: *"Antigravity runs 18 servers of its own,
> ten of which this router already fronts."* Its action opens the reconcile sheet (M18), which
> shows the diff of the real file before anything is written.
>
> Per-row actions: open config, verify now, reconcile, and — for a harness whose transport forces
> a shim — an explanation rather than a fix, because there is no fix on this side.
>
> The counts on this board are read from the harness config files, so they are only as fresh as
> the last drift check. Settings carries that interval (M15), and a stale reading here is worse
> than no reading.
>
> ## Insights
>
> The counted-usage board PRD §8.2 specifies. Four visualisations, and every number on it is
> counted from calls the router served:
>
> 1. **Four headline counts** — children at rest, resident memory across all children, tool calls
>    over the window, and the failure rate with its numerator and denominator both shown.
> 2. **Calls by harness** — a bar per harness. The value of this chart is the row reading zero:
>    a harness at zero is one still using its own servers, which is the same finding the
>    Harnesses board shows from the other side.
> 3. **Calls per hour** — a sparkline over the last 24 hours.
> 4. **Duty cycle per server** — the share of wall-clock time each child was alive. This is the
>    product's argument in one chart, and it needs the caption that makes it legible: before the
>    router, every one of these sat at 100%.
>
> Below them sits the analyst's own configuration and its last run — which model judged, how many
> lines it read, how many findings it produced — with a link into the analyzer sheet.
>
> **No number here is modelled.** A window with too little history says so (its empty state) rather
> than extrapolating, and the resident-memory figure is labelled *measured, not modelled*. There
> is no fabricated saving anywhere on this board; the saving is the duty-cycle chart, and it is
> counted.
>
> ## Converting this to SwiftUI
>
> **Harnesses** is a `List` of cards, one per detected harness, with the reading as an enum of
> four cases so a fifth transport cannot be added without the view failing to compile. The status
> sentence belongs to the case, not to a string built at the call site.
>
> **Insights** uses Swift Charts for the sparkline and the bar rows, with two constraints the mock
> makes explicit:
>
> - A bar's fill is a token, and the token is the text-safe ink rather than the published hue.
>   The mock uses `--live-ink` and `--attn-ink` for bar fills because the kit greens and ambers
>   fall below 3:1 against a near-white track. Charts will happily paint the brighter one.
> - A zero-valued row must still render its label and its zero. The Antigravity row reading zero
>   is the finding; a chart that drops empty series hides it.
>
> The headline counts are a `Grid` of four cards. Each carries its provenance line — *measured,
> not modelled* on the memory figure, and the numerator beside the failure rate — because those
> lines are the difference between a number and a claim.
>
> Acceptance: a structure dump of Insights contains a labelled node per harness including the ones
> at zero, and the bar fills read as the ink tokens rather than the kit hues (M23).

---

## 2 · Triage — 2026-08-22

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*

- **Where it shows up:** two new boards, Harnesses and Insights *(customer-facing — new screens)*; the navigation list, the View menu and the board shortcuts *(customer-facing — existing surfaces, two rows and two items added)*. Behind the scenes, the router gains a way to report what it already works out for the command line.
- **What users will see — per surface:**
  - Harnesses (new): one card per AI tool found on this machine, carrying its name, where its configuration lives, its version, and how it currently reaches the router said as one of four honest readings rather than a tick — reaching it directly, reaching it through an extra process per session, reaching it but still declaring its own servers as well, or not reaching it. Above the list, the finding when there is one, phrased as a count rather than a judgement, with an action that opens the panel showing the real file's differences. Per card: open the configuration, check it now, reconcile — and, for a tool whose design forces the extra process, an explanation instead of a fix, because there is no fix on this side. The counts are only as fresh as the last check, and the card says so.
  - Insights (new): four headline figures — how many child processes are at rest, how much memory they hold between them, how many tool calls over the window, and the failure rate with both its numerator and its denominator shown. Then a bar per AI tool, where a row reading zero still draws its label and its zero, because a tool at zero is the finding. Then calls per hour over the last day. Then the share of wall-clock time each server was alive, with the caption that makes it legible. Below those, which model read your sessions, how much it read, what it found, and a way into its settings.
  - The navigation list, the View menu and the shortcuts: two rows and two items appear, taking the board count from seven to nine.
- **Behaviour changes:**
  - Every figure on Insights is counted from calls the router actually served. The memory figure is labelled as measured rather than modelled, and where there is not enough history the board says so rather than extrapolating.
  - There is no saving figure anywhere. The argument the product makes is the wall-clock chart, and it is counted.
- **Design reference:** the console mock draws both boards; it is the visual reference, subject to the design-authority question under M21.

**Assumptions**

- `[Data & scope]` This item builds the way the router reports what it already works out, not only the two boards. Otherwise the board and the reporting each wait on the other, which is where they stand today. *(rather than shipping a board that shells out to a command line, or splitting it and stalling both)*
- `[Data & scope]` Everything both boards read is on this Mac and stays on it. Nothing is sent anywhere and nothing is shared. *(no sharing surface exists in this product, and the sessions the analyst reads are the most private thing it touches)*
- `[Experience]` The four readings are exactly four and are a fixed set, so a fifth kind of connection cannot be added without the board being updated with it. *(a boolean would have hidden the extra-process case, which is the finding worth naming)*
- `[Experience]` The sentence for each reading belongs to the reading, not to whatever is drawing it. *(one name per state, taken from one source)*
- `[Operations]` A reading is stamped with when it was taken, and a stale one says so. *(the brief's own words: a stale reading here is worse than no reading)*
- `[Operations]` Where the router has no figure, the board shows nothing rather than a zero. *(a zero is a measurement and an absence is not, and this product already dropped four columns for the same reason)*
- `[Layout]` A bar whose value is zero still draws its label and its zero. *(the zero row is the finding, and a chart that drops empty series hides it)*
- `[Layout]` Bar fills take the text-safe colours rather than the brighter published ones. Which values those are is M21's. *(the kit greens and ambers fall below the floor against a near-white track)*
- `[Compliance]` The caption under the wall-clock chart states the mechanism — a server started this way stays alive for the whole session — rather than asserting a measured figure for a world the router never ran. *(the brief's own caption quotes a percentage for exactly that world, two paragraphs before it says no number here is modelled)*
- `[Operations]` The memory figure crosses from the router to the app through the same reporting this item builds. The router measures it today and the app has no way to ask for it. *(the app may not reach past the router for anything, so a figure the router does not send is a figure the board cannot draw)*
- `[Compliance]` The memory figure is labelled measured, not modelled, and no figure on either board is computed against a world the router never ran. *(the product's standing rule, and the sketch in the requirements' own §8.2 breaks it — see §3.5)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage M22` before the planner picks this up.*

---

## 3 · Grounding record — pipeline note, not owner-facing

Measured on the main checkout at `7b730ee`, 2026-08-22.

### 3.1 Design authority

Recorded in full at `planning/specs/spec-M15.md` §3.1, asked at `planning/specs/spec-M21.md` §2. Not
re-asked here, and this item is the least exposed to the answer of the eight: **the prototype draws
neither of these boards**, so under any answer they are drawn from the console mock or from nothing.
That is also the argument for M21's option (c).

### 3.2 Neither board exists, and neither does the chart library

`app/Sources/MCPRouterUI` contains **zero** matches for `Harness` or `Insight`. `import Charts`
returns nothing anywhere in `app/Sources`. Neither board appears in the campaign's 24-entry surface
registry or the 17-entry surface input. No defect, case, deferred row or witness verdict names either
board as a subject. These are genuinely new surfaces with no prior measurement behind them.

### 3.3 R7 shipped the engine and a command-line verb, not a route

- `app/Sources/MCPRouterCLI/HarnessesVerb.swift` implements `mcp-router harnesses [--json] [--port] [--config] [--host]`, dispatched from `MCPRouterCLI.swift:61`. It reads harness configuration files off disk through `ClientConfigs.inventory` and `HarnessReconciliation.reportAll` and prints text or `{"harnesses":[…]}` to standard output. **It never talks to a running router.**
- `app/Sources/RouterCore/Discovery/HarnessReconciliation.swift` already models the readings: `HarnessState` with `.notWired`, `.wired(route:)` and `.wiredWithDuplicates(route:count:)`, plus `DuplicateEntry`. `HarnessWiring.swift` carries `HarnessDialect` for the per-client spellings.
- **There is no `GET /harnesses`.** `RouterCore/Service/RouterServiceDispatch.swift` has no harness case, and `src/` — the TypeScript reference — contains no occurrence of the string at all.

So three of the brief's four readings exist in the model and one does not: *routed but still declaring
direct upstreams* is not `wiredWithDuplicates`, which counts duplicate entries for the same server
rather than naming a harness that both routes and declares. The planner should treat that fourth
reading as new modelling, not as a rename.

### 3.4 R7-C1 and M22 currently block each other

`planning/features-to-triage/LEDGER.md` carries *"R7-C1 | The Harnesses board and the `GET /harnesses`
route behind it | Deferred (child of R7; blocked on M22)"*, and the ORCHESTRATOR deferred register's
own row says *"R7 ships the engine and a CLI verb only. A control route diverges from
`src/control.ts` and owes a parity row; the surface that draws it is M22, untriaged."*

Each names the other as what it waits for. The assumption above resolves it by giving M22 both halves,
which is the only reading under which either ships. **The route owes a parity row** — it diverges from
the TypeScript reference, and the parity census is at 82 of 83 against an owner-set target, so the
planner must declare the divergence as intent rather than let the gate discover it. That is the single
riskiest thing in this item.

`R7-C3` (opencode's transport is unestablished) and `R7-C4` (project-scoped harness entries) bear on
what a row can honestly say and stay R7's children. `R16` — adoption cannot see project-scoped servers
— is the same blind spot from the other side.

### 3.5 The requirements' own sketch breaks a rule this item must keep

`PRD.md` §8.2 draws an ASCII dashboard reading *"28 MB vs 12.4 GB unrouted"*, *"Savings: 99.8%
processes"* and *"Savings: 99.7% RAM"*. `DESIGN.md` §6 forbids exactly that — *"Numbers the router does
not observe are never displayed. There is no fabricated memory saving anywhere in this app, because
the router never runs the world where every server is resident and so has nothing to subtract from"* —
and `ORCHESTRATOR.md` repeats it as a standing rule.

The requirements text resolves this itself: *"§9.4 and `M22` are the authority on what the Insights
board actually renders"*, and the brief is explicit — *"No number here is modelled … the saving is the
duty-cycle chart, and it is counted."* So the sketch is superseded by the brief, not a contradiction
the owner must adjudicate. Recorded because a planner reading §8.2 alone would build the forbidden
thing.

The same rule already removed graded-evaluation columns from four boards and is the subject of
`DEF-042` on M28's docket.

### 3.6 The analyst does not exist

Both boards reference the session analyst — Insights draws its configuration and last run, and the
analyzer panel is M18's. `PRD.md` §6 specifies it; nothing in `app/Sources` implements it. The brief
handles this correctly by asking for *its own configuration and its last run* rather than for the
analyst itself, so the board draws its empty state until one runs. The planner should keep that
boundary rather than absorbing §6.

### 3.7 What this item owes M23's gate

Two boards, four states each, is eight cells and two surfaces. Each needs
`planning/fidelity/<surface>.layers.json`, a pairing file and a `Surface` case in
`app/Sources/MeasureDump/main.swift`, which declares `case servers` today. The brief's acceptance — *"a
structure dump of Insights contains a labelled node per harness including the ones at zero, and the
bar fills read as the ink tokens rather than the kit hues"* — is a `structure` assertion plus a
`tokens` assertion, and the second one cannot pass until M21 names the values. Under M21 answer (b)
there are no ink tokens and that half of the acceptance is rewritten.

### 3.8 Gate record

- Codebase grounding: `app/Sources/MCPRouterUI`, `app/Sources/MCPRouterCLI`, `app/Sources/RouterCore/Discovery`, `app/Sources/RouterCore/Service`, `src/`, `design/mcp-router-console.html`, `PRD.md` §8 and §9.4, `DESIGN.md` §6, `planning/test-campaign/`, ORCHESTRATOR's deferred register.
- Out-of-family spec review: see §3.9 for which lane answered.
- Nine assumptions. The consequential one is absorbing R7-C1, and it names what it beat.

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

- **The two lanes disagreed here, and the repository settles it in favour of absorbing the route.** One lane said M22 needs router endpoints it does not have. The other said the block is one-directional, that the brief reads its counts *"from the harness config files"* rather than from a route, and that the absorption assumption should be dropped. **The second is wrong, and `scripts/lint/no-raw-design-values.sh` is why:** its A36 boundary rule forbids `FileManager`, `Data(contentsOf:)`, `URL(fileURLWithPath:)`, `Bundle`, `Process(` and every socket type in `MCPRouterUI/Shell`, `Activity` and `Boards`, with the comment *"the Mac app talks to the router ONLY over the loopback control API"* and *"Reading a file is one of the ways past the API."* A Harnesses board lands under `Boards`, so it cannot read a harness configuration file itself. It needs the route. The assumption stands and is now cited.
- **Accepted — the duty-cycle caption breaks the rule the brief quotes two paragraphs later.** *"before the router, every one of these sat at 100%"* is a figure describing a world the router never ran, which is exactly what `DESIGN.md` §6 and `ORCHESTRATOR.md` forbid, and the same class as `DEF-042` on the owner's docket. The brief asserts *"No number here is modelled"* immediately afterwards. Added as an assumption in §2: the caption states the mechanism rather than asserting a measured figure.
- **Accepted — resident memory is observed but may not be reachable.** `app/Sources/RouterCore/Pool/ProcessResident.swift` reads RSS from `ps` router-side, with its own comment citing `DESIGN.md` §6 — *"the number behind it has to be measured, and this is where the observing happens"* — and `ServicePorts.swift:134` references `residentMb()`. **But `app/Sources/MCPRouterKit/Control/Models.swift` carries no resident-memory field**, so the figure does not currently cross the control API to the app. Under A36 the app cannot go and get it. The route this item absorbs must carry it, or the headline figure is not displayable. Recorded here rather than left for the planner to hit at build time.
- **Accepted:** the ink-token half of this item's acceptance waits on M21, for the same verified reason recorded under M19. `M21` is now a dependency in the header.
