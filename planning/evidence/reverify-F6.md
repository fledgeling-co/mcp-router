# reverify-F6 — marketplace update checker (DEF-361)

**Verdict: NEEDS-WORK.** The update-check core is built and tested (ported to TypeScript at `75d66ceb`). Five brief requirements are not met on main: the periodic check, the changelog preview, the Servers and menu-bar indicators, the Update and Update All actions, and iPhone. Two of those are spec-scoped to other items; the rest are not.

Checked against main at `63d7e208`, by branch `ai/reverify-2`, 2026-10-20.

**Method.** Requirements were derived from `planning/features-to-triage/F-marketplace-auto-update-checker.md` and `planning/specs/spec-F6.md` before code was read. Verdicts: MET = main does what the line says; PARTIAL = some of it; NOT MET = absent on main; DEFERRED = the spec names an owner and puts it out of scope (still unmet on main, so it is reported, not hidden). The spec's own §4 table marks A5–A7 "not built"; this audit counts the brief lines as requirements, so they stay visible.

**Base and drift.** Line references are at `63d7e208`, the tree this branch was cut from. Main has since advanced 21 commits (to `7432a5e1` at the time of the check). The files this item depends on are unchanged on main except `src/control.ts`, `src/insights.ts` and `src/router.ts` (the usage-window and inbox merges); the analyst routes there moved to lines 1038, 1044 and 1062 with the same logic. The audited Swift files are unchanged.

**Retirement check (DEF-361 requirement).** F6 was a Swift-only route and was ported under `plan-retire-swift-router.md` P3. The TypeScript router serves `GET /extensions/updates` (`src/control.ts:522`, `src/extension-routes.ts:55`). The Mac client's one call is at `app/Sources/MCPRouterKit/Control/LiveControlAPIClient+Extensions.swift:32`, and it is served. Windows and iPhone make no call. No dead control was found, so no DEF was filed.

