---
status: completed
shipped-by: 6d54ce2
---

# M23 — the mock-to-SwiftUI conversion contract

**Depends on:** F2. **Blocks:** M15–M22, and every later surface built from a mock.
**Category:** foundation · method
**Sources:** `design/mcp-router-console.html`; `mockup-fidelity` at
`.claude/plugins/fledgeling-plugins/plugins/mockup-fidelity/skills/mockup-fidelity/`
(SKILL.md, `references/react-native.md`, `references/measurement-enforcement.md`,
`references/engine-capability-matrix.md`); the repo's existing
`app/Tests/MCPRouterKitTests/DesignDocParser.swift` and `DesignTokenParityTests.swift`.

The project's primary task is converting an HTML mock into SwiftUI without drift. This brief
specifies how that conversion is proved, and it is worth building before the first board is
converted rather than after the third one has silently diverged.

## The problem this is guarding against

`mockup-fidelity` names twelve self-deceptions that produce a verdict which feels rigorous and
is wrong. Four of them are the ones this project will hit:

- **Code-read certification.** A `ColorToken` literal tells you what a view *declares*, not what
  rendered. It cannot reveal a view that never appeared, a modifier that lost the cascade, a
  control the data left empty, or a section that is simply absent.
- **Style-without-structure.** Diffing each element's colour and size in isolation never
  reconciles the skeleton — containment, stack axis, sibling order, geometry. Those are the
  highest-frequency real defects and a per-property diff is structurally incapable of catching
  one.
- **Motivated classification.** A real difference labelled intentional without a citation. This
  is the single most common way drift ships.
- **A green report from a blind instrument.** A property the measurement cannot compute reads as
  agreement on both sides and the differ emits nothing. That is not a miss you can see; it is a
  pass you cannot.

Two measurements make the case that prose cannot fix any of this. Frontier multimodal models top
out near **40% recall on fine-grained UI differences, under 23% on hard cases** — so comparing
screenshots is not an audit. And agents under effort pressure rationalise a skipped
measurement; models trained against that learn to conceal the shortcut rather than stop. What
works is making the artifact a precondition for the verdict.

## The four layers, and what measures each on this target

SwiftUI has no DOM, which puts it in the same position as React Native: `getComputedStyle` does
not exist, and by the time anything is on screen the modifiers have been resolved away. The
layer table below is the RN table with the tools substituted.

| Layer | Mock side | SwiftUI side | Catches |
|---|---|---|---|
| **Tokens** | the `:root` block and the `mac-craft:metrics` comment, both machine-readable | `ColorToken` / `TypeToken` / `MetricToken` | systematic offsets a single element hides |
| **Structure** | parsed DOM: role, text, stack axis, frame, ordered children | the accessibility tree of the running app | missing, substituted, relocated and reordered elements |
| **Resolved style** | `getComputedStyle` per element | an in-app measurement harness (below) | colour, font, radius and spacing drift |
| **Copy** | the mock's text nodes | the `*Copy` enums | placeholder text, absent unhappy-path sentences |
| **Pixels** | screenshot | `XCTAttachment` bitmap | supplementary only, never the evidence |

**The resolved-style layer is the piece that does not exist yet and has to be built.** Nothing
outside the process can read a SwiftUI view's resolved foreground colour or font. The working
shape, borrowed from `references/react-native.md` §2.5, is a **dev-only measurement harness**
compiled under a `MEASURE` flag: a view modifier that records, per instrumented view, its
token identity, its resolved colour and font, its `GeometryReader` frame in window
coordinates, its parent chain, and its stack axis — then writes one JSON dump per surface.

The lesson that reference records is worth repeating, because it cost a whole passing-looking
audit: a harness emitting a flat list of `{type, text, style}` per node is **layout-blind**. It
cannot tell an `HStack` card from a `VStack` card, a present divider from an absent one, or a
two-column grid from a stack. Per node the harness must also emit **containment** (the parent
chain), **layout** (the stack axis and alignment), and **geometry** (x/y/w/h). Without those
three, every colour can match while the entire layout is wrong.

