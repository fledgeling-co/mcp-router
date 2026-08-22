# R21 — `approve` answers 200 while discarding the write that would make it true

**Status:** Ready for AI · **Found:** 2026-08-22, re-measuring M28's DEF-049
**Category:** router · Standard tier

## The finding

`AuthRoutes.swift:120` is the last of the three `try? ManifestIO.save(...)` call sites DEF-049
named. The other two have been fixed; this one has not.

The approve route sets `tools`, `digest` and `builtAt` and removes `pending`
(`AuthRoutes.swift:108-114`), writes the manifest at `:120` discarding any error, and returns
`(200, { server, approved: N })` at `:123-126`. **When the write is refused the response is
unchanged**: the caller is told a tool surface was approved, and on disk it is still held.

`approved` is counted from the pending entry *before* the write (`:103`), so the number in the
response is a description of what the route intended rather than of what happened — the same
shape as `index --force` printing `ok <server> (N tools)` over a manifest that did not land.

## What this is not

DEF-049 predicted a different and more alarming harm — that a failed save leaves an older
`builtAt` on disk, `AuthStamp.isAfter(authorizedAt, builtAt)` fires, the suppression guard at
`Describe.swift:218` hides a real refusal, and `/servers` reports `authorized: true` over a
manifest never written.

**That does not follow, and the reason is a precondition neither side of the argument checked.**
Approve is reachable only for an entry carrying `pending`, and both implementations clear `error`
when they stage one — node at `src/manifest.ts:246`, Swift at `ManifestBookkeeping.swift:83`. So
`entry.member("error")` is `nil`, the `guard case let .string(text)?` at `Describe.swift:208`
fails first, `rejection` is `nil`, and the guard at `:218` is never reached. The two
implementations agree, so there is no parity divergence here either.

The plainer defect above survives that refutation intact, and is what this item fixes.

## The fix shape is already established in this repository

`ManifestIndexer.record` solved the identical problem at `ServicePorts.swift:388-394`: the save
became a `do`/`catch` returning a `cacheFailure`, which propagates through `IndexOutcome`
(`:320`, `:343`) to `ControlPorts.swift:95` and drives `cached` at `:108`. Its doc comment records
the decision and the reason:

> The error is reported, not thrown. Propagating it would change the CLI's exit code and the
> control API's status for a manifest that failed to write, and both are contracts this repo has
> taken a decision on elsewhere (`ControlApproveDispatchTests.swift:114-118`); moving either is
> its own item.

Follow it. **Do not change the route's status code** — `ControlApproveDispatchTests.swift:114-118`
pins 200 deliberately, and moving it is the separate item that comment names.

## Acceptance

1. A refused manifest write during approve is visible in the response — the route stops claiming
   a surface was approved when it was not.
2. The status code is unchanged at 200, and `ControlApproveDispatchTests` stays green unedited.
3. `approved` describes what landed rather than what was intended, or the response says plainly
   that it did not land.
4. Armed against a read-only router home, the way DEF-049 was originally found: a denial control
   rather than a mocked failure.
5. Node's `control.ts` equivalent at parity, or the divergence declared in `surface.tsv`.

## Related

`DEF-049` in `M28-decision-docket.md`, whose §2 records the two halves already fixed and §2b the
refuted lead. `R18` — the failure branch destroying the approved tools — writes the same row from
the other direction, and `ManifestBookkeeping.swift:38` documents that destruction in its own
table.
