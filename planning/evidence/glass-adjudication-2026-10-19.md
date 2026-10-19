# Glass adjudication, 19 October 2026

**Result:** 26 failing checks across seven cases before this change, 24 after. The brief said 21; `planning/test-campaign/evidence/runs/glass-assert.json` at HEAD records 26, so the artifact's count is used here.

- **Superseded design, updated (16 checks before):** the shell's sidebar copy and menu map (M15, M22), and the Analyse now control (the analyst landed in 404d7832). Each assertion now states the design of record, with a dated note in `cases.json`.
- **Build contradicts the design of record (DEF-522, new):** after the update, the shipped digits ⌘1 through ⌘8 fail against DESIGN.md §8 and the mock, eight checks on each of CASE-0001 and CASE-0101. The direction of the fix is an owner decision.
- **Evidence and instrument faults (10 checks):** the Settings captures are misfiled as Insights (DEF-059, open). The `⌘,` key was corrected to the title the build and mock both carry.

## Verdict key

- **(a) superseded design.** The assertion was updated to the design of record, which states the value explicitly.
- **(b) product defect.** The build contradicts the design of record. Recorded as DEF-522; the assertion keeps the design value.
- **(c) evidence or instrument fault.** The assertion is still current design. No product verdict is made.

## Rows

| # | Case | Failing check, as recorded | Verdict | Evidence | After this change |
|---|---|---|---|---|---|
| 1 | CASE-0001 | window carries: Settings | (a) | M15 `29829e6b` (2026-08-22), "Settings stops being a row in the console and becomes a window of its own". PRD.md:515 "Nine boards". `evidence/ax/SURF-001.window.txt` has no Settings row. | Copy list is now the nine boards. Check removed. |
| 2 | CASE-0001 | shell chrome present in all 11 window dumps | (a) | Same copy list. No `evidence/ax/SURF-0*.window.txt` carries Settings. | Pass. |
| 3 | CASE-0001 | menu bar binds ⌘4 to Discover | (a), then (b) DEF-522 | DESIGN.md:717 at `ad8c5ec9` reads "Discover" as `⌘1`. Live menu: `evidence/ax/SURF-001.menu.txt:144` at `ad8c5ec9` reads "Discover", index `5`. | Now asserts `⌘1` to Discover. Fails against the build. |
| 4 | CASE-0001 | menu bar binds ⌘5 to Inbox | (a), then (b) DEF-522 | DESIGN.md §8's digit table (the table row 1 cites, anchored) binds `⌘8` to Inbox. Live menu: Inbox is index `6` in the same AX dump row 1 cites. | Now asserts `⌘8` to Inbox. Fails. |
| 5 | CASE-0001 | menu bar binds ⌘6 to Checks | (a), then (b) DEF-522 | DESIGN.md §8's digit table binds `⌘6` to Checks. Live menu: Checks is index `7`. | Now asserts `⌘6` to Checks. Fails. |
| 6 | CASE-0001 | menu bar binds ⌘7 to Cleanup | (a), then (b) DEF-522 | DESIGN.md §8's digit table binds `⌘7` to Cleanup. Live menu: Cleanup is index `8`. | Now asserts `⌘7` to Cleanup. Fails. |
| 7 | CASE-0001 | menu bar binds ⌘, to Settings | (c) instrument | `evidence/ax/SURF-001.menu.txt:84` reads `Settings…`, cmd char `,`, action `menuAction:`. The key was `Settings`, so the parser never matched. The mock titles it `Settings…` (`design/mcp-router-console.html:1355` at `ad8c5ec9` reads "Settings…"). | Key corrected to `Settings…`. Pass. |
| 8 | CASE-0016 | window title is Settings | (c) evidence | `evidence/ax/SURF-011.title.txt:1` reads `Insights`. The Settings capture was misfiled (DEF-059). | Unchanged. Fails. |
| 9 | CASE-0016 | window carries: Read from the router, not set here | (c) evidence | Copy present in source: `app/Sources/MCPRouterKit/Shell/SettingsPresentation.swift:67` at `ad8c5ec9` reads "Read from the router, not set here". The SURF-011 dump is Insights, so the copy is absent from it. | Unchanged. Fails. |
| 10 | CASE-0016 | window carries: no endpoint that rewrites the router's own configuration | (c) evidence | `SettingsPresentation.swift:68` at `ad8c5ec9` reads "has no endpoint that rewrites the router's own configuration". Same dump as row 9. | Unchanged. Fails. |
| 11 | CASE-0016 | window carries: Forget the stored token | (c) evidence | `SettingsPresentation.swift:220` at `ad8c5ec9` reads "Forget the stored token" (`forgetAction`). Same dump as row 9. | Unchanged. Fails. |
| 12 | CASE-0170 | the Analyse now control is drawn disabled | (a) | `404d7832` (2026-08-29), "feat(analyst): the session analyst PRD §6 specifies, and the button that never did anything". `planning/specs/spec-F7.md:71`: "`Analyse now` is enabled exactly when the router serves the route." `evidence/ax/SURF-026.window.txt:78` reads `Analyse now`, enabled field `1`. | Expects enabled. Pass. |
| 13 | CASE-0171 | the Analyse now control is drawn disabled | (a) | Same as row 12, raster half. | Expects enabled. Pass. |
| 14 | CASE-0176 | the Analyse now control is drawn disabled | (a) | Same as row 12. | Expects enabled. Pass. |
| 15 | CASE-0176 | SURF-026/action-tracks-state: populated reading draws `Analyse now` disabled | (a) | Same as row 12. The relation still requires one action per reading, pairwise distinct. | Expected `("Analyse now", "1")`. Pass. |
| 16 | CASE-0101 | window carries: Settings | (a) | Same as row 1, raster case. | Copy list is now the nine boards. Check removed. |
| 17 | CASE-0101 | shell chrome present in all 11 window dumps | (a) | Same as row 2. | Pass. |
| 18 | CASE-0101 | menu bar binds ⌘4 to Discover | (a), then (b) DEF-522 | Same as row 3. | Fails. |
| 19 | CASE-0101 | menu bar binds ⌘5 to Inbox | (a), then (b) DEF-522 | Same as row 4. | Fails. |
| 20 | CASE-0101 | menu bar binds ⌘6 to Checks | (a), then (b) DEF-522 | Same as row 5. | Fails. |
| 21 | CASE-0101 | menu bar binds ⌘7 to Cleanup | (a), then (b) DEF-522 | Same as row 6. | Fails. |
| 22 | CASE-0101 | menu bar binds ⌘, to Settings | (c) instrument | Same as row 7. | Pass. |
| 23 | CASE-0111 | window title is Settings | (c) evidence | Same capture as row 8, raster half (DEF-059). | Unchanged. Fails. |
| 24 | CASE-0111 | window carries: Read from the router, not set here | (c) evidence | Same as row 9. | Unchanged. Fails. |
| 25 | CASE-0111 | window carries: no endpoint that rewrites the router's own configuration | (c) evidence | Same as row 10. | Unchanged. Fails. |
| 26 | CASE-0111 | window carries: Forget the stored token | (c) evidence | Same as row 11. | Unchanged. Fails. |

