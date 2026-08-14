# M7: Evals and Cleanup

**Status:** Ready for Work
**Depends on:** M1 (shell) ✓ merged · M3 (Servers board) ✓ merged · M4 (Skills board) ✓ merged
**Design representation:** `design/mocks/html/m7-evals-cleanup.html` — authoritative over
`design/mocks/prototype.html` per DESIGN.md's own precedence rule.
**Plan:** `planning/plans/plan-M7.md`
**Deep links:** `?only=mac&pane=evals`, `?only=mac&pane=cleanup`

---

## Feature description

Two panes sharing one subject: **evidence about whether a capability earns its place**. Evals
carries evidence of *fitness*; Cleanup carries evidence of *use*.

From the brief:

> **Evals** — run a skill or server's eval suite, see the result per check, and see the history
> across versions. An eval result is evidence attached to a version, so it must be invalidated when
> the version changes rather than carried forward.
>
> **Cleanup** — surface capabilities that are installed and unused. Two rules learned the hard way:
> never a trash metaphor — a never-used server was never deleted; and never an automatic cull —
> invocation count conflates "unused because worthless" with "unused because rare but critical", so
> the app proposes and the human decides. Show never-used as a value in the existing column plus a
> filter, not as a separate screen.

---

## The problem this item had to solve first

**The brief is not implementable as literally written, and the reason is structural rather than a
matter of effort.**

Verified rather than assumed. `grep -rniE '\beval' src/ app/Sources/RouterCore/` returns nothing:
there is no eval endpoint in the control API, no eval field on any wire type, and no eval runner
anywhere in this product. Two merged items already recorded the finding in source and deferred it
here:

- `ServerPresentation.swift:170` — *"The prototype fills it with an eval chip reading `passed` or
  `not evaluated`; there is no eval field on a server anywhere in the control API and no `eval` in
  `src/control.ts`, so that chip has nothing behind it and §6 rules it out. **Evals are M7's.**"*
- `SkillsBoard.swift:8` — *"there is no eval runner in this product at all"*, and
  `SkillPresentation.swift:49` tells the user *"evaluations arrive with Evals"*.

So M7 is expected to deliver something, and the thing named cannot be delivered.

### Two independent impossibilities, and only one of them is temporary

1. **No runner exists.** Nothing in this product can call a server's tools with fixtures and grade
   the replies. A router item could add one.
2. **A skill can never be graded by the router, ever.** A skill is markdown the *client* loads into
   an agent's context. It never traverses the router, so no execution of it is observable to the
   process that would have to grade it. **No future router item changes this.** The prototype's
   Evals pane grades eight cases against a skill (`pr-summariser`), which is unbuildable twice over.

### The resolution

M7 ships **the checks the router genuinely performs and reports**, stamped to the version each was
observed against and invalidated when that version moves — which is the brief's one hard rule and
the actual design content of the feature. `POST /servers/:name/reindex` really does re-perform the
handshake, so "run checks" really runs something.

A second opinion was taken on this fork before any code was designed (`claude-fable-5`, high
effort, briefed adversarially and asked to argue against the recommendation first). It agreed, and
attached three conditions that are now binding on this spec:

- Never render an aggregate labelled *eval*. The unit is a **check**, and a verdict appears only
  beside the statement it judges.
- The disclosure is **structural** — the pane's permanent subtitle, where M3 and M4 put theirs —
  never a footnote.
- The deferred runner is filed **servers only**. Promising skill evals again is the one mistake this
  spec exists to stop being repeated.

Its own strongest objection is recorded here rather than buried, because it is the risk this design
carries: *calling derived status checks "evals" may be a rename that dresses up data already shown
on two other boards; a user could read "passed" and believe a test suite ran.* The naming discipline
above is the mitigation, and A17–A20 test it.

---

## What the router actually observes

Every check below is a pure function of a wire type the control API already serves. Nothing is
derived that the router did not send.

### Server checks — from `MCPServer`

