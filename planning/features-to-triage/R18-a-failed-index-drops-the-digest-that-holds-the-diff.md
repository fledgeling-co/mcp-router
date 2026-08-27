---
status: completed
shipped-by: 4de2080
---

# R18 — a failed index drops the digest, so the next success serves a changed surface unheld

**Status:** Untriaged · security-adjacent
**Found:** 2026-08-22, by R17's `claude-fable-5` review lane, and **reproduced against the built router** by R17's runner
**Category:** router

## The finding

A failed index drops the manifest row's `digest`. On the next successful index `buildManifest`
takes its **first-sight-approves** branch — the path for a server nobody has seen before — so a
changed tool surface is served with **no held diff**.

Reproduced end to end against the built router, not argued from the code:

1. a benign tool surface, indexed and serving;
2. one failed re-index — `digest` becomes `None`;
3. re-index with a **tampered** surface — `pending: False`, and the tool is served.

The hold that exists to make a changed surface wait for a human is skipped, because the router no
longer holds the thing it would compare against.

## Why this is its own item rather than R17's

**It predates R17 and the behaviour R17 removed had the same hole.** R17 stopped the watcher
deleting the manifest row on failure; this is about what the row *carries* after a failure, and it
was true before that change and after it. Folding it into R17 would have meant a fix nobody had
asked for, in a pass whose scope was the missing record.

R17's runner recorded it and left it, which is the correct call and the reason it has a clean
provenance: the review output is preserved at `planning/evidence/R17-review-fable.md`.

## What to establish first

Whether the drop is deliberate. A failed index has no trustworthy surface to digest, so writing
*no* digest is defensible on its own terms — the defect may be that the **absence** is then read as
*never seen* rather than as *unknown*. Those want different fixes:

- if the digest should persist across a failure, keep the last good one and compare against it;
- if it should not, the first-sight branch needs a third state so *unknown* does not read as *new*.

Answer that before writing either, because they are not compatible.

## Acceptance

1. The reproduction above ends with the changed surface **held**, not served.
2. A server genuinely seen for the first time still takes the first-sight branch — the fix must not
   turn every new server into a held diff.
3. A fixture drives failure-then-tamper and asserts the hold, arming it by reverting the fix and
   watching it serve.
4. Both implementations, at parity.

## Related

`R17` — the failed-index record, which is where this was found. `R14`'s report reads state from
tool count and the auth record and would show this server as healthy throughout, because it is:
the tools are served. Nothing surfaces that a diff was skipped.

---

## Triage — 2026-08-22

**Verdict: To Do.** Standard tier. No dependency, but it must be planned alongside `R20`, which
writes the same manifest row from a different direction.

### The finding is confirmed by reading, and the drop is incidental rather than deliberate

`src/manifest.ts:258-265`, `buildManifest`'s `catch`:

```ts
manifest.servers[u.name] = {
  hash: upstreamHash(u),
  builtAt: new Date().toISOString(),
  tools: [],
  error: message,
};
```

It constructs a whole new entry. `prev` is in scope — the held-diff branch four lines above spreads
it (`...prev`) — and this branch does not, so both `digest` and `tools` are dropped. At the next
success `:236` reads `if (!prev?.digest || prev.digest === digest)` and an absent digest takes the
same branch as a matching one: **first sight approves**.

The brief asked whether the drop is deliberate before choosing between two incompatible fixes. It is
not. Every deliberate retention decision in this file carries a comment defending it — the
first-sight branch has a six-line one immediately above it — and this branch has none, while its
sibling four lines away spreads the value it drops. That is the evidence; it is an argument from
this file's own convention rather than from silence in general.

So the brief's first fix is the right one: **keep the last good digest across a failure**. An
absent digest then means *never seen*, which is what `:236` already assumes it means, and no third
state is needed.

### The fork that remains, and why it is the plan stage's first decision

Preserving `digest` alone is not obviously sufficient, and preserving `tools` too is not obviously
safe. `unionTools` (`src/manifest.ts:326`) skips an entry on `!entry || entry.tools.length === 0`
and **does not read `entry.error` at all**. So today a failed server serves nothing only because its
tools were emptied — the zero-length list is load-bearing, and it is doing a job the error field
looks like it should be doing.

Two shapes follow, and they are not compatible:

- **Digest only.** Smallest change, `tools` stays `[]`, serving behaviour unchanged. But after a
  failure followed by a *changed* surface the held-diff branch spreads `prev.tools` — which is now
  `[]` — so the server is held pending against an empty approved set and serves nothing until a
  human accepts. Safe, and a behaviour the product has never had.
- **Digest and tools, with serving gated on `error` instead of on emptiness.** Preserves the
  approved surface as the comparison baseline and keeps the failed server unservable for the right
  reason. Touches the serving path, so it is the larger change and reaches `router.ts:168` and
  `:347`.

Establish which before writing either, exactly as the brief asks. The measurement that decides it
is what the second shape does to `R20`'s collision, since both write this row.

### Note for whoever plans it

The brief's acceptance criterion 1 ("ends with the changed surface **held**, not served") is met by
both shapes. Criterion 2 ("a server genuinely seen for the first time still takes the first-sight
branch") is the one that distinguishes them under a prior failure, and it should be armed against a
never-seen server *and* a seen-then-failed one, because those are the two cases the fix collapses
or separates.
