# Reverify F8: cross-harness skill and plugin profile synchronisation

**Verdict: RETIRED.**

- **Scope.** DEF-361, retrospective verdict for `N4` (merge `ceb59c61`).
- **Requirements, derived from documents alone.** Brief `planning/features-to-triage/F-cross-harness-skill-sync.md` (acceptance lines 14–17 of the brief's "Acceptance sketch"); spec `planning/specs/spec-F8.md` (§2, §3, §4 A1–A8, §5); plan `planning/plans/plan-F8.md`; LEDGER and ORCHESTRATOR rows F8. The code was not opened until this table was drafted.
- **Tree checked.** main at `fe3b09b9`. Relevant paths are unchanged since the worktree base `63d7e208`.
- **Why RETIRED.** The `/profiles` family exists only in the Swift router. `plan-retire-swift-router.md` (Feature inventory, row "F8 profiles") says **DROP** (decision 1). `app/Retired/README.md` records the retirement. Same caveat as F5: decision 1 is still listed for the owner to confirm.

## Requirements

| # | Requirement | Source | Verdict | Evidence |
|---|---|---|---|---|
| B1 | A profile manager in the Mac app creates and toggles skill bundles | brief acceptance 1 | RETIRED | Not built. Spec §5 `F8-C2` defers the board, and no mock exists. Client grep on `fe3b09b9`: no `profiles` call in `app/Sources/MCPRouterUI`, `app/MCPRouter`, `app/windows` or `app/MCPRouterIOS`. |
| B2 | Reconcile harness configuration files to match the active profile | brief acceptance 2 | RETIRED | Refused by design. `case refused(reason: String)`, `app/Sources/RouterCore/Profiles/ProfileProjection.swift:24` at `fe3b09b9`. Spec §3 says a harness MCP config write is refused under R7 §7. |
| B3 | Detect drift between harnesses and show a visual diff | brief acceptance 3 | RETIRED | `case dangling(target: String)`, `app/Sources/RouterCore/Profiles/SkillRootInventory.swift:20` at `fe3b09b9`. This is the classification only. The rendered diff is `render()` in `ProfileProjection`, and no client displays it. |
| B4 | Single-click sync aligns all harnesses | brief acceptance 4 | RETIRED (refused in spec) | Spec §3 refuses it for two reasons: the router does not write another program's configuration, and nothing makes a running session re-read the bytes. Harness-write gate, run on this tree: `scripts/lint/no-harness-skill-writes.sh` at `c85663906be95affab1ef193db15c4b9f993e7f0` (historical source) printed `no-harness-skill-writes: 521 file(s) read, 4 in the seam, 0 refused`, exit 0. |
| A1 | A profile is created, read, listed and removed, and removal is recoverable | spec §4 A1 | RETIRED | `public func remove(name: String) -> ProfileRemoveOutcome {`, `app/Sources/RouterCore/Profiles/ProfileStore.swift:164` at `fe3b09b9`. Recoverable removal: `return .removed(destination)`, `app/Sources/RouterCore/Profiles/ProfileStore.swift:191` at `fe3b09b9`. Lane `scripts/acceptance/f8-profiles.sh` is covered in A7. |
| A2 | A malformed name or escaping path is refused before any byte is written | spec §4 A2 | RETIRED | `guard ExtensionNaming.isWellFormedName(record.name) else {`, `app/Sources/RouterCore/Profiles/ProfileStore.swift:101` at `fe3b09b9`. `if let refusal = Self.refuseSelection(record) { return .refused(refusal) }`, `app/Sources/RouterCore/Profiles/ProfileStore.swift:108` at `fe3b09b9`. |
| A3 | A harness skill root is classified entry by entry, with dangling reported as dangling | spec §4 A3 | RETIRED | `case dangling(target: String)`, `app/Sources/RouterCore/Profiles/SkillRootInventory.swift:20` at `fe3b09b9`. `case linked(target: String)` sits at line 18. |
| A4 | A harness with no skill root reads `absent`, which differs from a root with no entries | spec §4 A4 | RETIRED | `A harness with no known root is absent from the result rather than present and empty.`, `app/Sources/RouterCore/Profiles/SkillRootInventory.swift:87` at `fe3b09b9`. |
| A5 | Every projected step carries its reach; a harness MCP config step is `refused` | spec §4 A5 | RETIRED | `case durable(note: String)`, `app/Sources/RouterCore/Profiles/ProfileProjection.swift:17` at `fe3b09b9`. Refusal at line 24, as cited in B2. |
| A6 | Nothing in `app/Sources` writes a harness skill root | spec §4 A6 | RETIRED (gate still runs) | `scripts/lint/no-harness-skill-writes.sh` at `c85663906be95affab1ef193db15c4b9f993e7f0` (historical source): `521 file(s) read, 4 in the seam, 0 refused`, exit 0. Its selftest, `scripts/lint/no-harness-skill-writes-selftest.sh` at `c85663906be95affab1ef193db15c4b9f993e7f0` (historical source): `no-harness-skill-writes-selftest: 14 passed, 0 failed`, exit 0. |
| A7 | The daemon answers the `/profiles` family | spec §4 A7 | RETIRED | Lane `scripts/acceptance/f8-profiles.sh` exited 2: `environment: no MCPRouterCLI at /Volumes/LLMs/Dev/mcp-router-wt/reverify-3/app/.build/debug/MCPRouterCLI (run: make build-cli-debug)`. The binary is not declared in `app/Package.swift`, so it cannot be built. |
| A8 | No method outside the token gate's set is served by this family | spec §4 A8 | RETIRED | `return method == "POST" || method == "DELETE" || method == "PATCH"`, `app/Sources/RouterCore/Control/ControlAPIRequest.swift:86` at `fe3b09b9`. The profile route's write is `case "POST":`, `app/Sources/RouterCore/Control/ControlProfiles.swift:59` at `fe3b09b9`. |
| R1 | `/profiles` is not served by the TypeScript router | spec §2, plan | RETIRED | `isControlPath` in `src/control.ts` lists `/harnesses` (line 469) and `/skills` (line 477) at `fe3b09b9`, and no `/profiles`. `git grep` for `'/profiles` on `fe3b09b9` returns nothing in `src`. |

## Shipped clients

No call to `/profiles` in any shipped client (see B1). No DEF is filed, because no shipped client calls a route the TypeScript router no longer serves.

## Tests and lanes

- `swift test` was run once for the family with F5, R22 and R27 (see the F5 report): `warning: No matching test cases were run`, `EXIT=0`. `ProfileStoreTests`, `SkillRootInventoryTests`, `ProfileProjectionTests` and `ControlProfileRoutesTests` are not in any declared target, so none ran.
- `scripts/acceptance/f8-profiles.sh`: exit 2, environment message as quoted at A7.
- `planning/test-campaign/cases.json` records CASE-0262 to CASE-0264 as archived proofs of this item. No live run on this tree backs them.

## Open

1. Owner confirmation of plan decision 1, as in F5.
2. A stale comment: `is why the route is a`, `app/Sources/RouterCore/Profiles/ProfileStore.swift:97` at `fe3b09b9`, says the route is a PUT. The route is POST (row A8), and `isMutating` excludes PUT (row A8). The comment is stale.
3. Case-ID collision, shared with F5. `cases.json` gives CASE-0262 to 0264 to REQ-030 (this item). `cases.in.json` gives the same three IDs to REQ-007 (F5). Not renumbered here; see the F5 report, open item 4. It sits in code that is retired, so it is recorded here and not fixed.
