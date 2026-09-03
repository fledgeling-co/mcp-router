# Reckoning — mcp-router

198 piece(s) of work remain — 64 product, 19 evidence, 115 decision — across 630 ledger rows. This reckoning speaks for 206/216 (95%) of the campaign's designed cases and 26/41 (63%) of its stated requirements; the rest is not known to be done, it is simply not known. 90 brief(s) could not be tied to the registry at all; they are listed as `unjoined` and counted as decision work, rather than assumed unbuilt.

## What it can speak for

| Axis | Measured | Of | % | What the number means |
|---|---:|---:|---:|---|
| Cases adjudicated | 206 | 216 | 95.4% | an instrument returned a verdict on the product — pass or fail. A fail is knowledge; this is not a pass rate. |
| Cases ruled out by decision | 9 | 216 | 4.2% | somebody ruled the cell out of scope or not applicable. A decision, not a measurement, and it is kept out of the line above on purpose. |
| Requirements observed | 26 | 41 | 63.4% | somebody watched it happen, rather than the project reporting it of itself. |
| Surfaces spoken for | 43 | 47 | 91.5% | at least one case on this surface reached a verdict. |
| Briefs joined to evidence | 64 | 224 | 28.6% | the brief could be tied to something in the registry at all. |

_Each figure is a lower bound. Every `unnamed` row is a surface the documents never described, which means the true denominator is larger than the one the documents can supply._

## What remains

Two counts, because they answer different questions. **Rows** is every entity on both sides, and it is total by construction — that is what makes the gate meaningful. **Work** is what somebody would actually schedule: a failing case and the defect it evidences are one job, and blocked cases are counted as the blockers behind them rather than one by one.

| Class | Work | Rows | Kind | What it is |
|---|---:|---:|---|---|
| `unjoined` | 90 | 90 | decision-work | named in a brief; the join reached nothing, so its state is unknown either way |
| `broken` | 64 | 72 | product-work | measured, and the answer was no |
| `unmeasured` | 18 + 1 blockers | 23 | evidence-work | nobody found out — the work here is becoming able to tell |
| `undecided` | 25 | 25 | decision-work | the documents and the evidence disagree; needs a person |
| `waived` | 0 | 88 | exception | somebody decided not to — an exception, and it stays visible |
| `verified-done` | 0 | 332 | none | not remaining; kept so the denominator is honest |

## What unblocks the most

Blocked cases cluster: a handful of causes usually account for most of them. Resolving these in order returns the most measurement per unit of work.

| Blocker | Cases it unblocks | Coverage returned | Cause |
|---|---:|---:|---|
| `BLOCK-0001` | 1 | +1/216 (+0.5 pts) | unoracled: the drawn badge on the app's own menu has no channel. SwiftUI does not publish an NSMenuItem's badge to the accessibility plane; AXSize is  |

## The schedule

Every duration below is **wall-clock for one agent unit**, from a corpus of 1,842 measured Opus 4.8 and Opus 5 subagent runs across 88 sessions and 31 projects (14 Jul – 30 Aug 2026). Ranges are p25–p90 and are printed as ranges because the measured spread demands it: p90 ÷ median is 3.4 for build work and 3.1 for research, so any single number would be wrong by a factor of three in the ordinary case. Provenance, method and limits: `references/estimation.md`.

**5.4 h – 11 h across 3 wave(s) at up to 8 concurrent agents**, against roughly 21 h if the same work ran one item at a time. wall-clock for 3 wave(s) at up to 8 concurrent agents, summed. The implied speedup over running the same work serially is 3.9x, within the 2.2x median / 4.0x p90 measured on this corpus.

These figures do not carry a failure rate. A unit that ran forty minutes and produced work that was later rejected is counted the same as one that landed, so this answers how long an agent will be busy, not how long until the work is accepted.

| Wave | Items | Slots | Range | Serial | Bounded by |
|---:|---:|---:|---|---|---|
| 1 | 53 | 8 | 3.5 h – 6.1 h | 14 h | observed-speedup-ceiling |
| 2 | 29 | 8 | 1.8 h – 3.3 h | 7.1 h | observed-speedup-ceiling |
| 3 | 1 | 1 | 8 min – 1.7 h | 15 min | slowest-member |

### Wave 1 — 3.5 h – 6.1 h

