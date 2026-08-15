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

| id | Statement shown | Observed from | Not observed / not applicable when |
|---|---|---|---|
| `indexes` | The router can start it and read its tool surface | `indexError`, `indexedAt` | **not observed** when `indexedAt == nil` — never attempted |
| `declaresTools` | It offers at least one tool | `tools` | **not observed** when it has not indexed **or `indexError != nil`** — a stale count from a since-failed index is not evidence |
| `authorized` | Its credentials are current | `auth.supported`, `auth.authorized` | **not applicable** when `!auth.supported` |
| `surfaceApproved` | No tool description is waiting for review | `pendingChange` | — |
| `operative` | It carries no placard | `placard` | — |
| `callsSucceed` | Its calls come back without error | `usage.calls`, `usage.errors` | **not observed** when `usage.calls == 0` — never exercised |

`usage.calls`, never `callsServed`. `MCPServer` carries both, and they mean different things:
`callsServed` is this router process's lifetime tally, `usage.calls` is the recorded window that
`POST /usage/reset` clears and that `since` describes. Every sentence on both panes is scoped to
"the calls it has recorded since <date>", so `usage.calls` is the only field consistent with what is
said. The gate raised this; it is stated rather than left to the implementer.

### Skill checks — from `Skill` + `SkillsResponse.slotClients`

| id | Statement shown | Observed from | Not observed / not applicable when |
|---|---|---|---|
| `reachable` | At least one client can load it | `presence`, **`slotClients[].status`** | **not observed** when no client reports `.present` and any skills-capable client's `status == .unreadable` |
| `versioned` | It carries a version a result can be stamped against | `source` | — |
| `originUnchanged` | Its marketplace still resolves where the router first saw it | `provenance` | **not applicable** for a `.standalone` skill — it has no marketplace to have moved |
| `updateWantsNoMore` | Any newer version held asks for nothing extra | `held` | **not applicable** when `held == nil` — no newer version is offered, so the question does not arise |
| `described` | Its `SKILL.md` declares a description an agent can route on | `description` | — (binary; see below) |

Four corrections the gate forced, each of which was a pass being reported for a question nobody
asked — the same defect as `callsSucceed`, which the first draft applied to exactly one check:

- **`declaresTools`** was reporting a pass from a `tools` count left over from an index that has
  since started failing. Now not observed whenever `indexError != nil`.
- **`updateWantsNoMore`** was vacuously true for every skill with no held version, which is most of
  them. `held == nil` is now *not applicable* — the same treatment `authorized` gets when a transport
  carries no credentials.
- **`originUnchanged`** was asserting an origin is unchanged for a `.standalone` skill, which has no
  origin at all. Now not applicable for that case.
- **`described`** claimed a "not observed" state for an unreadable directory. **There is no such
  field.** `Skill` carries no per-skill readability, `SkillClientStatus.unreadable` is a property of
  a *client*, and a skill whose own directory could not be read does not appear in
  `SkillsResponse.skills` at all. The check is binary over `description`, and the phantom column is
  gone.

**`reachable` reads two types, and the gate was right that the first draft conflated them.**
`SkillPresence.unreadable` lives per-skill-per-client in `Skill.presence`;
`SkillClientStatus.unreadable` lives per-client in `SkillClient.status`. `presence` is a dictionary
and a key may simply be **absent**, so an absent key is not evidence of absence. The rule is
therefore: `.present` anywhere ⇒ confirmed; otherwise if any skills-capable client is `.unreadable`
by *either* signal ⇒ not observed, naming the client; only when every capable client was read and
none has it ⇒ not met. An `.unsupported` client never contributes to either branch.

### The vocabulary is observation, not grading

The gate's strongest argument was that `passed` / `failed` is the vocabulary of a test suite, and
that using it is what makes a re-tabulation read as a grade however carefully the subtitle is worded.
It is right, and the words change:

| Verdict | Word shown | |
|---|---|---|
| `.passed` | **confirmed** | the router observed this to hold |
| `.failed` | **not met** | the router observed this not to hold |
| `.unknown` | **not observed** | the router has not seen enough to say |
| `.notApplicable` | **not applicable** | the question does not arise for this subject |

