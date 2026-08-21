# spec-M21 — the token layer, the split accent, and reconciling `DESIGN.md`

| | |
|---|---|
| ID | M21 |
| Status | Needs More Info |
| Category | mac · design authority · foundation |
| Depends on | F2 ✓ · M23 ✓ |
| Blocked by | one essential question in §2 — the same fork M16 carries, asked here in its general form |
| Blocks in practice | nothing hard. Six of the eight items in this programme proceed under a recorded assumption; M16 is the one that cannot |
| Brief | `planning/features-to-triage/M21-token-layer-and-design-md.md` |
| Triage | 2026-08-22 · §2 is owner-facing · §3 is the pipeline record |

---

## 1 · Feature description (the brief, verbatim)

> # M21 — the token layer, the split accent, and reconciling `DESIGN.md`
>
> **Depends on:** F2 (the design system in SwiftUI).
> **Source:** `design/mcp-router-console.html`, PRD §9.1 and §9.9.
>
> Two things to settle: a colour system that clears the contrast floor without abandoning the
> platform's own hues, and a `DESIGN.md` that now describes a direction the mock does not build.
>
> ## `DESIGN.md` and the PRD disagree
>
> `DESIGN.md` specifies *Instrument Panel* — Terminal Dark with a Breaker Column signature. The
> mock builds *Patchbay* — light-first, with the Signal Path (M16). Both documents are in the
> repo and an implementer reading `DESIGN.md` alone will build the wrong thing.
>
> This needs a decision rather than a merge: either `DESIGN.md` is re-authored against the mock,
> or the mock is treated as an exploration and discarded. It should not be left as it is. The
> mock was built under an explicit instruction to ignore the existing direction, so `DESIGN.md`
> being out of date is expected rather than an oversight — but it is still out of date.
>
> ## The accent has to be split, and the reason is measured
>
> Apple's published system Blue `#0088FF` measures **3.52:1** against white, below the 4.5:1
> floor for 13px text. Shipping it under a white label ships a known accessibility failure with
> the platform's name on it.
>
> The resolution is two tokens with different jobs:
>
> - `--accent` keeps the published hue, and carries rings, plugs, dots and tints — none of which
>   is text.
> - `--accent-ink` carries any accent surface with text on it: `#0071E3` light (**4.70:1**),
>   `#0A6FD6` dark (**4.93:1**).
>
> Every indicator hue needs the same twin, because the same problem appears at every status
> colour: `--live-ink`, `--attn-ink`, `--fail-ink`, each solved against all three grounds
> (`--ground`, `--chrome`, `--panel`), plus `--shield-good` and `--badge-bg` for the two filled
> badges that carry white.
>
> ## Six appearance contexts, not two
>
> Light, dark, an explicit light and dark override for the in-app appearance switch, and **two
> separate increased-contrast blocks**. The last is the one that gets missed: a single
> scheme-agnostic `prefers-contrast` block paints dark ink on a graphite ground in whichever of
> the two appearances it was not written for. Author increased contrast per appearance.
>
> ## The invariants worth gating in the Swift port
>
> - Every colour lives in a token. The mock carries 89 in its token block and **zero colour
>   literals outside it**; the equivalent in SwiftUI is that no `Color(hex:)` appears outside the
>   palette type.
> - Contrast is measured in all four appearance contexts, not one. Current measurement on the
>   mock: 5,788 pairs, 0 failures, 0 unresolved.
> - Disabled text is exempt under WCAG 1.4.3 incidental, and that exemption is claimed
>   explicitly rather than by the check quietly skipping those pairs.
> - Colour is never the only signal — every state that has a colour also has a word.
> - No `cursor: pointer` equivalent: on macOS the hand cursor over a control is the non-native
>   tell an experienced user names first.
>
> ## What is unmeasured
>
> Motion, type fidelity, and the three accessibility media queries are specifications in the
> mock rather than measurements. The capture engine available here runs no CSS animation, loads
> no web fonts, and accepts `Emulation.setEmulatedMedia` without applying it. Any claim about
> those needs a real browser or a built app.
>
> ## Converting this to SwiftUI
>
> The four appearance contexts map exactly onto what an Xcode asset catalogue already models: an
> Any/Light/Dark appearance axis crossed with a High Contrast variant gives light, dark,
> light+contrast and dark+contrast. Author the colour set with all four filled rather than
> letting two of them inherit, because the mock's two separate `prefers-contrast` blocks exist
> precisely because a shared one is wrong in one of the two.
>
> - `ColorToken` stays the only place a colour literal appears. The parity test asserts that by
>   grep, which is the analogue of the mock's `literals_outside=0` and the check that keeps the
>   system from becoming decorative.
> - The split accent becomes two cases, not one with a modifier: `accent` for rings, plugs and
>   tints, `accentInk` for any filled surface carrying text. A single token with call-site
>   judgement is how the 3.52:1 label ships.
> - `MetricToken` gains the mock's metric rows. The parser for them is simpler than the Markdown
>   table parser `DesignDocParser` already implements, because the block is `name value tier`.
> - Contrast is asserted in code across all four contexts, not spot-checked. The mock measures
>   5,788 pairs; the Swift side can measure every token pair that actually co-occurs, which is a
>   smaller and more useful set.
>
> Acceptance: the token parity test passes against the mock, the colour-literal grep returns
> nothing outside the palette, and a deliberately mismatched token makes the test fail — a parity
> test never observed failing is a test nobody has written (M23).

