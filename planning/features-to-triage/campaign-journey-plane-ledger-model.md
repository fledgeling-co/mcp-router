# Test Campaign Multi-Step Journey and Execution Plane Model

- origin: test-campaign gate checks and reckoning unmeasured ledger · 2026-08-25
- audience: Quality engineers and automated test maintainers
- platforms: n/a
- proposed-by-ai: false

## What and why
The test campaign registry declares multi-step user journeys and execution planes across all verified cases. Currently, the campaign checks report planes and journeys as undeclared, making it impossible to distinguish between tests running against in-memory stubs versus the live application on glass. Establishing explicit journey boundaries and plane models ensures multi-step user workflows are verified across all durable operational stages.

## Acceptance sketch
- Multi-step user workflows define explicit boundary cuts for request emission, server commitment, and user confirmation.
- Every verified test case declares its execution plane among in-tree doubles, local protocol listeners, or live on-glass builds.
- Campaign validation checks enforce that critical flows cannot be marked passing on in-memory doubles alone.
- The published evidence page visualizes journey completion progression across each defined boundary stage.

## Assumptions made writing this
- Assuming execution planes are declared per test case rather than globally per test file.
- Assuming critical user flows require live on-glass or local protocol peer verification to earn full evidence status.
