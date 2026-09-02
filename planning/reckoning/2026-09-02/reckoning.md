# Reckoning — mcp-router

202 piece(s) of work remain — 57 product, 16 evidence, 129 decision — across 544 ledger rows. This reckoning speaks for 161/171 (94%) of the campaign's designed cases and 18/32 (56%) of its stated requirements; the rest is not known to be done, it is simply not known. 109 brief(s) could not be tied to the registry at all; they are listed as `unjoined` and counted as decision work, rather than assumed unbuilt.

## What it can speak for

| Axis | Measured | Of | % | What the number means |
|---|---:|---:|---:|---|
| Cases adjudicated | 161 | 171 | 94.2% | an instrument returned a verdict on the product — pass or fail. A fail is knowledge; this is not a pass rate. |
| Cases ruled out by decision | 9 | 171 | 5.3% | somebody ruled the cell out of scope or not applicable. A decision, not a measurement, and it is kept out of the line above on purpose. |
| Requirements observed | 18 | 32 | 56.2% | somebody watched it happen, rather than the project reporting it of itself. |
| Surfaces spoken for | 38 | 44 | 86.4% | at least one case on this surface reached a verdict. |
| Briefs joined to evidence | 52 | 224 | 23.2% | the brief could be tied to something in the registry at all. |

_Each figure is a lower bound. Every `unnamed` row is a surface the documents never described, which means the true denominator is larger than the one the documents can supply._

## What remains

Two counts, because they answer different questions. **Rows** is every entity on both sides, and it is total by construction — that is what makes the gate meaningful. **Work** is what somebody would actually schedule: a failing case and the defect it evidences are one job, and blocked cases are counted as the blockers behind them rather than one by one.

| Class | Work | Rows | Kind | What it is |
|---|---:|---:|---|---|
| `unbuilt` | 2 | 2 | product-work | named in a brief; nothing in the registry answers to it |
| `unjoined` | 109 | 109 | decision-work | named in a brief; the join reached nothing, so its state is unknown either way |
| `broken` | 55 | 62 | product-work | measured, and the answer was no |
| `unmeasured` | 15 + 1 blockers | 21 | evidence-work | nobody found out — the work here is becoming able to tell |
| `unnamed` | 1 | 1 | decision-work | the campaign found it; no document claims it |
| `undecided` | 19 | 19 | decision-work | the documents and the evidence disagree; needs a person |
| `waived` | 0 | 77 | exception | somebody decided not to — an exception, and it stays visible |
| `verified-done` | 0 | 253 | none | not remaining; kept so the denominator is honest |

## What unblocks the most

Blocked cases cluster: a handful of causes usually account for most of them. Resolving these in order returns the most measurement per unit of work.

| Blocker | Cases it unblocks | Coverage returned | Cause |
|---|---:|---:|---|
| `BLOCK-0001` | 1 | +1/171 (+0.6 pts) | unoracled: the drawn badge on the app's own menu has no channel. SwiftUI does not publish an NSMenuItem's badge to the accessibility plane; AXSize is  |

## The schedule

Every duration below is **wall-clock for one agent unit**, from a corpus of 1,842 measured Opus 4.8 and Opus 5 subagent runs across 88 sessions and 31 projects (14 Jul – 30 Aug 2026). Ranges are p25–p90 and are printed as ranges because the measured spread demands it: p90 ÷ median is 3.4 for build work and 3.1 for research, so any single number would be wrong by a factor of three in the ordinary case. Provenance, method and limits: `references/estimation.md`.

**4.9 h – 10 h across 3 wave(s) at up to 8 concurrent agents**, against roughly 19 h if the same work ran one item at a time. wall-clock for 3 wave(s) at up to 8 concurrent agents, summed. The implied speedup over running the same work serially is 3.9x, within the 2.2x median / 4.0x p90 measured on this corpus.

These figures do not carry a failure rate. A unit that ran forty minutes and produced work that was later rejected is counted the same as one that landed, so this answers how long an agent will be busy, not how long until the work is accepted.

| Wave | Items | Slots | Range | Serial | Bounded by |
|---:|---:|---:|---|---|---|
| 1 | 48 | 8 | 3.3 h – 5.7 h | 13 h | observed-speedup-ceiling |
| 2 | 24 | 8 | 89 min – 2.7 h | 5.9 h | observed-speedup-ceiling |
| 3 | 1 | 1 | 8 min – 1.7 h | 15 min | slowest-member |

### Wave 1 — 3.3 h – 5.7 h

costs its slowest member — measured wall-clock ÷ slowest member was 1.05 at the median and 1.8 at p90 across 253 real waves; with 48 item(s) the slowest-member figure would imply a speedup better than the 4.0x p90 ever measured here, so the low end is held to that instead; 48 members is above the observed concurrency ceiling of 8, where the slowest-member property degrades, so the upper bound is widened.