---

## 2 · Triage — 2026-08-22

**Sentinel review:** S1 — Block pending the one essential question below.

This item was filed as a decision. Its brief says so in its own words: *"This needs a decision rather
than a merge … It should not be left as it is."* Everything else in it — the split accent, the
per-appearance contrast work, the invariants worth gating — is settled, measured and buildable the
moment the decision lands.

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*

- **Where it shows up:** everywhere, but nothing moves *(customer-facing — every surface, no layout change)*; the design document at the root of the project *(behind the scenes — a document, not a screen)*. Nothing internal changes.
- **What users will see — per surface:**
  - Every surface: labels sitting on a coloured fill get a slightly darker version of that colour behind them, so the text clears the readable-contrast floor. Rings, dots, plugs and tints keep the brighter published colour. Nothing changes position or size.
  - Every surface, in increased-contrast mode: colours that are currently authored once for both light and dark are authored separately, so neither ends up with dark ink on a dark ground.
- **Behaviour changes:** none visible. What changes is that a colour that fails the readable floor becomes a build failure rather than a thing somebody notices later.
- **Design reference:** whichever document the answer below names.

**Essential Questions**

1. *[Layout]* **Which document is the design authority for the Mac app?**

   Two are in the repository and they describe different products.

   - The design document at the root specifies a graphite, dark-authored direction whose signature is
     the row of levers on Servers, and it names an interactive prototype as its reference
     implementation. The project's own orchestration file repeats that. Your recorded decision on
     2026-08-20, closing two findings, was *"`design/mocks/prototype.html` remains the design of
     record for the Mac console"*, and the test campaign's own configuration names that file.
   - The product requirements say the opposite in §9.1: the newer console mock *"supersedes the
     Instrument Panel direction"* and *"until it is re-authored, the mock and this section are the
     authority and `DESIGN.md` is historical. Resolving that is tracked as M21."* The console mock
     was built deliberately ignoring both the design document and the prototype, and all eight briefs
     in this programme are drawn from it.

   The two records do not actually contradict each other on their face — **neither names the other
   artifact at all.** Your decision was taken about the prototype versus two superseded contact
   sheets; the requirements' claim was written about the console mock. Nothing joins them up, and a
   runner reading either one alone builds a different app.

   a) The console mock is the authority. Re-author the design document against it: light-first,
      the split accent, the six appearance contexts, the signal path as the signature. The eight
      briefs stand as written, and roughly two thirds of the colour system is re-keyed.
   b) The prototype and the design document stay the authority, and the console mock is an
      exploration. *(reversible — nothing built is discarded, and (a) stays available afterwards)*
      This item shrinks to the contrast fixes the design document already records as owed, M16 closes
      with no work, and the other six items re-key to the prototype, losing the surfaces the
      prototype does not draw.
   c) Split it: the console mock is the authority for surfaces the prototype does not draw at all
      (the Harnesses and Insights boards, the Settings window, the capability panel), and the
      prototype stays the authority for the boards that already ship. This keeps every item in the
      programme alive and accepts two visual vocabularies in one app for as long as it takes to
      converge.

   My lean is (a), because it is what the requirements say, what the mock was commissioned for and
   what every brief in this programme assumes — but I am naming (b) as the reversible one because it
   is the only answer consistent with the decision you actually recorded, and because it discards
   nothing that has been built. What (a) is better at is coherence: the two documents stop
   disagreeing, and 64 measured token rows stop being pending. What (c) is better at is not stalling
   six buildable items on a document question. Which of those matters more is yours.

*Easy reply — edit your answer under the question (or correct an assumption), then re-run `/triage M21`:*

> `1. <a | b | c>`

**Assumptions** *(these hold under answer (a), narrow under (c), and mostly void under (b))*

