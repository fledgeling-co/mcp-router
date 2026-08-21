# spec-M19 — the in-app GitHub-flavoured Markdown viewer

| | |
|---|---|
| ID | M19 |
| Status | To Do |
| Category | mac · mock conversion · untrusted input |
| Depends on | M4 ✓ · M23 ✓ · M18 (owns the panel this renders inside) · M21 (the badge colour, and only that) |
| Delivers | `PRD.md` §7.2 |
| Brief | `planning/features-to-triage/M19-gfm-viewer.md` |
| Source mock | `design/mcp-router-console.html`, the `readme` panel — the design-authority question is M21's, recorded in §3.1 |
| Triage | 2026-08-22 · §2 is owner-facing · §3 is the pipeline record |

---

## 1 · Feature description (the brief, verbatim)

> # M19 — the in-app GitHub-flavoured Markdown viewer
>
> **Depends on:** M4. **Delivers:** PRD §7.2.
> **Source:** `design/mcp-router-console.html`, sheet `readme`.
>
> Deciding whether to install or update a capability means reading its README and its changelog,
> and today that means leaving for a browser. The mock renders both in a sheet, tabbed **Read me
> / Changelog / Capabilities**, so the decision and the evidence sit on the same surface.
>
> ## What the renderer has to handle
>
> Drawn in the mock, so all of it is in scope: headings h1–h3, paragraphs, bold and inline code,
> fenced code blocks with a monospace ground, blockquotes with a leading rule, ordered and
> unordered lists, tables with a header row, horizontal rules, links, inline images, and
> **shields** — the small two-part badges (`marketplace | fledgeling`, `checks | 12 of 12`) that
> open almost every README in this ecosystem.
>
> Shields are worth naming because they are the one element that must be re-drawn rather than
> loaded. A real shields.io badge is a remote image; fetching one leaks which capability the user
> is reading to a third party. Parse the badge URL and render it natively, matching the shape.
>
> ## Constraints
>
> **A README is untrusted input.** It comes from a marketplace and it is being rendered inside an
> app that can write to harness configuration. Render it as data: no scripts, no remote loads, no
> HTML passthrough, and images resolved from the downloaded package rather than fetched from
> wherever the Markdown points.
>
> **A shield that carries white text needs a text-safe fill.** The published badge greens and
> blues fail the contrast floor at badge type size. The mock carries a separate `--shield-good`
> token for exactly this, measured 5.40:1 to 9.72:1 across the four appearance contexts.
>
> **Changelog and capability list are separate tabs, not a scroll.** The question "what changed"
> and the question "what does it do" are asked at different moments, and a capability delta
> (M18) is the third answer, reachable from the same sheet.
>
> **Long documents scroll inside the sheet body**, which is capped rather than growing the sheet
> past its window.
>
> ## Converting this to SwiftUI
>
> `AttributedString(markdown:)` handles inline emphasis, code spans and links, and it is the right
> tool for the parts it covers. It does not render tables or fenced code blocks, both of which
> appear in the mock and in every README this app will show, so a renderer is needed on top of it
> rather than instead of it.
>
> The workable shape is a block parser producing an array of typed blocks — heading, paragraph,
> code fence, table, list, rule, image, shield — each rendered by its own small `View`, with
> `AttributedString` used for the inline runs inside a paragraph. That keeps the inline handling
> on a system parser and puts the custom work only where it is unavoidable.
>
> - Shields are drawn natively from the parsed badge URL. Loading the remote image tells a third
>   party which capability the user is reading, and the mock's `--shield-good` token exists
>   because the published badge colours fail the contrast floor under white text.
> - Images resolve from the downloaded package, never from an arbitrary URL in the Markdown.
> - No HTML passthrough. A README is untrusted input arriving from a marketplace into an app that
>   can write harness configuration.
> - Read me, Changelog and Capabilities are three tabs over one sheet, not one long scroll.
>
> Acceptance: a fixture README containing every block kind in the mock renders with no block
> falling back to raw text, and the shield colours are the token values rather than the badge's
> own (M23).

---

## 2 · Triage — 2026-08-22

**Ready for Implementation Plan**

**Sentinel review:** S2 — Approve with assumptions. Governance-adjacent because the thing being
rendered arrives from a third party and the app that renders it can write to the configuration files
other tools read.

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*