## Re-key the parity test that already exists

`DesignDocParser` already reads token tables out of `DESIGN.md` and `DesignTokenParityTests`
already compares them to the Swift token types. That mechanism is right and should be kept; it
is pointed at the wrong document.

The mock carries its tokens in two machine-readable blocks: a `<!-- mac-craft:metrics -->`
comment of `name value tier` rows, and a `:root` block where every colour lives in a custom
property with **no colour literal anywhere outside it**. Both parse more easily than the
Markdown tables the current parser handles.

Add a `MockTokenParser` beside `DesignDocParser`, keyed to `design/mcp-router-console.html`, and
assert three things:

1. Every metric row in the mock has a `MetricToken` case with the same value.
2. Every `:root` custom property has a `ColorToken` case with the same value, in each of the
   appearance contexts the mock authors.
3. **No Swift file outside the palette type contains a colour literal.** This is the direct
   analogue of the mock's `literals_outside=0`, it is a grep, and it is the check that stops the
   system becoming decorative.

Which document is authoritative is M21's open decision. Until it is settled, write the parser
against the mock and leave the `DESIGN.md` parser in place rather than deleting it.

## The breadth ledger comes before the style diff

For every surface, fill a **present / divergent / absent** row for every affordance the mock
shows — every header element, button, card, section, badge, chip, search field, meaningful
icon, list row and call to action — *before* opening the style findings. A clean style diff
means nothing about breadth, because the differ only compares elements that exist on both
sides and is structurally blind to a missing one.

Three rules keep the ledger honest, all of them from the skill's own gate:

- **`PRESENT` is earned by measuring, never inferred from purpose.** Two controls doing the same
  job are not a match; pair them, then audit label, control kind and glyph.
- **A citation is external and pre-existing.** A ticket line, a spec line, a code comment that
  predates the audit, a platform guardrail. A justification composed during the audit —
  "the app's richer treatment", "native chrome", "probably deferred" — is motivated
  classification wearing a citation's clothes, and the row is a defect.
- **Extra elements are divergent too.** Matching the mock means removing what it does not have,
  not only adding what it lacks.

## What counts as a surface

Every board, every state of every board, every sheet, the Settings window and each of its panes,
the popover, the notification, and each open menu. The mock draws 40 board-and-window state
cells (M17) plus twelve sheets (M18) plus nine menus (M20); each is its own row in the
inventory, and an omitted surface is an unaudited one rather than a passed one.

"Minor sub-state of X" is not a reason to drop a frame. If it is drawn, it is inventoried, and
an exclusion is recorded with its reason rather than made in silence.

## A check that cannot run is not a check that passed

The mock's own delivery note already carries a list of what was specified rather than measured —
motion, type fidelity and the three accessibility media queries, none of which the available
capture engine can execute. The SwiftUI side will have its own such list, and it must be
reported rather than absorbed.

Give the conversion gate three exit states rather than two:

| | |
|---|---|
| `0` | clean and complete — no findings, and every layer ran |
| `1` | findings — at least one difference |
| `3` | **inconclusive** — a layer the verdict depended on could not run |

An inconclusive layer gets a ledger row naming what it covers and where it was confirmed
instead. Marking a surface done with a silenced layer unrecorded files an unasked question as
an answer, which is the same failure as dropping a frame, one level down.

Where a tool fails, quote what it said. The failure strings name the engine and the value that
came back, and a paraphrase is how "this layer cannot run here" becomes "the shadows match".

## Acceptance

- `MockTokenParser` exists and its three assertions pass, including the colour-literal grep.
- The measurement harness produces a structure-and-geometry dump for one surface, and that dump
  is a nested tree with containment, axis and frames rather than a flat list.
- One surface — Servers, since M16 makes it the hardest — has a filled breadth ledger whose
  every cell names the two artifact values it compared.
- The gate returns 0, 1 or 3, and a run with a deliberately disabled layer returns 3 rather
  than 0. A gate never observed failing is a gate nobody has written.
