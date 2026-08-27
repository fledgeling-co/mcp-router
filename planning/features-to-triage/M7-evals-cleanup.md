---
status: completed
shipped-by: 85d8331
---

# M7 — Evals and Cleanup

**Depends on:** M3, M4.

Two surfaces sharing one idea: evidence about whether a capability earns its place.

**Evals** — run a skill or server's eval suite, see the result per check, and see the
history across versions. An eval result is evidence attached to a version, so it must
be invalidated when the version changes rather than carried forward.

**Cleanup** — surface capabilities that are installed and unused. Two rules learned the
hard way:
- Never a trash metaphor: a never-used server was never deleted.
- Never an automatic cull. Invocation count conflates "unused because worthless" with
  "unused because rare but critical", so the app proposes and the human decides.
Show never-used as a value in the existing column plus a filter, not as a separate
screen.

Deep links: `?only=mac&pane=evals`, `?only=mac&pane=cleanup`.
