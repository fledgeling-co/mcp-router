---
status: completed
shipped-by: e154bae
---

# R3 — Swift router: control API, auth, usage, registry

**Depends on:** R1.

Port `src/control.ts`, `src/auth.ts`, `src/usage.ts`, `src/registry.ts`. The wire format
must match the TypeScript control API byte for byte — F3's client is built against it and
the parity gate in R4 diffs both.

Non-negotiable, carried from the TypeScript build:
- **`command`, `args` and `env` are not writable through PATCH.** A control API that can
  rewrite a command line is a control API that can run anything.
- Caller identity resolves on the server's `connection` event (TCP accept), cached on
  the socket. Resolving it at the end of a tool call loses every short-lived client.
- Trending is a signed delta over a stated window, never a popularity level relabelled.
