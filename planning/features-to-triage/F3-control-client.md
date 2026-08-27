---
status: completed
shipped-by: 13825c9
---

# F3 — Typed control-API client and models

**Depends on:** F1.

The Mac app talks to the router **only** over the loopback HTTP control API. That is
what lets the router be swapped from TypeScript to Swift underneath without the app
changing, so this boundary must stay the sole interface.

- Typed models for servers, skills, marketplaces, registry entries, usage rows, held
  schemas, pairing state.
- An async client with a live-updating stream for the call log and breaker states.
- **The offline state is a first-class case, not an error banner:** the router is
  loopback, so unreachable means "the router is not running" — say that and offer to
  start it (DESIGN.md §5).
- Auth: the control token, its storage in the Keychain, and its rotation.
- A recorded-fixture test double so every UI surface's tests run without a live router.

Source of truth for the surface: `src/control.ts`.
