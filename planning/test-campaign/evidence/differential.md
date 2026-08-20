# Differential — mcp-router vs `design/mocks/prototype.html`

Compared 2026-08-19 against AX dumps in `evidence/ax/` (window-scoped, app backgrounded) and the prototype NAV / pane templates. Not a pixel diff. Subtracted: window chrome (close / zoom / minimise, Hide Sidebar), live tenant data (call rows, fixture server names, skill marketplace rows), and already-decided copy (Checks is not an eval runner — `DESIGN.md` and CASE-0014).

Instrument ceiling: native macOS exposes no cross-process computed style, so the resolved-style vector is `n/a` on macos-glass. Geometry is window frame only (980×620, origin 180,184) against a mock viewport of 1440×900 — different window, not a layout verdict.

Judgeable pairs: 10 of 17 (`witness-worklist.py`: comparable fraction 59%). SURF-009, SURF-012–014 have a mock half and no attributed build half. SURF-015–017 have no visual design of record.

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

SURF-012–014 iOS: mocks exist. Simulator has no Mac AX tree; MCPRouterIOS ships no URL scheme; Maestro on the booted sim asserted “Settings” visible but pulled 1Password frontmost, which this campaign refuses. Build half remains the Settings boot PNG, which is not Discover / Triage / pairing.

SURF-015–017 are daemon / HTTP / harness. No visual design of record, by construction.

## Disk vs registry

`surfaces.json` on disk lists 24 rows (Mac review sheet, add-server, held-change, iOS tabs split). `campaign.py check` enumerates 17 from the registry. The gate uses 17. The extra seven are not silently covered.
