# Reckoning — mcp-router

167 piece(s) of work remain — 31 product, 16 evidence, 120 decision — across 327 ledger rows. This reckoning speaks for 81/85 (95%) of the campaign's designed cases and 11/25 (44%) of its stated requirements; the rest is not known to be done, it is simply not known. 115 brief(s) could not be tied to the registry at all; they are listed as `unjoined` and counted as decision work, rather than assumed unbuilt.

## What it can speak for

| Axis | Measured | Of | % | What the number means |
|---|---:|---:|---:|---|
| Cases adjudicated | 81 | 85 | 95.3% | an instrument returned a verdict on the product — pass or fail. A fail is knowledge; this is not a pass rate. |
| Cases ruled out by decision | 4 | 85 | 4.7% | somebody ruled the cell out of scope or not applicable. A decision, not a measurement, and it is kept out of the line above on purpose. |
| Requirements observed | 11 | 25 | 44.0% | somebody watched it happen, rather than the project reporting it of itself. |
| Surfaces spoken for | 23 | 24 | 95.8% | at least one case on this surface reached a verdict. |
| Briefs joined to evidence | 21 | 136 | 15.4% | the brief could be tied to something in the registry at all. |

_Each figure is a lower bound. Every `unnamed` row is a surface the documents never described, which means the true denominator is larger than the one the documents can supply._

## What remains

Two counts, because they answer different questions. **Rows** is every entity on both sides, and it is total by construction — that is what makes the gate meaningful. **Work** is what somebody would actually schedule: a failing case and the defect it evidences are one job, and blocked cases are counted as the blockers behind them rather than one by one.

| Class | Work | Rows | Kind | What it is |
|---|---:|---:|---|---|
| `unbuilt` | 1 | 1 | product-work | named in a brief; nothing in the registry answers to it |
| `unjoined` | 115 | 115 | decision-work | named in a brief; the join reached nothing, so its state is unknown either way |
| `broken` | 30 | 33 | product-work | measured, and the answer was no |
| `unmeasured` | 16 | 17 | evidence-work | nobody found out — the work here is becoming able to tell |
| `undecided` | 5 | 5 | decision-work | the documents and the evidence disagree; needs a person |
| `waived` | 0 | 4 | exception | somebody decided not to — an exception, and it stays visible |
| `verified-done` | 0 | 152 | none | not remaining; kept so the denominator is honest |

## Broken (30)

- **BRIEF-G5-gapfix** — G5 gap-fix — the +4 is the instrument, and the trap is wider than the submodule pin
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-G5-vendor-the-campaign-version-the-gates-run** — G5 — vendor the `test-campaign` version the gates actually run
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-I1-ios-shell-pairing** — I1 — iPhone app: shell and pairing
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-M26-checks-board-framing** — M26 — the Checks board and the design's eval board are two different surfaces
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-M27-sidebar-foot-readout** — M27 — the sidebar foot's loopback readout is absent, and the child-process card lost its label
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-M28-decision-docket** — M28 — five findings that need a decision rather than a runner
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-M6-inbox-pairing** — M6 — Inbox and phone pairing (Mac side)
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-R10-index-reports-a-write-that-did-not-land** — R10 — `index` prints two counts that disagree, and neither is checked
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-R21-approve-answers-200-over-a-discarded-write** — R21 — `approve` answers 200 while discarding the write that would make it true
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-R4-C1-installer-points-at-swift** — R4-C1 — the installer points at Swift, and the TypeScript tree stays
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-X2-ios-on-glass** — X2 — the iOS on-glass instrument, and the six cases it takes off `n/a`
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-X7-campaign-artifacts-underreport** — X7 — the campaign's published artifacts under-report what the campaign knows
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-X8-detectors-misattribute** — X8 — two campaign detectors report findings they cannot support
  - the registry records a defect or a failing case against this brief's subject
- **DEF-001** — Pairing transport is unimplemented
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-008** — iOS tab buttons carry the icon name as their accessibility identifier, and it cannot be replaced
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-011** — Cleanup's per-row actions are specified by the design and drawn by nothing
  - this defect's status is 'partially-fixed · in-campaign', which is not a word this tool classifies. It stays broken because guessing done is the one error here that cannot be recovered from, and the word is reported as a finding with its row count because that placement is this tool's decision rather than the registry's.
