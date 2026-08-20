# spec-M23 — the mock-to-SwiftUI conversion contract

| | |
|---|---|
| ID | M23 |
| Status | Ready for Work |
| Category | foundation · method |
| Depends on | F2 ✓ |
| Blocks | M15 · M16 · M17 · M18 · M19 · M20 · M21 · M22 |
| Branch | `ai/m23` · worktree `.worktrees/M23` |
| Owns this wave | `app/Tests/MCPRouterKitTests/MockToken*.swift` · `app/Sources/MCPRouterUI/Measure/` · `app/Sources/MeasureDump/` · `planning/fidelity/` · `scripts/acceptance/mock-fidelity-*.sh` |
| Brief | `planning/features-to-triage/M23-mock-to-swiftui-contract.md` |
| Review | recorded in §8 |

---

## 1 · Feature description (the brief, verbatim)

> # M23 — the mock-to-SwiftUI conversion contract
>
> **Depends on:** F2. **Blocks:** M15–M22, and every later surface built from a mock.
> **Category:** foundation · method
> **Sources:** `design/mcp-router-console.html`; `mockup-fidelity` at
> `.claude/plugins/fledgeling-plugins/plugins/mockup-fidelity/skills/mockup-fidelity/`
> (SKILL.md, `references/react-native.md`, `references/measurement-enforcement.md`,
> `references/engine-capability-matrix.md`); the repo's existing
> `app/Tests/MCPRouterKitTests/DesignDocParser.swift` and `DesignTokenParityTests.swift`.
>
> The project's primary task is converting an HTML mock into SwiftUI without drift. This brief
> specifies how that conversion is proved, and it is worth building before the first board is
> converted rather than after the third one has silently diverged.
>
> ## The problem this is guarding against
>
> `mockup-fidelity` names twelve self-deceptions that produce a verdict which feels rigorous and
> is wrong. Four of them are the ones this project will hit:
>
> - **Code-read certification.** A `ColorToken` literal tells you what a view *declares*, not what
>   rendered. It cannot reveal a view that never appeared, a modifier that lost the cascade, a
>   control the data left empty, or a section that is simply absent.
> - **Style-without-structure.** Diffing each element's colour and size in isolation never
>   reconciles the skeleton — containment, stack axis, sibling order, geometry. Those are the
>   highest-frequency real defects and a per-property diff is structurally incapable of catching
>   one.
> - **Motivated classification.** A real difference labelled intentional without a citation. This
>   is the single most common way drift ships.
> - **A green report from a blind instrument.** A property the measurement cannot compute reads as
>   agreement on both sides and the differ emits nothing. That is not a miss you can see; it is a
>   pass you cannot.
>
> Two measurements make the case that prose cannot fix any of this. Frontier multimodal models top
> out near **40% recall on fine-grained UI differences, under 23% on hard cases** — so comparing
> screenshots is not an audit. And agents under effort pressure rationalise a skipped
> measurement; models trained against that learn to conceal the shortcut rather than stop. What
> works is making the artifact a precondition for the verdict.
>
> ## The four layers, and what measures each on this target
>
> SwiftUI has no DOM, which puts it in the same position as React Native: `getComputedStyle` does
> not exist, and by the time anything is on screen the modifiers have been resolved away. The
> layer table below is the RN table with the tools substituted.
>
> | Layer | Mock side | SwiftUI side | Catches |
> |---|---|---|---|
> | **Tokens** | the `:root` block and the `mac-craft:metrics` comment, both machine-readable | `ColorToken` / `TypeToken` / `MetricToken` | systematic offsets a single element hides |
> | **Structure** | parsed DOM: role, text, stack axis, frame, ordered children | the accessibility tree of the running app | missing, substituted, relocated and reordered elements |
> | **Resolved style** | `getComputedStyle` per element | an in-app measurement harness (below) | colour, font, radius and spacing drift |
> | **Copy** | the mock's text nodes | the `*Copy` enums | placeholder text, absent unhappy-path sentences |
> | **Pixels** | screenshot | `XCTAttachment` bitmap | supplementary only, never the evidence |
>
> **The resolved-style layer is the piece that does not exist yet and has to be built.** Nothing
> outside the process can read a SwiftUI view's resolved foreground colour or font. The working
> shape, borrowed from `references/react-native.md` §2.5, is a **dev-only measurement harness**
> compiled under a `MEASURE` flag: a view modifier that records, per instrumented view, its
> token identity, its resolved colour and font, its `GeometryReader` frame in window
> coordinates, its parent chain, and its stack axis — then writes one JSON dump per surface.
>
> The lesson that reference records is worth repeating, because it cost a whole passing-looking
> audit: a harness emitting a flat list of `{type, text, style}` per node is **layout-blind**. It
> cannot tell an `HStack` card from a `VStack` card, a present divider from an absent one, or a
> two-column grid from a stack. Per node the harness must also emit **containment** (the parent
> chain), **layout** (the stack axis and alignment), and **geometry** (x/y/w/h). Without those
> three, every colour can match while the entire layout is wrong.
>
> ## Re-key the parity test that already exists
>
> `DesignDocParser` already reads token tables out of `DESIGN.md` and `DesignTokenParityTests`
> already compares them to the Swift token types. That mechanism is right and should be kept; it
> is pointed at the wrong document.
>
> The mock carries its tokens in two machine-readable blocks: a `<!-- mac-craft:metrics -->`
> comment of `name value tier` rows, and a `:root` block where every colour lives in a custom
> property with **no colour literal anywhere outside it**. Both parse more easily than the
> Markdown tables the current parser handles.
>
> Add a `MockTokenParser` beside `DesignDocParser`, keyed to `design/mcp-router-console.html`, and
> assert three things:
>
> 1. Every metric row in the mock has a `MetricToken` case with the same value.
> 2. Every `:root` custom property has a `ColorToken` case with the same value, in each of the
>    appearance contexts the mock authors.
> 3. **No Swift file outside the palette type contains a colour literal.** This is the direct
>    analogue of the mock's `literals_outside=0`, it is a grep, and it is the check that stops the
>    system becoming decorative.
>
> Which document is authoritative is M21's open decision. Until it is settled, write the parser
> against the mock and leave the `DESIGN.md` parser in place rather than deleting it.
>
> ## The breadth ledger comes before the style diff
>
> For every surface, fill a **present / divergent / absent** row for every affordance the mock
> shows — every header element, button, card, section, badge, chip, search field, meaningful
> icon, list row and call to action — *before* opening the style findings. A clean style diff
> means nothing about breadth, because the differ only compares elements that exist on both
> sides and is structurally blind to a missing one.
>
> Three rules keep the ledger honest, all of them from the skill's own gate:
>
> - **`PRESENT` is earned by measuring, never inferred from purpose.** Two controls doing the same
>   job are not a match; pair them, then audit label, control kind and glyph.
> - **A citation is external and pre-existing.** A ticket line, a spec line, a code comment that
>   predates the audit, a platform guardrail. A justification composed during the audit —
>   "the app's richer treatment", "native chrome", "probably deferred" — is motivated
>   classification wearing a citation's clothes, and the row is a defect.
> - **Extra elements are divergent too.** Matching the mock means removing what it does not have,
>   not only adding what it lacks.
>
> ## What counts as a surface
>
> Every board, every state of every board, every sheet, the Settings window and each of its panes,
> the popover, the notification, and each open menu. The mock draws 40 board-and-window state
> cells (M17) plus twelve sheets (M18) plus nine menus (M20); each is its own row in the
> inventory, and an omitted surface is an unaudited one rather than a passed one.
>
> "Minor sub-state of X" is not a reason to drop a frame. If it is drawn, it is inventoried, and
> an exclusion is recorded with its reason rather than made in silence.
>
> ## A check that cannot run is not a check that passed
>
> The mock's own delivery note already carries a list of what was specified rather than measured —
> motion, type fidelity and the three accessibility media queries, none of which the available
> capture engine can execute. The SwiftUI side will have its own such list, and it must be
> reported rather than absorbed.
>
> Give the conversion gate three exit states rather than two:
>
> | | |
> |---|---|
> | `0` | clean and complete — no findings, and every layer ran |
> | `1` | findings — at least one difference |
> | `3` | **inconclusive** — a layer the verdict depended on could not run |
>
> An inconclusive layer gets a ledger row naming what it covers and where it was confirmed
> instead. Marking a surface done with a silenced layer unrecorded files an unasked question as
> an answer, which is the same failure as dropping a frame, one level down.
>
> Where a tool fails, quote what it said. The failure strings name the engine and the value that
> came back, and a paraphrase is how "this layer cannot run here" becomes "the shadows match".
>
> ## Acceptance
>
> - `MockTokenParser` exists and its three assertions pass, including the colour-literal grep.
> - The measurement harness produces a structure-and-geometry dump for one surface, and that dump
>   is a nested tree with containment, axis and frames rather than a flat list.
> - One surface — Servers, since M16 makes it the hardest — has a filled breadth ledger whose
>   every cell names the two artifact values it compared.
> - The gate returns 0, 1 or 3, and a run with a deliberately disabled layer returns 3 rather
>   than 0. A gate never observed failing is a gate nobody has written.