| # | Requirement | Source | Verdict | Evidence |
|---|---|---|---|---|
| F6-1 | Eight freshness verdicts; only `update-available` is an update; `catalogue-behind` is never reported as an update | spec-F6.md:57 (§1.1), spec-F6.md:135 (§2.1) | MET | `src/extension-updates.ts:22-47` (`'update-available'`, `'catalogue-behind'`, `hasUpdate: state === 'update-available'`). `test/extension-updates.test.ts:116` "V3 — each of the eight verdicts is reached, and only update-available is an update" — `ok 121` in the npm run below. Port commit `75d66ceb`. |
| F6-2 | A version that is not orderable (git SHA) is `unorderable`; no string comparison, no `0.0.0` normalisation | spec-F6.md:83 (§1.3) | MET | `src/extension-updates.ts:90` (`if (!left \|\| !right) return null;`), `:192` (`'unorderable'`). `test/extension-updates.test.ts:96` "V1 — a version is three numbers with an optional suffix, and anything else is not parsed". |
| F6-3 | `GET /extensions/updates` takes `kind`, `staleAfterMs` (default 86400000) and `name`; body carries per-entry fields, the catalogue block and the five-count summary | spec-F6.md:154 (§2.2) | MET | `src/extension-routes.ts:72-86` (`function updates(...)`, `DEFAULT_STALE_AFTER_MS`). `test/extension-routes.test.ts:556` "R13 — kind narrows the rows, name asks about one entry, and a bad window or kind is refused" — `ok` in the npm run. |
| F6-4 | Read-only (A3): GET only; other verbs refused; nothing written | spec-F6.md:212 (A3); brief:19 | MET | `src/extension-routes.ts:55` (`return method === 'GET' ? updates(...) : null;`). `test/extension-routes.test.ts:543` "R12 — a mutating verb on /extensions/updates is 405 and changes nothing". |
| F6-5 | No network, no child process, no timer in the check (A4 reinterpreted) | spec-F6.md:171 (§2.3); brief:20 | MET | `src/extension-updates.ts:10` ("It reads the store and nothing else. It reaches no network and spawns no child"). `test/extension-updates.test.ts:252` "buildFreshnessReport". |
| F6-6 | Staleness: a catalogue older than `staleAfterMs` is `stale`; `current` against a stale catalogue stays `current` and carries its age | spec-F6.md:93 (§1.4) | MET | `src/extension-updates.ts:388` (`stale: age === null ? false : age > this.staleAfterMs,`). `test/extension-updates.test.ts:208` "R2 — a catalogue older than the window is stale, and an unknown age is reported rather than assumed stale". |
| F6-7 | Acceptance oracle: the eight verdicts exercised, and `scripts/acceptance/f6-updates.sh` | spec-F6.md:210 (A1) | PARTIAL | The TS suite covers all eight verdicts (F6-1). `scripts/acceptance/f6-updates.sh` exists but was **not run** here: it needs a live daemon socket. |
| F6-8 | Brief: "Displays pending updates" | brief:9 | MET | `app/Sources/MCPRouterUI/Boards/SkillUpdatesSection.swift:9` (`struct SkillUpdatesSection: View {`), mounted at `app/Sources/MCPRouterUI/Boards/SkillsBoard.swift:119`. Commit `727bd392`. `app/Tests/MCPRouterUITests/SkillsUpdatesModelTests.swift:18` "showsUpdatesSectionWhenOffersExist" — suite "The Skills board's update check and Promote gate" passed in the Swift run below. |
| F6-9 | Brief: "Periodic background check … at user-configured intervals" | brief:12; spec-F6.md:171 (§2.3: "The cadence lives with whoever polls") | NOT MET | A search of `app/Sources`, `app/windows`, `src/`, `scripts/` and every plist found no timer, poller, agent or launchd job that calls the check. The check runs when the Skills board loads (`app/Sources/MCPRouterUI/Boards/SkillsBoardModel.swift:127`). The spec assigns the cadence to "the Mac app's timer, or an existing agent", and neither exists. Owner decision needed: build the poller, or accept on-demand checks. |
| F6-10 | Brief: GFM changelog preview of an available update, rendered in `CapabilityDocumentSheet` | brief:13; spec-F6.md:214 (A5), :227 (§5: owner M19) | NOT MET | `CapabilityDocumentSheet` is constructed only for server documents (`app/Sources/MCPRouterUI/Boards/ServerDocumentSheet.swift:29`). Update changelogs render as plain text in `SkillUpdatesSection` and `HeldVersionSheet`, with no path into the document sheet. M19 built the renderer; nothing passes it update data. |
| F6-11 | Brief: update indicators on the Skills **and Servers** boards and the menu bar | brief:14; spec-F6.md:215 (A6), :228 (§5: owners M4, M3, M20) | PARTIAL | Skills: yes (F6-8). Servers board and menu-bar status item: no update indicator found in `app/Sources/MCPRouterUI/Boards/ServersBoard.swift` or `MenuBarStatusItem.swift`. |
| F6-12 | Brief: individual "Update" and global "Update All Skills" actions | brief:15 | PARTIAL | Individual promotion exists for a held version: `app/Sources/MCPRouterUI/Boards/SkillSheets.swift:138` (`Button("Promote to \(version)")`), tested by `app/Tests/MCPRouterUITests/SkillsWriteModelTests.swift:10` "promotesHeldVersionFromCache". A generic Update action is absent. Update All Skills is disabled as unbuilt: `app/Sources/MCPRouterKit/Shell/MenuCommandAvailability.swift:130` (`.updateAllSkills` in the `.featureUnbuilt` arm). Not deferred by the spec. |
| F6-13 | Brief: iPhone receives update notifications and queues updates for Mac review | brief:16; spec-F6.md:216 (A7), :229 (§5: owner I3) | NOT MET | No update handling in `app/MCPRouterIOS` (searched all Swift and plist files). Owned by I3 per the spec. |
| F6-14 | Parity record: the Swift-only divergence row is accurate | spec-F6.md:154 (§2.2 says the route "diverges from `src/control.ts`") | PARTIAL | `planning/parity/surface.tsv:143` still declares `div-f6-updates` as a Swift-only surface, although the TS router now serves the route. The row is stale. |

**Commands run (2026-10-20, on `63d7e208`):**

```
perl -e 'alarm shift @ARGV; exec @ARGV' 900 <harbourmaster>/governor-run --weight 2 --project reverify-2 --label "npm test" -- npm test
# tests 314
# suites 28
# pass 314
# fail 0
# cancelled 0
```

```
cd app && governor-run --weight 4 -- swift test --build-system native -j 4 --filter 'SkillsUpdatesModelTests|SkillsWriteModelTests|InsightsAnalystBoardTests|CapabilityDocumentSheetTests|PairingRouterCodeTests'
Test run with 36 tests in 5 suites passed after 0.148 seconds.   exit=0
```

Suites in that run that concern F6: "The Skills board's update check and Promote gate", "The held-version sheet's writes".

**Not run:** `scripts/acceptance/f6-updates.sh` (needs a live daemon socket); the Windows client (not built).

**Open for the owner.** F6-9 (the periodic check has no poller), F6-10 (the changelog preview is not wired), F6-11 (Servers and menu-bar indicators), F6-12 (Update All is `featureUnbuilt`), F6-13 (iPhone queue, owner I3), and the stale parity row F6-14.