- **DEF-033** — the OAuth parity lane failed once inside a full gate and has not reproduced
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-035** — an incremental Swift build after adding an enum case reports impossible test failures
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-041** — REQ-016's declared outbound-socket effect has no provider in production source
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-042** — the design of record still draws a model-graded evaluation feature the product deliberately does not have
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-043** — the sidebar foot's loopback readout is absent from the build on every board, and the child-process card lost its label
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-055** — vacuity-check's blind-mutation pass examines non-tests and mis-reads Swift idiom; 7 of 7 sampled findings are false positives
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-056** — campaign.py's ledger writer prints only cases filed under a surface, silently dropping 8 of 80 — including all four effect-witness cases
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-057** — the vendored fledgeling-plugins submodule is test-campaign 0.5.0 while every gate in this campaign ran from the machine's 0.9.2 cache
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-052** — evidence-page.py and campaign.py's ledger writer both skip the defect registry, so no published artifact lists a defect
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-053** — strict-check.py omits effect-witness from EFFECT_RUNGS, so the ladder's top rung scores as 'only proves something rendered' and the gate pen
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-054** — attach-shots --apply would attach the design mock render as the build's surface shot for 11 surfaces, and its report names the surface rathe
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-048** — test-campaign 0.9.1's blind-mutation pass is dominated by its own verb configuration on this codebase, in both directions
  - this defect's status is 'superseded · by-def-055', which is not a word this tool classifies. It stays broken because guessing done is the one error here that cannot be recovered from, and the word is reported as a finding with its row count because that placement is this tool's decision rather than the registry's.
- **DEF-051** — 
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-049** — 
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it

## Unbuilt (1)

- **BRIEF-G9-two-gates-pin-a-worktree-that-no-longer-exists** — Two executable gates `cd` into a worktree that was deleted, and one is cited by a spec
  - this brief cites DEF-253, and the registry holds none of them. A citation is a link somebody wrote on purpose, so its target being absent is evidence of absence rather than a join that missed

## Unjoined (115)

