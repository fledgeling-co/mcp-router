# M19 — out-of-family referral on the scope fork

Asked 2026-08-22 from the `ai/m19` worktree at `87e16dc`, before the plan was written.

**Lanes attempted, in order.** `grok-4.6` at `xhigh` refused with
`API error (status 402 Payment Required): Grok Build usage balance exhausted` and wrote a
zero-byte file — recorded as a lane failure, not as a verdict. `codex` / `gpt-5.6-sol` is recorded
down until 2026-08-27 and was not attempted. `agy` / `gemini-3.7-flash-high` answered in one
invocation; it is the Google family, so the out-of-family gate ran rather than being downgraded.

**The question, verbatim, is below the answer.** It carried the measured facts rather than a
summary of them: the three control-API route families, the absent wire fields, the lint that
forbids the UI reaching the filesystem, the Release-never-renders-a-fixture rule, and M18's
recorded ownership of the host panel.

---

## `agy` / `gemini-3.7-flash-high` — verdict

**(A)** — with one specific refinement.

### Why (A) is the correct choice

1. **Strict adherence to the acceptance gate**: M19's acceptance criteria are explicitly fixture-based and verified by the M23 headless affordance gate. M23 exists precisely to prove surface completeness and visual fidelity in isolation without requiring active navigation wiring or live backend contracts.
2. **Rejection of (B)**: Shipping a live UI affordance that is a dead-end violates the core product rule. Presenting an interactive element in Release that cannot deliver live data degrades the integrity of the surface.
3. **Rejection of (C)**: Implementing the control API across two router runtimes (TypeScript `src/` and Swift `app/Sources/RouterCore/`), establishing new filesystem access policies across trust boundaries, and writing parity vectors is a multi-layer backend feature. Conflating it with M19 violates component isolation and inflates scope beyond the triaged brief.
4. **Clean boundary ownership**: M18 explicitly owns host panel lifecycle and sheet inventory. M19 should only own the Markdown tokenization and rendering pipeline.

---

### What is better: (A) + Typed Domain Contract & Discrete API Ticket

Instead of leaving the document source as a loose "unowned gap" under raw Option A:

1. **Formalise the Swift Client Contract in M19**: Implement the Markdown viewer against an explicit client protocol (e.g., `CapabilityDocumentationProviding`) whose production implementation returns an `EndpointUnavailable` domain error, while DEBUG/M23 uses the verified fixture bundle.
2. **File a dedicated backend task (`M19b` / `ROUTER-DOC-IPC`)**: Scope the `/registry/:id/readme` (and changelog) endpoint across `src/` and `RouterCore` as an independent router feature. 
3. **Sequence cleanly**: Let M18 (sheet inventory) integrate M19 (viewer) once the dedicated backend ticket lands, preserving release integrity without blocking M19's completion.

---

## The prompt it was given

> You are reviewing a scope decision on a macOS SwiftUI app (MCP Router). Answer decisively; say which option you would take and why, and name anything better than the options listed.
> 
> ## The item
> M19 — an in-app GitHub-flavoured Markdown viewer. It renders a capability's README / Changelog / Capabilities as three tabs of one panel, so a user deciding whether to install a marketplace capability does not leave for a browser. Its brief's acceptance criterion is: "a fixture README containing every block kind in the mock renders with no block falling back to raw text, and the shield colours are the token values rather than the badge's own."
> 
> ## Measured facts about the repository (verified this session, not remembered)
> 1. The Mac app talks to a local router process ONLY over a loopback control API. A lint (`scripts/lint/no-raw-design-values.sh`) fails the build if UI code references `URLSession`, `FileManager`, `Bundle`, `Data(contentsOf:)` or `URL(fileURLWithPath:)` — the app may not read the filesystem or the network directly.
> 2. The control API serves exactly three route families: `/servers`, `/usage`, `/registry` (verified in `src/control.ts:279-283`). There is NO endpoint that serves a README, a changelog, a licence or a capability table. No wire type has such a field (`RegistryEntry`, `Skill`, `PluginOrigin` all checked).
> 3. A standing product rule, written into the design authority: "No number is displayed that the router does not observe. There is no fabricated metric anywhere in this product." A Release build is structurally forbidden from rendering fixture data — `ShellClientFactory` returns the live client unconditionally outside DEBUG, with a comment explaining that a fixture-backed Release build would state invented figures in the present tense.
> 4. The panel the viewer renders inside does not exist. A separate, not-yet-built item (M18) is recorded as owning "the panel this renders inside" and the sheet inventory generally. M18 is To Do and unstarted.
> 5. There is a measurement gate (M23) that renders a surface headless, dumps its resolved geometry/colour/copy tree, and diffs it against the mock's own affordance census. It can render a view directly, without the view being reachable in the shipped app.
> 
> ## The fork
> Where does the viewer live, given there is no live document source?
> 
> (A) Ship the renderer, the block views, the panel (header + five-fact strip + three tabs + scrolling body), a fixture document exercising every block kind, the M23 measured surface, and the unit tests. Do NOT add any entry point in the shipped app. M18 wires it to a sheet later; the document source is recorded as an unowned gap. Result: a complete, measured, tested surface that no user can reach yet.
> 
> (B) Also add a "Read me…" button to the existing Skills inspector, opening the panel. Against live data it would always show "no document available", because the router serves none. Result: reachable, but the app advertises a capability it cannot fulfil in a Release build.
> 
> (C) Also add a control-API endpoint (both the TypeScript router in `src/` and the Swift router in `app/Sources/RouterCore/`) that serves a capability's README from the downloaded package on disk, plus the wire type, the client method, fixtures and parity vectors. Result: genuinely reachable and honest, but expands the item across two router implementations and a new trust boundary that neither the brief nor the triaged spec mentions.
> 
> ## The question
> Which of A, B, C — or something better? Consider: the acceptance criterion is fixture-based and gate-based; the item's declared dependency says another item owns the host panel; the product's central rule is that nothing is displayed that the router does not observe.
> 
> Answer in under 400 words. Lead with the letter.
