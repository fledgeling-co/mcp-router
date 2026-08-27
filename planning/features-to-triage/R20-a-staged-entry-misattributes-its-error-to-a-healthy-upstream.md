---
status: completed
shipped-by: b637adf
---

# R20 — a staged entry wipes a same-named healthy upstream and blames it for the failure

**Status:** Untriaged · **Found:** 2026-08-22 by R17's verifier, measured against R17's fixed code
**Category:** router

## The finding

The manifest is keyed by server name alone. When a name is claimed by both a healthy router
upstream and a failing entry staged in `~/.claude.json`, the watcher's failure row overwrites the
healthy one — and `/servers` then attributes the **staged** definition's error to the **configured**
server.

Measured: a healthy `db` serving 2 tools, then a broken `db` staged, gives an `indexError` of
`spawn /nonexistent/not-a-server ENOENT` for a server whose configured command is `node`. Pre-fix
the same sequence read `error: None`.

## What is new here and what is not

**The tool loss is not a regression.** Before R17 the watcher deleted the row outright, and
`unionTools` skips a missing entry exactly as it skips a zero-tool one, so the healthy server's
tools vanished mid-session either way. The serve daemon hot-reloads the manifest, so this is visible
without a restart.

**The misattribution is.** The reader used to be shown nothing and is now shown a specific, wrong
reason — one that names a command the configured server does not run. R17's argument is that the row
*is the record*; a record that can be written by a different server's definition is a record that
can lie. This is the one surface R17 makes newly wrong, and it is why the item is filed rather than
folded into R17's evidence.

## This is R7's duplicate class, and it should be decided there

`namecheap` itself is declared **both** as a router upstream and as a global Claude Code entry —
the shape R17's brief already flagged as R7's class and set aside as a separate defect. The same
collision is what makes this possible. Patching the attribution alone would leave two files still
claiming one name, with the healthy server's tools still disappearing when the staged one fails.

So establish first what a name means when two files claim it, rather than deciding where an error
string should be filed under a collision that should not exist.

## Acceptance

1. A failing staged entry cannot replace the manifest row of a same-named upstream that is
   currently serving, or the reader is told which definition the error belongs to.
2. Whatever is decided holds on both implementations — the Swift indexer keys by name in the same
   way.
3. Decided together with R7, since the duplicate declaration is the precondition.
