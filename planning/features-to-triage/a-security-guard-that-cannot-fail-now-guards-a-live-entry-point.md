---
status: to-triage
found-by: M19 re-verification, 2026-08-29
reckon-sources: [CASE-0262]
---

# A security guard that cannot fail now guards a live entry point

- origin: M19's second verification verdict (NEEDS MORE WORK) · 2026-08-29
- audience: whoever believes third-party markdown reaching the shipped UI is checked
- platforms: mac
- proposed-by-ai: true

## What and why

`MarkdownSecurityTests.htmlIsInert` is the only guard on the claim that embedded markup is never
obeyed, and **it cannot fail**. `MarkdownInline.sanitized` keeps only `inlinePresentationIntent`
and an `https` link, so "no `imageURL`" is true for every input, and "no link" is true for every
input carrying no https URL — and none of its four spellings does. Its own docstring says *"If a
toolchain change starts interpreting inline HTML, this goes red here."* It does not, and no
red-green arm names it.

**The property does hold in the product today.** A direct probe of the platform parser renders
`<a href="https://evil.example/x">press</a>` as literal text with no link. So this is an evidence
defect rather than a live vulnerability: nothing is known to be broken, and nothing would tell us
if it broke.

**What changed is the exposure.** M30 wired `ControlAPICapabilityDocumentSource` into the shipped
UI — `source: ControlAPICapabilityDocumentSource(client: board.client),`,
`app/Sources/MCPRouterUI/Boards/ServerSheets.swift:31` at `9128737` — so router-served
third-party document text now reaches this renderer in a Release build. At M19's merge there was no entry
point; there is one now.

That distinction decided a split between two out-of-family reviewers. `gpt-5.6-sol` returned
NEEDS MORE WORK with this finding blocking. `gemini-3.7-flash-high` returned AMEND on the same
finding, declining to block partly because of "zero production attack surface: M19 exposes no
entry point" — a statement that was true of M19 alone and false of the tree being graded.

## Acceptance sketch

- The inertness guard fails when inline HTML is interpreted, demonstrated by making it fail.
- The guard's inputs include at least one spelling carrying an `https` URL, so the "no link"
  assertion is capable of being false.
- A red-green arm names this test, so a future toolchain change is caught rather than assumed.
- The claim states which parser and which build configuration it was measured against, since the
  property is the platform's rather than this code's.

## Assumptions made writing this

- Assuming the remedy is to strengthen the assertion rather than to add sanitisation, because the
  probe shows the platform already refuses to interpret the markup — the gap is that nothing
  would notice if it stopped.
