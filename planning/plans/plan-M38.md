# plan-M38 — the staged tool diff's decision, witnessed at the catalog

**Spec:** `planning/specs/spec-M38.md` · **Branch:** `ai/n5` · **Worktree:** `.worktrees/N5`

Three of the brief's five acceptance lines are already built and are cited rather than rebuilt
(spec §1). This plan covers line 4, the witness the dispatch brief asked for, and the disposition
of line 5.

---

## Slices

| # | Slice | Files | Oracle lines |
|---|---|---|---|
| 1 | `/approve`'s 200 announces the tool-list change | `src/control.ts` | 1, 2, 3 |
| 2 | the lane that can tell which mechanism announced | `scripts/e2e-live-reload.mjs` | 1–4 |
| 3 | the promotion read back at the serving predicate | `app/Tests/RouterCoreTests/ControlApproveCatalogTests.swift` at `0cd5e792e6bb2095ef7923217adf3f5418f076d6` (historical source), `app/Sources/RouterCore/Service/MCPEndpoint.swift` at `0cd5e792e6bb2095ef7923217adf3f5418f076d6` (historical source) | 5–9 |
| 4 | the arms that prove slice 3 can fail | `scripts/red-green.py` (`APP-1`…`APP-5`) | — |
| 5 | line 5 deferred with its reason | `planning/features-to-triage/M38-phone-cannot-approve-a-tool-surface.md` | — |

### Slice 1 — one call, at the site of its four siblings

`announceTools(deps, 'approved "<name>"\'s new tool surface')` on the 200 only. Not on the 409,
which promoted nothing, and not on the 500, which wrote nothing — announcing either would send
every attached session to re-fetch a list that did not move, which is the cost `announceTools`'s
own doc comment refuses.

**No parity consequence, established by reading rather than assumed.**
`compare control-approve-post    "POST /servers/:name/approve"`,
`scripts/acceptance/control-differential.sh:511` at `08a24ed` drives `/approve` only at the 409 and
the 404,
and says so in its own comment (*"neither request issued here writes anything"*). The 200 is never
reached, so the differential cannot see this. `scripts/acceptance/parity-log.sh` at `0cd5e792e6bb2095ef7923217adf3f5418f076d6` (historical source) drives *start,
index, call, call again, SIGTERM* and never calls the control API, so no `live-reload:` line enters
the sequence it diffs. Nothing in `planning/parity/surface.tsv` at `0cd5e792e6bb2095ef7923217adf3f5418f076d6` (historical source) enumerates the notification stream.

### Slice 2 — the lane, and why its notification count is not its oracle

The arm stages a real held change: the upstream rewrites its own tool description, `index --force`
holds it as `pending` rather than serving it, `/changes` reports it, and the attached session is
still served the approved text. Then the decision, and the read-back.

**The poller has to be waited out, by quiescence rather than by a fixed window.** Measured while
writing this: `index --force` commits per server, so a two-upstream re-index moves the manifest
stamp twice and the poller announces on two consecutive ticks three seconds apart. A 4.5-second
window caught the second and failed a control that was right about the router and wrong about the
arithmetic.

**The oracle is the log line, not the notification count**, because the poller supplies a
notification either way. Spec D2. The count and the observed latency are printed as corroboration.

### Slice 3 — the read-back

`MCPEndpoint.listTools()` over a `ManifestStore` constructed **before** the strike and never handed
to the control handler. Constructed before on purpose: the store loads the pre-approval manifest at
init, so the promotion shows up only if the store notices the file moved and re-reads it — which is
what the serving process does between two `tools/list` calls, and what `APP-5` proves is load
bearing.

`listTools()` goes from `private` to `internal`, which is the accessibility its sibling `callTool`
already has and for the reason `MCPEndpointDisabledCallTests` already relies on.

---

## Test strategy

| Rung | What stands on it |
|---|---|
| a real socket, a real router, the SDK's own client | lines 1–4 (`make node-e2e`) |
| the serving predicate through the real control handler | lines 5–9 (`make test`) |
| mutation | `APP-1`…`APP-5`, plus the lane arm proved by removing the announce |

**Every new assertion was watched failing.** `APP-1`…`APP-5` were run against the suite and all
five killed; the lane's approve arms were proved by deleting the `announceTools` call, rebuilding
and re-running, which took the lane to 23/26 with the three approve checks red.

**One thing that went wrong while proving them, kept rather than smoothed.** `APP-3`'s first form
kept the catch block's braces balanced with `if false {`, which does not compile. A hand harness
reading the run only for `recorded an issue` lines then reported it **SURVIVED** — a mutation that
measured nothing, filed as a decoration exposed. The registered form compiles and kills, and
`red-green.py`'s own `COMPILE_RE` already demotes a non-compiling mutation, which is why the arm
belongs in that file rather than in a shell script beside it.

---

## Not in this plan

- **The Swift router's half of live-reload.** R29 shipped the family as TypeScript-only with the
  Swift router answering 404, and that boundary is R29's. Oracle lines 1–4 are TypeScript-only.
- **Re-reviewing the sheet.** M8's schema diff and M29's sheet are cited as built (spec §1).
- **Moving approve's status code.** R21's instruction, and `ControlApproveDispatchTests:114-118`
  pins 200 deliberately.
