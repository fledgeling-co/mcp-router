# plan-F8 — cross-harness skill profiles

**Spec:** `planning/specs/spec-F8.md` · **Tier:** Standard · **Branch:** `ai/n4`

## Slices

| # | File | What |
|---|---|---|
| 1 | `app/Sources/RouterCore/Profiles/ProfileRecord.swift` (new) | The record, its refusal type, and the `ProfileStoring` port. No Codable — hand-built `JSONValue`, as `no-wire-codable.sh` requires. |
| 2 | `app/Sources/RouterCore/Profiles/ProfileStore.swift` (new) | `DiskProfileStore` under `<router home>/profiles`. Read, list, write, remove-to-`.removed`. Refusals decided before any byte lands. |
| 3 | `app/Sources/RouterCore/Profiles/SkillRootInventory.swift` (new) | One harness skill root, classified entry by entry. `SkillRootReading` is the seam; `DiskSkillRoots` is the real one. Read-only. |
| 4 | `app/Sources/RouterCore/Profiles/SkillRootLocations.swift` (new) | Where each `MCPClient`'s skill root is, with the provenance of the reading — spec §1.1's table, transcribed the way `HTTPCapability.known(for:)` transcribes R7 §1.2. |
| 5 | `app/Sources/RouterCore/Profiles/ProfileProjection.swift` (new) | Profile × store listing × inventories → `ProfileStep`s carrying `ProfileReach`. `render()` in `ReconciliationPlan`'s not-a-patch shape. |
| 6 | `app/Sources/RouterCore/Control/ControlProfiles.swift` (new) | Route dispatch for the `/profiles` family. The write is a **POST**: `isMutating` is `POST \|\| DELETE \|\| PATCH` and PUT is not in it, so a PUT route here would be the first unauthenticated write in the API. |
| 7 | `app/Sources/RouterCore/Control/ControlProfilesJSON.swift` (new) | The bodies. Fixed member order; an unobserved figure is `null`, never `0`. |
| 8 | `app/Sources/RouterCore/Control/ControlToken.swift` | `/profiles` and `/profiles/` claimed by `isControlPath`. |
| 9 | `app/Sources/RouterCore/Control/ControlPorts.swift` | `ControlDeps.profiles` and `.skillRoots`, both optional for the reason `extensions` is. |
| 10 | `app/Sources/RouterCore/Control/ControlHandler.swift` | One arm in `routeReading`, not in `handle` — `handle` is at the complexity cap. |
| 11 | `app/Sources/RouterCore/Service/RouterServiceDispatch.swift` | Supply both in the one process that ships. The line the acceptance lane exists to see missing. |
| 12 | `app/Tests/RouterCoreTests/ProfileStoreTests.swift` (new) | A1, A2. |
| 13 | `app/Tests/RouterCoreTests/SkillRootInventoryTests.swift` (new) | A3, A4. |
| 14 | `app/Tests/RouterCoreTests/ProfileProjectionTests.swift` (new) | A5. |
| 15 | `app/Tests/RouterCoreTests/ControlProfileRoutesTests.swift` (new) | The routes through `ControlHandler.handle`. |
| 16 | `scripts/lint/no-harness-skill-writes.sh` (new) + selftest | A6. |
| 17 | `scripts/acceptance/f8-profiles.sh` (new), enrolled in `acceptance-lanes.sh` | A7 — the daemon's own socket. |
| 18 | `planning/parity/surface.tsv` | One declared-divergence row per new route. |
| 19 | `planning/test-campaign/cases.in.json`, `cases.json` | The campaign cases. |

## Test seams

`SkillRootReading` is a protocol so every state in spec §1.1 is reachable from a fixture: a root
that is absent, a root that is empty, a root holding a real directory, a root holding a live
symlink, and a root holding a **dangling** one. Only the last is the finding, and a developer's
own `$HOME` produces it by accident rather than on request — so the tests build their own roots
under a scratch directory with `FileManager.createSymbolicLink` and then delete the target.

`ProfileStoring` is a protocol for the reason `ExtensionStoring` is: `ControlDiff` supplies none,
and the routes must answer 503 rather than an empty list when it is absent.

**No test and no lane reads a real harness root.** Every root path in every test is inside a
`mktemp -d`; `DiskSkillRoots` takes its home directory as a parameter and the lane passes a
scratch one, the same discipline `div-m22-harnesses` records for `GET /harnesses`.

## What each new assertion must be watched failing on

Rule 11 of this fleet. Each of these is planted and observed red before it is trusted:

1. `dangling` — plant a live link, assert `linked`; delete the target, assert `dangling`. The same
   assertion must report both, so it cannot be a constant.
2. `absent` vs empty — a root that does not exist and a root that exists holding nothing must
   produce **different** values from the same call.
3. `refused` reach — a projection step for a harness MCP config must be `refused`; the control is
   a skill step in the same projection reading `durable`, so the enum is exercised on both sides.
4. The store's refusals — every refusal is followed by an assertion that `.staging` is empty and
   the listing is unchanged, because a refusal that half-wrote would pass a status check.
5. `C6` — the method invariant the PUT failure taught, parameterised over PUT, HEAD, OPTIONS and
   TRACE, watched red by restoring `case "POST", "PUT"`.
6. `no-harness-skill-writes.sh` — its selftest plants eleven subjects with the exit each must
   produce: a whole harness path beside a link, a path assembled a component at a time, a path
   named on one line and written on a later one, a mutation anywhere inside the read-only seam, a
   subprocess in the seam, a consumer of the seam's API that writes, a `//` inside a string that
   must not suppress the code after it, a comment naming both that must not fire, the router
   writing its **own** store, and two instrument failures. Plus **the known miss**, planted and
   expected to walk through: an applier split across two neutrally named files outside the seam.
   And a mechanical check that every alternative in the mutating vocabulary fires on a probe —
   which was itself watched failing, reporting a pass over eleven alternatives an unquoted
   `[^A-Za-z]` had silently emptied.

## Out of scope

Applying anything (F8-C1), the Mac board (F8-C2), the CLI verb (F8-C3), project scope (F8-C4).
The TypeScript router gains nothing: R28's store is Swift-only, so a `/profiles` family there
would select over a store that does not exist in that binary.
