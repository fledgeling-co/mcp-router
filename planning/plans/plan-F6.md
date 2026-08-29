# Plan F6 — the update check, and the catalogue it cannot see past

**Spec:** `planning/specs/spec-F6.md` · **Branch:** `ai/n2` · **Worktree:** `.worktrees/N2`
**Tier:** Standard. Router-side only; no UI slice, so the `design` stage is skipped with the reason
in spec §5 — the three surfaces the brief names are owned by M19, M4/M3/M20 and I3, and each is
already specified.

The spec's §1 measurement is the plan's premise: `updateAvailable` fires **0 times out of 127** on
the real machine and the one difference that exists points backwards. So the build order below puts
the verdict type and its eight arms first, and the route last — because the route is worth nothing
if the type it serialises collapses eight answers into a boolean.

---

## D1 · Ordering, or declining to

`SemanticVersion` — parse `major.minor.patch` with an optional trailing suffix, compare, and return
`nil` for anything that is not two comparable semvers. It is the only place `updateAvailable` can
be produced, so it is where the wrong-way bug of §1.1 has to be impossible.

Written as `compare(_:_:) -> ComparisonResult?` rather than `isNewer(_:_:) -> Bool`, because a
boolean has nowhere to put *these two cannot be ordered* and would have to answer `false` — which
is the same answer as *not newer*, and the two are the distinction this item exists to keep.

**Watched red:** three SHA pairs, a semver against a SHA, and `2.0.0` against `1.0.0` in both
argument orders.

## D2 · The catalogue

`MarketplaceCatalogue.read(text:)` — parse a marketplace descriptor into `[CatalogueOffer]` through
`JSONParser`, never `JSONSerialization` (`scripts/lint/no-wire-codable.sh` covers this directory).
It records `declaredNoVersion` as a count, so a catalogue that names 291 plugins and versions 14 of
them says so rather than looking like a catalogue of 14.

An offer with no `name` is skipped; a `plugins` member that is not an array is `nil`, matching
`ExtensionDescriptor`'s existing rule for a marketplace descriptor.

## D3 · The descriptor gains a version

`ExtensionDescriptor.Reading.version`, read by the two paths that already read `name`. Then
`ExtensionRecord.version`, and `ControlExtensionsJSON` carries it — `null` when absent, never
omitted, so a reader distinguishes *declares none* from *key not written* (`DESIGN.md` §6).

`ExtensionStoring.descriptorText(_:name:)` is added to the protocol and implemented on
`DiskExtensionStore` by the path `record` already builds. The name goes through
`ExtensionNaming.isWellFormedName` first, exactly as `read` does; there is no path parameter, so
the method cannot address anything but the descriptor.

**Every existing conformer must gain it** — the test doubles in `ControlExtensionRoutesTests` are
in that set, and M4's merge is the fleet's recorded case of a protocol growing a method while a
double in another file kept compiling on its own branch.

## D4 · The verdict

`ExtensionFreshness.compare(kind:name:installedVersion:catalogue:)` → `FreshnessVerdict`. The
eight arms of spec §3, in the order that makes each unreachable state impossible:

1. no catalogue at all → `noCatalogue(reason)`
2. catalogue read, entry absent → `notOffered`
3. offer declares no version → `catalogueDeclaresNoVersion(installed)`
4. installed declares no version → `installedDeclaresNoVersion`
5. equal strings → `current`
6. both orderable, available greater → `updateAvailable`
7. both orderable, available lesser → `catalogueBehind`
8. otherwise → `unorderable`

Rows 3 and 4 are before 5 deliberately: two absent versions are not "equal versions".

## D5 · The report

`ExtensionFreshnessReport.build(store:kinds:staleAfterMs:now:)` walks the store's three kinds, reads
each entry's descriptor, resolves the catalogue for a plugin from its `@marketplace` suffix, and
collects the per-catalogue reading — path, `newestModifiedMs` via `ExtensionStamp.measure`, `ageMs`,
`stale`, `refreshable`.

`refreshable` is `true` when the marketplace entry holds a `.git` directory. Two of the ten on this
machine do not, and a report that implied every catalogue could be refreshed would be wrong for 2
of 10 in the place a caller decides what to do next.

Summary counts: `total`, `updatesAvailable`, `compared`, `uncomparable`, `staleCatalogues`.
`compared + uncomparable == total` is asserted, so a verdict added later without a classification
reddens the suite instead of silently landing in neither.

## D6 · The route

`ControlUpdates.swift` — `GET /extensions/updates`, guarded by `deps.extensions` and answering the
503 sentence the `/extensions` family already answers when the store is absent. It must be routed
**before** `routeExtensions`' `:kind` match, or `updates` parses as a kind and answers
`404 no extension kind named "updates"`. That ordering is asserted, because it is the whole
difference between the route existing and not.

`ControlUpdatesJSON.swift` for the body. `planning/parity/surface.tsv` gains `div-f6-updates`.

## D7 · The lane

`scripts/acceptance/f6-updates.sh` over the daemon's own socket with a scratch
`MCP_ROUTER_HOME`, enrolled in `acceptance-lanes.sh`. It exists for the class R28 and R31 both
record: `ControlDeps.extensions` is optional, `registry` and `authFlow` both shipped `nil` in
`RouterServiceDispatch` with a green unit suite, and that is a 503 on every route in the family
that no unit test can see.

It drives all eight verdicts against a fixture store built with `mkdir` and `printf` — never
through the API — then edits the fixture catalogue on disk and requires the reply to change, which
is what proves the reading is of the bytes rather than of a cache. And it asserts the three
mutating verbs are 405 and that the store's file count is unchanged across the run (A3).

## D8 · Cases and evidence

Case ids allocated above the maximum read from `main`'s `planning/test-campaign/cases.json`
and `cases.in.json` — the authored input, whose maximum is HIGHER: `cases.json` holds 142 rows to `CASE-0222`, `cases.in.json` 98 rows to **`CASE-0261`**, and 0261 is the registry maximum. Allocated: **CASE-0276 … CASE-0280**. Every new file gets a sweep
disposition row at its commit. Evidence lands in `planning/evidence/F6/` with the producing command
in each header; no raw gate capture is committed.

---

## Risks

* **The zero-update machine.** Every `updateAvailable` assertion is fixture-driven by necessity. The
  mitigation is that each arm is watched red first and the record is committed, not that the suite
  is large.
* **Route ordering.** `/extensions/updates` and `/extensions/:kind` collide by shape. Asserted in
  both directions — the route answers, and `GET /extensions/nonsense` still 404s as a kind.
* **A protocol method breaking a double in another file.** D3 names it; the whole-tree `make lint`
  and `make test` before reporting is what catches it.
