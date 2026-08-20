# M23 — out-of-family review, gpt-5.6-sol at high effort

Lane: `codex exec -m gpt-5.6-sol -c model_reasoning_effort=high -s read-only`, run 2026-08-21 from
the M23 worktree against `/tmp/m23.diff` (5518 lines) plus the spec and brief. The reviewer was
briefed adversarially — told to refute, and told that finding nothing is a failed review.

ORCHESTRATOR.md recorded this lane as unavailable until 2026-08-20. It is back: the `-o` file came
back non-empty with a substantive review, which is the only honest tell, since `codex exec` exits 0
on a usage limit.

What follows is the reviewer's output verbatim. What was done about each finding is in
`M23-acceptance.md` §5.

---

1. **SEVERITY: Critical — A1 makes existing `pending` rows an exemption class.**  
   **Spec:** [§3.1, lines 198–208](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/planning/specs/spec-M23.md:198>) and [A1, lines 273–276](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/planning/specs/spec-M23.md:273>).  
   **Failure scenario:** `--accent` is already pending because the mock has `#0088FF` while Swift has `#0069CF`. Change the mock to `#FF00FF`; it remains “values differ” and can retain the same generic M21 citation. The spec explicitly promises red only for “a new mock token, or a drift in a matched pair,” leaving drift within a pending pair unchecked. Under effort pressure, “pending with a pre-existing citation” is therefore an obvious way to classify a newly introduced defect as expected.  
   **Fix:** Require every pending row to fingerprint the exact mock and Swift values per appearance, with any change failing until separately approved. Scope citations to the specific token, contexts and discrepancy; verify the cited owner remains unresolved. Add a mutation test changing an already-pending value and require exit 1.

2. **SEVERITY: Critical — A7 converts an inconclusive fidelity layer into a green result.**  
   **Spec:** [§5, lines 259–262](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/planning/specs/spec-M23.md:259>) and [A7, lines 295–297](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/planning/specs/spec-M23.md:295>), contradicting the embedded brief’s [exit-0 definition, lines 145–155](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/planning/specs/spec-M23.md:145>).  
   **Failure scenario:** A body label renders with the wrong `TypeToken`, weight or face while colour, copy and fixed geometry agree. The font layer produces no observation, yet `required:false` permits exit 0. Printing a citation records why measurement failed; it does not provide the “where it was confirmed instead” evidence required by the brief. This is a silenced layer made non-blocking while exit 0 is relabelled from “every layer ran” to “every required layer ran.”  
   **Fix:** An authored fidelity layer that cannot run must force exit 3. A substitute may avoid exit 3 only if it contains equivalent per-node evidence, such as measured font properties or a rigorously verified font-role observation—not merely a citation explaining opacity. Otherwise define a separate explicitly partial, non-accepting verdict.

3. **SEVERITY: Critical — the gate has no output-cardinality or freshness postcondition.**  
   **Spec:** [§5, lines 248–267](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/planning/specs/spec-M23.md:248>).  
   **Failure scenario:** `MeasureDump` exits successfully but writes `[]` or a zero-byte/stale result; the copy comparison receives zero rows; or the breadth TSV is header-only. A preflight can prove that a capability exists without proving that this run produced observations. Loops over these inputs find no differences, satisfying “produced no finding.” Missing input is likewise not explicitly required to become exit 3. The existing lint script has explicit missing-directory and zero-file guards at [lines 48–60](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/scripts/lint/no-raw-design-values.sh:48>); the proposed gate specifies no equivalent.  
   **Fix:** For every layer require a readable, non-empty, schema-valid artifact with the current run ID, surface ID, source digest and expected observation count/ID set. Missing, stale, zero-byte or syntactically valid empty output must return 3. Self-test each layer against all four cases.

4. **SEVERITY: Critical — the breadth ledger trusts its own mutable denominator.**  
   **Spec:** [§5, line 255](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/planning/specs/spec-M23.md:255>) and [A5, lines 288–289](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/planning/specs/spec-M23.md:288>).  
   **Failure scenario:** Delete a `divergent` or `absent` TSV row. The gate now sees no bad status and can return 0 because nothing independently proves that the affordance should have had a row. This repeats P4 exactly: deleting a census row reduced the denominator, raised reported coverage and exited 0, as recorded in [P4 acceptance lines 16–33](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/planning/evidence/P4-acceptance.md:16>). “Committed TSV” offers reviewability, not completeness.  
   **Fix:** Derive stable expected affordance IDs from the mock, reconcile ledger IDs in both directions against that inventory and the measured Swift tree, and pin the expected count/source digest. Extra Swift elements need the reverse comparison. Add row-deletion, row-duplication and row-replacement mutations that must fail.

