# Retired Swift router

The owner retired the Swift router on 19 October 2026 and authorized the remaining deletion through the feedback-panel recommendations on 1 November. TypeScript is the retained router.

The unbuilt RouterCore, MCPRouterCLI, ControlDiff and RouterCoreTests Swift sources are removed. Their history remains in Git. Restoring the router would require restoring its source, targets, pinned SDK and gates together.

`app/Tests/RouterCoreTests/Pins/pause-action.json` remains because the active UI pause-action test reads it. The `Vectors/` corpus remains for the TypeScript golden regeneration check. Neither directory compiles a Swift router.

The deleted routes and deferred scope stay recorded in `planning/plans/plan-retire-swift-router.md`. Source deletion is not evidence that those deferred capabilities were implemented.
