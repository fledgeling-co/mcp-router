---
status: completed
shipped-by: e129779
---

# R4 — Differential parity harness and the installer cutover

**Depends on:** R2, R3.

The gate that decides whether Swift replaces TypeScript.

Build a harness that runs both routers against the same recorded MCP traffic and diffs:
every tool-list response, every call result, every control-API response, spawn and reap
timing, and the log. Parity means byte-identical control responses and behaviourally
identical spawn/reap decisions over the full corpus.

Only once green: one commit flips `install.sh` to the Swift binary, deletes `src/*.ts`
and its Node dependency, and updates the README and the marketing site's install copy.
Until then both ship and TypeScript is the default.

**This item may not be marked done on a partial pass.** A parity gate that reports green
on a subset is the exact failure this harness exists to prevent.
