# R17 — a failed index leaves a recorded error for one server and nothing at all for another

**Status:** Untriaged · **Raised:** 2026-08-21, from a live "why isn't mobbin there" investigation across two sessions
**Category:** router

## Measured

14 configured, 13 in the manifest, 12 serving. Two upstreams serve nothing, and they fail the
same way — `MCP error -32000: Connection closed`, observed for both during `index --force`:

| | manifest row | `/servers` error | discoverable? |
|---|---|---|---|
| `lifeline` | **yes**, error recorded | `MCP error -32000: Connection closed` | yes |
| `namecheap` | **none** | `None` | **no** |

`namecheap` reports `state: idle`, `tools: 0`, `error: None`. Nothing anywhere says it failed, or
that it was ever attempted. A reader sees an upstream that simply has no tools.

That is the same class as R14's silent upstreams and R16's silent skipped adoption, one layer
further in: **the router knows the index failed and keeps no record of it for this server.**

## Why it matters more than one broken upstream

R14 was built to report which upstreams need attention, and it derives state from tool count plus
the auth record. For `namecheap` both are empty and blameless, so **R14's report will place it in
the not-an-auth-problem bucket with no reason to show** — correct as far as it goes, and unhelpful,
because the reason exists and was discarded rather than never known.

## What to establish first

Why the two differ. Both fail with `Connection closed`, so the divergence is in the indexing path,
not the failure. Candidates: a server that fails before any tool list is returned may take a
different branch from one that fails during it; an entry added by a different route (`namecheap` is
also a **global** `~/.claude.json` entry, so it arrived by adoption where `lifeline` may not have)
may be recorded differently; or a manifest row may be written only on partial success.

That question decides whether this is one bug or two, so answer it before writing the fix.

## Acceptance

1. An upstream whose index fails carries a record of that failure — in the manifest, on `/servers`,
   or both — regardless of how it was configured or which branch the failure took.
2. `namecheap` specifically shows its reason.
3. A fixture with two upstreams failing at different points in the index produces a record for each.
4. R14's report shows the reason for an upstream that failed to index rather than filing it as a
   silent not-an-auth-problem.

## Related, and worth settling together

`namecheap` is declared **both** as a router upstream and as a global Claude Code entry. That is
R7's duplicate class, and it is probably why the user still has a working namecheap — through the
direct entry rather than through the relay. Deciding this item may want the duplicate resolved too,
but they are separate defects and this one stands alone.

## Not in scope

Fixing `lifeline` or `namecheap` themselves. Both may be genuinely broken servers; this item is
about the router's record of that, not about their health.