- **Where it shows up:** the panel that opens when you are deciding whether to install or update a capability, reached from Discover, Skills and Inbox *(customer-facing — existing panel that gains its contents)*. Nothing else in the app changes, and nothing internal changes.
- **What users will see — per surface:**
  - The capability panel: three tabs across its title bar — Read me, Changelog, Capabilities — over a header carrying the capability's mark, name, publisher and one-line pitch, an install action, and a strip of five facts. Below that, the document itself: headings, paragraphs, bold and inline code, code blocks on their own ground, quotes with a leading rule, numbered and bulleted lists, tables with a header row, rules, links, images, and the small two-part badges that open almost every document of this kind. Long documents scroll inside the panel rather than growing it past the window.
- **Behaviour changes:**
  - Reading a capability's documentation no longer means leaving for a browser.
  - Nothing in the document reaches out to the internet while you read it. The badges are re-drawn by the app from what they say rather than fetched, so nobody outside learns which capability you are reading, and images come from the package you already downloaded rather than from wherever the document points.
  - Nothing in the document can run. Embedded markup is shown as text or dropped, never obeyed.
- **Design reference:** the console mock's capability panel draws every kind of block and every badge; it is the visual reference, subject to the design-authority question under M21.

**Assumptions**

- `[Experience]` The kinds of block in scope are the ones the mock actually draws. A kind that appears in no document the mock renders is not built, and a document containing one shows it as plain text rather than dropping it silently. *(a block falling back to raw text is visible; a block dropped is not)*
- `[Layout]` The panel's header and its strip of five facts come with this item, even though the brief predates them. *(they were added to the mock on 2026-08-20 after this brief was written, and the reader's question part-way through a document is still "and do I install it")*
- `[Experience]` Changelog and Capabilities are tabs over one panel, not one long scroll. *(two questions asked at different moments)*
- `[Operations]` The badges take the app's own text-safe colour rather than the colours the published badges carry, which fail the contrast floor at that size. *(measured; a badge with white text on a published green is a known failure with somebody else's brand on it)*
- `[Data & scope]` Nothing rendered here reaches the network, and nothing in the document may cause a request. *(the document arrives from a marketplace into an app that can write to other tools' configuration — this is the whole reason the brief exists)*
- `[Data & scope]` Images resolve from inside the downloaded package only. A document pointing outside it gets a placeholder, not a fetch. *(same reason)*
- `[Compliance]` Embedded markup is never obeyed. *(untrusted input; there is no case where honouring it is worth the exposure)*
- `[Operations]` Which colours the badges take is settled by M21 along with every other colour. This item names the need for a text-safe one rather than choosing its value, and the one acceptance line that checks the badge colour lands when M21 does. Everything else here ships without it. *(one item owns the palette, and waiting for it on the whole feature would stall ninety per cent of the work for one assertion)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage M19` before the planner picks this up.*

---

## 3 · Grounding record — pipeline note, not owner-facing

Measured on the main checkout at `7b730ee`, 2026-08-22.

### 3.1 Design authority

Recorded in full at `planning/specs/spec-M15.md` §3.1, asked at `planning/specs/spec-M21.md` §2. Not
re-asked here. A Markdown renderer's block coverage and its untrusted-input rules are independent of
which visual direction wins; only the shield colour token and the surrounding chrome move.

### 3.2 This is the emptiest starting point in the programme

There is **no Markdown rendering of any kind** in `app/Sources`. `AttributedString(markdown`,
`import Markdown` and `MarkdownUI` all return nothing. `README` and `changelog` appear only in
unrelated contexts — a URL-parsing comment in `RegistryMerge.swift:13`, and a fixture skill literally
named `"changelog-writer"` in `SkillFixtures.swift:79`. `shield` and `badge` resolve to the app's own
`Icon.shield` glyph and the sidebar's notification counts. Nothing here is a rename of something
existing.

The panel it renders inside is also absent: M18's table lists `readme` among the sheets the build does
not have.

### 3.3 The mock draws more than the brief describes

`design/mcp-router-console.html`'s `id="sh-readme"` carries, in order: a title bar with the capability
name, its version, and three tabs (`Read me`, `Changelog`, `Capabilities`); a `prodhead` block with
the app-style mark, name, publisher with a verified glyph, and a one-line pitch, plus a `What
changed…` action and a filled `Install…`; a `prodfacts` strip of five cells (Kind, Version, Licence,
Runs in, Reads); then the document body. Its shields are `<span class="shield"><b>key</b><i>value</i></span>`
pairs, with `class="good"` on the value that takes the text-safe fill.

The header and the facts strip arrived with M24 at `6c513b0`, whose commit message gives the reason:
*"the reader's question eight paragraphs into a README is still 'and do I install it'."* The brief was
written at 00:28 the same morning and does not mention them. The assumption above takes the mock.

### 3.4 Two mock links point at this item and lead nowhere

`data-act="sheet:changelog"` appears twice in the mock and there is no `id="sh-changelog"`, so
`openSheet` returns early and nothing opens. The changelog is a **tab of this panel**, so the correct
fix is the link, not a fourteenth panel. Recorded under M18 §3.2 as well, because the sheet inventory
is M18's.

### 3.5 What is measured, and it is nothing

Grepped `defects.in.json`, `inventory.json`, `cases.json`, `ledger.md`, `campaign.json` and
`RUN-2026-08-20.md` for readme, changelog, shield, markdown and gfm. **No defect, case, deferred row
or witness verdict bears on this feature.** The only `README` hits are requirement source citations of
the form `"source": "README.md:7-49"`. That is a genuine absence and is stated rather than read as
agreement — this item ships with no prior measurement behind it, which makes M23's gate the only thing
that will catch drift.

### 3.6 The library question, answered rather than asked

`AttributedString(markdown:)` covers inline emphasis, code spans and links and does not render tables
or fenced code blocks, both of which the mock draws. `PRD.md` §7.2 additionally names collapsible
blocks and side-by-side diffs. The brief's shape — a block parser producing typed blocks, each with
its own small view, with the system parser used for the inline runs inside a paragraph — is the only
shape that keeps the inline handling on a system parser. This is settled in the brief and is not a
question; the planner should not re-open it.

`CODING_PRACTICES.md` is a TypeScript, NestJS and Next.js document and has nothing to say about this
target. `planning/practices/SWIFT_PRACTICES.md` is the applicable one.

### 3.7 What this item owes M23's gate

The capability panel is one surface. It needs `planning/fidelity/readme.layers.json`, its pairing file,
and a `Surface` case in `app/Sources/MeasureDump/main.swift`. The brief's acceptance — *"a fixture
README containing every block kind in the mock renders with no block falling back to raw text, and the
shield colours are the token values rather than the badge's own"* — is a `breadth` layer assertion over
the block inventory plus a `tokens` assertion, both of which M23 built. The fixture document is this
item's to author.

### 3.8 Gate record

- Codebase grounding: `app/Sources`, `design/mcp-router-console.html`, `PRD.md` §7.2, `planning/test-campaign/`.
- Out-of-family spec review: see §3.9 for which lane answered.
- Eight assumptions. The security ones are the brief's own stated constraints rather than defaults chosen here, so they are recorded rather than asked.

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

- **Accepted in part — the token dependency, not the block.** One lane argued this item is blocked on M21, and the mechanism it gives is real and verified: `DesignTokenParityTests` asserts exact two-way name-set equality between `ColorToken` and `DESIGN.md` §2, `ColorToken` has 18 cases and no `shieldGood`, and the brief's acceptance requires *"the shield colours are the token values rather than the badge's own"*. So that one acceptance criterion cannot be written until M21 lands. **That is a dependency, not an owner question** — nothing about it needs a human, and blocking a whole item on one assertion's ordering stalls a feature whose other ninety per cent is untouched by the answer. The header now carries `M21` as a dependency and §2's last assumption says which half waits.
- **Accepted — the exposure, stated rather than buried.** Under M21 answer (b) the console mock is an exploration and this panel has no design source at all, because the prototype does not draw it. That is why M21's question carries an option (c) — the console mock stays authoritative for surfaces the prototype does not draw — and this item is one of the two that option exists for.
- **Both lanes agreed the renderer itself is unblocked** and independent of the design authority. The other lane called it *"completely unblocked … can proceed to To Do immediately regardless of the design authority outcome."*