| Item | Kind | Tier | Range | Sub-tasks | Why this tier |
|---|---|---|---|---|---|
| `BLOCK-0001` unoracled: the drawn badge on the app's own menu has no channel. Swift | evidence | S | 3 min – 25 min | 1 case(s): CASE-0197 | one cause behind 1 case(s); sized by the hook, not the cases |
| `DEF-001` Pairing transport is unimplemented | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-057` the vendored fledgeling-plugins submodule is test-campaign 0.5.0 while | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `REQ-015` Mac Pairing sheet shows an 8-character Crockford code and QR; the phon | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `DEF-008` iOS tab buttons carry the icon name as their accessibility identifier, | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-011` Cleanup's per-row actions are specified by the design and drawn by not | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-041` REQ-016's declared outbound-socket effect has no provider in productio | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-049`  | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-033` the OAuth parity lane failed once inside a full gate and has not repro | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-042` the design of record still draws a model-graded evaluation feature the | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-048` test-campaign 0.9.1's blind-mutation pass is dominated by its own verb | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-055` vacuity-check's blind-mutation pass examines non-tests and mis-reads S | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `REQ-020` install.sh flips to the Swift binary and retires src/*.ts once parity  | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `DEF-052` evidence-page.py and campaign.py's ledger writer both skip the defect  | product-work | L | 14 min – 68 min | — | broken work defaults to M; severity high |
| `DEF-053` strict-check.py omits effect-witness from EFFECT_RUNGS, so the ladder' | product-work | L | 14 min – 68 min | — | broken work defaults to M; severity high |
| `DEF-054` attach-shots --apply would attach the design mock render as the build' | product-work | L | 14 min – 68 min | — | broken work defaults to M; severity high |
| `DEF-063` A stdio child that starts and then exits is not noticed, so acquisitio | product-work | L | 14 min – 68 min | — | broken work defaults to M; wording suggests it spans more than one surface |
| `DEF-051`  | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-056` campaign.py's ledger writer prints only cases filed under a surface, s | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-058` the macos-glass lane is green over window evidence captured from a pre | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-059` `Settings` is no longer a sidebar row, so the glass capture filed a ne | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-060` A too-large refusal names the file and the cap but never the capabilit | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-061` The capture-lineage tie pass has no notion of a route template, so a p | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `REQ-007` Numbers the router does not observe are never displayed. There is no f | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-008` The menu-bar popover shows a readout, attention rows, and an inbox ban | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `DEF-043` the sidebar foot's loopback readout is absent from the build on every  | product-work | S | 3 min – 25 min | — | broken work defaults to M; wording suggests a contained change |
| `BRIEF-G9-two-gates-pin-a-worktree-that-no-longer-exists` Two executable gates `cd` into a worktree that was deleted, and one is | product-work | L | 14 min – 68 min | DEF-253 | unbuilt work defaults to L |
| `BRIEF-a-brief-that-names-nothing-cannot-be-retired` A brief that names nothing the registry holds can never leave the rema | product-work | L | 14 min – 68 min | DEF-253 | unbuilt work defaults to L |
| `DEF-072` WIN22's Action Center toasts cannot fire: nothing in product source ra | product-work | L | 14 min – 68 min | — | broken work defaults to M; severity high |
| `DEF-073` WIN19's packaging and distribution ships no package: no manifest of an | product-work | L | 14 min – 68 min | — | broken work defaults to M; severity high |
| `DEF-079` The shell's unhandled-exception log never fires, including for a crash | product-work | L | 14 min – 68 min | — | broken work defaults to M; wording suggests it spans more than one surface |
| `BRIEF-R9-sdk-drops-upstream-message` R9 — the upstream's own words survive the SDK that drops them | evidence-work | M | 7 min – 56 min | DEF-047 | unmeasured work defaults to M |
| `BRIEF-X1-ios-a11y-harness` X1 — the iOS accessibility-tree harness, and the two surfaces that wer | evidence-work | M | 7 min – 56 min | DEF-029 | unmeasured work defaults to M |
| `BRIEF-eleven-surfaces-declare-controls-that-nothing-drives` Eleven surfaces declare their controls and no passing case drives one  | product-work | M | 7 min – 56 min | SURF-001, SURF-002, SURF-004 | broken work defaults to M |
| `BRIEF-three-captures-name-a-route-they-were-not-pointed-at` Three captures name a route they were not pointed at, and one manifest | product-work | M | 7 min – 56 min | SURF-001, SURF-002, SURF-003, SURF-011… | broken work defaults to M |
| `DEF-062` The Skills board's held-update sheet offers no decision — its only con | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-070` GET /servers discloses every stdio upstream's full argv to an unauthen | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-074` WIN23's logon-task supervision registers no task: the model describes  | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-075` The Discover detail dialog is unaddressable from the automation plane: | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-076` The Settings board declares one addressable control against a claim of | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `REQ-002` The tool cache is keyed on each server's command/args/env identity and | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-004` The Servers board reflects live server states from ServerStateTracker  | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-005` When the tracker is stale or the router is not running, live counts go | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-009` Disposing an inbox item immediately withdraws its notification banner; | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-010` The phone exposes Discover, Triage, Queue, Library and Settings; Triag | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-014` Swift RouterCore matches the TypeScript reference on the parity corpus | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-017` Every data surface ships the nine DESIGN.md §5 states with real copy o | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-018` Undo is the Mac contract for reversible acts; a named-consequence dial | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |

### Wave 2 — 89 min – 2.7 h

costs its slowest member — measured wall-clock ÷ slowest member was 1.05 at the median and 1.8 at p90 across 253 real waves; with 24 item(s) the slowest-member figure would imply a speedup better than the 4.0x p90 ever measured here, so the low end is held to that instead; 24 members is above the observed concurrency ceiling of 8, where the slowest-member property degrades, so the upper bound is widened.

| Item | Kind | Tier | Range | Sub-tasks | Why this tier |
|---|---|---|---|---|---|
| `DEF-035` an incremental Swift build after adding an enum case reports impossibl | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `BRIEF-G5-gapfix` G5 gap-fix — the +4 is the instrument, and the trap is wider than the  | product-work | M | 7 min – 56 min | CASE-0145, DEF-048 | broken work defaults to M |
| `BRIEF-G5-vendor-the-campaign-version-the-gates-run` G5 — vendor the `test-campaign` version the gates actually run | product-work | M | 7 min – 56 min | DEF-057 | broken work defaults to M |
| `BRIEF-I1-ios-shell-pairing` I1 — iPhone app: shell and pairing | product-work | M | 7 min – 56 min | DEF-001, DEF-008, DEF-041, REQ-015… | broken work defaults to M |
| `BRIEF-M26-checks-board-framing` M26 — the Checks board and the design's eval board are two different s | product-work | M | 7 min – 56 min | DEF-011, DEF-012, DEF-031, SURF-006 | broken work defaults to M |
| `BRIEF-M28-decision-docket` M28 — five findings that need a decision rather than a runner | product-work | M | 7 min – 56 min | DEF-008, DEF-033, DEF-042, DEF-049… | broken work defaults to M |
| `BRIEF-M6-inbox-pairing` M6 — Inbox and phone pairing (Mac side) | product-work | M | 7 min – 56 min | DEF-001, DEF-041, REQ-015, REQ-016… | broken work defaults to M |
| `BRIEF-R10-index-reports-a-write-that-did-not-land` R10 — `index` prints two counts that disagree, and neither is checked | product-work | M | 7 min – 56 min | DEF-049, REQ-007, REQ-019 | broken work defaults to M |
| `BRIEF-R21-approve-answers-200-over-a-discarded-write` R21 — `approve` answers 200 while discarding the write that would make | product-work | M | 7 min – 56 min | DEF-049 | broken work defaults to M |
| `BRIEF-R33-four-features-shipped-to-the-router-that-does-not-run` R33 — Four merged features shipped into the router that does not run | evidence-work | M | 7 min – 56 min | REQ-020 | unmeasured work defaults to M |
| `BRIEF-R4-C1-installer-points-at-swift` R4-C1 — the installer points at Swift, and the TypeScript tree stays | product-work | M | 7 min – 56 min | DEF-033 | broken work defaults to M |
| `BRIEF-X2-ios-on-glass` X2 — the iOS on-glass instrument, and the six cases it takes off `n/a` | product-work | M | 7 min – 56 min | CASE-0020, CASE-0120, DEF-001, DEF-013… | broken work defaults to M |
| `BRIEF-X7-campaign-artifacts-underreport` X7 — the campaign's published artifacts under-report what the campaign | product-work | M | 7 min – 56 min | CASE-0145, CASE-0151, CASE-0184, DEF-051… | broken work defaults to M |
| `BRIEF-X8-detectors-misattribute` X8 — two campaign detectors report findings they cannot support | product-work | M | 7 min – 56 min | DEF-054, DEF-055, DEF-057, DEF-061… | broken work defaults to M |
| `BRIEF-a-refusal-that-cannot-say-which-capability-it-refused` A too-large refusal names the file and the cap but never the capabilit | product-work | M | 7 min – 56 min | DEF-060 | broken work defaults to M |
| `BRIEF-a-status-word-nobody-taught-the-gate-lands-pessimistic` A defect status nobody taught the gate is still classified by a guess | product-work | M | 7 min – 56 min | DEF-011, DEF-048 | broken work defaults to M |
| `BRIEF-glass-evidence-outlives-the-build-it-was-taken-from` Committed glass evidence outlives the build it was taken from, and not | product-work | M | 7 min – 56 min | CASE-0001, CASE-0016, CASE-0101, CASE-0111… | broken work defaults to M |
| `BRIEF-no-surface-declares-its-controls-so-nothing-counts-them` No surface declares its controls, so the actuation census has no denom | product-work | M | 7 min – 56 min | DEF-008, DEF-011, SURF-002, SURF-003… | broken work defaults to M |
| `BRIEF-phone-pairing-qr-render-and-countdown` Mobile Companion Pairing QR Code Presentation and Expiry Countdown | product-work | M | 7 min – 56 min | CASE-0286, CASE-0287, CASE-0288, CASE-0289… | broken work defaults to M |
| `BRIEF-req-016-claims-an-outbound-socket-and-names-nothing-that-opens-one` REQ-016 claims an outbound socket and names nothing that could open on | product-work | M | 7 min – 56 min | DEF-041, REQ-016 | broken work defaults to M |
| `BRIEF-the-campaign-never-enumerated-three-shipped-surfaces` The campaign never enumerated three surfaces that shipped | product-work | M | 7 min – 56 min | DEF-001, REQ-008, REQ-015, REQ-016… | broken work defaults to M |
| `BRIEF-the-oracle-ladders-top-rung-scores-as-its-bottom-one` The oracle ladder's top rung is scored as its weakest, so the gate pen | product-work | M | 7 min – 56 min | DEF-053 | broken work defaults to M |
| `BRIEF-upstream-server-health-probe-settings` Upstream Server Health Check and Timeout Configuration | product-work | M | 7 min – 56 min | CASE-0217, CASE-0218, CASE-0219, CASE-0220… | broken work defaults to M |
| `BRIEF-M27-sidebar-foot-readout` M27 — the sidebar foot's loopback readout is absent, and the child-pro | product-work | S | 3 min – 25 min | DEF-042, DEF-043, SURF-001 | broken work defaults to M; wording suggests a contained change |

### Wave 3 — 8 min – 1.7 h

costs its slowest member — measured wall-clock ÷ slowest member was 1.05 at the median and 1.8 at p90 across 253 real waves.

| Item | Kind | Tier | Range | Sub-tasks | Why this tier |
|---|---|---|---|---|---|
| `BRIEF-a-stale-build-can-fabricate-a-failure-and-as-easily-a-pass` A stale incremental build fabricates test failures, and can as easily  | product-work | M | 7 min – 56 min | DEF-035 | broken work defaults to M |

#### Dependency edges (49 cited, 1 inferred)

A **cited** edge is a citation somebody wrote into the registry, and it blocks: the item downstream cannot start first. An **inferred** edge is this tool's reading of a shared surface, and it only orders the work — it never blocks it, because a false edge costs somebody's parallelism and this tool is not entitled to spend that on a guess. Read the inferred ones before treating this ordering as a plan.

| From | To | How | Why |
|---|---|---|---|
| `DEF-048` | `BRIEF-G5-gapfix` | cited | BRIEF-G5-gapfix cites DEF-048 |
| `DEF-057` | `BRIEF-G5-vendor-the-campaign-version-the-gates-run` | cited | BRIEF-G5-vendor-the-campaign-version-the-gates-run cites DEF-057 |
| `DEF-001` | `BRIEF-I1-ios-shell-pairing` | cited | BRIEF-I1-ios-shell-pairing cites DEF-001 |
| `DEF-008` | `BRIEF-I1-ios-shell-pairing` | cited | BRIEF-I1-ios-shell-pairing cites DEF-008 |
| `DEF-041` | `BRIEF-I1-ios-shell-pairing` | cited | BRIEF-I1-ios-shell-pairing cites DEF-041 |
| `REQ-015` | `BRIEF-I1-ios-shell-pairing` | cited | BRIEF-I1-ios-shell-pairing cites REQ-015 |
| `DEF-011` | `BRIEF-M26-checks-board-framing` | cited | BRIEF-M26-checks-board-framing cites DEF-011 |
| `DEF-042` | `BRIEF-M27-sidebar-foot-readout` | cited | BRIEF-M27-sidebar-foot-readout cites DEF-042 |
| `DEF-043` | `BRIEF-M27-sidebar-foot-readout` | cited | BRIEF-M27-sidebar-foot-readout cites DEF-043 |
| `DEF-008` | `BRIEF-M28-decision-docket` | cited | BRIEF-M28-decision-docket cites DEF-008 |
| `DEF-033` | `BRIEF-M28-decision-docket` | cited | BRIEF-M28-decision-docket cites DEF-033 |
| `DEF-042` | `BRIEF-M28-decision-docket` | cited | BRIEF-M28-decision-docket cites DEF-042 |
| `DEF-049` | `BRIEF-M28-decision-docket` | cited | BRIEF-M28-decision-docket cites DEF-049 |
| `DEF-057` | `BRIEF-M28-decision-docket` | cited | BRIEF-M28-decision-docket cites DEF-057 |
| `DEF-001` | `BRIEF-M6-inbox-pairing` | cited | BRIEF-M6-inbox-pairing cites DEF-001 |
| `DEF-041` | `BRIEF-M6-inbox-pairing` | cited | BRIEF-M6-inbox-pairing cites DEF-041 |
| `REQ-015` | `BRIEF-M6-inbox-pairing` | cited | BRIEF-M6-inbox-pairing cites REQ-015 |
| `DEF-049` | `BRIEF-R10-index-reports-a-write-that-did-not-land` | cited | BRIEF-R10-index-reports-a-write-that-did-not-land cites DEF-049 |
| `REQ-007` | `BRIEF-R10-index-reports-a-write-that-did-not-land` | cited | BRIEF-R10-index-reports-a-write-that-did-not-land cites REQ-007 |
| `DEF-049` | `BRIEF-R21-approve-answers-200-over-a-discarded-write` | cited | BRIEF-R21-approve-answers-200-over-a-discarded-write cites DEF-049 |
| `REQ-020` | `BRIEF-R33-four-features-shipped-to-the-router-that-does-not-run` | cited | BRIEF-R33-four-features-shipped-to-the-router-that-does-not-run cites REQ-020 |
| `DEF-033` | `BRIEF-R4-C1-installer-points-at-swift` | cited | BRIEF-R4-C1-installer-points-at-swift cites DEF-033 |
| `DEF-001` | `BRIEF-X2-ios-on-glass` | cited | BRIEF-X2-ios-on-glass cites DEF-001 |
| `DEF-051` | `BRIEF-X7-campaign-artifacts-underreport` | cited | BRIEF-X7-campaign-artifacts-underreport cites DEF-051 |
| `DEF-052` | `BRIEF-X7-campaign-artifacts-underreport` | cited | BRIEF-X7-campaign-artifacts-underreport cites DEF-052 |
| `DEF-055` | `BRIEF-X7-campaign-artifacts-underreport` | cited | BRIEF-X7-campaign-artifacts-underreport cites DEF-055 |
| `DEF-056` | `BRIEF-X7-campaign-artifacts-underreport` | cited | BRIEF-X7-campaign-artifacts-underreport cites DEF-056 |
| `DEF-057` | `BRIEF-X7-campaign-artifacts-underreport` | cited | BRIEF-X7-campaign-artifacts-underreport cites DEF-057 |
| `DEF-054` | `BRIEF-X8-detectors-misattribute` | cited | BRIEF-X8-detectors-misattribute cites DEF-054 |
| `DEF-055` | `BRIEF-X8-detectors-misattribute` | cited | BRIEF-X8-detectors-misattribute cites DEF-055 |
| `DEF-057` | `BRIEF-X8-detectors-misattribute` | cited | BRIEF-X8-detectors-misattribute cites DEF-057 |
| `DEF-061` | `BRIEF-X8-detectors-misattribute` | cited | BRIEF-X8-detectors-misattribute cites DEF-061 |
| `DEF-060` | `BRIEF-a-refusal-that-cannot-say-which-capability-it-refused` | cited | BRIEF-a-refusal-that-cannot-say-which-capability-it-refused cites DEF-060 |
| `DEF-035` | `BRIEF-a-stale-build-can-fabricate-a-failure-and-as-easily-a-pass` | cited | BRIEF-a-stale-build-can-fabricate-a-failure-and-as-easily-a-pass cites DEF-035 |
| `DEF-011` | `BRIEF-a-status-word-nobody-taught-the-gate-lands-pessimistic` | cited | BRIEF-a-status-word-nobody-taught-the-gate-lands-pessimistic cites DEF-011 |
| `DEF-048` | `BRIEF-a-status-word-nobody-taught-the-gate-lands-pessimistic` | cited | BRIEF-a-status-word-nobody-taught-the-gate-lands-pessimistic cites DEF-048 |
| `DEF-058` | `BRIEF-glass-evidence-outlives-the-build-it-was-taken-from` | cited | BRIEF-glass-evidence-outlives-the-build-it-was-taken-from cites DEF-058 |
| `DEF-059` | `BRIEF-glass-evidence-outlives-the-build-it-was-taken-from` | cited | BRIEF-glass-evidence-outlives-the-build-it-was-taken-from cites DEF-059 |
| `DEF-008` | `BRIEF-no-surface-declares-its-controls-so-nothing-counts-them` | cited | BRIEF-no-surface-declares-its-controls-so-nothing-counts-them cites DEF-008 |
| `DEF-011` | `BRIEF-no-surface-declares-its-controls-so-nothing-counts-them` | cited | BRIEF-no-surface-declares-its-controls-so-nothing-counts-them cites DEF-011 |
| … | | | _10 more in ledger.json_ |

#### Not in any wave (129)

These are decisions — a person reading two documents and ruling — and they have no agent duration. Putting a wall-clock figure on them would report waiting on a human as though an agent were busy. They gate the waves rather than sitting inside them.

- **REQ-016** — A pairing exchange actually contacts the other device and stores a record only after that contact succeeds.
- **REQ-019** — A refused write is shown as the server's refusal. Success affordances are not shown for work that did not happen.
- **SURF-029** — Windows automation probe — WIN20's WinUI 3 plane witness
- **BRIEF-BLOCKED-apple-identity** — BLOCKED — the Apple developer identity. Not scheduled, not acted on.
- **BRIEF-D3-copy-proposals** — D3 — two copy decisions, drafted for the owner
- **BRIEF-F-cross-harness-skill-sync** — Cross-Harness Skill and Plugin Profile Synchronization
- **BRIEF-F-marketplace-auto-update-checker** — Marketplace Auto-Update Checker and Changelog Preview
- **BRIEF-F-session-analyzer-skill-recommender** — Session Analyzer and Multi-Harness Skill Recommender
- **BRIEF-F-skill-version-usage-history-stats** — Skill Version Usage History, Visualizations and Telemetry
- **BRIEF-G2-orchestrator-table-is-heterogeneous** — G2 — the ledger table holds two row shapes, and every reader silently drops one
- **BRIEF-G3-gapfix-2** — G3 gap-fix 2 — the property holds; the scanner meant to keep it holding does not
- **BRIEF-G3-gapfix-3** — G3 gap-fix 3 — the residue fails toward misses, and the third model has no grammar
- **BRIEF-G3-gapfix** — G3 gap-fix — the fix trades a 150ms false red for a ten-minute nameless one
- **BRIEF-G4-gapfix-2** — G4 gap-fix 2 — the item that catches unwritten records shipped one
- **BRIEF-G4-gapfix** — G4 gap-fix — the census counted the instrument into its own denominator
- **BRIEF-G5-gapfix-2** — G5 gap-fix 2 — a file moved aside and never moved back, and two clauses
- **BRIEF-G6-evidence-that-lives-in-tmp-is-not-evidence** — A sweep that proves a guard is armed, kept in `/tmp`
- **BRIEF-G7-a-citation-that-does-not-resolve-where-it-is-read** — A citation that resolved when written and does not resolve where it is read
- **BRIEF-G8-a-question-answered-at-the-wrong-scope** — A question answered at the wrong scope returns a clean answer
- **BRIEF-I4-phone-direct-install** — I4 — Let the phone install directly
- **BRIEF-M15-gapfix** — M15 gap-fix — four record defects, and the one product defect nothing guards
- **BRIEF-M18-sheets-and-gates** — M18 — twelve sheets, and the gate each decision gets
- **BRIEF-M19-gfm-viewer** — M19 — the in-app GitHub-flavoured Markdown viewer
- **BRIEF-M20-gapfix** — M20 gap-fix 1 — it does not compile, and three of four slices are only in the plan
- **BRIEF-M23-gapfix-2** — M23 gap-fix, second pass — assert the property, not the route

## Broken (55)

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
- **BRIEF-a-refusal-that-cannot-say-which-capability-it-refused** — A too-large refusal names the file and the cap but never the capability
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-a-stale-build-can-fabricate-a-failure-and-as-easily-a-pass** — A stale incremental build fabricates test failures, and can as easily fabricate a pass
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-a-status-word-nobody-taught-the-gate-lands-pessimistic** — A defect status nobody taught the gate is still classified by a guess
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-eleven-surfaces-declare-controls-that-nothing-drives** — Eleven surfaces declare their controls and no passing case drives one of them
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-glass-evidence-outlives-the-build-it-was-taken-from** — Committed glass evidence outlives the build it was taken from, and nothing goes red when it does
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-no-surface-declares-its-controls-so-nothing-counts-them** — No surface declares its controls, so the actuation census has no denominator
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-phone-pairing-qr-render-and-countdown** — Mobile Companion Pairing QR Code Presentation and Expiry Countdown
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-req-016-claims-an-outbound-socket-and-names-nothing-that-opens-one** — REQ-016 claims an outbound socket and names nothing that could open one
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-the-campaign-never-enumerated-three-shipped-surfaces** — The campaign never enumerated three surfaces that shipped
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-the-oracle-ladders-top-rung-scores-as-its-bottom-one** — The oracle ladder's top rung is scored as its weakest, so the gate penalises the hardest evidence
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-three-captures-name-a-route-they-were-not-pointed-at** — Three captures name a route they were not pointed at, and one manifest was written after the shutter
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-upstream-server-health-probe-settings** — Upstream Server Health Check and Timeout Configuration
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
- **DEF-058** — the macos-glass lane is green over window evidence captured from a pre-M22 build, and four of its cases assert a shell that no longer ships
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-059** — `Settings` is no longer a sidebar row, so the glass capture filed a neighbouring board's pixels under SURF-011 — and the committed glass evi
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-060** — A too-large refusal names the file and the cap but never the capability, so its picture cannot say what it refuses
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-061** — The capture-lineage tie pass has no notion of a route template, so a parameterised surface's capture is reported as a wrong subject
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- _…and 15 more in ledger.json_

## Unbuilt (2)

- **BRIEF-G9-two-gates-pin-a-worktree-that-no-longer-exists** — Two executable gates `cd` into a worktree that was deleted, and one is cited by a spec
  - this brief cites DEF-253, and the registry holds none of them. A citation is a link somebody wrote on purpose, so its target being absent is evidence of absence rather than a join that missed
- **BRIEF-a-brief-that-names-nothing-cannot-be-retired** — A brief that names nothing the registry holds can never leave the remaining set
  - this brief cites DEF-253, and the registry holds none of them. A citation is a link somebody wrote on purpose, so its target being absent is evidence of absence rather than a join that missed

## Unjoined (109)

- **BRIEF-2026-08-26-campaign-reckon-trawl** — Ideation Log — 2026-08-26, from test-campaign + tailings + reckon
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.08), REQ-016 (0.08), DEF-078 (0.07)
- **BRIEF-BLOCKED-apple-identity** — BLOCKED — the Apple developer identity. Not scheduled, not acted on.
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-016 (0.07), REQ-034 (0.06), REQ-027 (0.06)
- **BRIEF-D3-copy-proposals** — D3 — two copy decisions, drafted for the owner
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-016 (0.10), REQ-027 (0.10), REQ-034 (0.08)
- **BRIEF-F-marketplace-auto-update-checker** — Marketplace Auto-Update Checker and Changelog Preview
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-003 (0.04), REQ-016 (0.03), REQ-027 (0.03)
- **BRIEF-F-session-analyzer-skill-recommender** — Session Analyzer and Multi-Harness Skill Recommender
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-031 (0.05), DEF-079 (0.05), REQ-030 (0.05)
- **BRIEF-G2-orchestrator-table-is-heterogeneous** — G2 — the ledger table holds two row shapes, and every reader silently drops one
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.13), REQ-016 (0.08), REQ-034 (0.07)
- **BRIEF-G3-gapfix** — G3 gap-fix — the fix trades a 150ms false red for a ten-minute nameless one
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.10), REQ-016 (0.09), REQ-034 (0.06)
- **BRIEF-G3-gapfix-2** — G3 gap-fix 2 — the property holds; the scanner meant to keep it holding does not
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.11), REQ-016 (0.10), REQ-019 (0.06)
- **BRIEF-G3-gapfix-3** — G3 gap-fix 3 — the residue fails toward misses, and the third model has no grammar
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.09), REQ-016 (0.08), REQ-034 (0.05)
- **BRIEF-G4-gapfix** — G4 gap-fix — the census counted the instrument into its own denominator
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.12), REQ-016 (0.08), DEF-078 (0.06)
- **BRIEF-G4-gapfix-2** — G4 gap-fix 2 — the item that catches unwritten records shipped one
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.13), REQ-016 (0.09), REQ-034 (0.07)
- **BRIEF-G5-gapfix-2** — G5 gap-fix 2 — a file moved aside and never moved back, and two clauses
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.14), REQ-016 (0.09), DEF-078 (0.07)
- **BRIEF-G6-evidence-that-lives-in-tmp-is-not-evidence** — A sweep that proves a guard is armed, kept in `/tmp`
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.11), REQ-016 (0.10), REQ-034 (0.08)
- **BRIEF-G7-a-citation-that-does-not-resolve-where-it-is-read** — A citation that resolved when written and does not resolve where it is read
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.14), REQ-016 (0.09), DEF-078 (0.08)
- **BRIEF-G8-a-question-answered-at-the-wrong-scope** — A question answered at the wrong scope returns a clean answer
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.10), REQ-016 (0.09), REQ-034 (0.09)
- **BRIEF-I4-phone-direct-install** — I4 — Let the phone install directly
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-016 (0.06), REQ-019 (0.06), REQ-034 (0.05)
- **BRIEF-M15-gapfix** — M15 gap-fix — four record defects, and the one product defect nothing guards
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.14), REQ-016 (0.11), REQ-034 (0.06)
- **BRIEF-M18-sheets-and-gates** — M18 — twelve sheets, and the gate each decision gets
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.11), REQ-034 (0.07), REQ-016 (0.07)
- **BRIEF-M19-gfm-viewer** — M19 — the in-app GitHub-flavoured Markdown viewer
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.11), REQ-026 (0.07), DEF-078 (0.06)
- **BRIEF-M20-gapfix** — M20 gap-fix 1 — it does not compile, and three of four slices are only in the plan
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.11), REQ-016 (0.10), REQ-034 (0.08)
- **BRIEF-M23-gapfix** — M23 gap-fix — three rows that would let a future surface reach exit 0
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.12), REQ-016 (0.08), REQ-030 (0.06)
- **BRIEF-M23-gapfix-2** — M23 gap-fix, second pass — assert the property, not the route
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.12), REQ-016 (0.09), REQ-019 (0.07)
- **BRIEF-M23-gapfix-3** — M23 gap-fix 3 — the property is wider than the site, three times running
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.14), REQ-034 (0.08), REQ-016 (0.08)
- **BRIEF-M23-gapfix-4** — M23 gap-fix 4 — one arm, on the closure this pass shipped
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.12), REQ-016 (0.09), REQ-034 (0.08)
- **BRIEF-M23-gapfix-5** — M23 gap-fix 5 — one grep, on the fixture that already exists
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.14), REQ-016 (0.09), REQ-034 (0.08)
- **BRIEF-M23-gapfix-6** — M23 gap-fix 6 — stop arming the marker route by route; enumerate its routes
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.12), REQ-016 (0.07), REQ-026 (0.07)
- **BRIEF-M23-gapfix-7** — M23 gap-fix 7 — the enumeration's sixth row is false, and the engine says so
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.16), REQ-016 (0.10), REQ-034 (0.08)
- **BRIEF-M23-gapfix-8** — M23 gap-fix 8 — one grep, in the file the last pass was raised to fix
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.12), REQ-016 (0.11), REQ-034 (0.08)
- **BRIEF-M29-disable-a-server-is-drawn-with-nothing-behind-it** — "Disable a server" is a gate-table row with no action behind it, and no owner
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-016 (0.09), REQ-027 (0.09), REQ-034 (0.07)
- **BRIEF-M30-capability-document-source** — M30 — where a capability's documentation actually comes from
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.15), REQ-026 (0.10), REQ-016 (0.10)
- **BRIEF-M31-the-design-of-record-cannot-draw-a-disabled-primary** — The design of record cannot draw the state `DESIGN.md` requires of every control
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-016 (0.11), REQ-027 (0.11), REQ-034 (0.08)
- **BRIEF-M32-a-mock-driven-gate-is-blind-to-what-the-mock-does-not-draw** — A mock-driven fidelity gate cannot see a defect in something the mock does not draw
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.13), REQ-016 (0.12), DEF-078 (0.08)
- **BRIEF-M33-swift-build-cannot-gate-the-app-target** — `swift build` exits 0 and silent on a fault `xcodebuild` calls fatal
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-016 (0.10), REQ-027 (0.09), DEF-078 (0.09)
- **BRIEF-P7-auth-post-oauth-client** — P7 — `control-auth-post-http` needs a real OAuth client
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.10), REQ-016 (0.08), REQ-030 (0.07)
- **BRIEF-P8-launchd-watch-attributable** — P8 — make `install-launchd-watch`'s `reran` term attributable
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.10), REQ-034 (0.06), REQ-016 (0.06)
- **BRIEF-R17-a-failed-index-can-leave-no-trace** — R17 — a failed index leaves a recorded error for one server and nothing at all for another
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.11), REQ-034 (0.11), REQ-016 (0.10)
- **BRIEF-R17-gapfix** — R17 gap-fix — the fix is right; the claim is wider than the evidence
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.12), REQ-034 (0.08), REQ-016 (0.08)
- **BRIEF-R17-gapfix-2** — R17 gap-fix 2 — two clauses, both a withdrawn claim outliving its withdrawal
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.11), REQ-019 (0.09), DEF-078 (0.07)
- **BRIEF-R17-gapfix-3** — R17 gap-fix 3 — one claim, two homes, and a sweep that could not see one of them
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.12), REQ-016 (0.09), DEF-078 (0.07)
- **BRIEF-R17-gapfix-4** — R17 gap-fix 4 — stop stating a rate that the next measurement keeps refuting
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.12), REQ-016 (0.10), DEF-078 (0.07)
- _…and 69 more in ledger.json_

## Undecided (19)

- **BRIEF-F-cross-harness-skill-sync** — Cross-Harness Skill and Plugin Profile Synchronization
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-F-skill-version-usage-history-stats** — Skill Version Usage History, Visualizations and Telemetry
  - the brief declares status 'in-progress' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **BRIEF-M25-board-columns-do-not-flex** — M25 — closed: the width came from the controls row, not the columns
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-M34-the-menu-badge-is-unmeasurable-by-any-lane** — The one new user-visible behaviour in M20's Slice A cannot be measured by any lane we have
  - the brief declares status 'to-triage' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **BRIEF-M38-phone-cannot-approve-a-tool-surface** — The phone can be told a tool surface changed, and there is no honest way for it to accept one
  - the brief declares status 'to-triage' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **BRIEF-R8-auth-rejection-visible** — R8 — an upstream that refuses our credentials must say so
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-X3-ios-unit-lane-empty-tree** — X3 — the iOS unit lane read an empty accessibility tree because the engine was off
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-a-security-guard-that-cannot-fail-now-guards-a-live-entry-point** — A security guard that cannot fail now guards a live entry point
  - the brief declares status 'to-triage' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **BRIEF-drive-every-data-surface-off-its-happy-path** — Drive every data surface off its happy path, and read what it actually offers
  - the brief declares status 'to-triage' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **BRIEF-observe-a-notification-banner-and-its-withdrawal** — Observe a delivered banner, and observe it being withdrawn
  - the brief declares status 'to-triage' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **BRIEF-prove-the-tool-cache-is-keyed-on-a-servers-identity** — Prove the tool cache is keyed on a server's identity, rather than asserting it
  - the brief declares status 'to-triage' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **BRIEF-put-the-router-in-a-chosen-state-and-read-the-boards** — Put the router into a chosen state and read what the boards say
  - the brief declares status 'to-triage' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **BRIEF-staged-tool-diff-visual-review** — Visual Diff Review and Approval for Staged Upstream Tool Changes
  - the requirement this brief maps to is contradicted or vacuous; the document and the build disagree
- **BRIEF-the-document-route-can-serve-none-of-this-machines-upstreams** — The document route can serve none of this machine's twenty-one upstreams
  - looks done, but the join to the registry is a token-overlap guess, not a citation; and the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-the-relabel-gate-cannot-fire-on-any-ledger-it-writes** — The remaining-work gate against re-labelling cannot fire on any ledger it writes
  - the brief declares status 'to-triage' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **BRIEF-twenty-eight-visual-claims-cite-artifacts-that-are-not-pictures** — Twenty-eight visual claims stand on artifacts that are not pictures
  - the brief declares status 'to-triage' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **BRIEF-upstream-auth-expiry-desktop-notification** — Proactive Desktop Notification for Upstream Authentication Expiry
  - looks done, but the strongest oracle behind it is 'none', below the 'outcome' floor for retiring intent; and the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **REQ-016** — A pairing exchange actually contacts the other device and stores a record only after that contact succeeds.
  - requirement evidence 'vacuous' is a disagreement between the documents and the build; a person rules on it, an instrument cannot
- **REQ-019** — A refused write is shown as the server's refusal. Success affordances are not shown for work that did not happen.
  - requirement evidence 'contradicted' is a disagreement between the documents and the build; a person rules on it, an instrument cannot

## Unnamed (1)

- **SURF-029** — Windows automation probe — WIN20's WinUI 3 plane witness
  - the campaign found this surface; no brief and no requirement claims it

## Decisions on the record (77)

Not remaining work, and not done either. Each of these was ruled out by somebody, and the reason it was ruled out can stop being true — a state that had no hook may get one, an account that could not be reached may become reachable. They stay on the ledger so that when the reason expires, the item is still there.

- **CASE-0002** — SURF-001 · ?
  - n/a: posting Cmd+1–7 to a background pid does not change SwiftUI's focused scene (measured: title stayed Inbox then Activity); proving the shortcuts requires the window frontmost, which this campaign refuses
- **CASE-0004** — SURF-009 · ?
  - n/a: NSStatusItem is not an AXPress target while MCPRouter is backgrounded; this campaign never activates, so the popover cannot be opened or photographed
- **CASE-0006** — SURF-009 · ?
  - n/a: NSStatusItem is not an AXPress target while MCPRouter is backgrounded; inbox band never opened
- **CASE-0109** — SURF-009 · ?
  - n/a: status item not pressable in background; SURF-009 popover uncaptured. Raster-visual of the popover is unreachable under the no-activate constraint
- **CASE-0210** — SURF-002 · ?
  - n/a: the frame was refused. A live launch that is behind everything never finishes laying out, so screencapture returns an unpainted surface and bin/paint-check.py withholds it
- **CASE-0304** — SURF-041 · ?
  - n/a: not reachable from the shell's navigation, so the destination sweep never opens it. WIN11. Not a destination and not addressable by a route: it is raised from the notification area. Reaching it needs an actuation th
- **CASE-0305** — SURF-042 · ?
  - n/a: not reachable from the shell's navigation, so the destination sweep never opens it. WIN12. A ContentDialog reached from the Inbox board's `Pair iPhone…`. One literal control name; the pairing code and countdown are 
- **CASE-0306** — SURF-043 · ?
  - n/a: not reachable from the shell's navigation, so the destination sweep never opens it. WIN16. Reached from Skills, Discover or Inbox rather than from the shell's own navigation.
- **CASE-0307** — SURF-044 · ?
  - n/a: not reachable from the shell's navigation, so the destination sweep never opens it. WIN7's detail dialog. DiscoverDetailContent.xaml declares NO literal control name and no AutomationProperties.Name at all, so nothi
- **BRIEF-D1-deferred-router** — D1 — The deferred register: router side
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-D2-deferred-mac** — D2 — The deferred register: Mac surfaces and the design authority
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-D3-deferred-phone-harness** — D3 — The deferred register: phone copy, and the harness limit
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-F1-swift-workspace** — F1 — Swift workspace, shared kit, and the three targets
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-F2-design-system** — F2 — The design system in SwiftUI
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-F3-control-client** — F3 — Typed control-API client and models
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-F4-tracker-failure-states** — F4 — ServerStateTracker cannot report failure
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-G1-gate-hygiene** — G1 — Stop the checks blaming the app for being out of date
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-G10-make-acceptance-is-red-on-main-so-every-enrolment-into-it-is-inert** — `make acceptance` dies at its first lane, so enrolling a lane into it delivers nothing
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-G3-make-test-is-not-deterministic** — G3 — `make test` is green on the second run, which is not a gate
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-G4-assertions-that-do-not-read-their-own-quantity** — G4 — assertions that do not read the quantity they are named for
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-G4-gapfix-3** — G4 gap-fix 3 — the two gates this item shipped both violate the doctrine this item wrote
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-I2-ios-discover** — I2 — iPhone: Discover and detail
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-I3-ios-triage** — I3 — iPhone: Triage, Queue, Library, Settings
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-M1-mac-shell** — M1 — Mac window shell, menu bar commands, keyboard
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-M12-staleness-in-destructive-dialogs** — M12 — Staleness and an as-of time inside a destructive dialog
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.

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

