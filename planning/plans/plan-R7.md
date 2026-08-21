# plan-R7 — harness reconciliation

Spec: `planning/specs/spec-R7.md`. Tier: Standard. Three new Swift sources, one edited Swift
source, one new CLI verb, one new test file, one acceptance lane, one lint gate, one evidence
file. **No TypeScript change and no parity-row change** — spec §6.

## Steps

**1 · `ClientConfigs.swift`** (edit). Add `.geminiCLI` (`~/.gemini/settings.json`, JSON,
`mcpServers`) and `.grokCLI` (`~/.grok/config.toml`, TOML, the existing `mcp_servers` reader).
Add `ClientConfigs.inventory(...)` returning **every** entry including the router's own, since
`discover`'s `finish` drops exactly the evidence R7 needs. `discover` keeps its present
behaviour and its present tests — `import` and `watch` depend on it. Acceptance: A1.

**2 · `Discovery/HarnessWiring.swift`** (new). `RouterEndpoint.isThisRouter(url:port:)` over the
loopback host set shared with `SelfReference`; `HarnessRoute` with the three cases;
`HarnessRoute.detect(entries:port:)` scanning `url` for HTTP and `command`+`args` for a shim,
plus the bridge-naming rule. Acceptance: A1, A5.

**3 · `Discovery/HarnessCapability.swift`** (new). `HTTPCapability` with `.measured`,
`.documented`, `.unknown`, each carrying its provenance, and the per-client table transcribed
from spec §1.2 with the probe and the date in the value. Acceptance: A1.

**4 · `Discovery/HarnessReconciliation.swift`** (new). `DuplicateBasis`, `Duplicate`,
`HarnessReport` (client, path, route, capability, duplicates, unparsed, entry count, `summary`),
`HarnessState` (the brief's four, derived), `ReconciliationPlan` + `render()`.
`HarnessReconciliation.report(inventory:upstreams:port:)`. **No apply, no writer protocol.**
Acceptance: A1, A2, A6, A7.

**5 · `MCPRouterCLI/HarnessesVerb.swift`** (new) and one dispatch line in `MCPRouterCLI.swift`,
placed beside `install-entry` before `dispatchReferenceVerb`. Absent from `Copy.usage`.
Acceptance: A4.

**6 · `app/Tests/RouterCoreTests/HarnessReconciliationTests.swift`** (new). All four summaries;
route-by-endpoint-not-by-name; the shim with a non-`mcp-remote` bridge; the two real duplicate
cases from spec §1.3 (`Ref` by identity, `mobbin` by name-not-identity); an unparsable entry
reported as unparsed; overlap-not-duplicate for a not-wired harness; the plan's rendered diff.
Acceptance: A1, A2, A5, A6.

**7 · `scripts/acceptance/r7-harness-reconciliation.sh`** (new). Builds a scratch `HOME` with a
Gemini fixture carrying three duplicates plus a router shim entry and a router config carrying
those three upstreams; runs the built binary's `harnesses --json`; asserts three, named. Rewrites
the fixture with the three removed; asserts zero and that the route is unchanged. Then the
arming pass: re-runs with the router config emptied and requires the answer to move, so a
detector that reports three unconditionally fails the lane. Dispatched from `make acceptance`.
Acceptance: A3, A8.

**8 · `scripts/lint/no-harness-config-writes.sh`** (new) + one line in `make lint`. Fails when a
file under `app/Sources` pairs a harness config path with a writing call. Acceptance: A7.

**9 · `planning/evidence/R7-acceptance.md`.** The verb's real output against the machine's own
configs, the binary versions and probes behind spec §1.2, and the gate results.

**10 · Ledger.** `LEDGER.md` and `ORCHESTRATOR.md`: R7 status, and R7-C1…C4 rows.
