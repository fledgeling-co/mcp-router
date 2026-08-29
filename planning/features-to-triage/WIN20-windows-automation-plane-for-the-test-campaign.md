---
status: to-triage
found-by: intake divergent pass, from the campaign's dependence on an accessibility plane · 2026-08-30
registry-target: none
no-target-reason: the campaign's oracle rungs are defined against the macOS accessibility plane, and no requirement or case in the registry describes how a Windows surface would be observed at all
---

# Without a Windows automation plane, every Windows surface is unmeasurable and the campaign can only report never-measured

- origin: intake divergent pass, 2026-08-30
- audience: whoever has to say whether the thirteen Windows surfaces actually work
- platforms: windows, harness
- proposed-by-ai: true

## What and why

The test campaign does not judge surfaces by screenshot. It stands each case on a rung of oracle,
and the rungs above `touch` need a channel that publishes what a surface actually contains. On macOS
that channel is the accessibility plane, and the campaign's existing records show how precisely it
is reasoned about — one case is recorded as `unoracled` specifically because "SwiftUI does not
publish an NSMenuItem's badge to the accessibility plane", with the three conditions that would open
a rung named rather than the case being quietly passed.

Windows has an equivalent, UI Automation, and it is genuinely better in one respect: it is a
documented, queryable tree available out of process, which is what a campaign needs.

But whether the Windows client publishes a usable UIA tree is decided by WIN1. A WinUI 3 client
publishes one by construction. A WebView2-hosted client publishes a DOM inside a single UIA node
unless it is deliberately wired to expose more, so the campaign would see a window containing one
opaque element. Avalonia draws its own controls and its automation peers are its own responsibility.

So this brief is the reason WIN1 is not purely an aesthetic or convenience choice. Build the wrong
way and thirteen surfaces land permanently in reckon's `never-measured` class — which, per that
tool's own framing, is neither a pass nor a failure and is the class that silently turns a partial
campaign into a finished-looking product.

Getting this right also delivers something the Mac lane does not have: the campaign's macOS captures
were constrained by a rule against activating the app, which is what left several cases unoracled.
A UIA tree is readable without bringing the window forward, so several of those constraints do not
transfer.

## Acceptance sketch

- Every Windows surface publishes a UI Automation tree in which its controls are individually addressable, with names matching the vocabulary on screen.
- A control's state — disabled, selected, held, busy — is readable from the automation plane, not only from pixels.
- The campaign can enumerate a Windows surface's controls out of process, without activating or foregrounding the window.
- A surface whose controls are not addressable is reported as unoracled with the reason, following the existing convention rather than passing quietly.
- The chosen framework's automation behaviour is measured on a real window before thirteen surfaces are built on it.
- Screen readers benefit as a consequence: the same tree serves Narrator, so accessibility and measurability are one piece of work.

## Assumptions made writing this

- Assuming UI Automation is the Windows channel, since it is the platform's documented accessibility and automation API and the campaign already reasons in those terms.
- Assuming the campaign's oracle rungs transfer conceptually to Windows with the channel substituted, rather than needing a new rung scheme.
- Assuming this is worth its own brief rather than an acceptance line inside WIN1, because it also carries the screen-reader obligation, which outlives the framework decision.