- **BRIEF-BLOCKED-apple-identity** — BLOCKED — the Apple developer identity. Not scheduled, not acted on.
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-001 (0.05), REQ-022 (0.04), REQ-019 (0.04)
- **BRIEF-D1-deferred-router** — D1 — The deferred register: router side
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.07), REQ-001 (0.06), REQ-012 (0.06)
- **BRIEF-D2-deferred-mac** — D2 — The deferred register: Mac surfaces and the design authority
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.05), REQ-001 (0.04), REQ-003 (0.03)
- **BRIEF-D3-copy-proposals** — D3 — two copy decisions, drafted for the owner
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.06), REQ-001 (0.05), REQ-012 (0.04)
- **BRIEF-D3-deferred-phone-harness** — D3 — The deferred register: phone copy, and the harness limit
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.06), REQ-001 (0.06), REQ-013 (0.03)
- **BRIEF-F-cross-harness-skill-sync** — Cross-Harness Skill and Plugin Profile Synchronization
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-025 (0.03), REQ-001 (0.03), REQ-002 (0.03)
- **BRIEF-F-marketplace-auto-update-checker** — Marketplace Auto-Update Checker and Changelog Preview
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-003 (0.04), REQ-001 (0.03), SURF-009 (0.03)
- **BRIEF-F-session-analyzer-skill-recommender** — Session Analyzer and Multi-Harness Skill Recommender
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-003 (0.04), REQ-006 (0.04), REQ-001 (0.04)
- **BRIEF-F-skill-version-usage-history-stats** — Skill Version Usage History, Visualizations and Telemetry
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-004 (0.04), REQ-013 (0.03), REQ-006 (0.03)
- **BRIEF-F1-swift-workspace** — F1 — Swift workspace, shared kit, and the three targets
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-024 (0.05), REQ-013 (0.04), REQ-001 (0.04)
- **BRIEF-F2-design-system** — F2 — The design system in SwiftUI
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.04), REQ-017 (0.04), DEF-012 (0.03)
- **BRIEF-F3-control-client** — F3 — Typed control-API client and models
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-012 (0.09), REQ-004 (0.07), SURF-016 (0.05)
- **BRIEF-F4-tracker-failure-states** — F4 — ServerStateTracker cannot report failure
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.07), REQ-017 (0.04), REQ-005 (0.04)
- **BRIEF-G1-gate-hygiene** — G1 — Stop the checks blaming the app for being out of date
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.05), REQ-003 (0.04), REQ-016 (0.03)
- **BRIEF-G10-make-acceptance-is-red-on-main-so-every-enrolment-into-it-is-inert** — `make acceptance` dies at its first lane, so enrolling a lane into it delivers nothing
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.04), DEF-038 (0.04), REQ-024 (0.03)
- **BRIEF-G2-orchestrator-table-is-heterogeneous** — G2 — the ledger table holds two row shapes, and every reader silently drops one
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-012 (0.04), REQ-001 (0.04), REQ-019 (0.04)
- **BRIEF-G3-gapfix** — G3 gap-fix — the fix trades a 150ms false red for a ten-minute nameless one
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.05), REQ-001 (0.04), REQ-013 (0.03)
- **BRIEF-G3-gapfix-2** — G3 gap-fix 2 — the property holds; the scanner meant to keep it holding does not
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.06), REQ-001 (0.04), REQ-012 (0.04)
- **BRIEF-G3-gapfix-3** — G3 gap-fix 3 — the residue fails toward misses, and the third model has no grammar
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.05), REQ-001 (0.04), REQ-024 (0.03)
- **BRIEF-G3-make-test-is-not-deterministic** — G3 — `make test` is green on the second run, which is not a gate
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.06), REQ-001 (0.06), REQ-012 (0.03)
- **BRIEF-G4-assertions-that-do-not-read-their-own-quantity** — G4 — assertions that do not read the quantity they are named for
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.04), REQ-012 (0.04), DEF-046 (0.04)
- **BRIEF-G4-gapfix** — G4 gap-fix — the census counted the instrument into its own denominator
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-001 (0.05), REQ-019 (0.04), REQ-012 (0.04)
- **BRIEF-G4-gapfix-2** — G4 gap-fix 2 — the item that catches unwritten records shipped one
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.05), REQ-012 (0.04), REQ-001 (0.03)
- **BRIEF-G4-gapfix-3** — G4 gap-fix 3 — the two gates this item shipped both violate the doctrine this item wrote
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.05), REQ-012 (0.03), REQ-001 (0.03)
- **BRIEF-G5-gapfix-2** — G5 gap-fix 2 — a file moved aside and never moved back, and two clauses
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-001 (0.05), REQ-019 (0.04), DEF-057 (0.03)
- **BRIEF-G6-evidence-that-lives-in-tmp-is-not-evidence** — A sweep that proves a guard is armed, kept in `/tmp`
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-001 (0.04), REQ-019 (0.03), REQ-023 (0.03)
- **BRIEF-G7-a-citation-that-does-not-resolve-where-it-is-read** — A citation that resolved when written and does not resolve where it is read
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.05), REQ-001 (0.04), REQ-024 (0.03)
- **BRIEF-G8-a-question-answered-at-the-wrong-scope** — A question answered at the wrong scope returns a clean answer
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-001 (0.04), REQ-019 (0.04), REQ-013 (0.03)
- **BRIEF-I2-ios-discover** — I2 — iPhone: Discover and detail
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-016 (0.06), DEF-008 (0.05), REQ-010 (0.05)
- **BRIEF-I3-ios-triage** — I3 — iPhone: Triage, Queue, Library, Settings
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-010 (0.06), REQ-016 (0.05), REQ-019 (0.05)
- **BRIEF-I4-phone-direct-install** — I4 — Let the phone install directly
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.06), REQ-016 (0.05), REQ-012 (0.05)
- **BRIEF-M1-mac-shell** — M1 — Mac window shell, menu bar commands, keyboard
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-001 (0.08), REQ-005 (0.06), REQ-007 (0.05)
- **BRIEF-M12-staleness-in-destructive-dialogs** — M12 — Staleness and an as-of time inside a destructive dialog
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.05), REQ-012 (0.04), REQ-023 (0.04)
- **BRIEF-M13-scroll-edge** — M13 — The scroll-edge separator, A34
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-012 (0.05), DEF-018 (0.04), REQ-019 (0.04)
- **BRIEF-M14-menu-says-not-built** — M14 — a shipped menu tells the user the app is not built
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-019 (0.09), REQ-012 (0.05), REQ-001 (0.04)
- **BRIEF-M15-gapfix** — M15 gap-fix — four record defects, and the one product defect nothing guards
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-001 (0.05), REQ-019 (0.05), REQ-012 (0.05)
- **BRIEF-M15-settings-window** — M15 — Settings becomes its own window
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-001 (0.05), REQ-012 (0.04), REQ-019 (0.03)
- **BRIEF-M16-signal-path** — M16 — the Signal Path replaces the Breaker Column
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-001 (0.06), REQ-019 (0.04), REQ-012 (0.04)
- **BRIEF-M17-surface-states** — M17 — four states on every surface, and chrome that follows them
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-001 (0.05), REQ-019 (0.04), REQ-012 (0.04)
- **BRIEF-M18-sheets-and-gates** — M18 — twelve sheets, and the gate each decision gets
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-001 (0.04), REQ-019 (0.04), REQ-018 (0.04)
- _…and 75 more in ledger.json_

