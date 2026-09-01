# Goal: finish every wave of remaining work, with the Windows client actually measured

- **slug:** finish-all-waves
- **armed:** 2026-09-02 (local)
- **project:** C:/Dev/mcp-router
- **bound:** 200 turns / 2026-09-05T09:00:00Z / stuck after 4 identical failures

## Objective

Drive every scheduled item in the reckoning to merged-and-verified, and get the Windows
client — 24 items, 220 C# files, 38 XAML files, shipped 2026-08-31..09-01 by a lesser
model — into the measurement system for the first time. Finished means a reckoning
**newer than HEAD** reports zero product-work and zero evidence-work, every drawn Windows
surface is named and cased in the campaign registry, and the UIA lane holds a passing
verdict against the real shell rather than against its own probe.

## Why this run exists rather than resuming the last one

The `all-remaining-work` run armed 2026-09-01 13:30 local and reported `end_reason: met`
at turn 1, **eight minutes later**, with F-001..F-007 still reading `pending`/`in-progress`
in its own brief. It was not lying about its gates; its gates could not express its goal.

| Its gate | What it actually measures | Why it could not fail |
|---|---|---|
| `reckon … check` | the ledger's **partition** is total | printed `unbuilt 2 · unjoined 110 · broken 56 · unmeasured 17 · undecided 18` **and exited 0** |
| `brief-target-gate.py` | regression against a floor | sat at `0 above, 0 below` — passes by construction |
| `strict-check.py` | regression against a ratchet | same shape |
| `test -s docs/goals/goal-all-remaining-work.md` | a file the same session had just written | tautology |

Its stop condition was "0 unbuilt, 0 broken, 0 unmeasured, 0 undecided". Nothing it ran
could observe any of those four numbers. Two structural consequences, both fixed here:

1. **Every gate below is proved able to go both ways before arming.**
   `planning/goals/prove-gates.py` mutates each gate's real input to the state that should
   flip it, runs the gate, restores, and reads the restore back byte-for-byte. 13 arms,
   13 correct, recorded 2026-09-02. A gate nobody has watched fail is a rumour.
2. **The completion gate refuses a stale instrument.** `waves` fails when the reckoning it
   reads predates HEAD, because a ledger reporting zero *because it was written before the
   work existed* is the precise shape of the false green above.

## The finding that reframes the run

**The Windows client has never been measured, and nothing in the system said so.**

`campaign.json` declares lanes `macos-glass, ios-glass, swiftui, router-daemon, parity-wire`.
The registry holds 20 surfaces — all Mac, iOS or router — and **zero** Windows surfaces,
cases, requirements, flows or components. The only two hits for "windows" in `cases.json`
are the English word, in prose about dialogs.

So the campaign's `135 of 156 checked (87%)` and the reckoning's `27/28 surfaces spoken for
(96.4%)` are both computed over a denominator that **excludes the entire Windows client**.
That is reckon's `never-named` class doing exactly what it warns about: an unnamed surface
is invisible to a coverage percentage rather than counted against it. Sixteen drawn boards
are outside every number this project reports about itself.

WIN20 built the plane for this and it was never pointed at the product. Measured
2026-09-01T21:41Z from this session: the lane runs into WinSta0 via a scheduled task,
launches the WinUI window **without activation**, reads 36 control-view and 65 raw elements
out of process, and returns 90 passed / 0 failed / 2 honestly unoracled. Its own report
carries `subjectIsNotTheProduct: "WIN3 has not landed a drawable Windows shell"`. **WIN3
landed at `031295c3`**, so that disclosure is now a work order rather than a standing caveat.

That the tree is read *without foregrounding the window* is what makes the owner's
"every screen, for real" decision affordable: this is not the macOS `osascript` lane that
drove the owner's real screen and got a fleet killed (`RESUME.md`).

## Scope, as decided by the owner 2026-09-02

**In — "Everything that was built":** all 67 scheduled wave members (51 product-work,
16 evidence-work), plus every new item the Windows campaign and the tailings audit produce.

**Out — recorded, not guessed:** the 128 decision-work rows (110 `unjoined` briefs + 18
`undecided`). They stay in their documentary class. This is not deferral by convenience:
`ORCHESTRATOR.md` forbids writing citations in bulk to raise the join rate, because a cited
id the registry does not hold reads as evidence the thing is **absent**, so a wrong one
manufactures a finding. The `waves` gate asserts decision-work is still *counted*, so a
reckoning that silently dropped the class cannot read as progress.

**Every screen, for real** (owner, 2026-09-02): all 16 drawn Windows surfaces get a first
real UIA measurement. None of them has ever been measured, so `RESUME.md`'s "only test a
screen you changed" does not exempt them — there is no prior evidence to cite.

## Worklist

