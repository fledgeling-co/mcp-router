# Test Campaign External Effect Provider and Source Root Resolver

- origin: test-campaign vacuity checks and reckoning unmeasured audit · 2026-08-25
- audience: Quality engineers and test campaign maintainers
- platforms: n/a
- proposed-by-ai: false

## What and why
The test campaign configuration defines explicit source roots and maps external effect classes to concrete production code providers. Currently, the vacuity check reports that effect providers are named but not resolved because source roots are undeclared in the campaign registry. Resolving effect providers ensures guarantees about socket emissions and process lifecycles are validated against active code rather than passing vacuously.

## Acceptance sketch
- The test campaign configuration records explicit root directory paths for production source and test suites.
- Running the campaign vacuity validation check resolves every declared effect class to an existing code provider.
- Requirements that declare outbound socket or subprocess effects fail validation if no active provider is found.
- The published campaign evidence page displays verified provider mappings for all external effects.

## Assumptions made writing this
- Assuming effect providers are verified through static symbol resolution rather than requiring runtime instrumentation.
- Assuming external effect validation is enforced during standard campaign check passes.