This also collapses a name collision the gate found: the first draft had a filter segment reading
*Unchecked* beside a row tallying *unknown*, one letter apart and meaning different things. There is
now one name per state, which is what DESIGN.md §6 asks for.

**`callsSucceed` is the load-bearing one.** Zero calls with zero errors is arithmetically a clean
record and is **not** a pass — it is `unknown`, worded "never exercised". A check that reports
success for something nobody has ever done is the same defect as a fabricated number.

### The fingerprint — corrected after the spec gate

**The first draft of this section was factually wrong, and the gate caught it.** It claimed
`MCPServer.hash` is "the digest of the tool surface". It is not. `src/control.ts:163` sends
`hash: upstreamHash(u)`, and `src/config.ts:98` computes that as:

```js
const material = isStdio(u)
  ? JSON.stringify(['stdio', u.command, u.args, u.cwd ?? null, Object.entries(u.env).sort(...)])
  : JSON.stringify([u.transport, u.url, Object.entries(u.headers).sort(...)]);
return createHash('sha256').update(material).digest('hex').slice(0, 16);
```

It is a digest of the **declaration** — the command line, or the URL and header names. It moves when
the user edits the entry and at no other time. An upstream that silently changes its tools does not
move it.

That demolished the original model, in which one per-subject stamp governed all six server checks:
`authorized`, `callsSucceed`, `surfaceApproved` and `operative` all move without the declaration
moving, so a stored `authorized: passed` from last week would have rendered as a **current** reading
after the token expired. That is the fabrication this whole item exists to refuse, and it was in the
spec's own centre.

### The correction: the current reading is never stored, and the store holds only history

Two concerns, separated, which is both more honest and simpler than what it replaces:

1. **The reading on screen is always live.** Every verdict the board renders is computed from the
   response it just fetched. Nothing on screen is ever read back from the store, so there is no such
   thing as a stale verdict on screen — the failure mode the gate constructed cannot occur, because
   the code path it needs does not exist.
2. **History is stored evidence, and evidence is what carries a version.** Each stored run is
   stamped, and a stored run whose stamp differs from the live one is labelled *invalidated* and
   never presented as a reading of the capability as it is now.

This is the brief's hard rule stated exactly: *"an eval result is evidence attached to a version, so
it must be invalidated when the version changes rather than carried forward."* Evidence is history.
Version is the declaration digest for a server and the plugin version for a skill. Nothing is ever
carried forward, because nothing on screen comes from the store.

| Subject | Stamp | What it means, precisely |
|---|---|---|
| server | `hash` | The digest of the entry **as declared** — `src/config.ts:98`. "Evidence gathered against this command line / this URL." |
| skill | `source.plugin.pluginVersion` | The **plugin's** version, shared by every skill that plugin supplies. M4 established this and named the field accordingly. |

Two renderings, both of history rows only:

- **current** — the run's stamp equals the live one. Shown as evidence gathered against this version.
- **invalidated** — stamp differs. Labelled *"gathered against 0.4.1 · now 0.5.0"*, rendered at
  `--t3`, and **kept**: invalidation is not deletion. Never presented as a current reading.

`--t3`, not `--t4`: DESIGN.md §2 binds `--t4` to *"disabled controls only — never live text"*, and an
invalidated history row is live text. The first draft said `--t4`; the gate cited the rule and it is
corrected here.

### A standalone skill cannot hold a result, structurally

M4 modelled `SkillSource` as a closed enum whose `.standalone` case has **no version field at all**.
So a standalone skill has no stamp, and the store has nothing to write — the refusal is a failable
`Stamp` initialiser rather than a rule the view remembers to follow. Its checks still run and still
display, because the reading is live; only its history is empty, and the pane says why in a sentence
rather than leaving a blank.

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

Trailing: **Re-check all…** (standard, not accent-filled). Not "Run all checks": for a server the
call is `POST /servers/:name/reindex`, which really does re-perform the handshake, but for a skill it
is `GET /skills`, which re-reads directories. *Re-check* is true of both — it names re-running the
checks over a fresh reading, and claims no execution. The gate was right that a pane whose entire
defence is verb discipline cannot afford a primary button whose verb is false for half its subjects.