---

## 2 · What this item is, in one paragraph

M23 builds an instrument, not a board. Nothing that renders changes. What lands is: a parser for
the mock's two machine-readable token blocks, a classification register that says what every mock
token is against the shipped Swift palette, an in-process measurement harness that emits a nested
structure-and-geometry tree for a rendered SwiftUI surface, a filled breadth ledger for Servers,
and a gate with three exit states that reads all of it. M15–M22 consume the gate; they do not
re-derive it.

## 3 · What grounding found, and the two facts that shape the design

### 3.1 `DESIGN.md` and the mock describe different products, and that is M21's decision

`DESIGN.md` §1 specifies *Instrument Panel* — graphite ground, dark-authored, breaker column.
`design/mcp-router-console.html` builds *Patchbay* — light-first, signal path, jack lane. The
divergence is in the values, not only the prose: dark `--ground` is `#1E1E1E` in the document and
`#1C1C1E` in the mock; light `--accent` is `#0069CF` in the document and `#0088FF` in the mock;
the mock carries an `--accent-ink` family the document has no equivalent for. `M21-token-layer-and-design-md.md`
names this explicitly — *"This needs a decision rather than a merge"* — and the brief above says
**"Which document is authoritative is M21's open decision."**

The shipped Swift palette is locked to `DESIGN.md` by `DesignTokenParityTests`, which compares the
two name sets for **exact equality** in both directions. So adding the mock's tokens to
`ColorToken` or `MetricToken` today would fail the check that currently guards the shipped
palette, and re-pointing the palette at the mock is the substance of M21.

