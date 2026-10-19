# Retired: the Swift router

**Decision.** On 2026-10-19 the owner retired the Swift router. TypeScript is the only router.
The owner also decided to keep the Swift code in the tree, unbuilt, and to delete it later.
The plan is `planning/plans/plan-retire-swift-router.md`, steps G2 to G4, as modified by the owner.

**Where the sources are.** Nothing was moved or deleted. The sources stay at their original paths,
and history is intact:

- `app/Sources/RouterCore/`: the Swift router's data layer.
- `app/Sources/MCPRouterCLI/`: the router verbs.
- `app/Sources/ControlDiff/`: the differential oracle that drove the Swift handler.
- `app/Tests/RouterCoreTests/`: the tests for all of the above. The `Pins/` fixtures are still read
  by a live test in `app/Tests/MCPRouterUITests/`, which is why this directory did not move.

**What no longer builds.** `app/Package.swift` no longer declares those four targets, so SwiftPM
does not compile them. It also no longer declares the MCP Swift SDK dependency, which only
`RouterCore` used. The Mac and iOS apps do not import `RouterCore`, so they build without it.

**What the gates no longer run.** `make test` runs the MCPRouterKit and MCPRouterUI suites only.
`make lint` no longer runs `planning/carrier-parity-gate.py` or the pool mutation self-test. The
`make` targets for the Swift parity harness, the Swift mutation gate and the cutover streak were
removed. Their scripts stay in the tree, as listed in the plan.

**To build it again.** Re-declare the four targets in `app/Package.swift`, and re-add the SDK
dependency at the exact version the manifest carried before this change
(`git log -p -- app/Package.swift` shows it). Then restore the `make` targets from the same history.
