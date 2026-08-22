# ORCHESTRATOR.md — MCP Router

**This file is the memory, not the transcript.** A fresh session resumes the whole fleet
from here plus `DESIGN.md` and `planning/features-to-triage/LEDGER.md`. Update it after
every state change, before acting on that change.

---

## Contract

| | |
|---|---|
| Repo | `~/Dev/mcp-router` · public · `fledgeling-co/mcp-router` |
| Integration branch | `main` (pushed; the marketing site deploys from `main` `/docs`) |
| Pipeline root | **`planning/`**, not `docs/` — `docs/` is the live GitHub Pages source for mcp-router.fledgeling.app and Jekyll would publish every spec to the public site |
| Specs · plans · briefs | `planning/specs/spec-<ID>.md` · `planning/plans/plan-<ID>.md` · `planning/features-to-triage/` |
| Practices | `planning/practices/` — inherited from bella-team-files. **They are TypeScript/Next.js and carry no Swift guidance.** F1 owes `SWIFT_PRACTICES.md`; until it lands, Swift runners have no house style to conform to |
| Design authority | `DESIGN.md` at the root. Reference implementation `design/mcp-router-console.html` — the design of record settled 2026-08-22, which M21 re-authored `DESIGN.md` §1–2 against. `design/mocks/prototype.html` is the superseded prototype and is cited only for surfaces not yet converted |
| Worktrees | `.worktrees/<ID>` on `ai/<id>` |
| External model CLIs | **On** (no opt-out marker in this repo) but **the codex lane is UNAVAILABLE — do not probe it.** See below |
| Concurrency | ≤8 slots; the DAG peaks at 5 |
| Baseline on `main` | Measured at `6dc6007`, 2026-08-22 ~18:2x: `make test` **1725 tests in 215 suites** exit 0 · `make lint` exit 0, swiftlint 0 violations over 549 files · `ledger-reconcile.py` 0 across A–L · `reader-accounting.py` 0 · `null-run-gate.py` 0 with **28 armed, 0 held**. Re-measure before quoting — four briefs in this fleet have already carried a figure belonging to another branch |
| Merges | **Serialized by the orchestrator.** Runners stop at ready-to-merge |

### Two standing decisions, taken with the user at preflight

1. **Swift ships alongside TypeScript; TS stays the installed default until R4's parity
   gate passes.** The router the user's sessions depend on must not be under a rewrite
   with no fallback. Only R4 flips the installer and deletes `src/*.ts`.
2. **macOS is direct-distribution, unsandboxed** (Developer ID + notarized DMG). An app
   that spawns arbitrary MCP subprocesses and rewrites `~/.claude.json` cannot run under
   App Sandbox, so MAS was never available to it. iOS is the opposite: App Store,
   sandboxed. The entitlements differ per target and are written in F1, not retrofitted.

### Standing constraints every runner inherits

- The Mac app talks to the router **only** over the loopback control API. That boundary
  is what lets R1–R4 swap the router underneath without the app changing.
- `command`, `args` and `env` are never writable through the control API's PATCH.
- The phone **queues**; it never installs. Deliberately narrower than "remote install".
- No number is displayed that the router does not observe. There is no fabricated memory
  saving anywhere in this product.
- The Swift MCP SDK is pre-1.0 and warns that minor bumps may break — pin exact.
- The skills the pipeline uses are vendored, not assumed. `.claude/plugins/fledgeling-plugins`
  is a git submodule tracking `main`; run `git submodule update --init --recursive` after a
  clone. A runner reads `mockup-fidelity`, `mac-craft`, `design-craft` and `ux-craft` at a
  repo-relative path rather than depending on which machine it woke up on.
- A surface built from `design/mcp-router-console.html` is converted under `M23`, not by eye.
  Its five measurement layers, the breadth-before-depth ledger and the third exit state
  (inconclusive) are the contract; a screenshot comparison is not evidence, and the recall
  numbers behind that are in the brief.

### Only test a screen you changed, and only that screen — user instruction, 2026-08-14

Standing, and it outranks any sweep-everything habit in the pipeline skills. Changed a row,
a menu item, one pane? Test that one thing. Changed nothing under a screen since it was last
proven? Do not test it at all — cite the existing evidence. Never relaunch the app or boot a
simulator per screen: one launch, one pass, quit.

The measurement behind it: **M1 and I1 have each been through four runs**, and every relaunch
restarted UI verification from zero because nothing on disk recorded what had already been
proven. The Mac lane drives the user's *real* screen through `osascript`, so they sat watching
the same windows and menus driven over and over. That is their time, not just tokens.

The fix that makes it stick across a relaunch: each UI item keeps
`planning/evidence/<ID>-acceptance.md` — one row per screen: screen · how it was verified
(the actual command or AX path) · the commit SHA · result. Append, never rewrite, commit it,
and **read it before testing anything**. A row whose SHA-to-HEAD diff does not touch the files
behind that screen IS the evidence.

This narrows repetition, never rigour: a screen never yet tested still gets tested properly,
once, and behavioural claims still need behavioural proof. Skips get reported as skips.

### The codex lane is down until 2026-08-20 — read before any out-of-family gate

Verified by the orchestrator on 2026-08-14: every `codex exec` call, down to a one-word
probe at low effort, returns *"You've hit your usage limit … try again at Aug 20th, 2026
1:29 PM"*. That is **account-level**, not per-call, and Aug 20 is past this fleet's
horizon. Do not spend a probe rediscovering it.

Run the three out-of-family gates in-family instead: a **fresh `claude -p` opus-5 reviewer
per gate**, briefed adversarially — told to refute, and told that finding nothing is a
failed review rather than a pass — and record `codex: usage limit -> claude (downgrade)`
in the spec, plan or completion note, so the weakness travels with the evidence instead of
disappearing. This is a logged in-family downgrade, which the skill permits; it is not a
skipped gate.

**The trap that makes this dangerous: `codex exec` exits 0 on a usage limit.** A gate keyed
on `$?` records a pass for a review that never ran. The only honest tells are the ERROR
line in the log and a missing-or-empty `-o` file — assert the `-o` file is non-empty before
believing any codex result, on this fleet or a later one.

### A runner that messages the orchestrator ends its turn

Observed twice on 2026-08-14 (R5, and the stopped R3 duplicate): a runner that calls
SendMessage stops, and `TaskStop` then reports *"no active task"* for it. It stays stopped
until the orchestrator replies, which resumes it from its transcript. So a message is not
an aside — it costs the runner its turn.

Two consequences. Runners: say what you need in one message and expect to be resumed;
don't message mid-phase for something you could decide yourself. Orchestrator: **reply
promptly, because a runner awaiting a reply is indistinguishable from a dead one** — the
liveness watcher will report it quiet in fifteen minutes either way.

---

## Wave plan

Waves are the dependency DAG's topological levels. Slots refill on completion rather
than barriering on whole waves, so the real overlap is greater than the table implies.

| Wave | Items | Peak slots | Gate to leave |
|---|---|---|---|
| 1 | F1 | 1 | ✅ **CLEARED** — both targets build, CI green on a clean runner, `SWIFT_PRACTICES.md` landed |
| 2 | F2 · F3 · R1 | 3 | ✅ **CLEARED** — all three merged; merged-tree `make all` exit 0, 237 tests, lint clean |
| 3 | M1 · R2 · R3 · I1 (+ **F4**, injected) | 3 | **R2 ✓ R3 ✓ R5 ✓ F4 ✓ merged.** Remaining: M1 (no UI shipped), I1 (partial). Concurrency cut 5 → 3: I1's iOS build was `Killed: 9` by memory pressure from five parallel Swift/Xcode builds, which is part of what kept killing agents |
| 4 | M2 · M3 · M4 · I2 · R4 | 5 | **R4 is the parity gate and may not pass on a subset** |
| 5 | M5 · M7 · M8 · I3 | 4 | — |
| 6 | M6 | 1 | Phone → Mac inbox round-trip works end to end |


> **THE TERMINAL DIED AT 08:55:13Z AND KILLED EIGHT DISPATCHES.** Nothing was lost — every one of
> the eight has its work committed on its `ai/<item>` branch, `main` is intact at `78a27e7`, the
> reconciler is clean across A–L, and no worktree carries an `index.lock`. One commit that looked
> lost had landed: M22 was cut *during* `git commit` and `8952a5b` is on the branch.
>
> **HOLD LIFTED 2026-08-23.** All eight came back up on their own session ids with context intact,
> none cold-started, each told to reconcile against git and treat any `/tmp` file it was polling as
> stale. **Record the session ids — they are how this work stays recoverable if a terminal dies
> again**, and a resumed session is worth far more than a relaunched one:
>
> | Item | Session id | State when it was cut |
> |---|---|---|
> | M12 | `495116b3-751e-44b9-8984-4d6d137bcf98` | mid poll-loop |
> | M16 | `88a082e2-f132-448d-9483-24f66418d471` | inside `make lint` |
> | M18 | `2543db46-0f87-447c-9b32-de9d3a08b4f3` | **finished 08:42** — predates its own gap-fix brief |
> | M19 | `026cf02d-b260-4045-9a0b-2eacca1e76da` | inside `mock-fidelity-gate.sh` |
> | M20 | `948f8fe7-eee9-467c-817e-ef0f9b04235a` | **finished 08:10** owing 17 uncommitted paths |
> | M22 | `9fa43667-98db-42f7-a570-af0206880c7b` | mid-commit; it landed as `8952a5b` |
> | R19V | `b3bbdb08-2e04-4f24-91b4-9df540eb7777` | mid poll-loop, no verdict written |
> | G5V2 | `e4e8324f-d51a-4da1-ad0b-8b5b977c65fa` | mid tip-reconciliation, no verdict written |
>
> **`M18`'s resumed session has an information gap nobody else has.** It finished at 08:42 believing
> the item was blocked on a build it could not get through. The orchestrator then got one through at
> low priority and found the real defect, and wrote `GAPFIX-BRIEF.md` into that worktree — a file
> that session has never seen. Point it there rather than letting it re-derive the failure.
>
> The original hold, kept for the record: a separate recovery session
> (`lukerhodes-2f`) is resuming all eight **by session id**, so they come back holding the context
> they had. Relaunching one from its original prompt throws that away, and two processes on one
> worktree is worse than a cold start. Wait for each to report in.
>
> **The uncommitted work is the part a cold start would destroy.** `ai/m20` carries **17**
> uncommitted paths including `KeyChord.swift`, `MenuCommandAvailability.swift` and
> `MenuCommandRuleTests.swift` — new source that exists nowhere else — and it *finished its turn*
> at 08:10 owing that commit rather than being cut. `ai/m19` carries **11**, including a whole
> `app/Sources/MCPRouterUI/Document/` directory and three `planning/fidelity/` artifacts.
>
> **Neither verifier produced a verdict.** `R19V` and `G5V2` each hold only a `SCRATCH: merge main`
> commit and no file under `planning/verification/`, so **R19 and G5 gap-fix 3 are both still
> unverified and neither may merge.** Their sessions hold the measurements they had already taken,
> which is the whole reason to resume rather than restart them.
>
> **`main`'s checkout has 21 dirty paths and none of them are this fleet's.** They are another
> session's test-campaign witness work and the marketing store page, and they were already there
> when this session began. Do not `git add -A` here — that mistake has already swept a third
> session's work into a commit twice in this repo.

### DISPATCH — A GAP-FIX HANDED A VERDICT REBUILDS; ONE HANDED THE FINDINGS CONVERGES

From `sidetone` via the armada conductor, 2026-08-23, and **checked against this session's own four
gap-fix briefs, where it found two failures.**

None of the four said *"address the verifier's findings"* — no vague referral. But the itemisation
was uneven:

| brief | cited locations | named findings |
|---|---|---|
| M20 | 3 | 3 |
| M18 | 1 | blocker located; three non-blocking described only |
| M16 | **0** | **described four and told the runner there were six** |
| R19 | **0** | gave the matrix, pointed at the verdict for the rest |

M16's is the instructive one. Its verdict carries six numbered findings; the brief described four
and asserted six. **Findings 5 and 6 were never mentioned** — an `AC9` composition table omitting a
category so neither column reaches its own 116, and a correct base figure whose stated derivation is
in the wrong units. Both are counting defects of the class this fleet spent the day on. A runner
reading that brief gets four of six with no way to know which two are missing.

Both were amended in flight with a marked addendum rather than edited silently.

**The rule, with the half that doing it added.** Itemise the findings with their sites — and
itemise **from the findings section**, saying explicitly that the verdict's other citations are not
a work list. Extracting locations mechanically does not give you the findings: M16's verdict cites
**20** distinct `file:line` locations and almost none is a defect site; R19's cites **12**, same.
They are measurement citations. A runner handed all 20 treats them as 20 jobs.

### VERIFY — SPLIT THE MECHANICAL FROM THE OUT-OF-FAMILY, BECAUSE THE ONLY LANE LEFT CANNOT EXECUTE

From `proctor-mcp` via the conductor. `agy`/gemini is the **only** out-of-family lane on this
machine (`codex` limited to 27 August, `grok` at 402, `glm` absent) and it is a **one-shot that
cannot execute anything** — it cannot run a test, walk a diff, or reproduce.

So a verify stage briefed to *"get an out-of-family verdict"* gets a judgement over artifacts and
nothing mechanical. The shape to use instead, recorded as a logged downgrade rather than a silent
pass:

- **Mechanical verification** on a fresh-context Opus verifier that did not build the work — which
  preserves ship-fleet's structural rule that a runner cannot verify its own build.
- **Out-of-family judgement** on gemini over the artifacts.

**Do not brief one agent to do both**, because one agent briefed to do both will do the half it can
and report the whole. That is the same failure as an instrument that cannot fail reporting like one
that passed, one level up: **the agent that cannot execute reports like one that did.**

`M16V` demonstrates why it is not optional. It had presented `claude-fable-5` as its deciding second
opinion — different model, same family, writer was Opus, so not out-of-family at all — and corrected
the report before committing. Its verdict now says plainly that gemini said `Done` and it took
`Needs More Work` against it, with the downgrade logged.

### DISPATCH — PUT THE SESSION ID IN THE BRIEF YOU DROP IN A WORKTREE

`m18-c9` and `m16v-15` are both this session's runners and **neither could know it**. Each was
started from an untracked brief with no parent handle, and one wrote: *"I may well be the orphan the
m22 session meant, or a replacement for it — I can't distinguish those from inside."* It cost the
armada conductor two round trips to establish that no second writer existed. A line naming the
dispatching session closes it.

### HAZARD — ITEM IDS AND MUTATION IDS SHARE A NAMESPACE IN `scripts/red-green.py`

Second instance found 2026-08-23, so it is a pattern rather than an incident.

`scripts/red-green.py` numbers its mutations `M01…M59`. **Those collide with this fleet's item ids
and nothing distinguishes them.** The existing `"M20"` in that file is **the twentieth mutation**, on
`ServerStateTracker.swift` — nothing to do with item M20.

- **M19's renumber** found four `M29`s in the tree that were mutation ids: two in `spec-F3.md`, one in
  `G3-gapfix-2.md`, one in `scripts/red-green.py`. A tree-wide `sed` would have silently corrupted a
  red-green record, **and nothing would have gone red**, because those tables are prose to every gate
  we run.
- **M20's gap-fix** hit it from the other side and gave its five new drift guards ids **outside** the
  `M01…M59` range on purpose, recording it as *a trap for anyone grepping the item id*.

**So: never grep a bare item id across this tree, and never `sed` one.** Name the file set
explicitly, as M19's renumber did. The collision is invisible to every gate, which is why it has to
be a dispatch rule rather than a check.

### DISPATCH — DO NOT CITE THIS FILE BY LINE NUMBER; THE ORCHESTRATOR IS WRITING IT

Measured 2026-08-23 by M16's gap-fix runner, and the cause is this session's own bookkeeping.

It cited `ORCHESTRATOR.md:219-232`. `main` moved to `1f5ad55` while it worked and the text is now at
**`:350` — 131 lines off, landing on another item's verdict line.** Its own words: *that is the
defect I was fixing, arriving on schedule.*

**This file is appended to after every state change**, which is what makes it useful as memory and
useless as a line-addressable citation target. A runner's citation into it is stale before the
runner finishes.

So: **cite this file by anchor and tree, never by line.** The anchor survives; the line does not,
and it does not fail loudly — 131 lines off lands on another item's text, which reads plausibly.
`G7`'s dangerous variety, produced by the orchestrator rather than by any runner.

The same applies to `planning/features-to-triage/LEDGER.md`, for the same reason.

### MERGE — SWEEP EVERY VERDICT FOR FINDINGS OUTSIDE THE AC SET BEFORE MERGING IT

From `sidetone` via the armada conductor, and **it has already bitten this session.** This fleet has
the largest merge queue in the armada, so it lands here hardest.

**The gap.** Gap-fix takes failures; merge takes passes. **A finding attached to a pass falls between
the two stages with nothing looking for it.** `sidetone` found it on an already-merged item: a
genuine `Done` at 10 of 10 whose verdict also carried **five findings outside the AC set**, none of
which its Done-and-merge path captured. Three were holes in the integrity gate that repo had just
adopted — the sharpest being that **a silent deletion passes all five passes**, a check written to
catch silent writes with a silent-write hole in it.

This is the ninth instance of the day's shape and **the first that is a gap *between* stages rather
than inside an instrument**, which is why no gate here can see it: both stages are behaving
correctly.

**The rule.** Before any merge, sweep the verdict for findings outside the AC set and give each one a
destination — **a ledger row, a brief, or a recorded decline.** A `Needs More Work` verdict is safe
by construction, because a failure has somewhere to go. It is `Done` that loses them, so **M22 and
anything else returning `Done` is where this applies.**

**Measured on this session's own work, 2026-08-23.** M20's verdict carries **seven** findings. The
gap-fix brief carried **five** — F1, F2, F3, F6, F7 — and **F4 and F5 had no destination at all**:
not in the brief, not in a ledger row, not in a filed item. They are now `M34` and `M33`, and `M33`
turns out to be the mechanism behind M18's recurrence, so a finding with no home was holding the
explanation for a second item's failure.

### THE CITATION RULE ROUTES CONDITIONALLY — COUNT THE CITATIONS FIRST

`sidetone` measured that the two verdict shapes fail in **opposite** directions, which resolves the
tension between this session's refinement and the original rule:

| verdict shape | example | the risk | the half to apply |
|---|---|---|---|
| **citation-dense** | M16 at 20 distinct `file:line`, R19 at 12 — almost none a defect site | a runner treats measurements as a work list | say explicitly that the other citations are **not** a work list |
| **prose-dense** | `sidetone`'s at 0, 0 and 5 | findings living only in prose headings get **under-counted** | itemise **from the findings section**, exhaustively |

Its own evidence for the second: `SDT-044`'s brief carried five of six findings, and **the missing one
held four frames that were part of the gate count the same brief asked the runner to raise.** It
removed a cause of the number it asked for.

**So count the citations first, then apply the matching half.** This session's M16 fix was the right
half for M16; a prose-dense verdict needs the other one, and M20's omission of F4/F5 was that other
failure arriving here.

### DISPATCH — THE ADDENDUM ROUTE IS A PROPERTY OF HOW THIS FLEET LAUNCHES, NOT A GENERAL PRACTICE

This session can append a marked addendum to a live runner's brief **because its runners are
sessions**. `sidetone`'s are workflow-inner agents: `SendMessage` cannot revive them and
`ListAgents` does not show them — ship-fleet's scheduling reference records that, and that the
handover doc is their only pause artifact. Its substitute is to carry the correction forward to the
verifier and **attribute the omission to itself rather than to the runner.**

Do not assume another fleet can be corrected mid-flight the way this one can.

### MACHINE — LOAD AND THERMAL DISAGREED, AND THERMAL BOUND

`proctor-mcp` sampled thermal three times in forty seconds: `not_limited` held 364s → `not_limited`
held 395s → **`limited` with `held_for_sec: 0`**, P0 busy at 100% while spending **0.8%** of active
time near its 4512 MHz ladder top, load flat at 0.38–0.47 per core across all three samples. It went
to one runner instead of two on the thermal reading rather than the load one.

`berths.py` reported `in_use 0` while it had two Opus runners building Swift — **the third
independent confirmation that it is claim accounting rather than load measurement.**

Disk is the tightest axis at **13.7% free** (254 GiB absolute, 234 GiB clear of the hard gate) —
graded healthy, so watch rather than worry.

### DISPATCH — CHECK THE TIP MOVED BEFORE SENDING A VERIFIER

**Committed by this session, 2026-08-23.** G5's verdict `78ce229` had parent `6a3dbb8`. `ai/g5` was
still `6a3dbb8` when the next verifier was dispatched, because the gap-fix that verdict called for
was **recorded as owed and never dispatched.** So a verifier spent a full pass re-deriving a verdict
that already existed, and its own report is what surfaced it: *the tree I graded is the tree that
verdict graded, and no gap-fix has run since.*

**The check is one command and it takes a second:**

```
git rev-parse ai/<item>                     # the tip you are about to grade
git log -1 --format=%P <previous-verdict>   # the tree the last verdict graded
```

Equal means **there is nothing new to verify** — what is owed is the gap-fix, not another verdict.

It was not wasted, which is the part that makes it easy to repeat: the verifier re-derived all five
criteria independently and found **three new findings** the previous verdict had not. A wasted pass
that returns value is harder to notice than one that returns nothing.

**Related, and the reason this session missed it**: `Needs More Work` was recorded in the ledger row
with *gap-fix N owed*, which reads like a state and is actually a **to-do with no owner**. A verdict
that blocks does not dispatch its own successor. Either dispatch on receipt or make the owing
explicit enough that the next dispatch reads it — the ledger row said it and the dispatcher did not
look.

### R19'S PARAGRAPH HAS FAILED THREE PASSES, EACH TIME BY A NEW EXCLUSIVITY CLAIM

Three verifications, three `Needs More Work`, and **each pass removed one exclusivity claim and wrote
another**:

1. *A node-side delete would have failed **both**.* — false; the Swift arm leaves
   `IndexFailureRecordTests` green.
2. *`parity-cli.sh` is **not what catches** that one.* — false; it reddens on both arms, because a
   differential harness sees a one-sided regression whichever side it is on.
3. *What `IndexFailureRecordTests` **uniquely** holds is the both-sides-at-once case.* — false;
   `parity-overlap.sh` reddens there too.

**And the third was written four lines below the sentence the same pass narrowed for exactly this
reason.** The narrowing itself was right — arm A against two unnamed instruments showed
`parity-overlap.sh` reddening, so pasting the verdict's ready-made *the only instrument that does*
would have produced a **third** false exclusivity rather than a second.

**So the defect is the paragraph, not any sentence in it.** It is written in a register that reaches
for uniqueness — *only*, *not what catches*, *uniquely* — over a set of instruments nobody has
enumerated. A fourth pass briefed on the new sentence alone will write a fourth.

**Brief the next pass on the register**: state what each instrument *does* catch and stop there.
Every exclusivity claim requires enumerating the full instrument set, and this item has now
discovered a previously-unnamed instrument on each of three passes.

### HAZARD — TWO IDENTICALLY-NAMED `MCPRouter.app` BUNDLES EXIST RIGHT NOW

**Live as of 2026-08-23, with seven verifiers running.** Found by M20's verifier as its V5, verified
here:

```
~/Library/Developer/Xcode/DerivedData/MCPRouter-flunszcvdpykvngedkuolsadbrhh/Build/Products/Debug/MCPRouter.app
~/Library/Developer/Xcode/DerivedData/MCPRouter-ggpomhshywquhjafyrfgjqfgdyek/Build/Products/Debug/MCPRouter.app
```

One is the graded runner's worktree build, one is the verifier's. **They are distinguished only by an
opaque hash segment.** A verifier that globs for `MCPRouter.app` measures whichever it finds first —
**a different tree — and gets output that looks exactly right.** No error, no empty result, no
absence to notice.

M20's verifier avoided it by proving its subject via `WorkspacePath` before reading anything off the
bundle. **Every runner reading a built bundle must do the same**: derive the path from its own
workspace, never glob for the name.

Same family as `G6` (an artifact that does not survive) and `G9` (a path that was correct when
written): **an identifier that resolves to the wrong thing rather than to nothing.**

**A measurement note against this session.** The first probe here used `find … -maxdepth 4` and
returned **0**, because the bundles sit at depth 5. That zero was reported as nothing — briefly. It
was caught by re-measuring rather than by anyone correcting it, which is the **third** wrong-scope
failure this session has committed today and the first it caught itself. **A zero from a scoped
probe is a candidate, not a result.**

### STAND DOWN — NO NEW RUNNERS UNTIL THE 5-MINUTE LOAD CLEARS

2026-08-23, armada-wide. **Start nothing new.** Existing runners finish; they are not to be killed,
because killing them loses their work and they are the whole verification wave.

Measured here rather than taken on report — and the shape matters more than the level:

```
  1m  125.86  (7.87/core)     ← climbing
  5m   79.29  (4.96/core)     ← the figure to gate on
  15m  38.52
  CPU 73.47% user, 25.4% sys, 1.48% idle
```

**Load is rising across the window, not settling.** The armada conductor's own reading was 138/151/140
with `berths.py` collapsed from a ceiling of 10 to 3, `in_use 10`, `available 0`, cpu pressure
**critical** — after it cleared eleven idle sessions and fanned out on a single **1-minute** reading
of 3.67.

**So gate on the 5-minute figure, never the 1-minute one.** A 1-minute load is a snapshot that a
fan-out invalidates the moment it lands; this fleet's own eight verifiers are part of the number
above. Resume when `berths.py` reports `available > 0` against a 5-minute figure — and note
separately that **`berths.py` is claim accounting, not load measurement**: it reported `in_use 0`
with five Opus runners live, because workflow-inner agents never register as claimants. Read
`pressure.py` and thermal directly alongside it.

### PRECONDITION — INVOKE `reckon` BY EXPLICIT PATH, NEVER BY NAME

From `Graft`. **Both `1.0.0` and `1.1.0` sit in the plugin cache and both look installed**, and
nobody has established which one the loader picks on a bare skill invocation.

So `grep -c unjoined` is the right test **and it must be run against the copy that will actually
run**. Invoke by explicit path, or the test measures the copy you assume will run rather than the one
that does — *the same postmortem-versus-precondition shape as checking a remote after ordering a
push rather than before.*

This session's corrected run is clean on that: it used
`…/reckon/1.1.0/skills/reckon/scripts/reckon.py` explicitly and confirmed the resolution afterwards.
`1.1.0` landed in the cache at **23:38:28**, so any cache measurement taken before that is **stale
rather than wrong** — re-take rather than trusting a note.

### THE REMAINING-WORK FIGURES WERE WRONG BY A FACTOR OF THREE — RE-RUN BEFORE PLANNING

Corrected 2026-08-23 after `Google Drive Fixes` found the classifier defect and the armada conductor
relayed it. **`reckon` 1.0.0 classes a brief it cannot join to the registry as `unbuilt`** — it
publishes *"I could not find evidence for this"* as *"this was never built"*. 1.1.0 makes `unjoined`
its own class and routes it to **decision** work, which is the right destination: an unjoined brief
needs a person to read it, not an engineer to build it.

**The test is `grep -c unjoined` on the `reckon.py` that will actually run — 14 means fixed, 0 means
the old classifier.** A version string cannot be the test, because **both versions sit in the plugin
cache and both look installed.**

Measured on this repo's own ledger: **all 78 `unbuilt` rows had zero edges to the registry**, and the
tool stated the reason in its own field — *"no requirement, defect or case in the registry answers to
this brief"*. Not one was established as unbuilt.

| | 1.0.0 | 1.1.0 |
|---|---|---|
| remaining | 171 | **155** |
| **product** | **155** | **49** |
| evidence | 14 | 16 |
| decision | 2 | **90** |
| unbuilt | 78 | **1** |
| unjoined | — | **87** |
| broken | 77 | 51 |
| verified-done | 112 | 134 |
| rows | 287 | 297 |

Corrected ledger at `planning/reckoning/2026-08-23-fixed/`, gate clean.

**The join warning matters more than the delta.** 17.9% of briefs could be joined at all — 6% across
the whole ledger — and 1.1.0 **withholds retirement claims below half** rather than answering
confidently from a join it knows is too weak. 1.0.0 had no such warning and answered anyway. So this
reckoning cannot speak to what is done; it can only say what it could not reach.

**The reader-level lesson, which is the part worth keeping.** This orchestrator recorded *"62 of 78
`unbuilt` are merged or done"* and filed it as **staleness**. `Google Drive Fixes` recorded *"18 of
23 unbuilt already merged"* and filed it the same way, twelve hours earlier. **One instrument-level
question — why would a merged brief be classed unbuilt? — would have found this either time.** Both
readers had the anomaly and read it as noise.

That is a **different failure from the seven instruments that could not fail**: here the instrument
reported an anomaly faithfully and its readers discarded it. Probably the more common of the two.

### NINE INSTRUMENTS THAT COULD NOT FAIL, IN ONE DAY, ACROSS NINE MECHANISMS

Two more arrived from this wave's verifications, and both guard something load-bearing:

| # | instrument | why it could not fail |
|---|---|---|
| 8 | M19's `nothingFallsBack` | filters for `MarkdownBlock.plainText`, **never constructed anywhere in `app/`** — and the red-green arm proving it **reddens by trapping**, not by asserting |
| 9 | M12's `A15c` C7 row | greps `reading taken $shape` against a sentence hardcoding `at `, so **`taken at 3m ago` passes** — while claiming to prove the item's central design decision |

Both were found by **planting rather than by reading**, and both runs carried a **negative control**
that failed correctly — which is what turns *"I could not make it fail"* into *"it cannot fail"*.

### THE ORIGINAL SEVEN

The armada conductor is carrying this count because it is what the whole night was about. **An
instrument that cannot fail reports exactly like one that passed.**

| # | instrument | why it could not fail |
|---|---|---|
| 1 | a `pf` anchor (another project) | its positive control could never resolve |
| 2 | `capture-lineage` (another project) | exited 0 over an empty population |
| 3 | `reckon check` | compares `summary` against `rows`, **never reads `headline`** |
| 4 | `nonfailing-assertions.py` (another project) | blind to `XCTAssertEqual(a, b)` where both names hold one value |
| 5 | G5's guard | `\binstalled\b` cannot match inside `_installed_` — `_` is a word character |
| 6 | `mock-fidelity` | no opinion on what the build adds, and **no opinion reads like agreement** (`M32`) |
| 7 | a verify stage on the only lane left | **the agent that cannot execute reports like one that did** |

Number 3 is the one to sit with: it is the tool the fleet uses to count its own remaining work, in
the same failure class as the things it measures. Three sessions quoted a generated headline that
disagreed with the rows beneath it, this one included — its figures were corrected from 167/152/13
to **171/155/14** off `ledger.json`. **Read ledgers, not reports.**

Number 7 is why the verify stage is split. See the VERIFY rule above.

### SIX VERIFICATIONS, SIX `Needs More Work`, AND THE DEFECTS ARE NOT WHERE THE WORK IS

Measured 2026-08-23 across M16, M18, M19 (pending), M20, R19 and G5. **Every verdict came back
`Needs More Work`, and only two blocked on the product**: M20 does not compile, and M18 moved
`.keyboardShortcut(.cancelAction)` onto a destructive button so Escape removes an installed
capability. **The other four blocked entirely on records** — a claim that reads true and is false at
a level nobody had looked at.

That is a finding about how this fleet works rather than about these six items. The builds are
largely sound; **what is wrong is what was written about them**, and every instance was invisible to
a static read and visible to a measurement:

- R19's *replacement* claim was false thirteen lines above a sentence predicting it.
- G5's guard could not match `_installed_`, because `_` is a word character.
- M16 filed a three-versus-four enum defect against `spec-M22.md` **and then committed it in its own
  note**.
- M20's plan promised seven names that exist only in the plan.

**What follows for the next wave's briefs.** An acceptance file that instructs a reader to accept a
row *in place of* re-running the check makes a false row worse than a typo — it is an instruction to
believe something untrue. So a record's claims need the same arming its assertions get: the
normaliser named, the citation carrying anchor and tree and line, and every count re-derived on the
tree that ships rather than the tree it was measured on.

**And the verifiers earned their cost.** Five of six overrode or lacked an out-of-family lane and
said so rather than passing silently; three found defects in their own predecessors' figures; one
settled a cross-branch rule by execution and then refined it; one re-derived a dead session's
548-line draft rather than inheriting six wrong numbers.

### DISPATCH — A PID OBTAINED FROM A PATTERN IS NOT YOURS TO KILL

Reported 2026-08-23 by the armada conductor, from another project: a runner killed **a third
session's `agy` review** by running `pgrep -f "agy --model gemini-3.7-flash-high"` and killing the
first match.

That is expensive here specifically. **`agy` is the only out-of-family lane on this machine** —
`codex` is limited until 27 August, `grok` returns 402, `glm` is not installed. So a stray kill
does not slow a review down; it removes the only lane that can grade one, and the loss is silent
because the victim just sees an empty output file.

The rule: **name the process from its full command line and confirm it is yours before killing
anything.** A pattern match is a candidate, not an identification. Where a runner needs to know
whether a worktree is occupied, the check is `pgrep -x claude` plus `lsof -a -p <pid> -d cwd` and
comparing the path — not a `-f` match on a brief filename, which collides the moment two items
carry a file of the same name.

Measured today: two live processes both matched `-f "GAPFIX-2-BRIEF"` because M18 and R19 each
had a file of that name. Their cwds were different worktrees, and only the cwd separated them.

### DISPATCH — PERCH'S ACCOUNT-TRANSFER NOTICE KILLS A HEADLESS RUNNER AT LAUNCH

Measured 2026-08-23 across a seven-verifier wave. **Four died at launch, and a re-dispatch of one
died again on a different account pair.** Each produced a 224–241 byte file containing only:

> ⬤ Perch · account switched — this conversation is moving from `<a>` to `<b>` based on Relay's
> current routing and usage state. **Reply to continue on the new account, or tell me to stop.**

`claude -p` has no way to reply, so it exits having done nothing. The work is not lost — nothing
was started — but the dispatch is, and the failure is silent in the sense that matters: **the
wrapper exits 0.**

Perch's own contract (`RelayCore/Models.swift`, `transferConfirmThreshold`, default 450k): *tokens
a session may push through the proxy before an account transfer pauses for a one-beat confirmation
notice instead of switching silently … at or above it, the proxy tells the user their account
changed **and waits for them to continue***. These were fresh sessions that had pushed nothing, so
the notice is firing on a transfer decided before the first request rather than on a threshold
crossing.

**Why now**: the Personal pool has **3 of 9 accounts under 100% weekly**, so transfers are
frequent. This is the same pool exhaustion behind the Bedrock spend.

**Do not fix this by editing Perch's config.** It is the user's routing system, it affects every
session on the machine, and the threshold is theirs to set. What an orchestrator can do:

- **Read each dispatch's output before recording the runner as working.** A 224-byte file is this
  failure. `pgrep`+`lsof` on the worktree is the liveness check; the wrapper's exit code is not.
- Re-dispatch, and expect a proportion to die. It is not deterministic — five of seven survived.
- **Two Perch findings worth reporting upstream**: the notice is correct for an interactive session
  and fatal for a headless one, with no non-interactive path; and one notice named an **empty
  destination** — *"moving from luke.rhodes@icloud.com to  based on Relay's current routing"* — so
  it announced a transfer to nothing.

### OWNER DECISION 2026-08-23 — `PARITY_CUTOVER_TARGET` STAYS AT 82

The census now derives ~91 on `main` (92 rows less the standing exclusion) and 93 on M22's
branch. **The owner has held the target at the number they set on 2026-08-16.** The derived
figure stays a **reported drift**, which is what `parity-gate.sh` already does — it prints both
and alters no exit code, because a drift there *is a claim that needs an owner, not a measurement
this run can settle*.

Consequences to carry:

- **The cutover bar is met.** `surface.tsv` reads **87 proven** against a target of **82**. Nobody
  should write 93 as the bar, and no runner resolves the drift on its own.
- **That does not by itself unhold `R4-C2`.** Its recorded hold is *owner: not on a green streak*,
  which is a second condition and a separate decision.

### SPEC — `spec-M22.md` §3.3 MISDESCRIBES `HarnessState`, AND THE ROUTE WOULD INHERIT IT

Found by M16, verified against source 2026-08-23. `HarnessReconciliation.swift` declares **four**
cases — `notWired(overlapping: Int)`, `wiredViaHTTP`, `wiredViaShim(bridge: String)`,
`wiredWithDuplicates(route:count:)`. §3.3 names three: `.notWired`, `.wired(route:)`,
`.wiredWithDuplicates(route:count:)`.

**`.wired(route:)` does not exist.** It collapses `wiredViaHTTP` and `wiredViaShim(bridge:)` into
one case carrying a payload neither has — `wiredViaShim` carries a **bridge name**, `wiredViaHTTP`
carries nothing. A route built to the spec's names **could not distinguish an HTTP-wired harness
from a shim-wired one**, which is the distinction the Harnesses board exists to show. The spec
also drops `notWired`'s `overlapping` count.

§3.3 then concludes *three of the brief's four readings exist in the model and one does not*. That
is arithmetic on the wrong denominator — four exist, and the fourth reading it calls new modelling
may not be.

M22 owns both the spec and the route and has the finding. **M16's rail waits on `GET /harnesses`**,
so it does not stop at M22. Correct the spec in the same change as the route, not after it.

### MERGE ORDER — THREE BRANCHES AND ONE `VOUCHED_CONTROLS` TABLE, AND NOBODY HAS MEASURED THE UNION

Measured 2026-08-23, and it is **three-way** rather than the two a peer flagged:

| Branch | `scripts/acceptance/mock_fidelity.py` | Keys it touches |
|---|---|---|
| `ai/m19` | **+29 / −6** | `heading` `sentence` `button` `icon` `row`, and new `badge` `codeblock` `callout` |
| `ai/m16` | **+18 / −1** | `card` (adds `signature`), new `jack`, `indicator` **deliberately absent** |
| `ai/m22` | **0** | none — but it is *reasoning about* the table and has an open question on it |

**The textual collision is the easy half.** No key is edited by both: `M19` and `M16` own disjoint
sets, so the conflict is adjacency in one dict and the resolution is a **union**, not a judgement.
Take both.

**The measurement gap is the half that matters, and neither branch could have seen it.** `M16`'s
own comment states the mechanism: vouching a kind puts it into `MOCK_KINDS_FOR_ROLE`, and the
quota rule then reclassifies every unpaired build node of that role from `covered-by-pair` to
`extra`. `M16` cites exactly that to justify leaving `indicator` absent. `M19` adds **six** kinds
under the same rule.

Each measured its own additions against the **pre-existing** frames — `M19` re-measured all six
and reports 87/6/8/6 and 52/4 unchanged. Neither measured against the *other's* additions, and
`M16`'s frames (`signature`, `jack`) did not exist when `M19` measured. **So the merged table is
a combination nobody has run.**

**Order: `M19` first, `M16` second, and `M16` re-measures its own frames against the merged
table** — the still-building branch absorbs the change rather than the finished one being
reopened. `M22` edits nothing here and only needs to read the merged version before answering its
open question; its question may already be answered by `M16`'s `indicator` note, which is a
worked example of the same rule.

Neither order is safe without that re-measurement. A union that reclassifies a population would
show up as a fidelity finding on a surface neither item changed.

### MERGE — M22'S SHIM SHEET SHOULD NOT FOLD INTO `reconcile`, AND THE ARGUMENT IS SUBSTANTIVE

Recorded because `M18`'s session has exited and this would otherwise die with it.

`M22` argues its shim explanation sheet wants its own `Kind` case rather than being folded into
`reconcile`, and the reasoning is about what the two sheets *are* rather than about naming:
**`reconcile` is a diff of a file before a write. The shim sheet exists precisely because no write
is available** — a harness's transport belongs to the harness and this app writes no harness
files. So the honest affordance is an explanation, and the absent remedy is its substance rather
than a gap in it.

With the leading-hyphen convention above, that makes **three** options at merge — local-only, a
hyphenated `Kind` case of its own, or folded into `reconcile` — and `M22` has argued the third is
wrong.

`M22` also acted on a correction rather than filing it: `HarnessesBoardModel.Sheet` carried an
unreachable `.reconcile` case whose host arm dismissed on appear. Dead either way, but under the
corrected reading it read as **an intention to host**, which is what would have broken
`unhostedKindsAreTheOnesOnRecord` at merge. Removed at `0a5728a`.

### MERGE ORDER — M18, M19 AND M22 SHARE A FILE THAT EXISTS ON ONLY ONE OF THEM

`app/Sources/MCPRouterKit/Shell/RouterSheet.swift` exists on **`ai/m18` only**. `ai/m19` and
`ai/m22` were both cut from `87e16dc` and neither has it, so neither can line up with it now and
neither should be asked to.

**Two things are NOT the same and were confused once already.** `RouterSheet` is what the app can
present — seven board groups. `RouterSheet.Kind` is a separate inventory compared against the
mock's `sh-*` ids, and **a `Kind` row carrying an owner is a record of a deliberate hole, not a
slot to fill**. Hosting one would redden *M18's* tests, not the owner's: the test named *"every
kind is either presentable or has an owner — never neither"* and its companion pinning the four
unhosted kinds both live in `app/Tests/MCPRouterKitTests/RouterSheetTests.swift`.

**The landmine, and it is silent.** That companion test asserts
`RouterSheet.Kind.readme.owner == "M19"` as a literal. `owner` documents itself as *"Who closes
this sheet"*. M19 has built the sheet's **contents**; the entry point is M18's and the document
source is `M30`. So merging `ai/m19` makes the claim false **while the test goes on passing** —
filed as `G4`'s twenty-third instance. Decide what `owner` means before both land, and prefer
asserting the property over the literal.

**Sequencing fact for whichever of `m18`/`m22` merges second**: `M22` holds a local
`HarnessesBoardModel.Sheet` with `.reconcile(harness:)` and `.explainShim(harness:)` and has
recorded the migration onto `RouterSheet` as a merge-time obligation in
`planning/progress/M22.md` rather than inventing the enum's shape from a description. The second
merge collapses that local enum. `M22` does not present `.reconcile` at all — both controls that
would open it are drawn **disabled with the reason in their help tag**, because the panel is
M18's.

**The convention that makes the collapse possible**, measured: the mock's `sh-*` set is exactly
**13** ids and `Kind` has **16** cases. The three extra — `registryDetail`, `resetHistory`,
`skillProvenance` — carry **leading-hyphen** raw values, and the doc comment says why: a leading
`-` is not a legal HTML id fragment in that file, so it cannot collide. The 13 unhyphenated match
the 13 mock ids one for one. `M22`'s `.explainShim` has no mock id, so the hyphen convention is a
**third option** at merge rather than local-or-nothing.

### DISPATCH — `make lint` CANNOT RUN IN A FRESH WORKTREE, AND THREE RUNNERS HAVE PAID FOR IT

`make lint` depends on the `tools` target, which wants `node_modules` and `dist/index.js`. A
fresh worktree has neither, so the target fails before reaching a single check. **M18, M19 and
the G4B verifier have each hit this independently**, and one of them lost most of a session's
budget to it while attributing the failure to machine contention.

The two known handlings, both correct, neither free:

- Run the components directly (`swiftlint`, `swiftformat --lint`, `scripts/lint/*.sh`,
  `planning/*.py`) and **record that as a difference from the target rather than as the target
  passing** — M19's handling, and the honest one.
- `npm install && npm run build` in the worktree first, or symlink `node_modules` and `dist`
  from the main checkout — the G4B verifier's, and documented convention per `.gitignore:1-14`
  and `planning/evidence/P7-acceptance.md:160`.

Say which you want in the work order. A runner that discovers this itself spends real time on it
and may report a red it did not cause.

### In flight — 2026-08-23, after the 08:55:13Z crash · eight held for session-id recovery

Recorded so a fresh session resumes the fleet from this file rather than from a transcript.
Each runner is a detached `claude -p` in its own worktree; confirm liveness with
`pgrep -f 'model claude-opus-5 -p'` and read each pid's cwd with `lsof -a -p <pid> -d cwd`,
never the harness's own cwd notice.

| Item | Worktree | Branch | Base | Dispatched | Stop rules |
|---|---|---|---|---|---|
| M12 | `.worktrees/M12` | `ai/m12` | 9 commits, `cbe60bc` | **cut 08:55** | held for recovery — was polling a governor exit |
| M16 | `.worktrees/M16` | `ai/m16` | 2 commits, `a9d1bf9` | **cut 08:55** | held for recovery — cut inside `make lint`; `JackPresentation.swift` and its test are untracked |
| M18 | `.worktrees/M18` | `ai/m18` | 8 commits, `6b620b3` | **cut 08:55** | held for recovery. Its **gap-fix never began** — the only dirt is the two brief files. `GAPFIX-BRIEF.md` is in the worktree and still the work to do: `swift build` exits 1 at `Controls.swift:111` |
| M19 | `.worktrees/M19` | `ai/m19` | 2 commits, `9b13a49` | **cut 08:55** | held for recovery — **11 uncommitted paths**, cut inside `mock-fidelity-gate.sh` |
| M20 | `.worktrees/M20` | `ai/m20` | 1 commit, `f3cc64d` | finished 08:10 | held for recovery — **17 uncommitted paths**; it ended its turn owing the commit, which is the documented DISPATCH hazard biting again |
| M22 | `.worktrees/M22` | `ai/m22` | 3 commits, `8952a5b` | **cut 08:55** | held for recovery — the mid-flight commit landed. **M17 unblocks when this merges** |
| R19-INT **verify** | `.worktrees/R19V` | detached `b3234ed` | — | **cut 08:55** | held for recovery — **no verdict written**; only a SCRATCH merge of `ed37a30` |
| G5 gap-fix 3 **verify** | `.worktrees/G5V2` | detached `c49d674` | — | **cut 08:55** | held for recovery — **no verdict written**; only a SCRATCH merge of `28d0528` |
| R19 | `.worktrees/R19` | `ai/r19` | 7 commits, `eb3e42c` | done | work complete, **blocked on R19V's verdict** |
| G5 | `.worktrees/G5` | `ai/g5` | 5 commits, `43b44a2` | done | gap-fix 3 complete, **blocked on G5V2's verdict** |
| M17 | `.worktrees/M17` | `ai/m17` | staged | not dispatched | work order written. Blocked on M22 merging |
| G2 | `.worktrees/G2` | `ai/g2` | staged | not dispatched | blocked on the wave draining — it restructures the two files every recovered runner reads |

**Both verifiers are a logged in-family downgrade.** `codex` is down until 27 August on a usage
limit and the `grok` balance is exhausted (`402 … usage balance exhausted`, re-confirmed
2026-08-22), so the only out-of-family lane left is `agy`, which cannot run shell commands
non-interactively and therefore cannot run a gate. A fresh `claude -p` on `claude-opus-5[1m]` is
the sanctioned substitute; it is recorded here rather than passing silently, because the
verifier-out-of-family invariant is being missed and not met.

**The RUNNER CONTEXT hazard bit for real, on the one runner still on the 200k model.** R17's
runner completed all four acceptance criteria, ran every gate, wrote its 10 KB progress note at
12:35 — and died on `Prompt is too long` before it could commit. Its work was committed on its
branch by the orchestrator at `13e728b`, attributed in the message. Nothing was lost, and it would
have been if the worktree had been cleaned before anyone looked. **A runner that dies this way
leaves a clean exit and a full worktree**, which reads from outside exactly like a runner that
started and did nothing.

**R17's base is behind main and its dispatch contradicted itself** — it froze the branch off main
while setting `reconciler 0 across A–L` as a gate, and check L only exists on main from `b616dc1`.
The worktree also still carries both committed conflict blocks that check L was written to catch.
Resolution is the orchestrator's at finalisation: merge main into `ai/r17` — a base update, not a
merge *to* main — then re-run the gate line as written. Recorded in full in `R17-gapfix-2.md`.

**M16 · M17 · M18 · M19 · M20 · M22 are To Do and must not be dispatched before M21 merges.**
They are the per-surface half of the same programme: M21 delivers the token layer and every call
site keeps the name it already names, so choosing which surfaces move from `--accent` to
`--accent-ink` is theirs. Dispatched early they would build against the palette M21 replaces.

**R19 and G4 were dispatched at 12:26** and write their own spec and plan before building —
their 2026-08-22 triage settled the precondition each was blocked on, so a runner starts at the
spec stage rather than at triage. Both briefs restate the settled decision and say *do not
reopen it*, because the cheapest way for either item to fail is a runner re-litigating a fork
that a lane already closed.

**M21's merge at `e121801` unblocks M16, M17, M18, M19, M20 and M22** — they are the per-surface
half of its programme and were held only because they would have built against the palette it
replaced. They are the largest block of ready work in the backlog.

**Two ready items are deliberately not dispatched, because of who they would collide with.**
`R21` edits `AuthRoutes.swift:120`, which is one of R19's eight manifest write sites, and R19 is
rewriting all eight — two runners on one line. `M12` and `M16` both reach into the UI tree that
M15 is restructuring around a new `Settings` scene. Both wait for their neighbour to merge rather
than for capacity.

**R18 waits for R17**: its brief asks to be planned alongside `R20`, which exists only on
`ai/r17` at `b41c588` and reaches main when R17 merges.

**Five concurrent runners is the ceiling here.** Each brief caps subagents at two, which keeps
the product at ten against the fleet's ~16 budget. The machine sat at 0% idle when these were
dispatched, but that is eighteen other sessions rather than this fleet — runners here are
API-bound, and their local CPU share is small.


```
F1
├── F2 ─┬── M1 ──┬── M2
│       │        ├── M3 ──┬── M7
│  F3 ──┘        │        └── M8
│       │        └── M4 ──┬── M5 ── M6
│       │                 └── M7
│       └── I1 ── I2 ── I3
└── R1 ─┬── R2 ─┐
        └── R3 ─┴── R4
```

---

## Ledger

Status: `Untriaged → Spec → Plan → In Progress → Ready to merge → Merged` · `Blocked` ·
`Parked`.

**Two row shapes share this table, and one of them is outside every check.** Interleaved
through the nine-column rows below are 23 four-column `D-<parent>-<letter>` rows — deferred-child
notes reported by runners. They have no `Status` cell, so `ledger-reconcile.py`'s check H cannot
read them and counts them as skipped; and their ids do not match its allocation pattern, so
checks A, B, C, F and G do not see them either. **That exclusion is deliberate, not an oversight:
a `D-*` child is a note, never an id allocation, and the allocation checks exist to stop two
items claiming one id.** A note that claims no id cannot collide with one.

It is written here because it was previously written only in the script's `SERIES` definition,
where nobody reading this file could meet it — the same defect as a header claiming an authority
it does not hold. `G2` moves these rows into the register below, which is shaped for them; it
does **not** change what any check reads, and must not be described as though it does.

| ID | Title | Category | Deps | Mock (deep link) | Lane | Status | Branch | Outcome |
|---|---|---|---|---|---|---|---|---|
| F1 | Swift workspace, kit, three targets | foundation | — | — | Opus | **Merged** `0924040` | — | `make all` exit 0 on the merged tree · 31 tests · both targets build · **A12 (CI) MET** — run 31747021039 `build-and-test: success` on a clean GitHub runner, 2026-08-14 |
| F2 | Design system in SwiftUI | foundation | F1 ✓ | `?only=mac` + `DESIGN.md` §§2–7 | Opus | **Merged** `22d1802` | — | merged-tree `make all` exit 0 · 75 tests · both appearances authored · tokens tested *against* `DESIGN.md`, so doc and code cannot drift · two recorded deviations (tertiary 50% not 25%; `--onAccent` 3.23:1, kit wins) |
| F3 | Control-API client and models | foundation | F1 ✓ | — (surface: `src/control.ts`) | Opus | **Merged** `13825c9` | — | merged-tree `make all` exit 0 · 147 tests · 23 recorded fixtures + `ControlProbe` · **merge found a real defect**: unanchored `.gitignore` `servers.json` had silently swallowed a source fixture, green on the branch and red only when merged |
| R1 | Router: core, config, manifest | router | F1 ✓ | — | Opus | **Merged** `c30eac9` | — | merged-tree `make all` exit 0 · 237 tests · 224 parity vectors · mutation gate exit 0 · SDK pinned exact `0.12.1`, confined to `RouterCore` which neither app links |
| F4 | ServerStateTracker cannot report failure | foundation | F3 ✓ | — | Opus | **Merged** `aba30bd` | — | 306 tests on the merged tree · LoadKind .failed/.stale + StreamCondition .notConfigured · M55 survived the first mutation run (no test saw the notification lost when `register` is deferred into a Task) and `ServerStateTrackerPublicationTests.swift` is the test written to kill it · unblocks M2, M3 |
| R2 | Router: pool, relay, passthrough | router | R1 ✓ | — | Opus | **Merged** `a8091bb` | — | 279 tests · 224 parity · 13 mutation guards load-bearing · 10 behavioural tests against a REAL spawned child (pipes, signals, PATH, SDK handshake) · gate run on the rebased tree |
| R3 | Router: control, usage, registry | router | R1 ✓ R2 ✓ | — | Opus | **Merged** `e154bae` | — | 386 tests · 352 parity (parity-regen matches the reference exactly) · differential harness vs the RUNNING TypeScript router: 32/32 rows, 3 of which kill the reference where Swift answers 400 · 35/35 mutations red · 8 live port defects · **Phase D critic never ran** (codex account limit) — degraded, not passed |
| R5 | Router: OAuth and the auth routes | router | R3 ✓ | — | Opus | **Merged** `b7c527c` | — | 456 tests · 358 parity (352 core + 6 auth, asserted by name) · 10 mutations red-green · the real NWListener exposed 5 defects the double could not, incl. a CheckedContinuation double-resume in `AuthFlow.cleanup` that traps and kills the daemon · Phase D in-family (downgrade logged) 11 findings/8 fixed · one guard correct-by-construction but untested, recorded in the evidence file |
| **R2-R** | **Router: the process that actually serves** | router | R2 ✓ R3 ✓ R5 ✓ | — | Opus — never downgrade | **Merged** `62678aa` | — | The daemon exists: composition root, `LoopbackHTTPServer`, `MCPEndpoint`, `MCPRouterCLI`, lifecycle. **Parity gate 50/81 → 69 of 82, 0 DIVERGED** — the five structurally-blocked lanes (`mcp`, `cli`, `install`, `state`, `log`) are now measurable rather than blocked. Merged-tree gates re-run by the orchestrator, not taken on report: lint **0 violations / 243 files**, **750 tests / 106 suites**, **358 parity vectors**; merged tree byte-identical to the gated tree (`163597f7`). Lint went green by splitting on real seams (`RouterService` → root/dispatch/collaborators, `MCPEndpoint` split, `StdioUpstreamTransport.open` → spawn + handshake) — **no limit raised**. Real violation count was **31, not 29**: swiftformat's wrapping pushed three more files past the 400-line cap. One narrow config change for a genuine swiftformat↔swiftlint `opening_brace` deadlock, verified by hand. The gate still exits 1 by design; the cutover stays with R4 and the user |
| R4 | Parity harness and cutover | router | R2 ✓ R3 ✓ R5 ✓ | — | Opus — never downgrade | **Merged (harness only)** `e129779` | — | **Cutover NOT performed and NOT recommended.** `parity-gate.sh` exits 1 at **50/81** — `mcp` 0/5, `cli` 0/10, `install` 0/5, `state` 0/1, `log` 0/1, all blocked structurally because **there is no Swift router process**. All 3 gates REJECT, all 3 independently confirmed the no-daemon finding, all 3 rejected the coverage number (was overstated five ways; denominator rose 71→81). Gate proven by hiding `dist/`, by a lane exiting 0 recording nothing, and by a fabricated test name |
| **R2-W** | **Router: the `~/.claude.json` watcher and its adoption protocol** | router | R2 ✓ R3 ✓ | — | Opus — never downgrade | **Merged** `8e48a80` | — | The second launchd agent and the cross-process adoption protocol. Delivered with a **sidecar flock**, not a lock on the config itself, and the watcher shares that lock without sharing `ConfigEdit`'s writer. **It fixes the reference's own bug rather than porting it** — `D-i`/`R2 D7`, where a lost restart means an adopted server can never reach the running router; `restartPending` now persists before the rename, declared as a parity vector so R4 reads it as intent. Merged-tree gates: lint **0 / 403 files**, **1267 tests / 159 suites**, `parity-cli` 15 verbs agreed, `parity-divergence` 3 as declared 0 stale, `parity-install` four real launchd agents. **Parity 68 → 71 of 82 proven, 13 → 10 blocked**, measured by the orchestrator from the repo root both times — the runner read 69 → 72 from its own worktree and the **delta is identical**; the absolute differs by one row because of **D-o**. Gate still exits 1 by design. 8 mutations, 6 red, and **two that did not bite are recorded as such rather than swapped for ones that did**. The **plan gate returned REJECT** (2 critical, 3 high) and the design changed before any code existed |
| **CUTOVER TARGET** | **82 of 83, decided by the owner 2026-08-16** | R4-C | `fixture-registry-search` is a **standing exclusion** and 83 of 83 is unreachable by construction, which P3 stated in the row itself and asked for an owner decision on. **The target is now 82 of 83 with that row's reason attached.** The denominator stays 83: deleting the row would leave the numerator alone and shrink the denominator, so the coverage figure would RISE, which is the trap the row was kept in the census to avoid. Parity is 78, so **four rows stand between here and the cutover** — `D-p1-a` (control auth POST), `D-p1-d` (cli auth), `install-launchd-watch` (G1: name a fix per term and fix a bound IN ADVANCE, never a green streak), and `install-rollback`, which is R4-C's own work and the reason the cutover is a one-way door until it is proven |
| **R4-C** | **The installer cutover** | router | R2-R ✓ R4 ✓ P1 ✓ P2 ✓ P3 ✓ P4 ✓ | — | Opus — never downgrade | **Superseded — split into R4-C1 (Done) and R4-C2 (Held)** | `ai/r4c` (R4-C1, merged) | **Two rows collapsed into one, 2026-08-21.** They disagreed: one read `Blocked — needs 82 of 83`, the other `Wave 4 — last`, which is a wave label written into a status cell. Both were stale, and both quoted a parity figure (69, then 79, then 71) that has since been superseded. **What actually happened:** the owner took the third option — switch the binary, keep the TypeScript tree — so `R4-C1` shipped and `docs/install.sh` now defaults to `MCPR_ROUTER=swift`, while `R4-C2` (retiring `src/*.ts`) is **held by owner decision** and is not on a green streak. The target is **82 of 83**, not 83: `fixture-registry-search` is a standing exclusion, and deleting the row would shrink the denominator while leaving the numerator alone. |
| M1 | Mac shell, menu bar, keyboard | mac | F2 ✓ F3 ✓ F4 ✓ | `?only=mac` | Opus | **Merged** `10cad44` | — | 671 tests / 97 suites, lint clean over 205 files. **The FRAME, not the app** — `BoardRegistry.installed` is empty, so all seven destinations render the same placeholder; the boards are M2–M8. Real: three-zone window, sidebar + F2 focus ring, six menus with disabled reasons, keyboard routing, frame restoration, readout via F4's tracker, scroll-edge. Placeholder cannot outlive the boards — failable type, complement test, Release gate reading the list from source. Stopped before its critic: it was running over seven identical placeholders |
| M2 | Activity | mac | M1 ✓ M3 ✓ | `?only=mac&pane=activity` | Opus | **Merged** `c39c891` | — | 822 → merged-tree green. The lint block was real and was cleared by splitting on seams, never by raising a limit. The one test failure at merge time was a wall-clock load flake (`ActivityRecoveryTests.swift:198`), later fixed properly by `ShellTestSupport.waitUntil` |
| M3 | Servers: the breaker board | mac | M1 ✓ | `?only=mac&pane=servers` | Opus | **Done** | `589ab2e` `3b11f33` `af77200` (on main) | Triaged 2026-08-21 and found already shipped: six `ServersBoard*.swift` sources, seven test files. M7's `M3 ✓` was right; both ledger rows were stale. Not scheduled — scheduling it would have rebuilt a shipped board. |
| **P7** | `control-auth-post-http` needs a real OAuth client | router | R5 ✓ | — | Opus | **Merged** `d7f41f7` | `ai/p7` | Registered 2026-08-20 from D-p1-a. One of the two rows between the gate and 82 of 83. Discovery, dynamic registration, PKCE, callback on :8880. The only `AuthTransport` conformer is a test fake, so the 405 is real; the vendored SDK emits `state` unconditionally while `extractCode` hard-guards on it, so no SDK configuration reaches the reference's byte string |
| **P8** | Make `install-launchd-watch`'s `reran` attributable | parity | R4 ✓ | — | Opus | **Merged** `1e36144` | `ai/p8` | Registered 2026-08-20 from D-p1-e. The second of the two. `reran` went spuriously green 2 of 6 trials against a decoy `WatchPaths`, byte-identical to a genuine re-run, so the gate would record this row green about one run in three with a watcher that never re-ran. Everything P5 built is kept; the term becomes a stamped stimulus the watcher must observe and report |
| **X1** | The iOS accessibility-tree harness is red | mac/ios | — | — | Orchestrator + runner | **Merged** `79f6d2a` | main | Baseline 2026-08-20: `make all` exit 2 at `test-ios`, **19 failing cases**, all of the shape *rendered nothing*; macOS green at 1468 tests / 178 suites. Two instrument defects found by measuring: (1) a fixed 50ms settle pass is load- and OS-dependent — replaced with a non-asserting deadline poll, because asserting on an empty tree broke four passing tests while fixing four; (2) **`ObjectIdentifier` is unique only among live objects and the walker retained nothing**, so a released element vended by `accessibilityElement(at:)` had its address reused, collided in `seen`, and its whole branch silently returned `[]` — an address-reuse race, which is why failures moved between runs and files. **Closed by X3's engine fix, not by this row's own work** — X1 took it 19 → 9 → 2 with zero regressions at each step, and the residual two fell to X3; `make test-ios` reads 36/0. Recorded 2026-08-21 from LEDGER, which was current where this row was not; not re-run here, because the machine was at load average 548 and a red under saturation would have said nothing about the suite. (`comm` both directions over the sorted failing-test-name sets). The last 2 are `DiscoverSurfaceIOSTests` and **were red at the baseline**; the built-in diagnostic reports `descendants=5 containers=0 elemCounts=[]` for `ScrollView { QueueCommitBar }` — no content views realised at all — while `ScrollView { plate }` through the same harness now passes. Handed to a runner as `X1` |
| **M15–M23** | The mock-to-SwiftUI programme | mac | M23 ✓ | `design/mcp-router-console.html` | Opus | **M23 merged; the eight triaged 2026-08-22** | — | Nine briefs registered 2026-08-19/20 from the interactive mock. M23 is the conversion contract — five measurement layers, breadth-before-depth ledger, third exit state — and it merged at `6d54ce2`. **The eight were triaged serially on 2026-08-22: six To Do, two Needs More Info.** M16 and M21 carry one question between them — which document is the design authority — and the other six proceed under a recorded assumption so one answer un-parks the whole programme. Two facts every runner in this programme needs. **The instrument works for `servers` only**: `mock-fidelity-gate.sh <surface>` exits 3 at the missing manifest for anything else, so each item authors its own `planning/fidelity/<surface>.layers.json` and pairing file and teaches `MeasureDump` a `Surface` case, which declares `case servers` today. **And the briefs are stale against their own mock**, which M24 changed at `6c513b0` hours after they were written — four source-list groups rather than three, `⌘1`-`⌘9` in store-first order rather than the PRD's, a thirteenth sheet, and a product header and facts strip on the readme sheet. Take the mock over the prose describing it |
| M4 | Skills and marketplaces | mac | M1 ✓ M3 ✓ | `?only=mac&pane=skills` | Opus | **Merged** `7a28de8` | — | Relaunched after a 503 capacity death, not resumed — lifeline had the original agent parked and would have put a second writer in the worktree. **The merge found a merge-only defect**: M4 added `skills()`/`marketplaces()` to `ControlAPIClient` and M2 had written three test doubles against the older protocol, so both branches were green alone and the merged tree would not compile |
| M5 | Discover | mac | M4 ✓ | `?only=mac&pane=discover` | Opus | **Merged** `2a81c87` | — | The registry board plus the honesty it has to carry — every row declares its source. Found and fixed **D-p**, a data race in `StubHTTP` that had been mislabelled a flake; the label was the dangerous half, because flaky invites re-running until green. Four deferred children M5-a/b/c/d, one of which (**M5-d**, `axkit press` matches `AXRole == AXButton` only) is a harness limit later confirmed independently by M7 |
| M6 | Inbox and pairing (Mac) | mac | M5 ✓ | `?only=mac&pane=inbox`, `?sheet=pair` | Opus | **Merged** `6b3e940` | — | **The eighth and last board. `installed == Set(Destination.allCases)`, `scaffolded` is derived rather than listed, so it is empty by construction and the `isn't built yet` pane is unreachable.** Merged-tree gates re-run by the orchestrator: lint **0 / 356 files**, **1143 tests / 145 suites**, `BUILD SUCCEEDED`, acceptance **20 passed 0 failed** with the app never frontmost. Parity **not** run green (exit 2, `pool` needs `npm install`) — accepted only because M6's diff over `RouterCore`, `MCPRouterCLI` and `src/` is **empty**, verified rather than taken on report. **Eight tripwires, none deleted** — the brief named seven, M6 found an eighth; three moved off `ScaffoldedDestination(x) == nil`, which goes vacuous once nothing is scaffolded, onto `!BoardRegistry.scaffolded.contains(x)`. Critic AMEND, 10/10 accepted: the load-bearing one is **an `Undo` that undid neither half of what it named** — it restored an accepted row while the server stayed installed. **Two defects the critic missed**, both invisible to build, lint and a green suite: the failed pane blamed the router for this Mac's own storage failure, and a queued row announced itself as a button, answered `AXPress` with `.success`, and did nothing. One mutation **survived** its first form because the seam was private — missing coverage, not a weak assertion |
| M7 | Evals and Cleanup | mac | M3 ✓ M4 ✓ | `?pane=evals`, `?pane=cleanup` | Opus | **Merged** `85d8331` | — | Two boards in one item, taking `installed` to **seven of eight**. Merged-tree gates re-run by the orchestrator: lint **0 / 336 files**, **1073 tests / 137 suites**, **358 parity**, `BUILD SUCCEEDED`, acceptance **16 passed 0 failed** with Proctor frontmost throughout. Eight mutations red-green. Phase D critic REJECTed (11 raised · 3 fixed · 2 → M12 · 1 hedge removed · 5 rejected with citation). Unified three acceptance registry readers into `scripts/acceptance/board-registry.sh`, fixing a latent `head -1` that would have blocked on a second board. **Declared, not fixed: `mac-shell.sh` exits 1 at A22 on this branch AND on main** → **M11** |
| M8 | Settings, popover, quarantine | mac | M3 ✓ | `?pane=settings`, `?popover=1`, `?sheet=held` | Opus | **Merged** `affaed6` | — | Settings pane, the menu-bar status item and popover, and the quarantine sheet. `command`/`args`/`env` stay unwritable through the control API PATCH — now enforced as a Swift test rather than as a convention |
| **M11** | **Regenerate the M1 command inventory** | mac | M1 ✓ M3 ✓ M4 ✓ | — | Opus | **Merged (partial)** `2a434b9` | — | **The brief's premise was half wrong and the wrong half was a live product defect.** The orchestrator asserted the app *correctly* had `Add server…` enabled — an inference from reading `availability(in:)`, never a measurement. M11 measured the built app: `Add server…`, `Add marketplace…` and `Find` rendered **`enabled=0` with an EMPTY `AXHelp`** — dimmed **and** silent, permanently unusable with no explanation, **since M3**. `CommandItem` computed `.disabled()` from the `.none` shorthand while `ShellMenuReasons` wrote the help tag from the live context. **The inventory was deliberately NOT regenerated**: its column means the `.none` answer, a green test pins it, and rewriting it would have reddened a correct table — the derivation went into the **gate**, which now compiles `MenuCommand.swift` and asks `availability(in:)` with the real registry, so it cannot rot when a board ships. **A22 green**; lint 0/383, 1234 tests, both mac builds. `MenuCommand.swift` byte-identical to main — the rule was right. **Still exits 1 at A34** → **M13** |
| I1 | iPhone shell and pairing | ios | F2 ✓ F3 ✓ | `?only=phone&pairing=1` | Opus | **Merged** `d582d43` | — | 566 tests / 86 suites · 12 iOS tests on ONE reused simulator · 6 red-green mutations · fixed two `try?` sites swallowing Keychain failures (a refused save rendered "Paired." while nothing was written) · Phase D critic 8/6 caught `PhoneStorageFailureTests.swift` **untracked** — the fix would have shipped with no tests while `make test` still rose · unblocks I2 |
| I2 | iPhone Discover and detail | ios | I1 ✓ | `?only=phone&tab=discover` | Opus | **Merged** `ba139d4` | — | Resumed, not restarted: two runs died on 503 capacity and 4,911 lines survived as orchestrator rescues on a branch **37 commits stale**, whose raw diff read as deleting M5/M7/M8's merged work. Rebased twice, both clean. Merged-tree gates: lint **0 / 382 files**, **1230 tests / 152 suites**, **test-ios 23 tests `TEST SUCCEEDED`** on one reused simulator, **358 parity**, `BUILD SUCCEEDED`, acceptance 11 assertions over Discover and detail only. **No merge-only defect** although M6 rewrote the shared test support and five tripwires in the same window. Critic **REJECT**, 16 findings, 14 fixed in code and 2 in docs; all three HIGHs real, incl. copy rendering **"…changed in the last Any time days"** with a reset action that did nothing, and `isBandEmptyWithinResults` proven in the Kit suite while **nothing called it**. The critic also found **a guard blind to its own defect class**: `stripped()` removed string literals before the source scan ran, and the one logic-bearing file was exempted by name with no reason |
| I3 | iPhone Triage, Queue, Library | ios | I1 ✓ I2 ✓ | `?only=phone&tab=triage` | Opus | **Merged** `b50aa8d` | — | **The phone is complete.** Merged-tree gates: lint **0 / 433 files**, **1350 tests / 166 suites**, **test-ios 28 `TEST SUCCEEDED`**, 358 parity, `BUILD SUCCEEDED`, acceptance 5 assertions over its three surfaces only. **The inherited state was the story**: the branch arrived with ~3,800 lines of Phase A/B/C code and **1233 tests against main's 1234 — a net loss of one**; the plan's eight mutations each named the assertion that should kill them and most had never been written, so the first real work was building the proof layer. **8 defects found — 3 by the critic, 4 by the new tests, 1 live in shipped code**: `CapabilitySummary` took attention severity from `CapabilityPlate`, firing the attention colour on **every Smithery entry**, a majority of the corpus and exactly the noise A6 exists to prevent. Critic **AMEND** 18 findings (15 fixed, 2 rejected with citation, 1 registered) — three user-visible falsehoods incl. **the Queue's Undo not undoing, M6's exact defect one item later**, and **six of its own gates that could not fail**. Interaction is a **checklist**, with the commit bar absent rather than disabled; the three rejected patterns all share "the act happens where the affordance was not visible", so **A1 is asserted negatively and structurally** — verified independently at merge: no `DragGesture`/`swipeActions`/`onDrag`/`gesture(` anywhere under `Phone/` |
| **P1** | **Make the two auth routes reachable** | router | R3 ✓ R5 ✓ | — | Opus | **Merged** `496f88c` | — | `D-j` + `D-r2r-c`. **control-differential 49+2-known-defect → 53 of 53** against the running reference. Parity **72/82 → 73/83**, so **the DENOMINATOR MOVED and R4-C's target is now 83/83**. Merged-tree gates: lint **0 / 438**, **1379 tests / 169 suites**. Caught **the fleet's third merge-only break** — V1 tightened `ControlDeps.fileSystem` mid-flight, both branches green alone, merged tree would not compile. Declined to flip `install-launchd-watch`: unstable on **both** binaries over six runs (agreed 1 in 6, losing side alternating) → `D-p1-e`, and **deliberately not called "flaky"**, which was the `D-p` mistake. Two mutation defects found in the mutations themselves: one **could not** have reddened and was re-aimed rather than swapped, and one reported **11/11 green against a stale binary** · **SUPERSEDED 2026-08-16**: the denominator is still 83, but the TARGET is now **82 of 83** — `fixture-registry-search` became a standing exclusion after P3 showed it unprovable, and the owner set the target accordingly |
| **M13** | **The scroll-edge separator, A34** | mac | M1 ✓ M6 ✓ M11 ✓ | — | Opus | **Merged** `08b9bdf` | — | **The item inverted itself: the separator is correct and the CHECK was wrong, and NO APP SOURCE CHANGED.** `#2F2F2F` is `--line` (#FFF @7.5%) over `--ground` #1E1E1E — 0.075·255 + 0.925·30 = 46.875 = 0x2F — so the check was reporting the separator's own colour and calling it content. Per-pixel alpha recovers **0.0756 scrolled, 0.0000 at rest**, verified by the orchestrator after a clean rebuild (32 oks). **The orchestrator's own predicted mechanism was false** and the runner said so: `boardsThatScrollThemselves = [.activity]`, so Servers needed no move. Both mutations red. Two grok passes killed its first design and found two false-reds it had shipped (a white-only solver reads nothing on the light ground; a hard-coded 2× scale) |
| **V1** | **Re-run the out-of-family review on the router items** | review | R3 ✓ R2-W ✓ | — | Opus | **Merged** `29af3eb` | — | Owner's note overrode the lane: **grok-4.6 at high, no downgrade**, model verified per run from the JSON envelope (`modelUsage: grok-4.6-build`). **21 findings, all dispositioned, NONE rejected** — and that ratio is the finding, because R3's Phase D critic never ran at all, so no independent reader had ever read its shipped code. **9 fixed red-green**, incl. three trapping `Int` conversions on file-sourced numbers (measured `signal 5, Fatal error: Double value cannot be converted to Int`), `control.token`/`servers.json` written at the umask default where the reference uses `0600`, and the watcher resolving **two different homes** so a scratch `$HOME` still hit the developer's real directory. **Lane trap found and worth the item: grok exits 0 when session init fails** — the first dispatch of both reviews returned exit 0 carrying only an error payload, so a gate keyed on `$?` would have recorded two reviews that never ran. Merged-tree gates: lint **0 / 434 files**, **1362 tests / 167 suites**, `BUILD SUCCEEDED` |
| **P2** | **The `import` verb writes to the developer's own home** | router | R2-R ✓ R2-W ✓ | — | Opus | **Merged** `95d16f9` | — | Three rows blocked → proven (`div-r1-d3`, `install-import-servers`, `install-claude-json`), all blocked by one defect: `NSHomeDirectory()` ignores `$HOME`, so measuring them would have rewritten the developer's real `~/.claude.json`. **A live security defect found and fixed on the way**: `servers.json` was written at the umask default where the reference passes `{mode: 0o600}` — the file holding every server's API keys. Its M4/M5/M6 mutation triple exists because `fileExists ? .fixed(0o644) : .fixed(0o600)` passes the first two while widening a 0600 config on every import. The `install-claude-json` lane **extracts the node -e body from docs/install.sh at run time** rather than retyping it, because a retyped oracle drifts silently. Parity 74 → 77 of 83. **One deliberate deviation from the brief, flagged not buried, and accepted**: it did NOT lock `~/.claude.json`, because that lock would exclude nothing (Claude Code will never take it, the watcher's rewrite is unlocked by `D-v1f`, nothing in the app writes it) while leaving a permanent lockfile in the user's home |
| **P3** | **Oracles for the usage stream and registry search** | router | R3 ✓ | — | Opus | **Merged** `f466020` | — | Two rows blocked → proven (`control-usage-stream` driven over a real socket at BOTH routers, so the comparison is of what each emits rather than what each advertises; `control-registry-search` given a **deterministic fixture registry** so the comparison is about the router rather than the network). **The third row deliberately stays blocked**, reclassified `D-m` → `accepted-uncomparable`: not blocked on work, not waiting for anyone. The ledger licensed exactly that, and the runner took the harder half of the sentence instead of finding a formulation under which the row went green. **A silent-failure class found on the way, and it is the more valuable half of the item**: `parity-stream.sh` existed on disk, was executable and passed when run by hand — and was **dispatched by nothing**, because `stream` was never in `parity-gate.sh`'s LANES list. Its rows had sat blocked under their own notes since R2-R. The missing-script guard only fires for a lane the gate was asked about, so it could never have caught this. Parity **77 → 78 of 83**, blocked 6 → 4, denominator unmoved. **The runner never saw that number**: it stopped at lane 7 of 12, armed a monitor and ended its turn expecting a wake that workflow-inner agents never get. Its work was committed and every other gate had reported, so the orchestrator finished the measurement rather than relaunching it |
| **P4** | **Derive the manifest rows, and the directory-dependent normaliser** | harness | R4 ✓ | — | Opus | **Merged** `8686fd6` | — | **D-o is dead, and the fix is not the one the brief proposed.** Widening the character class was **rejected with a reason**: the path rules run first, so `[^"]+` would have rewritten a whole-cwd regression through to `<project>` and hidden it. Instead `project` is no longer matched by shape at all — it is checked against its own contract (equals `basename(cwd)` of its own object, non-empty), which is the reference's actual rule at `usage.ts:305`. **Verified by the orchestrator in the direction that matters**: every parity group reads byte-identical between the hyphenated repo root and a non-hyphenated worktree, including `fixture` at 23 of 24, the group D-o corrupted. That rewrite exposed a **second, blind defect no test had reported**: the `projectNames` rule split an array of OBJECTS on their internal commas and substituted `<project>` for the `calls` count, so a per-project count of 1 and of 900 normalised identically — it never failed because it mangled both sides the same way. **D-n closed for all 83 rows, up from 39**: four row deletions each exited 0 while reporting 82. Parity 73 → 74, denominator unmoved. **The pin is kept, and that was the orchestrator's call** — one line in a diff is the right price for closing a class where the number improves by losing work |
| **G1** | **Stop the checks blaming the app for being out of date** | harness | M11 ✓ I3 ✓ P4 ✓ | — | Opus | **Merged** `8cfb9e3` | — | Stale builds now **BLOCK at exit 2 naming staleness** instead of FAILING and naming the product. Headline proof: one real edit to `ControlAPIClient.swift` with no rebuild — new script names the stale build, old one blocked on the mtimes of four files that had not changed while blind to the one that had. **`D-m11-a` closed** on a simulated rebase (217 files touched, `git status` clean): the content check passes where the mtime check blocked forever. **THE M14 VERIFICATION IS DISCHARGED** — `mac-shell.sh` **exit 0, 39 assertions, never frontmost, measured at load 65**, which is higher than the 18–27 where it previously failed and the 42+ where M14 saw five false reds. `install-launchd-watch` is now **honestly blocked** with both real fixes kept, so parity reads **78 of 83, 5 blocked, 0 DIVERGED** — one lower than a lucky run and **the first deterministic number this harness has produced**; the 76/77/78/79 wobble was that row. `D-p3-a` and `D-p4-e` closed, both demonstrated by one mutation. 12 mutations, each rebuilt first, each **re-aimed rather than swapped**. **The plan gate returned REJECT with 11 findings and had never run on the first attempt**, which died on capacity before reaching it. **Four places measurement beat the orchestrator's brief**, including my own launch diagnosis: `set -e` aborts at `open`, so the 40-iteration poll I described never runs |
| **D2** | **Deferred register: Mac surfaces and design authority** | mac | M13 ✓ G1 ✓ | — | Opus | **Merged** `9e8a754` | — | Resumed from its own rescued WIP `9bdbffb`: all six of those changes were correct in substance and kept, but two were **half-applied** — the M9 rename left a second copy of the word in `CheckCopy.evalsTitle` and had moved none of the four acceptance scripts, so the suite would have gone red. **`D-m13-a` real but one board, not seven**: Servers measured 209.5pt below content top and `(768-351)/2 = 208.5` agrees; after, 16.0pt on all seven shell-scrolled boards. **`D-m13-b` real with the halves reversed** — the registry was right and the board wrong; Settings published 3 scroll areas, now exactly 1 on all eight panes. **M9 was wider than its spec**: THREE user-visible copies, and the third also promised an eval runner that does not exist. **Two defects D2 introduced and caught itself, both assertions that could not fail** (see `D-d2-lesson`). Gates: lint 0 · 1422 tests / 174 suites · build-mac 0 · 83 rows · mac-shell 0 at **load 16.9, never frontmost** · m8 21/0 · m7 16/0 · m6 20/0 |
| **D1** | **Deferred register: router side** | router | P1 ✓ P2 ✓ P3 ✓ P4 ✓ | — | Opus | **Merged** `997f7af` | — | `D-g1-g` fixed, **and the ledger entry it came from was wrong in mechanism**: the collision is not silent, every path exits 2 naming the port. The real harm was one step on — a run that could not measure the surface still printed a coverage fraction, and `69 of 83` from a run whose lanes never started is indistinguishable at a glance from a regression against a truth of 78. **Both numbers are in this fleet's history and neither was a measurement.** The gate now WITHHOLDS the fraction and `parity-lock.sh` refuses a second concurrent run. **The arithmetic is untouched: the new branch can only remove a number, never raise one** — checked specifically, because moving it was the one thing this item was forbidden to do. `D-g1-e` failability **11 → 16 of 19**. `D-p1-c` closed, and its FIRST fix was not actually closed for the real caller (`authStart` runs the observer in a detached Task) — caught by the grok critic, fixed, now a committed test. **Three rows closed as not-a-defect with the measurement**: `D-p4-b` (premise false — the gate does run unbuilt), `D-g`, `D-p4-c`. Parity **78 of 83, 0 DIVERGED, unmoved** — a withheld number, not a moved one |
| **P5** | **Close the last three closeable parity rows** | router | D1 ✓ P1 ✓ | — | Opus | **Merged** `e752305` | — | Parity **78 → 79**. It went up by one and **down from what the rescued commit claimed**, and the second movement is the more valuable. `cli-auth` (D-p1-d) **CLOSED and verified rather than inherited**: both routers answered `/health` with `{"ok":true,"upstreams":1}` and the verb printed an interpreted body per side — *stdio servers do not authorize; their credentials are env vars* for the stdio upstream, *no server named "nope"* for the unknown — which is substantive agreement rather than two connection failures agreeing, which is what the lane produced before. **Both guards proven to FIRE.** `install-launchd-watch` **WITHDRAWN** (see `D-p1-e`). `control-auth-post-http` left blocked with its triage **verified rather than accepted**. Gates: lint 0 (449 files) · test 0 (1422/174) · parity-selftest 0 · lane-selftest 0 · manifest 0 · parity-gate 1 before and after, correct while rows are blocked |
| **P6** | **State the owner's cutover target in the gate** | router | — | — | Opus | **Merged** `05296ea` | — | The risk was never the change, it was that it touches `parity-gate.sh`. So the deliverable was **the proof that it moves nothing**, produced two independent ways. **Mechanically**: the nine statements assigning `proven` / `total` / `blocked` / `mismatched` are identical before and after, only line numbers shifted. **Empirically**: BEFORE and AFTER full gates on one tree under a confirmed sole lock gave **byte-identical** output and an identical blocked list, across three runs. It also **verified the premises it inherited** rather than trusting the brief. **Seven defects fixed and every one was the report asserting something untrue** — three from its own mutations (a tail claiming *0 rows are excluded and named above* when nothing was named; a comment claiming a guard `parity-manifest-check.sh` does not have), four from grok (a line printed on the exit-2 path that contradicts it; a distance printed one paragraph after the drift warning withdrew it). **Seven mutations**, real manifest never modified. Two grok suggestions declined with reasons |
| **D-p6-e** | `m5` never reached the branch it aimed at, and P6 said so | open, small | The unscoreable-verdict branch is unreachable from the mutation because `parity-manifest-check.sh` rejects the verdict first and the gate exits before reconciliation. That branch is defence-in-depth and **its fix is NOT mutation-proven**. Recorded as unproven rather than counted, which is the behaviour this fleet has had to buy twice |
| **D-p6-f** | **"4 by suite only" and "eight unfailable" were never the same number** | closed, recorded | P6 was asked to reconcile them and the answer is that there is nothing to reconcile: the gate's **4** counts rows whose verdict is `proven-by-suite`, which is *the kind of evidence*, while the register's count is of assertions never shown able to go red, which is *a property of the assertion*. **A wire-compared row can still carry an unfailable assertion.** Worth keeping because the orchestrator suspected a single defect wearing two faces, and it was two honest measurements of different things |
| **D-p6-c** | **THE CLASSIFIER WAS RIGHT AND I WAS WRONG: I DISPATCHED A DUPLICATE RUNNER ONTO A LIVE WORKTREE** | closed, corrected | I resumed P6 twice on `wf_9697f470-a29` while `wf_360694cd-3c9` **already held a live P6 runner on the same branch and the same worktree**. I never checked. Denial 2's stated reason — *the agent is spawning a brand-new Agent call instructing a runner to create a fresh worktree/branch and redo P6's work from scratch* — was **an accurate description of what I was doing**, and it caught an orchestration defect I had not seen: two concurrent runners on one worktree, which is how a fleet corrupts a branch. I recorded it as a brief killed by the RULE and told the owner the work was dead. **Both claims were false.** The RULE governs a brief denied on its CONTENT; it does not convert a correct duplicate-work refusal into a dead item. **The check I skipped is the cheapest one available**: before any resume, list the run directories, read every journal, and identify which items already have a live agent — `wf_9697f470-a29` named P6 in its script and so did a run that was still writing. `D-p6-a` (my launcher says *create* for an item that exists) stands as a real defect; it was **not** the cause of denial 2 |
| **D-p6-d** | `TICKET-123` named a third time, and a live run was nearly resumed on it | closed, recorded | A resume instruction arrived for `wf_360694cd-3c9` describing *the lost item* as `TICKET-123`. **That id exists nowhere in this repo** and this ledger already records it twice as the placeholder used when item names cannot be parsed — the same label that misrouted `wf_48b3dafa-109` at row *ORPHAN-SCAN MARKERS ARE NOT EVIDENCE OF DEATH*, where all three claims were wrong. The run it named holds **I6 and P6, both with real branches**, and P6 was **actively writing**. Two independent tells, both cheap: an item id that is not in the ledger, and `journal started=2 results=0` on a run whose transcripts are still growing. **An id you cannot find in the ledger is the signal to verify before acting, not a detail to skip past** |
| **D-p6-a** | **A resume script that says `create` reads as new work, and a classifier is not wrong to say so** | open, for the owner | The launcher text was written for a FIRST dispatch and was never updated after the rescue. By the second resume the worktree, the branch and a commit all existed, so *create the worktree on a new branch from main* described **destroying the rescued state**, not resuming it. Two separate costs follow. The classifier read it literally and halted the run — **correctly, on the words it was given**. And a runner that had obeyed it literally would have discarded `c027463`. Registered because it generalises: **a rescued item's launcher is stale by construction**, and every relaunch after a rescue must be re-read against the tree as it now stands rather than as it stood when the text was written |
| **D-p6-b** | `tool_uses: 0` is not evidence a blocked agent did nothing | closed, recorded | Denial 1 reported zero tool uses and zero tokens, and the P6 worktree nonetheless came back holding an uncommitted revert of its own rescued work — `parity-gate.sh` byte-identical to main's copy, which is what a *before* measurement looks like when the run dies between the checkout and the restore. The branch had also been rebased onto the post-I5 main in the same window. **Nothing was lost** and the tree was restored to `c027463` before the retry, but the counter said none of it happened. Treat a blocked agent's usage figures as unreported rather than as zero, and read the tree |
| **D-p5-a** | **WatchPaths delivery is lossy, and the loss is launchd's** | carried by P5, unverified | From the rescued commit, so it is the dead runner's measurement and the relaunch owes it a reproduction. Taken with a scratch launchd agent whose program was **a plain bash script, so neither router could be the cause**: `launchctl print` carries `runs = N`, launchd's own count of spawns, and one `mv` onto the watched path incremented it in **four of five trials**, 9-14s later (ThrottleInterval 10 is the floor). In the fifth it never incremented inside 60s. If that reproduces, a lane treating one `mv` as a reliable stimulus is **nondeterministic by construction**, and no amount of waiting on the observer side fixes a stimulus that was never delivered — which is why P1's six runs showed the two terms varying independently and no single explanation ever covered the signature |
| ~~**D-p5-b**~~ **RESOLVED — the gateway was pointed at a dead upstream** | lifeline gateway | fixed, owner authorised | **Four runners died to this** (P5, I5, I6, P6) and the diagnosis was wrong twice before it was right. It was **NOT a hung process** and **NOT a stuck pid**: `gateway.out.log` shows it **listening correctly on 8787 the whole time**, chained to `127.0.0.1:8857` — **a port with no listener at all** — while `gateway.err.log` is a solid wall of `ECONNREFUSED` retries against it. A `launchctl kickstart` changed nothing, because it re-read the same dead upstream from `~/.lifeline/config.json`. **Fix**: repoint `upstream` to `8858`, which is **RelayApp, the owner's own multi-account proxy** — so this aims the gateway AT the proxy rather than bypassing it, and the history agrees (8858 was the upstream **21 times** against 8857's **7**). Config backed up first, then verified three ways: `8787 -> 200`, doctor green, and a real call end to end. **Two of my own probes were wrong on the way**: `lsof -p X -i` **ORs rather than ANDs** without `-a`, so it reported three other processes' sockets as the gateway's, and my log glob missed `gateway.out.log` / `gateway.err.log` — the same `.out.log` naming that has already produced one false "no logs" negative here |
| **I4** | ~~Let the phone install directly~~ **BRIEF RETIRED — panel determination** | ios | I3 ✓ D-m6-a | — | — | **Retired, replaced by I5/I6** | `ai/i4` (empty) | Two judges ran independently on the verbatim blocked text — **fable** in-family and **grok-4.6** out of family — and converged. Neither found a bad instruction in it. Both rejected park, close AND retry in favour of **redesign**. Both said the third-launch refusal was correct and gave the same standing rule (below). **Grok's finding, verified against the repo and upheld: the launch text closed a question the brief deliberately left open.** `I4-phone-direct-install.md` says a second Mac confirmation is an *"open question for the spec, not to be settled by assumption... let the owner decide"*; the launch text said "the owner asked for direct install... **so build it**", which forbade the runner from reaching the conclusion the brief reserved for it. That is an orchestrator defect, not a classifier artefact. **The brief is retired rather than parked** so no later wave reads "stopped pending the owner" as licence to relaunch the same text |
| **I5** | **Prove the phone↔Mac pairing round trip, and stop there** | ios | M6 ✓ I1 ✓ | — | Opus | **Merged** `4157bc4` | — | **THE FINDING: the round trip does not happen because NEITHER SIDE IMPLEMENTS IT.** M6 suspected an unproven transport; this measures an **unimplemented** one. The line that carries it — **row 7 beside row 8: the phone stored a paired-Mac record for a Mac it never contacted, at an address it demonstrably could reach.** The calibrations are the design: an absence is trivial to manufacture by accident, so four rows exist only to make rows 4 and 8 mean something, the load-bearing one being **a connection made by the SAME process whose pairing call is under test, to the SAME port, in the SAME run** — counted, while the pairing call contributed zero. **Nine mutations**, every assertion proved able to go red, including a natural one where run 1's env var never reached the simulator and the harness **BLOCKED on the assertion count rather than passing with two of three probes skipped**. Runs at load 12.18 / 34.21 / 76.94, same result |
| **D-i5-a** | **The out-of-family review landed a real hit, and it was taken** | closed, recorded | Grok attacked the METHOD rather than the write-up. Its hit: the phone half drove `FixturePairingService` directly, a type whose contract is *do not talk to anyone*, so **the tap was confirmatory theatre and the conclusion rests on a source grep as much as on the experiment**. It also enumerated what a loopback TCP tap **structurally cannot see** — IPv6 `::1`, UDP, Bonjour/mDNS, unix domain sockets, and any connection to an address other than the tap's own. Four holes closed in response, including **driving the pairing sheet open via the accessibility API** so the socket count is of a Mac actually displaying a live code rather than of an idle window. Grok's summary stands as the honest framing: *"in this repository there is no implemented pairing transport, so a phone-to-Mac pairing exchange cannot occur. That is a source fact. The tap is consistent with it. The tap is not what makes it true"* |
| **D-i5-b** | **Everything queued on this surface was downstream of a transport that does not exist** | open, for the owner | `D-m6-a` is not *unproven*, it is **unimplemented**, and the register should say so. The consequence reaches back: **I4 could never have been built** — direct install on top of no transport at all — so the classifier block, whatever tripped it, stopped work that had nothing underneath it. Any future item that moves an install privilege **builds the transport first**, and that is a substantial item rather than a follow-up |
| **I6** | **Make Mac approval fast, without moving the boundary** | mac | M6 ✓ | — | Opus | **Merged** `ef4f615` | — | **Two out-of-family reviews dispositioned and closed.** Gates: lint clean across 461 files · **1467 tests in 178 suites** (up from main's 1422/174, adds 45 tests) · build-mac BUILD SUCCEEDED · **31 of 31 mutations proven RED** in `scripts/acceptance/i6-mutations.sh`. The boundary holds along every indirect path. Popover inbox band (`MenuBarInboxBand`) renders glanceable, capped rows, oldest-first, with full capability text; partial rows carry no review button. Arrival notifications (`UserNotificationArrivalNotifier`) seed at login so no storm of banners occurs; single-item banners carry Review and Decline; multi-item banners carry Review only. Withdrawals commanded immediately on disposition and swept on next read. Delegate attached at `applicationDidFinishLaunching` so launch responses are never lost |
| **D-i6-e** | **A runner returned the bare string `ok` instead of a report** | closed, recorded | New failure mode, and it is not a death: 55 tool uses over 12 minutes, **eleven files modified and uncommitted**, and a two-token return. The work was real and on-brief — the diff carried the review's two hardest fixes — but **none of it was reported and none of it was committed**, so reconstructing what it had done cost a full relaunch. Rescued as `15d9e7f`. The brief now says COMMIT AS YOU GO **and REPORT AT THE END**, because this fleet had only ever guarded the first half |
| **D-i6-f** | Three rescue commits on one branch, and the second one broke a gate | open, watch | `ebeece0`, `7fe67ab`, `15d9e7f`. Each is unreviewed code committed verbatim by the orchestrator to survive an infrastructure death, and **`7fe67ab` is the one that split a test suite and left nine mutation filters aimed at the wrong one** — the exact defect the review then refused the branch for. The rescues are still correct as a policy, since the alternative was losing the work outright, but **the third one was checked for compilation before the ledger claimed anything about it**, which the first two were not |
| **D-i6-a** | **THE ORCHESTRATOR'S RESCUE COMMIT BROKE THE MUTATION GATE** | closed, fixed | Re-aimed in `0abceb2` and all 31 mutations proven RED. The lesson stands: a series bounds agreement, never what a term measures |
| **D-i6-b** | The many-item notification ships a button the spec forbade | closed, fixed in `15d9e7f` | Two distinct `UNNotificationCategory` instances registered: single-item with Review/Decline, many-item with Review only |
| **D-i6-c** | The notification delegate is installed too late to receive a launch response | closed, fixed in `15d9e7f` | Shell moved to app delegate; notification delegate attached at `applicationDidFinishLaunching` |
| **D-i6-d** | Four smaller claims the spec makes that the code does not keep | closed, fixed in `8dbc4dc` / `7b6d5f2` | `notificationsOff` deleted; partial row review button removed; immediate withdrawal commanded; keyboard table amended |
| **D-i4-a** | **DESIGN.md's boundary is load-bearing and was never amended** | open, for the owner | `DESIGN.md` states it as a principle: *"**The phone queues; it never installs.** Pairing grants a remote party the ability to put executable code on a laptop, so the phone's commit bar sends items to the Mac's inbox for review. This is narrower than 'remote install' and deliberately so."* I4 would have contradicted a written design principle **and no amendment to it was ever drafted**. Any future one-tap install has to amend this line first, in the open, rather than route around it |
| **D-i4-b** | **Off-by-default was never in the brief, and this ships to other people** | open | Fable's substantive gap: the owner's accepted threat model covers **his** Mac, not a downstream user's. Both judges independently required the same shape for any future version — the grant **originates on the Mac** and is never implied by pairing, is per named device, **off by default**, visible in Settings with an install history, revocable in one action killing in-flight installs, restricted to registry identities rather than arbitrary URLs, and gated on the phone being unlocked |
| **RULE** | **Standing rule for an automated safety denial** | orchestrator | Both judges gave this independently and in near-identical terms. A **transient-labelled first denial** licenses **one** identical retry. **Any later denial, or any denial citing circumvention, kills that brief**: do not relaunch it, do not reword it to pass, and do not carry it into the next wave. The test for any rewrite is whether it improves the brief **with the classifier imagined away** — a genuine redesign passes, synonym-shuffling does not. **The classifier halts an execution path; it is not a product verdict**, so silent parking is also wrong because owner-authorised work would vanish without the owner learning it happened. Escalate with the verbatim text, the denial count, and a disposition that is not "try again" |
| **D3** | **Deferred register: phone copy and the harness limit** | ios | I3 ✓ | — | Opus | **Merged** `67ae4f5` | — | **M5-d closed with a verb, not a widening.** Measured before building: a SwiftUI `.segmented` Picker vends `AXRadioButton` / subrole `AXSegment` in an `AXRadioGroup`, label in `AXDescription`, and **`AXValue` reads 1 for the chosen segment** — the observable the verb needed. `axkit pick` presses, re-walks, and requires exactly one segment in the target's own group to read 1 and be the one named. Exit **0** switched / **3** already chosen so the call drove nothing / **1** ambiguous — 3 rather than 0 because every call site is `>/dev/null || fail`, which makes a printed-word distinction invisible. A SECOND verb deliberately: widening `press` would lose the restriction that stops a menu item being pressed where `AXPress` returns `.success` and does nothing. Gates: lint 0 · test 0 (1422) · build-mac 0 · iOS fresh sim 29 executed, 2 pre-existing failures · grok ran, found **4 real defects in the first draft**, all fixed and re-proven |
| — | **BLOCKED: the Apple developer identity** | — | — | — | — | **Needs input** | — | `apple-identity` came back `as-found`: pre-selected by the page, never confirmed, and flagged `blocksAutomation`. **Not scheduled.** Its note points at a 1Password vault, and the bundle id it supplies is domain-shaped rather than reverse-DNS and conflicts with the assumed one. Holds signing, the phone leaving the simulator, and `D-e` |

| M14 | A shipped menu tells the user the app is not built | mac | M1 ✓ M6 ✓ M13 ✓ | — | Opus | **Merged** `7e7ed70` | — | **The diagnosis inverted on measurement, the second item running to do so.** The gate's own text blamed a surviving scaffold; on a clean Release build `ScaffoldCopy` and `ScaffoldedDestination` are **zero** in the bundle, so M6's deletion worked. The single hit **is** `surfaceAbsent`'s live help tag, which has shared that substring with the deleted pane's copy deliberately since M1, and a bytes grep cannot ask about reachability at all. A new `.featureUnbuilt` refusal separates a missing **destination** from an unbuilt **feature**; one substring grep became four derived checks. Merged-tree gates: lint **0 / 438**, **1379 tests**, both Mac builds. **`mac-shell.sh` measured exit 0 / 39 assertions by the runner; the orchestrator's re-run hit `axkit setframe` (line 974, provably outside M14's diff) under load 42.9/64.9/137.9 from two live runners — full green OWED on an idle machine.** Five mutations red-green, **each rebuilt first** (without a rebuild every one reports BLOCKED, not red), incl. one that only bites when the reintroduced symbol is also **referenced**, since unreferenced is dead-stripped. Three grok reviews, all AMEND, all three changed the work; the plan gate found **two mutations that could not have reddened** and both were **re-aimed rather than swapped**. `spec-M1.md` is committed **on the branch** by declared exception: `MenuCommandTests` parses that table as a test oracle, verified at merge |
| M15 | Settings becomes its own window | mac | M1 ✓ M8 ✓ M23 ✓ | `design/mcp-router-console.html` | Opus | **Merged** `29d5111` | — | **Triaged 2026-08-22** — spec at `planning/specs/spec-M15.md`. Settings is `Destination.settings`, a sidebar board; `MCPRouterApp.swift` declares three scenes and none is a `Settings` scene, its own comment at :21 naming the line that would change. `⌘,` maps to `.select(.settings)`. **No URL handling exists anywhere in `app/Sources`** — `onOpenURL`, `URLComponents` and `queryItems` all return nothing — so the brief's `?window=settings` addresses are the mock's own navigation and are recorded out of scope. Seven panes confirmed against the mock's `data-pane` values; the brief's prose and its own table disagree on where Menu bar sits and the mock decides it. The riskiest edit is removing `.settings` from the destination enum: the digit accelerators are generated from it, frame restoration persists its `rawValue`, and M6's `installed == Set(Destination.allCases)` invariant is asserted by test. `SURF-011` already fails both witness passes on what the campaign calls *a content divergence needing an owner decision*, against a third content set. Eight assumptions, no essential question. Out-of-family review `agy`/`gemini-3.7-flash-high` AMEND — accepted that every dimension the brief quotes must route through `MetricToken` or redden `no-raw-design-values.sh`, and that the deep links are an orphan requirement across three briefs **Planned 2026-08-22** — plan at `planning/plans/plan-M15.md`, Large tier, 759 lines. **The riskiest edit is bigger than triage recorded: `Destination.settings` has eleven readers, not four** — eleven Swift sites across `Destination.swift`, `Sidebar.swift`, `ScaffoldPane.swift`, `ShellWindow.swift`, `ShellCommandRouter.swift`, `Icon.swift`, `ShellRestoration` and four test files, plus two more in `mac-shell.sh` and `m6-inbox-pairing.sh` that a source-only sweep misses. Out-of-family **plan** review (distinct from the triage review above): `agy`/`gemini-3.7-flash-high` returned **REJECT** with nine findings, all seven sections FAILED. Seven were dispositioned — two critical compile-order breaks fixed by a new atomic D0 removal phase and an additive A3/B6; the no-op `perform(.openSettingsScene)` replaced by an injected `openSettings`; the tautological acceptance gate tightened and E4's citations moved to pre-existing artifacts; pane selection persisted through `ShellRestoration`; one `SettingsWindow` initializer; R8 corrected so criterion 8 is falsifiable at base. **One was overruled with reason**: the 256pt source list stays, because `DESIGN.md` §2 specifies `Sidebar 256pt` and the mock's own `mac-craft:metrics` block carries `sidebar 256px` and no 200, so the mock disagrees with itself; the 56pt gap is declared in the fidelity manifest. **The planner's session ended mid-disposition**, so §11's four narrowings and three §8 parity rows the review named are recorded as open in the plan's §14 rather than folded in. The `claude-fable-5` second reading never returned, so this gate stands on a single family. One fact corrected here: the spec lists **nine** assumptions at `spec-M15.md:23-31`, not the eight both the spec and the plan claim. **Gap-fix delivered 2026-08-22 at `554a473`, eight commits, in verification.** All four record blocks addressed: the divergence list adjudicates its own 97 findings, the row count corrected in its four homes, `planning/evidence/M15-acceptance.md` written per `UI_VERIFICATION.md` rule 2, and **the duplicate-`Settings…` defect gains a regression guard that counts rather than matches** — `mac-shell.sh`'s EXTRAS loop matched each item against the inventory, so a second identical item passed and the one product defect this item found by hand had nothing holding it. One commit worth reading alone: `aae3033`, *the reconciler went red between two runs, and main is what moved* — the check-E false-RED, **diagnosed correctly** where R17's runner had read the same symptom as another session merging. **Gap-fix verified Done 2026-08-22 at the metamorphic rung and merged at `29d5111`** — BL-3's load-bearing claim flipped by a controlled single-property mutation and flipped back rather than re-run, BL-1 re-derived by regenerating the artifact, BL-2 by an independently written sweep. **A correction the orchestrator owes**: this row previously credited M15's runner with diagnosing the check-E false-RED correctly where R17's had not. `aae3033` gets the **mechanism** right and repeats the **specific** error — *seventeen commits, M21's merge and G5's among them*. There was no G5 merge: `4de2080..52f0c5c` is **18 commits with exactly one merge**, `e121801`, and `ai/g5` was cut from `2fbe062` having committed nothing, so its tip **was** a main commit. Today's green is not main moving again — `ai/g5` committed `3cd45c6` at **14:40:51, six minutes after `aae3033`**, and that is what stopped check E firing. **And the guard's claim is narrower than its comment**: armed by re-chording `Add server…` to `,`, AppKit **strips the chord from the loser**, so A19b read 35 chords on one item each against a 36/23 baseline and saw nothing; A20 caught it instead. The guard bites on the case it was built for, and `AXMenuItemCmdChar` cannot see a collision that has already been resolved — filed as G4's **nineteenth** instance. Two fixes named and not blocking: the gap-fix's reconciler paragraph, and A19b's comment. **Merged-tree gates re-run by the orchestrator**: `make lint` **0 violations in 549 files**, `0/556 require formatting`; `make test` **1725 tests in 215 suites passed**, 0 failures; reconciler **0 across A–L**. |
| M16 | The Signal Path replaces the Breaker Column | mac | M3 ✓ M23 ✓ · blocked by M21's answer | `design/mcp-router-console.html` | Opus | **To Do** | — | **Unblocked 2026-08-22**: the design-of-record question is answered — the console mock. M16 is therefore a **retirement**, not an addition: `DESIGN.md` §1 names the breaker column as the signature, §2 records nineteen of its measurements, `Breaker.swift:4` and `BreakerGeometry.swift:5` both cite it in source, and `BreakerParityTests` asserts exact two-way name-set equality between `DESIGN.md`'s rows and `BreakerGeometry.standard` — so removing the levers reddens a parity test whose oracle is the document being re-authored. Sequence that deliberately. **Triaged 2026-08-22** — spec at `planning/specs/spec-M16.md`. **One essential question, and it is M21's fork applied to the signature element.** `DESIGN.md` §1 names the breaker column as the app's signature, §2 records nineteen of its measurements and §7 its two springs; `PRD.md` §9.2 names the Signal Path instead. Built and cited as the signature in source: `Breaker.swift:4`, `BreakerGeometry.swift:5`, four `BreakerState` cases, `ServersBoardTable.swift:20` sizing the row gutter from the housing width. No `Jack`, `SignalPath`, `Patchbay`, `Hub` or `Rail` type exists anywhere. **The mechanical half of the block, verified:** `BreakerParityTests.swift` declares `BreakerGeometryParityTests`, which reads `DesignDocParser.breakerRows(in:)` out of `DESIGN.md` and asserts exact name-set equality against `BreakerGeometry.standard.documentedValues` in both directions — so removing the levers reddens a parity test whose oracle is the document whose fate the answer decides. M23's ledger has already enumerated this item's work: `planning/fidelity/servers.ledger.md` carries `absent` rows for the signal-path card and the harness dots, each cited to this brief, and `servers.pairing.tsv` states the cause outright. The gate sits at exit 1 with 116 breadth and 16 copy findings, a large share of which close only under answer (a). Three options offered: build the band and retire the levers; keep the levers and add the band as the second subject-mined element `DESIGN.md` §10 says is owed (marked as the reversible one); or keep the levers and treat the console mock as an exploration. Five assumptions hold under (a). Out-of-family review `agy`/`gemini-3.7-flash-high` AMEND, `claude-fable-5` second reading — both agreed the block is right and cheaper than the assumption, and both said it is one question rather than two |
| M17 | Four states on every surface, and chrome that follows | mac | M1 ✓ M23 ✓ M15 M22 | `design/mcp-router-console.html` | Opus | To Do | — | **Triaged 2026-08-22** — spec at `planning/specs/spec-M17.md`. **The brief declares `Depends on: M1` and that is wrong in two places:** its forty cells are four states over the nine boards the mock draws plus the Settings window, and the app has seven boards plus a Settings board — Harnesses and Insights are M22 and the window is M15. Both lanes raised this independently. `StateContainer.swift` already models the nine `DESIGN.md` §5 states, and is instantiated exactly once, in the `#if DEBUG` design gallery; every shipping board hand-rolls its own switch. All eight boards do have real empty, loading and error bodies, so this is unification plus two new boards plus making the count assertable, not building unhappy paths from nothing. `M7DesignedStateTests` covers two boards and roughly fifteen strings; its `assertUsable` rejects an empty string, anything under twelve characters and six placeholder patterns. **Nine states versus four was tested for divergence and produces the same build**, because the mock's four are a strict subset of the document's nine — so it is an assumption rather than a question, and `REQ-017` stays true. Cites rather than re-derives `D-m23-g` (filed against M17 by name), `DEF-015` (the overflow clipping this item must keep fixed), `DEF-014` and `DEF-034` (state reachability), and `SURF-003`'s `unoracled` verdict, whose fixture gap M23's harness is the route out of. The briefs are stale against their own mock: it now draws four source-list groups where they say three, after M24 at `6c513b0`. Nine assumptions, no essential question. Out-of-family review `agy`/`gemini-3.7-flash-high` AMEND — its argument that this item is unbuildable without M21 was tested on both grounds and rejected, with the exposure recorded as an assumption instead |
| M18 | Twelve sheets, and the gate each decision gets | mac | M1 ✓ M8 ✓ M23 ✓ M15 M19 M22 | `design/mcp-router-console.html` | Opus | To Do | — | **Triaged 2026-08-22** — spec at `planning/specs/spec-M18.md`. **Thirteen, not twelve.** Counted by `id="sh-*"` in the mock: the twelve the brief names plus `official`, which M24 added at `6c513b0` after this brief was written the same morning, and which `design/mcp-router-console-spec.md` names. **Two of the mock's own links are dead** — `sheet:changelog` and `sheet:install-server` resolve to no sheet id, and `openSheet` returns early — reported as faults in the mock rather than built as two more panels, since the changelog is already a tab of the readme sheet. The build has seven `.sheet(` sites, four on `item:` and three on `isPresented:` (`InboxBoard` twice, `DiscoverBoard` once), no single sheet enum but five per-board ones, and `EvalsBoardModel.Sheet.recheckAll` which is never assigned or presented. `confirmationDialog` appears once in the tree and it is on the phone; `alert(` appears nowhere. Five of the thirteen have no host surface until M15, M19 and M22 land — the brief declares none of those. Only `pair` has measured evidence and it is decisive: `DEF-001` is open, the transport does not exist, and `SURF-010` fails while `CASE-0142` and `CASE-0143` pass against the honesty requirement — two requirements, opposite verdicts, one sheet. This item builds the panel and its wording; the exchange stays `DEF-001`'s. **Nothing at all is recorded for the other ten**, stated as an absence rather than read as agreement. A live contradiction recorded rather than resolved silently: `DESIGN.md`:400 says `⌘⌫` removes a server *undoable, never confirmed* and the build confirms, deliberately, per `DEF-011`'s fix note. Ten assumptions, no essential question. Out-of-family review AMEND — accepted three missing dependencies and the `⌘⌫` contradiction |
| M19 | The in-app GitHub-flavoured Markdown viewer | mac | M4 ✓ M23 ✓ M18 M21 (the badge colour only) | `design/mcp-router-console.html` sheet `readme` | Opus | To Do | — | **Triaged 2026-08-22** — spec at `planning/specs/spec-M19.md`. **The emptiest starting point in the programme.** There is no Markdown rendering of any kind in `app/Sources`: `AttributedString(markdown`, `import Markdown` and `MarkdownUI` all return nothing, and the only `README` and `changelog` hits are a URL-parsing comment and a fixture skill named `changelog-writer`. The panel it renders inside does not exist either. **And nothing is measured.** No defect, case, deferred row or witness verdict bears on readme, changelog, shield, markdown or gfm across the whole campaign — stated as an absence rather than read as agreement, which makes M23's gate the only thing that will catch drift here. The mock draws more than the brief describes: the readme sheet carries a product header (mark, name, verified publisher, pitch, install) and a five-cell facts strip that M24 added at `6c513b0` after the brief was written, with its commit giving the reason. The library question is settled in the brief and the planner should not re-open it — `AttributedString(markdown:)` covers inline runs and not tables or fences, both of which the mock draws. Note `CODING_PRACTICES.md` is a TypeScript and Next.js document with nothing to say about this target; `SWIFT_PRACTICES.md` is the applicable one. Eight assumptions, no essential question. **One acceptance line waits on M21** — the shield colour cannot be a token until `ColorToken` gains a case, and `DesignTokenParityTests` asserts exact two-way name-set equality against `DESIGN.md`. That is a dependency, not an owner question, and it is why this is To Do rather than blocked. Out-of-family review AMEND — one lane argued this item is blocked on M21 and the mechanism was verified and accepted, the block was not |
| M20 | Menu bar, status item, and the notification banner | mac | M1 ✓ M8 ✓ M11 ✓ M14 ✓ I6 ✓ M23 ✓ M15 M22 | `design/mcp-router-console.html` | Opus | To Do | — | **Triaged 2026-08-22** — spec at `planning/specs/spec-M20.md`. The app declares six `CommandGroup`s, not nine menus: there is **no Router menu and no Library menu**, and the View group is a `ForEach` over seven destinations at `⌘1`-`⌘7`. `MenuCommand.swift` carries 26 fixed cases plus seven generated, with `availability(in:)` returning four refusals and `exportLibrary` hard-wired `.featureUnbuilt`. `MenuBarExtra` and its popover exist with the amber-dot rule already correct; what the popover lacks is the four-count summary and the three-control decision band. `UNUserNotificationCenter` is wired for I6's arrivals with `.review` and `.decline` — the analyst-finding notification with Install, Details and Dismiss does not exist, and neither does the analyst. **The accelerator map disagrees three ways** and the mock wins: it reads Discover `⌘1` through Insights `⌘9` after M24 re-ordered it at `6c513b0`, an owner-authored commit whose message states the intent, while `PRD.md` §9.4 still lists Servers `⌘1`. Recorded as an assumption rather than a question because it is one table and reversing it breaks nothing. Stands on M11's measured finding — three menu items shipped `enabled=0` with an empty `AXHelp`, dimmed and silent since M3 — and on M14's `.featureUnbuilt`; `D-m14-a`, `D-m14-b` and `D-m14-c` land squarely here. **The status item has never been measured and the reason is structural:** `SURF-009` carries three `n/a` cases, all reading *NSStatusItem is not an AXPress target while MCPRouter is backgrounded*. M23's `MeasureDump` renders under a `.prohibited` activation policy and reaches it, so the brief's popover acceptance is reachable through that route and not the campaign's. Eight assumptions, no essential question. Out-of-family review AMEND — accepted M15 as a missing dependency and the orphan deep links; the argued block on the accelerator map was rejected on the divergence test |
| M21 | The token layer, the split accent, and `DESIGN.md` | mac | F2 ✓ M23 ✓ | — | Opus | **Merged** `e121801` | — | **Unblocked 2026-08-22**: the design-of-record question is answered — the console mock, which is what `PRD.md` §9.1 already said. M21 is now the re-authoring of `DESIGN.md` against it. Measured size: `token-register.json` holds 89 rows at 25 matched and 64 pending; `Assets.xcassets` has **zero** colour sets so the high-contrast mechanism is unbuilt rather than unfilled; and two brief figures are stale — contrast is 6,548 pairs not 5,788, and the 89 is M23's parsed row count rather than a `:root` count of 45. **Triaged 2026-08-22** — spec at `planning/specs/spec-M21.md`. **This is the programme's one owner decision and it is asked here in its general form: which document is the design authority.** The repository holds both commitments at once and neither record names the other artifact, which is why every reconciliation check reads clean over it. On one side: `DESIGN.md`:8 and `ORCHESTRATOR.md`:18 name `design/mocks/prototype.html`, `campaign.json`'s `designOfRecord` is that file, and DEF-016's closure records the owner's decision verbatim — *Closed 20 Aug 2026, on the owner's decision that `design/mocks/prototype.html` remains the design of record for the Mac console* — with DEF-012 repeating it. On the other: `PRD.md` §9.1 says the console mock *supersedes the Instrument Panel direction* and that *`DESIGN.md` is historical. Resolving that is tracked as M21*, and `design/mcp-router-console-spec.md`:3 says the mock was built *deliberately ignoring* both. **The owner's decision was taken about the prototype versus two superseded contact sheets; the PRD's claim was written about the console mock. Nothing joins them.** **The size of the answer is already measured**: `planning/fidelity/token-register.json` holds 89 rows and M23's ledger classifies them 25 matched, 64 pending. **The mechanical half of the block is verified**: `DesignTokenParityTests` asserts exact two-way name-set equality between `ColorToken` (18 cases, no `*Ink` of any kind) and `DESIGN.md` §2, so even the uncontroversial split accent reddens it until the document carries the rows — and writing those rows against the mock is the contested act. `Assets.xcassets` holds zero colour sets, so the high-contrast mechanism is unbuilt rather than unfilled, and the campaign's own sample line says *drop high-contrast (no authored tokens)*. Two of the brief's figures are stale: the mock's contrast gate now reports 6,548 pairs rather than 5,788 (M24 at `6c513b0`), and the 89 is M23's parsed row count rather than a `:root` count, which measures 45. Three options offered, with (b) marked as the reversible one; **(c) — authority split by surface — was added because of the review**, since M19 and M22 draw surfaces the prototype does not have at all. Pairs with `DEF-042` on M28's docket, which is the same question's concrete instance. Seven assumptions. Out-of-family review `agy`/`gemini-3.7-flash-high` AMEND plus a `claude-fable-5` second reading — both agreed independently that this must block and that it is one question rather than two **Planned 2026-08-22** — plan at `planning/plans/plan-M21.md`, Standard tier, 609 lines. **Sequencing against M16 is decided, and it is D6 in the plan: M21 lands first, M16 second.** Three binding reasons — M16 needs `--jack-off`, `--jack-ring` and the `jack-lane` metric, all of which M23 filed under an `M21-*` citation and which `no-raw-design-values.sh` forbids M16 from typing as literals; M16 must edit the same `DESIGN.md` §1 signature paragraph M21 re-authors; and **the parity oracles do not intersect** — `DesignTokenParityTests` reads the Grounds and lines, Label tiers, Colour, Type and Chrome geometry tables while `BreakerGeometryParityTests` reads `Breaker geometry` and nothing else. So nothing in the suite goes red between the two merges: M21 leaves `### Breaker geometry` byte-identical and adds one sentence recording that it documents the outgoing signature and retires under M16. What is inconsistent in that window is stated rather than hidden — §1 names the Signal Path while §2 still carries the breaker's nineteen rows — and `PRD.md` §9.2 already names the Signal Path, so the window closes a PRD/DESIGN disagreement rather than opening one. Both out-of-family lanes confirmed the order independently, one adding that M16 landing first would have to author the Signal Path tokens in `ColorToken` and redden two-way parity immediately. **The out-of-family plan review did not run during the planning session**: three attempts, all zero-byte — `agy` denied on a permission prompt, `agy` again timing out under `--sandbox --dangerously-skip-permissions`, and `claude-fable-5` still running at session end; codex is down to 2026-08-27 and grok's balance is exhausted. It was run afterwards against the byte-identical packet and **both lanes returned AMEND**, eight questions each. Three findings were checked against the repository and stand: the plan's opening census is wrong — `token-register.json` carries **50** rows with an `M21-*` citation (38 colour, 7 metric, 5 composite), not 45, and the five composite shadow rows are neither modelled nor declared out of scope; five tokens (`--accent-wash`, `--accent-wash-line`, `--tl-close`, `--tl-min`, `--tl-zoom`) carry only `mock.light`, so the register cannot be the oracle for their dark values the plan says it is; and `LightAppearanceTests.lightIsAuthored`, which exempts only `.onAccent` by name, will redden on exactly those five when `ColorToken` grows to 40 — a red gate inside M21's own first run that the plan does not predict. **Both lanes independently reached the same strongest finding**: the 3.23:1 dark-onAccent deviation must be ported rather than resolved, because M21 migrates no call sites and white-on-accent keeps shipping until M16-M22 move them. They named two different fourth problems in D3 and both are real — a missing WCAG 1.4.11 3:1 non-text rung, and `--accent-ink` being a fill while every other `-ink` is text. **Nothing is dispositioned into the plan**: the verdicts postdate the planning session and are recorded in the plan's review section as a work order for the runner, not folded into the body. **Verified Done 2026-08-22 and merged at `e121801`.** `ColorToken` 40 cases over four resolved appearance contexts, `MetricToken` 21, `DESIGN.md` §1-2 re-authored to *Patchbay*, register regenerating **byte-identical** to the committed file at **89 rows — 70 matched, 19 pending, 0 uncited** against a plan expecting 64+. **The verification is stronger than the delivery in the two places the runner said it could not reach from its own worktree.** `mac-shell.sh`'s one scroll-edge failure is **not this branch's**: `main`'s build reports the identical `0.872 uniform` against the same 0.90 bar and passes 52/52. What M21 does move there is the separator — `main` **0.0742** to the branch's **0.0921** against a token going 7.5% → 9%, nominal 1.200 and measured 1.241, while `main` at the unchanged token differs from M13's reading by 1.9%, the run-to-run spread. An order of magnitude outside the noise and landing where the token says. And all 40 colour rows were reparsed from `DESIGN.md` alone with all **78** documented ratios recomputed in WCAG arithmetic: **zero disagreements beyond 0.05**. **Arm 7a's no-bit confirmed to four decimals** — `#FF5A5D` is 4.5610:1 on dark `--raised`, `#FF6E70` is 5.1209:1, so lightening raised contrast and the arm was aimed the wrong way; one precision the note missed is that the mutation would have reddened `colorsDocumentToCode` regardless, since `DESIGN.md:169` documents the original, so *no bit* is true of the aimed oracle and not of the suite. The silent-mutation-reuse defect is settled by evidence rather than assurance: 7b's and arm 8's recorded figures reproduce to **sixteen digits**, which cannot happen without the mutation having been applied. Departures all delivered-with-reason, none scope drift — the pin is **ported not replaced** and provably so, since no call site moved. Carried as `D-g4-a`: `planning/fidelity/servers.ledger.md` still reads `25 matched, 64 pending` beside the new register. **Merged-tree gates re-run by the orchestrator rather than taken on report**: `make lint` **0 violations, 0 serious in 535 files**, `0/542 require formatting`, `no-raw-design-values: clean`; `make test` **1697 tests in 211 suites passed**, exit 0 — identical to the branch figure, so the merge introduced nothing; reconciler **0 across A–L**. |
| M22 | The Harnesses and Insights boards | mac | M1 ✓ R6 ✓ R7 ✓ M23 ✓ M21 (bar fills only) | `design/mcp-router-console.html` | Opus | To Do | — | **Triaged 2026-08-22** — spec at `planning/specs/spec-M22.md`. **Absorbs `R7-C1`.** Neither board exists, `import Charts` returns nothing anywhere, and neither board appears in the campaign's surface registry — genuinely new surfaces with no prior measurement. R7 shipped the engine and a CLI verb: `HarnessesVerb.swift` reads configuration files off disk and prints JSON to stdout and never talks to a running router; `HarnessReconciliation.swift` already models `.notWired`, `.wired(route:)` and `.wiredWithDuplicates(route:count:)`. **There is no `GET /harnesses`** in `RouterServiceDispatch.swift` or anywhere in `src/`. **The two review lanes disagreed on whether the route is needed and the repository settles it:** `no-raw-design-values.sh`'s A36 rule forbids `FileManager`, `Data(contentsOf:)`, `URL(fileURLWithPath:)`, `Bundle`, `Process(` and every socket type under `MCPRouterUI/Boards`, saying *the Mac app talks to the router ONLY over the loopback control API* and *Reading a file is one of the ways past the API* — so the board cannot read a harness config itself and the route is required. `R7-C1` and M22 each name the other as their blocker, so this item takes both halves or neither ships. **The route owes a parity row** against `src/control.ts` with the census at 82 of 83, so the divergence must be declared as intent. Three of the brief's four readings exist in the model and the fourth — routed but still declaring direct upstreams — is new modelling, not a rename. `PRD.md` §8.2's sketch draws *28 MB vs 12.4 GB unrouted* and *Savings: 99.7% RAM*, which `DESIGN.md` §6 forbids; the PRD defers to M22 and the brief refuses it, so the sketch is superseded rather than a contradiction — recorded because a planner reading §8.2 alone would build the forbidden thing. Eleven assumptions, no essential question. Out-of-family review AMEND — accepted that the brief's own duty-cycle caption asserts a figure for a world the router never ran, and that resident memory is measured router-side but crosses no wire the app can read |
| M24 | The storefront's own artwork — banners and app-style icons | mac | — | — | Opus | **Done** (ai/m24 → main; design-only, 23 files, all under `design/`) | `ai/m24` | Recorded in LEDGER.md. |
| M25 | The controls row, not the columns, set the boards' width | mac | — | — | Opus | **Done** (ai/x4 broke the min-width chain, ai/x5 flexed the two controls rows) | — | Recorded in LEDGER.md; see `M25-board-columns-do-not-flex.md`. |
| M26 | The Checks board and the design's eval board are two surfaces | mac | — | — | Opus | **Done** (ai/m26 → main; owner kept the reachability board, mock amended, DEF-031 closed) | `ai/m26` | Recorded in LEDGER.md; see `M26-checks-board-framing.md`. |
| M28 | Five findings that need a decision rather than a runner | mac | — | — | Opus | **Done** — all five dispositioned 2026-08-22 | — | **A decision docket, not work.** Closes by the owner answering five questions (DEF-042, DEF-049, DEF-008, DEF-057, DEF-033). A fleet reading only the table will dispatch it; it must not be given a slot. **Re-measured 2026-08-22 and four of the five no longer need an answer.** **DEF-042 is resolved, by a third route the docket did not consider**: the console mock — settled as the design of record that day — **re-sourced** the numbers rather than deleting or shelving them. `install velocity` is gone outright (`grep -ioc` 0 against the prototype's 2), `eval` 29→2 and `trend` 7→2, and every survivor is observable: both `trend` hits are one section headed *Why there is no "trending" band*, both `eval` hits are about a browser engine, `Last run` and `Runs` at `:3470-3474` are the **session analyst's own** cadence, and the Skills `Runs` column at `:2576` says where it comes from at `:2772` — the analyst grepping sessions, a PRD feature the owner asked for by name. What remains is per-surface work under M17/M20 plus `campaign.json`'s stale `designOfRecord`. **DEF-049 is answered in the code, with its reason**: the `try?` at `ServicePorts.swift:341` is now a `do`/`catch` at `:388-394` returning a `cacheFailure` that reaches `ControlPorts.swift:95` and drives `cached` at `:108`, and the doc comment records the docket's own smaller option taken, citing `ControlApproveDispatchTests.swift:114-118`. **Its "unverified lead" is refuted**: approve is reachable only with `pending` present and both implementations clear `error` when they stage one (`src/manifest.ts:246`, `ManifestBookkeeping.swift:83`), so `Describe.swift:208`'s guard fails before `:218` is reached. The plainer defect that survives is **R21**. **DEF-008 closed by the orchestrator** — the losing option is better at nothing here, so it was taken rather than asked. **DEF-033 unchanged**, open on purpose. **Only DEF-057 is left**, and it has a third option now: `plugins/test-campaign` alone is **8.9 MB** against the submodule's **546 MB**, and populating that submodule in a worktree was measured this morning to break every runner dispatched into it. **Closed 2026-08-22.** DEF-057 answered by the owner — vendor `test-campaign` only — and filed as **G5**. Four of five never reached the owner: two had been answered by work that landed after the docket was written, one was the orchestrator's to take, and DEF-033 needs nothing. The two that became work are **R21** and **G5**. |
| M29 | "Disable a server" is drawn with nothing behind it | mac + router | R16 · R18 | `design/mcp-router-console.html` | — | **Untriaged** | — | Filed 2026-08-22 by M18's runner. A gate-table row with no action behind it and no owner. A decision before a build — see the LEDGER row for the three questions it has to answer, all of which touch items currently in flight. |
| M30 | Where a capability document actually comes from | mac + router | M19 | — | — | **Untriaged** | — | Filed 2026-08-23 by M19's runner as M19's real exposure. Allocated `M29` and renumbered on the orchestrator's collision. **The renumber avoided a trap worth carrying**: four other `M29`s in this tree are **mutation ids in red-green tables** — same spelling, different namespace — and a tree-wide `sed` would have corrupted one with **nothing going red**, because those tables are prose to every gate. See the LEDGER row. |
| M31 | The design of record cannot draw a disabled primary | design | — | `design/mcp-router-console.html` | — | **Untriaged** | — | Raised by `lukerhodes-2f` from M18's gap-fix, verified independently. `.btn:disabled` and `.btn.primary` are both specificity 0-2-0 with `.primary` second, so a disabled primary keeps its accent fill and label and differs from a live one only by losing its shadow — **drawn as though enabled**, which is the failure `DESIGN.md` names. **Inverts the instrument too**: `mock-fidelity` compares a build to the mock, so a build that correctly dims would be reported as a divergence. Reaches M18, M19 and M22; none owns it. |
| M32 | A mock-driven gate is blind to what the mock does not draw | harness + design | — | — | — | **Untriaged** | — | Filed 2026-08-23 from M22 driving the shipped app. `mock-fidelity` has no opinion on what the build adds beyond the mock, and **no opinion reads exactly like agreement** — so *clean over N nodes* means *nothing the mock draws diverges*, not *the surface is right*. An `extra` needs an oracle rather than only a citation. See the LEDGER row. |
| M33 | `swift build` exits 0 and silent where `xcodebuild` is fatal | harness | — | — | — | **Untriaged** | — | M20 verifier F5. `Package.swift` has no target at `MCPRouter/`; `project.yml` does. **The mechanism behind M18's recurrence**, and the widest-blast-radius entry in the instrument-that-cannot-fail register. |
| M34 | The menu badge is unmeasurable by any lane we have | evidence | — | — | — | **Untriaged** | — | M20 verifier F4, rescued from a verdict with no destination. Four lanes closed and measured; a grep for `badge` in the acceptance lane returns nine hits and none is this. |
| R4-C1 | The installer points at Swift; the TypeScript tree stays | router | — | — | Opus | **Done** (ai/r4c) | — | Recorded in LEDGER.md; see `R4-C1-installer-points-at-swift.md`. |
| R4-C2 | Retire `src/*.ts` — held, and what it waits on | router | — | — | Opus | Held (owner: not on a green streak) | — | Held by owner decision: the TypeScript reference stays until several consecutive whole-gates pass, including a cold port-reuse path. Not a green-streak call. |
| R9 | The SDK drops an upstream's message on -32603; the router reads it off the wire | router | — | — | Opus | **Done** (ai/r9 → main; DEF-047 closed, 7 tests armed 5-of-7 red, parity 82/83 0 diverged) | `ai/r9` | Recorded in LEDGER.md; see `R9-sdk-drops-upstream-message.md`. |
| X2 | The iOS on-glass instrument, and the six cases it takes off `n/a` | harness | — | — | Opus | **Done** (ai/x2 → main; lane-owned device, six green runs) | `ai/x2` | Recorded in LEDGER.md; see `X2-ios-on-glass.md`. |
| X3 | The iOS unit lane read an empty accessibility tree because the engine was off | harness | — | — | Opus | Done (DEF-029 closed, armed three ways) | — | Recorded in LEDGER.md; see `X3-ios-unit-lane-empty-tree.md`. |
| X6 | Cleanup's `Read first…`, the half DEF-011 was held open for | harness | — | — | Opus | **Done** (ai/x6 → main; CASE-0135/0136/0137, nine mutation arms) | `ai/x6` | Recorded in LEDGER.md. |
| X7 | The campaign's published artifacts under-report what it knows | harness | — | — | Opus | Untriaged (**upstream**: fledgeling-plugins, not this repo) | — | **Cannot be closed from this repository.** test-campaign 0.9.2 lives in the plugin cache; the vendored submodule carries 0.5.0 and does not contain the scripts (DEF-057). Closing it means a change pushed to fledgeling-plugins and a submodule bump. |
| X8 | Two campaign detectors report findings they cannot support | harness | — | — | Opus | Untriaged (**upstream**: fledgeling-plugins, not this repo) | — | **Cannot be closed from this repository** — same reason as X7. |

| R6 | Children inherit launchd's minimal PATH | router | R2 ✓ | — | Opus | **Merged** `1d958b4` | `ai/r6` `7a4f15a` | **Verified 2026-08-21 at `effect-witness`**, the highest rung any item in this fleet has reached. The verifier read the `PATH=` string out of a real child process's environment, recorded by a Python stub MCP server that is not product code, and watched it change under mutation and return on restore. 12 gates; two mutations red-green (`augmentedEnvironment` returning its input → `examined=6 failures=5`; `commandNotFound.message` reworded → `cli: 16 verbs agreed, 1 did not`). codex/gpt-5.6-sol returned *request changes* with 7 findings — two reproduced at outcome rung and taken, three overruled on severity with the reason recorded. **Nine follow-ups registered `D-r6-d`…`D-r6-l`; none blocks the merge.** Four bundle claims refuted, including spec §7's A7 and spec §9's load-bearing sentence. |
| R7 | The router's thesis is unmet for every harness but Claude Code | router | R3 ✓ | — | Opus | **Merged** `4429e36` | `ai/r7` `51735c6` | **Verified 2026-08-21 at `effect-witness`; verdict Done.** No blocking findings. **B1 closed and cross-checked against the harness's own tool**: path `~/.gemini/config/mcp_config.json`, `wired-with-duplicates`, route `http`, 19 entries, 12 duplicates, `unparsed: []` — the verifier computed the 12 independently (11 name matches plus `Ref` to `ref-tools-mcp` by identity) and confirmed 19 plus the router entry equals `agy mcp list`'s 20 rows. Both real Gemini configs byte-identical across the run on SHA-256, inode, mode, size, mtime **and** ctime — stronger than the lane's content-only digest that `D-r7-v` flags. **B2**: all five previous walk-throughs now exit 1, re-planted from scratch in the verifier's own baseline rather than the selftest's, and the seam censused by hand at 313 files and 8 seam files with no write symbol in any. **B3 and B4 closed in both directions**, with a seven-shape sweep for a remaining silent zero finding none — including duplicated JSON keys, where R7 agrees with both node and `agy` that the last wins. Gates each captured from their own `$?` and never through `tail`: swiftformat 0/509, swiftlint 0 in 502 files, `swift test` 1648 tests in 202 suites twice, parity 358/358, write gate, selftest 27 cases, acceptance lane 59 ok lines. Two mutation arms discriminate and were restored. **Three things the verifier established that the runner had asserted.** The stripper was checked **by construction** over seven string-literal shapes in both orders: four hold and **three miss** — a `/*` inside a `"""` body, inside a raw string with an odd inner quote, and after a raw-string trailing backslash — each blanking a real applier below it, and the gate's own comment claims the multiline case is the safe direction when it is the opposite. **Latent, not live**: instrumented over all 313 real sources, the stripper opens exactly one block comment in the whole tree, at `Describe.swift:193`, and that one is genuine (`D-r7-z`). The closure check fires but **does not discriminate** — narrowing a vocabulary alternative keeps it green while a real applier walks through at exit 0 (`D-r7-ac`). And `make lint`'s three-pass block is genuine but a **false dependency**: satisfying the guard with an empty `node_modules/` and an empty `dist/index.js` turns all six steps green, which proves no step reads either path (`D-r7-af`). **The `url` overrule is now a measurement rather than an argument** — driving `agy` against a scratch HOME lists a `url`-only entry as http, so the key really is accepted. The two-slash overrule is correct as recorded, though `JSURL` does diverge from `new URL()` for special schemes other than `file` (`D-r7-ag`), with no wrong answer resulting because Go's `net/url` gives those spellings no host either. `D-r7-y`'s deferral reason holds. **One process claim of the orchestrator's corrected: grok is packet-size limited, not down** — 1,051 bytes at exit 0 for a 1,174-byte prompt after returning nothing at 16.5 KB and 64 KB. Follow-ups `D-r7-z`...`D-r7-ai`. **Prior-pass detail folded in at merge (the branch carried a second R7 row):** **Delivered 2026-08-21, ready to verify (gap-fix 2; `ai/r7` `d285298`, base `fd8ae22`, 13 files, +1870/-125).** **B1 closed against the real machine**: the run now reads `~/.gemini/config/mcp_config.json` and reports `wired-with-duplicates`, route `http`, 19 entries, 12 duplicates, `unparsed: []` — 19 plus the router entry is `agy mcp list`'s twenty rows, so the tool and the harness now agree. Both real Gemini configs byte-identical before and after every run. **The panel caught two defects in the fix itself, both taken** — the fifth time this session. `HarnessDialect.resolve` rewrote any non-standard endpoint key to `url` without asking what the entry was, and `ServerParser` reads a truthy `url` as the transport when `type` is absent, so a stdio entry carrying a stale `serverUrl` was digested as an HTTP upstream — losing its own stdio duplicate and inviting a false one against the stale address; the comparison now asks the route rule through the same predicate that already knew. And endpoints were compared byte-for-byte, so `/mcp` and `/mcp/` — one endpoint by the route rule's own reckoning — read as a conflict and went to `unparsed`, which is **B4's silent loss arriving through formatting**. **The gate's own stripper was the worst finding and it was silent**: `let marker = " /*"` is a Swift string containing a slash-star, so the comment reader opened a block on it and blanked every line to end of file — an applier under one reported clean, and the mirror image was there too. It now tracks string state. The relink group gained its POSIX spellings (`symlink`, `link`, `chmod`, `rename`, `truncate`), which is this pass's own defect in miniature, and a closure check that splits the pattern on alternation and exits 2 for any alternative no subject exercises **failed on its first run**, on `link\(`. **Two panel findings overruled on measurement**: dropping `url` from Gemini's dialect rests on an error string that enumerates nothing (`strings -a ~/.local/bin/agy` returns `json:"httpUrl"`, a key absent from both that string and the help text) and would risk reporting a working config not-wired then offering to wire it, which is F1; and `endpointPath`'s two-slash limit does not diverge from `JSURL`, whose `authority` consumes `while consumed < 2` for the documented `file:///tmp/x` reason while `http:///host/mcp` is refused at the host guard first. Both now carry tests. **Two process findings the runner surfaced rather than buried.** Arm P1 passed on its first run and **the arm was at fault** — its fixture named the harness entry after the upstream, so it matched on name and never reached `resolve`; `D-r7-y` met inside the test written to guard the defect beside it, renamed to `browser` against upstream `fetch` and now red at both levels. And `swiftformat --lint .` piped into `tail -2` with `echo exit=$?` after it reported `exit=0` over a failing run because `$?` was `tail`'s — the same mistake this repo's own gate-log rule names, one command shorter, and it hid a real `wrapFunctionBodies` violation until the gate was re-run unpiped. Gates: `swiftformat` 0/509 (0), `swiftlint --strict` 0 violations in 502 files (0), `swift test` 1648 tests in 202 suites twice (0, 0), parity 358/358 (0), write gate `313 examined, 8 name a harness config, 20 write a file, 8 in the seam — none writes one` (0), selftest **27 cases** (0, was 22), acceptance lane pass at **59 checks** over eleven passes (0, was 55). **`make lint` blocked at 2** on the `tools` guard `node_modules is missing` — the same recorded block as passes 1 and 2, with all six steps run individually and green. Five mutation arms red and restored; the pre-panel gate fails **4 of 27** against the new selftest, each with the reviewer's exact failure, while P20b passes both ways as the control direction it is. **grok is down as a lane on this item** — 0 bytes of output and 0 bytes of log at a 16.5 KB packet, having already failed at 64 KB; reported once and substituted with `claude-fable-5` (5,783 B). `D-r7-y` registered and not taken. **From the branch's own row, kept in the union:** `ServerParser`, `UpstreamHash` and `SelfReference` were left untouched; `make test` was run four times over this pass and run 2 lost `CallbackLifecycleTests.swift:238`, a loopback bind race that is 0 of 8 in isolation and touches nothing in this diff, registered as `D-r7-x`; the six lint steps were run individually and were green. |
| R7-C1 | The Harnesses board and the `GET /harnesses` route behind it | mac | R7, M22 | — | Opus | Deferred | — | R7 ships the engine and a CLI verb only. A control route diverges from `src/control.ts` and owes a parity row; the surface that draws it is M22, untriaged. **Absorbed by M22, 2026-08-22 triage.** This row and M22's each named the other as their blocker, so neither could ever be scheduled. `no-raw-design-values.sh`'s A36 rule forbids the Mac app reading a harness config file itself, so the board genuinely needs the route and the two are one piece of work. M22 takes both halves and still owes the parity row this cell names |
| R7-C2 | Apply a reconciliation plan to a harness config, behind a human | router | R7 | — | Opus | Deferred | — | The write R7 refuses (spec-R7 §7). Needs per-dialect writing, undo and a confirmation surface, and it is what the brief puts out of scope. |
| R7-C3 | opencode's transport is unestablished | router | R7 | — | Opus | Deferred | — | No config on this machine and its launcher is a shim whose bundle was not probed. Displays as `.unknown` rather than guessed. |
| R7-C4 | Project-scoped harness entries | router | R7 | — | Opus | Deferred | — | `~/.claude.json` carries 8 more across 5 projects and Codex has `[projects.*]`. R7 reads the global scope and prints that it did. |
| R16-C1 | Adopt project-scoped upstreams and serve them by caller cwd | router | R16 | — | Opus | Deferred | — | Registered 2026-08-22 at R16's triage. **Blocked on a decision, not on plumbing**: `D-r7-i` and `R7-C4` are the mirror image — R7 reads project scope while printing that it read global — and R16's brief says both should be settled by one decision about what scope this product works in. The information a fix needs is already at call time: `CallerIdentity` carries cwd and `usage` reports per-project call counts. Shape 3 (disambiguated names like `proctor@proctor-mcp`) stays refused — it changes the tool namespace the model sees, so it changes prompts that name a tool. |
| G5-C1 | Repo-owned gate wrappers for the vendored campaign scripts | harness | G5 | — | Opus | Deferred | — | Registered 2026-08-22 at G5's pre-dispatch check. **Nothing in this repository invokes a `test-campaign` script.** Searched `Makefile`, `scripts/` and `planning/test-campaign/bin/` for `campaign.py`, `strict-check`, `capture-lineage`, `vacuity-check`, `attach-shots` and `witness-worklist`: every hit is a **comment naming a script**, and `plugins/cache` and `fledgeling-plugins` appear nowhere outside `.claude/`. The campaign is run by an agent invoking the skill, and the skill resolves its own `scripts/` from wherever it was loaded — the machine's plugin cache — so vendoring a copy changes nothing about what runs. Giving the repository wrappers `make` could call is **new surface rather than a relocation**, so it is split out rather than smuggled into G5, whose job is to carry the code pinned and prove it runs from here. |
| R8 | An upstream that refuses our credentials must say so | router | R3 ✓ R5 ✓ | — | Opus | **Merged** `2a4e811` | `ai/r8` | **Row restored 2026-08-21.** R8's only ORCHESTRATOR row described a different item — *server soft-delete with a restore endpoint*, a deferred child of R3, now `R12` — so renumbering that collision left the merged item with no row at all, and check G found it. Owner unfroze `src/`; A38 rewritten to guard the reference's existence rather than freeze the tree; Swift half unblocked by R9. Parity 82/83, control 16/16, 0 diverged; auth gate examined=8 failures=0. |
| X4 | Mac boards: six defects the design of record names | mac | — | `design/mocks/prototype.html` | Opus | **Merged** `2ff0941` | `ai/x4` | Row added 2026-08-21 — the branch was merged and recorded in neither file until the thirteen-row reconciliation. Its work is written up under M25. |
| X5 | Discover and Skills: the controls row set the board's width | mac | X4 ✓ | `design/mocks/prototype.html` | Opus | **Merged** `dee20da` | `ai/x5` | Row added 2026-08-21, same reason as X4. The driver was a `.fixedSize()` segmented picker (567pt on Discover, 516pt on Skills) beside a search field pinned to one width — **not** the table columns: cutting Discover's `nameColumn` from 216pt to 96pt moved its content width by zero. Written up under M25. |
| G2 | The ledger table holds two row shapes, and every reader silently drops one | harness | — | — | Opus | **Ready for AI** | — | This table declares nine columns and carries 23 four-column rows interleaved through it in seven runs. A four-column row under a nine-column header has no `Status` cell to read, so every reader invents an exclusion — `ledger-reconcile.py` guarded on cell count, a peer's scanner matched ids with a regex rejecting `D-p6-a`; different mechanisms, same 23 rows, neither said so. **Agreement between two independent instruments was measuring the file's shape rather than its content.** `7c2c67a` made the omission visible (the reconciler names the skipped ids and exits 2 on `examined == 0`); this item makes the rows readable. Deferred on 2026-08-21 because the runs are scattered rather than contiguous, so the fix moves rows, and four verify agents plus a runner were mid-read. |
| G3 | `make test` is not deterministically green | harness | — | — | Opus | **Merged** `4e18cc0` | `ai/g3` `7abaff8` | **Merged 2026-08-21 at `4e18cc0`.** **Verified 2026-08-21 at `metamorphic`; verdict Done. No blocking findings.** The verifier built the scanner standalone at **both** `e8c20e0` and HEAD and ran the same fixtures through each: all three shapes flip, each confirmed by its one-token control in both directions, and both further doors are real and closed. 69 controls counted in the tree. Gates on the merged tree: lint 0 over 509 files, parity 358/358, `acceptance-r6` clean, reconciler 0 across A-K with **check K over 185 register rows and no id occurring twice**, assigned mutation exit 2 at 10.936 s naming its own condition, `git diff app/Sources/` empty, and an independent walk finding **exactly 5 call sites, all bounded**, over 508 files. **The count was audited as a count and is wrong about which scanner it measured**: 8/4 over twelve is 2/1 on the **pre-fix** scanner plus 6/3 on the delivered one, so against the delivered artifact the residue is **nine at 6/3**, not twelve at 8/4 — written at four sites and correct only in `D-g3-ah`'s own row. **And the population is a convenience sample of found defects**: the verifier took it from nine shapes to eighteen in one session, 13 misses to 5 reds, so *the ratio tracks how long the last person looked, not a property of the layer.* The conclusion it supports — fails both ways, direction not predictable — is unaffected and conservative. **Nine new shapes, none in the 69 controls and none in `D-g3-ah`**, with four misses plus one false red sharing one unnamed mechanism: `continuesStatement` recognises only a trailing `.` and a trailing body keyword, so a comma, a boolean operator, `where` or `=` cuts the opener at the line break. **One is caused by this pass's own two fixes interacting** — eliding non-ASCII to close one door makes `wordSpan` return an empty word, which disables the label skip the same pass added, so *taken one level up* holds for `D-g3-ab` and not for `D-g3-aa`. **None blocks, and the reason is the standard rather than leniency**: the artifact declares Family C open and gives directions for what it left, and *blocking on a bound the brief invited the runner to state honestly would make honesty the losing move.* `D-g3-q` now defers on scope alone. **On the title: the item cannot close on its title and should close anyway on its delivered scope.** `make test` was 1 red in 5 runs and that red was `listen EADDRINUSE` — a port-reuse collision under load, **not a fixed sleep** — while another `D-g3-s` instance compares two timestamps rounding to the same second. Sweeping `D-g3-c`, which names *sixty-odd fixed sleeps*, would leave both: the residue is **at least three mechanisms** and needs its own item (`D-g3-ao`). Follow-ups `D-g3-ai`...`D-g3-ao`, which live on the branch and arrive with the merge. **Merged 2026-08-21.** Prior-pass detail follows: **Gap-fix 3 delivered 2026-08-21, ready to verify (`ai/g3` `94ddd73`, 4 commits on `e8c20e0`).** The property is unchanged and every gate held: a regression in this class produces a named red inside the CI bound. This pass fixed the layer the rebuild deliberately did not replace — Swift's statement and trailing-closure grammar — and **corrected what the previous pass claimed about which way that layer fails**, which is the load-bearing half. **Three shapes, each pinned by a one-token control.** `check: if awaitEvent(x) {` read an unbounded call as BOUND and deleting the label read the identical source as UNBOUND, because `firstWord` returned `check` and the `bodyKeywords` guard never fired; it now steps past a prefix that introduces a statement without being one, which closed a `case`/`default` clause with it. `await p.awaitReap(name: "own")` produced **no call site at all**, delexing to the shape of an unapplied method reference; the cause was one level up — a comment is nothing and a literal is a **value**, and blanking both to whitespace made a value indistinguishable from absence — so literal bytes and non-ASCII code bytes now become `ScanByte.elided`, closing the same miss's other door. `try await awaitEvent("reap at \(Task.currentPriority)")` read UNBOUND where `Clock` in the same line read BOUND, because the escape test ran on the opener rather than on the callee receiving the closure; it now reads the owner of the brace. **The directional claim is corrected where it was made.** `G3-gapfix-2.md` said the residue "fails toward a red on correct source rather than toward a miss". That was true of the three unreachable shapes it named and false as a statement about the layer, and a claim about which way a residue fails is what decides whether the residue is tolerable. Measured this pass: **two misses and one false fire** in the three blocking shapes, and of the nine further shapes the lanes broke it with and this pass did not take (`D-g3-ah`), **six fail toward a miss and three toward a red**. The corrected claim is that the layer fails both ways and the direction is not predictable from it — recorded in the brief, in the suite's doc comment, in the register, in the LEDGER and here. **Stated as a count: of the twelve shapes measured against the delivered scanner, eight fail toward a miss and four toward a red.** **Asking two lanes to break it rather than review it found eight more, two of them regressions this pass had just introduced**: reading the escape from the brace's owner fixed the interpolation false fire and broke `_Concurrency.Task { }` and `Task.detached(operation: { })`, which the old whole-opener word search had covered. The owner is now every component of the chain, read from both positions a brace can hold, which also catches `keep(Task { })` that neither lane named. Three more taken: `awaitEvent(.init("x")) { }` no longer reads as a declaration; a receiver's dot at the end of a line is a statement continuation; and the qualification test reads past whitespace, because `collapsed` turns that line break into a space. **The population is stated rather than closed** (`D-g3-ae`). Family A (lexical grammar) is 19 controls on a citable production list and Family B (block structure) is 12 on brace nesting; **Family C is 38 and its population is open** — `verdict`, `statement`, `firstWord`, `continuesStatement` and five keyword lists implement no grammar, and every defect of this round was in it. `AwaitBoundControl` now gives the count and the population family by family, and states the mutation matrix separately, because *every mechanism in the code as written is load-bearing* is a different claim from *the grammar the code should implement is covered*. **69 controls, each seen to fail under at least one of twelve single-mechanism mutations.** `AwaitBoundScan` split into three files at the family seam, the scan file having passed SwiftLint's 400-line `file_length` default. **`D-g3-q`'s derivation withdrawn** (B1): gap-fix 2 saw `PoolTests.swift:144` green 4 of 4 at 0% idle and derived a load-dependence; the verifier ran the same mutation at 15.5% idle falling to 0.6% under 1-minute load 127 — *heavier* contention — and got both sites red 4 of 4, which refutes the explanation on its own terms. The row reverts to the previous verifier's reading and defers **on scope alone**, which was available the whole time and needs no contested number. **Five duplicated register ids removed** (`D-g3-ad`): `D-g3-g`…`D-g3-k` each appeared twice from this item's own merge `e4cb050`, three carrying different rows; the richer copy is kept and `main`'s `D-p1-a`/`D-p1-e` merges are taken verbatim rather than re-split. The reconciler was taken from `main`, since the branch's copy predated **check K**. Gates, each to a full log: `make test` **0** and **0** at `1587 tests in 199 suites` (7.126 s, 12.513 s); `make lint` **0**, `0 violations, 0 serious in 500 files`; `make parity` **0** at `358 vector cases compared (floor 358)`; `make acceptance-r6` **0** at `examined=6 failures=0`; **`python3 planning/ledger-reconcile.py` 0**, `reconciled — no findings across A, B, B-range, C, D, E, F, G, H, I, J, K`, with **check K** examining 172 register rows. The assigned mutation reds at **exit 2**, `failed after 13.189 seconds with 1 issue` at `PoolReapingTests.swift:98:29` naming *timed out after 10.0s waiting for: `own` to be reaped under the arming it just made* — inside the 150 s bound. `UpstreamPoolReaping.swift` was restored from a `cp` backup and `git diff app/Sources/` is empty, and the scan itself finds **exactly 5 call sites, all bounded, over 499 files**. **Two `make test` runs of four went red, and neither is this pass's work**: `CallbackLifecycleTests.swift:238` (*the callback listener was cancelled before it bound*) and `ControlStreamTests.swift:72` (`arrival < lastSent` compared at second granularity). Both are in files this item does not touch and both are `D-g3-c`'s class, recorded under `D-g3-s` — the fourth and fifth measured instances. The two green runs are the two the gate asks for, and saying so without saying the other two happened would be the shape this item was filed about. **`make test` is still not deterministically green on this machine, which is this item's own title** — what G3 fixed is the pool suite, and the residue is `D-g3-c`'s ~60 unclassified sleeps elsewhere. New defects registered: `D-g3-aa`…`D-g3-ac` (the three shapes, closed), `D-g3-ad` (the duplicate ids, closed), `D-g3-ae` (the population, closed by stating the split), `D-g3-af` (the assigned mutation as briefed does not compile — it needs a local capture before the `Task`, hit and worked around silently by every pass), `D-g3-ag` (two cited length limits no config states — measured as SwiftLint's own `file_length` and `type_body_length` defaults) and `D-g3-ah` (the nine untaken shapes with their directions). Machine: 1-minute load average **421**, idle **0.0%** throughout, two sibling runners live. **The timings above are not representative and are reported rather than compared** — the assigned mutation's 13.189 s sits against 10.589 s on the runner's machine and 10.836 s on the verifier's at load 127. **Gap-fix 2's record follows, with its two corrected claims marked.**  The property was already established by the verifier's own re-run and is unchanged: **a regression in this class produces a named red inside the CI bound, not a timeout.** This pass fixed the guard built around it, which a verifier defeated five ways in both directions with 22 planted call sites. **The scanner was rebuilt rather than patched**, because all seven defects found by the panel and the verifier are instances of two approximations standing in for Swift's grammar: comments recognised by a line's first three characters with a truncation at the first `//`, and block structure read from indentation. Both are gone — a `Delexer` implementing Swift's comment and literal grammar (line, block, **nested** block, single-line, multi-line, raw at any hash count, escapes, interpolation, and a literal nested inside an interpolation) blanks every byte in place so length and line breaks are preserved, and `AwaitBoundScan` then walks **brace balance** outward, reading the statement each enclosing `{` terminates. Indentation is consulted nowhere. Three named residues close as side effects: a newline between the name and its paren, `awaitEvent (` with a space, and a brace inside a literal. ~~**The completeness claim is bounded and evidenced**: the population is the two grammars rather than the open set of shapes~~ — **corrected in gap-fix 3 under `D-g3-ae`: that was true of two families of three, and Family C's population is open.** Held then by **53 controls** asserting both directions, every one seen to fail — **34 single-mechanism mutations, 34 of 34 red, all 53 controls red under at least one**. `M11` reinstates the deleted same-line shortcut and reds exactly the three `D-g3-l` shapes. Three controls were rewritten because the matrix showed they did not discriminate as drafted. `D-g3-l`, `D-g3-m`, `D-g3-n`, `D-g3-o`, `D-g3-p`, `D-g3-r` and `D-g3-v` all closed. ~~**`D-g3-q` re-measured and it is wider than recorded** — gutting both accessors reds only `PoolReapingTests.swift:101`, 4 of 4 at 0% idle, where the verifier also saw `PoolTests.swift:144`; that site's power is load-dependent.~~ **Withdrawn in gap-fix 3: it does not reproduce, and the verifier got both sites red 4 of 4 under heavier load.** Deferred on scope; the probe below stands: a probe reports `PROBE-EARLY-RETURN` 3 of 3 and `PROBE-AWAITS-WATCHER` 0, so at every `awaitSessionEnded` site the accessor awaits nothing whatever the caller does, which is `D-g3-g`'s mechanism and `D-g3-g`'s remedy. **Acceptance criterion 3 deleted with its reason** (`D-g3-r`, the orchestrator's error): the observable separating the two sides of the await is the duration, and the assigned mutation already carries it, so no independent discriminating version exists. New defects registered from this pass: `D-g3-w` (a suite's own doc comment prints on every failure of that suite, after the actionable line) `D-g3-x` (a scan whose delexer is wrong is quadratic), `D-g3-y` (**nine more defects the two out-of-family lanes found in the rebuilt scanner, all fixed here** — an opener span crossing statements, a trailing closure belonging to an inner call, both markers matching mid-identifier, `#\"\"\"\"#` read as a multi-line opener that never closes and silently blanking a real file, a control-flow body reading as a wrap, a CRLF desync that keeps `endedCleanly` true, `init`/`deinit`/`subscript` walked through, a non-trailing closure argument read as a red, a tab hiding a call, and an unapplied method reference read as one) and `D-g3-z` (a compile-time witness would make an unbounded call unwritable; blocked on `@testable import` making any `internal` initialiser forgeable, not on source location, which a lane corrected). Gates, each to a full log: `make test` **0** and **0** at `1587 tests in 199 suites` (4.941s, 4.130s); `make lint` **0**, `0 violations, 0 serious in 497 files`; `make parity` **0** at `358 vector cases compared (floor 358)`; `make acceptance-r6` **0** at `examined=6 failures=0`. The assigned mutation reds at **exit 2**, `failed after 10.589 seconds with 1 issue` at `PoolReapingTests.swift:98:29` naming *timed out after 10.0s waiting for: `own` to be reaped under the arming it just made*. One red on an earlier gate run is recorded rather than re-rolled away: `CallbackLifecycleTests.swift:238` went red once in six runs, in a file this pass does not touch — the third measured instance of `D-g3-c`'s class, under `D-g3-s`. Machine idle **0.0%** to **44.6%** across the session, two sibling runners live. `main` was merged into `ai/g3` at the start of this pass so the `D-g3-l`…`D-g3-v` rows could be corrected where they live; the `ORCHESTRATOR.md` and `LEDGER.md` conflicts were resolved to `main`'s side and then rewritten here. Prior passes: the blocking finding — `awaitReap` and `awaitSessionEnded` awaiting an unstructured `Task`, so the effective bound was the pool's own 600,000 ms arming — is closed by calling both through `awaitEvent` under `waitUntil`'s ten-second breaker; the `release()`/`armedReap()` race is structurally closed and would not reopen in 80,797 rounds at a 1 ms window under 48 spinners; 11 of 14 fixed sleeps removed. Original finding: found independently by the R6 and M23 verifiers on the same night, in different worktrees — `PoolReapingTests.swift:61` slept 150ms expecting a 25ms idle reap, passing in isolation four times and failing under whole-suite load. **A gate that is green on the second run is not a gate.** The session's unattributed load-548 red stays unattributed; nothing here touched it. `D-g3-a`…`D-g3-f`, `D-g3-g`, `D-g3-h`, `D-g3-i`, `D-g3-k`, `D-g3-q`, `D-g3-s`, `D-g3-t`, `D-g3-u`, `D-g3-w` and `D-g3-x` stay open. **From `main`'s row, folded in at the merge.** **Criterion 2 was argued rather than assumed**: copying `isCall`'s comment treatment into `isBounded` closes **three of six**, cannot close `D-g3-m` *because that defect is in the donor*, and closes none of the three false fires — so the shared cause is one level up, two hand-rolled models of one grammar, both wrong. The same-line test was deleted rather than repaired. **What is still approximated is stated plainly**: Swift's statement and trailing-closure grammar — where every reviewer defect actually lived — plus regex literals, `#if` branches read as if all compile, and lexical containment standing in for an execution bound. **Asking the lanes to break it rather than review it found twelve more defects across three rounds, all fixed** (this row's `D-g3-y` summary above says nine; both counts are carried across the merge unreconciled). **One defect no lane named**: the readability guard, added because a lane pointed at regex literals, immediately reported a real file — a raw literal holding two quotes at `PrimitiveBodyTests.swift:140` was being read as a multi-line opener that never closes, silently blanking the rest of the file. All mutated files were restored from `cp` backups and the restoration diffed before the gates ran; `git diff app/Sources/` empty across the pass. `D-g3-b` cites `:116`; `D-g3-j` now states three of four corrected and names the one that was not; `D-g3-o` closed; `D-g3-v` reworded. **Lanes: codex down to 27 Aug (header verified first), and grok down four ways** — output about an unrelated repo at 5.6 KB, `cursor-agent` fallback out of usage, and two runs at a **3.7 KB** packet emitting only narration before the 900 s alarm, which is worse than the packet-size limit `D-r7-ai` recorded. Gemini delivered twice and fable, substituting for codex, ported the code into a harness and **ran** each break. |
| G4 | Assertions that do not read the quantity they are named for | harness | — | — | Opus | **Merged** `de1315d` | — | Filed 2026-08-21 from a cross-session exchange with `egress`. **Three instances already found here and each treated as unrelated:** check H named for rows read parseable-rows; G2's first acceptance test named for readability read in-scope-ness; R7's `no-harness-config-writes.sh` named for any write under `app/Sources` reads writes on the same physical line. Its pass and its cannot-discriminate are indistinguishable, so the green carries no information about the thing in the name. All four instances were found by someone attacking something adjacent — none by review. Detection is cheap (perturb the named quantity, require red); whether the name→quantity mapping is mechanisable is the open question, and a mis-targeted perturbation that stays green is a false finding of the kind `detector-defects` refuses. Triage should also decide whether this is the policy half of `G1`. See `G4-assertions-that-do-not-read-their-own-quantity.md` **Triaged 2026-08-22 — Ready for AI, Standard, harness-only.** The open question was whether name→quantity is mechanisable; the Google lane (`agy`, `gemini-3.7-flash-high`) answered **no** — *heuristic or NLP mapping from test identifiers to arbitrary in-scope constants yields ambiguous bindings and false positives on auxiliary constants* — so **option B is refused on this repo's own detector-defects doctrine**, A starts at zero coverage and C holds no line. **The substitute needs no quantity at all**: raw-input accounting as a structural invariant (every reader returns `(matched, dropped)`, `dropped` empty unless a skip is declared) plus a null-run gate (an assertion passing on an empty, inverted or poisoned fixture is *provably* vacuous — a property of the assertion, not an inference about its name). Reaches instances 1, 4, 5, 6, every silent-drop and partial-match case, with no false-finding class. **Instances 2, 3, 7 and the `egress` one read a real quantity that is the wrong one and survive both mechanisms** — half this brief's own table is out of scope for its own fix, and the item must not report as closing the class. Separate from `G1`: G1 owns assertions that are too weak, this owns readers that cannot account for their input. **Verified 2026-08-22 (1st); verdict Needs More Work — gap-fix queued (`G4-gapfix.md`), figures only, no gate logic.** Four of five claims hold, each re-derived rather than read. **The load-bearing one stands**: `make all` is red at `parity-selftest` and **red identically at the base** — `git archive 72958de` plus this worktree's `node_modules` and `dist` gives `31 behaved, 5 did not`, exit 1, `diff`ing empty against the HEAD run bar one case killed at exit 143 under load 945 which behaved on re-run. Both gates print their boundary on every run, confirmed by running them. `no-wire-codable.sh` behaves as blamed. Both arms recorded as fixture defects read that way from outside. The verifier armed both gates itself **in a clone**, and both bit. **The block is one number and it is this item's own shape: the census's before column counts the instrument into its own denominator.** With the gate placed outside `planning/` and `scripts/`, the base reads **15 readers / 22 iterations / 34 drop sites**, not 19/27/48 — and copying `reader-accounting.py` into that base tree reproduces the reported column exactly, which proves the mechanism rather than suggesting it. `table_ids` had **one** base drop site, not three. *Nineteen readers in this repository* is `5a9569c`'s subject line and §1's headline. **The after column had already caught it** — `unresolved 67` is the measured 55 plus the 12 the three new files contribute — so the accounting was sound and the baseline was not. Filed as G4's **eleventh instance**, and the only one on its own reachable side. Also settled here: **1686/210 was never `main`'s** — `ai/r17` carries `IndexFailureRecordTests.swift`, one suite of exactly two `@Test`s, and `git diff --name-only HEAD main` holds zero `.swift` files. **Gap-fix 2 delivered 2026-08-22 at `8539f5e` and in verification, and this runner committed** — the first of three on this item to end its turn with a commit rather than a promise, after the brief said so in as many words and the orchestrator ran `make all` for it. **§6 is measured output with its elisions marked and counted**: `1 + 22 + 6 + 7 = 36 = 31 behaved + 5 not`, which is an arithmetic proof that the paste is complete rather than merely long — this item's own discipline applied to itself. The five `WRONG REASON` cases are verbatim, so the stale 82/83 and 84/83 fixture counts are visible against the tree's 91/92 rather than described. **§7's `D-g4-b` is repointed onto the verdict rather than the number**, with the three pastes diffed to show every other figure identical. **The sweep loads `main:planning/claim-sweep.py`'s `normalise` rather than copying it**, and uses `\s+` between words so no pattern matches its own text after collapse — which buys the fixed point that R17's exclusion-list approach cannot buy here, because the corrected figures live inside the scanned file. Re-run byte-identical, diffed twice. **Flagged and correctly untouched**: `planning/progress/G4.md:151` cites §6 for a finding §6 now records as not reproducing — filed as this item's **eighteenth instance**, and notable because §6 was *corrected*, so diligence is what broke the citation. **Gap-fix 2 verified Done 2026-08-22 and merged at `de1315d`.** Oracle rung **differential measurement with an armed control** — the verifier armed its own sweep against a synthetic residue before trusting its clean sheet, and **every figure came from a command it ran** rather than from the runner's account. §6's arithmetic holds (`1 + 22 + 6 + 7 = 36` case lines; `31 behaved + 5 did not = 36`), every non-elided line appears verbatim in its own run, and the two absent are make's echo and make's error because it invoked the script directly. **`D-g4-b`'s thesis proved itself a fourth time while being checked**: the aligned diff of the two pastes differs in exactly one line, `merged ai/*` 29 → 27, and the verifier's own run read **28** — a count that has moved 29, 27, 27, 28 with **no tracker file edited**. `ai/g5` has since added a third commit past the merge point, so *committed twice* is already stale, and chasing it is the row's own point. **The sweep loads `claim-sweep.py` from `main` rather than copying it** — absent from this HEAD, present there, `exec`'d — and its accounting closes: **1118 scanned + 157 skipped = 1275 = `git ls-files`**, so nothing is dropped in silence. Non-blocking imprecision left: §6's diagnostic sentence attributes all five selftest failures to the stale count, and `div-r1-d3` fails a different check — the *expectation* is stale in all five, so the sentence is right about the fixture and loose about the output. |
| G4-B | The two gates G4 shipped, and the doctrine they each broke | harness | G4 ✓ | — | Opus | **Merged** `92a348d` | — | Filed 2026-08-22 when `main`'s `make lint` went red on G4's own merge — the fleet's **fourth merge-only break**, green on its branch and red beside other verified work. Both causes were G4's doctrine violated by G4's gates: a hardcoded `GEOMETRY_DIRS` list that M15 widened out from under the RAW arms, and a filesystem walk that read another session's untracked work-in-progress as a finding. Fixed forward rather than reverted, because both gates are verified, armed and correct about their subject; what was stale is one literal and one enumeration boundary. **Verified Done at `bc41e13`** over five arms, the strongest being a two-way boundary control on the real fixture — 22 files exit 0 untracked, 23 files exit 1 after `git add` alone with no byte changed. See the LEDGER row for the full verification. |
| G5 | Vendor the `test-campaign` version the gates actually run | harness | — | — | Opus | **Needs More Work** — gap-fix 2 | — | Filed 2026-08-22 from **M28/DEF-057, answered by the owner**: vendor `test-campaign` only. Measured — vendored `plugin.json` says `0.5.0`, the cache the gates actually ran says `0.9.2`, and `plugins/test-campaign` is **8.9 MB** against `.claude/plugins/fledgeling-plugins`'s **546 MB**. 0.5.0 has five scripts and none the campaign depends on (`vacuity-check.py`, `capture-lineage.py`, `effect-witness`, `blindVocabulary` all absent), so a fresh clone following the documented `--init --recursive` reproduces none of the campaign's numbers while `LEDGER.md` claims it can. **The docket predates the second cost**: populating the submodule in a worktree breaks every runner sent into it, which cost three launches on 2026-08-22 and is now a dispatch hazard row above — so the vendoring claim describes something this fleet deliberately avoids. Rejected and recorded: bumping the whole submodule keeps 546 MB and the hazard; dropping the claim costs reproducibility outright. Acceptance requires the cache fallback be **disproved** by renaming it away, because a path that silently falls back is this item's own defect class. **X7 and X8 do not close** — vendoring makes them editable here for the first time, and an edit that never reaches upstream is a fork rather than a fix. **Verified 2026-08-22 (1st); verdict Needs More Work — gap-fix queued (`G5-gapfix.md`), documentary only, no change to the vendored tree, pin or gates.** Oracle rung **metamorphic**: the load-bearing claim was flipped by a controlled single-property mutation rather than re-run. **Confirmed and stronger than reported** — `effect-witness` appears **0×** in 0.5.0's `strict-check.py` and 2× in 0.9.2's, `EFFECT_RUNGS` lacks the rung, and relabelling the registry's four armed `effect-witness` cases to `outcome` **in a temp copy** makes 0.5.0 read 62. So the gap is the rung entire, 58 is exactly what `strict-ratchet.json` records, and a fresh clone prints the recorded figure and the word `held.` — **a false confirmation**. The **deny-instead-of-rename** substitution is judged better than what was asked: a deny fails every read of the subtree where a rename only moves the name, and its one scope gap is closed because the clone's submodule is uninitialised and all four scripts import stdlib only. **Gate parity is byte-identical stdout AND stderr**, the pin verified byte-for-byte against what GitHub returns, zero files changed under `planning/test-campaign/` after ~15 gate runs, and carrying the assets whole is what makes the tree-SHA identity possible. **The block: the attribution is inverted for the figure the item turns on.** `G5.md` calls the 58→62 rise *the registry moving, not the instrument*; the 2×2 says every version through **0.9.1 reads 58 on today's registry** while 0.9.2/0.9.3/0.9.4 read 62, and `RUN-2026-08-20.md:589` records 58 of 76 from a sitting headed **0.9.1** with `cases.json` unchanged since — so the entire +4 is the **instrument**. The lineage half stands as the registry (`capture-lineage.py` is byte-identical 0.9.1↔0.9.2). **Consequence the documents do not carry: 0.9.1 reads 58 too**, so the trap is not 0.5.0-only and the vendored pin does **not** reproduce the campaign's recorded strict figure — the recorded one is pre-0.9.2. Vendoring 0.9.2 stays right (0.9.1 plus the campaign's own DEF-048 fix; 8 lines in `strict-check.py`, 80 in `vacuity-check.py`, three scripts byte-identical). **For the owner: 92% of the vendored 8.9 MB is imagery** — `assets/` 8.2 MB against `skills/` 456 KB — and the verifier's judgement, accepted, is that the ratio does not change the call. **Gap-fix delivered 2026-08-22 and in verification, documents only — the vendored tree, the pin and every gate untouched.** The 2×2 is re-derived and stated: **0.9.1 reads 58 of 76 on today's registry, 0.9.2/0.9.3/0.9.4 read 62**, `capture-lineage.py` byte-identical 0.9.1↔0.9.2 judging 16 in both, the four `effect-witness` cases CASE-0145-0148 all armed and passing. So the strict rise is the **instrument** and the lineage rise is the **registry**, both halves of the strict case are necessary, and **0.9.1 reads 58 too** — the trap is not the submodule pin's alone and the vendored 0.9.2 does not reproduce the recorded strict figure. Gates green: lint **0 over 535**, reconciler **0 across A–L**, `parity-manifest-check.sh` exit 0 over **92 rows**; two moved denominators each isolated rather than explained away. **The sweep took two failing runs to get honest, and the second is filed as G4's seventeenth instance**: its wrap control was quoted unwrapped inside the document it guarded, so `grep -Fc` found the quotation and the control collapsed silently. All three controls are now proved two ways — `grep -Fc` 0, sweep 1. **Open and not this item's**: `strict-ratchet.json` still holds 58 and should read 62; recorded in all three documents rather than edited, because `planning/test-campaign/` belongs to another session. **Verified 2026-08-22 (2nd); verdict Needs More Work — gap-fix 2 queued (`G5-gapfix-2.md`), documents only, no gate re-run needed.** **Oracle rung metamorphic**: the verifier re-executed **seven versions of the instrument against two registry snapshots**, extracting scripts with `git archive` at each version-bump commit, and moved single properties to see the denominators and controls respond. **The block is closed and independently reproduced**, the controls armed both ways (`grep -Fc` 0 in the file each guards, normalised match 1, and mutating two phrases made them print `FAIL`), and **zero files changed under `planning/test-campaign/`**. **BL-1: `planning/progress/G5-gapfix.md` is deleted from the working tree** — the commit holds it, the rows point at it, and it is not on disk; the swiftformat move-aside that isolated the 284→285 skip count never moved back, so every gate afterwards ran on a tree missing the item's own record. Filed as G4's **twentieth** instance: a measurement technique with a side effect on its subject that nothing checked was undone. **BL-2**: the backtick paragraph's `main` clause is wrong — the parity argument stands on `64e1631` alone and `main` reads **1128**. **BL-3**: the hazard row's *the cache's 0.9.1* reads as present tense about a cache that today holds **0.9.6** and reads 62. Registered not fixed: `D-g5-a` (the sweep's ABSENT half was never repository surface — the withdrawn claims were checked over four hand-listed files, and the verifier's own corpus check over **1366 tracked files** found nothing leaked, *which was luck confirmed afterwards rather than coverage*), `D-g5-b` (the fixed point is **per-file, not general** — W1 is quoted unwrapped at `G5-gapfix.md:84` and a corpus-wide sweep would collapse on it), `D-g5-c` (`strict-ratchet.json` still 58, should be 62). |
| G6 | Evidence kept in `/tmp` is not evidence | harness | — | — | — | **Untriaged** | — | Filed 2026-08-23. A sweep proving a guard is armed lived in `/tmp` and did not survive the crash, while R17's equivalent is committed at `planning/claim-sweep.py` and did. An accepted verdict and a live verifier both rest on files that are gone. See the LEDGER row. |
| G7 | A citation that does not resolve where it is read | harness | — | — | — | **Untriaged** | — | Split out of `G6` 2026-08-23 on `G6`'s own coupling test: neither fix displaces or helps the other, so they are orthogonal rather than nested. See the LEDGER row. |
| G8 | A question answered at the wrong scope returns a clean answer | harness | — | — | — | **Untriaged** | — | Filed 2026-08-23 beside `G7`. Three occurrences in one evening, plus a fourth by a line-anchored grep. **M16's reduction is the positive form and belongs in `mock_fidelity.py`'s header**, where it retires the three-way merge hazard rather than answering it once. |
| G9 | Two gates `cd` into a worktree that no longer exists | harness | — | — | — | **Untriaged** | — | `.worktrees/R2` is gone; both scripts exit 90 forever, and `spec-R2.md` cites one as runnable. Mitigated by `\|\| exit 90` — not destructive, but a spec asserting an instrument that cannot run. |
| G10 | `make acceptance` dies at its first lane | harness | — | — | — | **Untriaged** | — | `shells.sh` is red on `main` and inherited, so **every lane enrolled into `acceptance` is inert** — enrolment has stopped being a way to make a lane run while still reading like one. Found in a `Done` residual sweep. |
| M23 | The mock-to-SwiftUI conversion contract | mac | — | `design/mcp-router-console.html` | Opus | **Merged** `6d54ce2` | `ai/m23` `3e0b6b8` | **Merged 2026-08-21 at `6d54ce2`.** **Verified 2026-08-21 at `effect-witness`; verdict DONE.** No blocking findings, after eight bounces. Every load-bearing assertion is a live-process measurement rather than a reading: two full suite runs under the verifier's own `sitecustomize.py`, a `sys.settrace` line-trace of both emission sites with caller chains off live frames, a real `python3 -` process whose `argv[0]` and `ps` line were read directly, gate A driven end to end against the real MEASURE build, and `make test` run three times with the failing suite isolated three times. **The trace was rebuilt from `git archive` at `9bb2a2e` and every figure reproduces exactly**: 145 processes, 52 engine runs, 10 with `--report`, 8 emissions at 5 and 3, R1 at zero. **And `53` turns out to be recoverable** — it is the count of processes whose command line *mentions* the engine: the 52 runs plus case 46's heredoc reader. The row says *not recoverable* and then names case 46 as the one thing that would produce it, and the trace shows that thing produces precisely 53 — **so the row is honest and now under-claims rather than over-claims**. `D-m23-bk`'s revision sweep holds over all twelve blobs; `D-m23-bm` is exact, and the fifth statement in the earlier count was the `ExceptHandler`, which is not an `ast.stmt`. Gates: selftest 0 twice at 68, lint 0 over 521 files, gate A exit 1 at 132 with the ledger and all four dumps sha256-identical **to a baseline taken before anything ran**, gate B exit 3, reconciler 0 across A-K over 206 register rows. `make test` green on 2 of 3 with the one failure at `OAuthWireTests.swift:263` at 0.0% idle, and the suite alone passing 3/3 at equal or worse contention — the discrimination confirmed. **The machine was pathological: load 1009 with 648 runnable on 16 cores, and a three-line bash stub unscheduled for over three minutes.** **The merge was resolved against the standing union rule, with a reason**: both conflicts were the same M23 row diverging, so a literal union would have put two M23 rows in each table and tripped checks H and K; main's newer row was taken. **Why Done rather than another cycle** — the verifier found one genuinely false sentence (`D-m23-bn`) and did not block, drawing the distinction exactly: gap-fix 8 set three criteria and all three are met and independently re-measured, where the eighth verification's block was an **acceptance failure** — four sites asked for, three delivered. This is a rebuttal sentence whose substantive point is correct and on which no figure rests, *which is what the register exists to carry*. Follow-ups `D-m23-bn`...`D-m23-bq`, including **`D-m23-bq`: `swift test --filter` reports a zero-match filter as a pass** — `make test` guards exactly that and a direct `--filter` does not, so a verifier doing contention discrimination can record three green isolation runs that executed no test. G4's class, met in the verification path rather than the product. |
| R10 | `index` prints two counts that disagree, and neither is checked | router | R9 ✓ | — | Opus | **Merged** `8241e0f` | `ai/r10` `f810870` | **Verified 2026-08-21 at `effect-witness`.** The verifier ran the rebuilt CLI as a separate process against a real `0o500` home and asserted the kernel's refusal from outside the product — `manifest.json` genuinely absent, the refusal in the router's own log — rather than that stdout stopped saying `ok`. 8 gates; two arms red (restoring `try? ManifestIO.save` and adding an `exit(1)` both turn the suite red, so the fix and the held exit-code contract are each pinned). codex failed twice for harness reasons — once *Not inside a trusted directory*, once an 880s SIGALRM with an empty `-o` — **logged as lane-down and substituted with agy/gemini-3.7-flash-high**, which found no blocking defect. Three follow-ups `D-r10-a`…`D-r10-c`. Two bundle claims refuted. |
| R14 | A client's Authenticate action succeeds, and says which upstreams still need authorising | router | — | — | Opus | **Merged** `2481e05` | `ai/r14` `0ecf7b4` | **Merged 2026-08-21 at `2481e05`, on the owner's decision.** **Verified 2026-08-21 at `raster-visual`; verdict Done.** The load-bearing security and behaviour assertions sat at **`effect-witness`** — raw-socket reads of the 302's terminating chunk, `stat` on the issuer key, and real process kill and restart to prove token survival. **The symptom is fixed**, driven independently against built instances of **both** routers on spare ports under `MCP_ROUTER_HOME` sandboxes: discovery 200 plus the RFC 9728 suffixed form, `POST /register` **201 and idempotent**, `/authorize` 200 with `X-Frame-Options: DENY` and `frame-ancestors 'none'`, `/token` 200, code replay refused, refresh validated, garbage refresh refused. `/mcp` returned 200 bare, with a valid bearer, with a garbage bearer and with an empty header — **`401` appears nowhere in either implementation**. **The four-state report's discriminator was proved on the verifier's own fixtures rather than trusted**: on a synthetic set `auth.authorized` read `true` for 3 of 5 silent upstreams **and `false` for 3 of 8 healthy ones**, so it fails in both directions — and the page ignored it, giving `mobbin` *not an authorisation problem* with **no command box**, confirmed in the raster. **The bypass is closed and the class is clean**: consent ticket as code, ticket as refresh, access as refresh, refresh as code, `client_id` as code and access token as `client_id` are all refused on both routers. Also verified on both: `Origin: null` and cross-origin refused on all three POST routes, `/register` 415 unless `application/json`, loopback-only `redirect_uri` at registration *and* authorize with userinfo and suffix tricks refused, PKCE S256 mandatory, 64 KB cap, issuer key 0600 in a 0700 dir, tokens and `client_id` surviving a real restart. **The Swift 302 genuinely completes** — chunked with the terminating zero-length chunk, read off a raw socket, identical to the reference. Gates: `swift test` 1595/199 exit 0 with both new suites executed, `parity-authserver.sh` **94 checks 0 failed**, `parity-manifest-check` 0 at 92 rows, `make lint` 0. **Blocking for the merge, not for these items**: `parity-gate.sh` exits 1 on one row, `control / POST /servers/:name/auth`, which R14 cannot have caused — it changed **no file** under `Control/` — and which the verifier measured as a coin flip, **5 green and 4 red over nine runs of the identical binary**, uncorrelated with the gate wrapper. Registered `D-r14-f`. **The runner's lint claim is half right**: four steps not six is correct, but `D-r7-af` stands — the only mentions of `node_modules` and `dist` in the lint configuration are *exclusions*, so no step reads either path and `lint: tools` is a genuine false dependency; the runner answered *is lint blocked* while `D-r7-af` asked *does lint need node*. **The R7 refusal was right** and is not a gap. Lanes: gemini attacked from a malicious page's position and found **no working attack**, naming the stopping control for each of seven vectors and matching the verifier's own results independently; grok exited 0 after ~30 minutes with 303 bytes of preamble and no findings, reported as not delivered rather than retried. **Disclosed by the verifier**: running the CLI without `MCP_ROUTER_HOME` read the owner's live config and minted `~/.claude/mcp-router/auth/issuer.key` before dying on `EADDRINUSE`; it created exactly that one file, removed it, and the orchestrator independently confirmed the directory is intact — key absent, `mobbin.json` and `control.token` unchanged. Follow-ups `D-r14-a`...`D-r14-g`. |
| R15 | The Host check guards `/mcp` and nothing else | router | — | — | Opus | **Merged** `2481e05` | `ai/r14` `0ecf7b4` | **Merged 2026-08-21 at `2481e05`, on the owner's decision.** **Verified 2026-08-21 at `effect-witness`; verdict Done.** R15 holds **across all eleven routes on both routers**, with `/mcp`'s 403 body byte-identical to the reference at 97 bytes in `jsonrpc, error, id` order while every other route gets the plain `Invalid Host header` envelope. The live exposure this was filed for — `/health`, `/status`, `/servers` and `/usage` answering 200 to a foreign Host — is closed. Delivered inside `ai/r14`; merges with it. |
| R16 | Adoption reads global scope only, so a project-scoped server is invisible to it | router | — | — | Opus | **To Do** | — | **Raised by the owner 2026-08-21 from a live failure**: proctor was expected in the relay and was never there. `src/index.ts:85-86` reads `src.mcpServers`, the top-level key, and never reads `projects` — so **every project-scoped server in `~/.claude.json` is invisible to `import` and `watch` by construction**, not by a race. Confirmed empirically: no upstream the router serves carries a `projects` field. The sharper half is that **the router already models this** — `src/config.ts:16-21` carries `projects?: string[]` with the comment *a global on/off switch cannot say "this server for that repo and not this one"* — so it can express per-project scoping and cannot learn it from the harness it adopts from. And it is not merely a missing read: `proctor` is one name over three different commands (`serve`, `--profile core`, `--profile scripting`) in three projects, and the router keys upstreams by name, so adopting the first match would silently run the wrong profile for two of them — worse than today, which at least fails visibly. Three shapes recorded, none obviously right; shape 2 is the floor, because **a skipped adoption should be reported rather than absent**, which is R14's silent-upstream class again. `D-r7-i` is the mirror image — `HarnessesVerb` prints `Global scope only` while reading a project-scoped file — and both should be settled by one decision about what scope this product works in. **Triaged 2026-08-22 — To Do, Standard, scoped to shape 2.** Both halves confirmed at HEAD: `cmdImport` reads `src.mcpServers` at `src/index.ts:85` and never `projects`, while `projects?: string[]` is modelled at `src/config.ts:21`/`:126`, resolved at `:164`/`:189` and **editable through the control PATCH** at `src/control.ts:450` — so hand-scoping works today and only *learning* it from the harness is missing. **The report criterion 3 asks for is already built**: `skipped` is collected at `src/index.ts:93` and printed as `not adoptable:` at `:153-155` with a per-server reason, holding only `parseServer` refusals today. So the work is enumeration plus the collision decision, not a new report. **Shape 1 is not deferred by preference** — it decides what scope this product works in and `D-r7-i` is its mirror image, so building it now settles that from the side with less evidence. Filed **R16-C1**. Shape 3 refused: it changes the tool namespace the model sees. |
| R17 | A failed index leaves a recorded error for one server and nothing at all for another | router | — | — | Opus | **Merged** `54666f7` | `ai/r17` `55075ed` | **Verified 2026-08-22 (2nd); verdict Needs More Work — two clauses, no code (gap-fix 2 queued, `R17-gapfix-2.md`).** **"No behaviour changed" was proven above the rung it was claimed at**: rather than filtering the diff, the verifier compiled both revisions — `tsc --removeComments` gives byte-identical JS and `swiftc -frontend -dump-parse` byte-identical parse trees — so **the edits are ruled out of the named red by construction rather than observation**. **The strengthened route account survived the strongest attack available and is under-stated**: the R19-only world was built in the shape of the owner's machine and run against a held-open fire, and **R19 alone admits exactly two outcomes across the two write timings, neither of which is the measured partition**. Every gate green, every line citation resolving, the named red confirmed registered by name in `D-r7-x` and by file-and-line in `D-g3-s`, and `R20` filed with a real work order. **BL-1**: `R17-acceptance.md:114` still carries *R19's window is indifferent to whether a server is staged* — the framing the same section records as broken five lines above and replaces four lines above. **Third consecutive pass to block on that class**, second on this item. **BL-2**: the uncovered list is wrong in both directions — **six** sites not four, `src/index.ts:146` and `:186` have **no Swift twin** so the symmetry claim is untrue of half the list, and the two Swift sites that are uncovered appear **nowhere** in `R19.md` or in `surface.tsv` where the declaration lives. The correction landed in two of the four places the claim appears, which is BL-1's shape inside the same pass, and it sends R19's runner looking for twins that do not exist. **Settled counts, from both sides: node 5, Swift 3** — a number now wrong three times in three directions. Follow-ups `VER2-R17-3` (the same divergence readable from source on `index` and `import`, filed as merely unmeasured), `-4` (LEDGER's compressed row reads as if five were wrong; five was right for node), `-5` (the replacement figure is as unstable as the one it replaced — 21/21 twice standalone, the struck-through number). **And the verifier found two committed merge-conflict blocks in `ORCHESTRATOR.md` that all ten reconciler checks passed over** — the orchestrator's, from the R7 merge; resolved by union with nothing lost, and **check L** added, which reads lines rather than rows. **Verified 2026-08-22 (3rd); verdict Needs More Work — gap-fix 3 queued (`R17-gapfix-3.md`), two lines, no code.** Criteria 1, 2 and 4 pass: the withdrawn clause is gone and a wrap-tolerant sweep finds the assertion nowhere; the six-site list has **both inventories re-derived from source rather than carried** (node 5 `saveManifest` with `writeFileSync` only inside it, Swift 3 `ManifestIO.save` and no other writer), verb attributions spot-checked; gates unmoved. **Criterion 3 fails, and the instrument is the finding.** `R17-acceptance.md:472` still reads *the declaration names all four uncovered sites* — the document in its own voice, now false since `surface.tsv` names six — and **the runner's sweep could not see it**: the hard wrap falls between `all four` and `uncovered sites`, so `grep -c` returns **0** where a whitespace-normalising match returns **1**. Fourth consecutive pass to block on this claim class and the first where the instrument rather than the diligence is at fault. Filed as G4's **tenth instance**. `:647` fails arguably too — node-scoped it is true, but its subject is what the declaration says. **`D-r17-d` refuted as stated and strengthened in substance**: serially it never reds (**0 of 40** on the branch, **0 of 40** on main), under four concurrent copies **53 of 104** and **24 of 72** — concurrency-conditional, not flat, and reproduces-on-main settled. Mechanism **proven**: ten fixture names reported in **both directions at once** over an unchanging git-tracked directory, which can only come from the `grep -qxF`-per-item comparison at `parity-manifest-check.sh:431`/`:437`. Now also carried as a fleet-level gate hazard. **The base-behind-main pair confirmed**: `grep -c '"L"'` is 0 here and 1 on main, both conflict blocks are still at `:242-249` and `:643-664`, so check L would go red from this base and the work order's `A-L` was unmeetable — the dispatch's gap, not the runner's, and it does not change the verdict. **Verified 2026-08-22 (4th); verdict Needs More Work — gap-fix 4 queued (`R17-gapfix-4.md`), record only, no code.** Criteria 1, 2 and 4 pass with both inventories **re-derived from source by the verifier** rather than carried; criterion 3 passes **in substance** — the claim is gone from every home — while its pasted evidence predates the file it reports on. **The block is `D-r17-d`, and it is the third consecutive pass to state a reproduction rate the next measurement refutes.** 368 invocations on a quiet tree: **0 of 40 serial, 0 of 80 at 4×, 0 of 96 at 8×, 0 of 96 at 16×, 1 of 96 at 32×** — against the row's 29/80 at 4×, and the pass before that 53/104 and 24/72. **The defect is proven** — one red on a git-clean 24-file fixture directory — and the **condition is not**: the controlling variable is total machine pressure rather than this gate's own concurrency, and every high rate was recorded while other sessions loaded the box. The remedy is to stop stating a rate: record the mechanism, the direction and the four measurement sets as history, and say plainly that the condition is not yet stateable. **`D-r17-d`'s *proven rather than suspected*** rests on the third pass alone — the both-directions contradiction **was not re-witnessed**, the fourth pass's single red giving direction A only. And `R17-gapfix-3.md`'s *another session merged `ai/g5`* is closed as false: `git merge-base ai/g5 main` is `2fbe062`, `ai/g5~1` **is** that commit, and main's merge list holds M21, R7, M23 and G3 and no G5 — the runner's conclusion was right and its cause wrong. **Gap-fix 4 delivered and in its fifth verification.** All four criteria met: `D-r17-d` carries the four measurement sets **as history with no reproduction recipe**, naming total machine pressure rather than the gate's own concurrency, and matching `main`'s fleet hazard row. The both-directions claim drops to *proven once, not reproduced since*. **Three things the runner found rather than repeated.** The fourth verification's *368 invocations* **does not match its own table, which sums to 408** — 368 is the concurrent subtotal and the serial 40 sits outside it; both are right about different populations and neither said which, which is how the last three passes each inherited a wrong denominator. The brief's `ai/g5~1` **is** `2fbe062` **had already rotted when written** — the branch took two commits, so it is `ai/g5~2`, `ai/g5` is no longer an ancestor of main and check E is clean; substance unaffected, no G5 merge ever happened. And **where `main`'s row and gap-fix 3 disagree on the both-directions contradiction, it recorded the disagreement rather than picking a side**, since neither run can be replayed. **The sweep is committed as `planning/claim-sweep.py`, and why its evidence never reproduced is now understood: a report that echoes what it matched becomes a corpus hit.** Without exclusions, gap-fix 3's sweep reds **8 times inside gap-fix 3's own document**. It now excludes the records of a withdrawn claim by name with no counts, making its output a **fixed point under being pasted into one of them**, `cmp`-verified — and a blockquote `>` was found to separate two words exactly as a hard wrap does, invisible until fixed. One gate red reported rather than re-rolled: `OAuthWireTests.swift:263` failed once and passed on retry at load 625-1015, **reported as two events rather than a rate**, and added to `D-g3-s`'s count as its third instance. **Merged-tree gates re-run by the orchestrator rather than taken on report**: `make lint` **0 violations, 0 serious in 536 files**, `0/543 require formatting`; `make test` **1699 tests in 212 suites passed**, exit 0; reconciler **0 across A–L**. The merge introduced nothing. |
| R18 | A failed index drops the digest, so the next success serves a changed surface unheld | router | — | — | Opus | **To Do** | — | **Found 2026-08-22 by R17's fable review lane and reproduced against the built router.** A failed index drops the manifest row's `digest`; on the next successful index `buildManifest` takes its **first-sight-approves** branch, so a changed tool surface is served with **no held diff**. Reproduced end to end: benign surface serving, one failed re-index leaving `digest= None`, then a re-index with a **tampered** surface giving `pending: False` and the tool served. The hold that exists to make a changed surface wait for a human is skipped, because the router no longer holds what it would compare against. **Its own item, not R17's**: it predates R17 and the behaviour R17 removed had the same hole, so folding it in would have been an unasked-for fix inside a pass scoped to the missing record. **Establish first whether the drop is deliberate** — a failed index has no trustworthy surface to digest, so writing no digest is defensible and the defect may be that the *absence* reads as *never seen* rather than *unknown*; persisting the last good digest and adding a third state are not compatible fixes. `R14`'s report would show this server healthy throughout, because it is — the tools are served, and nothing surfaces that a diff was skipped. Review output preserved at `planning/evidence/R17-review-fable.md`. **Triaged 2026-08-22 — To Do, Standard, planned alongside `R20`.** **Confirmed by reading and the drop is incidental, not deliberate**: the `catch` at `src/manifest.ts:258-265` constructs a whole new entry while `prev` is in scope, and the held-diff branch four lines above spreads it — so `digest` and `tools` both go, and `!prev?.digest` at `:236` takes the same branch as a match. Evidence is this file's own convention: every deliberate retention here carries a defending comment, the first-sight branch has a six-line one, this branch has none. So **keep the last good digest** and an absent digest keeps meaning *never seen*. **The remaining fork is the plan stage's first decision**: `unionTools` at `:326` skips on `!entry` or zero tools and **never reads `entry.error`**, so the empty list is load-bearing and doing the error field's job. Digest-only leaves a seen-then-failed server held against an empty approved set; digest-and-tools with serving gated on `error` is correct for the right reason and reaches `router.ts:168`/`:347`. Criterion 2 separates them — arm it against a never-seen server **and** a seen-then-failed one. |
| R19 | A watch fire saves a manifest snapshot taken before a concurrent write | router | — | — | Opus | **Done** — merge held as R19-INT | — | **Found 2026-08-22 by R17's verifier, demonstrated against the FIXED code.** `cmdWatch` snapshots the manifest at `src/watch.ts:212` and saves that snapshot at `:273`, so anything written in the window is clobbered **with no delete statement in the path**. Sandbox demonstration: a `watch` fire held open six seconds on a staged failing server while `index --force` wrote unstaged `lifeline`'s row at t+2s — the final manifest holds `slowfail` only. **This produces the same observable R17 attributes solely to the deleted row**, and R17's evidence was gathered on a timeline where the two were concurrent, so that account is *sufficient* and not *exclusive* (`VER-R17-1`). R17's route account remains the better fit for the observed asymmetry and is kept as that. **The class is already guarded elsewhere**: `manifest.json` has five `saveManifest` call sites and no lock, while the config writer states *W11 — the read happens inside the lock, so a concurrent write is not clobbered*. The question is whether the manifest wants that same treatment, decided over all five sites rather than one. **`VER-R17-2` rides with it**: Swift re-loads the manifest per entry immediately before saving and node loads once per run, so on the same fixture Swift keeps both rows and node does not — and `parity-cli.sh` cannot see it because it runs the binaries **sequentially**. **Triaged 2026-08-22 — Ready for AI, Standard. The precondition is settled and the answer is neither option the brief listed.** Referred to the Google lane (`agy`, `gemini-3.7-flash-high`) with the write-site census, the `ConfigMutationLock` source and both options; it returned a third shape: *do the long-running child indexing with no lock held, then take the lock strictly around the commit phase — read current disk state, merge the single row, write temp, rename. Lock duration drops from seconds to <1ms.* **Policy over all eight sites: `withExclusiveLock { load; merge the rows this path owns; save }`** — the load moves inside the lock, because it is the stale read that clobbers rather than the write. **That dissolves the objection which made this a fork**: option A held the lock across the seconds-long read-then-index window and would have made a concurrent PATCH fail at the 2000 ms daemon bound; commit-phase-only never reaches it. Rejected by name: a `manifest.d/*.json` split (*orphan cleanup bugs on delete/rename, migration churn for a single small config*) and optimistic CAS retry (*unnecessary — `flock(2)` queues sub-millisecond writes with zero retries*). **`VER-R17-2` inverts** — Swift's re-load-per-entry was the right instinct without exclusion, so the fix upgrades it and the two converge by construction; a `surface.tsv` declaration becomes the fallback rather than the plan. `ConfigMutationLock` is already generic over the path; **node has no counterpart and that is the larger half**. Eight sites, a node lock module, and **one overlapping-writer scenario with no precedent here** — `parity-cli.sh` runs the binaries sequentially and is structurally blind, so it needs a new lane rather than a new row. **Ready to verify 2026-08-22** — five commits on `ai/r19`, all eight write sites inside `withExclusiveLock { load; merge; save }` with the load in and the spawning out, exactly as the triage settled. Node's five writers collapse to three. **`VER-R17-2` closes by convergence rather than declaration**: node's `buildManifest` takes a **required** commit hook so it re-reads per entry immediately before saving, which is what Swift already did — so the two agree on the property instead of the divergence being written down. Node reaches `flock(2)` through macOS **`O_EXLOCK`** (Node has no `flock` binding), measured excluding in both directions and kept true by `overlap-lock-shared`. **The scenario that had no precedent exists**: `scripts/acceptance/parity-overlap.sh`, dispatched by the gate with two `overlap` rows in `surface.tsv`, drives `index --force` into the middle of a live `watch` fire and asserts the second writer's row survives, then holds the sidecar from a third process and asserts neither binary writes through it. Gates: lint **0 over 533**, `make test` **1687 in 210**, `parity-gate.sh` exit 1 at **93 of 94 proven, 0 diverged, 1 blocked** (the standing exclusion, which is what the exit 1 is), `parity-cli.sh` **17/17**. **Five arms, two recorded as not biting where aimed rather than swapped** — Swift's `WatchIndexer` unlocked reddens `W11/watch` while the overlap lane stays **green**, because Swift's pre-R19 window was a per-entry re-read microseconds wide that no fixture reliably lands inside, which the runner offers as the reason `parity-cli.sh` could never have found this. Two unrequested changes declared: `ManifestIndexer` moved to its own file (the comments took `ServicePorts.swift` past the 400-line ceiling), and the gate's coverage-by-group block walked a **hardcoded list of nine names** already swallowing `authserver`'s eight rows — now derived, and filed as G4's fourteenth instance. **Merge-order hazard**: `ai/r17` declares the window this item closes, so whichever lands second must delete that note. **Verified Done 2026-08-22.** Oracle rung **behavioural, cross-process, on the real binaries** — the verifier re-armed and reproduced the defect itself and **timed the overlap rather than assuming it**. Gates on the branch: lint **0 over 533**, `make test` **1687 in 210**, `parity-cli.sh` **17/0**. Three gate numbers that moved are each shown outside this item's diff. **The reconciler does not reproduce the check-E finding** — exit 0, clean across A–L, 26 merged branches — because `ai/g5`'s tip is no longer an ancestor of `main`; better than predicted and for a reason that is not this item's. **Merge ordering answered, and the orchestrator had already merged R17 first**: the verifier's advice was R19-first precisely because `surface.tsv` **auto-merges**, so R17's stale `cli-watch` note survives silently. Taken up as **R19-INT** rather than resolved at the merge, because the two code conflicts are **records rather than logic** and R19's base predates R17, so its side never chose to drop R17's route account. **Unsettled and declared, none blocking**: `buildManifest` still decides staleness from the outer snapshot, so a non-forced run can skip a server another process invalidated mid-run; the watcher's in-lock `delete` of a failed row can still remove a good row another writer just wrote for that name, identically on both routers and predating this item; and node now has a lock module while node-side `servers.json` (`watch.ts:311`, `control.ts:105`) still takes nothing where Swift locks it — a real asymmetry this item's scope correctly excludes and that is now cheap to close. |
| R19-INT | The R19/R17 join: three records to merge and a declaration to delete | router | R19 ✓ R17 ✓ | — | Opus | **Ready for AI** | `ai/r19` | Raised 2026-08-22 after the orchestrator **aborted the merge deliberately**. R19 is verified Done; merging it into `main` at `54666f7` conflicts in `src/watch.ts` and `WatchIndexing.swift` and **auto-merges `surface.tsv`**, which is the dangerous half. **None of the three is a logic conflict** — all are records carrying evidence that took five verifications to make true, and R19's base predates R17's merge, so where its side drops R17's comment it never made that choice. Taking either side wholesale discards one of them. **The `cli-watch` note's third-divergence declaration is false the moment R19 lands** in three specific claims, and git will not prompt anyone: node now re-reads per entry too, so the divergence closes **by convergence**, and the property the note calls unreachable is now held by R19's `parity-overlap.sh`. **And `parity-cli.sh` has never run on the two together** — R17 added a fourth `cli-watch` scenario projecting the manifest's shape, R19 changed the node watcher under it, and main reads 18 or 17 verbs depending which branch you ask. |
| R21 | `approve` answers 200 while discarding the write that would make it true | router | — | — | Opus | **Ready for AI** | — | Filed 2026-08-22 while re-measuring M28's DEF-049. `AuthRoutes.swift:120` is the last of that defect's three `try? ManifestIO.save` sites and the only one unfixed: the route sets `tools`/`digest`/`builtAt`, removes `pending`, discards the write and returns `(200, approved: N)` unchanged, so a refused write leaves the tool surface held while the caller is told it was approved. `approved` is counted from the pending entry **before** the write, so the number describes intent rather than outcome — the same shape as `index --force` printing `ok` over a manifest that did not land. **DEF-049's louder prediction is refuted**: a stale `builtAt` firing `Describe.swift:218` so `/servers` reports `authorized: true` cannot happen, because approve is reachable only with `pending` present and both implementations clear `error` when they stage one (`src/manifest.ts:246`, `ManifestBookkeeping.swift:83`), so the `guard` at `Describe.swift:208` fails first and `:218` is never reached — and the two agree, so it is not a parity divergence either. The fix shape is established at `ServicePorts.swift:388-394` — catch, carry a `cacheFailure` into the response — and the status code does not move, because `ControlApproveDispatchTests.swift:114-118` pins 200 deliberately. |
| R20 | A staged entry wipes a same-named healthy upstream and blames it for the failure | router | — | — | Opus | Untriaged | — | **Found 2026-08-22 by R17's verifier, measured against R17's FIXED code.** The manifest is keyed by name alone, so a failing entry staged in `~/.claude.json` overwrites the row of a same-named healthy router upstream — and `/servers` then attributes the **staged** definition's error to the **configured** server. Measured: a healthy `db` serving 2 tools, then a broken `db` staged, yields `indexError: spawn /nonexistent/not-a-server ENOENT` for a server whose configured command is `node`; pre-fix the same sequence read `error: None`. **The tool loss is not a regression** — the old delete removed the row outright and `unionTools` skips a missing entry exactly as it skips a zero-tool one, so the tools vanished either way, hot-reloaded and mid-session. **The misattribution is**: the reader is now shown a specific wrong reason naming a command the configured server does not run, where before it was shown nothing. This is **the one surface R17 makes newly wrong**, which is why it is filed rather than left in R17's evidence. fable's F4 raised the shape and the verifier measured it. **Decide it with R7**: the duplicate declaration is the precondition, `namecheap` is exactly that shape, and patching the attribution alone leaves two files claiming one name and a serving upstream still losing its tools when the staged one fails. |
| M27 | The sidebar foot's loopback readout and the child-process label | mac | M1 ✓ | `design/mocks/prototype.html` | Opus | **Merged** `cbe5cc3` | `ai/m27` `26337b8` | **Verified 2026-08-21 at `raster-visual`.** The verifier re-ran `mac-shell.sh` against the live app and, in the same iteration as each AX assertion, took a `screencapture -l<CGWindowID>` of that window — then opened the PNGs and read `127.0.0.1:8971` and `Child processes  1 of 4` off the pixels. Two mutations red (`.combine`→`.ignore`, and deleting the line). codex/gpt-5.6-sol confirmed no runtime defect. Six follow-ups `D-m27-a`…`D-m27-f`, none blocking — but `D-m27-a` is worth reading before the next item touches A35. |

**Wave A, 2026-08-21 04:18 — one of four landed, and the cause is not capacity.** Nineteen
agents ran for four items: the harness retried each stalled runner six times. Every abort
reads `[Request interrupted by user]`, and every stalled transcript ends inside a foreground
polling loop — `until grep -q "^exit=" …; do sleep 15; done`, `for i in $(seq 1 40)`,
`until [ "$(wc -c < …)" -gt 1500 ]; do sleep 20; done`. A loop like that emits no tool output,
**The baseline this fleet's greens now rest on, re-measured quiet.** Every gate run this session
landed at 08:23, 08:30, 08:44 and 08:49 — all four inside the load window above, so all four were
obtained on a machine running 32 competing busy-loops. Re-run on merged `main` at 09:47–09:49 with
the CPU 46–61% idle: `make lint` 0, **`make test` three times, 1583 tests in 197 suites, all three
exit 0**, `make parity` 358/358 at floor, `make acceptance-r6` `examined=6 failures=0`.

Worth stating plainly because the instinct is backwards: contamination made those greens
**stronger**, not weaker. A suite that passes while 32 processes fight it for CPU has been tested
harder than one that passes on an idle box. Nothing else in these
gates reads a clock: lint counts, parity vector counts, the child-PATH lane's assertion on PATH
content and the ledger reconciler are all deterministic, so saturation cannot move them.

**The one result that cannot be re-derived, recorded as unattributed.** The session's first
`make test`, at 08:23 on R6's merged tree, exited 1 with *"Test run with 1543 tests in 193 suites
failed after 4.480 seconds with 1 issue"*. **Which test failed is not known and is not
recoverable** — the command piped through `tail -6`, which kept four passing lines and the summary,
and no fuller log exists. G3's `PoolReapingTests.swift:61` is the strongest candidate: it is the
only wall-clock assumption in the suite and the machine was saturated. A strongest candidate is not
a name, and this row does not claim one. Two runs on the same tree minutes later and three on
merged `main` an hour later all exited 0.

The forward fix is one line: **a gate's output goes to a full log and `tail` reads the log**, never
the other way round. Piping the gate through `tail` discards precisely the evidence a red run
exists to produce, and it costs nothing until the one run that fails.

**DESIGN OF RECORD — settled 2026-08-22 by the owner: `design/mcp-router-console.html`.** The instruction was *whichever's newest*, and the two readings of newest disagree: the console mock was **created** 20 Aug against the prototype's 13 Aug, while the prototype was **last modified** 21 Aug 03:06 against the console's 20 Aug 09:49. The prototype is the more recently touched file because M27 was implementing against it, not because it was redesigned — so *newest design* and *newest file* point opposite ways, and the newer **design** is the console mock. Corroboration is one-directional: `PRD.md` §9.1 states it supersedes the Instrument Panel direction and calls `DESIGN.md` historical, `planning/fidelity/` keys every layer file and the token register to it, and **M23's only manifest — the pipeline's one measured route to Done — already assumes it**. Against that: `campaign.json`'s `designOfRecord` names the prototype, and DEF-016's closure records an owner decision for the prototype **which never mentions the console mock**, having been taken about the prototype versus two superseded contact sheets. **Consequences now live.** `DESIGN.md` §1-2 and `BreakerParityTests` bind to the breaker column, which the console mock retires, so M16 is a re-authoring rather than an addition and its parity test's oracle moves with it. `campaign.json`'s `designOfRecord` is now stale and is **not corrected here** — `planning/test-campaign/` belongs to another session, and this is recorded for its owner to apply.

**RULE — a `-p` review lane asked to BREAK something gets a read-only sandbox or a throwaway copy, never the tree under test.** Recorded 2026-08-21 after `claude-fable-5`, launched with the M23 worktree as its cwd and asked to break the artifact, *applied* its proposed mutation to `scripts/acceptance/mock_fidelity.py` in the working tree — between one gate finishing and the next, so the later gate measured a mutated engine and reported the lane's edit as the product's behaviour. Caught by `git status`, not by the gate. **The finding was genuine and was the strongest evidence in that pass** — witnessed on the live gate rather than on a fixture — which is exactly why this is a rule about method rather than about that lane: a reviewer that can write to the subject can make a true finding unattributable, and a gate run beside it cannot tell a product defect from a reviewer's edit. Run the lane from `/tmp`, or against a copy, or read-only. `codex exec -s read-only` already does this; the Claude and Gemini lanes do not by default.

**2026-08-21, updating the lane record.** `D-r7-ai` recorded grok as **packet-size limited rather than down**, on evidence that it returned 1,051 bytes at exit 0 for a 1,174-byte prompt. G3's gap-fix 2 measured worse: **down four ways** — output about an unrelated repository at a 5.6 KB packet, the `cursor-agent` fallback reporting out of usage, and two runs at **3.7 KB** emitting only narration before the 900-second alarm. A 3.7 KB failure is inside the size band `D-r7-ai` said worked, so the packet-size reading no longer covers it. Codex remains down to 27 August on a usage limit, header verified before the call rather than inferred from the empty output. **`claude-fable-5` substituting for codex earned the slot**: it ported the scanner into a harness and *ran* each break rather than reasoning about it. Two families is the working configuration today, and both should be asked to **break** the artifact rather than review it — that phrasing yielded twelve defects across three rounds where review phrasing had yielded a handful.

**2026-08-21 — a runner died holding a live mutation, and the worktree looked ordinary.** M23's gap-fix 4 runner terminated on an API error mid-arm. `.worktrees/M23` showed two modified files and nothing else amiss; one of them was the engine, carrying `run.report_written = False  # MUTANT`. Any gate run there would have measured a mutant and reported it as the product. Reverted by targeted replacement rather than `git checkout` — the file returned byte-identical to HEAD and no `# MUTANT` marker survived anywhere under `scripts/` or `app/`; the mutant copy was kept at `/tmp/m23-mutant-backup.py` so the runner could re-plant rather than re-derive. The 31 lines of selftest arming work survived and the agent was resumed in place rather than cold-started, told what had been changed and instructed to **re-plant and re-measure any arm whose red it had not personally seen this session**, because an agent resuming from a transcript can believe it watched something fail when what it holds is the memory of intending to. **RULE — after any runner failure, diff the worktree against HEAD before running anything in it.** A dead runner's uncommitted state is not neutral; on an item about checks that stay green under mutation, the wreckage was an engine that was green because it was mutated.

**2026-08-21 — the codex lane is down until 27 August**, on a usage limit, reported by M23's fourth verification. It is the default out-of-family lane in every brief in this repo, so substitute the Google family first and then xAI. **grok is packet-size limited rather than down** (`D-r7-ai`): 1,051 bytes at exit 0 for a 1,174-byte prompt, after returning nothing at 16.5 KB and at 64 KB — send it hunks and a question, never a whole diff. The Google lane earned its substitution on M23: it named two evasion families the verifier had not found, and also produced one factual error the verifier refuted by measurement and one hallucination, which is the argument for running it and checking it rather than either trusting or skipping it.

**2026-08-21 — R7's merge is deferred on purpose, and the reason is not caution.** R7 verified `Done` at `effect-witness` on `ai/r7` `51735c6` with no blocking findings, and the merge did not follow immediately. At the moment it landed the machine read **0.0% idle** with a load average near 380 and two sibling runners live: G3's second gap-fix and M23's fourth verification. The merge gate is `make test` twice plus lint, parity and the R6 lane — substantial load. **G3's runner is measuring wall-clock mutation timings for an item whose entire subject is timing determinism**, so running that gate now would not merely be slow, it would corrupt the evidence the sibling is producing, in precisely the dimension that item exists to measure. This session already refused to create synthetic load beside a measuring runner and constrained another to one short named window; a real gate is the same load with a better excuse. R7 sits at **Verified — awaiting merge** until G3's runner reports, then merges under the normal sequence: gate the merged tree, `comm` the branch's changed paths against the main checkout's dirty paths, merge with `MCPR_ORCHESTRATOR=1`. Nothing about the verdict is provisional; only its landing is.

**2026-08-21, and the detector is now 600s rather than 180s.** Two runners (M23 gap-fix, G3)
were killed by it inside the same ten minutes without either doing anything wrong. The cause was
off this repository: another project left 32 orphaned busy-loop processes — a load generator whose
parent was SIGKILLed before its `kill $LOADPIDS` ran — pinning the machine at load average 548
across 3001 processes for 2h48m. A starved agent emits no tool output, which is indistinguishable
to the watchdog from a stuck one. Cleared by the owning session; CPU came back to 27% idle and both
runners resumed in place from their own transcripts rather than cold-starting.

Two things this repository should carry from it. **A red `make test` is uninterpretable without
knowing the machine's load** — under that saturation `PoolReapingTests.swift:61` would have failed
every run, which is G3's whole argument for removing the wall-clock assumption rather than widening
it. And **a shell-snapshot id names a session, not a command**: `pkill -f <snapshot-id>` looks like
a precise selector and matches every Bash call that session ever makes, including its own. Find
candidates by pattern; select victims by explicit pid, after asserting the count and asserting the
known-live pids are absent.

the 180-second no-progress detector fires, and the agent is killed mid-build. R6 survived
because its last call was a fast `git rev-parse`.

`workflow-resume`'s scanner reports all nineteen as `session/usage limit`. That is a false
positive and its own documentation predicts it: the detector substring-matches transcripts, and
both the runner prompt and this file discuss usage limits at length. The transcripts settle it.

**Runners must not poll in the foreground.** Long builds go to a backgrounded command the
harness owns, or get bounded hard. That instruction is in the relaunch prompt, and it is the
only change from the brief that produced this.

**Wave A resumed, 2026-08-21 07:5x — four of four ready to verify.** All three stalled items
were resumed in their own worktrees rather than cold-started, so roughly 1.6M tokens of runner
work was recovered rather than re-paid for. `Workflow({resumeFromRunId})` was **not** used: the
journal held `results=1` of `started=19`, and replay stops at the first miss, so a resume would
have paid nearly full price for the tail while re-asserting one cached result that was itself
empty (`workflow-resume` §4).

Every branch merges cleanly against `main` at `425b360`: R6 +1 commit, R10 +6, M23 +6, M27 +12.

**Merged 2026-08-21, serialised one at a time, each gated on its own MERGED tree rather than on
its branch.** R6 `1d958b4`, R10 `8241e0f`, M27 `cbe5cc3`. The distinction matters: R10's tree ran
R6's `acceptance-r6` lane and reported `examined=6 failures=0`, so the two are known to compose
rather than merely to pass alone. Every merge was preceded by a `comm` of the branch's changed
paths against the main checkout's dirty paths, because three other sessions hold uncommitted work
here and this fleet has swept some of it into a commit twice.

R6's and M27's merges each conflicted in `LEDGER.md`, and in both cases **each side knew something
the other did not** — `main` carried the verify verdict, the rung and the follow-up ids, the branch
carried the spec/plan pointers or the build narrative. Both were resolved by combining, never by
taking a side wholesale.

`.worktrees/R6` and `.worktrees/R10` removed after proving `git rev-list --count main..<branch>`
is 0 and the tree clean. **`.worktrees/M27` is deliberately left in place**: it carries 12
uncommitted modified files under `planning/test-campaign/evidence/shots/` (a whole-file
re-serialisation of `captures.json` plus ten iOS PNGs) whose provenance is not established. It is
merged and could be force-removed; it is not, because campaign evidence in this repository belongs
to another session and a forced removal is unrecoverable. Whoever owns those changes should commit
or discard them, and then the worktree goes.
Each carries a committed evidence bundle at `planning/evidence/<ID>-acceptance.md`, so none
bounces back to its runner for an empty bundle.

**Verify dispatched 2026-08-21, run `wf_ca77347d-292`.** Four fresh-context agents, none of
them the builder — that stage's rule is structural. Two phases rather than four concurrent
agents, because M23's `MeasureDump` opens an `NSWindow` and M27's lane drives the real app
through the accessibility API: R6, R10 and M27 run together, M23 runs alone afterwards. Each
verdict must name the oracle rung of the assertions the verifier re-ran — not the rung the
runner claimed — and must run its own out-of-family review lane, because the work was written
by Claude and a verifier inside the writer's family is not an oracle.

**Merge blocker, open with its owner.** `app/Tests/MCPRouterUITests/ShellTests.swift` carries an
uncommitted change in main's working tree (20 Aug 23:37:58) that `ai/m27` also edits. Different
hunks, no content conflict, but git refuses a merge that touches a locally-modified file. The
author is session `7cba6593` (cwd `~/Dev`), identified by phrase-grep on two strings from the
comment body, matching that transcript alone at `2026-08-20T13:37:58.252Z` — the file's mtime to
the second. Asked rather than moved. M27 does not merge until its owner commits, stashes, or
says explicitly where they want it put.

**The ShellTests.swift blocker is cleared** — its owner (session `7cba6593`) set the change aside
to `~/.claude/projects/-Users-lukerhodes-Dev/setaside/mcp-router/`, verified byte-identical before
the restore, and asked that it not be reapplied until the fleet's merges are done. Worth carrying
into any work on that suite: `ShellTests.swift:133` currently reads
`#expect(result.tools != nil, …)` against a **non-optional `Int`**, so that assertion reads nothing
and passes against the failure fixture. It is one assertion weaker than it looks, the fix exists
and is not ours to land, and a runner that rewrites that line silently discards it.

**A benign merge conflict is now expected on two branches.** `ai/r6` and `ai/m27` each edit
`planning/features-to-triage/LEDGER.md`, and the fleet has since committed its own status changes
to the same cells (`c96b20f`, `eb784e4`). `ai/r10` and `ai/m23` stay clean. Resolve toward the
fleet's row at merge — it carries the branch and commit the branch's own row cannot know — rather
than taking either side wholesale.

**No branch touches `planning/test-campaign/`.** Checked across all five (`ai/r6`, `ai/r10`,
`ai/m27`, `ai/m23`, `ai/r7`): zero files each. That tree belongs to another session, and a merge
blocking there would be a surprise rather than a conflict.

`app/Tests/RouterCoreTests/ManifestIndexerWriteFailureTests.swift` was the other blocker and is
cleared: an untracked 133-line draft in main, superseded by the 373-line version `ai/r10` carries.
Copied to `/tmp/mcp-router-setaside/` before removal rather than deleted outright.

**Reconciled 2026-08-21.** The twenty-two rows below existed in
`planning/features-to-triage/LEDGER.md` and in no row of this file, which is the memory a
resuming fleet plans from. Fifteen of them had already merged. They are added here rather
than left to be rediscovered by a runner. `planning/ledger-reconcile.py` is the check that
found them and refuses in both directions; run it after every allocation.

Three ids in this table have no LEDGER row and need one there rather than here: **P5**,
**P6**, **R2-R**, **R2-W**, **R4-C**. And **X4** and **X5** are branches merged into `main`
that neither file records at all — the ids are spent, and both files read them as free.

**Mock note:** every item's mock is a deep link into the single interactive
`design/mocks/prototype.html`, not a separate file. `design/mocks/mac-surfaces.html` and
`ios-surfaces.html` are superseded static contact sheets — do not build from them; they
are pending deletion.

---

## Deferred children — registered, not yet scheduled

Reported by wave-1/2 runners. Each names the item that should absorb it; none blocks a wave.

Rows here whose id matches the allocation pattern — `R11`, `R12`, `R13`, `M5-a` — **are** checked
by `ledger-reconcile.py` (A, B, C, F, G). Rows named `D-<parent>-<letter>` are notes rather than
allocations and are excluded by design; check H reads none of this table, because it carries no
`Status` column.

| # | Child | Absorbed by | Why it was deferred |
|---|---|---|---|
| D-a | Record the HTTP status alongside each recorded fixture | R4 | The fixture set proves the *body* decodes; the status is a second assertion the parity harness will want and the client currently infers |
| D-b | Surface the call-log stream's skipped-record count | M2 | The stream already skips an unreadable record "not silently"; nothing yet displays the count, so a lossy stream looks clean |
| D-c | Expose `usage(limit:server:cwd:)` in Activity's filters | M2 | The client takes all three filters; the Activity mock only offers server |
| D-d | Make the router's caller attribution deterministic rather than `lsof`-raced | R3 | F3's fixture capture raced the async lookup and recorded an unattributable call. Worked around with a capture-time guard; the router-side fix belongs to whoever owns the control API |
| D-e | Signed/notarized macOS packaging | new item, after M8 | Blocked on **Needs input #1**, not on code |
| D-f | Machine-readable token block in `DESIGN.md` | M1 | F2's parity gate parses prose tables today; a fenced block would make it robust to editing |
| D-g | Parity vectors for divergences D1/D3/D4 | R4 | R1 recorded three deliberate divergences from the TypeScript router with **no parity vector**. R4 must not read their absence as agreement |
| D-h | Rename `callsServed` to what it measures, across router, control API, client and surfaces | R4-C | R2 D6 — it is an *acquisition* counter, not a served-call count. Wire-visible, so F3 and the Mac surfaces move together with it |
| D-i | Fix the lost router restart in the TypeScript watcher | — | R2 D7 — a latent bug in the **reference**: an adopted server can never reach the running router. Declared so the Swift watcher does not reproduce it |
| D-j | Wire `AuthRoutes.approve` and `AuthRoutes.authStart` into `ControlHandler`'s dispatch | R3 | Both implemented, both unreachable over the wire, both answering 405 where the reference answers 409/400. **Blocks 2 parity rows.** Fixing it also retires `control-differential.sh`'s stale known-defect assertions in the same change (`D-r2r-c`), or the gate goes red on a *fixed* defect |
| D-k | Swift implementations of the remaining CLI verbs | R2-R ✓ / R4-C | `serve watch import index refresh status tools auth usage help`. R2-R shipped the CLI and proved 8 of 10; `import` and the `~/.claude.json` rewrite remain. **Blocks 3 parity rows** |
| D-l | An SSE differential for `GET /usage/stream` | R4 | The body is an open stream, so there is no byte oracle. Framing agreement is not body parity. **Blocks 1 parity row** |
| D-m | A recorded oracle for `registry/search` | — | The reference calls live registries; two runs a second apart differ. Either record a fixture-server registry or accept the route as permanently uncomparable. **Blocks 2 parity rows** |
| D-n | Derive the `cli` and `mcp` manifest rows from source | R4 | `src/index.ts`'s ten `case` arms and `src/router.ts`'s endpoints are mechanically extractable. Until they are, **42 of 82 rows are hand-maintained and deleting one raises the coverage figure** — the gate's own worst failure mode |
| D-r2r-a | `mcp-router tools` has no empty state | R4-C | `DESIGN.md` §5 wants one sentence and one action; the reference has no empty branch, so adding it is a *divergence* on an owned row until the cutover happens |
| D-r2r-b | The control API has never been compared **over a socket** | R4 | `control-differential.sh` drives `ControlDiff`, an in-process oracle. R2-R made `ControlHandler` reachable over a socket for the first time and **that surface has no lane** — 11 `control` rows are proven against an oracle that is not the wire |
| D-r2r-c | Retire the stale known-defect assertions when D-j lands | D-j | Same change or the gate reports a failure *because* the defect was fixed |
| **D-p** | ~~`RegistryEnrichmentTests` is flaky~~ — **CLOSED `1cb3fd7`, and the label was wrong** | — | **It was a data race, not a flake.** `StubHTTP` is `@unchecked Sendable` with a plain `var requested: [String]` appended from `get()`, and `Registry.search` queries the official and smithery registries **concurrently** — two tasks appending to one array unsynchronised, under an annotation promising exactly the safety the class lacked. A lost append presents as *"that URL was never requested"*. Fixed with an `NSLock` (scoped `withLock`; `lock()`/`unlock()` are unavailable from `get()`'s async context). **Filing it as "flaky" was the mistake worth remembering**: flaky invites re-running until green, which would have hidden a real race forever. 8 consecutive full-suite runs, 8 green |
| **D-o** | **The fixture lane's project normaliser drops any project name containing a hyphen** | R4 | `parity-fixture.sh:121` normalises with `"project":"[A-Za-z0-9]+"` — **no `-`, no `_`**. Project attribution is the directory a call came from, so the gate's verdict depends on the *name of the directory it is run from*. Proven: `F3` and `R2R` normalise, `mcp-router` and `my_project` do not. From `.worktrees/R2R` the gate reports **69 of 82, 0 DIVERGED**; from the repo root, on the identical tree, **68 of 82, 1 DIVERGED** (`fixture usage`, `recorded="<project>" live="mcp-router"`). Every runner works in a worktree named alphanumerically, so no runner can hit it — which is why it survived R4's three adversarial reviews and R2-R's re-measure. **The cutover decision will be taken from the repo root**, where the false DIVERGED is what a reader sees. Fix is the character class; the orchestrator did not apply it because it moves the coverage number *up* and that diff should be reviewed by someone who does not benefit from it |
| ~~**M9**~~ | ~~**Rename the `Evals` destination to `Checks`**~~ — **CLOSED inside D2 `9e8a754`; triaged 2026-08-21.** `Destination.title` returns `Checks`; the `rawValue`, `iconName` and `?pane=evals` slug stay `evals` **on purpose**, documented in `Destination.swift` — they are identifiers in frame restoration and every mock link, and §6 governs words a user reads rather than keys a machine matches. Original filing: | M1, M7 | M7's residual objection, which it could not fix from inside. Every *reading* on both panes is an observation with its input beside it and the vocabulary carries no grading verb — but the word `Evals` in the sidebar, window title, menu and deep link still says "test results". `Destination.title` is a merged shared surface, and a runner editing one unilaterally is how a shared surface stops being shared. M7 filed it rather than took it |
| ~~M10~~ | ~~Amend `DESIGN.md` §6:279–280~~ — **CLOSED inside D2 `9e8a754`; triaged 2026-08-21.** §6 now carries the correction and its reason: the old illustration named a state the product cannot be in, because there is no eval runner anywhere in it. Original filing: | M7 | Its mandated "not evaluated" skill string describes a state that no longer exists. `DESIGN.md` is authoritative and merged; F2's parity gate tests tokens *against* it, so it and the code cannot drift — which is exactly why a runner does not amend it alone |
| ~~M11~~ | ~~Regenerate `spec-M1.md`'s command inventory~~ | — | **Promoted to a ledger item and merged `2a434b9`.** Its A22 half is closed; what it uncovered is now **M13** (the A34 scroll edge) and **D-m11-a** (the freshness check that blocks after a rebase) |
| M12 | Staleness and an as-of time inside a destructive dialog — **still open, measured 2026-08-21**: `CleanupSheets.swift` draws `Remove <name>?` with a consequence figure carrying no staleness marker and no as-of time | M7 | M7's Phase D findings 4 and 8, both VALID. A `.stale` reading is shown in the present tense with no marker, and calls accruing between load and POST are discarded uncounted — so the figure is a lower bound presented as a count |
| **M5-a** | Router-side registry snapshot store, and the trending band it makes possible | R3 (control), M5 | The only honest route to a velocity figure: the router is the process that runs continuously. Until it exists the Discover footer names the absence rather than inventing a number |
| M5-b | Registry search for skills and marketplaces | M4, M5 | The prototype's Servers/Skills toggle has no endpoint behind it. Needs a router route before any UI |
| M5-c | GitHub token in settings, to lift star coverage | M8, M5 | `GITHUB_TOKEN` raises the unauthenticated 60/hour limit; the footer currently just explains the shortfall |
| **M5-d** | **An `axkit` verb that can press a non-`AXButton` role** | — | A harness limit, not a product gap. `axkit press` matches `AXRole == "AXButton"` only, so no rendered pass can drive a segmented filter. Raised by M5, predicted to hit M7's two boards, and it did — M7 confirmed it and declared it rather than faking a press |
| R13 | Router-side behavioural eval runner — **servers only** — *filed as R6 and renumbered 2026-08-21; that id belongs to the child-PATH item on `ai/r6`.* | R3, R4 | The router can start a server and call a tool; it cannot execute a skill. A runner promising both would promise something the product does not do |
| R11 | Skills write endpoint (remove/disable) with preconditions and undo | R3 | **Filed as R7 and renumbered 2026-08-21 — that id was already a top-level ledger item.** Cleanup lists absent skills and can offer no action on them, because the control API is read-only for skills. M7's A16 asserts that gap rather than hiding it, and `CleanupSheets.swift:204` still draws `DisabledAction(label: "Remove", reason: CheckCopy.skillRemoveDisabled)` — so the gap is live and this item is genuinely open |
| R12 | Server soft-delete with a restore endpoint | R3 | **Filed as R8 and renumbered 2026-08-21 — that id belongs to the merged auth-rejection item (`ai/r8` → main).** Removal is irreversible today, which is why it needs a named-consequence dialog |
| M13 | The scroll-edge separator, A34 | — | **Promoted to a ledger item and merged `08b9bdf`** — its full row is in the main table above. A complete nine-column row had been pasted into this four-column register, where its cells read as `Absorbed by: mac` and its outcome as a dependency list. Replaced 2026-08-21 with a register-shaped row. |
| D-m11-a | The A22 freshness check blocks after a rebase and cannot be cleared | M13 | M11 added an oracle/binary skew check comparing SOURCE MTIMES against the built app — correct in intent and it caught a real skew. But **a rebase rewrites source mtimes without changing content**, so `xcodebuild` rightly does not relink, the binary keeps its old mtime, and the check blocks forever: the orchestrator hit this immediately, and `make build-mac` exiting 0 does not clear it. Clearing it needs the derived Debug product deleted and a full rebuild. Compare content (a hash of the menu sources baked into the build, or the binary's own build id) rather than mtime — **rebase-then-gate is the orchestrator's standard cycle, so an mtime check blocks every merge** |
| D-m11-b | Menu commands render enabled but no-op with the window closed | M1 | M11's critic finding H2, accepted as a finding and deliberately not fixed. With the app running and no window, `@FocusedValue` is nil so the command does nothing. Reverting to `.none` there would falsely claim the surface was never built; the residue is pre-existing for the 16 always-enabled commands and belongs to `ShellCommandRouter` |
| D-w1 | Nothing renders `watch.log` | M2 or M6 | A repeatedly-failing server is **invisible**: the watcher records it and no surface reads it. The adoption protocol is the one part of the product with no window onto it |
| D-w2 | `ImportVerb.swift:22` uses `NSHomeDirectory()` where the reference honours `$HOME` | R4-C | Out of scope for R2-W and currently unreached, because `cli-import` passes `--from`. It diverges the moment anything calls it without one |
| D-w3 | `manifest.json`'s other writers are still unlocked | R3 | R2-W closed the **seconds-wide** window between the watcher and the daemon. The **microsecond** one between R3's and R5's writers remains, and it is the harder half |
| D-i3-g | The Triage commit button says **"Send"** where nothing sends | I3 | The phone queues; the Mac decides. A11 specifies that string **verbatim** and it passed the spec gate, so I3 declined to rewrite it unilaterally. A **spec-level** fix |
| D-i3-h | Decided buckets are the intersection with the current results page | I3 | So the Dismissed empty state claims a durability it does not deliver — dismissals appear to vanish when the page changes. Also spec-level |
| D-i3-a | No phone surface scales with Dynamic Type | — | `TypeToken.font` is a fixed `Font.system(size:weight:)` **shared with every Mac surface**, and `DESIGN.md` §2 fixes the eight sizes deliberately, so this is a shared design decision rather than a bug in any one item. I1's Dynamic Type test **overrides a UIKit trait that measurably never reaches the SwiftUI view** — I3 deliberately did not copy that pattern |
| **D-m6-a** | **Pairing transport: the wave-6 round-trip gate is explicitly NOT met** | I4 | M6 reported this rather than claiming it. The Mac side of pairing exists and the round trip has never been proven end to end against the phone. Folded into **I4**, since direct install cannot be built on an unproven transport |
| D-m6-b | Envelope versioning for the pairing protocol | I4 | No version field, so a phone and a Mac on different builds cannot detect the mismatch; they just misread each other |
| D-m6-c | Rename `ScaffoldPane.swift` | — | The file no longer holds a scaffold; it holds the registry. Five other items’ acceptance scripts read it by name, which is why M6 declined to rename it alone |
| D-m6-d | The popover has no inbox band | M6 | The menu-bar popover is the app’s most visible surface and the one place a queued item should appear without opening the window |
| D-m6-e | An accent-substrate token | M6 | M6 hand-rolled a `0.16` selection alpha where every other row uses the shared `selectionFill`; the fix is a token, not a constant |
| D-m6-f | `CleanupPresentationTests.weakWindowBoundary` | M7 | M7’s merged file, outside M6’s diff. Mechanism recorded, not re-run until green |
| D-m6-g | The readout repaints the whole window once a second | M6 | A cadence problem rather than a correctness one, and the acceptance script works around it by re-walking a fresh element |
| **D-v1a** | **The control API's writes never reach the live process** | R3 | `controlResponse` discards the `deps` it passed `inout`, so a write lands nowhere the running router can see: **`POST /servers` answers 201 and `GET /servers` still lists the old set.** Found by the grok review; **it was in no register**, which is the whole argument for the out-of-family lane |
| D-v1b | The usage debounce is declared and never scheduled | R3 | The timer exists in the type and nothing ever arms it, so every record writes through |
| D-v1c | B52's missing warning | R3 | The clause specifies a warning the code never emits |
| D-v1d | Attribution does not complete inside accept (B68) | R3 | The same class of race F3 hit from the other side; the caller lookup can still finish after the response |
| D-v1e | A `JSToNumber` radix edge | R1 | Diverges from the reference on a narrow input class |
| D-v1f | The watcher's staging rewrite is unlocked | R2-W | **Deliberately left**: it matches the reference's own window, so closing it is a NEW declared divergence and R4's call rather than a fix |
| **D-v1g** | **B23 and B44 are wrong as written** | R4 | Two real divergences are missing from R4's D-table. A divergence absent from the table reads as agreement, which is the parity harness's own worst failure mode |
| M14 | A shipped menu tells the user the app is not built | — | **Promoted to a ledger item and merged `7e7ed70`** — its full row is in the main table above. A complete nine-column row had been pasted into this four-column register, exactly as `M13`'s was; that one was found and replaced on 2026-08-21 and this one, four rows below it, was not. Found by `ledger-reconcile.py` check J, which reads the direction H does not: a row parsing to MORE cells than its header. Replaced 2026-08-21. |
| D-p1-a | OAuth client behind `AuthTransport` — and, from the stray row now folded in, `control-auth-post-http` needs a hand-written OAuth client, not a harness change | new item | P1's owner note: must be a NEW item, not R2 (merged) or R4-C **Merged 2026-08-21 from two rows sharing this id**: a register-shaped stray in the item table said — open, blocked, **triage verified** — P5 checked the inherited triage rather than accepting it. The **only** conformer to `AuthTransport` anywhere is `FakeAuthTransport` in the *test* target, so the 405 is real; and the vendored swift-sdk emits `state` **unconditionally** while `extractCode(from:expectedRedirectURI:expectedState:)` hard-guards on it, so the SDK **can neither produce the reference's byte string nor work without it**. Closing it means discovery, dynamic registration, PKCE and a callback on :8880 — router work, sized as its own item Neither side was taken wholesale; which reading is current is a judgement about what shipped and is not made here. |
| D-p1-c | `awaitCompletion` reports a settled flow as absent | R3 | Turns a **successful** auth into a warn with no re-index |
| D-p1-d | `cli-auth` needs a serve-backed row and an OWNED entry | R4 | Comparing it today compares two connection failures agreeing with each other |
| D-p1-e | **`install-launchd-watch` is unstable on BOTH binaries** — and, from the stray row now folded in, **`install-launchd-watch` withdrawn: its `reran` term does not measure what it claims** | R4 | Six runs, losing side alternating, agreed 1 in 6, while the control lane read 53/53 every time. **Not filed as flaky** — that label invites re-running until green over a real race **Merged 2026-08-21 from two rows sharing this id**: a register-shaped stray in the item table said — open, blocked — **The series held and the mutation broke it.** P5 reproduced the dead runner's eight pairs with eight of its own — sixteen observations, every one agreeing on all four terms at loads 5.5–10.3 — then ran the mutation itself **because it could not inherit an unwitnessed demonstration**. `oneshot` discriminates: a resident Swift program reads `yes,no,no` and the lane exits 1. `reran` **does not**: pointing the agent's `WatchPaths` at a decoy in a fresh `mktemp -d` the lane never touches, with the generated plist dumped to prove the mutation took, gave 4 of 6 trials correctly red and **2 of 6 spuriously green, byte-identical in the report to a genuine first-delivery re-run**. The gate runs this lane once, so **a watcher that never re-ran would have recorded green about one run in three**. THE LESSON, GENERAL: *a series bounds the AGREEMENT rate; what is broken here is what the term MEASURES, and no number of agreeing runs can find that.* Grok returned REVERT independently on the same contradiction. Every code improvement is KEPT — launchd's own `runs` counter, the settle predicate, restaging, the evidence line. The row note's stated limit (*fires on churn in the file's directory*) is **also wrong, measured**: a decoy in its own private directory went green twice, so the measured rate replaces the theory The stray is the later reading and supersedes on its face; both texts are kept because neither side is taken wholesale. |
| D-p1-f | 405 vs 501 | owner | Two grok reviews disagreed; the owner's call |
| D-p1-g | `currentFlow` unset in the daemon | R3 | — |
| D-m13-a | Boards render vertically centred, not top-aligned | D2 | `.frame(minHeight: sidebar*3)` with the default `.center` puts the Servers board **~208pt down the pane**. One word to change and seven boards to re-verify |
| D-m13-b | `SettingsBoard` nests a ScrollView inside the shell's | D2 | `SettingsBoard.swift:70`, absent from `boardsThatScrollThemselves`, which contradicts M2's B41 |
| D-m14-a | Per-command `.featureUnbuilt` copy | M1 | Needs an associated value, which breaks `==` at six sites, or moving reason resolution onto `MenuCommand` |
| D-m14-b | `⌘E` is still bound to a permanently dimmed command | M1 | Pre-existing and inert; it becomes live the day export ships |
| D-m14-c | `Export library…` keeps an ellipsis promising a view that does not exist | M1 | M1 chose the title and `ellipsisRule` pins it, so changing it is M1's call |
| ~~**OWED**~~ **DISCHARGED** | `mac-shell.sh` full green on an idle machine | — | Carried since M14 and closed by G1 at `8cfb9e3`: **exit 0, 39 assertions, at load 65**. Recorded rather than deleted because the route mattered — the gate was re-run three times across two items, gave three different answers, and the orchestrator declined to re-run it until green. It was a harness defect the whole time |
| **D-p1-e** → G1 | **`install-launchd-watch` now reports DIVERGED on main** | G1 | Promoted from deferred to blocking. It is `proven` in the manifest, and a proven row whose lane disagrees reports **DIVERGED** — worse than blocked. Main now reads 76 or 77 of 83 depending on the run, and both orchestrator runs had the **reference** as the losing side. P1's recommendation stands: mark it blocked until the lane waits on a launchd observable rather than a fixed delay |
| **D-p3-a** | **A lane script that exists but is not dispatched is invisible** | G1 | Found by P3: `parity-stream.sh` was executable and passing by hand while being run by nothing, for the whole life of the harness. P4's orphan detection catches a ROW with no lane; this is the inverse — a LANE with no dispatch — and nothing catches it. `parity-manifest-check.sh` should assert that every `parity-*.sh` lane script on disk appears in LANES, or is explicitly listed as deliberately unwired |
| ~~**D-g1-g**~~ **CLOSED, MECHANISM CORRECTED** | Two parity runs on one machine | D1 `997f7af` | Recorded from G1 as *silent* corruption. **D1 reproduced it three ways and it is not silent** — every collision path exits 2 and names the port. What was actually wrong: the gate printed a coverage fraction for a run that never measured the surface. Fixed by withholding the fraction plus a real lock. **Fifth time a runner's measurement has corrected this orchestrator's brief**, and the reason the row is rewritten rather than ticked |
| **D-r2r-b** ↑ | **Confirmed and WORSE than recorded** | new item | `parity-gate.sh:280` claims the control lane compares on the wire; **that is false for the Swift half.** D1 promoted it rather than half-doing it. R2-R-sized |
| **D-p4-a** ↑ | **Upgraded: the row has now moved a full gate run** | open | Recorded as "not filed as flaky". An intermediate D1 run at **load 612** read 77/83 with 1 DIVERGED on `div-r2-d6`. D1 did **not** re-run until green: it ran that lane 3× in isolation (3/3) and the full gate once (78/83/0). Contention, named rather than relabelled |
| D-g1-g-b | Residue from the lock work | open | Reclaim race and the `mkdir`→pid window, both found by the grok critic and both fixed; the residue is recorded in spec-D1 |
| D-d1-a | Three parity rows remain undemonstrable | open | Failability is 16 of 19. The three are recorded as undemonstrable rather than quietly counted, which is what took the roll-up from 11 |
| **CAPACITY** | **Three consecutive runner deaths on `503 over_reserve`** | orchestrator | G1's first attempt, then D2 and D1 together. **Not a fast failure**: wave 3 ran 24 minutes and spent ~592k tokens before dying, so a blind relaunch risks paying that again. A one-word `claude -p` probe is a known WEAK ORACLE here — it returned OK once and a four-runner wave died immediately after. **Retry when the pool recovers rather than probing**, and prefer ONE runner at a time until a wave completes cleanly |
| **MERGE ORDER — R17 AND R19 CONTRADICT EACH OTHER ONCE BOTH LAND** | **One branch declares a divergence the other closes** | orchestrator | Flagged by R19's runner, 2026-08-22. `ai/r17` adds a `surface.tsv` note declaring the Swift/node manifest read-window divergence as something its `cli-watch` lane cannot reach. **R19 closes that window by convergence** — node's `buildManifest` takes a required commit hook so it re-reads per entry before saving, which is what Swift already did — so the declaration is **false the moment both branches are in one tree**. Neither branch can fix it alone: R19's base predates the note, and R17's scope carries no code. **Whichever merges second must delete or rewrite that note in the merge**, and the merged tree's `parity-gate.sh` divergence count moves with it. R19's verifier has been asked to state the ordering explicitly, because this is the orchestrator's to serialise and getting it wrong ships a declaration that contradicts the code beside it. |
| **GATE — `ledger-reconcile.py` CHECK E FALSE-REDS FROM A WORKTREE** | **Every runner runs the reconciler from a worktree, and check E is not sound there** | G4 | Measured 2026-08-22, reproducible on demand: the script exits **0** from `main` and **1** on `E — G5 (ai/g5)` from `.worktrees/R17`, same commit of the script, same moment. Two gaps between the check's name and its reading, firing together. **(a)** A branch with **no commits** is an ancestor of `main`, so `git branch --merged main` lists it the instant it is created — `ai/g5` was cut from `2fbe062`, committed nothing, and `git rev-parse` confirms its tip *is* a main commit. **(b)** It compares a **live, repository-global** branch list against **branch-local ledger files**, and every worktree is on an older base than `main`, so the row for a newly-filed item is missing there by construction. **Direction is false-RED.** R17's gap-fix 3 runner hit it and read it as *another session merged `ai/g5` into main* — the natural reading, and wrong; it then proved its own edit was not the cause by restoring `ORCHESTRATOR.md` to `HEAD`, re-running and getting the identical finding. **A check whose false positive reads as "somebody else broke main" costs more than one that reads as noise.** Registered as `D-g4-b` and filed as G4's twelfth instance. **A check-E finding naming a branch created after this worktree's base is this, not a defect** — confirm from `main` before acting on one. |
| **GATE — `parity-manifest-check.sh` FALSE-REDS, AND NOBODY CAN STATE THE CONDITION** | **The gate reds on an unchanged, git-clean file. Three passes have each stated a reproduction rate the next measurement contradicted.** | R19 | **The defect is real and proven.** `parity-manifest-check.sh:431` and `:437` pipe a `printf` into `grep -qxF` per item and read **any** non-zero exit as *not found*, with no way to tell a genuine miss from a `grep` that failed to spawn; `:189` is the same shape for the cli list. Direction is **false-RED**. **The condition is NOT a fixed concurrency, and every attempt to name one has been refuted by the next.** Measured, in order: gap-fix 2 reported ~a quarter to a third of ~60 runs, flat. The third verification measured **0 of 40 serial** and **53 of 104 / 24 of 72 at 4 concurrent**. Gap-fix 3 re-measured and got **29 of 80 at 4 concurrent**. The fourth verification then ran **368 invocations on a quiet tree** and got **0 of 40 serial, 0 of 80 at 4×, 0 of 96 at 8×, 0 of 96 at 16×, and 1 of 96 at 32×** — the single red on a git-clean 24-file fixture directory, which is what proves the defect. **The controlling variable is total machine pressure, not this gate's own concurrency**: the high rates were all recorded while other sessions were loading the box. **Do not read any of these rates as a recipe** — a register row stating a rate is how the last three passes each inherited a number the next disproved. **The both-directions contradiction** (ten fixture names reported simultaneously as *on disk with no row* and *carries a row, not on disk*) **has not been re-witnessed** since the third verification; the fourth got direction A only. It stands on that pass's report rather than on independent reproduction, and is recorded as such. **Operationally**: read any manifest-check red seen while other work is running as unproven, and re-run it on a quiet machine before acting on it. |
| **DISPATCH — BASELINE PROVENANCE** | **A brief's gate line is copied from the last report read, not measured against the base the brief names** | orchestrator | Four instances on 2026-08-22, all the orchestrator's. **(1)** `make test` stated as `1686/210` in the M15, M21, R19 and G4 briefs; that is `ai/r17`'s figure, and `ai/r17` is **16 commits ahead of main**. Both M21's and G4's runners independently measured **1684 in 209** at their main-based bases, and G4's flagged the two-test gap as unexplained because the brief told it to expect more. **(2)** lint stated as `531 files`; the base is **530**. **(3)** the briefs named `scripts/acceptance/no-raw-design-values.sh`, which **does not exist** — the script is `scripts/lint/no-raw-design-values.sh`, which is what `make lint` invokes. **(4)** R17's brief set `reconciler 0 across A-L` on a base carrying only A–K. **This is `G4`'s own defect class**: a figure named for one quantity and read from another, and it is filed as an instance there. The fix is mechanical and belongs before dispatch — **run the gate line against the brief's stated base and paste what it returns**, rather than carrying a number across branches. A runner cannot tell a wrong baseline from a regression it caused, so every one of these spends a runner's attention proving the orchestrator wrong. |
| ~~`main`'s `make lint` was RED — 2026-08-22 ~17:1x~~ **CLEARED `92a348d`** | G4's two new gates were green on their branch and red beside other verified work — the fleet's **fourth merge-only break** | G4-B, verified `bc41e13`, merged `92a348d` | Kept as the record of the class, not as a live hazard. Both causes were G4's own doctrine broken by G4's own gates: (1) the three RAW arms built a scratch tree from a **hardcoded directory list** and M15 widened `GEOMETRY_DIRS` to four, so `no-raw-design-values.sh` exited early and each arm honestly reported it could not discriminate; (2) `reader-accounting.py` **walked the filesystem instead of `git ls-files`** and reddened a shared branch over another session's untracked work-in-progress. **The standing lesson is the second one**: a gate that walks the working directory reports on whoever last ran it rather than on the repository, and every gate added here should enumerate `git ls-files`. Merged-tree gates after the fix: `make lint` 0, 28 armed / 0 held, reader-accounting 0, reconciler 0 across A–L. |
| **DISPATCH — DO NOT ASK A RUNNER TO WAIT FOR `make all`** | **Two runners have now ended their turn waiting for it, leaving uncommitted work and a report that reads like a stall** | orchestrator | Measured 2026-08-22, twice on the same item. `make all` takes **30-40 minutes** end to end on this box under load. G4's gap-fix runner reported its state and exited mid-run, saying it would write §6 and commit once the gate landed; the orchestrator committed its work and the progress note shipped with the literal string `GATES_PLACEHOLDER` in its evidence section. G4 gap-fix 2 then did **the same thing again** — *"waiting on `make all` … the waiter will re-invoke me when it exits"* — and there is no re-invocation: a `claude -p` runner that ends its turn is gone, and its edits sit uncommitted in the worktree. **The failure is not the wait, it is that the runner's last act is a promise rather than a commit.** Two fixes, both cheap: acceptance that needs `make all` should say **commit first, then run it and amend**, so the work is never held hostage to a 40-minute gate; and where the result is already established (G4's `parity-selftest` red-at-base was proven twice from `git archive`), the criterion should cite it rather than demand a re-run, because re-running a settled 40-minute gate to paste a known number is ritual rather than evidence. **The orchestrator now runs `make all` itself** when a runner needs its output, and hands the numbers over. |
| **DISPATCH — RUNNER CONTEXT** | **`--model claude-opus-5` is the wrong model for a runner in this repository** | orchestrator | Measured 2026-08-22, and it is the cause the PROMPT CEILING row below only saw the edge of. A runner on plain `claude-opus-5` gets a **200k** window, and this repository's MCP configuration puts roughly **200 tool schemas** into every runner's system prompt before it reads a line. M21 died twice with `Prompt is too long` — once at its first turn on a 4.5 KB prompt, and once **after three minutes of real work on a 240-byte pointer prompt**, having committed nothing. A one-line probe answered in the same worktree both times, which is what makes this look like a prompt-size problem when it is a context-budget problem. **Dispatch runners on `--model 'claude-opus-5[1m]'`**, quoted — the brackets are shell globbing characters. The premium applies only above 200k, and a runner that dies at minute three costs more than the premium. The failure is a clean exit 1 with no partial work, so it reads exactly like a runner that started and did nothing. |
| **DISPATCH — PROMPT CEILING** | **A runner prompt over ~3.6 KB dies with `Prompt is too long`** | orchestrator | Measured 2026-08-22 on three launches into fresh worktrees. R17 gap-fix 2 at **3556 bytes** ran; M21 at **4547 bytes** failed twice with `Prompt is too long` and exit 1; the same prompt truncated to its first 40 lines (~2.2 KB) ran. A one-line probe in the same worktree answered, so the worktree is not the variable. The base a `-p` runner already carries — system prompt plus the router MCP's ~200 tool schemas — leaves roughly this much room, and the failure is a **clean exit 1 before any tool call**, which reads exactly like a runner that started and did nothing. **Write the work order to a file in the worktree and dispatch a short pointer to it.** That is also the doctrine the fleet already follows for everything else: the artifacts are the memory. |
| **DISPATCH — BACKGROUND CWD** | **A backgrounded runner inherits the session's cwd, and the harness's `Session cwd remains …` line can be wrong about which** | orchestrator | Measured 2026-08-22. A runner dispatched with no `cd` in its own command launched into the **main checkout** carrying a brief scoped to a worktree, while the harness notice named the worktree. Caught at 4 seconds by `lsof -a -p <pid> -d cwd` and killed before it read or wrote anything; `git status` unchanged. This is the same mechanism that destroyed uncommitted work earlier in this fleet, reached from the other direction. **Always `cd <absolute path> && claude …` inside the backgrounded command, and then read the pid's cwd back — never the notice.** |
| **DISPATCH — WORKTREE SUBMODULE** | **`git submodule update --init` in a worktree breaks every runner dispatched into it** | orchestrator | Measured 2026-08-22. Populating `.claude/plugins/fledgeling-plugins` puts **546 MB** of plugin skills where Claude Code loads them, and the runner dies on prompt length. The main checkout survives it only because `.claude/settings.local.json` curates which plugins load, and that file is untracked so no worktree has it. **Every existing worktree leaves the submodule uninitialised on purpose** — `R17` and `R7` both read 0 B. `git submodule deinit -f` reverses it. |
| **MERGE HAZARD** | An untracked draft in the main tree refuses the merge that would replace it | orchestrator | Real for **D1**: its merge aborted on `planning/specs/spec-D1.md`, the dead run's 8.9k draft blocking the branch's finished 20k one. Preserved, checked to be a strict subset (no `D-` id lost), then removed. **I predicted D2 would hit this identically and it did not** — D2 never committed its spec or plan, so there was no collision. The orchestrator committed them separately instead, because spec-D2 is 21KB holding the measurements and the reasons three rows were refused, and the ledger cites it. **The hazard is real; my rule for when it fires was wrong** |
| **ORPHAN-SCAN MARKERS ARE NOT EVIDENCE OF DEATH** | A background scan reported wave 6 `stopped` with no completion record, and instructed a `resumeFromRunId` replay | orchestrator | **All three claims were wrong.** P5's transcript grew 8KB in the 45s it was watched and D3's had been written 1s earlier — the run was LIVE, and a resume would have started a second concurrent run against their worktrees. The journal read `started=3 results=0`, so replay would have recovered nothing and cold-started all three (the miss flag is sticky, replay is a prefix). And the item it named, `TICKET-123`, **exists nowhere in this repo** — wave 6 is P5, I4, D3. Only I4 was genuinely dead, and it got a fresh launch rather than a resume. **Establish liveness from file mtimes before believing any notification.** Note the probe that misled once here too: a workflow DIRECTORY's mtime does not change when a transcript inside it is appended, so a dir-level freshness check reports a busy fleet as idle |
| ~~**D-g1-b**~~ **CLOSED — NOT A PRODUCT DEFECT** | m8 A9: a disabled control carries no reason | D2 `9e8a754` | Registered from G1 as a real product finding. **It was the check.** Measured live the control reports `enabled=1`, empty help, and no "There is no stored token" anywhere, so the old unconditional A9 **would have failed a correct app**. Now an assertion about the pairing in both directions, each arm proven by its own mutation |
| **D-d2-lesson** | **Two assertions that could only ever BLOCK, never fail** | closed, recorded | The sweep used awk's `and()`, a gawk extension macOS awk lacks. It passed every green run **and its own mutation**, because `&&` short-circuits and the call was never reached until a real violation arrived — at which point the script exited **2 BLOCKED rather than 1 FAILED**. Premise verified independently: macOS awk answers `calling undefined function and`, and the merged code now does the bit test in POSIX shell arithmetic, touching awk not at all. Second: a `x > 450` threshold matched **zero** scroll areas because AX positions are screen-absolute, so it would have passed by finding none of what it forbids. **Both are the gates-that-lie family and both were caught by mutation, not by review** |
| D-d2-a | 13 out-of-scope children remain in spec-D2 §6 | open | Unchanged by this item and listed rather than silently carried |
| D-d2-b | `parity-lane-selftest` reports an honest SKIP with no `dist/index.js` | open | Inherited, not introduced by D2 |
| ~~D-g1-e~~ **SUPERSEDED — it is three, not eight** | ~~Eight parity rows have never been shown able to fail~~ | closed by D1's measurement | True when G1 raised it and **stale since D1 merged**: `D-d1-a` records failability at **16 of 19**, so **three** rows remain undemonstrable rather than eight. Left as a strike-through rather than deleted because the headline number was quoted onward. **Found by P6, which flagged it and did not edit it** — the register is the orchestrator's to move, and a runner correctly declining to move it is the behaviour we want |
| D-g1-a | `GET /usage/stream` races on caller attribution | R3 | `D-d`; did not reproduce serially, registered not closed |
| D-g1-c | m8 fails on ANY focus change | new item | Rather than on this app taking the screen, which is the rule |
| D-g1-d | i2's placeholder claim is asserted by construction | D3 | Not mutation-proven |
| D-g1-f | The iOS stamp has no consumer | D3 | — |
| D-p3-b | `fixture-registry-search` is now `accepted-uncomparable` | R4-C | Not a defect. Recorded so the cutover's target is read correctly — it is now **82 of 83**, this row being the excluded one: this row can never be byte-compared, and pretending otherwise later would be a regression |
| D-p4-e | `parity-manifest-check.sh` counts one problem as two | G1 | Its counter counts `note` calls and each finding emits a message plus an explanation. Cosmetic, but it inflates a number in a gate whose whole purpose is that numbers are not inflated |
| D-p2-a | Neither Swift writer locks `~/.claude.json` | new item | P2 declined deliberately; see its row |
| D-p2-b | `install.sh` still calls node for the claude.json rewrite | R4-C | `install-claude-json` being green is explicitly **not** evidence that the caller flipped |
| D-r6-d | A colon in a discovered directory name injects a RELATIVE PATH entry | new item | Measured: a scratch home containing `.with:colon/bin` gave a child PATH whose appended entries were `$HOME/.with` and `colon/bin` — the second relative, resolved by `execvp` against the child's cwd. Both routers do it identically so parity holds. Same hazard class the spec reasoned about when it chose to keep empty PATH components, and unguarded. One-line fix: skip any candidate containing `:` |
| D-r6-e | The two routers disagree on PATH dedup for non-ASCII names | new item | **A7 is falsified.** Swift's `Set<String>` dedups by Unicode canonical equivalence; JavaScript's `Set` dedups by code units. With the inherited PATH naming `$HOME/.café/bin` precomposed and the directory on disk spelled decomposed, Swift handed the child 5 entries and Node 6. R6 went to explicit trouble to make the SORT byte-based for this exact reason and missed the DEDUP |
| D-r6-f | spec-R6.md §9's load-bearing sentence is false under symlinks | R6 | *"Every directory added is inside `$HOME`"* — not when a discovered `bin`, or its parent dot-directory, is a symlink pointing out; `fileExists(atPath:isDirectory:)` and `statSync` both follow. It matters because §9 is the written argument the owner is asked to rule on as `D-r6-c`, and as written it understates the exposure. The code need not change; the sentence the decision rests on should |
| D-r6-g | A router started with no `PATH` at all loses `execvp`'s `_CS_PATH` default | new item | It now hands children an explicit `PATH=<discovered>` or `PATH=`, losing the implicit `/usr/bin:/bin:/usr/sbin:/sbin`. Demonstrated by the codex lane under `env -i`. Not reachable from a launchd-installed router, which is why it is a follow-up rather than a block |
| D-r6-h | Two soft assertions in the R6 acceptance lane | G1 | The red half captures `before_status`, prints it and never asserts on it — a router that emits the expected ENOENT line then crashes with 139 still reports `ok`. The ordering check is a byte prefix, so `${LAUNCHD_PATH}.corrupt:…` passes |
| D-r6-i | The 64-directory cap truncates silently, in byte order | R6 | A home with 70 `.capNN/bin` directories dropped `.fixture/bin` from the PATH and the child never saw it — no diagnostic. **The same silent-capability-loss shape the brief was filed about**, reintroduced by its own fix's guard rail |
| D-r6-j | `D-r6-a`, `D-r6-b` and `D-r6-c` were registered only inside spec-R6.md §10 | R6 | Including `D-r6-c`, which is an explicit owner decision. The ledger row did not name them, and this repo's convention gives a deferred child a register row. Fixed by these rows |
| D-r6-k | `commandNotFound`'s directory count excludes the empty components R6 preserves | R6 | Computed with `omittingEmptySubsequences: true`, so the number is not the length of the PATH the child actually received. A diagnostic that disagrees with the thing it diagnoses |
| D-r10-a | `ManifestIO.save` races on its temp path | new item | The temp is `manifest.json.tmp-<pid>`, so two concurrent `index()` calls in one process race: A's rename can carry B's bytes and B then reports a `cacheFailure` for a row that is on disk — **a false refusal**. Root cause is in `ManifestIO.swift`, outside R10's declared scope; the CLI verb walks upstreams sequentially and cannot reach it |
| D-r10-b | `import` still prints the false green `index` just lost | R7 | `ImportVerb.swift:109` prints `ok <name> (N tools)` and reads neither `cacheFailure` nor `heldChanges`, so it can adopt a server and exit 0 with no manifest row. Fenced out of R10 expressly; verified unchanged |
| D-r10-c | The `lost` line points the reader at a file that never existed | R10 | Its reason is `error.localizedDescription`, a localised NSError sentence naming the *temp*: *"You don't have permission to save the file 'manifest.json.tmp-31931'"*. A reader who goes looking for that file will not find it |
| D-m27-a | A35 now tolerates the head rather than requiring it | new item | Widened to `^(Child processes, )?[0-9]+ of [0-9]+ declared servers running$`, so **A35 alone can no longer tell M27's fix from the defect it closes** — measured under mutation B. The new `sidebar_count_announcement` assertion does distinguish them, so the branch is covered; A35 is not the thing covering it |
| D-m27-b | Three failure-state absence checks can pass over an empty geometry domain | G1 | `axkit` prints `-1.0` for an unreadable AXSize, so `sidebar_bounds` returns L=0 R=-1, `[ -n "$STATE_SIDE_L" ]` passes on `0`, and every range predicate matches nothing. **An absence check whose domain is empty is satisfied by anything** |
| D-m27-c | The gate claims a containment it does not measure | G1 | It says the foot is held *below the card it is the foot of* and *inside the sidebar*, but `LABEL_Y` is the label element's top rather than the card's bottom, so an address drawn inside the card on the label's own row passes |
| D-m27-d | Two evidence claims in the M27 bundle do not reproduce | M27 | *"35 `ok` lines"* — the file it names has **52**, and the verifier's own run produced 52. And `captures.tsv`'s `bundle` column is described as the path the pid was executing; it is the script's `$MAC_APP` variable and is never read back from the process |
| D-m27-e | Two doc comments describe the prototype in the present tense for things this branch removed | M27 | They say it draws a literal `127.0.0.1:8879` and paints a `--live` dot; the same branch removed both from `prototype.html`. DESIGN.md handles tense explicitly and these do not |
| D-m27-f | The zero-count tint change is a third sidebar divergence | M27 | `--live` unconditionally → `--live` above zero, `--t1` at zero. The brief's Scope says a third divergence found while working is recorded and left. The verifier would keep it; recorded so the keeping is a decision |
| D-m23-a | Neither the `structure` nor the `geometry` layer compares anything against the mock | M23 | `structure` corroborates each declared axis against the build's own child geometry; `geometry` checks root size and non-zero frames. A conversion gate with two layers that never read the source |
| D-m23-b | Every node records a resolved colour that no layer reads | M23 | The dump advertises `layers: [… "resolved-colour" …]` and `Context.load` never validates the advertised set against the layers that exist |
| D-m23-c | All four dumps are dark; the mock is light-first | M23 | The gate never passes `--appearance`, so every structure, geometry, copy, type-metrics and breadth measurement in the ledger is dark-only and the light cascade is unrendered |
| D-m23-d | Several numbers in the M23 bundle do not reproduce | M23 | Against its own opening claim that *"every number below is quoted from the run that produced it"*: the ledger is called 173 rows and has 149 breadth + 8 layer rows; `swift test --filter MockToken` is quoted as 2 suites and reports 3 |
| D-m23-e | Two pointers send a maintainer to a file that does not exist | M23 | The lint's new comment cites `scripts/lint/no-raw-design-values-selftest.sh`, which is nowhere in the repo — the arming is elsewhere |
| D-m23-f | The tokens layer poisons the `.build` the MEASURE product links against | M23 | It runs `swift test` in the same SwiftPM `.build` without the `MEASURE` flag, so a run leaves `MCPRouterUI` compiled without it and the next `swift build --product MeasureDump` can fail to link `SurfaceRecorder`. Exits 3 — the right code for the wrong reason. Cost the gap-fix runner two gate runs; cleared by `rm -rf app/.build`. **Read this before running the gate** |
| D-m23-g | The error state's primary action is `state-action-disabled` where the mock draws it enabled | M17 | A real divergence between mock and build, surfaced by the now-honest `present` rule rather than introduced by it. M17 owns the four-states work |
| D-m23-h | `VOUCHED_CONTROLS` covers 8 of the mock's 17 kinds, and each entry is global | M23 | A kind the table does not name cannot be vouched, and an entry vouches everywhere rather than per surface. Honest today because an unvouched pair reads `unclassified`; it caps how much of a surface can ever reach `present` |
| D-m23-i | A role the table does not map is still exempt inside a pair | M23 | G2's quota binds the kinds the census enumerates; a build role outside the table's domain still rides the container's pairing |
| D-m23-j | Glyph identity is still unread | M23 | The parent brief asks for label, control kind AND glyph. The first two are now compared; `<use href="#i-…">` against `IconView` is not |
| D-m23-k | The census arithmetic itself is unchecked | M23 | Nothing asserts that `present + unclassified + divergent + covered-by-pair` equals the enumerated total, so a node lost between classification and report is invisible |
| D-m23-l | An unvouched pairing is filed as `divergent`, claiming a measurement that did not happen | M23 | `if not vouched: status = "divergent"`. The layer's own doctrine says a comparison the instrument could not make is `unclassified`, and *this gate has never vouched for this pairing* is that, not a measured difference. 2 of today's 18 divergent rows are this shape and both are real control differences, so nothing is mis-stated yet — but the nine unmapped kinds `D-m23-h` lists each land here, and **a correct build will read `divergent`**. Taken into the 2nd gap-fix |
| D-m23-m | ~~No node-id uniqueness check~~ **CLOSED, 3rd gap-fix** | M23 | Two siblings sharing an id make `structure` report 8 nodes where the dump carries 9, and breadth never sees the second. Every per-node layer under-counts and the `dumpNodes` floor is computed from the collapsed set, so the ratchet cannot catch it. Raised independently by `gpt-5.6-sol`, and again by it against the third gap-fix as BL-2's own property failing from the node side: a pairing path that names two nodes does not name a control, so `vouched_pairing` vouches for whichever the dict kept. `index_nodes` replaces every `dict(flatten(...))` and exits 3 on a repeated path; 73 flattened and 73 indexed on the real dumps, so it is armed rather than measured |
| D-m23-n | `floors` lives in the manifest the gate reads, unlike `ALLOWED_OPTIONAL` and `VOUCHED_CONTROLS` | M23 | A surface author sets their own denominator in the artifact the gate consumes — the placement both other tables were deliberately moved out of, for the reason `ALLOWED_OPTIONAL`'s own comment gives. `grok-4.6` reached this from the other end of B1 |
| D-m23-o | The token marker's own arithmetic is unchecked | M23 | Every field of `MOCK-FIDELITY-TOKENS` is parsed as the number it claims to be and the literals marker must name `stray=`, but nothing asserts `matched + pending == rows` or that any of them is non-negative. Distinct from `D-m23-k`, which is the breadth layer's classification total; this is the tokens layer's census (gpt-5.6-sol, first-pass finding 6) |
| D-m23-p | `readable()` is a category test plus a codepoint list, and the list is a list | M23 | The category half covers `Cc Cf Cs Co Cn Zs Zl Zp Mn Me Mc` and picks up every future member of those classes; `BLANK_CODEPOINTS` covers the four Hangul fillers and U+2800 BRAILLE PATTERN BLANK and picks up nothing else. Unicode publishes no "renders blank" property, so a blank codepoint in a visible category that nobody has written down still reads as content. The two errors are not symmetric — filtering too much costs a finding that names what was not measured, filtering too little is a false `present` — so the list errs long. Narrowed from the whole `Lo` hole to this residue on 2026-08-21 after `gpt-5.6-sol`, `gemini-3.7-flash-high` and `grok-4.6` each reached U+3164 independently |
| D-m23-q | The `lintFiles` floor is an exact count, so any Swift file added or removed moves it | M23 | Set to 118, the census measured on the run that wrote it, matching how `tokenRows` and `dumpNodes` already work. It means a deleted file exits 3 until somebody lowers the floor deliberately — the ratchet the manifest's note describes, and the cost of it is a manifest edit on every file-count change |
| D-m23-r | An unmeasured run overwrites the ledger, so a transient failure destroys the last good table | M23 | `write_unmeasured_report` replaces `<surface>.ledger.md` with what stopped the run, which is what stops a stale table sitting under a nonzero exit. The cost is that the previous run's rows are gone from the working tree until the gate is re-run — recoverable from git, and the alternative is the failure this pass exists to close |
| D-m23-s | ~~`layer_copy` measures a pairing the gate has never vouched for~~ **CLOSED, 3rd gap-fix** | M23 | `D-m23-l`'s confusion one layer over: breadth files an unvouched pair `unclassified` while copy compares the same two strings and reports a mismatch as a measured difference. Deliberately not closed in this pass — filtering copy's population moves the finding count acceptance criterion 6 pins at 16, so it belongs to the pass that re-pins it. `gpt-5.6-sol`, against the shipped diff. **That reason did not survive measurement**: filtering copy to vouched pairings gives 19 paired strings and 16 findings, gate total still 132 — the population moves and the pinned number does not. Closed with BL-2 by moving both tests into `Context.derive_pairings`, so the answer to "may these two be compared" exists once and every layer reads it |
| D-m23-t | The collision branch shadows the unvouched branch in the finding text | M23 | A pairing that is both non-injective and unvouched reports only the collision. The status is right either way — both are `unclassified` — but a reader who fixes the collision finds the second reason waiting behind it, and the two are independent. `gpt-5.6-sol` Registered by the gap-fix 2 panel; closed as deferred rather than taken (`M23-gapfix-2-review.md`). |
| D-m23-u | `readable()` filters private-use codepoints, which a bundled font can render | M23 | `Co` is in `INVISIBLE_CATEGORIES`, so a label drawn from a private-use range in an embedded icon font reads as unreadable and its pairing reads `unclassified`. Kept deliberately, on the asymmetry in `D-m23-p`: this direction costs a finding, the other costs a false clean. `gpt-5.6-sol` Registered by the gap-fix 2 panel; closed as deferred rather than taken (`M23-gapfix-2-review.md`). |
| D-m23-v | `--report` followed by another flag takes that flag as the path | M23 | The parse checks only that something follows `--report`, so `--report --verbose` writes the ledger to a file named `--verbose`. `gemini-3.7-flash-high` Registered by the gap-fix 2 panel; closed as deferred rather than taken (`M23-gapfix-2-review.md`). |
| D-m23-w | A duplicate affordance id is absorbed rather than named | M23 | Two inventory entries sharing an id now read `unclassified` rather than each earning `present`, but the finding says one control is named by several affordances rather than that the inventory carries one id twice. `mock-affordances.py` disambiguates with a `#N` suffix, so it is reachable only from a different inventory tool — which is why the selftest reaches it through a wrapper that strips the suffix. `gpt-5.6-sol` Registered by the gap-fix 2 panel; closed as deferred rather than taken (`M23-gapfix-2-review.md`). |
| D-m23-x | The selftest's closing `all three exits observed` is printed, not computed | M23 | `echo`ed whenever `fail == 0`, so deleting every exit-0 case leaves the line unchanged. The 47 cases do observe all three today (1/18/16 plus 12 non-exit assertions), so the sentence is true and unmeasured — G4's shape inside the instrument that proves the gate |
| D-m23-y | ~~`mock-fidelity-gate.sh` asserts `ledger written to $LEDGER` unconditionally~~ **CLOSED, 4th gap-fix** | M23-gapfix-3 | The `echo` sat between `status=$?` and `exit $status` with no test on it, so an exit that wrote no report was followed by the gate stating it did. The behaviour was closed in the 3rd gap-fix — the script reads the engine's own `REPORT_MARKER` rather than inferring from an mtime — and witnessed on the live gate with the ledger path made a directory. What was still open is the CHECK: selftest case 51 drove no configuration in which the marker's position relative to `write_report` is observable, so moving the `emit` before the write left all 59 cases green. Its third invocation, a `--report` path whose write fails under a clean tree, is what holds it shut |
| D-m23-z | `main()` returns 2, which is not one of the gate's three declared states | M23 | Both usage guards return 2 without writing the ledger; the gate script passes it through and `make mock-fidelity` tests only for 3 and 1, so a usage error reads as neither clean, nor findings, nor inconclusive. Adjacent to `D-m23-v` |
| D-m23-aa | A pairing row naming an affordance the inventory does not carry is silently ignored | M23 | Measured: appending a pairing row for a non-existent node leaves every census cell and the finding total unchanged. `claims` is built by iterating the inventory and copy skips on `by_id.get(...) is None`, so a stale or misspelt id in the one hand-maintained artifact in the loop produces no row and no finding |
| D-m23-ab | The gap-fix 2 review record says `paired_nodes` is read at five sites; it is four | M23-gapfix-3 | Lines 718 and 722 (the two prefix tests), 739 (surface check), 759 (sibling census); 602 is the write and 562 the init. The refutation of the dead-code finding stands — only the count is wrong |
| D-m23-ac | The AST enumeration attributes a `.pairs` read only to a function, so a read outside every function body is invisible | M23 | Measured against engine copies: a module-level lambda, a module-level comprehension and a class-body `staticmethod` reader each leave case 46 green, while an ordinary `def` or `async def` reader turns it red. Today's engine has exactly four `.pairs` reads, all inside the allowlist, so the enumeration is correct now and it is the guard that does not generalise. Attributing an unenclosed read to a module scope and failing on it is the one-line form |
| D-m23-ad | The AST guard's escape list names three spellings and misses four | M23 | It rejects `getattr(`, `vars(` and `__dict__`. Measured as evading it: `operator.attrgetter("pairs")`, `ctx.__getattribute__("pairs")`, `inspect.getattr_static`, and a structural-pattern read written as a `match` statement with a `Context(pairs=p)` case. The last two came from the Google lane |
| D-m23-ae | Four of the eight layers have a floor; the other four rest on the zero-guard alone | M23 | `tokenRows`, `lintFiles`, `dumpNodes` and `affordances` are ratchets. `geometry`, `copy`, `type-metrics` and `structure`'s corroboration count have none, so a population falling from 22 comparisons to 1 passes. Not a route to a false clean — a missing ratchet, the shape `dumpNodes` exists to prevent, one layer over |
| D-m23-af | An interpreter-startup failure exits 1, which the gate script reads as findings | M23 | Measured: an invalid `PYTHONIOENCODING` makes CPython fail before executing a statement of the engine and exit 1. The only region found outside all three of the partition's rows, and arguably outside its domain since the file never runs |
| D-m23-ag | ~~Cases 44 and 50 assert only the exit code, so BL-1's report-ordering half is unarmed on the broken-pipe route~~ **CORRECTED AND CLOSED, 5th gap-fix** | M23-gapfix-4 | The row is false about the tree as written, which is `D-m23-an`. Case 44 was armed by the 4th gap-fix and passes `--report` on both of its invocations, asserting each ledger's table. Re-measured on this branch: moving `write_report` back after the console loop reddens exactly two cases at **57 ok / 2 FAIL**, cases 43 and 44, where 44's `PYTHONUNBUFFERED=1` invocation leaves the obituary on disk in place of the table. Case 50 stays green and correctly so — it passes no `--report`, so it has no ledger half to assert. The row reached `main` with `5e70149`, after this branch's base, so no runner could have marked it |
| D-m23-ah | ~~Case 48's second want survives the mutation the case is named for~~ **CLOSED, 5th gap-fix** | M23-gapfix-4 | `1 multi-line node(s) excluded` reads the exclusion rather than the comparison count, so it stayed true when `observations` was reverted to the eligibility census. The 4th gap-fix replaced both wants with `comparisons + excluded == census` beside three literals; the 5th found the identity could not fire from behind them (`D-m23-aj`) and moved it to the head of the chain with the fixture's shape behind it as floors. Measured: red **at the identity** under the census mutation, and green the moment the identity is deleted, reporting `3 + 1 = 3` |
| D-m23-ai | The eight colour-literal spelling cases read only the lint's exit code | M23 | The probe file sits under `Boards/`, which the geometry rules also scan, so any other rule reddening it keeps all eight green while the colour spelling goes uncaught. Arming it needs the lint's own output read for which rule fired |
| D-m23-aj | Case 48's partition conjunct can never discriminate | M23-gapfix-5 | The fifth conjunct sits in an `&&` chain whose preceding conjuncts pin comparisons, census and excluded as string equalities, so it is reachable only when it reduces to 3 = 3 and the chain short-circuits before it whenever a value differs. Measured under both of the case's own mutations: the literals caught each and the conjunct was never evaluated. The case is armed; the identity is decorative |
| D-m23-ak | The sweep's five passes are preserved as outputs, not as code | M23 | The artifact tree holds the instrumented selftest, per-case coverage and want data and the blind-mutant log, but not the pass scripts that turned them into the reported figures, so the conclusions cannot be re-derived without rebuilding the instrument. The coverage half was re-derived independently and agrees exactly |
| D-m23-al | The uncovered-statement figure omits `except` clause lines | M23 | 573 and 72 hold under an AST statement walk skipping `except` handlers, def and class headers and decorators; coverage.py gives 629 and 82, and the ten-statement gap is entirely unreached `except` arms, so the published figure under-reports unexercised error handling |
| D-m23-am | The subprocess-timeout handler is reached by no case | M23 | The largest contiguous never-executed region in the engine, six statements around L232-243: no case makes a shelled-out tool time out, so that path has never been observed. The nested `except Exception: pass` inside main's handler is likewise unreached |
| D-m23-an | `D-m23-ag`'s register row is false about the tree after this merge | M23-gapfix-5 | It says cases 44 and 50 pass no `--report` and that reverting the write-before-print ordering leaves them green. Case 44 now passes `--report`, asserts both ledgers, and goes red under that revert alongside case 43 — measured. The row arrived with main's `5e70149`, after this branch's base, so no runner could have marked it |
| D-m23-ao | The branch's LEDGER row lagged its ORCHESTRATOR row by one pass | M23-gapfix-5 | At `0bad4a6` the LEDGER cell read 3rd gap-fix while the ORCHESTRATOR cell read 4th, itself one commit behind the tip. Both status cells read Ready to verify, so reconciler check I passes on the pair — membership and status agreed while the identity drifted. Resolved by union at the merge |
| D-m23-ap | ~~The report marker is asserted only at paths the fixture already spelled absolutely~~ **CLOSED, 5th gap-fix** | M23-gapfix-5 | `mock-fidelity-gate.sh` greps for `REPORT_MARKER + $LEDGER` with `$LEDGER` relative to the repo root, so `emit(REPORT_MARKER + os.path.abspath(report_path))` makes the gate deny the table it just wrote. Every `--report` in the suite was an absolute path under `$SCRATCH`, where `abspath` is the identity, so all 59 cases stayed green on it. Witnessed on the **live gate** rather than a fixture: exit 1 at 132 findings with the table on disk, and the wrapper printing `NO ledger was written by this run (exit 1)` over it. Closed by a fourth invocation of case 51 passing a relative `--report`. Found by `claude-fable-5` asked to break the artifact  **6th gap-fix:** the family was wider than the closure — `os.path.normpath` is the identity on both spellings the closure pinned, so it too left all 59 green. Case 51's fourth invocation now spells its relative `--report` as `./rel-ledger.md`, a fixed point of neither `normpath` nor `abspath`, and reds case 51 alone under either |
| D-m23-aq | ~~No case reads the marker for an obituary the path accepted~~ **CLOSED, 5th gap-fix** | M23-gapfix-5 | `write_unmeasured_report` emits `REPORT_MARKER` after replacing a ledger and nothing read it: case 51's failing write points at an unwritable directory where `open()` raises and the marker is correctly absent, leaving case 49 the only run that writes an obituary to a path that took it. Dropping that `emit` left all 59 cases green while the gate denied a ledger it had written. Closed by a marker conjunct on case 49 (`gemini-3.7-flash-high`, asked to break)  **6th gap-fix:** closing it on case 49 armed the emission SITE and one of its five callers. Moving the `emit` out of `write_unmeasured_report` into case 49's own call site left all 59 green; cases 32 and 61 now cover the other two callers that reach the marker |
| D-m23-ar | ~~`emit`'s stderr fallback is unarmed for the marker itself~~ **CLOSED, 6th gap-fix — and the row was false about the tree** | M23-gapfix-5 | The row said the route where the fallback earns its place, stdout closed with stderr open, is driven by no case. **Measured: case 44's two invocations both drive it, and `emit`'s fallback fires on both.** `emit` prints and then flushes explicitly, so on a dead stdout the flush raises whether the stream is block-buffered or not — case 44 was discarding the result with `2>/dev/null`, which is `D-m23-au`. The route was driven and unasserted rather than undriven. Closed by redirecting both invocations to files and grepping the marker out of them: under the bare-`print` mutation the suite now gives exit 1 at 65 ok with cases 44 and 60 red, where it gave 59 ok / 0 FAIL. The row was recorded from a runner's report without being tested, which is the same failure as `D-m23-an` |
| D-m23-as | Case 48's partition survives a census computed from the two numbers it partitions | M23-gapfix-5 | Rendering the note as `{observations} per-role comparison(s) over {observations + multiline} text nodes` keeps the suite at 59 cases, exit 0, 0 FAIL, with case 48 still printing `2 + 1 = 3` — measured. An identity read entirely off one sentence cannot tell a partition from a restatement, so closing it needs the census from a second source; `structure`'s dump node count is the one already on hand (`gemini-3.7-flash-high`) |
| D-m23-at | Three of the five obituary call sites are executed by no case | M23 | A full marker trace records eight emissions: five from `gate()`'s post-write site and three from `write_unmeasured_report`, whose callers are only the validation door and the context-load failure. The first validation exit, a report-write failure at a path that accepts the obituary, and `main()`'s handler obituary are never executed, so nothing has observed the marker on any of them |
| D-m23-au | Case 44 discards stderr wholesale, not only the marker | M23-gapfix-6 | `2>/dev/null` on both invocations throws away everything `emit`'s fallback produced on the one route that exercises it — the marker, the INCONCLUSIVE reason and the ledger-stands sentence. No diagnostic on the dead-pipe route can be asserted without changing the redirection, which makes the redirection rather than the case the limit |
| D-m23-av | `D-m23-f`'s prescribed remedy failed silently in a batch | M23 | `rm -rf app/.build` returned `Directory not empty` with a concurrent writer present and the batch continued; the gates then ran clean, so the failure cost nothing this time and would have been invisible if it had. A remedy a note tells operators to run needs its own exit check |
| D-m23-aw | Nothing keeps the suite's declared blind spots true | M23-gapfix-6 | The selftest states in prose what it cannot reach, and one such declaration was measured false this pass — the gate script's console decision, called three-minute and non-hermetic, is reachable in about a second by a harness built from stubs the suite already writes. **A bound that is wrong reads exactly like one that is right**, which is this item's own defect one level up: the declarations are the last unchecked assertions in the file |
| D-m23-ax | ~~`run.report_path` is written and read on no reachable route~~ **CLOSED structurally, 6th gap-fix** | M23-gapfix-6 | `gate()` records the report path on `Run` and `main()`'s handler is its only reader, and that handler's obituary branch cannot execute with a path set: with `--report` given, `gate()` either returns 3 from R1–R4 without raising, or it reaches the report block, after which `run.report_written` is true before anything downstream can raise. So dropping the `Run` field and keeping the local — a redundant-assignment cleanup — leaves all 67 cases green, measured. It is not dead code: under the pre-fix ordering the R5 route becomes reachable and `run.report_path` is what carries the obituary. Pinned by case 60 as a structural check, since the route that would exercise it cannot run (`gemini-3.7-flash-high`, asked to break rather than review) |
| D-m23-ay | ~~`mock-fidelity-gate.sh` depends on `-e` being off and nothing said so~~ **CLOSED by arming, 6th gap-fix** | M23-gapfix-6 | The instrument preflight runs `"$TOOL" --state definitely-not-a-state` as a bare command and reads `$?`, so `set -uo pipefail` → `set -euo pipefail`, the ordinary hardening edit, kills the script there on every run: exit 3, no output, and `stale_ledger_note` never called — the pre-marker stale-ledger failure reintroduced by making the whole marker block unreachable rather than by mis-deciding its grep. Everything past line 57 of that script was executed by nothing before this pass, so the edit was invisible; it now reds six cases (`claude-fable-5`, asked to break rather than review) |
| D-m23-az | `D-m23-at` is mis-stated about which call sites execute | M23-gapfix-6 | The row says three of `write_unmeasured_report`'s five call sites "are executed by no case". Measured by tracing both emission lines across the 145 python3 processes the suite starts, 52 of which are the engine (`D-m23-bc`; this row first said 145 engine processes): only R1, the manifest-load failure, is executed by nothing. R4 is executed once and R5 once — R4's write fails so it takes the WARNING branch, and R5 runs with `path` None because no `expect()` case passes `--report`. The row's conclusion holds, three of the five never reach the marker, but its stated reason does not. It arrived on main after this branch's base, so no runner could correct it in place; correct at merge |
| D-m23-ba | Case 60's enumeration is evadable three ways, all of them a new emitter | M23-gapfix-7 | Check 1 is a raw substring scan and check 3's escape list omits `globals(`. Three constructed third emission sites each leave all 67 green: a split literal byte-identical to the constant, a `globals()` lookup with no `Name` load, and a sibling module since case 60 parses one file. What it does catch was measured — a third `emit` site, a local alias, and the dropped store, each redding case 60 alone. The engine today contains none of the dynamic spellings and imports only stdlib, so the enumeration is sound now and the guard is one-directional |
| D-m23-bb | *Five of the eleven arms were invisible to the shipped suite* is nine | M23-gapfix-7 | Against the pre-pass 59-case suite, a1-a5 and a8-a11 all ran 59 ok with 0 FAIL; only a6 and a7 were visible. **The evidence file's own table says the same** — five rows reading all-59-green plus four reading invisible — so the summary sentence and both ledger rows contradict the table beneath them. The error understates the pass |
| D-m23-bc | *145 engine runs* counts every `python3` process, and `D-m23-az` repeats it | M23-gapfix-7 | 145 python3 processes in total across the 59-case suite that shipped before the sixth pass, of which **52 are the engine**, 10 of those carrying `--report`. Every emission figure the conclusion rests on is right; only the population is over-counted, 2.8x. **This row first read 53 and named an inline `-c` script as the 53rd process; both halves of that were wrong.** No `-c` form appears at any of the 11 revisions `git log --follow` names for `mock-fidelity-selftest.sh` (each blob read and non-empty, so no absent path reads as a zero). **What 53 was counted from is not recoverable** — the correction did not say — but the one thing in the suite that would produce it is case 46, which hands the engine's path to a `python3 -` stdin heredoc: that heredoc `ast.parse`s the engine's source and never executes it, and its `sys.argv[0]` is `-`, so it is an engine **reader** rather than an engine run. A count keyed on the path appearing in a command line takes it; one keyed on `sys.argv[0]` does not. That suite held one such heredoc (the sixth pass added case 60's second, which reads the engine the same way). **52 is the `sys.argv[0]` figure — the number of times the engine's own code ran — and the one the route table rests on.** Corrected in M23-gapfix-8 (`D-m23-bk` the reason, `D-m23-bl` the value), where `claude-fable-5` and `gemini-3.7-flash-high` independently broke the first wording of this row for treating a source grep as a bound on a trace quantity; the row arrived on main after this branch's base, so no runner could correct it in place — the situation `D-m23-az` records for itself |
| D-m23-bd | Gate B is in every brief's standing gate list and its recipe exists nowhere | M23-gapfix-7 | Named once at `M23-gapfix-2.md:121` and carried forward as *B 3 with a ledger written* through four briefs with no surface, command or fixture recorded. The verifier constructed an equivalent and states plainly that is not the same as reproducing it. A gate in a standing list that nobody can run is a claim, not a check |
| D-m23-be | `make test` red once at `OAuthWireTests.swift:263` | D-g3-c | *A waiter that is cancelled is resumed rather than stranded*, exit 2 with one issue at 1615/202, green on the re-run. A cancellation-timing test on a machine concurrently running another session's Swift builds — G3's class, not M23-adjacent |
| D-m23-bf | The selftest's case labels are names, not execution ordinals | M23 | The `# NN` comments do not match run order: label 60 is the 50th case to run, 43 the 47th, 62-67 the 52nd-57th. So a claim like *case 51 alone at 66 ok* cannot be checked against the suite's output without reading the source and reconstructing the ordering, which every verifier of this item has had to do by hand |
| D-r7-a | The acceptance lane never exercises the `.name` duplicate basis | R7 | Removing `.name` leaves the lane green — the fixture's three duplicates all match by identity too. The unit suite does catch it, so the regression is guarded; it is just not guarded by the artifact A3/A8 cite. Add the spec's own `mobbin` row (same name, different identity) and assert `basis` |
| D-r7-b | `HTTPCapability`'s table is unasserted except for `opencode` | R7 | Flipping `claudeDesktop` `.documented` → a fabricated `.measured`, or `cursor` `.measured` → `.unknown`, passes every gate. The honesty argument in spec §3 and DESIGN.md §6 rests entirely on this table. A pinning test per client, like the existing `opencode == .unknown`, closes it |
| D-r7-c | MiniTOML refuses ordinary TOML: CRLF, and a comment after a table header | R7 | `[mcp_servers.router] # shared` and CRLF both throw `unterminated table header` — only `.whitespaces` is trimmed and `hasSuffix("]")` is a literal test. Degrades to `could not be read` with no plan emitted, so it is a coverage limit rather than a wrong answer |
| D-r7-d | MiniTOML never scans past a `#` inside a multi-line array | R7 | `bracketDepth` returns at the first `#` of the accumulated string, so `args = [ # flags` consumes to EOF. All three review lanes ranked this a blocker; ranked lower here because it cannot produce a wrong answer — it degrades honestly to unreadable |
| D-r7-e | A `]` inside a header comment yields a mis-named entry and an under-count | R7 | `[mcp_servers.obscura] # see [ref]` parses "successfully"; the duplicate lands in `unparsed` as `obscura] # see [ref` while `duplicateCount` reads 0 and the harness reports `wired-http` clean. The designed `unparsed` channel does surface it; `headline` does not. Worst of the TOML set, still not silent |
| D-r7-f | Shim detection requires the endpoint to be a whole token | R7 | `--url=<endpoint>`, a single-string `command` and a string-valued `args` all report `not-wired`. Matches spec §4's wording ("is such a URL"), so this is a widening rather than a bug |
| D-r7-g | A second router-pointing entry counts as a direct-upstream duplicate | R7 | Only the entry `detect` selected is filtered out of `others`, so an `mcp-remote` shim named after a router upstream is labelled a duplicate. The advice is right and the stated reason is wrong |
| D-r7-h | A name-matched entry never reaches `ServerParser`, so its parse failure never reaches `unparsed` | R7 | Spec §4's narrow wording ("never silently counted as no-duplicate") survives; the broader invariant does not |
| D-r7-i | `"Global scope only"` is printed while a project-scoped file is read | R7 | `HarnessesVerb` passes `FileManager.default.currentDirectoryPath` and `.chatGPTCLI`'s path is project-scoped, so results vary by cwd while `"scope":"global"` is emitted. Inherited from `ClientConfigs.path`; adjacent to R7-C4 |
| D-r7-j | ~~The lane's non-mutation check only greps for `"Ref"`~~ | G1 | **Closed in the R7 gap-fix.** Any rewrite preserving that one entry passed. It is now a sha256 over every harness fixture in the scratch home, compared across a JSON probe and a text probe. Closed here rather than left deferred because the gap-fix's own reviewers filed the identical finding against the new pass-4 assertion, and leaving one grep beside one digest in the same script is worse than doing both |
| D-r7-l | `--json`'s `state` still reads `not-wired` for a config that could not be read | R7-C1 | F2 makes the distinction *expressible* — `unreadable` carries the parser's own reason and the acceptance lane asserts the wire and the screen carry the same sentence. It does not make it unmissable: a consumer switching on `state` alone still sees a clean unwired harness, because `HarnessState` has no case for "nothing was measured". The verb's doc comment says to read `unreadable` first and the lane pins the whole empty row, so the trap is documented and guarded rather than removed. Adding a state word is R7-C1's call, since its board is the first consumer |
| D-r7-m | The write-boundary gate cannot see an applier split across two files | new item | Named by the out-of-family review and true: a coordinator asking `ClientConfigs.path(for:)` for the target and a neutrally-named helper taking a `String` and writing it satisfies no intersection and lives in no watched name. `grep` cannot follow a value between files. **The gate no longer claims otherwise** — its header, `spec-R7.md` §7 and the ledger row all now say what it does check — and `no-harness-config-writes-selftest.sh` carries the case as **P10, an assertion that the gate misses it**, so the limit is visible from a run rather than only from a paragraph. The closed-world fix is a census of every writing file under `app/Sources` against a declared allowlist; that turns every unrelated feature adding a file write into an edit of this script, which is a real cost across a fleet and is the owner's trade to take |
| D-r7-n | `SelfReference.isSelfReference` keys on `url` alone, so `discover` cannot see a renamed `httpUrl` router entry | new item | The dialect widening is deliberately confined to R7's read path: `ServerParser`, `UpstreamHash` and `SelfReference` are shared with adoption and with the TypeScript reference, and moving any of them changes what the router adopts or what a manifest hashes to. The consequence is that `ClientConfigs.discover` would not filter a Gemini router entry that both spells its endpoint `httpUrl` **and** is renamed away from `router`/`mcp-router`. It cannot produce a wrong answer today — `discover` has no production caller, only tests — and it becomes real the moment a board calls it |
| D-r7-o | `MCPRouterCLI.swift` is at 399 lines against swiftlint's 400-line `file_length` | new item | R10's `IndexReport` work took it to 393 on `main` and R7's `harnesses` arm takes it to 399. The dispatch comment was cut from four lines to two to land under the limit, which is not a fix. The next verb arm trips `--strict`, and the answer is to split the dispatcher rather than to keep trimming prose |
| D-r7-p | An entry declaring two different endpoints under two spellings is resolved by precedence, not by evidence | **Closed by R7's 2nd gap-fix** | **The note this row carried was wrong and is corrected here.** It read that taking `url` was "the right answer for a yes/no question" — half true: the ROUTE asks yes/no of every spelling and needs no pick, while the COMPARISON has to hash one value and had no evidence for the pick. The guard returned early on any non-empty `url`, so a decoy there erased a real duplicate declared under `httpUrl` — neither counted nor reported, which spec §4 forbids in those words. It was also not hypothetical: `agy`'s HTTP transports are `serverUrl` and `httpUrl`, never `url`, so a stale `url` beside a live `serverUrl` is the ordinary shape of a half-finished migration. `HarnessDialect.resolve` now returns a conflict that lands in `unparsed`, in both directions, while two spellings carrying the same string stay one endpoint |
| D-r7-q | The gate's standard-stream exclusion is same-line, so a two-line `print` reads as a file write | G1 | `let handle = FileHandle.standardOutput` on one line and `handle.write(data)` on the next leaves `.write(` unneutralised, and a file naming a harness path in code would then be a finding. It over-fires rather than under-fires, and the gate prints the offending line, so it is diagnosable in one read — but a gate that cries wolf is a gate that gets deleted |
| D-r7-k | Pass 2's empty-expected assertion can pass on a `field` crash | G1 | `check "the names" "" "$(<pipeline ending in `field duplicates`>)"` — no literal pipe in this cell on purpose, see RULE below — a python failure yields `actual=""`, which equals the expected `""`. `set -e` is absent by design; capture with `if ! actual="$(…)"` |
| D-g3-l | A trailing comment containing `awaitEvent(` makes a bare call read as bounded | G3-gapfix-2 | **Closed by gap-fix 2, by removing the mechanism rather than the symptom.** `isBounded`'s raw same-line test is gone: boundedness is now decided only by which brace block encloses the call, so no text on the call's own line can change the answer. Three controls hold the three measured shapes — a `//` TODO naming `awaitEvent(`, a block comment, and a URL ending in it — and mutation `M11`, which reinstates the same-line shortcut, reds all three |
| D-g3-m | A call on a line with `//` inside a string literal is not seen at all | G3-gapfix-2 | **Closed by gap-fix 2.** Line-at-a-time truncation at the first `//` is replaced by a whole-file delexer implementing Swift's comment and literal grammar, so a `//` inside a literal is literal content and the call after it is code. Controlled, and mutation `M2` (literal stripping off) reds it along with six others |
| D-g3-n | The scanner reds on three correct or non-code shapes | G3-gapfix-2 | **Closed by gap-fix 2.** All three were indentation standing in for block structure, or a comment recognised by its first three characters. The walk now counts braces, so a `#if` at column 0 has no depth to set and a tab has none to count; comments are removed by the delexer before anything reads them. One control each for `#if`, tabs and no indentation at all, plus one for a wrapped call inside a block comment; `M14` and `M12` red them |
| D-g3-o | The gate's failure message dumps the whole scanned file ahead of the actionable line | G3-gapfix-2 | **Closed by gap-fix 2.** The scan now collects `File.swift:line` offenders and asserts `offenders.isEmpty`, so `#expect` displays a short list rather than the source array. A smaller residual remains and is registered separately as `D-g3-w`: Swift Testing prints a suite's own doc comment on failure, which lands **after** the actionable line rather than before it |
| D-g3-p | `D-g3-b` cites a line no revision at HEAD carries, and `D-g3-j` claims it fixed | G3-gapfix-2 | **Closed by gap-fix 2.** `D-g3-b` now cites `PoolLifecycleTests.swift:116`, which is the 30 ms sleep on the delivered tree, and `D-g3-j`'s row now states that three of its four counts were corrected and which one was not. A register row claiming a correction it did not make is worse than the uncorrected row, because the next reader stops looking |
| D-g3-q | Gutting `awaitSessionEnded` leaves three of its five call sites green | G3 | Both accessors replaced with an immediate `return` reds `PoolReapingTests.swift:101` and `PoolTests.swift:144`, 4 of 4 runs. Three sites never move, so they have no demonstrated mutation power. Wider than `D-g3-g`; reopened from the runner's overrule, which the measurement supported only half of. **Gap-fix 2's narrowing is withdrawn in gap-fix 3.** That pass saw `PoolTests.swift:144` green 4 of 4 at 0% idle and derived a load-dependence from it; the verifier then ran the same mutation at 15.5% idle falling to 0.6% under 1-minute load 127 — *heavier* contention — and got both sites red 4 of 4, which refutes the explanation on its own terms. The measured claim reverts to the previous verifier's. **Deferred on scope alone**, which was always available and needs no contested number: the remedy is `D-g3-g`, which is deferred, and a call-site change cannot substitute for it — a probe printing which branch the accessor takes reports `PROBE-EARLY-RETURN` at 3 of 3 and `PROBE-AWAITS-WATCHER` at 0, so at every one of those three sites the handle is already gone and the accessor awaits nothing whatever the caller does. The bound it places on the gate is explicit: `PoolAwaitBoundTests` proves no site is unbounded, not that every site observes something |
| D-g3-r | Acceptance criterion 3 cannot report what it is named for | G3-gapfix-2 | **Closed by gap-fix 2 by deletion, with the reason recorded in `G3-gapfix.md`.** Mutation B keeps the reap deadline on the requested 25 ms window; relaxing `:87` so execution reaches `:98` gives P6 passing in 2.291 s and the run green. No discriminating version was built because none exists that is independent: the observable separating the two sides of the await is the duration, and the assigned mutation already shows it — 11.280 s red naming its own condition against 601.184 s unbounded. **The orchestrator wrote this criterion**; sixth entry in G4 |
| D-g3-s | Three fixed-sleep flakes observed red outside the three surveyed suites | D-g3-c | `CallbackListenerTests.swift:108` (150 ms at `:101`) red 2 of 3; `OAuthWireTests.swift:263` (3 s at `:261`) **red three times now** — once as first recorded, once during G4's first verification at load 900-945, and once during R17's gap-fix 4 at load 625-1015, green on the retry each time. **Recorded as three events rather than as a rate**, deliberately: `D-r17-d` spent three passes stating rates the next measurement refuted, and this row is not going to repeat it. All three reds are on a loaded box and none has been reproduced on a quiet one, which is a statement about what has been observed rather than about what the test does; and **`CallbackLifecycleTests.swift:238` red once in gap-fix 2** — *the callback listener was cancelled before it bound*, in a file carrying three fixed sleeps including a 50 ms one at `:217`. **Two more in gap-fix 3**, at 0.0% idle and 1-minute load 421: `CallbackLifecycleTests.swift:238` again, and `ControlStreamTests.swift:72` — *(arrival → …) < (lastSent → …)* comparing two timestamps that round to the same second. Five measured instances in four files now, two of them red on 2 of 4 `make test` runs in one session. All at 0-11% idle with two sibling runners live, and none in a file this item touched. `D-g3-c` predicted around sixty unclassified; three are now measured rather than surveyed, in three different files |
| D-g3-t | "The closure only awaits" is a doc comment the gate does not read | new item | The observer's safety on the timed-out path depends on `event` awaiting rather than acting. `PoolAwaitBoundTests` asserts the wrap exists and nothing about its contents, so a sixth site doing work reopens the leak Gemini named |
| D-g3-u | Three directories under `app/` are outside the scan | new item | `trees` names four directories; a bare call planted in `app/MCPRouterIOSTests`, `app/MCPRouterIOSUITests` or `app/Scripts` is invisible, measured. Currently unreachable — `import RouterCore` appears in only three places — so a floor, not an open hole |
| D-g3-v | The brief says `ReapTimer` "is not `Sendable`" where it conforms implicitly | G3-gapfix-2 | **Closed by gap-fix 2.** The diff claim and the register row are right; the type claim was not. Every target builds under `.swiftLanguageMode(.v6)` and all of `ReapTimer`'s stored properties are `Sendable`, so it conforms without an annotation. `G3-make-test-is-not-deterministic.md` now says "carries no explicit `Sendable` annotation", and `D-g3-j`'s row above is worded the same way |
| D-g3-w | A suite's own doc comment is printed on every failure of that suite | new item (recorded as G3-gapfix-2 on the branch) | Found while measuring `D-g3-o`'s fix. Swift Testing treats a `///` doc comment on an `@Suite` or `@Test` as a test comment and emits it with the failure — 35 lines of argument after every red of `PoolAwaitBoundTests`. It lands **after** the actionable line rather than before it, which is why `D-g3-o` is closed and this is separate. The control file's long argument was moved onto a non-suite type when lint forced a split, which is what made the behaviour visible; the scanner's was left, so the two files now differ and one of them should follow the other |
| D-g3-x | A scan whose delexer is wrong is quadratic, not merely wrong | G3 (recorded as G3-gapfix-2 on the branch) | Measured, not reasoned: mutation `M3` (interpolation tracking off) desynchronises the delexer over the real tree, which turns a handful of call sites into hundreds and each into a backward walk to the file start. The unfiltered run had to be killed at roughly five minutes where the clean run takes 1.5 s. Harmless on the delivered scanner, which finds five sites in 497 files, and worth knowing before anyone widens the needle set |
| D-g3-y | The rebuilt scanner carried nine more defects, and two out-of-family lanes found them | G3 (recorded as G3-gapfix-2 on the branch) | **Found and closed inside gap-fix 2**, by asking each lane to break the scanner rather than to review it — the question that has now yielded a defect on every round of this item. **Round one (gemini):** the opener span ran back to the enclosing brace, so `log(awaitEvent(x))` on an earlier line bounded a later `if` block; the span's `awaitEvent(` could belong to an inner call, so `withTimeout(awaitEvent("x")) { … }` and `guard awaitEvent(…) != nil else { … }` read as wraps; both markers matched mid-identifier, so `mock_awaitEvent(` was a wrap and `if myfunc {` was a `func`. A **readability guard** added on the same lane's regex-literal point then caught a fourth nobody named: `#""""#` — a raw literal holding two quotes — read as a multi-line opener that never closes, silently blanking `PrimitiveBodyTests.swift` from `:140`. **Round two (fable, which ran each break in a harness rather than tracing it):** a control-flow body reads as a wrap, because `if flags.awaitEvent(x) {` has exactly the shape the ownership rule accepts — five constructed, five confirmed; **CRLF desynchronises the delexer while `endedCleanly` and the brace balance both still pass**, the one break that defeats the guard as well; `init`/`deinit`/`subscript` bodies were walked through where `func` terminates; a closure passed as an ordinary argument (`awaitEvent("x", { … })`) was a false red, one formatting choice from the blessed spelling; a tab between the dot and the name made a call invisible; and an unapplied reference `pool.awaitReap(_:epoch:)` reported unbounded. **Round three (gemini again, on the finished scanner):** an `if` on the line above its condition — legal Swift — put the span below the `if` so the body read as the wrapper's trailing closure; a closure handed to `Task.detached` inside a wrap is lexically inside it and outlives it, the one place the scan can tell containment from an execution bound; and `analytics.awaitEvent("x") { … }` read as the wrapper because `.` counts as a word boundary. Twenty-one controls and eighteen mutations added across the three rounds. **Not taken, with reasons:** `awaitEvent<T>(…)`, a second labelled trailing closure and a closure passed as an earlier argument are all unreachable with `awaitEvent`'s signature and all fail toward a red on correct source; and a Swift 5.7 regex literal carrying an unbalanced brace would trip the readability guard and red CI — a deliberate trade, with no regex literals in the four scanned trees today and the guard's message naming one as the first thing to look for |
| D-g3-z | A compile-time witness would make an unbounded call impossible, and layering blocks it | new item | The reviewer's architectural answer, and it is right about the ceiling: give `awaitReap`/`awaitSessionEnded` a witness parameter only `awaitEvent` can mint and the scanner is unnecessary, because the compiler enforces it. It is not taken because the witness type would have to live in `RouterCore` for `UpstreamPool` to name it, and `@testable import` makes any `internal` initialiser mintable from any test — so making it unforgeable means moving the bound into `RouterCore`, which is the layering the accessor's own doc argues against. The SwiftSyntax variant is the same property with a real parser and no production-signature change, and it costs an exact-pinned pre-1.0 dependency plus its build time. Both are strictly better instruments than a byte scan; neither is free, and the scan is what fits the constraint today |
| D-g3-aa | A statement label makes a control-flow body read as the wrapper's trailing closure | G3-gapfix-3 | **Closed by gap-fix 3.** `check: if awaitEvent(x) {` read the enclosed call as bounded; deleting the one token read the identical source as unbounded. `firstWord(of:)` returned `check`, so the `bodyKeywords` guard added in round two — added *precisely because a lane broke this* — never fired. Labels are legal on `if`, `while`, `for`, `switch`, `do` and `repeat`. `firstWord` now steps past a prefix that introduces a statement without being one, which closed a `case`/`default` clause with it: `case .a: if awaitEvent(x) {` was the same miss through a door nobody had opened, measured on the pre-fix scanner. Four controls, both directions; mutation `M-label` (the skip removed) reds three of them and `M-labelled-body` (a labelled statement always read as a body) reds the other two |
| D-g3-ab | A labelled string-literal final argument produces no call site at all | G3-gapfix-3 | **Closed by gap-fix 3, one level up from the symptom.** `await p.awaitReap(name: "own")` delexed to `awaitReap(name:    )`, which is the shape of an unapplied method reference, so `callEnd` discarded it and the scan reported nothing. The cause is that a comment and a literal were blanked to the same byte: a comment is nothing and a literal is a **value**, and whitespace where a value stood is indistinguishable from absence. Literal bytes now become `ScanByte.elided`, and so do non-ASCII code bytes, which was the same miss's other door — `p.awaitReap(name: 名前)` was invisible for the same reason. Unreachable with today's two signatures and silent the moment one gains a labelled string parameter. Three controls; mutation `M-blank` (literals back to whitespace) and `M-any-colon` (any colon in an argument list read as a reference) red them |
| D-g3-ac | `Task` anywhere in the opener statement, including inside a string interpolation, reddens a correct wrap | G3-gapfix-3 | **Closed by gap-fix 3.** `try await awaitEvent("reap at \(Task.currentPriority)") { … }` read UNBOUND; swapping `Task` for `Clock` in the same line read BOUND. An interpolation is code, so the word really was there — the `escapes` test ran on the opener statement rather than on the callee actually receiving the closure. It now reads the owner of the brace, stepping back over an argument list and a generic argument list, so `Task.detached(priority:) {` and `Task<Never, Never> {` still escape. Three controls; mutation `M-task-word` (the whole-opener search restored) and `M-no-group` (the owner walking no group backwards) red them |
| D-g3-ad | Five deferred-register ids occur twice on the branch, three carrying different rows | G3-gapfix-3 | **Closed by gap-fix 3.** `D-g3-g` … `D-g3-k` each appeared twice inside the Deferred children section, introduced by this item's own merge `e4cb050` and shipped at `cbc6a81`; `g`, `i` and `k` carried materially different text, so a grep for the id returned two answers. The richer copy — this branch's own, which subsumes `main`'s — is kept and the stray deleted. `main`'s `D-p1-a` and `D-p1-e` merges are taken verbatim rather than re-split. `ledger-reconcile.py`'s **check K** catches exactly this class and now exits 0 on the branch at 164 register rows examined; the reconciler was taken from `main`, since the branch's copy predates the check |
| D-g3-ae | The control count stands for three populations of different kinds | G3-gapfix-3 | **Closed by gap-fix 3 by stating the split rather than by closing it.** Family A (lexical grammar, 19) and Family B (block structure, 12) rest on closed, citable production lists. Family C — `verdict`, `statement`, `firstWord`, `continuesStatement` and five keyword lists, 38 controls after this pass — implements no grammar: its population is *shapes somebody might write*, the open set the completeness argument set out to escape, and every defect of `D-g3-aa`…`D-g3-ac` was in it. `AwaitBoundControl`'s doc comment now gives the count and the population family by family and says which one is open; the mutation matrix is stated separately, because *every mechanism in the code as written is load-bearing* is a different claim from *the grammar the code should implement is covered*, and Family C is where the two come apart. An honest bound beats a claim that reads wider than it is |
| D-g3-af | The assigned mutation as written in the brief does not compile | G3 (recorded as G3-gapfix-3 on the branch) | The mutation the gate is specified with needs a local capture before the `Task`, or it fails with *explicit use of self is required*. Registered rather than fixed: it is the brief's text, not the gate's behaviour, and every pass has hit it and worked around it silently. The next writer of that brief should carry the capture line |
| D-g3-ag | Two cited length limits that no config or document states | G3 (recorded as G3-gapfix-3 on the branch) | `PoolAwaitBoundTests`'s doc cites a 400-line limit and the control files cite a 250-line one, both as though a project rule stated them. Neither is in `.swiftlint.yml`, which configures `line_length`, `identifier_name`, `type_name` and `function_body_length` and nothing else. Measured while splitting a control file in gap-fix 3: they are **SwiftLint's own defaults** — `file_length` warns at 400 and `type_body_length` at 250 — so the citations are true and unsourced rather than wrong. The two comments gap-fix 3 wrote name the rule; the older ones do not, and making them agree is not this pass's work |
| D-g3-ah | Nine more shapes two lanes broke it with, not taken, six of them misses | G3-gapfix-3 | The residue after gap-fix 3, measured on the delivered scanner rather than reasoned about, and **this is the evidence the corrected directional claim rests on: six fail toward a MISS and three toward a red.** Misses — a bare `awaitReap(…)` with no receiver carries nothing to match (already in the suite's doc, and unreachable outside the actor that defines it); `pool.awaitReap<Int>()` with explicit generic arguments is not read as a call, because `callEnd` wants `(` after the name; a **typealiased** `Task` (`typealias Job = Task<Void, Error>`, then `Job { … }`) escapes unseen, and no text scan can follow an alias; an accessor or nested declaration inside a wrap is walked through, because `declarations` holds `func`/`init`/`deinit`/`subscript` and adding `var` or `let` would red `if let x = y {` inside a wrap, which is common correct source; a closure **stored** rather than run inside a wrap satisfies the gate, which is `D-g3-t`'s shape with `Task` as the only escape the scan knows; and an escaping closure inside the wrapper's own argument list (`awaitEvent(watchdog.register { … }) { … }`) reads as the non-trailing spelling. Reds on correct source — `Self.awaitEvent(…) { … }`, which is the free-function rule working as designed; `awaitEvent(setup: { () }) { … }`, where the inner `}` truncates the opener; and the wrapper called through backticks. The last six are unreachable with `awaitEvent`'s and the two accessors' signatures as they stand today |
| D-r7-r | A case-folded endpoint key reads not-wired though the harness accepts it | R7 | `httpurl`, `HTTPURL` and `HttpUrl` all report `not-wired`. `agy` is Go and links `encoding/json`, which matches object keys case-insensitively as a documented fallback. Grounded in the decoder's documented behaviour, not witnessed on agy directly — a HOME override does not reach its config dir |
| D-r7-s | The remedy prints a literal placeholder for a port the tool has measured | R7 | `Point this harness at http://127.0.0.1:<port>/mcp.` is emitted verbatim while the run knows the port is 8879. A user copying the line writes an unusable entry |
| D-r7-t | A dialect regression crashes the test bundle instead of failing it | G1 | `HarnessDialectTests.swift:163` indexes `found.duplicates[0]` unguarded, so the mutation that empties it aborts the suite at signal 5 and ~1600 tests never run. The gate still reddens, but the diagnosis names an index rather than the assertion |
| D-r7-u | The lane accepts a prefix of the parser's sentence as the same sentence | G1 | Pass 5 greps the whole text for `could not be read: $UNREADABLE` as a substring, so a truncated prefix passes, as does a match found under a different harness. Named by the codex lane |
| D-r7-v | The read-only boundary digest reads contents only | R7 | `fixture_digest` hashes bytes, so a rewrite to identical bytes, a truncate-and-restore, a mode change or an mtime change all pass while the verb would have opened a config for writing. Named by the codex lane |
| D-r7-w | The printed transport evidence for Gemini cites a key the harness does not document | R7 | The `.measured` string names `json:"httpUrl"`; agy's own help and its written config use `serverUrl`, and `httpUrl` is a bare struct tag with no documentation. Not false — the wrong half of the evidence, printed three lines above the wrong answer |
| D-r7-z | The comment stripper goes quiet on an opener inside a multiline or raw string, and the header says the opposite | R7 | A `/*` inside a `"""` body, inside a raw string with an odd inner quote, or after a raw-string trailing backslash opens a block and blanks the applier below it, so the gate reports none writes one. The stripper's own comment claims the multiline body is read as code and therefore errs toward reporting; a per-line reset makes it err toward silence. Latent today — the tree opens exactly one block comment, at `Describe.swift:193`, and it is genuine — but the tree carries 280 multiline and 11 raw strings |
| D-r7-aa | R7 reports wired via HTTP for a Gemini entry `agy` cannot run | R7 | Driving `agy mcp list` against a scratch HOME lists an `httpUrl`-only entry as stdio with an empty command while R7 says `wired-http` and suppresses the remedy. `httpUrl` is correct for upstream gemini-cli's `settings.json`, so the fix is to scope the key set per candidate file rather than per client, which also settles `D-r7-w`'s evidence string |
| D-r7-ab | `agy`'s endpoint precedence is measurable, and route detection does not use it | R7 | Measured: `agy` resolves `serverUrl` over `url` regardless of key order. Route detection asks yes-or-no of every spelling, so a router entry with `url` at this router and `serverUrl` elsewhere reports `wired-http` while `agy` connects elsewhere. `resolve`'s conflict text and `D-r7-p` both say the precedence is not established by anything here, and it now is |
| D-r7-ac | The closure check is satisfiable without discriminating | G1 | Narrowing a vocabulary alternative to a longer literal keeps the check green because its own probe subject still matches, while a real applier on a differently-named variable walks through at exit 0 against a plant the unmodified gate refuses at 1. The check proves each alternative matches a subject, not that the alternative is scoped to the property |
| D-r7-ad | Two false positives inside the seam | G1 | A nested block comment, and a block-comment terminator spelled inside a string within a block, both report a write that is genuinely commented out. The direction is the safe one and the header says there is no suppression syntax, so the cost is rewriting a comment |
| D-r7-ae | Four natural mutating spellings sit outside both vocabularies | R7 | A bare POSIX open plus write with a numeric mode, `copyfile`, `pwrite`, and `FileDescriptor.writeAll` all exit 0 in the seam. The header declares this class rather than overclaiming, so these are instances to add rather than a defect in the claim |
| D-r7-af | `make lint`'s node precondition is a false dependency for lint | G1 | Satisfying the tools guard with an empty `node_modules` directory and an empty `dist/index.js` turns all six lint steps green, which proves no step reads either path. Splitting the guard so lint requires only the three binaries would unblock a gate recorded blocked for three passes |
| D-r7-ag | `JSURL`'s two-slash authority rule diverges from `new URL()` for special schemes other than `file` | R2 | node resolves three and four leading slashes to the host while `JSURL` rejects them at the empty-host guard. The url-parse corpus has 18 vectors and one with three slashes, which is the single case where two is correct. No wrong answer about `agy`, whose Go parser also gives those spellings no host |
| D-r7-ah | spec §7's A7 row understates the artifact it cites | R7 | It says 22 selftest cases and describes twelve plants and five innocent shapes; the third round raised the selftest to 27 and the evidence file records that. The prose above it was updated and the acceptance row was not |
| D-r7-ai | grok is packet-size limited rather than down | G1 | It returned 1,051 bytes at exit 0 for a 1,174-byte prompt after returning nothing at 16.5 KB and 64 KB. Worth a size ceiling in the lane guidance rather than a lane-down record, since the substitution to fable-5 costs a family |
| VER2-R17-3 | The same read-window divergence is readable from source on `index` and `import`, and is filed as merely unmeasured | R19 | Swift routes every upstream through `ManifestIndexer.index` to `record`, re-loading at `ServicePorts.swift:381` and saving at `:391` **per entry**; node's `cmdIndex` loads once at `src/index.ts:177` and saves once at `:186`, and `cmdImport` at `:101` and `:146`. The same disagreement the declaration covers for `watch`, on the writer R19's own reproduction used. Established by reading rather than measuring |
| VER2-R17-4 | LEDGER's compressed R17 row reads as if five save sites were wrong | R17-gapfix-2 | It says *the orchestrator's five save sites corrected to three*. Five was correct for node; three is correct for Swift. ORCHESTRATOR states it properly |
| VER2-R17-5 | The replacement figure is as unstable as the one it replaced | R17-gapfix-2 | `parity-oauth.sh` standalone gave **21 of 21 twice** on this branch — the number that was struck through. The document's conclusion survives because it says the count moves under load; the table presents `19/21 each` as a measurement of the branch |
| D-r14-a | Acceptance 10, `tools/list_changed` on an upstream authorising, is unimplemented | R14 | Absent from both implementations. The router builds a fresh MCP Server per request and holds no stream to push down. Internally honest — `capabilities.tools` is empty and does not advertise `listChanged` — so no client is misled. Whether an unmet listed criterion blocks closure is a scope call the verifier surfaced rather than absorbed |
| D-r14-b | Acceptance 9 is unverified against a real GUI client | R14 | The three mitigations were each confirmed on both routers — a 365-day access token, a validated refresh grant, an idempotent `client_id`. None of that is watching a real client reconnect |
| D-r14-c | A never-indexed router reports all 13 upstreams broken | R14 | Measured on a second sandbox with no manifest: the page reads `0 of 13 upstreams are serving tools` and prints 13 rows. Each row's state and remedy is individually correct, but the single fact explaining all 13 is the one the page omits, and the router already logs it. This is the fresh-install moment R14 targets. Found independently by the orchestrator and the verifier |
| D-r14-d | `ClientBlob` is the only sealed value that does not name its type | R14 | The bypass fix's invariant is that every blob names what it is. This one carries `u` and `n` and no `t`. Safe today because `readClientId` demands an array at `u` and no sibling has that member; a future blob gaining a `u` array reopens it |
| D-r14-e | Swift prints `argv[0]` verbatim as the entry point | R14 | Node resolves `argv[1]` to an absolute path so its command runs from any directory. A Swift router started by a relative path prints a command that works from one cwd only. Under launchd both are absolute |
| D-r14-f | The oauth lane races the re-index it does not await | G1 | It waits for the credential file then curls describe immediately. **5 green and 4 red in nine runs of one binary.** `Describe.swift` documents the race in its own comment — the post-authorization re-index is fire-and-forget. Either await it or stop asserting on a value that depends on it. This is what makes `parity-gate.sh` red on a branch that changed no file under `Control/` |
| D-r14-g | The delivery row cited a gate figure that is not that gate | G1 | `parity 358/358` is `make parity`'s vector census from `swift test`. `parity-gate.sh` is a 92-row wire surface and exits 1. Both numbers are real; a row should name which gate produced its number |
| D-r7-x | `CallbackLifecycleTests`' bind-once case races under whole-suite load | new item | `a listener binds once — reuse is refused rather than quietly racing` threw `the callback listener was cancelled before it bound` in 1 of 4 `make test` runs and 0 of 8 runs of its own suite. It binds a real loopback port at `port: 0`, stops, then rebinds the port it was handed, so a port the OS has not finished releasing fails the second bind for a reason the test reads as the bug it guards. Adjacent to `G3` and found the same way: under the full suite, not in isolation |
| D-r7-y | A name duplicate is settled before an entry's endpoints are read, so a conflict in one is never reported | R7 | Found by the Google lane on the 2nd gap-fix's own diff. `HarnessReconciliation.compare` matches on name and `continue`s before calling `HarnessDialect.resolve`, so an entry whose two spellings disagree AND whose name matches an upstream is counted as a `.name` duplicate and never appears in `unparsed`. Deferred because the entry is still counted — nothing goes silently to zero — and what is lost is a second finding about an entry already reported, a completeness gap rather than a wrong answer. Met inside arm P1, whose fixture named the harness entry after the upstream and so matched on name without ever reaching `resolve`; the arm was renamed rather than the defect taken Also recorded, from the other copy this merge brought: So a conflict inside one is never reported. Deferred because the entry is still counted — nothing goes silently to zero — and what is lost is a second finding about an entry already reported. Met inside arm P1, whose fixture named the harness entry after the upstream and so matched on name without ever reaching `resolve`; the arm was renamed rather than the defect taken |

**RULE — no literal `|` in a table cell, escaped or not.** A pipe inside a code span renders correctly in GFM when escaped as `\|`, and every naive `-F'|'` reader still splits on it: `D-r7-k` read 7 cells against a 6-cell register row before and after escaping. Found by R7's gap-fix runner in a row this orchestrator wrote. Describe the pipeline in prose instead — the row is read by scripts more often than by people, and a cell that renders right while parsing wrong is `G2`'s defect in miniature.
| D-p2-c | The import backup's mode | new item | The reference shares the bug |
| D-p2-d | The atomic writer on non-regular files | new item | A consequence of R1-D3 |
| D-p4-a | pool D6 contention | new item | 8/8 isolated reads correct; **not** filed as flaky |
| D-p4-b | A fresh worktree cannot run the parity gate unbuilt | G1 | — |
| D-p4-c | Derive the install rows from source too | new item | — |
| D-p4-d | `spec-R4.md`'s prose D-table lists only D1–D7 | R4-C | `D-v1g` is **stale as written**: `surface.tsv` already carries `div-r3-d1…d5` covering B23/B44, so the defect is in R4's prose and no row is missing |
| D-g3-a | Two fixed sleeps left in `PoolTests.swift`'s P2a, both vacuous-on-loss | new item | `:96` sleeps 20ms before opening the transport gate and `:102` sleeps 50ms before asserting the superseded session was closed. Neither can report a failure that is not there — losing the first lets the start install and shutdown force-reaps it, so the assertion holds either way, and the second is dead weight because both `pool.shutdown()` and the lease attempt are already awaited above it. Left because the failure mode is **proving less**, not going red, which is a different item from G3. Line numbers are **post-fix**, corrected under `D-g3-j` from the pre-fix `:92`/`:98` that made this row and `D-g3-b` use different numbering |
| D-g3-b | `PoolLifecycleTests.swift:116`'s 30ms before the follower shutdown | new item | P9 wants the second `shutdown()` to arrive with teardown still in flight. Lose the window and the follower arrives after teardown finished, and shutdown is idempotent, so it passes **vacuously**. Same class as `D-g3-a`: a test that stops meaning what it says rather than one that fails. The fix wants an observable for "teardown is in flight", which the pool does not currently expose. Line number corrected from `:114` to `:116` in gap-fix 2 under `D-g3-p` — `:114` is blank, and the two rows now share the delivered tree's numbering |
| D-g3-c | Sixty-odd fixed sleeps outside the pool suites are unsurveyed | new item | G3 surveyed and fixed the three pool suites (11 sleeps removed, 3 left as above). `grep 'Task.sleep' app/Tests` still reports around 60 more across `CallbackListenerTests`, `AuthFlowTests`, `AuthCleanupRaceTests`, `AuthRoutesTests`, `ServerStateTracker*`, `DiscoverBoardTests` and others, several of them 150ms–400ms positive assertions of the exact shape G3 was filed about. **None has been classified.** The seam pattern G3 established — read the arming, or await the event — is what a sweep would apply |
| D-g3-d | A `make test` failure was piped through `tail -6` and its name is unrecoverable | new item | 2026-08-21, inside the load-average-548 window: *"Test run with 1543 tests in 193 suites failed after 4.480 seconds with 1 issue"* survived, and the four lines naming the issue did not. `PoolReapingTests.swift:61` is the strongest candidate and the record says **unattributed**, because a strongest candidate is not a name. The fleet's evidence convention should require `make test` output to reach a file before anything truncates it |
| D-g3-e | The reap path cannot be driven by an injected clock | new item | Two of the three out-of-family reviewers named this as the textbook fix: `armReap` uses `ContinuousClock` and `Task.sleep` directly, so `TestClock` — which already exists in `PoolTestSupport` and already drives `idleSec` — cannot advance a reap. G3 did not take it because it changes how the router **schedules** production reaps in an item whose premise is that the product is correct, and because `PoolEntry.swift` carries a written argument for `ContinuousClock` over the injectable `RouterClock` that a clock-injection change has to answer rather than ignore. What it would buy: the last real `Task.sleep` in these tests (25ms and 30ms) and the `waitUntil` deadlock breaker both disappear |
| D-g3-f | `waitingCallers`'s sufficiency is an unenforced invariant on `acquire` | new item | The cohort tests are correct because nothing suspends between `pendingWaiters += 1` in `lease` and `await flight.task.value` in `acquire`, so the count cannot be observed before the joiner is parked. Codex and grok both flagged it: add one `await` on that path — a log line, a config lookup, a yield — and the poll can be early, the gate opens, the joiner takes a HOT acquire, and the test reports a spawn-count defect that is the test's. It is written in the accessor's doc comment and nothing enforces it |
| D-g3-g | `awaitSessionEnded` returns before the shutdown it is named for | new item | `sessionEnded` nils the handle synchronously then awaits `live.session.shutdown()`, releasing the actor; the guard then sees no handle and returns without awaiting the watcher, so `PoolLifecycleTests.swift:46`'s `shutdownCount == 1` can read 0. Natural: 0/500 uncontended, 0/74,830 under 32 spinners. Forced with a 150 ms shutdown delay it yields 0. Grok reached it independently. Narrower than the 80 ms sleep it replaced. **Not taken in the gap-fix** — the bound added there changes when the wait gives up, not what it waits for |
| D-g3-h | The two negative `armedReap` sites can mask a mutation rather than report one | new item | `PoolReapingTests:42` and `:55` read `armedReap` as a second hop. For a correct pool nothing can appear in the gap. For a mutated pool wrongly arming a 20 ms timer, the timer can fire and clear itself in the gap and `armed == nil` passes — a false green in the mutation gate, not a false red in CI. Both bit in practice |
| D-g3-i | `waitUntil` skips a final condition check when its poll overshoots | new item | `PoolTestSupport.swift:199-204` tests `now < deadline` before `condition()`, so a sleep waking past the mark reports a timeout without re-checking. Needs the condition to land in the last 2 ms of a 10 s wait. `awaitEvent` inherits it, being built on the same poll. **All three gap-fix panel lanes reached it independently** and each proposed the same two-line fix; left because it is registered and outside that gap-fix's scope, and because the exposure it adds is an event that takes ten seconds and THEN lands, not a 25ms window running long. `D-g3-k` would retire it entirely |
| D-g3-j | G3's brief misstated its own diff on four counts | G3-gapfix | **Three of the four corrected by the gap-fix; the fourth was not, and this row said otherwise.** Corrected: five test-only members described as three read-only accessors; the self-contradicting `Sendable` claim about `ReapTimer`, whose `struct ReapTimer {` is unchanged at `PoolEntry.swift:74` at both `e32b185` and HEAD — the wording is corrected again under `D-g3-v`, because "is not `Sendable`" is itself wrong; 960 ms of removed sleeps written as 950. **Not corrected: `D-g3-a` and `D-g3-b` were left on different numbering bases**, the exact defect this row was opened for — `D-g3-a` moved to post-fix `:96`/`:102` while `D-g3-b` kept `:114`, which the gap-fix commit `f85f29b` had itself shifted to `:116`. Closed in gap-fix 2 under `D-g3-p` |
| D-g3-k | A cancellation-aware wait would let a task group bound the awaits, and this repo already has one | new item | G3's gap-fix rejected a task group on the grounds that `await task.value` on a `Task<_, Never>` has no cancellation check, so the group awaits the loser and the run still takes ten minutes. True of that shape and **overstated as a general claim** — grok's correction, taken into the source. Make the WAIT cancellation-aware and a group abandons it properly: `AuthorizationURLBox` in `OAuthFlowStarter.swift` is exactly that construction, `withTaskCancellationHandler` around a continuation, written here for the same hang — a race whose losing child cancellation could not resume ran **91 seconds against a 20-second budget**. A continuation resumed by whichever of the event or the deadline arrives first would drop `awaitEvent`'s 2ms poll and retire `D-g3-i` with it. Not taken because the poll is measured and the handshake needs its own mutation evidence, plus a first-resume-wins guard against double-resume. The observer form shipped; this is the simplification, not a defect |
| D-r17-a | `VER2-R17-3` — the manifest read-window divergence is readable from source on the `index` and `import` verbs, and is filed as merely unmeasured | R19 | Swift routes every upstream through `ManifestIndexer.index` → `record`, which re-loads at `ServicePorts.swift:381` and saves at `:391` **per entry**; node's `cmdIndex` loads once at `src/index.ts:177` and saves once at `:186`, and `cmdImport` loads at `:101` and saves at `:146`. That is the same read-window disagreement `surface.tsv`'s `cli-watch` note declares for `watch`, on the writer R19's own reproduction drove — so it is a second instance of a declared divergence rather than a new one. **Established by reading the source, not by measuring it**, and said that way deliberately: `parity-cli.sh` runs the two binaries sequentially and cannot reach the property. Raised by R17's second verification, registered rather than fixed |
| D-r17-b | `VER2-R17-4` — LEDGER's compressed R17 row reads as though five save sites had been wrong | G1 | The row says *the orchestrator's five save sites corrected to three*. **Five is correct** — it is node's `saveManifest` count. Three is Swift's `ManifestIO.save` count, a different inventory, and the correction was that the two are not a pairing rather than that five was miscounted. ORCHESTRATOR's own R17 row states it properly, so the defect is the compression in LEDGER alone. Raised by R17's second verification, registered rather than fixed |
| D-r17-c | `VER2-R17-5` — the replacement oauth figure is as unstable as the one it replaced | G1 | `R17-acceptance.md` withdrew *21 of 21 both times* and put **19 of 21 twice** in its place as a measurement of this branch. The second verifier re-ran `parity-oauth.sh` standalone on this branch and got **21/21 twice** — the struck number. The document's *conclusion* survives and is arguably strengthened, since it is precisely that the count moves under unrelated load; what does not survive is the table presenting `19/21 each` as the branch's figure. A load-dependent count wants a range and a condition, not a second point estimate. Raised by R17's second verification, registered rather than fixed |
| D-r17-d | `parity-manifest-check.sh` false-reds on an unchanged, git-clean file, and four passes have each stated a condition the next measurement refuted | G1 | Found by R17's gap-fix 2 while running the gate, and **it reproduces on `main`'s `surface.tsv` as well as on the edited one**, so it is not this pass's. **The defect is real and proven. The condition is not, and this row deliberately states no reproduction rate** — a register row stating a rate is how each of the last three passes inherited a number the next disproved. **Mechanism.** `parity-manifest-check.sh:431` and `:437` pipe a `printf` of the list into `grep -qxF` per item and read **any** non-zero exit as *not found*, with no way to tell a genuine miss from a `grep` that failed to spawn. `:189` is the same shape for the cli list — it named `src/index.ts dispatches "serve"` for one verifier and `"tools"` for gap-fix 2 — and the control, authserver, mcp and oauth comparisons are built the same way. **Each subject named demonstrably has its row** (`control-registry-search` at `surface.tsv:50`, `fixture-add-refused` at `:75`), and the two lists the fixture comparison comes down to are byte-identical over 30 samples, so the inputs are stable and the flake is in the per-item comparison rather than in what it reads. **Direction is false-RED** rather than false-green. **The four measurement sets, as history rather than as a recipe.** Gap-fix 2 reported *about a quarter to a third* of roughly 60 runs, flat. The third verification measured **0 of 40 serial** on the branch and **0 of 40 serial** on main, with **53 of 104** on the branch and **24 of 72** on main at four concurrent — the concurrent figure on main being what settles the reproduces-on-main half. Gap-fix 3 re-measured and got **0 of 40 serial** and **29 of 80** at four concurrent. The fourth verification ran a quiet tree and got **0 of 40 serial, 0 of 80 at 4×, 0 of 96 at 8×, 0 of 96 at 16× and 1 of 96 at 32×**; that single red, on a git-clean 24-file fixture directory, is what proves the defect. **Its headline *368 invocations* is the concurrent subtotal** — 80 plus 96 plus 96 plus 96 — and the whole run is **408** with the serial 40 added, which is how the figure should be read wherever it is quoted. **The controlling variable is total machine pressure rather than this gate's own concurrency** — every high rate was recorded while other sessions were loading the box, and the fourth verification's quiet tree is where four concurrent copies produced nothing. **No condition is stated because none of the four sets survives the next one**, and the fleet-level gate hazard row records it the same way. **The both-directions contradiction is proven once and not reproduced since, so the mechanism is the best-supported account rather than a re-demonstrated one.** The third verification reported ten fixture names simultaneously in both directions — `add-refused`, `added`, `approve`, `auth-start`, `patch-response`, `removed`, `server-placarded`, `server-tools`, `servers`, `unauthorized`, each appearing both as *on disk and has no manifest row* and as *carries a row, which is not on disk* — over the git-tracked 24-file fixture directory with no local modifications, and gap-fix 3 reported the shape independently with `servers` in both directions over 80 runs. The fourth verification could not re-witness it: its single red gave direction A only. *Two mutually exclusive findings about one unchanging file can only come from the comparison* therefore rests on those reports rather than on anything re-witnessed since. **One difference from the fleet hazard row is recorded rather than resolved**: that row reads *not re-witnessed since the third verification*, which does not count gap-fix 3's `servers`, and neither pass's run can be replayed to settle it. **Operationally: read any manifest-check red seen while other work is running as unproven, and re-run it on a quiet machine before acting on it.** Registered rather than fixed: this item's scope carries no code |
---

## Needs input — not blocking any wave

| # | Question | Blocks |
|---|---|---|
| 1 | Apple Developer team ID and signing identity for Developer ID + notarization, and the App Store Connect app record for iOS | F1 can build and test unsigned; **release** artifacts for both platforms are blocked until these exist |
| 2 | Bundle identifiers — `app.fledgeling.mcprouter` / `.ios` assumed unless told otherwise | F1, changeable later but noisier after the App Store record exists |
| 3 | The phone currently queues but cannot install, narrowing the original "or the user can remote install them" | I3 ships the narrower behaviour; widening it is a later item, not a change to this fleet |

---

## Changelog

- 2026-08-15 — **Owner answers received and dispositioned** (`mcp-router-status-answers.json`, 6 of 6
  answered, 5 confirmed, 1 as-found, 2 flagged blocksAutomation). Eleven new pipeline items written to
  `planning/features-to-triage/` and the ledger. The pipeline root is **`planning/`, not `docs/`**;
  `docs/` is the published GitHub Pages site and this repo is public.

  | Question | Answer | Origin | Disposition |
  |---|---|---|---|
  | `cutover` | finish-first | own choice | **P1-P4** finish parity to what turned out to be **82 of 83**, then **R4-C** flips. The switch is licensed, but only once the number is complete |
  | `red-checks` | all-three | took the recommendation | **M13** + **G1** |
  | `deferred-plan` | schedule-all | **chose differently** — I recommended picking off the handful that were real gaps | **D1/D2/D3**, all 46 children batched by surface |
  | `review-rerun` | rerun-the-router | took the recommendation, **note qualifies it** | **V1**, on grok-4.6 rather than codex, per the note. Lane probe-verified before scheduling |
  | `phone-install` | allow-install | own choice, against the shipped default | **I4**. Widens the pairing threat model; the page stated that plainly and it was accepted |
  | `apple-identity` | give-me-the-id | **`as-found` — never confirmed**, blocksAutomation | **NOT scheduled.** `BLOCKED-apple-identity.md`. Its note points at a 1Password vault, and the bundle id it gives (`mcp-relay.fledgeling.app`) is domain-shaped rather than reverse-DNS and conflicts with the assumed `app.fledgeling.mcprouter`. Guessing would bake the guess into the signing identity and the App Store record |

  **Also registered: M6's seven deferred children (`D-m6-a` … `D-m6-g`), which M6 reported and nobody
  had written into the table.** That is the same unregistered-child gap that cost R2-R a whole item.
  The register is 46 rows, not 40.

- 2026-08-15 — **Wave M6 + I2 launched** `wf_6527714f-b4a`, two runners. Two, not four: a dAIolog
  runner is live on this machine and the four-wide waves died twice on `503 no-eligible-account`.
  Before launching, `ai/i2` was **rebased off a 37-commit-stale base** — its raw diff against `main`
  read as deleting `spec-M5/M7/M8`, `plan-M8` and four acceptance scripts, which is what a stale
  branch looks like and not what it contained. Clean rebase, 0 conflicts, then measured: the tree
  **does not build** (4 compile errors, 5 lint violations), so its runner inherits a precise failing
  set rather than a claim. Both briefs carry the owner's standing instruction on acceptance —
  **test only the surface you changed, and read `BoardRegistry.installed` before running anything,
  because a pass over a placeholder proves nothing and costs the owner tokens.**

- 2026-08-15 — **M7 merged `85d8331` — seven of eight panes.** The `<<<<<<<` SourceKit reported at
  `ShellTestSupport.swift:161` was a **stale index artefact, not a conflict**: no markers in either
  tree, and line 161 is a comment. Settled by reading both trees rather than by trusting either the
  diagnostic or M7's "tree clean". M7 was 0 behind `main`, so its tree *was* the merged tree; gates
  re-run on it by the orchestrator: lint **0 / 336 files**, **1073 tests / 137 suites**, **358
  parity**, `BUILD SUCCEEDED`. Post-merge re-verified on `main`: 1073 tests, HEAD moved.
  **M11 is a live red gate on `main`** (`mac-shell.sh` exits 1 at A22) and is deliberately NOT being
  fixed now — M6 changes the installed set to 8/8, which would invalidate any inventory regenerated
  today. It is M6's to close, or the orchestrator's immediately after M6 merges.

- 2026-08-15 — **Ledger corrected: five rows (M2, M4, M5, M7, M8) still read `Untriaged`,
  `Blocked on lint` or `Relaunched` after all five had merged.** Each merge SHA re-verified as an
  ancestor of `main` before the row was rewritten. A ledger that disagrees with `git` is worse than
  no ledger, because the fleet plans from it.

- 2026-08-15 — **M5 merged `2a81c87` (five of eight panes) and M8 `affaed6` (four), both under
  one-runner concurrency after four-wide died twice.** M5's merged-tree gates: lint 0 over 313
  files, **1021 tests / 131 suites run three times, three green**, 358 parity, `build-mac` ok, plus
  **32 behavioural assertions** across four fixture scenarios with the app never frontmost.

  **The two M5 findings worth carrying forward are both gates that lie.** A row *claimed*
  `.isButton` and published **no `AXPress`** — accepted-and-inert, so a check keyed on a return code
  passes it because the action genuinely is accepted and simply does nothing. And `declaration` sent
  `command`/`args`/`url` **raw** while the sheet displayed them **sanitised**: display ≠ execution,
  on the one surface whose entire purpose is knowing what will run. Also `missingRequirements` was
  dead code (Add with blank fields sent a credential-less declaration), and the fabricated-field
  grep read four Kit paths and **none of the five files that draw the screen**.

  **A sixth board-registry tripwire exists that git does not mark as a conflict**:
  `ShellIntegrationTests` pins the scaffolded count in a second place outside the conflicted region,
  so M5's rebase was clean and the suite was red anyway. Carried into M7's brief.

- 2026-08-15 — **Two defects were making every runner's gate unreliable; both fixed on main
  (`1cb3fd7`), and one of them I had filed under the wrong diagnosis.**

  **`D-p` was never a flake — it is a data race.** `StubHTTP` is `@unchecked Sendable` with a plain
  `var requested: [String]` appended from `get()`, while `Registry.search` queries the official and
  smithery registries **concurrently**: two tasks appending to one array unsynchronised, under an
  annotation promising exactly the safety the class lacked. A lost append reads as *"that URL was
  never requested"*. **Calling it flaky was the dangerous part** — flaky invites re-running until
  green, which would have preserved a real race indefinitely. Fixed with `NSLock`, scoped
  `withLock` because `lock()`/`unlock()` are unavailable from `get()`'s async context.

  Separately, M8's `pollingIsIdempotent` and its sibling slept a fixed 120ms then asserted a poll
  had run — 5/5 in isolation, **~4 failures in 5 under full-suite load** as M5 measured. Replaced
  with `ShellTestSupport.waitUntil`, which is also *faster* when healthy. `ShellTests`'
  `loadingIsTheAbsenceOfAnAnswer` looks identical and was **left alone deliberately**: it asserts a
  state *stays* put, so there is no condition to wait for and a fixed delay is the right instrument.

  Proof is repetition, not a pass: **8 consecutive full-suite runs, 8 green.** One run proves
  nothing about a race, and the first attempt at this fix did not compile at all — SourceKit's
  async-context warning was real rather than its usual cross-file noise.


- 2026-08-15 — **Capacity returned, the orchestrator took the recovery back from lifeline, and all
  four items relaunched with briefs that describe reality (`wf_997da1e0-2d0`).** A one-word probe
  (`claude -p` → `OK`) confirmed the outage had cleared before anything was spent on a wave.

  **Why take it back rather than let lifeline retry: lifeline replays the ORIGINAL prompt.** M5's,
  M7's and M8's all said `resume: fresh`, and by then M5 had 9 uncommitted files, M7 a design commit,
  and M8 six commits. A lifeline retry would have handed each runner a brief contradicting its own
  worktree. Both old runs were paused first so the two could not race.

  **The WIP rescue declined an hour ago was taken now, and the difference is control of the clock.**
  With lifeline paused and zero live processes verified immediately beforehand, committing is safe;
  while lifeline could fire at any second it was not. Four rescue commits, each labelled as the
  orchestrator's and explicitly **not claimed to compile or pass**: M5 `cf0acdc` (9 files), M7
  `a8169a9`, M8 `c799153`, I2 `e5f7fb5`.

  State the briefs were written from, rather than assumed: **M8** is closest — 6 commits, spec, plan
  and evidence — but its `installed` reads `[.servers, .settings]` because it branched before M4 and
  M2, so **its rebase will conflict on exactly the pair M2 hit an hour ago** and the brief says
  resolve as a union. **M5** is deep in Phase 4 with `.discover` already registered and five new
  files, but *one commit on its branch and that one is mine*, which is why the brief warns it looks
  emptier than it is. **M7** and **I2** both have a spec and no plan — Phase 3. Only M8 and M5 will
  trip the board-registry assertions; both briefs name that as the designed edit and flag the
  `ScaffoldedDestination(.x) != nil` trap that has to be repointed rather than renumbered.

- 2026-08-15 — **Both waves died at once on capacity, not code, and the correct response was to do
  nothing.** All five agents across `wf_67a6b2b6-231` and `wf_4dda644a-0ae` failed within minutes of
  each other on `503 no-eligible-account / over_reserve` (*"9 of 11 accounts at or over their usage
  reserve"*) and `429`. Five simultaneous failures with five different items and one identical cause
  is an outage; nothing here is a defect to diagnose.

  **lifeline already owns the recovery**: M5 and M8 `retrying` on `RATE_LIMIT`, I2 and M7
  `paused-usage-limit` with retry times that have since passed, all at attempt 1 of 30. A
  `resumeFromRunId` would recover nothing anyway — both journals have **results=0**, so replay
  misses on the first call and the miss flag is sticky — and a manual relaunch would cold-start work
  lifeline is holding.

  **Real work survived on all four, and it is deliberately left untouched.** M8 is furthest
  (5 commits), M7 and I2 have their Phase-1 commits, and **M5 has 0 commits and 9 uncommitted files**
  including `ShellModel`, `ShellWindow` and `ScaffoldPane`. The temptation is a WIP rescue commit,
  and it was declined: uncommitted files in a worktree are lost only to a hard reset or a worktree
  removal, neither of which happens on its own, whereas committing into a worktree whose runner
  lifeline may resume *at any second* is the two-writer hazard that has already bitten this fleet
  four times. **The exposure is hypothetical; the collision would be real.**

  I2's resume from the previous wave did work before the outage: it adopted the inherited 79KB mock
  and committed it as `I2 Phase 1`, which is the judgement its brief asked for rather than the
  assumption it warned against.

- 2026-08-14 — **M2 merged `c39c891`. Three of eight panes are real: `[.servers, .skills, .activity]`.**
  Merged-tree gates: lint **0 violations over 279 files**, **891 tests / 120 suites**, 358 parity
  vectors, `build-mac` succeeded, and **0 code files** differ between the merged tree and the tree
  those numbers were taken on.

  **This merge is the argument for gating the merged tree rather than the branch, and it is no longer
  hypothetical.** M2 and M4 each compiled and passed alone; together they **did not compile at all**.
  M4 added `skills()` and `marketplaces()` to `ControlAPIClient` after M2's three Activity test
  doubles were written, so all three stopped conforming. Three board-registry assertions then failed
  — correctly, since they pin the exact set and count precisely so that a board landing is a
  deliberate edit. One could not simply be renumbered: `ScaffoldedDestination(.skills) != nil`, named
  *"a scaffolded destination still builds one"*, lost its subject the moment M4 installed Skills, and
  fixing the counts around it would have left a test that no longer tested what it said.

  **A false alarm worth recording, because the trap is general.** M2's uncommitted delta removed
  seven `@Test` cases and added none — including the `BoardRegistry` complement guard — which is
  indistinguishable from a suite going green by deleting its assertions. It was not: those seven had
  already been *copied* into `ActivityBoardContractTests.swift` in an earlier commit, and removing
  the duplicates completes the move. So **822 is the honest count and 829 was double-counting**. The
  rule: *a working-tree diff cannot show a move whose other half is already committed*, and it
  renders identically to a deletion. Settle it by grepping both files at HEAD, never by reading the
  delta.

- 2026-08-14 — **Wave: M5 and M7 launched (`wf_4dda644a-0ae`), both unblocked by M4's merge, plus
  I2 resumed.** I2 was **dead, not slow** — 63 minutes since its last write, zero commits, and its
  only remaining process was a `python -m http.server` orphaned to PID 1 on port 8931. Its
  predecessor died in Phase 1 leaving one untracked 79KB mock nobody has judged; the brief says so
  rather than implying it is sound. Reaped that orphan; **left M8's two alone because M8 is live**
  and may still be serving a mock. Concurrency 4 with M8.

- 2026-08-14 — **M4 merged `7a28de8`: `BoardRegistry.installed` is `[.servers, .skills]` — two of
  eight panes are real.** M4 never needed resuming. It hit a 503, the harness retried it under a new
  agentId, and the retried agent did the bulk of the work and then stopped **without reporting** —
  the returned-early shape, not the died shape. What it needed was a merge.

  Gates re-run here on the rebased branch and again on the merged tree, deliberately, because
  **this branch stacks commits from two different runners** (a fork of the orchestrator ran an M4
  runner whose brief wrongly said its predecessor had died): lint 0 violations, **819 tests / 113
  suites**, 358 parity vectors, `build-mac` succeeded. Merged tree differs from the branch by
  `ORCHESTRATOR.md` alone — **0 code files** — and was re-gated rather than assumed.

  **The runner's best decision was refusing to fake a rendered pass.** With no accessibility grant
  it did not assert a string and call it proof: it moved inspector item 7's *decision* out of the
  view into `SkillPresentation.autoUpdateItem(for:in:)`, leaving the view a `switch` with no logic,
  and red-green proved both new guards. It also caught its own gate lying — the first `make lint`
  omitted `-C` and linted the **main checkout's 243 files** instead of the worktree's 257 — and
  re-ran it. Declared, not claimed: Empty, Loading, Partial, Offline and Error remain undriven, and
  **inspector item 7 has never been seen rendered by anyone**. That check is now the orchestrator's
  to close, since the interactive session holds the AX grant a runner under a recovered session
  does not.

- 2026-08-14 — **A runner under a lifeline-spawned orchestrator cannot do rendered UI verification,
  and the reason is TCC, not the code.** M4's second pass reported `axkit trusted` → `no` from two
  independently built binaries and correctly refused to fake a rendered pass. Verified from the
  interactive session immediately afterwards: `/tmp/m3-ax/axkit`, `/tmp/m4-pass/axkit` **and a
  freshly built binary all report `trusted` → `yes`**, with `front` → `Ghostty`.

  Both observations are true. The macOS accessibility grant belongs to the **responsible process**,
  and a runner beneath a headless `claude --resume … -p` process that lifeline spawned has a
  different responsible process from one beneath the interactive terminal session. M3 took real AX
  rows earlier because it ran under the terminal; M4 could not because it ran under a recovered
  headless orchestrator. Nothing was misconfigured and **no system permission needs granting.**

  Consequences, in order of usefulness: a rendered pass must run under the interactive session, so
  **the orchestrator can close a runner's blocked rendered check itself** rather than re-dispatching
  it; a runner that reports `axkit trusted: no` has hit this, and should say so and move on rather
  than treat it as its own defect; and `axkit front` keeps answering either way because it reads
  `NSWorkspace` rather than the AX API, so **`front` working is not evidence the grant is present**.

- 2026-08-14 — **Two orchestrators ran this fleet at once, and neither knew until an Edit failed.**
  lifeline (PID 41580) recovered this session by spawning **two** headless
  `--resume <same-session-id> -p "Resume workflow run wf_…"` processes at the same instant — 28866
  and 28892. Both replayed the same transcript, so both believed they were the sole orchestrator,
  and **both committed to `main`** (`0341b42`, `efddb0c`, `a33a7de` from one; `cd3be8d`, `cfb4eda`,
  `eb356df` from the other) and both launched fleet waves.

  **Neither detected it by looking.** One found out when its `Edit` failed with *"File has not been
  read yet"* on a file it had never touched; the other found out from commits in `git log` it had no
  record of making. Resolved by `ListAgents` → `SendMessage`, and 28866 stood down cleanly rather
  than being killed — it handed over its in-flight state, which is the only reason the next two
  facts are known.

  **Attribution between the two is not recoverable and was not worth recovering.** Both sessions
  claim the same commits, because a resumed transcript makes the other's pre-fork work
  indistinguishable from your own. The commits are on `main`, they are correct, and that is the
  part that matters. **Do not spend a turn litigating who wrote what after a fork.**

  What it actually cost: **`ai/m4` carries commits from two different runners.** The sibling's wave
  `wf_60e34389-efe` had an M4 runner that committed `ceeac1e` at 23:08:50; this session's
  `wf_2ff47aa9-981` runner committed `05f5e49` and is still live on top of it. The sibling's runner
  was working from a brief that said its predecessor had died, which was false. **M4's branch must
  be gated on the merged tree with that in mind** — two agents' understanding is stacked in it.

  The guard that held: `.worktrees/M2`'s abandoned split was **measured rather than assumed**. The
  handover recommended deleting three untracked files as half-finished; running them showed 829
  tests in 113 suites, exit 0, and violations down from 5 to 3. They were committed (`138b62c`)
  instead of discarded. *"It looks half-finished"* is a hypothesis, and the test suite is the
  instrument.

- 2026-08-14 — **`planning/watch-fleet.sh` had never run, once, all session (`a33a7de`).** It used
  `declare -A`, which needs bash 4; macOS `/bin/bash` is 3.2 and fails immediately. Every "watcher
  armed" claim this session was false, and the runner deaths it existed to catch were all found by
  hand instead. Now verified the only way that means anything: run it under `/bin/bash` explicitly
  and confirm it is **still alive** when a deadline kills it (exit 142), rather than confirming it
  started. A watcher that exits instantly and a watcher that is quietly watching look identical
  from the outside — which is exactly the failure it was written to detect in other things.

- 2026-08-14 — **`make lint` was hiding half its own output, and it cost two items a turn each
  (`cfb4eda`).** make stops a recipe at the first failing line, so a swiftformat failure meant
  **swiftlint never ran**. R2-R reported its lint clean while 31 violations sat behind a formatting
  failure; M2 reported ready-to-merge with 5 more. The shape is nastier than a silent pass: the
  target *does* exit non-zero, so nothing looks green — it just names one tool's problems and omits
  another's, so a runner fixes what it was shown, re-runs, and meets a fresh set it had no way to
  predict. Now all four linters run and the target fails if any did. Red-green proven both ways:
  green on `main` unchanged at exit 0 with all four running; red with a deliberate swiftformat
  violation gives exit 2 *and* swiftlint still runs, where that count was 0 before.

- 2026-08-14 — **lifeline is the second-writer mechanism, identified (PID 41580).** The daemon at
  `~/Dev/claude-lifeline` recovers a lost agent by **re-dispatching the whole run script**, not the
  one agent, and it labels every item in this fleet `TICKET-123` because it cannot parse item names
  out of the runner prompt. That is the process R2-R caught writing into `.worktrees/R2R` (PID
  24251), and at 22:5x it had **five** `--resume … -p "Resume workflow run wf_"` processes in
  flight, two of them replaying this session's own id.

  A resume instruction for `wf_67a6b2b6-231` arrived and was **declined**: M8's runner is live
  inside that run, so re-dispatching would have put a second `fleet-runner.js` into `.worktrees/M8`
  mid-plan-gate. The rule that follows is `workflow-resume`'s own and it is now load-bearing here —
  **a run with any live agent is never resumed**, whatever asks for it.

  It also had M4's original agent parked at `paused-usage-limit` 1/30, queued to retry into a
  worktree where a freshly-launched M4 was about to work. `lifeline_pause` on that agent is the one
  case pause genuinely covers (it gates retries of failed agents), so that collision was headed off
  rather than discovered afterwards.

- 2026-08-14 — **Capacity, not code, is the binding constraint tonight.** `503 no-eligible-account`
  — *"8 of 10 accounts at or over their usage reserve"* — killed M4 here and is visible in the
  anvil, proctor-mcp and dAIolog fleets simultaneously. Load average **62.7 on 16 cores**. That
  matters for verdicts, not just throughput: M2's one test failure at merge time was
  `completes(within: .seconds(2))`, a wall-clock deadline, missing under an 18.4s suite run that
  normally takes 3.0s. It passes 3/3 in isolation at 0.08s. **A wall-clock deadline in a test is a
  load sensor**, and under a fleet it reports the machine rather than the code.

- 2026-08-14 — **M4 died on capacity, not code; M2 hit a merge-only lint defect; both relaunched.
  M8 and I2 survived the session boundary and were left alone.**

  **M4** was reported lost to a `503 no-eligible-account` from the inference gateway. The disk said
  otherwise: `ai/m4` carries **7 commits**, `.skills` is registered in `BoardRegistry.installed`,
  and `planning/evidence/M4-acceptance.md` is written. It was killed *mid-edit*, leaving an
  uncommitted 5-file delta that is good work and currently broken — it fails to compile
  (`'SkillPresentationStateTests' has no member 'testPluginSkill'`) and pushes a test file to 453
  lines against the 400 cap. Worth keeping because it fixes two real defects: a filter badge
  counting the **unsearched** set, so `Held 1` sat above a list saying nothing was held; and the
  `All` filter with a non-matching search falling through to no message at all, drawing column
  headers over blank space. Relaunched to finish it rather than restart.

  **M2** returned ready-to-merge and its own numbers held on the rebased tree — **822 tests / 111
  suites**, parity 358 — but rebasing onto the R2-R main turned lint red. This is a **merge-only
  defect**: R2-R brought a stricter formatting and lint config, so M2's earlier files fail rules
  that did not exist when they were written. Red on neither branch alone. `make format` fixed three
  files, and — the same trap R2-R documented — that unmasked **5 structural swiftlint violations**
  that had been invisible behind `swiftformat --lint`'s short-circuit. Relaunched as a lint
  close-out with its acceptance evidence explicitly ring-fenced from re-running.

  **Two orchestrator errors worth keeping.** First, I ran `make format` and `make lint` inside M2's
  worktree while my own backgrounded `make build-mac` was still running there, and got
  `** BUILD FAILED **` — `build.db … database is locked. Possibly there are two concurrent builds
  running in the same filesystem location.` A self-inflicted race that reads exactly like "M2 does
  not build". **The orchestrator gates a worktree or a runner owns it, never both at once.**
  Second, `git rebase main` printed *"Current branch ai/m2 is up to date"* while its own reflog
  showed five `rebase (pick)` entries and a `rebase (finish)`. Another case of the word after the
  command not being the verification — ancestry and the reflog are.

  **M8 and I2 are alive** and were not touched. A 45-second no-write probe on their worktrees
  returned nothing, which is a false death signal: both were sitting in adversarial `claude -p`
  spec and plan gates, which think for minutes and write nothing. Liveness was settled by walking
  the gate processes' parents to a live session (PID 92491), not by file mtime.

- 2026-08-14 — **`wf_03c742d3-20a` reported `completed` having lost M4 to a 503, and a workflow
  resume was the wrong instrument.** The run returned 2 of 3: R2-R (merged), M2 (ready-to-merge),
  and **M4 dead** on `API Error: 503 … no-eligible-account, over_reserve` — a death with zero
  retries that the run still reports as completed.

  **The resume was rejected on liveness, not on cache economics.** By `journal started=3 results=2`
  the arithmetic favours a resume: two cached hits, one re-run. But the cache miss flag is sticky,
  and a miss on M2 spawns a *second* M2 runner into its worktree. M2 is demonstrably still working:
  its report names `ai/m2 @ 5d15aff`, **`5d15aff` is not an ancestor of `ai/m2`** (it rebased), the
  branch now contains `cd3be8d` — a ledger commit made minutes ago — and `make test` and
  `make build-mac` are live in `.worktrees/M2`. lifeline reports that agent `done`; the process
  tree and the reflog disagree, and on this repo the process tree has been right every time.
  **A fifth two-writer incident is not worth two cached replays.**

  M4 is **not dead, and the recovery was called off before it started.** Within minutes of the
  paragraph above being written, `ugrep` was running in `.worktrees/M4`, dozens of `swift-frontend`
  processes were seconds old, and the task list moved M4 Phase 4 to completed and Phase 5 to
  in-progress. **The harness retried M4 under a new agentId** — a documented behaviour — so the
  original agent's transcript is frozen at 22:49 forever and lifeline still reports that agent
  `paused-manual` with `lastClass: USAGE_LIMIT`. Both are true statements about a *corpse*, and
  neither is a statement about the item.

  **Agent-keyed state cannot answer "is this item alive".** That is the third time this session
  the two disagreed, and the item-keyed answer was right all three times. `planning/watch-fleet.sh`
  already encodes the fix — liveness per ITEM across transcript, worktree and process cwd — and it
  was consulted last rather than first, which is how a live runner came within one tool call of
  getting a second writer. The order is: process tree and worktree first, journal and lifeline
  second, and never the other way round.

  Net effect: **nothing was resumed and nothing was relaunched.** M2, M4, M8 and I2 are all live
  and untouched, which is the correct outcome of this scan.

- 2026-08-14 — **The parity gate's verdict depends on the name of the directory it is run from
  (`D-o`).** Re-running the gate on merged `main` from the repo root returned **68 of 82 with 1
  DIVERGED**, where R2-R had reported **69 of 82, 0 DIVERGED** on a byte-identical tree. Neither
  number was wrong about the code and neither runner was careless: `parity-fixture.sh:121`
  normalises attributed projects with `"project":"[A-Za-z0-9]+"`, a class that **omits `-` and
  `_`**. A call's project is the directory it came from, so `R2R` normalises and `mcp-router`
  does not, and the `fixture usage` row reports `recorded="<project>" live="mcp-router"`.

  **The reason it survived every review is the interesting part.** Runners work in worktrees named
  `R2R`, `M2`, `I1` — alphanumeric, all of them — so no runner could reach the bug, and R4's three
  adversarial gates and R2-R's independent re-measure all ran from inside one. It is reachable only
  from the repo root, which is exactly where the cutover decision gets taken. A false DIVERGED
  there is worse than a missing row, because the lesson a reader takes from it is to discount
  DIVERGED.

  Registered as `D-o` and **not fixed here**: the diff is one character class and it moves coverage
  *up*, which is the one direction the orchestrator should not move a number it is also reporting.
  It goes to R4 with the mechanism and the proof attached.

- 2026-08-14 — **Twelve unregistered work items found and registered — the R2-R failure repeating,
  seven-fold.** R2-R's evidence groups its 13 blocked parity rows "by the item that would unblock
  them" and names `D-j`, `D-k`, `D-l`, `D-m`, `D-r2r-a/b/c`, `R2-W` and `R4-C`. **Not one of them
  appeared in this ledger or in `LEDGER.md`** — the deferred table stopped at `D-g`, and `D-h`
  through `D-n` lived only inside `spec-R2.md`'s and `plan-R2R.md`'s own tables. `spec-R4.md:68`
  had already written the general form of this down — *"`R2-R` is registered nowhere … the single
  largest missing piece of the Swift router is named only in a deferred table"* — and the same
  thing was true of eleven more items at the moment it said so.

  Two are real work items, now in the ledger rather than in prose: **`R2-W`**, the `~/.claude.json`
  watcher and its adoption protocol — `install.sh` installs a `watch` launchd agent that still runs
  `node dist/index.js` even when `MCPR_ROUTER_BINARY` is set, because there is no Swift watcher to
  point it at — and **`R4-C`**, the cutover itself, blocked on **82 of 83** (the user decision is made; `fixture-registry-search` is a standing exclusion).

  The one that should worry a future reader most is **`D-n`**: a row missing from `surface.tsv`
  shrinks the denominator, so **deleting a row raises the coverage figure**. That hole is *partly*
  guarded already and the ledger should not overstate it — `scripts/acceptance/parity-manifest-check.sh`
  runs at `parity-gate.sh:49` and derives the **control** and **fixture** rows from source, so a
  deletion there fails the gate. The **43 rows in `cli`, `mcp`, `install`, `divergence`, `pool`,
  `state` and `log` have no such derivation**, and `D-n` covers the two most mechanical of those
  (`src/index.ts`'s ten `case` arms and `src/router.ts`'s endpoints). **`D-r2r-b`** is the same
  shape one level down — 11 `control` rows are proven against `ControlDiff`, an in-process oracle,
  not against the socket R2-R just made reachable.


  The lesson is mechanical, not moral: a deferred child named in a spec is invisible to the fleet.
  Registration is the orchestrator's job and nobody else's, and the check is cheap — grep every
  item id a runner's report mentions against this file before accepting the report.

- 2026-08-14 — **R2-R merged `62678aa`: the router is now a process, and R4's gate went 50/81 → 69
  of 82 with 0 DIVERGED.** The five lanes R4 could not measure at all — `mcp`, `cli`, `install`,
  `state`, `log` — are measurable because the thing they measure now exists. Merged-tree gates were
  re-run here rather than taken on the runner's word: lint **0 violations over 243 files**, **750
  tests / 106 suites**, **358 parity vectors**, and the merged tree is byte-identical to the gated
  tree (`163597f7`), so the numbers describe what landed.

  Three things worth keeping. **The lint fix was structural, never a raised limit** — `RouterService`
  split into composition root / dispatch / collaborators, `MCPEndpoint` split, and
  `StdioUpstreamTransport.open` into spawn + handshake; the honest violation count turned out to be
  **31, not 29**, because swiftformat's own wrapping pushed three more files past the 400-line cap
  after the first pass. **One config change, and it settles a real tool deadlock**: swiftformat's
  `wrapMultilineStatementBraces` and swiftlint's `opening_brace` demand opposite brace positions,
  verified by moving a brace by hand and watching swiftformat put it back — narrowed to
  `opening_brace: ignore_multiline_statement_conditions`. And the runner **hashed the source before
  and after its gate run** and reported the hash, which is what let the merge trust a number
  produced hours earlier.

  **A fourth two-writer incident, and the first one that cost nothing.** A resume of the older run
  `wf_48b3dafa-109` re-dispatched `fleet-runner.js` into `.worktrees/R2R` while R2-R was working,
  creating `AuthVerb.swift` and `StdioUpstreamSession.swift` under it. By merge time that process
  was dead, the worktree was clean, and both files were committed inside R2-R's own history — so the
  gated tree already contained the intruder's work and the gate passed over it. That is luck, not a
  control. **The control is the merged-tree gate**, which is why it is run every time even when the
  branch is already at main's head and the rebase is a no-op.

- 2026-08-14 — **Wave: M8 and I2 launched (`wf_67a6b2b6-231`), and the wave is two items because the
  DAG says two.** M5 and M7 wait on M4, M6 waits on M5, I3 waits on I2 — all still in flight or
  unstarted. Concurrency is 4 with M2 and M4 live. Reclaimed M3's worktree and branch (merged at
  `bf08ecb`, clean, holding only two orphan processes from its finished runner).

- 2026-08-14 — **R4 refused the cutover, and the refusal is the most valuable thing the fleet has
  produced.** Its parity gate exits 1 at **50 of 81 rows**, and the blocked lanes are structural,
  not a matter of effort: `mcp` 0/5, `cli` 0/10, `install` 0/5, `state` and `log` 0/1 each.
  **There is no Swift router process to cut over to.** `RouterCore` is a library; the only
  `NWListener` in it is R5's single-shot OAuth callback; `docs/install.sh` writes launchd agents
  running `node dist/index.js serve`. Verified here independently before acting on it, because it
  invalidates a standing plan.
  The cause: R2 shipped Phases 0–2 and deferred the relay, listener, HTTP clients and composition
  root to **"R2-R" — a name that appeared in R2's plan, in no ledger, and was owned by nobody.**
  Now registered as a first-class item on the critical path, with R4's gate as its acceptance test
  and an explicit instruction not to edit the gate to make it pass.
  All three of R4's reviews rejected its **coverage number**, correctly: it had been 50 of 74 and
  was overstated five ways — a lane recording `blocked` read as proven, group-blind reconciliation,
  `proven-by-suite` counting because a test merely existed, a pool lane naming Swift tests it never
  ran, and a route extractor that saw 15 where there were 16. The denominator rose 71 → 81 once six
  missing rows were added, so **their absence had been inflating the reported coverage.**
- 2026-08-14 — **I1 merged.** 566 tests in 86 suites, 12 iOS tests on one reused simulator. The
  substantive fix was two `try?` sites discarding a Keychain failure: a refused save rendered the
  "Paired." success surface while nothing was written, so the pairing vanished at the next launch
  with nothing having said so. Its in-family Phase D critic caught that
  `PhoneStorageFailureTests.swift` was **untracked** — the fix would have committed with no tests
  while `make test` still reported a rising count.
  Two orchestrator errors worth recording. `git merge -q -F -` with a heredoc silently failed
  (`could not read file '-'`) and a `;` let the "merged" echo print anyway; the tell was the gate
  reporting 456 tests where I1's own count was 566. **A merge is verified by the test count moving
  and HEAD changing, not by the word that follows it.** Separately, backticks inside a `git commit
  -m "…"` were eaten by zsh and dropped a word from R5's pushed merge message — commit messages go
  through a heredoc file, never `-m` with backticks.

- 2026-08-14 — **Four items merged after the fleet was killed and restarted: R2, F4, R3, R5.**
  `main` went `b093122 → a8091bb → aba30bd → e154bae → b7c527c`, each merge gated on the
  **merged** tree rather than the branch. Final state: 456 tests in 68 suites, 358 parity cases,
  lint clean.
  The lost runs were **not resumed**, deliberately. The scanner showed all three as `no-snapshot`
  with results far under started (1-of-3, 0-of-2, 0-of-3), and replay stops at the first miss and
  re-asserts stale results — so a resume would have paid nearly full price *and* carried forward
  claims that were never true. Each item was relaunched instead with a brief handing it what its
  predecessor had actually established, so F4 inherited "M50–M54 killed, M55 survived" rather than
  re-running the gate, and R3 was told to close out rather than rebuild.
  What building for real found, which no double could: R5's `NWListener` exposed a
  **`CheckedContinuation` double-resume in `AuthFlow.cleanup`** — it cleared `current` after two
  awaits, so a callback landing during teardown settled the flow and cleanup then resumed the same
  continuation again, trapping and killing the daemon. Unreachable against the fake, whose `stop()`
  never suspends. R3's differential harness ran the Swift handler against the **running** TypeScript
  router: 32/32 rows, three of which kill the reference (`TypeError`, `URIError`) where Swift
  answers 400.
  Conflict resolved at the R5 rebase exactly as predicted: R3's `coreFiles + controlFiles` structure
  won, R5's auth entry became the first element of `coreFiles`, both assertions kept, and the floor
  ratcheted 352 → 358 — left at 352 the auth corpus could have been deleted without failing.
  **Concurrency cut to 3.** I1's own report named the cause: its iOS build was `Killed: 9` by
  "memory pressure from the concurrent fleet". Five parallel Swift/Xcode builds were thrashing the
  machine, agents died, lifeline retried them, and the retries thrashed it again.
- 2026-08-14 — **The fleet was killed at the user's instruction, and the orchestrator could not do
  it.** Workflow agents are async tasks inside the `claude` process, not child processes. `TaskStop`
  resolves only ids held in the current context and a compaction had wiped them; `lifeline pause`
  gates retries of *failed* agents and does nothing to a healthy one; killing OS processes stopped
  builds that were immediately respawned. The session's own process was the only lever, and it
  exited before the kill landed. **The process tree was the first thing to check and was checked
  last** — three wrong "it's stopped" claims were made before it was.

- 2026-08-14 — **F4 died a second time, and left a mutant in the source.** It ran the
  mutation gate as a background task and polled its output file for a sentinel; the task
  was killed at 14:56:09 without writing one, and the poll never returned because the child
  died with the parent. Mutant **M56** was left applied in `ServerStateTracker.swift`
  (`guard snapshot != lastPublished` rewritten to `if false { return }`) — applied to disk,
  killed before it could run or revert. Since F4 must merge before wave 4, that is
  deliberately-broken code one merge away from `main`. Reverted, the real work committed as
  `ca32ee4`, and F4 relaunched in `wf_196b1c68-865` with the cause named in its brief.
  Inherited by the relaunch rather than re-run: M50–M54 KILLED, **M55 SURVIVED** (a real
  coverage gap — no test observes the notification lost when `register` is deferred into a
  `Task`), M56/M57 never ran. Also flagged: `ai/f4` predates the hooks commit, so its diff
  proposes deleting `planning/hooks/*` and reverting `watch-fleet.sh` — rebase before merge.
- 2026-08-14 — **R5 reported a second writer in its worktree; there wasn't one.** It found
  `Auth/` files it did not recognise, a package resolve it did not remember starting, and a
  subagent citing `FileModeWriting.swift` by path. It stopped rather than raced and committed
  only its own files by explicit pathspec (`0fad8c0`) — exactly right given what it believed.
  Checked before answering, because if it had been right the correct action was to stop:
  across every agent transcript in the session, `.worktrees/R5` has **21 Edit/Write calls,
  all from R5 itself**, four of them the very files it disowned. The resolve was its own
  `swift build`; the subagent was the one plan-gate agent it spawned. Cause is almost
  certainly compaction — 323 entries — which its brief already covers with a re-read rule.
  Told to resume; it owns `ai/r5`.
  Its finding was still worth having: **`DELETE /servers/:name/auth` is already shipped on
  `ai/r3`**, so R5 drops it rather than building a second implementation that can silently
  disagree.
- 2026-08-14 — **Watcher, revision 6: a journalled result no longer retires an item.** R5
  exposed the hole — an orchestrator message resumes a stopped runner, that turn journals a
  result, and the runner then works for another half hour with nothing watching it. Liveness
  alone now decides whether to fire; the result only changes what the event means (`STOPPED`,
  owes a report, versus `QUIET`, probably died). Added a third liveness test ahead of both:
  **a live process whose cwd is inside the worktree**, one `lsof` per pass for all items.
  I1 forced that one — its `xcodebuild` writes DerivedData *outside* the worktree, so 18
  minutes of real compiling read as 18 minutes of nothing to a file-mtime check.
  The proving needed a negative control, because the first red run fired **zero** and that
  looked like a pass: R3, M1 and R5 had all started builds between probes, so the new gate
  suppressed everything and a broken gate would have looked identical. `FLEET_REPO` is now
  overridable purely so it can be pointed somewhere no process can match — under that
  control all 8 items fire, R5 included, and the real repo stays silent.

- 2026-08-14 — **Two R3 runners were editing `ai/r3` at once for ~18 minutes, and I put
  the second one there.** When auth was split out into R5 I relaunched R3 with a corrected
  brief ("auth split out") in a new workflow run — and never stopped the original, which
  was still running the pre-split brief in the run that also carries R5. So one branch had
  two writers, and R5's scope had two owners. Found by accident: the liveness watcher's
  denominator listed R3 in two live runs. Both prompts were read before acting, and the
  ledger's own row (*"Partial — relaunched, auth split out"*) named which one was intended.
  The stale runner was not stoppable by `TaskStop` — workflow-inner agents are not tasks —
  so it was stopped by message, told explicitly not to commit, revert or clean, and to hand
  back findings instead. It had already committed `2a1121e` with `git add -A` four minutes
  earlier, sweeping up the surviving runner's in-flight P6 work.
  **Kept, not reset.** `reset --soft` would leave every file byte-identical, so it buys only
  a more accurate commit message — and it would hand a *live* runner an unexpectedly dirty
  index mid-turn. That is the same live-worktree hazard this fleet already got away with
  once, and attribution is not worth spending it on. The content is entirely in-scope R3
  work on R3's own branch; no `Auth/` sources or OAuth routes reached it, so R5 is
  uncontested. Verified rather than assumed: `git ls-tree` for Auth sources, and
  `ControlHandler` carries only `DELETE /auth` and the 401 path, which are control-surface
  and R3's by right.
  Its stop report was worth more than its code: three further live port defects (all now
  fixed on the branch), B70's cache implemented from the reference's real semantics, the
  parity corpus at 352, a **spec** defect where B69's "never a partial identity" cannot
  coexist with B71's equality-with-the-reference, and a correction retiring a plan-gate
  finding as latent rather than live. All of it forwarded to R5, whose brief carried the
  now-stale 224 floor and the unresolved B69 contradiction.
  Two mechanisms changed. Runners are told a message costs them their turn; the orchestrator
  is told to reply promptly, since a runner awaiting a reply looks exactly like a dead one.
- 2026-08-14 — **The codex lane is down fleet-wide until Aug 20**, reported by the R5
  runner and reproduced here with a one-word probe: an account-level usage limit, past this
  fleet's horizon. The three out-of-family gates now run in-family as adversarially-briefed
  `claude -p` opus-5 reviewers, logged as `codex: usage limit -> claude (downgrade)` in each
  artifact. Recorded in the contract above so in-flight runners see it on their next
  pre-call re-grep — that file is the only kill-switch that reaches a running runner — and
  in `planning/fleet-runner.js` so future launches inherit it.
  The dangerous half: **`codex exec` exits 0 on a usage limit.** Any gate keyed on `$?` would
  have recorded a pass for a review that never ran. Only the log's ERROR line and an empty
  `-o` file distinguish them.
- 2026-08-14 — **The liveness watcher was measuring the wrong thing and reported two false
  deaths.** It keyed on one agent's transcript mtime, so it called M1 quiet at 16m while M1
  was mid-build, and F4 quiet at 24m while F4's gate output was seconds old. Two distinct
  causes, one fix: a transcript is appended when an agent *speaks*, and an agent thirty
  minutes into a `swift build` writes thousands of files and not a byte to it; separately,
  the harness retries under a new agentId, leaving the original's transcript frozen forever
  with no journalled result. Liveness is now judged **per item**, from the newest of every
  agent's transcript *and* the item's worktree (walking the tree, plus `.build/build.db`
  directly, since that one file is touched throughout a compile). Item keying folds a retry
  and its corpse into one row for free.
  Proved both directions before trusting it: silent at real thresholds while M1 and F4 were
  working, and **9 of 9 unfinished items firing** at `FLEET_QUIET=0`. The first red run used
  `FLEET_QUIET=1` and printed only 7 — a transcript written that same second reads as 0s of
  silence, which is not `-lt 1`. A denominator two short is exactly what a coverage hole
  looks like, and it took a second run at 0 to show it was the threshold, not the code.

- 2026-08-14 — **I1 returned early and the fleet read it as delivered.** The runner
  finished Phase 1, wrote a genuinely good design report — 12 sections, 30 phone frames,
  both appearances — and ended its turn. A returned turn is a *success* to the harness, so
  `agent()` journaled a result, nothing retried it, and the item looked complete while no
  spec, no plan and no code existed. Its only artifact sat **untracked** in the worktree,
  one `git clean` from gone.

  This is a different failure from a death and hides better: a dead agent leaves an error,
  this one leaves a good report. The tell was liveness, not output — its transcript stopped
  at 12:43 while the other three were still writing. Worth noting the two adjacent states
  it was distinguished from in the same sweep: R2 looked equally idle on disk but was alive
  inside a 10-minute codex plan gate, and an earlier check reported all four worktrees
  untouched, which was a **broken predicate** (`find -newermt` with a relative time returns
  nothing on BSD find) rather than four idle runners. Uniform zeros are a bug until proven
  otherwise.

  Actions: Phase 1 committed by the orchestrator as `af0234f`; I1 relaunched from Phase 2
  in the same worktree on the same branch, with the failure named in its resume brief; and
  `planning/fleet-runner.js` now carries "finish the whole item in one turn — a phase report
  is not a deliverable", with the instruction that a report naming its own incompleteness is
  recoverable while one that looks finished is not.

- 2026-08-14 — **A runner pushed to `main`, and the instruction against it is now a hook.**
  A wave-3 runner committed `04eac69` ("Ignore .worktrees/") in the shared main checkout and
  pushed it to origin. The change is **correct and kept** — an untracked `.worktrees/` is a
  real hazard, one `git add -A` from the root would commit another branch's whole working
  tree — but it moved the integration branch under a merge sequence that assumes one writer.
  Mid-merge it could have corrupted the tree.

  Every runner prompt already said stop before merge, so the instruction is not the control.
  `.git/hooks/pre-push` now refuses any push without `MCPR_ORCHESTRATOR=1`, proved in both
  directions (refused without, allowed with). Worktrees share the hooks directory, so it
  covers wave 3's in-flight runners too — which matters, because a fleet cannot message its
  own workflow-inner agents. `planning/fleet-runner.js` carries the explicit rule for waves
  4–6. The hook is scaffolding for this run; remove it when the fleet finishes.

- 2026-08-14 — **CI red on the merged main, and the test was wrong rather than the code.**
  `31763577290` failed one assertion: the stream-liveness check timed from *before* the
  connection opened, charging URLSession construction and the TCP handshake to stream
  latency, so a contended runner read 0.52s against a 0.36s bound while streaming
  correctly. Replaced the wall-clock budget with the ordering property the docstring
  already stated — the stub records when it sent its last line, and the first record must
  arrive before that instant. No threshold left to tune. Green on `8e9c689`
  (`31764012564`). The first red-green proof was itself void: `swift test --filter` on the
  *display* name matched nothing and reported `0 tests in 0 suites passed`, which is a gate
  that never ran wearing a pass. Re-proved against the function name.

- 2026-08-14 — **Wave 3 launched: M1, R2, R3, I1.** Four slots. All four wire-verified
  `claude-opus-5` on the first launch.

  That first launch **died whole in 27 seconds** — two runners on `Connection refused`,
  two on `Connection lost mid-response`. Recorded because the signature is easy to
  misread as wave 2's capacity outage and the remedy is opposite: `ps -o etime` showed the
  local gateway had been up **2m07s**, so the launch landed mid-restart. Not capacity, not
  code. Nothing was lost — no worktree, no branch, `started=4 results=0` — so recovery was
  a fresh launch, not `resumeFromRunId`, which would have replayed nothing while
  re-asserting an empty cache. Before relaunching, the lane was proved end to end with a
  real one-token request rather than trusted from `/healthz`: a health flag says the
  process is up, not that a request can obtain an account.

- 2026-08-14 — **Wave 2 cleared: F2, F3 and R1 all merged**, serially, each gated on the
  merged tree rather than on its own branch. `22d1802` → `13825c9` → `c30eac9`; final
  merged tree `make all` exit 0, **237 tests**, `no-raw-design-values: clean`. All three
  worktrees removed and branches deleted, each proved merged by `git branch --merged`
  first. Seven deferred children registered above.

  **The merge found a defect no branch gate could have.** F3 was green on `ai/f3` and red
  the moment it merged: five tests failing on one missing fixture. `.gitignore` carried a
  bare `servers.json` for the router's runtime config, and an unanchored gitignore pattern
  matches at *every* depth — so it silently swallowed
  `app/Sources/MCPRouterKit/Control/Fixtures/servers.json`. The file stayed on disk in the
  author's worktree, which is exactly why its own gate passed. Both runtime-state patterns
  are now anchored (`/servers.json`, `/manifest.json`) and the fixture is committed. This
  is the merge-only defect class again: the break existed on no branch.

  Both merges conflicted in `app/Package.swift` and both were purely additive — F2's
  `MCPRouterUI`/`MCPRouterUITests`, F3's `ControlProbe`, R1's `RouterCore` product,
  `RouterCoreTests` and the exact-pinned MCP SDK. Kept all of them; the SDK stays confined
  to `RouterCore`, which neither app target links, so the kit's no-external-dependencies
  promise still holds for everything the apps compile.

- 2026-08-14 — **A12 met and wave 1's exit gate cleared.** `main` pushed
  (`e5a61ce..e15b31d`, 10 commits) and Swift CI executed for the first time: run
  31747021039, `build-and-test: success`. This is the first verification of F1 that did
  not happen on the authoring machine — every prior green was a warm local toolchain.
  The `pages-build-deployment` run also succeeded and `docs/` was untouched in the diff,
  so mcp-router.fledgeling.app is unaffected.
- 2026-08-14 — **Wave 2 relaunched into the contended pool** at the user's instruction,
  riding lifeline's retries rather than waiting for the `~/Dev/hopper` fleet to finish.
  All three wire-verified `claude-opus-5`; two took 503s within the first minutes and
  backed off, as expected. Each carries a RESUME brief naming its existing worktree and
  branch, forbidding a fresh worktree, and pointing at its pause checkpoint.

- 2026-08-14 — **Wave 2 died on capacity, not code.** All three runners took
  `503 no-eligible-account` — "9 of 11 accounts at or over their usage reserve". The
  gateway pool is shared, and `lifeline` shows **another live fleet in `~/Dev/hopper`**
  with agents in flight. Relaunching into that starves again, so wave 2 is **paused, not
  failed**, and nothing has been discarded.

  The journal reads `started=6 results=0`, so a `resumeFromRunId` would replay **nothing**
  — the recovery is a re-run in the existing worktrees on the existing branches, never a
  fresh start, because all three died LATE:

  | Item | Branch | Gate now | Died at |
  |---|---|---|---|
  | F2 | `ai/f2` (4) | `make test` exit 0, 65 tests, clean | mid Phase-D critic, after two codex lane failures |
  | F3 | `ai/f3` (2) | `make test` exit 0, **93 tests** | entering the red-green proving pass |
  | R1 | `ai/r1` (6) | **RED — does not compile** | mid-write of `VectorRegistry.swift` |

  Orchestrator actions taken while the pool is contended:
  1. **Rescued 52 orphaned files.** F3 died with 28 uncommitted and *nothing* on its
     branch; R1 with 24 and a broken build. Both are now WIP commits, R1's deliberately
     red and labelled as such — losing the files is worse than a red commit on a branch
     that is never merged in that state.
  2. **Wrote pause checkpoints into all three specs**, since no runner survived to write
     its own: exact stopping point, what is on disk, the diagnosed-but-unfixed defect, and
     the next three steps. A resume reads those instead of re-deriving state.
  3. Confirmed each branch's gate independently rather than trusting a report.

  **Resume is blocked on capacity, which is the user's call, not a code fix.**

- 2026-08-14 — **Wave 2 launched: F2, F3, R1.** Three slots.
- 2026-08-14 — **F1 merged as `0924040`.** Verified independently rather than on the
  runner's report: protected files diffed clean (`DESIGN.md`, the ledger, this file,
  `install.sh`, `package.json`, `src/`), `make all` re-run to exit 0 on the **merged**
  tree, and the token-parity gate proved able to fail — changing `DESIGN.md`'s ground
  colour by one digit fails the suite. A gate that cannot fail is not evidence.
  Four things the run surfaced, recorded rather than smoothed over:
  1. **Two runner attempts died and were retried by the harness** before the third
     returned; the journal holds three `started` entries and one `result`. The surviving
     runner correctly read the on-disk work as a resume rather than restarting.
  2. **A runner wrote to this file, which its prompt forbids.** Its content was accurate
     and has been absorbed here, but the edit was reverted and re-authored by the
     orchestrator. Ownership is reasserted at every merge rather than trusted to the
     instruction — that is the control that actually holds.
  3. **A12 (CI) has never executed.** The workflow is delivered and calls the same
     Makefile targets, but nothing is pushed, so wave 1's "CI green" exit gate is
     **not met**. Recorded as unmet, not waived.
  4. **~1,800 lines of the earlier hand-rolled scaffold were deleted** (`ServersView`,
     `DiscoverView`, `ServerDetailView`, `MenuBarView`, `ActivityView`, `CleanupView`,
     `SettingsView`, `RootView`). Consistent with the brief, and recoverable from
     `97d4a55` — M1–M8 may want it as reference.
  Also: `make acceptance` needs an Accessibility grant and fails *safe* (exit 2) without
  one, so on hosted CI it will report blocked rather than green.

- 2026-08-14 — A task notification reported wave 2 stopped with "no completion record"
  and instructed a relaunch with `resumeFromRunId`. **Declined — the premise was false.**
  The scanner reports the run `LIVE · session-alive`, one agent still writing, and F2/F3
  worktrees held by live processes with an active `swift test`. Relaunching would have
  dropped a second set of agents into worktrees already being written to. It would also
  have bought nothing: `started=6 results=0`, so the replay cache is empty and a resume
  cold-starts regardless. The notification's `TICKET-123` is lifeline's placeholder id,
  not one of ours. Six starts against three items = the harness retrying; the recurring
  cause on every agent is a **session/usage limit**, which is throttling this wave rather
  than killing it. Left alone; a tracked waiter is armed for the settle. Journal resolves
  under session `bdb1ad3b`, so nothing is orphaned — but note compaction can mint a new
  session id and silently orphan a journal mid-run, which would break any later resume.
- 2026-08-13 — Fleet size confirmed with the user: **all 18 items**. Runner lane verified
  on the wire (`claude-opus-5`), not merely configured. Wave 1 launched: F1 alone, since
  every other item depends on it. Deviation from the skill's serial pre-triage, stated:
  ids are pre-allocated in the ledger and runners are forbidden from writing LEDGER.md at
  all, which removes the shared-write hazard rather than locking around it.
- 2026-08-13 — Preflight: pipeline rooted at `planning/` (docs/ is the published Pages
  source); practices copied from bella-team-files with the Swift gap recorded; router
  work committed as `2e70229`; `DESIGN.md` authored from the verified prototype tokens;
  18 briefs written; ledger and wave plan built. No fleet slot has started.
