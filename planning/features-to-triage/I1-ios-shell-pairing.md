# I1 — iPhone app: shell and pairing

**Depends on:** F2, F3, M6.

The companion's foundation. A tab bar (Discover / Triage / Queue / Library / Settings)
and the pairing flow that connects it to a Mac.

- Pairing by QR scan with a typed-code fallback, mirroring M6's Mac side and its expiry
  countdown.
- Connection state is always legible: paired to which Mac, reachable or not. A phone
  that silently fails to send is worse than one that says it cannot.
- **The phone queues; it never installs.** This is a deliberate narrowing of "remote
  install" and every surface must reflect it rather than implying otherwise.
- iOS-native grammar throughout — this is not the Mac app's chrome on a phone.

Deep link: `design/mocks/prototype.html?only=phone&pairing=1`.

## What the test campaign measured about this, 2026-08-21

**Defects:** DEF-001, DEF-041 · **Related:** M6 (the Mac half), DEF-008

The transport this brief's pairing flow depends on does not exist. See M6's campaign note
for the measurement: an effect census over `app/Sources` finds no symbol that opens a
connection to a paired device, so REQ-016 holds vacuously and three cases stand `fail`
against REQ-015. **This item cannot be completed before M6's transport lands** — the
dependency is already declared in the header, and it is now measured rather than assumed.

The measurement to read first is **I5, merged at `4157bc4`** (ORCHESTRATOR.md), which proved
the round trip does not happen because *neither side implements it*, and pinned it on the
phone storing a paired-Mac record for a Mac it never contacted at an address it could reach.
Nine mutation arms. That is the specification of what is missing on this side.

One iOS-specific finding for whoever builds the tab bar here: a SwiftUI tab item's
accessibility identifier **cannot be set**. `.accessibilityIdentifier` was measured on
glass in both places the framework offers it and both *clear* the identifier rather than
set it. The shipped tab bar therefore carries the SF Symbol's name as its identifier and
the destination's name as its label, and `MCPRouterIOSUITests` queries it by label. The
full measurement is at `PhoneShell.swift:121-129`; the open question of whether to keep
fighting it is DEF-008 in the M28 docket. Query by label rather than re-deriving this.
