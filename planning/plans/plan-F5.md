# plan-F5 — skill and server use, by version

Spec: `planning/specs/spec-F5.md`. Branch `ai/n1`, worktree `.worktrees/N1`, base `08a24ed`.

## Slices, in dependency order

| # | slice | files | proves |
|---|---|---|---|
| 1 | The version, with its provenance in the case | `Invocations/CapabilityKind.swift`, `CapabilityVersion.swift` | A8 |
| 2 | The boundary set and the join that refuses | `VersionLedger.swift`, `VersionAtRun.swift` | A6, A7 |
| 3 | The record that structurally cannot carry a prompt | `InvocationEvent.swift` | A5 |
| 4 | The reader, incremental, counting every drop | `TranscriptScan.swift`, `TranscriptWatermarks.swift` | A1–A4, A9, A10 |
| 5 | The fold and the two encoders | `InvocationInsights.swift`, `InvocationExport.swift` | A12, A13 |
| 6 | The route | `Control/ControlInvocations.swift`, `surface.tsv` rows | A11 |
| 7 | The gate that keeps §6 true | `scripts/lint/no-telemetry-egress.sh` + selftest, `Makefile` | A14 |

## Test strategy

`app/Tests/RouterCoreTests/InvocationScanTests.swift` and `InvocationVersionTests.swift`, driven
through `MemoryFileSystem` — its `seed(_:atPath:modified:size:)` sets a stamp explicitly, which is
what makes the watermark cases (A9, A10) assertable rather than timing-dependent.

**Every assertion is watched failing before it is trusted** (fleet rule 11). The two that would
most easily be unfailable are written to be inverted first: A7 asserts a total does **not** move,
so it is run against a ledger with the boundary removed to see it move; A5 asserts the serialised
key set is exactly four, so it is run against a record given a fifth to see it redden.

## Case ids

Allocated by reading `planning/test-campaign/cases.in.json` at `08a24ed`, whose maximum is
**CASE-0261**. This item takes **CASE-0262 … CASE-0265**. (The dispatch brief said the maximum was
CASE-0216; that was 45 ids stale and would have collided.)

## Not in this branch

`D-f5-a` the SwiftUI table, `D-f5-b` the `serverInfo.version` stamp, `D-f5-c` a codex adapter,
`D-f5-d` a rollup that survives rotation. Reasons in spec §8.
