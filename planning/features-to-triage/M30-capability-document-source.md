# M30 — where a capability's documentation actually comes from

**Depends on:** M19 (built the renderer and the panel). **Blocks:** nothing that ships today.
**Raised by:** M19's build, 2026-08-22, from a measured absence rather than a design idea.

M19 built the in-app Markdown viewer: a block parser, a shield parser that re-draws a badge
rather than fetching it, an image resolver that refuses anything outside the downloaded package,
and the three-tab panel the console mock draws. It renders a fixture. **Nothing serves it a real
document**, and this is the item that decides whether anything ever should.

## The measurement

Taken on `ai/m19` at `87e16dc`, and stated as an absence rather than read as agreement:

- The control API admits `/servers`, `/usage` and `/registry` and nothing else
  (`src/control.ts:279-283`).
- No wire type carries a read me, a changelog, a licence or a capability table. Checked:
  `RegistryEntry`, `RegistryInstall`, `Skill`, `PluginOrigin`, `HeldVersion`, `MarketplaceSource`.
- `Skill.path` is a resolved real path on disk, so the *router* is in a position to read a
  package's files. The Mac app is not: `A36` and `scripts/lint/no-raw-design-values.sh` forbid the
  presentation layer reaching past the control API, which is what lets the router be replaced
  underneath the app.

So the honest position today is `UnavailableCapabilityDocumentSource`, which answers
`CapabilityDocumentError.notServed` — *the router doesn't read a capability's read me, changelog or
capability list, so there is nothing here to show* — and no surface in the shipped app presents
the panel at all.

## What this item would decide

1. **Whether the router should serve documents.** It is the only process that may read a package,
   and it already resolves every skill's path. A `/registry/<id>/document` or
   `/skills/<path>/document` route is the shape; both the TypeScript router in `src/` and the Swift
   one in `app/Sources/RouterCore/` would need it, plus the parity vectors that keep the two honest.
2. **What it may serve.** A read me, a changelog and a capability list are files in a package. A
   *licence* and a "runs in" fact are derivations, and `DESIGN.md` §6 forbids displaying a figure
   the router does not observe — so the facts strip's five cells need one answer each, and
   "we can compute it" is not the same answer as "the router observes it".
3. **Whether images travel.** M19's resolver returns bytes rather than paths precisely so the app
   never opens a file. A wire shape that carries a document has to carry its images too, or the
   viewer draws placeholders for every figure in every real document.
4. **Size.** A README is unbounded on the wire. `MarkdownLimits` caps the parse; the transport
   needs its own cap, and a refusal that says which.

## What it would not change

The renderer, the shield parser, the image resolver and the panel are done and measured under
`M23` (`planning/fidelity/readme.layers.json`). This item supplies a second implementation of
`CapabilityDocumentSource` and the entry point that opens the panel; the sheet inventory that owns
that entry point is `M18`'s.

## The alternative, stated so it is chosen rather than defaulted past

Do nothing. The viewer stays a measured surface with a fixture behind it and no user reaches it,
which is a renderer built and shelved. That is a real option — it costs nothing and it ships
nothing — and it is worth naming because the cost of the other path is a new route on a trust
boundary in two router implementations.