| ID | Item | Gate | Status |
|---|---|---|---|
| A-1 | Audit the 2026-08-31..09-01 sessions that built the 24 WIN items — a lesser model's account is the thing that fails, not usually its work | `tailings` worklist, ranked | pending |
| A-2 | Point the UIA lane at `MCPRouter.Shell` and clear `subjectIsNotTheProduct` | `completion-gates.py winlive` | pending |
| A-3 | Enumerate and register the 16 drawn Windows surfaces + cases in the campaign | `completion-gates.py wincoverage` | pending |
| A-4 | Add a `windows-uia` lane to `campaign.json`; every Windows case names its oracle rung | `strict-check.py planning/test-campaign` | pending |
| B-1 | Re-reckon against the current tree, with Windows in the denominator for the first time | `completion-gates.py waves` (freshness half) | pending |
| C-1 | Intake every finding from A-1..B-1 as a brief carrying `reckon-sources:` or an explicit `no-target-reason:` | `planning/brief-target-gate.py` | pending |
| D-1 | Ship wave 1 — 42 members, 8 slots | `completion-gates.py waves` | pending |
| D-2 | Ship wave 2 — 24 members | `completion-gates.py waves` | pending |
| D-3 | Ship wave 3 + every wave the Windows campaign adds | `completion-gates.py waves` | pending |
| D-4 | Merge `ai/p4`, the branch the previous fleet's `ai/win*`-scoped gate never looked at | `completion-gates.py branches` | pending |

Total: 10 phases over 67 known members, growing as A-3 and B-1 widen the denominator.

## Gates

Run by the guard at the end of every turn, in this order — cheap first, judged on exit code
alone. Baseline at arm time: **all six red**, each with a real next action.

| Name | Command | Passes when |
|---|---|---|
| `branches` | `python planning/goals/completion-gates.py branches` | no unmerged `ai/*` — every prefix, not just `ai/win*` |
| `liveness` | `python planning/goals/completion-gates.py liveness` | something moved in 90 min; **auto-passes once `waves` is clear** |
| `wincoverage` | `python planning/goals/completion-gates.py wincoverage` | all 16 drawn Windows surfaces named **and** cased |
| `winlive` | `python planning/goals/completion-gates.py winlive` | UIA verdict against the real shell, ≥1 assertion, 0 failed |
| `waves` | `python planning/goals/completion-gates.py waves` | product-work 0, evidence-work 0, on a reckoning **newer than HEAD** |
| `lane` | `python planning/goals/win-gates.py lane` | WIN18's Windows verify lane exits 0 (cached on HEAD + lane digest) |

`lane` is last and slowest; it caches against HEAD and its own content digest, so it re-runs
exactly when something it measures could differ. Its green is deliberately narrow and says so
in its own output: xcodebuild, swiftlint and the whole macOS/iOS side cannot run on this
machine, and it prints `A green run here is NOT a green repository`.

### Why `liveness` auto-passes when `waves` is clear

`ORCHESTRATOR.md` records the `ship-remaining-work` harness disarming as `stuck` at iteration
25 while three verifiers were actively writing. The diagnosis was a clock mismatch: `branches`
and `worklist` can only change when a merge lands, a merge waits on a ~40-minute fresh-context
verdict, and the Stop hook samples every 4–6 minutes — so the correct output of both gates is
byte-identical across eight or ten healthy turns and the `stuck` fingerprint fires on progress.

`liveness` is the fast-clock partner that post-mortem asked for. But a progress watchdog that
stays red when there is nothing left to progress would block a *finished* run forever, so it
reads the reckoning first and passes outright once no scheduled work remains.

## Blocked-item policy

Follow `/clarify`: settle technical forks by referral, decide craft and convention alone and
report the call in a clause, and reserve the owner for taste, cost, scope, risk and anything
irreversible. A parked item carries its reason in the ledger, never silence.

**A blocked or inconclusive check is not a pass and not a failure.** It goes to reckon's
`never-measured` class with the blocker named, and is scheduled as the blocker rather than
case by case. Never let a NOT-RUN be swallowed by a green tick — the Windows verify lane
already models this correctly and prints its 5 not-run members every run.

## Resources

| Resource | Reserved for this run | Conflicts with |
|---|---|---|
| WinSta0 / session 1 | yes — the UIA lane needs an interactive window station | another desktop session; the lane launches **without activation**, so it does not take the foreground |
| `MCPRouter-WIN20-AutomationPlaneLane` scheduled task | yes | a second concurrent UIA lane run |
| `.worktrees/<ID>` on `ai/<id>` | yes | two runners on one item — the failure that killed the 2026-08-14 fleet |
| Loopback control API port | yes | other router instances |

Owner instruction, standing: ignore harbourmaster berth/CPU/memory warnings and dispatch
anyway. That does **not** license ignoring a measured agent death.

## Delivery

- **Driver:** `/ship-fleet:ship-fleet`, then `/ship-feature:ship-feature` per item
- **Model / effort:** `claude-opus-5` / medium — owner instruction, 2026-09-02, for every subagent
- **Concurrency cap:** 8 (the reckoning's own `max_concurrency`)
- **If an agent dies:** `workflow-resume`; never double-dispatch a runner believed dead
  without checking its worktree first (`RESUME.md` §1 — duplicate runners on M1/R2/R3/I1)

## Stop conditions

- All six gates green: no unmerged branch, Windows named + cased + measured live, a
  fresh reckoning at zero scheduled work, and the Windows lane at exit 0.
- 200 turns, the 2026-09-05T09:00:00Z deadline, or 4 identical failures after escalation.
- A gate that fails identically after the escalation brief ends the run deliberately,
  with the ledger naming the wall it hit.

## Open questions

_Appended during the run._

- 2026-09-02: `docs/goals/` held the previous run's brief, ledger and draft state. `docs/` is
  the live GitHub Pages source for mcp-router.fledgeling.app and Jekyll would publish them.
  They were untracked, so nothing reached the site. Moved to `planning/goals/` per the
  `ORCHESTRATOR.md` contract; recorded here rather than silently.