- `[Layout]` The accent is split into two named colours with different jobs, not one with a modifier applied at the point of use. *(a single colour plus judgement at each call site is exactly how a label at 3.52:1 ships)*
- `[Layout]` Every indicator colour gets the same twin, solved against all three backgrounds. *(the same failure appears at every status colour, not only the accent)*
- `[Layout]` Increased contrast is authored once per appearance rather than once for both. *(one shared block paints dark ink on a dark ground in whichever appearance it was not written for)*
- `[Experience]` Colour is never the only signal: every state that has a colour also has a word. *(already this app's rule)*
- `[Operations]` Contrast is asserted in code across every appearance the app authors, not spot-checked, and a deliberately mismatched value must be seen to fail. *(a parity test never observed failing is a test nobody has written)*
- `[Operations]` Text that is dimmed because it is unavailable is exempt from the floor, and the exemption is claimed out loud rather than by quietly skipping those pairs. *(a skipped check and a passed check are the same shade of green)*
- `[Compliance]` No colour value appears anywhere except in the one place colours are defined. *(already enforced by a build gate; this item extends it rather than writing a second, weaker one)*

*If any of these are wrong, edit it inline in this file and re-run `/triage M21` before the planner picks this up.*

---

## 3 · Grounding record — pipeline note, not owner-facing

Measured on the main checkout at `7b730ee`, 2026-08-22.

### 3.1 The fork, with every citation

| Source | Says |
|---|---|
| `DESIGN.md`:8 | *"The reference implementation is `design/mocks/prototype.html`."* |
| `DESIGN.md` §1 | *Instrument Panel*, graphite, breaker column as the signature |
| `ORCHESTRATOR.md`:18 | *"Design authority: `DESIGN.md` at the root. Reference implementation `design/mocks/prototype.html`."* |
| `ORCHESTRATOR.md`:411 | *"every item's mock is a deep link into the single interactive `design/mocks/prototype.html`, not a separate file"* |
| `planning/test-campaign/` DEF-016 closure | *"Closed 20 Aug 2026, on the owner's decision that `design/mocks/prototype.html` remains the design of record for the Mac console."* DEF-012 repeats it |
| `planning/test-campaign/campaign.json` | `designOfRecord` is `design/mocks/prototype.html` |
| `PRD.md` §9 preamble | *"derived from the interactive macOS mock at `design/mcp-router-console.html`, which is the authority on everything below"* |
| `PRD.md` §9.1 | *"This supersedes the Instrument Panel direction recorded in `DESIGN.md` … `DESIGN.md` is historical. Resolving that is tracked as M21."* |
| `PRD.md` §9.11 | *"`DESIGN.md` still describes the superseded direction … any implementer reading `DESIGN.md` alone will build the wrong thing."* |
| `design/mcp-router-console-spec.md`:3 | built *"deliberately ignoring the project's existing `DESIGN.md` and `design/mocks/prototype.html` per the brief"* |
| `ORCHESTRATOR.md`:47 | *"A surface built from `design/mcp-router-console.html` is converted under `M23`, not by eye"* — method, not authority |

The owner's recorded decision and the requirements' claim are about different artifacts and neither
names the other, which is why this reads clean in every check and is still a live fork. **This is the
only item in the repository that asks for the join.**

### 3.2 M23 has already measured the size of the answer

`planning/fidelity/token-register.json` holds **89 rows** and `planning/fidelity/servers.ledger.md`
reports the classification: **25 matched, 64 pending**. Every pending row carries a citation that
predates the audit. So under answer (a) this item's work is 64 rows; under (b) the register is
re-keyed and most of them stop existing.

M23 deliberately did not do this work. `planning/specs/spec-M23.md` §6 records it as assumption A1 —
the token assertions classify rather than merge, *"rather than extending `ColorToken` and
`MetricToken` to the mock's values now, which is the substance of M21 and would fail
`DesignTokenParityTests`' exact name-set equality against `DESIGN.md`"*.

### 3.3 What the built palette is

- `app/Sources/MCPRouterKit/Design/ColorToken.swift` — 18 cases, values as hex string literals in `hex`/`lightHex` switches plus separate opacity fractions. Kept out of an asset catalogue deliberately, per its own comment, because `DesignTokenParityTests` cannot read catalogue JSON.
- `TypeToken.swift` — 8 cases. `MetricToken.swift` — 14 cases.
- **No `*Ink` token of any kind exists.** `Assets.xcassets` contains zero colour sets, so there is no High Contrast variant anywhere — the mechanism the brief proposes (an Any/Light/Dark axis crossed with a High Contrast variant) is not merely unfilled, it is unbuilt.
- `DesignTokenParityTests.swift` asserts exact name-set equality against `DESIGN.md` **in both directions**. Adding `accentInk` today reddens it. That is the mechanical reason this item cannot be started under either answer without the answer.
- `scripts/lint/no-raw-design-values.sh` is the literal gate, exempting `ColorToken+SwiftUI.swift` and `TypeToken+SwiftUI.swift` by exact path, and it is already wired into `make lint` and re-used rather than re-implemented by M23's `literals` layer.

### 3.4 Two figures in the brief are stale, and one is a different number than it looks

- The brief and `PRD.md` §9.9 both say *"89 in its token block and zero colour literals outside it"*. Measured on the mock today: the `:root` block holds **45** custom properties, the file holds **59** distinct custom property names and **188** declarations across its appearance blocks. The **89** is real but is M23's parsed row count — metric rows plus colour rows across the contexts — not a `:root` count. `servers.layers.json` carries it as the `tokenRows` floor.
- The brief says *"5,788 pairs, 0 failures, 0 unresolved"*. M24's commit `6c513b0` reports the mock's own gate at **`contrast examined=6548 failures=0 unresolved=0 across 4 contexts`**. The figure moved when the mock did; the direction did not.
- The brief says six appearance contexts; the mock's own gate reports four. `spec-M23.md` §4 records the parser as reading six, and `MockTokenParser.swift`'s `Appearance` enum has six cases — `light, dark, lightOverride, darkOverride, lightContrast, darkContrast`. Take six.

### 3.5 What is measured on the campaign side, and the one deliberate exclusion

Nothing in the campaign measures the token claims. The one relevant statement is an exclusion with a
stated reason, from `ledger.md`:5 and `campaign.json`'s sample field: **"drop high-contrast (no
authored tokens)"**. That is the `n/a` for the brief's six-context claim, and its reason is the same
one the brief gives.