**Therefore assertions 1 and 2 assert classification, not merger** (assumption A1 below). Every
mock token must be *classified* against the Swift palette as either

- `matched` — a Swift token of the same name-mapping exists and its value is equal in every
  appearance context the mock authors, or
- `pending` — the values differ or no Swift token exists, and the row carries a **citation** to a
  file and line that predates this item.

A mock token that is neither is `unclassified`, and an unclassified token is a finding. That keeps
the check live — a *new* mock token, or a drift in a matched pair, goes red today — without doing
M21's work or weakening the `DESIGN.md` parity that is currently the palette's only guard.

### 3.2 Assertion 3 already exists and is stronger than a grep

`scripts/lint/no-raw-design-values.sh` already fails the build on a hex literal, a
component-constructed colour, a named SwiftUI colour, a shorthand system colour, a numeric font
size, a system text style, `Font.custom`, a geometry literal, a control-API bypass and a private
colour bridge — with the two binding files exempted **by explicit path**. It is already wired into
`make lint`. M23 does not write a second, weaker grep; the gate's `literals` layer runs that
script and reports its output, and the spec records the reuse (assumption A2).

### 3.3 The instrument's measured capability

Probed on this machine, 21 Aug 2026, against the toolchain the repo builds with:

| Probe | Result |
|---|---|
| `NSHostingView` + `layoutSubtreeIfNeeded()` in a headless process | lays out; `walk(NSView)` returns **one** view — SwiftUI renders no AppKit subtree |
| `GeometryReader` + `PreferenceKey` inside that host | returns real frames for every instrumented node (`left (142.0, 20.0, 100.0, 20.0)`, `stack (250.0, 14.0, 8.0, 32.0)`) |
| `Color.resolve(in:)` with `EnvironmentValues.colorScheme` set | resolves a dynamic colour per appearance — dark `#FF4245FF`, light `#0088FFFF` |
| `String(describing: Font.system(size: 13, weight: .semibold))` | `Font(provider: SwiftUI.FontBox<SwiftUI.Font.SystemProvider>)` — **no size, no weight, no face** |

