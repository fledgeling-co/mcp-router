---
status: completed
shipped-by: cef3729
---

# Test Campaign Visual Capture Lineage and Unpublished Reason Catalog

- origin: test-campaign capture lineage gate checks · 2026-08-25
- audience: Test campaign maintainers and visual regression reviewers
- platforms: n/a
- proposed-by-ai: false

## What and why
All visual capture artifacts stored in the test campaign directory are cataloged with explicit subject bindings or recorded unpublished reasons. Currently, the capture lineage validation fails because unaccounted screenshots exist on disk that are neither published to the evidence wall nor annotated with reasons for omission. Completing the capture catalog ensures every visual artifact is verified against an intended surface without lingering orphan files.

## Acceptance sketch
- Every visual capture file in the campaign artifact directory corresponds to a published surface or an explicit unpublished reason.
- Running capture lineage validation checks passes cleanly without reporting unaccounted image files.
- Re-running the campaign capture pipeline purges obsolete intermediate frames automatically.
- The published evidence page displays verified visual provenance badges for all rendered captures.

## Assumptions made writing this
- Assuming orphan capture files should be explicitly cataloged or pruned rather than disabling the lineage check.
- Assuming visual captures are tied to specific surface identifiers through recorded target channels.
