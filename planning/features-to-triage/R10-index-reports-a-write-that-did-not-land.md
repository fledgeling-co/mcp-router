# R10 — `index` prints two counts that disagree, and neither is checked

**Half of:** DEF-049 (major). **Requirement:** REQ-019, REQ-007.
**The other half is M28's**, and this brief must not take it. See *The line* below.
**Found by:** the effect-witness denial control, not by reading code.

## What is wrong

`MCPRouterCLI index --force` against a router home the process may read and traverse
but not write (mode `dr-x------`) prints

```
ok    witness-fixture (1 tools)
…
0 tools cached -> /tmp/.../manifest.json
```

and exits 0, over a `manifest.json` that does not exist.

The `ok` line and the summary line disagree inside one run, eight lines apart, and
nothing in the verb compares them. The summary is the one that happens to be right: it
re-reads the manifest from disk to count, so it reports the truth by accident of how it
was implemented, while the per-server line reports what the indexer intended to write.

`ManifestIndexer.record` (`app/Sources/RouterCore/Service/ServicePorts.swift:347`) calls
`try? ManifestIO.save(...)`. `try?` discards the error, so the one call that makes an
index durable is the one call whose failure is unobservable from inside the verb.

## The line this brief does not cross

**The exit code stays as it is, and changing it is not in scope here.**

That is the owner's call, and it is already recorded as theirs in `inventory.json` from
the sitting that found the defect: propagating the error changes the CLI's exit-code
contract, and the project has taken the opposite decision once already on a sibling path
— `AuthRoutes.approve` answers 200 whether or not the bytes landed, pinned deliberately
at `ControlApproveDispatchTests.swift:114-118`. A brief that picked the propagating fix
would be making that decision on the owner's behalf while calling it a defect fix.

So `M28-decision-docket.md` keeps DEF-049's contract half, and this item takes only what
is a defect under any answer to it: **a verb whose own output contradicts itself and
which checks neither line against the other.**

If the owner later rules that a failed write must exit non-zero, that is a second, smaller
item on top of this one — and the trap to avoid then is folding an unperformed write into
the ordinary pass/fail pair. A reader that cannot tell "nothing to cache" from "the cache
was never written" reports the first while meaning the second, which moves the defect
rather than removing it.

## What done looks like

- `index` does not print `ok <server> (N tools)` for a server whose manifest row did not
  reach disk. Whatever it prints instead names the server and says the row was not
  cached.
- The per-server lines and the summary count cannot disagree, because one is derived
  from the other or both are read from the same place.
- The exit code is unchanged, and a test says so, so that a later change to it is
  deliberate rather than incidental to this one.

## Three call sites, and why only one is in scope

The same swallowed save appears three times:

- `app/Sources/RouterCore/Service/ServicePorts.swift:347` — the indexer. **In scope.**
- `app/Sources/RouterCore/Watch/WatchIndexing.swift:150` — the file-watch re-index.
  Out of scope: it has no output to contradict itself with. Recorded here so the fix is
  not mistaken for a sweep.
- `app/Sources/RouterCore/Auth/AuthRoutes.swift:120` — the tool-surface **approve**
  route, which writes a fresh `builtAt`. Out of scope here and **the one worth
  escalating**, because its failure path produces a false green.

  Traced rather than assumed, and the first version of this brief had the direction
  backwards. `AuthStamp.isAfter(stamp, other)` is `left > right` (`AuthStamp.swift:19-22`),
  and `Describe.swift:216-218` returns `nil` — meaning **no rejection reported** — when
  `authorizedAt` is after `builtAt`. So:

  - Save lands: `builtAt` = now, later than `authorizedAt`, the guard does not fire, a
    recorded refusal is reported, `authorized` is false.
  - Save silently lost: the disk keeps the older `builtAt`, `authorizedAt` is after it,
    the guard fires, the refusal is suppressed.

  And `authorized` is `deps.auth.hasTokens(name) && rejection == nil`
  (`Describe.swift:222-225`). Tokens live in `FileAuthStore`, which the failed manifest
  write never touches, so `hasTokens` stays true while `rejection` has just become nil:
  the route answers **`authorized: true` over a manifest that was never written.**

  That is the same shape as the `index --force` false green this brief is about, one
  layer up and user-visible, which is why it goes to M28 as a decision rather than being
  fixed quietly here.

  One thing flagged and **not verified**: the approve path sets `tools`, `digest` and
  `builtAt` and removes `pending`, and never removes `error` (`AuthRoutes.swift:108-114`).
  If that is right, a *successful* approve leaves the recorded refusal in place with a
  `builtAt` that stops the staleness guard firing, so the refusal shows. That would be a
  third defect, separate from either half of DEF-049. It is written here as a lead, not a
  finding.

## Evidence to reproduce

`planning/test-campaign/bin/witness-arm-denial.sh` is the control that found it. It points
the CLI at a home with mode `dr-x------` and reads what the process actually did rather
than what it said. Keep it as the arming control for whatever assertion closes this: the
defect is precisely that the happy-path output is indistinguishable from the failed one,
so an assertion that only reads stdout on a writable home cannot bite.

The assertion has to read the file system rather than the value the test itself just
wrote. `app/Tests/RouterCoreTests/ManifestIndexerWriteFailureTests.swift` — untracked in
the main checkout, author unidentified as of 2026-08-21 — already characterises the CLI
half without correcting it, and says so in its own doc comment. Read it before writing a
second one.

## Scope

`RouterCore/Service/ServicePorts.swift` and the CLI's index command. Does not touch the
TypeScript reference; a parity row exists for `cli index` and must stay proven.