After the change, the failing checks are the eight digits on CASE-0001 and CASE-0101 (DEF-522) and the four Settings-window checks on CASE-0016 and CASE-0111 (DEF-059). The checked count rose from 429 to 435 because the copy and menu lists gained entries.

## Changes

- `planning/test-campaign/bin/glass-assert.py`: SURF-001 copy list and menu map now follow DESIGN.md §8 and the mock; `Settings` key corrected to `Settings…`; SURF-026 `Analyse now` expected enabled (controls and relation).
- `planning/test-campaign/cases.json`: dated notes appended to CASE-0001, CASE-0101, CASE-0170, CASE-0171, CASE-0176. Their status fields are unchanged.
- `planning/test-campaign/inventory.json`: DEF-522 added (REQ-003, SURF-001).
- `planning/test-campaign/evidence/runs/glass-assert.json`: regenerated by the clean run. No file under `evidence/ax`, `evidence/shots` or `captures.json` was edited.

## Open

- **DEF-522, owner decision.** Either the build moves to DESIGN.md §8, or DESIGN §8 and the mock move to the build. DESIGN.md:733 at `ad8c5ec9` reads "`⌘5` and `⌘9` belong to Harnesses and Insights, which M22 ships", so the build does not match what the document says M22 would ship. DEF-058 says the product is right on these four cases; that does not hold for the digits, and DEF-058 is left unedited.
- **DEF-059, owed to a macOS host.** Re-capture the Settings window and give SURF-011 a route to the Settings scene. Until then the four CASE-0016 and CASE-0111 checks stay red.
- **Analyst enablement is stated only in spec-F7.** DESIGN.md has no analyst section, so the enabled rule rests on spec-F7 §3 item 8 alone.

## Verification

```
python3 planning/test-campaign/bin/glass-assert.py      # before (HEAD assertions, original evidence)
  checked=429 failures=26 cases=38 (surfaces 11, states 7, relations 3)
python3 planning/test-campaign/bin/glass-assert.py      # after
  checked=435 failures=24 cases=38 (surfaces 11, states 7, relations 3)
python3 planning/test-campaign/bin/glass-assert.py --decoy SURF-026
  checked=435 failures=42   (CASE-0170, CASE-0171 and CASE-0176 go red)
python3 planning/test-campaign/bin/glass-assert.py --relation-decoy SURF-026/one-fixed-action
  checked=435 failures=27   (CASE-0176 goes red)
```