| id | Statement shown | Observed from | `unknown` when |
|---|---|---|---|
| `indexes` | The router can start it and read its tool surface | `indexError`, `indexedAt` | `indexedAt == nil` — never attempted |
| `declaresTools` | It offers at least one tool | `tools` | it has not indexed |
| `authorized` | Its credentials are current | `auth.supported`, `auth.authorized` | — (**not applicable** when `!auth.supported`) |
| `surfaceApproved` | No tool description is waiting for review | `pendingChange` | — |
| `operative` | It carries no placard | `placard` | — |
| `callsSucceed` | Its calls come back without error | `usage.calls`, `usage.errors` | **`usage.calls == 0` — never exercised** |

### Skill checks — from `Skill` + `SkillsResponse.slotClients`

| id | Statement shown | Observed from | `unknown` when |
|---|---|---|---|
| `reachable` | At least one client can load it | `presence` | any client `.unreadable` and none `.present` |
| `versioned` | It carries a version a result can be stamped against | `source` | — |
| `originUnchanged` | Its marketplace still resolves where the router first saw it | `provenance` | — |
| `updateWantsNoMore` | Any newer version held asks for nothing extra | `held.addedCapabilities` | — |
| `described` | Its `SKILL.md` declares a description an agent can route on | `description` | its directory was unreadable |

**`callsSucceed` is the load-bearing one.** Zero calls with zero errors is arithmetically a clean
record and is **not** a pass — it is `unknown`, worded "never exercised". A check that reports
success for something nobody has ever done is the same defect as a fabricated number.

### The fingerprint

| Subject | Fingerprint | Why |
|---|---|---|
| server | `hash` | The digest of the tool surface. It *is* the version of the thing being checked — more precisely than a version string an upstream can leave unchanged while its tools move. |
| skill | `source.plugin.pluginVersion` | A skill's version is its **plugin's** version, shared by every skill that plugin supplies. M4 established this and named the field accordingly. |

Three renderings, not interchangeable:

- **current** — stored stamp equals the live one. Verdicts show as the current reading.
- **invalidated** — stored ≠ live. Verdicts dim to `--t4` and are labelled *"was 0.4.1, now 0.5.0"*.
  Never shown as a current pass. The run **stays in history** under its own fingerprint —
  invalidation is not deletion.
- **unstampable** — no live fingerprint exists (`hash == nil`, or a `.standalone` skill). Checks run
  and display; **no result is stored**, because nothing could ever invalidate it.

### A standalone skill cannot hold a result, structurally

M4 modelled `SkillSource` as a closed enum whose `.standalone` case has **no version field at all**.
So the `versioned` check failing is not a tidiness nag — it is the pane explaining its own
behaviour. The store refuses the write; it is not a rule the view remembers to follow.

---

## What the router cannot observe, and what happens to it

| The prototype draws | Verdict | What ships instead |
|---|---|---|
| 8 graded cases on a skill, per-case verdicts, a failing transcript, `18.4s` | **Fabricated / impossible** | The five structural skill checks above |
| Skills filtered by `runs === 0`; `installed 4mo ago, never invoked` | **Fabricated** — M4 refused to model `runs` for exactly this reason | Reachability: a skill present in *no* readable client is loadable by nobody, which *is* observed |
| "Judging over 4 months of history" | **Hardcoded** | `UsageResponse.since`, rendered as the observation track |
| "why it might be idle" → `no reason found` | **Speculation** — the router does not observe whether a project was opened | The column is removed |
| `Remove` on a skill row | **Uncallable** — the control API is read-only for skills | A dimmed control with its reason, plus *Show in Finder* |
| Any memory or byte saving | **Already refused** by DESIGN.md §6 | Nothing, and the footer says why in one sentence |
| Pass verdicts painted `color:var(--live)` | **Colour misuse** | `--t1`. See below. |

### A pass is never green, and this is a rule

DESIGN.md §2 binds `--live` to exactly one meaning — *a child process is running* — and states that
nothing else in the app may be any of the three indicator hues. A check that passed is not a running
process. The prototype paints its pass verdicts `color:var(--live)`, which is the same defect
DESIGN.md §10 already records against the prototype's phone Discover list, in a new place.

