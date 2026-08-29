# M39 — acceptance record

One row per screen: screen · how it was verified · commit · result. Append, never rewrite. Read this
before testing anything (`ORCHESTRATOR.md`, *Only test a screen you changed*).

| Screen | How | Commit | Result |
|---|---|---|---|
| Mac pairing sheet — `Phase.live` | in-process: `swift test --filter 'PairingSheetTests\|MacPairingTests\|PairingExpiryTests'` from `app/`, 38 tests in 4 suites, exit 0; 14 mutation arms each watched red (`planning/evidence/M39/arming.md`) | `f0b6e0f` | pass, at the `structural` rung |
| Mac pairing sheet — `Phase.live` **on glass** | **not run.** Machine load ran 114–700 across 16 cores with eight runners live, and this run's stop rule is before verify | — | skipped, and reported as a skip |
| Mac pairing sheet — `.noEndpoint`, `.preparing`, `.expired`, `.failed` | not tested: neither addition renders outside `.live`, and no file behind those branches changed | `f0b6e0f` | not tested, cited rather than re-run |

## What a glass pass would have to do that this one did not

- **Photograph the arc.** `PairingExpiryRing` is `.accessibilityHidden(true)` by design — the label
  beside it carries the same fact in words — so an accessibility-tree sweep cannot see it at all. The
  only rung that can is `raster-visual`, which owes a capture method and a frame status.
- **Reach `Phase.live` at all**, which needs a Debug build with `MCPROUTER_PAIRING` set to a fixture
  scenario. A Release build cannot show this screen.
- **Drive the arc to more than one reading.** A single capture of a full ring is satisfied by a ring
  that never depletes. The service's `pairingLifetime()` is what makes a short window reachable in
  the running app, and it exists for exactly this.

`SURF-010`'s current capture — `evidence/shots/SURF-010.build.png`, taken 2026-08-20 — predates both
additions and is not evidence for either.
