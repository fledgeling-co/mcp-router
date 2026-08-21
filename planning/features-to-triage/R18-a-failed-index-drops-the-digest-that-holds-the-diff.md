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