costs its slowest member — measured wall-clock ÷ slowest member was 1.05 at the median and 1.8 at p90 across 253 real waves; with 53 item(s) the slowest-member figure would imply a speedup better than the 4.0x p90 ever measured here, so the low end is held to that instead; 53 members is above the observed concurrency ceiling of 8, where the slowest-member property degrades, so the upper bound is widened.

| Item | Kind | Tier | Range | Sub-tasks | Why this tier |
|---|---|---|---|---|---|
| `BLOCK-0001` unoracled: the drawn badge on the app's own menu has no channel. Swift | evidence | S | 3 min – 25 min | 1 case(s): CASE-0197 | one cause behind 1 case(s); sized by the hook, not the cases |
| `DEF-001` Pairing transport is unimplemented | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-011` Cleanup's per-row actions are specified by the design and drawn by not | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-055` vacuity-check's blind-mutation pass examines non-tests and mis-reads S | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-057` the vendored fledgeling-plugins submodule is test-campaign 0.5.0 while | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `REQ-015` Mac Pairing sheet shows an 8-character Crockford code and QR; the phon | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `DEF-008` iOS tab buttons carry the icon name as their accessibility identifier, | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-041` REQ-016's declared outbound-socket effect has no provider in productio | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-049`  | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-054` attach-shots --apply would attach the design mock render as the build' | product-work | L | 14 min – 68 min | — | broken work defaults to M; severity high |
| `DEF-063` A stdio child that starts and then exits is not noticed, so acquisitio | product-work | L | 14 min – 68 min | — | broken work defaults to M; wording suggests it spans more than one surface |
| `DEF-033` the OAuth parity lane failed once inside a full gate and has not repro | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-059` `Settings` is no longer a sidebar row, so the glass capture filed a ne | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-061` The capture-lineage tie pass has no notion of a route template, so a p | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-052` evidence-page.py and campaign.py's ledger writer both skip the defect  | product-work | L | 14 min – 68 min | — | broken work defaults to M; severity high |
| `DEF-053` strict-check.py omits effect-witness from EFFECT_RUNGS, so the ladder' | product-work | L | 14 min – 68 min | — | broken work defaults to M; severity high |
| `DEF-090` Only 41 of 219 briefs name anything the registry holds, so the reckoni | product-work | L | 14 min – 68 min | — | broken work defaults to M; wording suggests it spans more than one surface |
| `DEF-051`  | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-056` campaign.py's ledger writer prints only cases filed under a surface, s | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-058` the macos-glass lane is green over window evidence captured from a pre | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-060` A too-large refusal names the file and the cap but never the capabilit | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-064` Three Settings and pairing controls the design draws have no counterpa | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `REQ-007` Numbers the router does not observe are never displayed. There is no f | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-008` The menu-bar popover shows a readout, attention rows, and an inbox ban | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-020` install.sh flips to the Swift binary and retires src/*.ts once parity  | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-034` The router says when an upstream's credential is running out or has be | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `DEF-043` the sidebar foot's loopback readout is absent from the build on every  | product-work | S | 3 min – 25 min | — | broken work defaults to M; wording suggests a contained change |
| `DEF-083` The winget manifest points at a placeholder URL because nothing publis | product-work | L | 14 min – 68 min | — | broken work defaults to M; wording suggests it spans more than one surface |
| `BRIEF-R9-sdk-drops-upstream-message` R9 — the upstream's own words survive the SDK that drops them | evidence-work | M | 7 min – 56 min | DEF-047 | unmeasured work defaults to M |
| `BRIEF-X1-ios-a11y-harness` X1 — the iOS accessibility-tree harness, and the two surfaces that wer | evidence-work | M | 7 min – 56 min | DEF-029 | unmeasured work defaults to M |
| `BRIEF-an-effect-class-the-census-cannot-name-reads-as-no-effect` An effect class the census cannot name reads as no effect at all | product-work | M | 7 min – 56 min | REQ-016 | broken work defaults to M |
| `BRIEF-eleven-surfaces-declare-controls-that-nothing-drives` Eleven surfaces declare their controls and no passing case drives one  | product-work | M | 7 min – 56 min | SURF-001, SURF-002, SURF-004 | broken work defaults to M |
| `DEF-062` The Skills board's held-update sheet offers no decision — its only con | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-065` The Insights analyst panel is an empty state with a dead button — thre | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-070` GET /servers discloses every stdio upstream's full argv to an unauthen | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-081` WIN23's logon trigger has never been watched to fire; the restart has  | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-082` Nothing on this host can press a toast button, or say which applicatio | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-131` The command-shape check cannot see a bare command NAME, so a two-word  | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-280` Six diagnostics-bundle cases are filed under REQ-035, which is the Win | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-300` The notification-area icon does not come back after an Explorer restar | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-302` The Cleanup board's Remove selected button reaches nothing and asks no | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-340` The Discover board draws neither of the design's two scoping controls  | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-361` Twelve wave-slot landings merged to main with no verify verdict record | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `DEF-362` M18 and R19 carry a standing Needs More Work verdict and their gap-fix | product-work | M | 7 min – 56 min | — | broken work defaults to M |
| `REQ-002` The tool cache is keyed on each server's command/args/env identity and | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-004` The Servers board reflects live server states from ServerStateTracker  | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-005` When the tracker is stale or the router is not running, live counts go | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-009` Disposing an inbox item immediately withdraws its notification banner; | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-010` The phone exposes Discover, Triage, Queue, Library and Settings; Triag | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-014` Swift RouterCore matches the TypeScript reference on the parity corpus | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-017` Every data surface ships the nine DESIGN.md §5 states with real copy o | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `REQ-018` Undo is the Mac contract for reversible acts; a named-consequence dial | evidence-work | M | 7 min – 56 min | — | unmeasured work defaults to M |
| `DEF-301` The ambient surface reports AtRest without anything ever reading the r | product-work | S | 3 min – 25 min | — | broken work defaults to M; wording suggests a contained change |

### Wave 2 — 1.8 h – 3.3 h

costs its slowest member — measured wall-clock ÷ slowest member was 1.05 at the median and 1.8 at p90 across 253 real waves; with 29 item(s) the slowest-member figure would imply a speedup better than the 4.0x p90 ever measured here, so the low end is held to that instead; 29 members is above the observed concurrency ceiling of 8, where the slowest-member property degrades, so the upper bound is widened.

| Item | Kind | Tier | Range | Sub-tasks | Why this tier |
|---|---|---|---|---|---|
| `DEF-035` an incremental Swift build after adding an enum case reports impossibl | product-work | M | 7 min – 56 min | — | broken work defaults to M |
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
| `BRIEF-a-brief-that-names-nothing-cannot-be-retired` A brief that names nothing the registry holds can never leave the rema | product-work | M | 7 min – 56 min | DEF-002, DEF-040, DEF-063, DEF-090… | broken work defaults to M |
| `BRIEF-a-refusal-that-cannot-say-which-capability-it-refused` A too-large refusal names the file and the cap but never the capabilit | product-work | M | 7 min – 56 min | DEF-060 | broken work defaults to M |
| `BRIEF-a-status-word-nobody-taught-the-gate-lands-pessimistic` A defect status nobody taught the gate is still classified by a guess | product-work | M | 7 min – 56 min | CASE-0355, CASE-0356, DEF-011, DEF-048… | broken work defaults to M |
| `BRIEF-daemon-status-popover-interactive-testability` Background Status Item and Popover Accessible Testability | evidence-work | M | 7 min – 56 min | CASE-0004, CASE-0006, CASE-0109, REQ-008… | unmeasured work defaults to M |
| `BRIEF-defect-vocabulary-blocks-the-reckoning-gate` The remaining-work gate fails every run on words nobody taught it | product-work | M | 7 min – 56 min | CASE-0355, CASE-0356, DEF-011, DEF-048… | broken work defaults to M |
| `BRIEF-glass-evidence-outlives-the-build-it-was-taken-from` Committed glass evidence outlives the build it was taken from, and not | product-work | M | 7 min – 56 min | CASE-0001, CASE-0016, CASE-0101, CASE-0111… | broken work defaults to M |
| `BRIEF-local-network-device-pairing-handshake` Local Network Device Discovery and Mutual Pairing Handshake | product-work | M | 7 min – 56 min | DEF-001, REQ-015, REQ-016, SURF-010… | broken work defaults to M |
| `BRIEF-no-surface-declares-its-controls-so-nothing-counts-them` No surface declares its controls, so the actuation census has no denom | product-work | M | 7 min – 56 min | DEF-008, DEF-011, SURF-002, SURF-003… | broken work defaults to M |
| `BRIEF-phone-pairing-qr-render-and-countdown` Mobile Companion Pairing QR Code Presentation and Expiry Countdown | product-work | M | 7 min – 56 min | CASE-0286, CASE-0287, CASE-0288, CASE-0289… | broken work defaults to M |
| `BRIEF-req-016-claims-an-outbound-socket-and-names-nothing-that-opens-one` REQ-016 claims an outbound socket and names nothing that could open on | product-work | M | 7 min – 56 min | DEF-041, REQ-016 | broken work defaults to M |
| `BRIEF-the-blind-sweep-runs-on-a-vocabulary-nobody-wrote-for-this-project` The blind-mutation sweep runs on borrowed vocabulary, so its three fin | product-work | M | 7 min – 56 min | DEF-048, DEF-055 | broken work defaults to M |
| `BRIEF-the-oracle-ladders-top-rung-scores-as-its-bottom-one` The oracle ladder's top rung is scored as its weakest, so the gate pen | product-work | M | 7 min – 56 min | DEF-053 | broken work defaults to M |
| `BRIEF-three-captures-name-a-route-they-were-not-pointed-at` Three captures name a route they were not pointed at, and one manifest | product-work | M | 7 min – 56 min | CASE-0001, CASE-0016, CASE-0101, CASE-0111… | broken work defaults to M |
| `BRIEF-upstream-auth-expiry-desktop-notification` Proactive Desktop Notification for Upstream Authentication Expiry | evidence-work | M | 7 min – 56 min | REQ-034 | unmeasured work defaults to M |
| `BRIEF-upstream-server-health-probe-settings` Upstream Server Health Check and Timeout Configuration | product-work | M | 7 min – 56 min | CASE-0217, CASE-0218, CASE-0219, CASE-0220… | broken work defaults to M |
| `BRIEF-M27-sidebar-foot-readout` M27 — the sidebar foot's loopback readout is absent, and the child-pro | product-work | S | 3 min – 25 min | DEF-042, DEF-043, SURF-001 | broken work defaults to M; wording suggests a contained change |

### Wave 3 — 8 min – 1.7 h

costs its slowest member — measured wall-clock ÷ slowest member was 1.05 at the median and 1.8 at p90 across 253 real waves.

| Item | Kind | Tier | Range | Sub-tasks | Why this tier |
|---|---|---|---|---|---|
| `BRIEF-a-stale-build-can-fabricate-a-failure-and-as-easily-a-pass` A stale incremental build fabricates test failures, and can as easily  | product-work | M | 7 min – 56 min | DEF-035 | broken work defaults to M |

#### Dependency edges (54 cited, 1 inferred)

A **cited** edge is a citation somebody wrote into the registry, and it blocks: the item downstream cannot start first. An **inferred** edge is this tool's reading of a shared surface, and it only orders the work — it never blocks it, because a false edge costs somebody's parallelism and this tool is not entitled to spend that on a guess. Read the inferred ones before treating this ordering as a plan.

| From | To | How | Why |
|---|---|---|---|
| `DEF-057` | `BRIEF-G5-vendor-the-campaign-version-the-gates-run` | cited | BRIEF-G5-vendor-the-campaign-version-the-gates-run cites DEF-057 |
| `DEF-001` | `BRIEF-I1-ios-shell-pairing` | cited | BRIEF-I1-ios-shell-pairing cites DEF-001 |
| `DEF-008` | `BRIEF-I1-ios-shell-pairing` | cited | BRIEF-I1-ios-shell-pairing cites DEF-008 |
| `DEF-041` | `BRIEF-I1-ios-shell-pairing` | cited | BRIEF-I1-ios-shell-pairing cites DEF-041 |
| `REQ-015` | `BRIEF-I1-ios-shell-pairing` | cited | BRIEF-I1-ios-shell-pairing cites REQ-015 |
| `DEF-011` | `BRIEF-M26-checks-board-framing` | cited | BRIEF-M26-checks-board-framing cites DEF-011 |
| `DEF-043` | `BRIEF-M27-sidebar-foot-readout` | cited | BRIEF-M27-sidebar-foot-readout cites DEF-043 |
| `DEF-008` | `BRIEF-M28-decision-docket` | cited | BRIEF-M28-decision-docket cites DEF-008 |
| `DEF-033` | `BRIEF-M28-decision-docket` | cited | BRIEF-M28-decision-docket cites DEF-033 |
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
| `DEF-063` | `BRIEF-a-brief-that-names-nothing-cannot-be-retired` | cited | BRIEF-a-brief-that-names-nothing-cannot-be-retired cites DEF-063 |
| `DEF-090` | `BRIEF-a-brief-that-names-nothing-cannot-be-retired` | cited | BRIEF-a-brief-that-names-nothing-cannot-be-retired cites DEF-090 |
| `DEF-060` | `BRIEF-a-refusal-that-cannot-say-which-capability-it-refused` | cited | BRIEF-a-refusal-that-cannot-say-which-capability-it-refused cites DEF-060 |
| `DEF-035` | `BRIEF-a-stale-build-can-fabricate-a-failure-and-as-easily-a-pass` | cited | BRIEF-a-stale-build-can-fabricate-a-failure-and-as-easily-a-pass cites DEF-035 |
| `DEF-011` | `BRIEF-a-status-word-nobody-taught-the-gate-lands-pessimistic` | cited | BRIEF-a-status-word-nobody-taught-the-gate-lands-pessimistic cites DEF-011 |
| `DEF-055` | `BRIEF-a-status-word-nobody-taught-the-gate-lands-pessimistic` | cited | BRIEF-a-status-word-nobody-taught-the-gate-lands-pessimistic cites DEF-055 |
| `REQ-008` | `BRIEF-daemon-status-popover-interactive-testability` | cited | BRIEF-daemon-status-popover-interactive-testability cites REQ-008 |
| `DEF-011` | `BRIEF-defect-vocabulary-blocks-the-reckoning-gate` | cited | BRIEF-defect-vocabulary-blocks-the-reckoning-gate cites DEF-011 |
| `DEF-058` | `BRIEF-glass-evidence-outlives-the-build-it-was-taken-from` | cited | BRIEF-glass-evidence-outlives-the-build-it-was-taken-from cites DEF-058 |
| `DEF-059` | `BRIEF-glass-evidence-outlives-the-build-it-was-taken-from` | cited | BRIEF-glass-evidence-outlives-the-build-it-was-taken-from cites DEF-059 |
| `DEF-001` | `BRIEF-local-network-device-pairing-handshake` | cited | BRIEF-local-network-device-pairing-handshake cites DEF-001 |
| … | | | _15 more in ledger.json_ |

#### Not in any wave (115)

These are decisions — a person reading two documents and ruling — and they have no agent duration. Putting a wall-clock figure on them would report waiting on a human as though an agent were busy. They gate the waves rather than sitting inside them.

- **REQ-016** — A pairing exchange actually contacts the other device and stores a record only after that contact succeeds.
- **REQ-019** — A refused write is shown as the server's refusal. Success affordances are not shown for work that did not happen.
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
- **BRIEF-G5-gapfix** — G5 gap-fix — the +4 is the instrument, and the trap is wider than the submodule pin
- **BRIEF-G8-a-question-answered-at-the-wrong-scope** — A question answered at the wrong scope returns a clean answer
- **BRIEF-I4-phone-direct-install** — I4 — Let the phone install directly
- **BRIEF-M15-gapfix** — M15 gap-fix — four record defects, and the one product defect nothing guards
- **BRIEF-M18-sheets-and-gates** — M18 — twelve sheets, and the gate each decision gets
- **BRIEF-M19-gfm-viewer** — M19 — the in-app GitHub-flavoured Markdown viewer
- **BRIEF-M20-gapfix** — M20 gap-fix 1 — it does not compile, and three of four slices are only in the plan
- **BRIEF-M23-gapfix-2** — M23 gap-fix, second pass — assert the property, not the route
- **BRIEF-M23-gapfix-3** — M23 gap-fix 3 — the property is wider than the site, three times running
- **BRIEF-M23-gapfix-4** — M23 gap-fix 4 — one arm, on the closure this pass shipped

## Broken (64)

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
- **BRIEF-a-brief-that-names-nothing-cannot-be-retired** — A brief that names nothing the registry holds can never leave the remaining set
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-a-refusal-that-cannot-say-which-capability-it-refused** — A too-large refusal names the file and the cap but never the capability
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-a-stale-build-can-fabricate-a-failure-and-as-easily-a-pass** — A stale incremental build fabricates test failures, and can as easily fabricate a pass
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-a-status-word-nobody-taught-the-gate-lands-pessimistic** — A defect status nobody taught the gate is still classified by a guess
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-an-effect-class-the-census-cannot-name-reads-as-no-effect** — An effect class the census cannot name reads as no effect at all
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-defect-vocabulary-blocks-the-reckoning-gate** — The remaining-work gate fails every run on words nobody taught it
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-eleven-surfaces-declare-controls-that-nothing-drives** — Eleven surfaces declare their controls and no passing case drives one of them
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-glass-evidence-outlives-the-build-it-was-taken-from** — Committed glass evidence outlives the build it was taken from, and nothing goes red when it does
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-local-network-device-pairing-handshake** — Local Network Device Discovery and Mutual Pairing Handshake
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-no-surface-declares-its-controls-so-nothing-counts-them** — No surface declares its controls, so the actuation census has no denominator
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-phone-pairing-qr-render-and-countdown** — Mobile Companion Pairing QR Code Presentation and Expiry Countdown
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-req-016-claims-an-outbound-socket-and-names-nothing-that-opens-one** — REQ-016 claims an outbound socket and names nothing that could open one
  - the registry records a defect or a failing case against this brief's subject
- **BRIEF-the-blind-sweep-runs-on-a-vocabulary-nobody-wrote-for-this-project** — The blind-mutation sweep runs on borrowed vocabulary, so its three findings settle nothing
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
  - the registry records this defect as 'partially-fixed', which stays in the owing set. A half still broken owes a reproduction for that half, and retiring it here would make this tool under-report for the first time.
- **DEF-033** — the OAuth parity lane failed once inside a full gate and has not reproduced
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-035** — an incremental Swift build after adding an enum case reports impossible test failures
  - a defect is a measured negative result — the unit of product work behind every failing case that cites it
- **DEF-041** — REQ-016's declared outbound-socket effect has no provider in production source
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
- _…and 24 more in ledger.json_

## Unjoined (90)

- **BRIEF-2026-08-26-campaign-reckon-trawl** — Ideation Log — 2026-08-26, from test-campaign + tailings + reckon
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.08), REQ-016 (0.08), DEF-361 (0.07)
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
  - nearest the join considered: REQ-027 (0.10), REQ-016 (0.09), REQ-080 (0.06)
- **BRIEF-G3-gapfix-2** — G3 gap-fix 2 — the property holds; the scanner meant to keep it holding does not
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.11), REQ-016 (0.10), REQ-019 (0.06)
- **BRIEF-G3-gapfix-3** — G3 gap-fix 3 — the residue fails toward misses, and the third model has no grammar
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.09), REQ-016 (0.08), DEF-320 (0.06)
- **BRIEF-G4-gapfix** — G4 gap-fix — the census counted the instrument into its own denominator
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.12), REQ-016 (0.08), DEF-320 (0.07)
- **BRIEF-G4-gapfix-2** — G4 gap-fix 2 — the item that catches unwritten records shipped one
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.13), REQ-016 (0.09), REQ-040 (0.07)
- **BRIEF-G5-gapfix-2** — G5 gap-fix 2 — a file moved aside and never moved back, and two clauses
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.14), REQ-016 (0.09), DEF-078 (0.07)
- **BRIEF-G8-a-question-answered-at-the-wrong-scope** — A question answered at the wrong scope returns a clean answer
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.10), REQ-016 (0.09), REQ-034 (0.09)
- **BRIEF-M15-gapfix** — M15 gap-fix — four record defects, and the one product defect nothing guards
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.14), REQ-016 (0.11), REQ-080 (0.07)
- **BRIEF-M18-sheets-and-gates** — M18 — twelve sheets, and the gate each decision gets
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.11), REQ-034 (0.07), REQ-016 (0.07)
- **BRIEF-M20-gapfix** — M20 gap-fix 1 — it does not compile, and three of four slices are only in the plan
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.11), REQ-016 (0.10), REQ-034 (0.08)
- **BRIEF-M23-gapfix** — M23 gap-fix — three rows that would let a future surface reach exit 0
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.12), REQ-016 (0.08), REQ-080 (0.07)
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
  - nearest the join considered: REQ-027 (0.12), REQ-016 (0.07), DEF-361 (0.07)
- **BRIEF-M23-gapfix-7** — M23 gap-fix 7 — the enumeration's sixth row is false, and the engine says so
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.16), REQ-016 (0.10), REQ-040 (0.10)
- **BRIEF-M23-gapfix-8** — M23 gap-fix 8 — one grep, in the file the last pass was raised to fix
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.12), REQ-016 (0.11), REQ-034 (0.08)
- **BRIEF-M29-disable-a-server-is-drawn-with-nothing-behind-it** — "Disable a server" is a gate-table row with no action behind it, and no owner
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-016 (0.09), REQ-027 (0.09), REQ-034 (0.07)
- **BRIEF-P8-launchd-watch-attributable** — P8 — make `install-launchd-watch`'s `reran` term attributable
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.10), REQ-080 (0.07), REQ-040 (0.07)
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
  - nearest the join considered: REQ-027 (0.12), REQ-016 (0.09), REQ-080 (0.08)
- **BRIEF-R17-gapfix-4** — R17 gap-fix 4 — stop stating a rate that the next measurement keeps refuting
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.12), REQ-016 (0.10), REQ-080 (0.07)
- **BRIEF-R19-a-stale-manifest-snapshot-clobbers-a-concurrent-write** — R19 — a watch fire saves a manifest snapshot taken before a concurrent write
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.11), REQ-019 (0.10), REQ-016 (0.07)
- **BRIEF-R19-integration** — R19 integration — a merge that needs a person, not a resolution
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.15), REQ-019 (0.08), REQ-016 (0.08)
- **BRIEF-R28-router-owns-skills-plugins-marketplaces** — R28 — The router owns skills, plugins and marketplaces, not just MCP servers
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.10), REQ-030 (0.09), DEF-087 (0.08)
- **BRIEF-R29-push-a-reload-to-live-sessions** — R29 — Push a reload to live sessions, rather than asking Claude to watch files
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.11), REQ-034 (0.09), REQ-030 (0.08)
- **BRIEF-R30-ingest-what-claude-acquires** — R30 — Ingest what Claude acquires, so the router stays the only source
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.08), REQ-030 (0.07), REQ-016 (0.06)
- **BRIEF-R31-invalidate-the-caches-a-change-outruns** — R31 — Invalidate the caches a change outruns
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.09), REQ-034 (0.08), REQ-030 (0.07)
- **BRIEF-R32-claude-desktop-has-no-live-reload** — R32 — Claude Desktop takes the config but has no live reload, and that gap is structural
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-030 (0.11), REQ-027 (0.10), REQ-016 (0.08)
- **BRIEF-R7-gapfix** — R7 gap-fix — three rows where the tool answers confidently and wrongly
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.12), REQ-016 (0.08), REQ-026 (0.08)
- **BRIEF-R7-gapfix-2** — R7 gap-fix 2 — the Gemini harness reads a file R7 has never opened
  - the join could not tie this brief to anything in the registry. That is not evidence that it was never built — it is the inferential step of this pipeline returning nothing, and a person has to read the brief and rule
  - nearest the join considered: REQ-027 (0.13), REQ-080 (0.09), REQ-016 (0.09)
- _…and 50 more in ledger.json_

## Undecided (25)

- **BRIEF-F-cross-harness-skill-sync** — Cross-Harness Skill and Plugin Profile Synchronization
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-F-skill-version-usage-history-stats** — Skill Version Usage History, Visualizations and Telemetry
  - the brief declares status 'in-progress' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **BRIEF-G5-gapfix** — G5 gap-fix — the +4 is the instrument, and the trap is wider than the submodule pin
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-I4-phone-direct-install** — I4 — Let the phone install directly
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-M19-gfm-viewer** — M19 — the in-app GitHub-flavoured Markdown viewer
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-M25-board-columns-do-not-flex** — M25 — closed: the width came from the controls row, not the columns
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-M38-phone-cannot-approve-a-tool-surface** — The phone can be told a tool surface changed, and there is no honest way for it to accept one
  - the brief declares status 'to-triage' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **BRIEF-P7-auth-post-oauth-client** — P7 — `control-auth-post-http` needs a real OAuth client
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-R2R-router-daemon** — R2-R — Swift router: the process that actually serves
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-R8-auth-rejection-visible** — R8 — an upstream that refuses our credentials must say so
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-X3-ios-unit-lane-empty-tree** — X3 — the iOS unit lane read an empty accessibility tree because the engine was off
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-a-security-guard-that-cannot-fail-now-guards-a-live-entry-point** — A security guard that cannot fail now guards a live entry point
  - the brief declares status 'to-triage' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **BRIEF-daemon-diagnostics-bundle-export** — Single Action Router Daemon Diagnostics Bundle Export
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-design-of-record-honesty-alignment** — Design of Record Parity Alignment with Honesty Guardrails
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
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
  - looks done, but the join as a whole is too weak to carry a retirement claim — route to spec-validation before retiring
- **BRIEF-the-relabel-gate-cannot-fire-on-any-ledger-it-writes** — The remaining-work gate against re-labelling cannot fire on any ledger it writes
  - the brief declares status 'to-triage' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **BRIEF-the-wave-enumerated-three-surfaces-and-bound-none** — The wave enumerated three surfaces and bound none, so the gate it was measured by got worse
  - the brief declares status 'in-progress' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **BRIEF-twenty-eight-visual-claims-cite-artifacts-that-are-not-pictures** — Twenty-eight visual claims stand on artifacts that are not pictures
  - the brief declares status 'to-triage' while the registry's evidence reads done -- the document and the evidence disagree; a person rules, an instrument cannot
- **REQ-016** — A pairing exchange actually contacts the other device and stores a record only after that contact succeeds.
  - requirement evidence 'vacuous' is a disagreement between the documents and the build; a person rules on it, an instrument cannot
- **REQ-019** — A refused write is shown as the server's refusal. Success affordances are not shown for work that did not happen.
  - requirement evidence 'contradicted' is a disagreement between the documents and the build; a person rules on it, an instrument cannot

## Decisions on the record (88)

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
- **CASE-0335** — SURF-041 · ?
  - n/a: not reachable from the shell's navigation, so the destination sweep never opens it. WIN11. Not a destination and not addressable by a route: it is raised from the notification area. Reaching it needs an actuation th
- **CASE-0336** — SURF-042 · ?
  - n/a: not reachable from the shell's navigation, so the destination sweep never opens it. WIN12. A ContentDialog reached from the Inbox board's `Pair iPhone…`. One literal control name; the pairing code and countdown are 
- **CASE-0337** — SURF-043 · ?
  - n/a: not reachable from the shell's navigation, so the destination sweep never opens it. WIN16. Reached from Skills, Discover or Inbox rather than from the shell's own navigation.
- **CASE-0338** — SURF-044 · ?
  - n/a: not reachable from the shell's navigation, so the destination sweep never opens it. WIN7's detail dialog. DiscoverDetailContent.xaml declares NO literal control name and no AutomationProperties.Name at all, so nothi
- **DEF-048** — test-campaign 0.9.1's blind-mutation pass is dominated by its own verb configuration on this codebase, in both direction
  - the registry records this defect as 'superseded' — a ruling that the row owes nothing, rather than a record of anybody repairing it. It stays on the ledger because the ruling can stop being true.
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
- **BRIEF-G6-evidence-that-lives-in-tmp-is-not-evidence** — A sweep that proves a guard is armed, kept in `/tmp`
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-G7-a-citation-that-does-not-resolve-where-it-is-read** — A citation that resolved when written and does not resolve where it is read
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.
- **BRIEF-G9-two-gates-pin-a-worktree-that-no-longer-exists** — Two executable gates `cd` into a worktree that was deleted, and one is cited by a spec
  - the brief declares status 'completed' — a decision, not a measurement. It stays on the ledger because the reason for it may stop being true.

## Requirements standing on the project's own word (13)

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
- **REQ-034** (`reported`) — The router says when an upstream's credential is running out or has been refused, before a tool call fails on it — and it can say that it do
  - obtain independent evidence — this is the project's own account of itself