`--fail` **is** available for a failed check, because that is literally what it means. `--attn`
stays reserved for conditions that genuinely want a human decision: a held version asking for more,
a marketplace whose origin moved, and the weak-window banner in Cleanup.

---

## What M7 writes, and the one write it does not

| Write | Route | Notes |
|---|---|---|
| Re-run a server's checks | `POST /servers/:name/reindex` | Genuinely re-performs the handshake |
| Re-run a skill's checks | `GET /skills` | Re-reads every client directory; there is no per-skill read |
| Remove a server | `DELETE /servers/:name?keepHistory=` | Reuses M3's `remove(_:keepHistory:)` and its dialog copy |
| Reset call history | `POST /usage/reset` | Already on the client |
| **Remove a skill** | **none** | The control API is read-only for skills. Dimmed, with the reason. |

Check results are persisted **locally by the app**, not by the router. This is app state, not a
second channel: it records the router's own observations stamped with time and fingerprint, which is
provenance rather than fabrication, and it is the only way to satisfy "history across versions" and
"invalidated when the version changes".

---

## The Evals pane

### Header
Title "Evals". Subtitle, permanent and present even while loading, because it is a statement about
the product rather than about the data:

> The checks MCP Router runs itself, stamped to the version each was run against. No model-graded
> evaluation exists in this product.

Trailing: **Run all checks…** (standard, not accent-filled). `…` because it opens a sheet.

### Filter — segmented, switches the view in place (§3.6)
`All` · `Failing` · `Unchecked` · `Invalidated`, each with a count. A zero count carries no badge at
all rather than reading "0" — M4's precedent.

### Columns and rows
`subject` (30pt tile + 180pt name/sub) · `kind` (58pt) · `checks` (170pt tally) · `checked against`
(150pt stamp) · trailing action. Row height 44pt, fixed.

The tally reads `4 passed · 1 failed · 1 unknown` in mono, with only the failed segment tinted
`--fail`. **It is never rendered as a single word.**

### Footer
> A check is something MCP Router performed and can show you the input to. It is not a graded test of
> whether a capability does its job well. Skills are never executed by the router, so nothing here
> reports how one behaved when an agent used it.

### The inspector
Per-check rows: verdict + statement + a reason line for anything not passing. Then `checked against`
(fingerprint + when), then **history** — newest first, each row carrying its own fingerprint, so two
runs against different surfaces are visibly different evidence and never merged.

History is capped at 20 runs per subject, oldest evicted.

---

## The Cleanup pane

### Header
Title "Cleanup". Subtitle names the window from `UsageResponse.since`:

> Capabilities MCP Router has never seen used, judged over the calls it has recorded since 4 July.
> It proposes; you decide.

Trailing: **Reset call history…**

### Inclusion rules

| Subject | Listed when | Never listed for |
|---|---|---|
| server | `usage.calls == 0` over the recorded window (`MCPServer.neverUsed`), **or** `indexError != nil`, **or** indexed with `tools == 0` | "last used a while ago" — the prototype's `last > 3600` is an invented threshold |
| skill | every skills-capable client was **read** and reports `.absent` | **anything about invocation** |

**An unreadable client suspends the judgement rather than making it.** If any skills-capable client
is `.unreadable`, a skill absent everywhere else is *not* a candidate — it may be installed in
exactly the folder nobody could open. Those are held out and counted in a banner.

### The observation track — the second subject-mined element

DESIGN.md §10 records that the breaker is the app's only subject-mined element and asks any new
surface to add a second. This is it.

The question Cleanup exists to answer is *how much do we actually know*, and the answer is dominated
by one number nobody looks at: how long the router has been recording. "Never used" over 41 days is
evidence; over two hours it is nothing, and every table that shows only the verdict renders those
identically. The track draws the observation window at its real length against a 30-day reference,
with the real figure in mono beside it, so nothing depends on reading the bar. Under 7 days it tints
`--attn` — at its own meaning, "wants a human decision".

A pane-level banner fires when `since` is under seven days:

> **Call history was reset 2 hours ago.** Everything below reads as never-used because there is
> almost nothing recorded yet, not because it is unused. Give it a few days before acting on this.

