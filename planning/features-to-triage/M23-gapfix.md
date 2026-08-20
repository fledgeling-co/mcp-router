# M23 gap-fix — three rows that would let a future surface reach exit 0

**Parent:** M23, the mock-to-SwiftUI conversion contract (`M23-mock-to-swiftui-contract.md`).
**Branch:** `ai/m23`, worktree `.worktrees/M23`, at `5d388fb`. Resume in place; do not cold-start.
**Verdict this closes:** Verified 2026-08-21 at `metamorphic`, **Needs More Work**.
**Found by:** the fresh-context verifier, corroborated independently by `codex`/`gpt-5.6-sol`,
which returned REJECT with 10 findings and hit two of these three by a different route.

## Why this is a gap-fix and not a rebuild

The instrument is sound and its central claim survived attack. Marking `structure`
`required:false` in the real manifest gives exit 3; removing a dump gives 3; cutting the
ideal census from 39 nodes to 3 gives 3; and reverting `return 3` to `return 1` inside the
engine turns the selftest red. The third exit state is armed, not decorative.

The declared 64-of-89 `pending` residue is honest bookkeeping rather than a gap: every
pending row carries a citation, a test checks each citation resolves to a pre-existing file
containing the quoted line verbatim, and drifting one (`--tl-zoom` `#28C840`→`#FF00FF`)
turns the suite red naming both values. A `pending` row is a fingerprint, not an exemption.

What blocks is narrower. M23 exists so that a later surface conversion can be *proved*, and
these three sit in the exact rows a future surface would travel to reach exit 0. Each one
lets a conversion pass while unmeasured.

## G1 — `present` is inferred where the brief says it must be earned

**Where:** `planning/fidelity/servers.ledger.md:150-160`, and
`scripts/acceptance/mock_fidelity.py` `layer_breadth`, the four-outcome block (~line 400).

Status comes from `mock_text == app_text`. In 6 of the 10 `present` rows of the one worked
example the acceptance criterion names, both sides are the empty string — so agreement
between two absences reads as a match. One pairs the mock's `<use href="#i-…">` glyph to the
build's `IconView` with no glyph compared. Another pairs mock kind `card` to build role
`skeleton` and still reads `present`, because `affordance["kind"]` is written into the
ledger and never compared to `node["role"]`.

The brief's rule is explicit: *"PRESENT is earned by measuring, never inferred from purpose.
Two controls doing the same job are not a match; pair them, then audit label, control kind
and glyph."*

**Fix:** an empty-vs-empty comparison resolves to `unclassified` — the layer's own doctrine
for a comparison it could not make — and the paired node's role and kind are compared
against the affordance's kind.

## G2 — an extra build element is swallowed silently

**Where:** the `inside_a_pair` exemption in `layer_breadth`
(`scripts/acceptance/mock_fidelity.py`, ~line 440); witnessed at
`planning/fidelity/servers.ledger.md:163`.

The mock's `v-loading` state draws three skeleton rows. The build's dump draws four
(`skeleton-row-0..3`). Because the container is paired, the fourth is classified
`covered-by-pair` and produces no finding.

The brief's rule is *"Extra elements are divergent too. Matching the mock means removing
what it does not have, not only adding what it lacks."* The exemption's own comment says a
descendant of a paired node is "accounted for by that pair" — but the mock's census does
enumerate that kind at that granularity, naming three of them, so the fourth is an
uncounted invention rather than containment.

**Fix:** where the mock's inventory contains affordances of the same kind under the same
parent, exempt only as many build children as the mock declares.

## G3 — a tokens layer that measured nothing exits 1 rather than 3

**Where:** `scripts/acceptance/mock_fidelity.py:97` (`layer_tokens` marker parsing), against
`app/Tests/MCPRouterKitTests/MockTokenParityTests.swift:183-189`.

Reproduced: with `MCP_ROUTER_WRITE_TOKEN_REGISTER=1` inherited in the environment, the Swift
suite prints `MOCK-FIDELITY-TOKENS: register rewritten at <path>` and returns before the
census marker. `dict(part.split("=", 1) for part in …)` then raises an uncaught
`ValueError: dictionary update sequence element #0 has length 1; 2 is required`, Python
exits 1, and `write_report` is never reached — so the stale committed `servers.ledger.md`
stays on disk beside an exit code that reads as a measured verdict.

This is the gate's own doctrine violated inside the gate: an unparseable marker is a layer
that could not run, and a layer that measured nothing must read as inconclusive rather than
as findings. `subprocess.TimeoutExpired` from `run()` escapes the same way.

**Fix:** wrap the marker parse and the subprocess calls so both raise `Inconclusive`.

## Acceptance

Each fix is proved by a mutation that goes red and returns on restore, because an assertion
nobody has watched fail is not known to bite.

1. A ledger row whose mock text and build text are both empty resolves `unclassified`, and
   a row pairing kind `card` to role `skeleton` produces a finding. Restoring the
   `mock_text == app_text` comparison turns the selftest red.
2. The `v-loading` state reports the fourth skeleton row as divergent. Adding a fifth build
   child reports two. Restoring the blanket `inside_a_pair` exemption turns the selftest red.
3. `MCP_ROUTER_WRITE_TOKEN_REGISTER=1 scripts/acceptance/mock-fidelity-gate.sh servers`
   exits **3**, names the tokens layer as inconclusive, and writes a ledger. A planted
   `TimeoutExpired` exits 3 by the same path. Removing the `Inconclusive` wrapper returns
   the uncaught `ValueError` and exit 1.
4. `scripts/acceptance/mock-fidelity-gate.sh servers` still exits 1 with its findings count
   quoted, `make lint` exits 0, and `make test` is run twice with both exit codes quoted —
   `PoolReapingTests.swift:61` is non-deterministically red under whole-suite load
   (registered as G3 in `ORCHESTRATOR.md`, a wall-clock assumption rather than a product
   defect), so one red run there is not a verdict on this branch.

## Scope

Deliver these three and their acceptance, at the scope intended. `D-m23-a` through `D-m23-e`
are registered in `ORCHESTRATOR.md`'s deferred register and stay deferred — in particular
the dark-only dumps (`D-m23-c`) and the unread resolved-colour layer (`D-m23-b`) are real and
are not this item's to close. The verifier downgraded five of codex's ten findings to
follow-ups; those are recorded there too.

Record anything else found rather than fixing it.
