# Differential — mcp-router vs `design/mocks/prototype.html`

Compared 2026-08-19 against AX dumps in `evidence/ax/` (window-scoped, app backgrounded) and the prototype NAV / pane templates. Not a pixel diff. Subtracted: window chrome (close / zoom / minimise, Hide Sidebar), live tenant data (call rows, fixture server names, skill marketplace rows), and already-decided copy (Checks is not an eval runner — `DESIGN.md` and CASE-0014).

Instrument ceiling: native macOS exposes no cross-process computed style, so the resolved-style vector is `n/a` on macos-glass. Geometry is window frame only (980×620, origin 180,184) against a mock viewport of 1440×900 — different window, not a layout verdict.

Judgeable pairs, as this section was first written on 2026-08-19: 10 of 17. Superseded — see **Second pass** below.

## Structure

Sidebar groups and destinations match the prototype NAV:

| Prototype | Build AX (every Mac board dump) |
|---|---|
| Running → Activity, Servers, Skills | AXHeading Running; buttons Activity, Servers, Skills |
| Library → Discover, Inbox, Checks, Cleanup | AXHeading Library; buttons Discover, Inbox, Checks, Cleanup |
| Settings | button Settings |

The evals id in the mock is labelled Checks. The build window title on SURF-006 is Checks, not Evals.

Missing as a control, not as a route: the prototype pairing sheet (`<h4>Pair iPhone</h4>`, QR, `K7QN·4FMD`, expiry, “Can't scan? Type a code”). The build sheet on SURF-010 is titled Pair iPhone and contains no code, no QR, no expiry. CASE-0010 / CASE-0110 fail on that; DEF-001.

The prototype Settings section “Paired devices” (Luke's iPhone, Unpair, Pair another device…) is absent from SURF-011 AX (Token, Menu bar, Warm set, Control token — zero hits for Pair / Unpair / iPhone). Same defect, different surface.

## Vocabulary

| Surface | Prototype | Build | Arbitration |
|---|---|---|---|
| SURF-006 Checks | `PANES.evals` is still a skill-eval runner: “pr-summariser · 8 cases”, “3 of 8 passed”, Run again | “The checks MCP Router runs itself… No model-graded evaluation exists in this product.” | **Mock is wrong.** The build matches REQ / DESIGN. CASE-0014 records the copy. |
| SURF-010 Pairing | 8-character Crockford `K7QN·4FMD`, treated as a password, expires | “Pairing is not available in this build” / “this build ships no way to listen for one” | **Build is wrong** relative to the design of record. Honest about I5; the control the design specifies is not rendered. |
| SURF-008 Inbox empty | “Nothing waiting” + “The phone can queue and nothing else — a lost or unlocked phone still cannot install code on this Mac.” | Same sentences in AX | Agree. |
| Sidebar rest | “Child processes” / “of N declared” / “last 60s · peak” | “1 of 4 declared servers running” / “last Ns · peak 1” | Same quantities, different wording. Both legitimate; no token source pins the label. |
| SURF-002 Servers | “Add server…” | “Add server…” | Agree. |
| SURF-005 Discover | sessions on Smithery | “2,984 sessions”, “Most used on Smithery” | Agree on the unit. CASE-0023. |

## Geometry

Not compared. AX frames are the window and outline rows; the mock is an HTML layout at a different size. A banded comparison would need a shared coordinate system this lane does not have.

## Uncompared

SURF-009 menu-bar popover: mock exists (`SURF-009.png`); NSStatusItem is not an AXPress target while backgrounded, so the build half was never photographed. CASE-0004 / 0006 / 0109 are `n/a` for that structural reason.

SURF-012–014 iOS: **no longer uncompared.** This paragraph recorded that the build half was the Settings boot PNG — not Discover, not Triage, not pairing. That stopped being true when the iOS on-glass lane shipped on its own device (DEF-020): Discover, Triage and the Pair Mac preflight are photographed in `evidence/shots/ios/`, attributed in that directory's `captures.json`, and asserted by CASE-0020 through CASE-0125. Kept here struck through rather than deleted, because a differential that silently loses its own false claims is not a record.

SURF-015–017 are daemon / HTTP / harness. No visual design of record, by construction.

## Disk vs registry

`surfaces.json` on disk lists 24 rows (Mac review sheet, add-server, held-change, iOS tabs split). `campaign.py check` enumerates 17 from the registry. The gate uses 17. The extra seven are not silently covered.

## Second pass — 2026-08-20

Three things moved since the section above was written, and one claim in it went false.

**The pair map was under-reporting.** `evidence/shots/pairs.json` — what `witness-worklist.py` reads — listed 17 pairs against a 20-surface registry and named absent build halves for four more. DEF-010 has the detail. Corrected count: **16 of 20 pairs now hold both halves.** Three (SURF-015–017) have no visual design of record by construction. One (SURF-009, the menu-bar popover) has no build half, for the structural reason its cases already carry: `NSStatusItem` is not an AXPress target while the app is backgrounded, and this campaign never activates.

Read `witness-worklist.py`'s own `comparable fraction: 85%` with that in mind — it counts a pair as judgeable when a *reference* exists, so SURF-009 is inside its numerator and has nothing to judge. 16 of 20 is the number with two halves.

**Three states gained a build half that had none.** `SURF-007/cleanup-skills`, `SURF-007/provenance-sheet` and `SURF-010/unavailable`, asserted by CASE-0138 through CASE-0143. Each carries a local control the surface pairs do not need — the state's copy must be **absent** from that same board's default dump — because both the state and the default photograph the same board, and a predicate passing on both would be describing the board rather than the state.

**SURF-010's structural claim above still holds.** Re-read against the fresh dump: the build sheet says `Pairing is not available in this build` and `no way to listen for one. Nothing is wrong with your phone or your network.` No code, no QR, no expiry. The design of record specifies all three. CASE-0010 / CASE-0110 stay failed; DEF-001.

**A shared reference, deliberately.** `mock/SURF-001.png` and `mock/SURF-002.png` are byte-identical (sha 1b1f3c84) because both were captured from `prototype.html?pane=servers&only=mac`. That is correct rather than a defect — SURF-001 is the chrome every destination is drawn inside, so there is no separate "shell pane" to photograph — but it means one image backs two reference halves, and the build halves are what must differ. They now do: SURF-001's pair points at the sidebar crop `SURF-001.shell.png` (sha c45c098a) rather than at `SURF-001.build.png` (sha f221cce5), which is byte-identical to SURF-002's.

**Byte-identity is not an oracle on the iOS lane.** Two XCUIScreenshots of the same Pair Mac preflight — `SURF-014.ios.camera-preflight.png` and `UNASSERTED.ios.after-tapping-pair-mac.png` — are visually indistinguishable and differ in sha256 (49be996c vs 6c58ee19). On the Mac lane, `SURF-007.cleanup-skills.png` was byte-identical across two consecutive capture runs and that stability is cited as evidence. The two lanes do not support the same claim, and the second image is left asserted by nothing rather than turned into a case that would count one check twice.

**Still uncompared, unchanged:** the resolved-style vector is `n/a` on macos-glass because no macOS API exposes a cross-process computed style, and geometry is window-frame-only against a mock at a different viewport. Neither is a pixel diff and neither becomes one.