### Filter — segmented, switches the view in place (§3.6)
`All` · `Not met` · `Not observed` · `Unstamped`, each with a count. A zero count carries no badge at
all rather than reading "0" — M4's precedent. The segment names are the verdict names, so nothing on
screen has two names.

*Unstamped* is where a subject with no live fingerprint lives — every `.standalone` skill, and any
server with `hash == nil`. The first draft left it reachable only under *All*, with nothing specified
for its cell. Its checks run and display like any other; what it has no room for is history.

Beside the segments, a **`SearchField`** (M4's, reused) — `⌘F` focuses it. The first draft bound `⌘F`
to a segmented control, which cannot take typed input.

### Columns and rows
`subject` (30pt tile + 180pt name/sub) · `kind` (58pt) · `checks` (170pt tally) · `checked against`
(150pt stamp) · trailing action. Row height fixed, and identical in the skeleton.

**Row order** is the router's own: servers in `GET /servers` order, then skills in `GET /skills`
order, stable across refresh. M3 recorded why it matters — a list that reorders itself as servers
start and stop is a list nobody can point at — and `↑`/`↓` need a defined sequence to move through.

The tally reads `4 confirmed · 1 not met · 1 not observed` in mono, with only the *not met* segment
tinted `--fail`. **It is never rendered as a single word**, and it carries no grading verb.

### Footer
> A check is something MCP Router performed and can show you the input to. It is not a graded test of
> whether a capability does its job well. Skills are never executed by the router, so nothing here
> reports how one behaved when an agent used it.

### The inspector — and the promise the footer makes
Per-check rows: verdict + statement + a reason line for anything not confirmed. **Each row also
renders the field and the value it was computed from** — `indexError = "spawn ENOENT"`,
`auth.authorized = false`, `usage.calls = 0`. That is not decoration: the footer promises "something
MCP Router performed and can show you the input to", and without the input on screen that promise is
unverifiable by the person it is addressed to, which is exactly what makes a derived row
indistinguishable from a grade. The gate identified this as the single most load-bearing mitigation
available, and it is now required rather than optional.

Then `checked against` (the live stamp), then **history** — newest first, each row carrying its own
stamp, so two runs against different declarations are visibly different evidence and are never
merged. A row whose stamp differs from the live one is labelled *"gathered against 0.4.1 · now
0.5.0"* at `--t3`.

History is capped at 20 runs per subject, oldest evicted. An unstamped subject has no history and the
pane says so in a sentence.

---

## The Cleanup pane

### Header
Title "Cleanup". Subtitle names the window from `UsageResponse.since`:

> Capabilities MCP Router has never seen used, judged over the calls it has recorded since 4 July.
> It proposes; you decide.

Trailing: **Reset call history…**, which opens a named-consequence dialog. It is not a plain button:
`POST /usage/reset` has no restore endpoint, and pressing it immediately makes every server
never-used, repopulates this very pane with false candidates and trips its own weak-window banner.
§9's escalation clause governs — the blast radius is the whole judgement surface this pane rests on.
The dialog names what is lost (`N recorded calls since 4 July`), Cancel leads, and the destructive
button is never the default.

### The sidebar badge counts a subset, and the pane says so

`Destination.badgeSource` binds `.cleanup` to `.serversNeverUsed` — `MCPServer.neverUsed`, i.e.
`usage.calls == 0` — and M1 already decided it. This pane lists more than that. So a line under the
header states the relationship rather than leaving the user to reconcile a badge of 3 against a list
of 9:

> The sidebar badge counts the 3 servers nobody has called. This list also includes servers that
> failed to index or declared no tools.

Changing `BadgeSource` is a merged shared surface and is reported rather than made.

### Inclusion rules

| Subject | Listed when | Never listed for |
|---|---|---|
| server | `usage.calls == 0` over the recorded window (`MCPServer.neverUsed`), **or** `indexError != nil`, **or** indexed with `tools == 0` | "last used a while ago" — the prototype's `last > 3600` is an invented threshold |
| skill | every skills-capable client was **read** and reports `.absent` | **anything about invocation** |

**An unreadable client suspends the judgement rather than making it.** If any skills-capable client
is `.unreadable`, *every* skill is held out of the proposal — a skill absent everywhere readable may
be installed in exactly the folder nobody could open. Those are counted in a banner.

### Filter and order

Segmented, as Evals: `All` · `Servers` · `Skills`, with counts and the same no-zero-badge rule, plus
a `SearchField`. The brief asks for never-used as a value in the existing column plus a filter, *not*
as a separate screen — so one list, filtered, rather than two panes. Row order is the router's own,
servers then skills, stable across refresh.

### The observation track — the second subject-mined element

DESIGN.md §10 records that the breaker is the app's only subject-mined element and asks any new
surface to add a second. This is it.

The question Cleanup exists to answer is *how much do we actually know*, and the answer is dominated
by one number nobody looks at: how long the router has been recording. "Never used" over 41 days is
evidence; over two hours it is nothing, and every table that shows only the verdict renders those
identically. The track draws the observation window at its real length against a 30-day reference,
with the real figure in mono beside it, so nothing depends on reading the bar. Beyond 30 days the bar
is **pegged full** and the mono figure carries the real value — a 400-day window is not drawn 13×
its own track.

Under 7 days it tints `--attn`, at its own meaning: "wants a human decision".

`since` comes from **`UsageSummary.since`** — the response `usageSummary()` actually returns — parsed
with `String.asControlAPIDate` (Kit/Formatting). If it does not parse, the subtitle drops the clause
and the banner does not fire; no number is substituted.

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
| `⌘F` | focus the search field | focus the search field |
| `↑` `↓` | move the selection | move the selection |
| `Return` | re-check the selection | open the selection's inspector — **not** remove |
| `Esc` | dismiss sheet, then clear selection | dismiss sheet, then clear selection |
| `⌘⌫` | — | named-consequence sheet for the selected **server**; no-op for a skill |
| `⇧⌘R` | re-check the selection | — |

**`⇧⌘R`, not `⌘R`.** DESIGN.md §8 line 319 already binds `⌘R` to *"Reset the selected server"*, and
`MenuCommand` models it. The first draft rebound it silently; the gate caught it. §8 is titled "Named
in every spec, not discovered later", so re-check takes an unclaimed key rather than a second meaning
being taught for one that is already spoken for.

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
- **A2** The merged tests that pin the exact set are updated in the same change:
  `installed == [.servers, .activity, .skills, .evals, .cleanup]` and `scaffolded.count == 3`.
- **A3** Selecting Evals renders `EvalsBoard` and Cleanup renders `CleanupBoard`, never
  `ScaffoldPane`. `ScaffoldedDestination(.evals)` and `(.cleanup)` both return `nil`.

### What is displayed is what is observed
- **A4** No view, model or copy function references a run count, last-run time, duration, byte figure
  or memory saving for any subject. Enforced by a source guard over **all four** locations the code
  actually lives in — `MCPRouterKit/Checks/`, `MCPRouterKit/Cleanup/`, `MCPRouterUI/Checks/` and
  `MCPRouterUI/Boards/{Evals,Cleanup}*` — in the style of `PhoneSourceGuardTests`. The first draft
  globbed only the last of the four, which excluded the file named "every statement, reason and
  disclosure string"; the guard would have been pointed away from everything it exists to catch.
- **A5** `callsSucceed` returns *not observed* for every `MCPServer` with `usage.calls == 0`, whatever
  `usage.errors` is. Asserted over the cross product, not over examples.
- **A5b** Every check that can be vacuously true is *not applicable* rather than *confirmed* when its
  question does not arise: `updateWantsNoMore` with `held == nil`, `originUnchanged` for a
  `.standalone` skill, `authorized` with `!auth.supported`. Asserted per case.
- **A5c** `declaresTools` returns *not observed* whenever `indexError != nil`, whatever `tools` holds.
- **A6** `reachable` returns *not observed*, never *not met*, whenever no client reports `.present`
  and any skills-capable client is unreadable **by either signal** — `SkillClient.status ==
  .unreadable` or a `SkillPresence.unreadable` in `Skill.presence`. Asserted over both signals
  independently, and over a `presence` dictionary with a **missing** key for a capable client, which
  must not be read as absence.
- **A7** Cleanup's candidate list excludes every skill when any skills-capable client is
  `.unreadable`, and the banner states how many were held out.
- **A8** Cleanup's subtitle and the observation track derive their window from **`UsageSummary.since`**
  — the type `usageSummary()` returns — parsed with `String.asControlAPIDate`. No literal duration
  appears in any Cleanup copy function. When `since` does not parse, the subtitle drops the clause and
  the banner does not fire; asserted directly.
- **A8b** Cleanup reads `usage.calls`, never `callsServed`. Asserted by constructing a server with
  `callsServed > 0, usage.calls == 0` and requiring it to be listed.
- **A9** The weak-window banner appears iff `since` is under 7 days — boundary asserted at exactly
  7 days — and its copy names the real elapsed time.

### Evidence is stamped, and invalidated rather than carried forward
- **A10** **No verdict on screen is ever read from the store.** Every rendered verdict is computed
  from the response just fetched. Asserted structurally: the board model's row type has no path to
  `CheckHistoryStore`, and a source guard requires it. This replaces the first draft's
  "there is no input for which a stale verdict renders as a current pass", which was unbounded and
  therefore untestable — and which, per the gate, was **false**: `hash` digests the declaration, so
  an expired token left a stored `authorized: passed` rendering as current.
- **A10b** A history row whose stamp differs from the live stamp renders as *invalidated* at `--t3`
  with the "gathered against X · now Y" label, over the cross product of stored × live stamp values.
- **A11** An invalidated run remains in the inspector's history under its own stamp.
- **A12** The store refuses to persist a result for a subject with no live stamp — a `.standalone`
  skill, or a server with `hash == nil`. Structural: the persist call returns `false` without writing
  and a test asserts the file's bytes are unchanged.
- **A13** History is capped at 20 runs per subject; the 21st evicts the oldest.
- **A13b** An unstamped subject is reachable under the `Unstamped` filter segment, its
  `checked against` cell renders `CheckCopy.unstampable`, and its history section renders its own
  sentence rather than a blank.

### The actions
- **A14** *Re-check* on a server issues exactly one `reindex` for that server and no other write.
- **A14b** *Re-check* on a skill issues exactly one `skills()` read and **no write at all**.
- **A15** *Remove…* on a Cleanup server row renders M3's `removeToolsConsequence` and
  `removeConsequence` strings verbatim — asserted by comparing against the functions, not by
  duplicating the literals.
- **A15b** *Reset call history…* opens a named-consequence dialog before any call to `resetUsage()`;
  the dialog names the recorded call count and the window, Cancel is the default, and dismissing it
  issues no request. Asserted with a recording double.
- **A16** *Remove* on a skill row is disabled in every state, and its reason string is present and
  non-empty. There is no code path from Cleanup to a skill write.

### Naming discipline
- **A17** **No verdict is ever rendered without the statement it judges.** Asserted against the row
  model rather than by string equality: `CheckResult` carries its statement, and the tally is a list
  of `(count, noun)` segments that the renderer cannot collapse to one word. The first draft banned
  four exact literals, which the tally `4 passed · 1 failed · 1 unknown` passed while being precisely
  the bare aggregate the design forbids.
- **A17b** No word in either board's verdict vocabulary is a grading verb: the four nouns are
  *confirmed*, *not met*, *not observed*, *not applicable*. Asserted over `CheckVerdict.allCases`.
- **A18** The Evals subtitle contains the sentence "No model-graded evaluation exists in this
  product", and it is returned unconditionally — including in the loading state.
- **A19** The Evals footer states that skills are never executed by the router.
- **A20** No string anywhere in the four M7 source locations contains "eval suite", "test suite",
  "eval case" or "graded" — except the subtitle's own disclosure, which is asserted by exact match so
  the exception cannot widen.
- **A20b** Every check row in the inspector renders the **field name and value** it was computed
  from. Asserted per check id: the rendered detail contains the field's name and its value's
  description. This is what makes the footer's "can show you the input to" verifiable rather than a
  claim.

### Colour and the native floor
- **A21** No verdict resolves to `ColorToken.live`, asserted **two ways**: a token test over
  `CheckVerdict.allCases` → token, **and** a source guard over the four locations for `.live` /
  `--live`. The first draft required a token test and explicitly forbade reading source, which cannot
  prove an absence across every view that composes a colour.
- **A22** `--attn` appears in these boards only for: a held version wanting more, a moved provenance,
  and the weak observation window — in **both** its renderings, the banner and the track tint, which
  are one condition shown twice. `--fail` only for a *not met* check and a failed write.
- **A23** Cleanup renders zero accent-filled buttons. Evals renders at most one per view.
- **A24** Every token used resolves through `ColorToken` / `MetricToken` / `TypeToken`;
  `scripts/lint/no-raw-design-values.sh` passes.
- **A25** Section headers are sentence case; no tracked uppercase.
- **A25b** No invalidated or dimmed **live text** uses `--t4`. DESIGN.md §2 binds `--t4` to disabled
  controls only; asserted as a token test over the invalidated rendering.

### The nine states
- **A26** Each of the nine states renders for each pane, from a **named fixture per state per pane**
  listed in the plan, and each unhappy path's copy is asserted against the string the model returns.
  Exhaustiveness is enforced by `EvalsBoardStates` / `CleanupBoardStates` switching over
  `SurfaceState`, so a tenth case stops the build.
- **A27** The loading skeleton's row height equals the populated row height exactly, so neither board
  jumps when data lands.
- **A27b** The observation track pegs at its full width for any window beyond the 30-day reference,
  and the mono figure beside it carries the real value.

### The keyboard and the menu bar
- **A28** `⌘F` focuses a real `SearchField` in both panes; `↑`, `↓`, `Return` and `Esc` behave per the
  table above, over the defined row order; and `Return` in Cleanup does **not** remove.
- **A29** `⌘⌫` in Cleanup opens the removal sheet for a selected server and is a no-op for a skill.
- **A30** Every command appears in the menu bar with the same enablement reason as its in-pane
  control, and re-check is bound to `⇧⌘R` — `⌘R` remains DESIGN.md §8's reset.

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
   > **Superseded 2026-08-16 by D2 (M9). The rename was made.** The sidebar row, the window title,
   > the View-menu item, this board's own heading and the Skills footer all read `Checks`; the enum
   > case, its `rawValue` and the `?pane=evals` deep-link slug deliberately still read `evals`,
   > because restoration and the prototype's links persist them. This note exists because the
   > assumption above, left standing, reads as an instruction to put `Evals` back — an out-of-family
   > critic flagged exactly that. `ShellDestinationTests` now pins both halves.
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

### Verdict: REJECT — 6 blocker, 15 major, 7 minor

The gate rejected the first draft, and it was right to. Three of its blockers were factual errors
about this repository that a reviewer agreeing with fluent prose would have passed:

1. **`hash` is not the tool-surface digest.** `src/config.ts:98` computes it over the *declaration*.
   The entire invalidation model rested on a sentence that reading the router source disproves in
   thirty seconds. Verified and corrected above; the correction — live readings, stored history —
   is simpler than what it replaces.
2. **The anti-fabrication source guard was pointed at the wrong directories,** excluding all three
   files that hold the strings and the stored figures.
3. **Three checks reported a confirmation for a question nobody asked** — the exact defect the spec
   declares load-bearing about `callsSucceed`, applied to one check and not the others.

Full disposition, every finding:

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | blocker | One stamp cannot govern checks that move independently of it | **Accepted** — live readings; store holds history only |
| 2 | blocker | Source guard globs miss `CheckCopy`, `CleanupPresentation`, `CheckHistoryStore` | **Accepted** — A4 names all four locations |
| 3 | blocker | Vacuous confirmations (`updateWantsNoMore`, `originUnchanged`, `declaresTools`) | **Accepted** — A5b, A5c; *not applicable* rather than the suggested *unknown*, matching `authorized` |
| 4 | blocker | `described`'s unknown condition reads a field that does not exist | **Accepted** — binary check, phantom column deleted |
| 5 | blocker | `SkillPresence` vs `SkillClientStatus` conflated; missing dict key ≠ absence | **Accepted** — A6 asserts both signals and the missing-key case |
| 6 | blocker | Evals can contradict Servers on the same refresh | **Accepted** — this *is* the correction in 1 |
| 7 | major | `--t4` is disabled-controls-only (DESIGN §2:81) | **Accepted, verified** — `--t3`, plus A25b |
| 8 | major | Track's `--attn` is a fourth use A22 forbids | **Accepted** — A22 names both renderings of one condition |
| 9 | major | Badge counts a subset of what the pane lists | **Accepted** — the pane states the relationship; `BadgeSource` change reported, not made |
| 10 | major | `⌘R` already bound to Reset (DESIGN §8:319) | **Accepted, verified** — `⇧⌘R` |
| 11 | major | `⌘F` targets a segmented control that cannot take input | **Accepted** — a real `SearchField` in both panes |
| 12 | major | "Run all checks" is a false verb for skills | **Accepted** — "Re-check all…" |
| 13 | major | Unstampable has no home in filter, column or matrix | **Accepted** — `Unstamped` segment, A13b |
| 14 | major | "Unchecked" and "unknown" one letter apart | **Accepted** — one vocabulary throughout |
| 15 | major | Reset is irreversible with no consequence dialog | **Accepted** — A15b |
| 16 | major | DESIGN §6:279 mandates a "not evaluated" string this spec deletes | **Accepted as a finding, deferred as an action** — DESIGN.md is a merged shared surface; reported for the orchestrator, not edited here |
| 17 | major | `hash` semantics asserted, not verified | **Accepted** — quoted from source above |
| 18 | major | A21 forbade the only method that could prove it | **Accepted** — guard *and* token test |
| 19 | major | A10/A26 unbounded, so untestable | **Accepted** — A10 restated structurally; A26 takes named fixtures |
| 20 | major | A17 drafted so the offending tally passes | **Accepted** — restated against the row model; vocabulary changed |
| 21 | major | `callsServed` vs `usage.calls` unstated | **Accepted** — stated, plus A8b |
| 22 | minor | A8 pins `UsageResponse` not `UsageSummary` | **Accepted** |
| 23 | minor | No parse-failure path for `since` | **Accepted** — parser named, fallback stated |
| 24 | minor | No row order specified | **Accepted** — router order, stable |
| 25 | minor | Track has no overflow rule | **Accepted** — pegged, A27b |
| 26 | minor | Evals' empty action is server-only | **Accepted** — conditioned on what exists |
| 27 | minor | Cleanup's segmented filter promised, never specified | **Accepted** — specified |
| 28 | minor | `remove(_:keepHistory:)` attributed to M3 | **Accepted** — it is F3's, on `ControlAPIClient` |

**Finding 29 — the central objection, and what was and was not taken.** The gate argued that
delivering derived status checks under the word "Evals" is a misleading rename unless five things are
true. Four are now in this spec: the grading vocabulary is gone (A17b), every check row renders the
field and value it was computed from (A20b), the action verbs match the calls they make (A14/A14b),
and the pane's genuinely new content is the stamp and the history rather than the verdicts.

**The fifth is not taken, and it is the strongest one.** The gate's first condition is that the word
"eval" appear nowhere in shipped chrome — that `Destination.title` read "Checks", with the sidebar,
window title, menu item and deep link following. `Destination` is a merged shared surface that M1
owns, and this fleet's rule is to report a shared change rather than make it. So M9 stands as filed,
and it is flagged in this item's report as the highest-value follow-up rather than a tidy-up: until
it lands, the disclosure is structural inside the pane and the word is structural everywhere else,
which is the gate's objection and it is unrebutted.

**Lane note.** Every reviewer in this item's pipeline is Claude auditing Claude, and this gate is
what that weakness looks like when it happens to work: it found three factual errors about the repo,
one of which invalidated the spec's central mechanism. It should not be read as evidence that the
in-family lane is equivalent to the out-of-family one it replaced.