### Actions
- Server: **Remove…** → M3's named-consequence dialog, using
  `ServersBoardModel.removeToolsConsequence` and `removeConsequence` **verbatim**.
- Skill: **Show in Finder** (real, local) + **Remove** dimmed with its reason.
- **No accent-filled action anywhere in this view.** §3.4 allows one prominent action and forbids
  destructive as the default; the only thing this pane proposes is a removal, so the correct number
  is zero.

### Footer
> These sit in every session's tool list, where a model reads them. Nothing here claims a memory
> saving: MCP Router never runs the world in which every server is resident, so it has no figure to
> subtract from. Nothing is removed unless you remove it, and what you remove is not counted.

### Why a dialog, when DESIGN.md §8 says removal is "undoable, never confirmed"
Because it is not undoable, and M3 already measured why: `describe()` in `src/control.ts` sends
`envKeys: Object.keys(u.env).sort()` — key *names*, never values. An app that cannot read a secret
cannot restore an entry carrying one. §9's escalation clause governs: a named-consequence dialog
whose destructive button is never the default. Cancel leads. A server carrying no secrets gets the
other branch of M3's copy, which says it can be re-declared exactly.

---

## Keyboard and the menu bar

| Key | Evals | Cleanup |
|---|---|---|
| `⌘6` / `⌘7` | select the pane (already bound by `Destination.selectionDigit`) | |
| `⌘F` | focus the filter field | focus the filter field |
| `↑` `↓` | move the selection | move the selection |
| `Return` | run checks on the selection | open the selection's inspector — **not** remove |
| `Esc` | dismiss sheet, then clear selection | dismiss sheet, then clear selection |
| `⌘⌫` | — | named-consequence sheet for the selected **server**; no-op for a skill |
| `⌘R` | run checks on the selection | — |

§3.9: every command appears in the menu bar, dimmed with the same reasons the in-pane controls give.

---

## The nine states (§5) — with real copy

Both panes ship all nine. Full copy is in the design representation; the table below is the index.

| State | Evals | Cleanup |
|---|---|---|
| Default | populated board | populated board |
| Empty | "Nothing to check yet" + *Add a server…* | "Everything here has been used" (no action); separate under-filter message |
| Loading | skeleton at 44pt row geometry, subtitle present, counts absent | same |
| Partial | unreadable client → checks `unknown`, banner naming the client and the reason | unreadable client → skills held **out** of the proposal, banner counting them |
| Error | against the row, carrying the router's `hint` | a refused removal leaves the row in place |
| Success | in place; tally + stamp update, history gains a row, no toast | row leaves, counts decrement, **nothing tallied** |
| Offline | `ControlAPIError.routerNotRunning` verbatim + *Start the router* | same strings |
| Disabled | four controls, each with its reason | *Remove* on a skill, with its reason |
| Overflow | truncate at 180pt, row height fixed | same |

Plus **stale** — a reading no longer current — following M3/M4's banner.

---

## Acceptance criteria

### The boards are installed
- **A1** `.evals` and `.cleanup` are both in `BoardRegistry.installed`, and `ShellIntegrationTests`'
  existing complement assertion passes with them there.
- **A2** The three merged tests that pin the exact set are updated in the same change:
  `installed == [.servers, .activity, .skills, .evals, .cleanup]` and `scaffolded.count == 3`.
- **A3** Selecting Evals renders `EvalsBoard` and Cleanup renders `CleanupBoard`, never
  `ScaffoldPane`. `ScaffoldedDestination(.evals)` and `(.cleanup)` both return `nil`.

### What is displayed is what is observed
- **A4** No view, model or copy function references a run count, last-run time, duration, byte
  figure or memory saving for any subject. Enforced by a source guard test over
  `MCPRouterUI/Boards/Evals*` and `Cleanup*`, in the style of `PhoneSourceGuardTests`.
- **A5** `callsSucceed` returns `.unknown` for every `MCPServer` with `usage.calls == 0`, whatever
  `usage.errors` is. Asserted over the cross product, not over examples.
- **A6** `reachable` returns `.unknown`, never `.failed`, whenever any skills-capable client reports
  `.unreadable` and no client reports `.present`.
