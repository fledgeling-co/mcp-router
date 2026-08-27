---
status: completed
shipped-by: f466020
---

# P3 — An oracle for the usage stream, and one for registry search

**Source:** `cutover` = `finish-first`.

The last two parity gaps are both oracle problems rather than implementation gaps, which is why they
were deferred rather than done.

- `D-l` — `GET /usage/stream` is an open stream, so there is no byte oracle to compare against.
  Framing agreement is not body parity, and saying so is part of the job. **Blocks 1 row.**
- `D-m` — `registry/search` calls live registries, so two runs a second apart differ. Either record a
  fixture registry server, or accept the route as permanently uncomparable and say so in the manifest.
  **Blocks 2 rows.** An accepted-as-uncomparable row is a legitimate outcome here; a quietly passing
  one is not.

**Done means:** each row either proven or explicitly recorded as uncomparable with the reason, and the
gate's blocked count reduced by 3 either way.