## Undecided (5)

- **BRIEF-M25-board-columns-do-not-flex** — M25 — closed: the width came from the controls row, not the columns
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-R14-client-auth-succeeds-and-reports-upstreams** — R14 — a client's Authenticate action succeeds, and says what still needs authorising
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent; and the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-R15-host-check-is-scoped-to-the-mcp-transport** — R15 — the Host check guards `/mcp` and nothing else
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent; and the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **REQ-016** — A pairing exchange actually contacts the other device and stores a record only after that contact succeeds.
  - requirement evidence 'contradicted' is a disagreement between the documents and the build; a person rules on it, an instrument cannot
- **REQ-019** — A refused write is shown as the server's refusal. Success affordances are not shown for work that did not happen.
  - requirement evidence 'contradicted' is a disagreement between the documents and the build; a person rules on it, an instrument cannot

## Decisions on the record (4)

Not remaining work, and not done either. Each of these was ruled out by somebody, and the reason it was ruled out can stop being true — a state that had no hook may get one, an account that could not be reached may become reachable. They stay on the ledger so that when the reason expires, the item is still there.

- **CASE-0002** — SURF-001 · ?
  - n/a: posting Cmd+1–7 to a background pid does not change SwiftUI's focused scene (measured: title stayed Inbox then Activity); proving the shortcuts requires the window frontmost, which this campaign refuses
- **CASE-0004** — SURF-009 · ?
  - n/a: NSStatusItem is not an AXPress target while MCPRouter is backgrounded; this campaign never activates, so the popover cannot be opened or photographed
- **CASE-0006** — SURF-009 · ?
  - n/a: NSStatusItem is not an AXPress target while MCPRouter is backgrounded; inbox band never opened
- **CASE-0109** — SURF-009 · ?
  - n/a: status item not pressable in background; SURF-009 popover uncaptured. Raster-visual of the popover is unreachable under the no-activate constraint

## Requirements standing on the project's own word (12)

These are not failures. Each is a claim the project makes about itself that nothing independent has confirmed, which is a different thing from a claim that has been checked and held.

- **REQ-002** (`reported`) — The tool cache is keyed on each server's command/args/env identity and tools are namespaced <server>__<tool>.
  - obtain independent evidence — this is the project's own account of itself
- **REQ-004** (`reported`) — The Servers board reflects live server states from ServerStateTracker (running, tripped, never used, held) without inventing a figure the tr
  - obtain independent evidence — this is the project's own account of itself
- **REQ-005** (`reported`) — When the tracker is stale or the router is not running, live counts go absent rather than displaying last-known figures as current.
  - obtain independent evidence — this is the project's own account of itself
- **REQ-007** (`reported`) — Numbers the router does not observe are never displayed. There is no fabricated memory saving.
  - obtain independent evidence — this is the project's own account of itself
- **REQ-008** (`reported`) — The menu-bar popover shows a readout, attention rows, and an inbox band of oldest-first arrivals; a partial row carries no review affordance
  - obtain independent evidence — this is the project's own account of itself
- **REQ-009** (`reported`) — Disposing an inbox item immediately withdraws its notification banner; a multi-item banner carries Review only.
  - obtain independent evidence — this is the project's own account of itself
- **REQ-010** (`reported`) — The phone exposes Discover, Triage, Queue, Library and Settings; Triage commit is a single-batch undoable enqueue.
  - obtain independent evidence — this is the project's own account of itself
- **REQ-014** (`reported`) — Swift RouterCore matches the TypeScript reference on the parity corpus; the cutover target is 82 of 83 with fixture-registry-search a standi
  - obtain independent evidence — this is the project's own account of itself
- **REQ-015** (`reported`) — Mac Pairing sheet shows an 8-character Crockford code and QR; the phone can scan or type it.
  - obtain independent evidence — this is the project's own account of itself
- **REQ-017** (`unknown`) — Every data surface ships the nine DESIGN.md §5 states with real copy on the unhappy paths.
  - obtain any evidence at all
- **REQ-018** (`reported`) — Undo is the Mac contract for reversible acts; a named-consequence dialog is reserved for genuinely destructive ones and is never the default
  - obtain independent evidence — this is the project's own account of itself
- **REQ-020** (`reported`) — install.sh flips to the Swift binary and retires src/*.ts once parity is 82 of 83 and the owner decides.
  - obtain independent evidence — this is the project's own account of itself

