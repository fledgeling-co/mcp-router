# plan-M19 — the in-app GitHub-flavoured Markdown viewer

Spec: `planning/specs/spec-M19.md` · brief `planning/features-to-triage/M19-gfm-viewer.md`
Design of record: `design/mcp-router-console.html`, the `sh-readme` sheet at `:3953-4079`
Plan size: **Large**. A new `MCPRouterKit/Markdown/` module (a block parser, an inline sanitiser,
a shield parser and a package-scoped image resolver), a new `MCPRouterUI/Document/` directory with
one view per block kind, a new fidelity surface with its manifest and pairing file, a new
`Surface` case in `MeasureDump`, and one new capability in the fidelity engine. Twenty-one
requirements across five layers.

Baseline, measured on this worktree at `87e16dc` rather than quoted: `swift build` exit 0;
`make test` **1725 tests in 215 suites passed**, exit 0; `python3 planning/reader-accounting.py`
accounted — 3 record, 16 declare, 1 recorded gap.

---

## 1 · Task

Render a capability's documentation inside the app, so deciding whether to install or update one
does not mean leaving for a browser. The mock draws it as a wide sheet: a titlebar with the
capability's name, its version and three tabs; a product header carrying the mark, name, verified
publisher, pitch and the install action; a five-cell facts strip; then the document itself,
scrolling inside a capped body.

The renderer is the substance. `AttributedString(markdown:)` handles the inline runs — emphasis,
code spans, links — and renders neither tables nor fenced code blocks, both of which appear in
every README this app will show. So a block parser produces an array of typed blocks, each drawn
by its own small view, with the system parser used only inside a paragraph.

Three constraints shape it, and all three are the brief's own: **a README is untrusted input**
arriving from a marketplace into an app that rewrites other tools' configuration, so nothing in it
may run, load or reach the network; **shields are re-drawn rather than fetched**, because
requesting `img.shields.io/badge/checks-12%20of%2012-green` tells a third party which capability
is being read; and **images resolve from inside the downloaded package**, never from wherever the
document points.

## 2 · Approach

Four layers, in dependency order.

**`MCPRouterKit/Markdown/`** gains the whole of the parsing and the whole of the security
boundary, because `SWIFT_PRACTICES.md` §8 keeps the kit free of UI frameworks and the parser is
the part with something to prove. A block parser walks lines and emits `MarkdownBlock`; an inline
builder hands a run to `AttributedString(markdown:)` and then **strips every attribute the view
did not ask for**, keeping presentation intents and links whose scheme is `https` and nothing
else; a shield parser turns a shields.io URL into a key, a value and a tone; and a resolver maps
an image reference to bytes already inside a declared package root, refusing anything with a
scheme and anything that escapes the root.

**`MCPRouterKit/Control/`** gains `CapabilityDocument` — three tabs' worth of parsed blocks, an
identity, five facts and the resolved images — and the source protocol that produces one. The
fixture implementation reads a real README, CHANGELOG and CAPABILITIES from the bundle and
resolves the image beside them, which is what makes the "resolved from inside the package" path
exercised rather than described.

**`MCPRouterUI/Document/`** gains the sheet and one view per block. Every dimension is derived
from `MetricToken` in a single `DocumentMetrics` enum, following `SettingsMetrics` and
`DiscoverBoardMetrics` exactly, and the directory joins `no-raw-design-values.sh`'s geometry list
in the same commit — M15's Settings window is the precedent, and the reason it is stated there is
that a directory nobody listed is invisible to the guard that fires for a listed directory that is
missing.

**The measurement layer** gains `Surface.readme` in `MeasureDump`, `planning/fidelity/readme.layers.json`,
`planning/fidelity/readme.pairing.tsv`, and one new capability in the engine (§6).

**The analogue to follow is `DiscoverDetailSheet.swift`.** It already solves this sheet's hard
parts against attacker-controlled strings: every string sanitised before it is drawn, a `Link`
only where the URL is one this app is willing to open, an action bar with cancel leading and one
prominent action trailing, and a scroll over a fixed-width sheet. This item does not re-derive
that shape; it renders a document inside it.

## 3 · Requirements & Decisions

### 3.1 Functional — the renderer

1. Every block kind the mock draws parses to its own typed block: `h1`–`h3`, paragraph, fenced
   code, blockquote, ordered list, unordered list, table with a header row, horizontal rule,
   image, and a shield row. *(brief, "What the renderer has to handle")*
2. Inline emphasis, strong, code spans and links inside a paragraph come from
   `AttributedString(markdown:)`. *(brief §Converting this to SwiftUI; spec §3.6 settles the
   library question and forbids re-opening it)*