So the structure, geometry and resolved-colour layers genuinely run in-process, and **a `Font`
value cannot be read back**. That is the item's first real inconclusive layer, and it is recorded
as one rather than absorbed.

## 4 · The five layers as built

| Layer | Mock side | SwiftUI side | Rung |
|---|---|---|---|
| `tokens` | `<!-- mac-craft:metrics -->` rows + every `:root`-family custom property, six appearance contexts | `MetricToken` / `ColorToken`, via the classification register | parsed value vs parsed value |
| `literals` | the mock's own `literals_outside=0` claim | `scripts/lint/no-raw-design-values.sh` | executed lint, exit code + output |
| `structure` | parsed DOM: tag, role, text, ordered children | the harness's nested node tree — parent chain, ordered children, stack axis | recorded at render time in the running view |
| `geometry` | element box | the harness's `GeometryReader` frame in the surface coordinate space | measured after a real layout pass |
| `copy` | the mock's text nodes | the `*Copy` enums | string equality against a named enum case |
| `font` | `getComputedStyle().font` | **cannot be read** — a `Font` is opaque | **inconclusive**, ledgered |
| `pixels` | screenshot | — | supplementary only; never evidence, and not a layer of the gate |

## 5 · The gate

`scripts/acceptance/mock-fidelity-gate.sh <surface>` reads
`planning/fidelity/<surface>.layers.json` — one entry per layer, each `required` true or false, a
`required: false` entry carrying a `substitute` citation — runs a **capability preflight** per
layer before reading any result, then:

| Exit | Meaning |
|---|---|
| `0` | every required layer ran and produced no finding, and the breadth ledger has no `divergent`, `absent` or unclassified row |
| `1` | at least one finding — a token drift, an unclassified token, a lint violation, a `divergent`/`absent`/unclassified breadth row |
| `3` | a required layer's preflight says it could not run, or a layer errored — the tool's own words are quoted, never paraphrased |

`0` stays reachable because `font` is `required: false` with a substitute citation that the gate
prints on **every** run, so the substitution is visible rather than forgotten. A surface whose
verdict actually depends on the font layer flips `required` to true and gets `3`, which is the
brief's clause read literally: *a layer the verdict depended on could not run*.

`scripts/acceptance/mock-fidelity-selftest.sh` drives all three exits against scratch copies —
clean → `0`, injected token drift → `1`, disabled required layer → `3` — and fails if any of the
three does not come back. It is hermetic and joins `make all`; the gate itself does not, because
it needs the `MEASURE` build, which is the same reason `mutation` and `acceptance` are out.

## 6 · Assumptions

Each states what it beat, so a later reader can reverse it deliberately.

- **A1 — the token assertions classify rather than merge.** Every mock token is `matched`,
  `pending` with a pre-existing citation, or a finding. *Rather than* extending `ColorToken` and
  `MetricToken` to the mock's values now, which is the substance of M21 and would fail
  `DesignTokenParityTests`' exact name-set equality against `DESIGN.md`.
- **A2 — assertion 3 reuses `scripts/lint/no-raw-design-values.sh`.** *Rather than* a second grep
  inside the Swift suite, which would be weaker than the script, would duplicate its exemption
  list, and would drift from it.
- **A3 — the harness is driven by a small executable target, not by launching the app.** A
  `MeasureDump` executable hosts one surface in an `NSHostingView`, forces a layout pass and
  writes the JSON. *Rather than* instrumenting the shipping app and reading a dump off a running
  instance, which cannot run unattended and collides with `UI_VERIFICATION.md` rule 1.