- **A7** Cleanup's candidate list excludes every skill when any skills-capable client is
  `.unreadable`, and the banner states how many were held out.
- **A8** Cleanup's subtitle and the observation track derive their window from
  `UsageResponse.since`. No literal duration appears in any Cleanup copy function.
- **A9** The weak-window banner appears iff `since` is under 7 days, and its copy names the real
  elapsed time.

### Evidence is stamped, and invalidated rather than carried forward
- **A10** A stored result whose fingerprint differs from the live one renders as *invalidated* and
  its verdicts render at `--t4`. There is no input for which a stale verdict renders as a current
  pass.
- **A11** An invalidated run remains in the inspector's history under its own fingerprint.
- **A12** The store refuses to persist a result for a subject with no live fingerprint — a
  `.standalone` skill, or a server with `hash == nil`. Structural, not a view-level guard: the
  persist call returns without writing and a test asserts the file is unchanged.
- **A13** History is capped at 20 runs per subject; the 21st evicts the oldest.

### The actions
- **A14** *Run checks* on a server issues exactly one `reindex` for that server and no other write.
- **A15** *Remove…* on a Cleanup server row renders M3's `removeToolsConsequence` and
  `removeConsequence` strings verbatim — asserted by comparing against the functions, not by
  duplicating the literals.
- **A16** *Remove* on a skill row is disabled in every state, and its reason string is present and
  non-empty. There is no code path from Cleanup to a skill write.

### Naming discipline
- **A17** No copy function in either board returns a string that is exactly `passed`, `failed`,
  `pass` or `fail` as a standalone aggregate. Per-check verdicts are only ever produced together
  with the statement they judge.
- **A18** The Evals subtitle contains the sentence "No model-graded evaluation exists in this
  product", and it is returned unconditionally — including in the loading state.
- **A19** The Evals footer states that skills are never executed by the router.
- **A20** No string in either board contains "eval suite", "test suite", "eval case" or "graded".

### Colour and the native floor
- **A21** No passing verdict resolves to `ColorToken.live` anywhere in either board. Asserted as a
  token-level test, not by reading source.
- **A22** `--attn` appears in these boards only for: a held version wanting more, a moved
  provenance, and the weak-window banner. `--fail` only for a failed check and a failed write.
- **A23** Cleanup renders zero accent-filled buttons. Evals renders at most one per view.
- **A24** Every token used resolves through `ColorToken` / `MetricToken` / `TypeToken`;
  `scripts/lint/no-raw-design-values.sh` passes.
- **A25** Section headers are sentence case; no tracked uppercase.

### The nine states
- **A26** Each of the nine states renders for each pane, and each unhappy path's copy is asserted
  against the string the model returns — not against a placeholder.
- **A27** The loading skeleton's row height equals the populated row height exactly (44pt), so
  neither board jumps when data lands.

### The keyboard and the menu bar
- **A28** `⌘F`, `↑`, `↓`, `Return` and `Esc` behave per the table above in both panes, and `Return`
  in Cleanup does **not** remove.
- **A29** `⌘⌫` in Cleanup opens the removal sheet for a selected server and is a no-op for a skill.
- **A30** Every command appears in the menu bar with the same enablement reason as its in-pane
  control.

---

## Triage — 2026-08-15

### Grounding — what exists and is reused rather than rebuilt

| Reused | From | Why |
|---|---|---|
| `ControlAPIClient` — `servers`, `skills`, `usageSummary`, `reindex`, `remove`, `resetUsage` | F3 | The whole callable surface M7 needs already exists |
| `ServersBoardModel.removeToolsConsequence` / `removeConsequence` | M3 | Public statics, already testable without a host; one wording per state (§6) |
| `ConnectionFailurePane`, `StaleReadingBanner`, `MessageState`, `SearchField` | M3/M4 | Offline/error/stale/empty are identical in construction |
| `MCPServer.neverUsed` | M3 | Already modelled, with a comment naming Cleanup as its consumer |
| `SkillPresence.unreadable` | M4 | The third case is what makes Partial expressible |
| `Destination.badgeSource` `.cleanup: .serversNeverUsed`, `.evals: nil` | M1 | Already decided; not reopened |
| `Icon.cleanup` = `arrow.down.circle` + its anti-trash comment | M1 | Already decided; not reopened |