3. A construct outside that list renders as **plain text**, visibly, rather than being dropped.
   *(spec §2 assumption 1 — a block falling back to raw text is visible; a block dropped is not)*
4. A shield is parsed from its badge URL into a key, a value and a tone, and drawn natively.
   *(brief)*
5. The fixture document contains every block kind in the mock and **no block falls back to raw
   text**. *(brief's acceptance line)*

### 3.2 Functional — the untrusted-input boundary

6. Nothing rendered here performs a network request. No remote image is fetched, no shield image
   is fetched, and no link is followed without a press. *(spec §2 assumption 5)*
7. An image resolves only from inside the declared package root. A reference carrying any scheme,
   an absolute path, or a `..` that escapes the root is **refused with a placeholder**, never
   fetched. *(spec §2 assumption 6)*
8. Embedded markup is never obeyed. HTML in the source reaches the screen as text or not at all.
   *(spec §2 assumption 7)*
9. A link survives only when its scheme is `https`. Every other attribute
   `AttributedString(markdown:)` can attach — `imageURL` included — is stripped before the run
   reaches a view. *(§3.1 req 2's consequence; `DiscoverDetailSheet`'s repository rule, one level
   in)*
10. Parsing is bounded: a document, a block, a table and a line each have a cap, so a hostile
    document cannot make the sheet unusable. *(`DiscoverDetailSheet`'s `cap: 4000` precedent —
    "capped only against a denial of the sheet")*

### 3.3 UI/UX

11. Three tabs over one panel — Read me, Changelog, Capabilities — not one scroll.
    *(spec §2 assumption 3)*
12. The product header and the five-cell facts strip ship with this item, above the body, and do
    not scroll away under a long document. *(spec §2 assumption 2; the mock's own comment at
    `:1160-1162` gives the reason)*
13. Long documents scroll inside a **capped** body rather than growing the sheet past its window.
    *(brief)*
14. A shield's value cell takes `ColorToken.shieldGood` where the badge's colour is green-family
    and `ColorToken.accentInk` otherwise — the app's own text-safe fills, never the badge's own
    colour. *(brief; `DESIGN.md` §2's `--shield-good` row)*
15. Every dimension is read from `MetricToken` or derived from it in `DocumentMetrics`; every
    colour from `ColorToken`; every text size off the eight-role ladder.
    *(`SWIFT_PRACTICES.md` §5)*
16. Sentence case throughout; no case transform. *(`DESIGN.md` §3.2)*

### 3.4 The states

17. The panel ships its designed states, not only the populated one: a tab whose document is
    present; a tab whose document the capability did not publish; and a document source that
    could not answer. Real copy for each. *(`DESIGN.md` §5; `SWIFT_PRACTICES.md` §4)*

### 3.5 Measurement

18. `planning/fidelity/readme.layers.json`, `planning/fidelity/readme.pairing.tsv` and
    `Surface.readme` in `app/Sources/MeasureDump/main.swift` exist, and
    `scripts/acceptance/mock-fidelity-gate.sh readme` runs all eight layers to a verdict.
    *(spec §3.7)*
19. The shield-colour assertion is a `tokens`-layer claim over `ColorToken.shieldGood`, which
    `M21` merged at `e121801` and which `ColorToken.swift:99` now carries — so the one acceptance
    line the spec parked on M21 is **writable in this item** rather than deferred. *(spec §2's
    eighth assumption, now discharged by measurement)*

### 3.6 Constraints and decisions

20. **The document source is a protocol with no live implementation, and that is stated rather
    than papered over.** Measured this session: the control API serves `/servers`, `/usage` and
    `/registry` (`src/control.ts:279-283`) and nothing else; no wire type — `RegistryEntry`,
    `Skill`, `PluginOrigin` — carries a README, a changelog, a licence or a capability table. So
    there is **nothing the router observes** for this panel to render, and `DESIGN.md` §6 forbids
    displaying what it does not. The viewer therefore ships against
    `CapabilityDocumentSource`, whose only implementation today is the fixture one; the sheet is
    rendered by `MeasureDump` and by the Debug gallery, and **no entry point is added to the
    shipped app**.
21. **No entry point, deliberately.** `spec-M19.md`'s header names M18 as the owner of "the panel
    this renders inside", and M18 is To Do. A `Read me…` button wired now would open a panel that
    says "no document" for every capability in a Release build — advertising a capability the
    router cannot supply, which is the honesty rule broken outward. The fork was referred out of
    family (`agy` / `gemini-3.7-flash-high`, 2026-08-22, recorded at
    `planning/evidence/M19-review-agy.md`): it took the same option, rejected the wiring for the
    same reason, rejected the endpoint as "a multi-layer backend feature" outside the triaged
    brief, and added the refinement this plan takes — name the contract in a protocol whose
    production arm returns an unavailable state, and **file the endpoint as its own item**. The
    `grok-4.6` lane was attempted first and refused with `402 Payment Required`; `codex` is
    recorded down to 2026-08-27.
22. **The endpoint becomes a brief, not a TODO.** `planning/features-to-triage/M30-capability-document-source.md`
    is written in this item so the gap has an owner rather than a sentence in a plan.

## 4 · Steps

### 1. The block model and the parser

- **Files:** `app/Sources/MCPRouterKit/Markdown/MarkdownBlock.swift` (create),
  `app/Sources/MCPRouterKit/Markdown/MarkdownParser.swift` (create)
- **Details:** `MarkdownBlock` is a `Sendable` enum with one case per kind in req 1 plus
  `.plainText(String)` for req 3. `MarkdownParser.blocks(from:limits:)` walks lines: fence,
  ATX heading (1–3 hashes; four or more is `.plainText`), blockquote (recursing on its own
  content), thematic break, GFM table (a header row followed by a delimiter row), ordered and
  unordered list, an images-only paragraph (→ `.shields` when every image is a shield, else one
  `.image` each), otherwise a paragraph run to the next blank line.
- **Reference:** no analogue in this repo — spec §3.2 records that there is no Markdown rendering
  of any kind in `app/Sources`. The shape is the brief's, and `SkillChecks.swift`'s pure-value,
  heavily-tested style is the one to write in.
- **Verify:** unit tests per kind, plus the boundary cases — a fence never closed, a table whose
  rows are ragged, a list item with no space after the marker, four hashes, a blockquote holding
  a list.

### 2. The inline builder and its sanitiser

- **File:** `app/Sources/MCPRouterKit/Markdown/MarkdownInline.swift` (create)
- **Details:** wraps `AttributedString(markdown:options:)` at
  `interpretedSyntax: .inlineOnlyPreservingWhitespace`, in a `do`/`catch` whose catch renders the
  literal source with no attributes — handled, not `try?`-and-defaulted. Then the sanitiser
  rebuilds the string keeping `inlinePresentationIntent` and a `link` whose scheme is `https`,
  and dropping every other attribute including `imageURL`. What cmark does with an inline `<span>`
  is **pinned by a test rather than assumed**, so a toolchain change that starts interpreting it
  goes red here.
- **Verify:** `[x](javascript:alert(1))` carries no link; `[x](https://example.com)` does;
  `![x](https://evil/pixel.png)` leaves no `imageURL`; a malformed run renders its own source.

### 3. The shield parser

- **File:** `app/Sources/MCPRouterKit/Markdown/Shield.swift` (create)
- **Details:** `Shield.parse(_ url: String)` accepts `img.shields.io` and `shields.io`, path
  `/badge/<label>-<message>-<colour>`, with shields.io's own escaping (`--` → `-`, `__` → `_`,
  `_` → space) and percent-decoding, and ignores the query entirely — `?style=`, `&logo=` and a
  `&link=` are all discarded, which is also what stops a query parameter smuggling a second URL.
  The colour maps to a **tone**, never to a colour: green-family (`brightgreen`, `green`,
  `success`, and the hexes shields.io publishes for them) → `.good`; everything else →
  `.neutral`. The badge's own colour value is not carried on the type at all, which is the
  structural form of "the shield colours are the token values rather than the badge's own".
- **Verify:** the mock's four badges round-trip; a non-shields host does not parse; a badge with
  an escaped hyphen in its label decodes; the parsed value has no field a colour could occupy.

### 4. The package image resolver

- **File:** `app/Sources/MCPRouterKit/Markdown/PackageImageResolver.swift` (create)
- **Details:** `resolve(_ reference: String, inPackageAt root: URL) -> Result<URL, Refusal>`.
  Refuses: any reference `URL(string:)` reads a scheme from; any absolute path; any reference
  whose standardised path is not a descendant of the standardised root. The **root is
  standardised before the comparison and the comparison is on path components**, not on a string
  prefix — `/pkg-evil` is not inside `/pkg`.
- **Verify:** `docs/x.png` resolves; `../../etc/passwd`, `/etc/passwd`, `https://…`, `data:…`,
  `file:///…` and `docs/../../x` are each refused with their own reason.

### 5. The document, its source, and the fixture

- **Files:** `app/Sources/MCPRouterKit/Markdown/CapabilityDocument.swift` (create),
  `app/Sources/MCPRouterKit/Markdown/CapabilityDocumentSource.swift` (create),
  `app/Sources/MCPRouterKit/Markdown/CapabilityDocumentFixture.swift` (create),
  `app/Sources/MCPRouterKit/Control/Authored/capability-documents/trawl/{README,CHANGELOG,CAPABILITIES}.md`
  and `.../docs/matches.png` (create)
- **Details:** `CapabilityDocument` carries the identity the header draws, the five facts, the
  three tabs' blocks and `images: [String: Data]` — **already resolved**, so the view performs no
  IO and `no-raw-design-values.sh`'s A36 rule stays true of the new directory. `Control/Authored`
  is already a `.copy` resource in `Package.swift`, so the fixture files need no manifest change.
  The fixture reader is the only thing that touches the filesystem, it lives in the kit beside
  `FixtureControlAPIClient`'s own `Bundle.module` loader, and it carries `SkillFixtures`' standing
  sentence: a Release build never reaches it.
- **Reference:** `FixtureControlAPIClient.swift:81-89` for the bundle lookup; `SkillFixtures.swift:1-11`
  for how invented fixture data is labelled as such.
- **Verify:** the fixture parses to zero `.plainText` blocks (req 5); its image resolves; a second
  fixture that references outside the package draws the placeholder.

### 6. `DocumentMetrics` and the block views

- **Files:** `app/Sources/MCPRouterUI/Document/DocumentMetrics.swift`,
  `MarkdownBlockView.swift`, `MarkdownTableView.swift`, `ShieldView.swift`,
  `CapabilityDocumentSheet.swift`, `CapabilityDocumentHeader.swift` (all create)
- **Details:** `DocumentMetrics` derives every value from `MetricToken` — the shield is
  `controlSmall` tall at `selectionInset` radius, the code fence sits on `--sunken` at
  `selectionRadius`, the table hairline is `focusRing / 2`, the sheet is `sidebar * 3` wide and
  its body caps at `sidebar * 2`. Two of those disagree with the mock and are declared in the
  layers manifest rather than derived toward: the mock's wide sheet is `min(820px, 94%)` and its
  body caps at `56vh`, neither of which is a token in `DESIGN.md` §2.
  Type: `h1`→`Title1`, `h2`→`Title2`, `h3`→`Title3`, body→`Body`, code span→`Callout` monospaced,
  fence→`Subheadline` monospaced, table→`Callout`, shield→`Subheadline`. The mock's 19pt body
  leading is off `DESIGN.md`'s ladder and the ladder wins (`SWIFT_PRACTICES.md` §5); declared.
- **Verify:** `./scripts/lint/no-raw-design-values.sh` clean with `Document/` added to
  `GEOMETRY_DIRS`, and the count it prints for the geometry rules goes **up** — which is what
  proves the directory was scanned rather than merely named.

### 7. The sheet, its tabs and its states

- **File:** `app/Sources/MCPRouterUI/Document/CapabilityDocumentSheet.swift`
- **Details:** titlebar (name, version pill, three tabs), header, facts strip, scrolling body,
  foot with cancel leading and one prominent action trailing. Tab selection is `@State` on the
  sheet. States per req 17: a tab with blocks; a tab the capability did not publish, with copy
  that says which document is missing and that the others are still there; and a source that
  could not answer, with `ControlAPIError`-shaped copy. `Esc` dismisses (`DESIGN.md` §8).
- **Reference:** `DiscoverDetailSheet.swift` for the scroll-over-fixed-width-plus-action-bar
  shape; `SettingsWindow.swift:74-81` for the `onExitCommand` precedent and why it is needed.
- **Verify:** the three states construct; the tab switch changes the rendered block count.

### 8. The measurement surface

- **Files:** `app/Sources/MeasureDump/main.swift` (modify),
  `planning/fidelity/readme.layers.json` (create), `planning/fidelity/readme.pairing.tsv` (create),
  `scripts/acceptance/mock_fidelity.py` (modify), `scripts/acceptance/mock-affordances.py` (modify)
- **Details:** `Surface.readme` renders `CapabilityDocumentSheet` over the fixture document.
  The engine change is one capability and it is needed because **this surface has no `.v-*`
  frame**: `mock_fidelity.py:1072` passes `f"v-{state}"` to the affordance census, every board and
  the Settings window carry `.v-ideal` / `.v-empty` blocks, and `#sh-readme` carries none — so
  without it the census exits 3 at "`#sh-readme` has no `.v-ideal` block" and the surface cannot
  be measured at all. The manifest gains an optional `stateFrames` map whose value may be `#id`
  or a bare class, defaulting to `v-<state>`; `mock-affordances.py` matches an `#id` selector as
  well as a class, and prefixes affordance ids with the selector minus its `#`. Existing
  manifests carry no `stateFrames`, so `servers`, `settings` and the selftest's `v-ideal` fixture
  are byte-identical in behaviour.
- **Verify:** `make mock-fidelity-selftest` still green (it reaches all three exits and its
  fixture uses the default); `./scripts/acceptance/mock-fidelity-gate.sh readme` reaches a verdict
  with every required layer having run.

### 9. Tests

- **Files:** `app/Tests/MCPRouterKitTests/MarkdownParserTests.swift`,
  `MarkdownInlineTests.swift`, `MarkdownSecurityTests.swift`, `ShieldTests.swift`,
  `CapabilityDocumentFixtureTests.swift` (create);
  `app/Tests/MCPRouterUITests/CapabilityDocumentSheetTests.swift` (create)
- **Details:** per-step verification above, plus the two that are this item's real subject.
  **`everyBlockKindInTheMockIsCovered`** enumerates the mock's own `sh-readme` block kinds and
  asserts the fixture parses one of each with zero `.plainText` — the brief's acceptance line as
  an assertion. **`shieldsTakeTheAppsOwnFills`** asserts every drawn shield fill is
  `ColorToken.shieldGood` or `ColorToken.accentInk` and that `Shield` has no member a badge colour
  could be read from.
- **Red-green:** `SWIFT_PRACTICES.md` §7 — each drift guard is watched failing and restored, and
  the arms are recorded in `planning/evidence/M19-acceptance.md`.

### 10. The record

- **Files:** `planning/specs/spec-M19.md` (status), `ORCHESTRATOR.md` (row),
  `planning/progress/M19.md`, `planning/evidence/M19-acceptance.md`,
  `planning/features-to-triage/M30-capability-document-source.md`, `DESIGN.md` (§10 if a new gap
  is owed)

## 5 · Audit coverage

This change adds no path that mutates tenant data, sends anything to a human, produces AI output,
or reads a sensitive record. It reads three Markdown files out of the app's own resource bundle
and renders them; it writes nothing, and it opens no socket. Stated rather than dropped, because
an absent section reads as forgotten.

## 6 · Acceptance criteria

- [ ] A fixture README containing every block kind the mock draws parses with **zero** blocks
      falling back to plain text, asserted against a kind list derived from the mock itself.
- [ ] Every shield in the fixture draws with `ColorToken.shieldGood` or `ColorToken.accentInk`,
      and `Shield` carries no field the badge's own colour could occupy.
- [ ] `PackageImageResolver` refuses a scheme, an absolute path and a `..` escape, each with its
      own reason, and resolves a relative reference inside the root.
- [ ] A `javascript:` link is stripped from an inline run and an `https:` link survives.
- [ ] The three tabs render independently and the panel's body scrolls inside a cap rather than
      growing the sheet.
- [ ] `./scripts/acceptance/mock-fidelity-gate.sh readme` reaches a verdict with all eight layers
      run and the ledger written to `planning/fidelity/readme.ledger.md`.
- [ ] `make lint` exit 0 with `MCPRouterUI/Document` inside the geometry rules and the printed
      file count higher than the baseline.
- [ ] `make test` green with the suite count **above** 1725, and every drift guard in this item
      recorded as watched failing.

## 7 · Falsifiability at the base commit

Each acceptance criterion above fails at `87e16dc`, and the reason is the same for all of them:
`grep -rn 'AttributedString(markdown\|import Markdown\|MarkdownUI' app/Sources` returns nothing,
`ColorToken.shieldGood` has no call site, `planning/fidelity/readme.layers.json` does not exist,
and `./scripts/acceptance/mock-fidelity-gate.sh readme` exits 3 at the missing manifest. Confirmed
by running the last of those before starting.

## 8 · Out of scope

- **Collapsible `<details>` blocks and side-by-side diffs**, which `PRD.md` §7.2 names. The mock
  draws neither in `sh-readme`, and spec §2's first assumption is that the kinds in scope are the
  ones the mock draws. A document containing one renders it as plain text, visibly.
- **The entry point.** M18 owns the sheet inventory and the panel this renders inside.
- **A live document source.** No control-API route serves one; filed as
  `planning/features-to-triage/M30-capability-document-source.md`.
- **Syntax highlighting inside a fence.** The mock draws a monospace ground and no colour.
- **The iPhone.** `PRD.md` §7.2 names both platforms; the mock draws this surface on the Mac only
  and `spec-M19.md`'s category is `mac`.
