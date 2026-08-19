# M19 — the in-app GitHub-flavoured Markdown viewer

**Depends on:** M4. **Delivers:** PRD §7.2.
**Source:** `design/mcp-router-console.html`, sheet `readme`.

Deciding whether to install or update a capability means reading its README and its changelog,
and today that means leaving for a browser. The mock renders both in a sheet, tabbed **Read me
/ Changelog / Capabilities**, so the decision and the evidence sit on the same surface.

## What the renderer has to handle

Drawn in the mock, so all of it is in scope: headings h1–h3, paragraphs, bold and inline code,
fenced code blocks with a monospace ground, blockquotes with a leading rule, ordered and
unordered lists, tables with a header row, horizontal rules, links, inline images, and
**shields** — the small two-part badges (`marketplace | fledgeling`, `checks | 12 of 12`) that
open almost every README in this ecosystem.

Shields are worth naming because they are the one element that must be re-drawn rather than
loaded. A real shields.io badge is a remote image; fetching one leaks which capability the user
is reading to a third party. Parse the badge URL and render it natively, matching the shape.

## Constraints

**A README is untrusted input.** It comes from a marketplace and it is being rendered inside an
app that can write to harness configuration. Render it as data: no scripts, no remote loads, no
HTML passthrough, and images resolved from the downloaded package rather than fetched from
wherever the Markdown points.

**A shield that carries white text needs a text-safe fill.** The published badge greens and
blues fail the contrast floor at badge type size. The mock carries a separate `--shield-good`
token for exactly this, measured 5.40:1 to 9.72:1 across the four appearance contexts.

**Changelog and capability list are separate tabs, not a scroll.** The question "what changed"
and the question "what does it do" are asked at different moments, and a capability delta
(M18) is the third answer, reachable from the same sheet.

**Long documents scroll inside the sheet body**, which is capped rather than growing the sheet
past its window.

## Converting this to SwiftUI

`AttributedString(markdown:)` handles inline emphasis, code spans and links, and it is the right
tool for the parts it covers. It does not render tables or fenced code blocks, both of which
appear in the mock and in every README this app will show, so a renderer is needed on top of it
rather than instead of it.

The workable shape is a block parser producing an array of typed blocks — heading, paragraph,
code fence, table, list, rule, image, shield — each rendered by its own small `View`, with
`AttributedString` used for the inline runs inside a paragraph. That keeps the inline handling
on a system parser and puts the custom work only where it is unavoidable.

- Shields are drawn natively from the parsed badge URL. Loading the remote image tells a third
  party which capability the user is reading, and the mock's `--shield-good` token exists
  because the published badge colours fail the contrast floor under white text.
- Images resolve from the downloaded package, never from an arbitrary URL in the Markdown.
- No HTML passthrough. A README is untrusted input arriving from a marketplace into an app that
  can write harness configuration.
- Read me, Changelog and Capabilities are three tabs over one sheet, not one long scroll.

Acceptance: a fixture README containing every block kind in the mock renders with no block
falling back to raw text, and the shield colours are the token values rather than the badge's
own (M23).