- **A4 — `MEASURE` is a compile-time define switched by `MCP_ROUTER_MEASURE=1` at package-load
  time.** With it off, `.measured(…)` is an identity modifier and the harness compiles to
  nothing. *Rather than* a runtime flag, which would leave the recorder linked into the shipped
  app.
- **A5 — the breadth ledger is a committed TSV the gate reads, with a Markdown reading beside
  it.** *Rather than* prose only, which no gate can count.
- **A6 — the Servers ledger is filled against the mock's `v-ideal` state.** The other three drawn
  states (`v-empty`, `v-loading`, `v-error`) are inventoried as rows with an explicit
  `not-yet-audited` status and a reason, so they are visibly owed rather than silently dropped.
  *Rather than* filling four states at a shallower depth, which would make the worked example a
  weaker demonstration of the method than the method requires.
- **A7 — the `font` layer ships `required: false` with a substitute citation.** *Rather than*
  `required: true`, which would make every gate run return `3` and make `0` unreachable, which is
  a two-state gate wearing a three-state gate's clothes.

## 7 · Out of scope

Converting any board. Re-authoring `DESIGN.md`. Extending `ColorToken` / `MetricToken` to the
mock. Filling the ledger for a second surface. The 40 × 12 × 9 surface inventory (M17 / M18 / M20
own their own frames; M23 owns the row shape they fill).

## 8 · Review record

`codex exec -m gpt-5.6-sol -c model_reasoning_effort=high -s read-only`, adversarially briefed —
told to refute, and told that finding nothing is a failed review. Verbatim in
`planning/evidence/M23-review-codex.md`; verdict REJECT, 8 findings.

`ORCHESTRATOR.md` records this lane as down until 2026-08-20 and it is back, so this is a genuine
out-of-family gate rather than the logged in-family downgrade that note anticipated. The `-o` file
came back non-empty with a substantive review, which is the only honest tell — `codex exec` exits 0
on a usage limit. A second lane, `grok-4.6` at xhigh, was started in parallel and produced no report
before this was written; it is recorded as a lane that did not land, not as a lane that passed.

Two findings were accepted and fixed, one was partly accepted, one partly closed, three were
refuted by running the mutation the reviewer predicted would pass, and one is a recorded
disagreement. `planning/evidence/M23-acceptance.md` §5 carries the disposition of each, and §4
carries the mutation that settled it.

The two that were real:

- **The reused lint was described as more complete than it is.** Measured on 21 Aug 2026:
  `Color(white:)`, `Color(hue:saturation:brightness:)` and `Color(.displayP3, red:green:blue:)` all
  passed `scripts/lint/no-raw-design-values.sh` clean while §3.2 above claimed component-constructed
  colours were caught. The rule now covers every `Color` initializer that takes raw components or a
  foreign colour value, and all seven spellings are armed against the real script in the selftest,
  with a clean-tree control so a lint that is red whatever you feed it cannot pass them all.
- **The selftest armed outcomes rather than layers.** One route to 1 and one to 3 left `structure`,
  `geometry`, `type-metrics` and both directions of `breadth` free to be constant-green. Five
  mutations were added; 21 cases, from 8.

One finding pointed at something real one level up from where it aimed: `MeasureDump` defaulted an
unreadable `--surface` or `--state` back to the first case, so `--state loadng` wrote the ideal
frame into `servers.loadng.json` and exited 0. It now refuses and exits 3, and the gate asserts that
refusal on every run rather than trusting it.

**A7 stands, and here is what was argued against it.** The reviewer's position is that an authored
fidelity layer which cannot run must force exit 3 whatever else is true. Taken literally that makes
0 unreachable for every surface for as long as `Font` stays opaque, which is a two-state gate
wearing a three-state gate's clothes — the failure A7 was written to avoid. What the argument did
change is the shape of the answer: the measurable half of the font question is now its own required
layer, `type-metrics`, and it arms the exact residue the reviewer named. A text node rendering at
the wrong size for the role it declares is a finding today. What remains genuinely unread is weight
and face, and that is what the substitute citation prints on every run.