5. **SEVERITY: High — “every `:root`-family custom property” is neither defined nor measurable as written.**  
   **Spec:** [§4, line 238](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/planning/specs/spec-M23.md:238>).  
   **Failure scenario:** The HTML has another top-level `:root` at [line 822](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/design/mcp-router-console.html:822>) containing `--ic-*` WebP data-URI assets, while the first `:root` contains colours, composite shadows and other values. A first-match parser silently ignores the later block; a literal interpretation tries to classify image assets as colours. The contrast `:root` blocks are partial overrides, so declared-value parsing also fails to calculate inherited effective values. A colour added to the second root or a cascade change can therefore escape while the gate claims all contexts were checked.  
   **Fix:** Define a typed token grammar and the exact included selectors. Enumerate every matching block, reject unknown token kinds, and resolve the CSS cascade into effective values for each appearance context. Assert block/name-set completeness and mutate a token in the second root and an inherited contrast value.

6. **SEVERITY: High — the spec claims the structure layer ran without measuring structure.**  
   **Spec:** [§3.3, lines 221–232](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/planning/specs/spec-M23.md:221>) and [§4, lines 240–241](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/planning/specs/spec-M23.md:240>).  
   **Failure scenario:** The listed probes measured frames for instrumented nodes and showed that SwiftUI exposes no AppKit subtree. They did not measure containment, ordered children, stack axis, alignment, a real surface, or agreement with parsed DOM. Nevertheless the spec concludes that “the structure … layer genuinely run[s].” A modifier can report a declared `HStack` annotation while the actual view is a `VStack`; the self-description matches the mock and the gate passes. No probe source or output is committed, and the §8 evidence file is absent.  
   **Fix:** Recast these as feasibility observations until reproducible probe code and raw output are committed. Arm the layer with real-surface mutations for H/V axis, reorder, removal, insertion and containment. Structure evidence must be independently observed, not metadata supplied by the view being certified.

7. **SEVERITY: High — the reused literal lint is described as more complete than it is.**  
   **Spec:** [§3.2, lines 210–217](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/planning/specs/spec-M23.md:210>).  
   **Failure scenario:** The script’s component-colour pattern at [lines 74–77](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/scripts/lint/no-raw-design-values.sh:74>) catches `Color(.sRGB…)` and `Color(red:…)`, but not valid raw forms such as `Color(.displayP3, red:…, green:…, blue:…)`, `Color(white:…)` or `Color(hue:saturation:brightness:)`. Those literals can ship while the gate claims no component-constructed colour exists. Fixed scan directories also permit a future UI source directory to sit outside the census.  
   **Fix:** Use a SwiftSyntax-based rule covering colour initializer overloads and token-bypass expressions, derive scanned UI targets from the package/project, and add red-green mutations for each constructor form. Until then, narrow the spec’s claim to the spellings actually checked.

8. **SEVERITY: High — the self-test arms only selected outcomes, not every layer.**  
   **Spec:** [§5, lines 264–267](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/planning/specs/spec-M23.md:264>) and the embedded [acceptance lines 167–168](</Users/lukerhodes/Dev/mcp-router/.worktrees/M23/planning/specs/spec-M23.md:167>).  
   **Failure scenario:** Token drift proves one route to exit 1, and disabling one required layer proves one route to exit 3. The structure, geometry, copy, breadth and literal evaluators can be constant-green or never invoked while this self-test still passes. The statement “a gate never observed failing is a gate nobody has written” is not applied per layer.  
   **Fix:** Require an arming matrix: every layer must independently produce exit 1 for a representative defect and exit 3 for missing/invalid output. Include structural reorder, geometry offset, copy drift, extra/removed breadth row, raw literal and pending-token drift mutations, asserting both exit code and layer-specific message.

VERDICT: REJECT