### Where the code goes

| Path | Contents |
|---|---|
| `MCPRouterKit/Checks/CheckModels.swift` | `CheckVerdict`, `CheckResult`, `CheckSubject`, `Fingerprint` |
| `MCPRouterKit/Checks/ServerChecks.swift` | The six pure functions over `MCPServer` |
| `MCPRouterKit/Checks/SkillChecks.swift` | The five pure functions over `Skill` |
| `MCPRouterKit/Checks/CheckCopy.swift` | Every statement, reason and disclosure string |
| `MCPRouterKit/Cleanup/CleanupPresentation.swift` | Inclusion rules, the observation window, its copy |
| `MCPRouterUI/Boards/EvalsBoard*.swift` | Board, model, row, inspector |
| `MCPRouterUI/Boards/CleanupBoard*.swift` | Board, model, row, inspector, remove sheet |
| `MCPRouterUI/Checks/CheckHistoryStore.swift` | The bounded local store |

The kit stays free of UI frameworks (`SWIFT_PRACTICES.md` §8), so every rule above is testable with
a constructed `MCPServer` / `Skill` and none of it needs a host — M3's precedent exactly.

### Stated deviations from the prototype

Recorded in full in the design representation's §0 table. In summary: the entire Evals pane is
replaced; Cleanup keeps its honesty paragraph and its shape and loses `runs`, the invented idle
threshold, the speculation column, the hardcoded window and the skill `Remove` button.

### Assumptions recorded — autonomous run, no human to ask

1. **"Eval" is delivered as "the checks the router can run".** The alternative — an honest empty
   pane — ships a placeholder, which this fleet forbids, and would fail M4's stated promise more
   completely. Second-opinioned; see above.
2. **The destination keeps the name "Evals".** `Destination.title` is a merged shared surface;
   renaming it to "Checks" is reported, not made. The permanent subtitle carries the disclosure,
   which is why it is a subtitle and not a footnote.
3. **Check history is persisted locally, bounded at 20 runs per subject.** The brief asks for
   history across versions and the router stores none.
4. **The observation track's reference is 30 days.** A rendering scale, labelled, with the real
   figure in mono beside it.
5. **The weak-window threshold is 7 days.** Chosen so a fresh reset and a week's holiday both trip
   it; the banner states the real elapsed time either way.
6. **Cleanup lists servers and skills in one list**, filtered by a segmented control, rather than as
   two screens — the brief's "not as a separate screen" applied.

### Open questions — raised, not guessed

None that block. The two worth a human's eye are in the report: whether to rename the destination,
and whether the graded runner is wanted as a router item.

### Deferred children discovered

| Suggested id | Title | Deps |
|---|---|---|
| R6 | Router-side behavioural eval runner — **servers only** | R3, R4 |
| R7 | Skills write endpoint (remove/disable) with preconditions and undo | R3 |
| R8 | Server soft-delete with a restore endpoint, so removal can be undone | R3 |
| M9 | Rename the `Evals` destination to `Checks` | M1, M7 |

### Shared-surface changes wanted and deliberately skipped

- `Destination.title` `.evals` → "Checks". Reported; not made.
- `BadgeSource` cannot express "checks failing" as an Evals badge. Not added — it would be a new
  badge source for a count that is derived rather than served, and `.evals: nil` is currently
  correct.

---

## The spec gate — in-family, and what it found

**codex: usage limit → claude (downgrade).** The out-of-family lane is unavailable for this fleet:
every `codex exec` call returns an account-level usage limit until 20 August, and `codex exec` exits
0 on that limit, so a gate keyed on its exit code would record a pass for a review that never ran.
The gate was run in-family instead — a fresh `claude -p` Opus 5 reviewer, briefed adversarially and
told that finding no defects is a failed review rather than a pass. **This weakness travels with the
evidence:** every reviewer in this item's pipeline is Claude auditing Claude.

Verdict and tallies are appended below by the gate run.
