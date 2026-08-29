# M37 — the referral prompt, as sent to both lanes

```
You are reviewing a design/engineering fork in a macOS SwiftUI app (MCP Router). Answer with a recommendation and the reasoning. Be concise (under 500 words). Say which option you pick, and say what the losing options are genuinely better at.

CONTEXT

The router multiplexes upstream MCP servers. A previously-shipped item (M29) added a `disabled` boolean to each upstream:
- Router side: `ToolUnion.isServed(upstream, cwd:) = upstream.disabled != true && visibleTo(upstream, cwd:)`. A disabled server contributes no tools, refuses tool calls with its own message, is skipped by automatic index sweeps, is reaped even if `warm`, and keeps its manifest row, digest and credentials.
- Wire: `PATCH /servers/:name {"disabled": true|false}`.
- UI shipped by M29: the Servers table row for a disabled server dims, its state cell reads `disabled by you`, its Tools cell is withheld (em-dash), and its single row-action slot offers `Enable`. The *disable* direction shipped in ONE place only: the destructive footer button on the "held schema change" sheet, which is reachable only when that server is holding a changed tool description.

THE GAP (this item, M37): an ordinary healthy server has NO way to be disabled from the UI at all. The brief asks for "an explicit active or paused toggle so operators can troubleshoot flaky servers or isolate tools during testing without losing saved configuration."

THE SERVERS INSPECTOR (right-hand pane) currently has these sections, top to bottom:
  header (name, "stdio · 41 tools", "Read its documentation…", "Close")
  banners (tripped / held change / needs sign-in / write error)
  "Right now" (read-only: state, in flight, calls, idle)
  "Use" (read-only counters)
  "Configuration" (read-only: transport, command, args, cwd, env key NAMES, hash, indexed-at)
  "Behaviour" (the writable half — two `ToggleRow`s: "Keep warm", "Only load in named projects", plus a per-project directory list and a "Sign out" button)
  "Tools" (tag list)
  "Danger" (one quiet destructive button: "Remove this server…", which deletes the config entry and unrecoverable secrets)

`ToggleRow` = a switch with a title, one quiet secondary sentence underneath, and a `disabledReason` that dims it in place with the reason spoken.

DESIGN RULES THAT BIND:
- "Undo over confirm — reversible actions are made reversible and reported, never gated behind 'are you sure'. Friction scales to blast radius only for genuinely destructive acts."
- "One name per state across both devices, taken from one source rather than spelled twice."
- Buttons verb-first, sentence case.
- A disabled control dims in place with a discoverable reason; never hidden.
- The design of record (an HTML mock) draws the disable as "a quiet destructive-red text button, never the primary" on the held-change sheet. It draws an inspector action row of `Wake now` (primary) / `Trip breaker` / `⋯ More actions` (chevron) — but NONE of those three exist in the built app (there is no start or stop operation on the control API, and no breaker endpoint), and the `⋯ More actions` MENU CONTENTS ARE NOT DRAWN anywhere in the mock. A prior deferral explicitly says inventing that menu's contents is out of scope.
- The single row-action slot in the table is already occupied by a strict precedence: enable > reset > review held change > sign in. So a tripped, held or unauthorised server has no free row slot.

THE FORK — where does the "disable this server" affordance live?

(A) A third `ToggleRow` in the "Behaviour" section, e.g. title "Disable this server", off by default, help sentence saying tools stop being served while config/credentials/approved tool list are kept.
(B) A quiet destructive text button in the "Danger" section, above "Remove this server…", reading "Disable this server" / "Enable this server".
(C) Add `.disable` to the table row's action slot for servers that currently have no action.
(D) Build the mock's inspector header action row and put disable in a `⋯ More actions` menu there.

Secondary question: the brief's words are "pause"/"paused"; the shipped product word for this state is "disabled" ("disabled by you" in the row, "Disable mobbin" on the sheet, `disabled` on the wire). Should the new control introduce the word "pause", or stay on "disabled"?
```