`DEF-042` is the already-docketed concrete instance of this same question — the design of record draws
a graded-evaluation feature the product deliberately does not have, on four boards — and it sits on
M28 awaiting the same owner. The two should probably be answered in one sitting.

### 3.6 Why this is a question and not an assumption

The three-part bar, taken in order. **No internal source yields a safe default:** two owner-authored
documents say opposite things and the repository's own reconciliation script cannot see it, because
both files are internally consistent. **Guessing wrong is expensive:** answer (a) re-keys 64 token
rows, re-authors the root design document and retires a built signature element; answer (b) discards
the source of all eight briefs in this programme. **It is genuinely yours:** it is a direction
decision about what the product looks like, which no amount of measurement settles.

Every out-of-family lane was down when this was written, so no second opinion was taken on the
question itself — see §3.7. That does not change the verdict: a lane cannot answer a taste question,
and this was routed to the owner on the bar above rather than for want of a reviewer.

### 3.7 Gate record

- Codebase grounding: `app/Sources/MCPRouterKit/Design`, `app/Tests/MCPRouterKitTests`, `scripts/lint/`, `planning/fidelity/`, `design/`, `DESIGN.md`, `PRD.md`, `ORCHESTRATOR.md`, `planning/test-campaign/`.
- Out-of-family spec review: see §3.8 for which lane answered.

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

- **Both lanes independently agreed this must block, and agreed it is one question rather than two.** One put it as *"blocking is vastly cheaper"* — a wrong assumption here costs discarded implementation and a red suite, where a block costs delay. The other reached the same verdict from different evidence, noting that `main` carries both commitments at once: the owner's docket calls the prototype the design of record while merged M23 keyed its only fidelity manifest to the console mock.
- **Accepted — the mechanical half of the block, verified.** `DesignTokenParityTests` asserts exact two-way name-set equality between `ColorToken` and `DESIGN.md` §2. Adding `accentInk`, `liveInk`, `attnInk`, `failInk` or `shieldGood` reddens it until `DESIGN.md` §2 carries a row for each — and writing those rows against the console mock's values **is** the contested act. So this item cannot take even its uncontroversial half, the split accent, without the answer. Recorded in §3.3 and it is why the whole item blocks rather than only its document half.
- **Accepted — option (c) was added because of the review.** Two other items in this programme, the capability panel and the two new boards, draw surfaces the prototype does not have at all. Under a flat answer (b) they lose their design source entirely. Splitting authority by surface keeps six items alive and was not in the first draft of this question.
- **Neither lane was asked to answer the question itself, and neither could have.** It is a direction decision. What they were asked was whether it is genuinely the owner's and whether blocking is right, and both said yes.
