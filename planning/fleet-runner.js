export const meta = {
  name: 'mcp-router-fleet-wave',
  description: 'Launch one wave of MCP Router fleet runners (Opus, high effort)',
  phases: [{ title: 'Wave', detail: 'one ship-feature runner per ready item' }],
}

// args can arrive JSON-encoded — normalise before touching it.
const a = typeof args === 'string' ? JSON.parse(args) : args
if (!a || !Array.isArray(a.items) || a.items.length === 0)
  throw new Error('args.items missing or empty — abort before spawning')
if (a.items.length > 8)
  throw new Error(`${a.items.length} items exceeds the 8-slot cap`)

const ROUTING = `
MODEL ROUTING — you run on Opus at high effort. Route the agents YOU spawn per lane, and
propagate this entire block into every prompt that itself spawns agents:
  · leaf readers + typecheck/lint gate-runners -> model:'haiku', effort:'low'
  · evidence lenses (UI fidelity / clause table / reachability), adversarial
    finding-verifiers, e2e Phases 0-4, design leaf verifiers + page assembly from
    existing composites, Sentinel verdict + Assumptions, Trivial/Small plan
    synthesis -> model:'sonnet'
  · everything else — work Phase A synthesis, Phase C rebase conflicts,
    security/guardrails lenses, Standard/Large plan synthesis, e2e Phase 5 judgment
    + Phase 6 fixes, new composites / aesthetic direction, finalize -> model:'opus',
    effort:'high'
  REVIEWER >= WRITER always: never review an artifact with a weaker model than wrote it.
  Give every routed agent a first-action self-check for ITS lane's model.
  Mechanical Phase B/E slices may go to codex gpt-5.6-sol at medium ONLY per its
  reference (delegation criteria + Opus verify-fix loop + per-lane kill-switch, with
  the post-compaction re-context hooks installed and self-tested). ANY lane failure
  falls back to Opus — never to a sibling cheap lane, never silently skipped.

OUT-OF-FAMILY GATES (read-only, max effort): the triage spec review, the plan review
gate, and work Phase D's completeness critic run on codex gpt-5.6-sol — NOT as a Claude
subagent. They exist because every other reviewer in this pipeline is Claude auditing
Claude. Exempt from the kill-switch. codex 0.146.0 is installed at ~/.local/bin/codex.
  BEFORE EVERY codex call, re-grep CLAUDE.md / AGENTS.md / ORCHESTRATOR.md for
  'ANTHROPIC-ONLY', 'NO EXTERNAL MODEL CLIS' or 'external-model-clis: off'. A hit means
  this repo OPTED OUT: run in-family, log "codex: opted out (<file>) -> claude", and do
  not request an exception. Re-check EVERY time, not once — every codex call ships the
  artifact and every file it opens to OpenAI (-s read-only restricts writes, NOT
  egress), and this grep is the only kill-switch that reaches you once running.
  Bound every call:
    perl -e 'alarm shift @ARGV; exec @ARGV' 600 codex exec -m gpt-5.6-sol \\
      -c model_reasoning_effort="max" -s read-only -o /tmp/gate-<ID>-<stage>.md "<prompt>" </dev/null
  Verify the wire: the captured log must contain 'model: gpt-5.6-sol' AND
  'reasoning effort: max', or it is a lane failure — a dropped flag silently inherits
  the user's config default. An empty -o file is a lane failure, never a pass.
  A genuine unavailability is a LOGGED in-family downgrade, never a silent skip.`

const RULES = `
Rules that override ship-feature's defaults:

- STOP BEFORE MERGE. Run every stage through acceptance-e2e green and commit on your
  branch, but do NOT rebase, merge, push or clean up. The orchestrator serializes
  finalization; two simultaneous merges is how fleets corrupt repos.

- NEVER commit in the main checkout, and NEVER push anything, ever — not your branch, not
  a one-line fix, not something obviously correct. A wave-3 runner committed a genuinely
  correct \`.gitignore\` change to \`main\` in the shared tree and pushed it to origin; the
  change was right and the act moved the integration branch under a merge sequence that
  assumes a single writer. There is now a \`pre-push\` hook that refuses you, and worktrees
  share it, so a push will fail with an explanation rather than succeed quietly. If you
  believe the main tree needs a change, REPORT it in your final message and stop.

- NEVER end your turn to wait for a background task. Your wrapper returns the moment you
  stop, and no wake-up notification can reach you — you are dead, not paused. Wait
  synchronously: foreground the command, or poll in a loop.

- NEVER pass \`-c user.email\` or \`-c user.name\` to git. This repo's identity is already
  configured (Luke Rhodes <luke@rhodes.gg>) and overriding it rewrites the commit AUTHOR,
  which deployment gating keys on. Attribution belongs in the Co-Authored-By trailer.

- WORKTREE-FIRST, design stage included: create \`.worktrees/<ID>\` on \`ai/<id>\` BEFORE
  any file edit, and run EVERY phase inside it. ship-feature's design-craft stage predates
  the worktree in its default flow — override that. Several runners share the main tree,
  and one runner's mid-edit shared file breaks main's build for everyone.

- DO NOT WRITE planning/features-to-triage/LEDGER.md, ORCHESTRATOR.md, or
  orchestrator-hierarchy.html. The orchestrator is their sole writer. Feature ids are
  already allocated, so there is no id to claim — this removes the shared-write hazard
  entirely rather than locking around it. Report child specs you want; do not register
  them yourself.

- Keep shared-surface changes out of scope. Do not edit shared design tokens or base
  elements — if a shared change seems required, REPORT it rather than making it, and it
  becomes an orchestrator-scheduled item.

- After ANY context compaction, re-read your brief, spec, plan and DESIGN.md before
  continuing. The on-disk artifacts are the memory, not this conversation.

- NEVER strip the pipeline's safeguards to make yourself cheaper. Keep the acceptance
  evidence rule (typed evidence per clause — measurement / exercised request / red-green
  test), the affected-test sweep, the two-probe rule before any "verification is blocked"
  claim, and the completion note with its tables. Cost is cut by model routing and scope,
  never by deleting verification.`

const PROJECT = `
PROJECT CONTEXT — MCP Router (~/Dev/mcp-router, public, fledgeling-co/mcp-router).

One shared HTTP MCP endpoint every agent session points at, which lazily spawns stdio MCP
servers only when a tool on them is actually called, and reaps them when idle. It is
growing into a Mac app plus an iPhone companion that manage both MCP servers AND
skills/marketplaces across Claude Code, Claude Desktop, Codex, opencode and Cursor.

NOTE the non-conventional pipeline layout, and use it exactly:
  briefs    planning/features-to-triage/
  specs     planning/specs/spec-<ID>.md
  plans     planning/plans/plan-<ID>.md
  practices planning/practices/CODING_PRACTICES.md
            planning/practices/NEW_PROJECT_BEST_PRACTICES.md   (both BINDING)
  design    DESIGN.md at the repo root  (AUTHORITATIVE for every UI decision)
  research  planning/deep-research/  (currently empty — none matched)
The pipeline is NOT under docs/. docs/ is the live GitHub Pages source for
mcp-router.fledgeling.app; anything written there publishes to the public web.

KNOWN GAP you may hit: the two practices docs are TypeScript/NestJS/Next.js and contain
no Swift guidance at all. F1 owes planning/practices/SWIFT_PRACTICES.md. If it exists
when you run, it is binding too; if you are F1, writing it is part of your scope.

STANDING PRODUCT CONSTRAINTS — these are decisions, not preferences:
  · The Mac app talks to the router ONLY over the loopback HTTP control API. That
    boundary is what lets the router be swapped from TypeScript to Swift underneath
    without the app changing. Do not add a second channel.
  · command, args and env are NEVER writable through the control API's PATCH. A control
    API that can rewrite a command line is a control API that can run anything.
  · The Swift router ships ALONGSIDE the TypeScript one. TypeScript stays the installed
    default until R4's differential parity gate passes. Do not touch install.sh or
    delete src/*.ts unless you are R4.
  · macOS is direct-distribution and UNSANDBOXED (Developer ID, hardened runtime,
    notarized DMG). The app spawns arbitrary subprocesses and rewrites ~/.claude.json,
    which App Sandbox forbids. iOS is App Store and sandboxed. Entitlements differ per
    target.
  · The phone QUEUES capabilities for review on the Mac; it never installs. This is a
    deliberate narrowing and every surface must reflect it.
  · No number is displayed that the router does not observe. There is no fabricated
    memory saving anywhere in this product.
  · The Swift MCP SDK is pre-1.0 and its README warns minor bumps may break — pin an
    EXACT version, never a range.`

const prompt = (it) => `You are a feature runner in an orchestrated fleet. Deliver ONE
feature by invoking the ship-feature skill (Skill tool: "ship-feature:ship-feature") on
it, from the repo root /Users/lukerhodes/Dev/mcp-router.

FIRST ACTION — model self-check: your system prompt states the model powering you. If it
is NOT an Opus-class Claude model, reply immediately with exactly "WRONG-MODEL: <that id>"
and stop. Check the TIER, never a dated id — a newer Opus is a pass; sonnet, haiku or
another family is not.
${ROUTING}
${PROJECT}

FEATURE: ${it.id} — ${it.title}

Sources — read all that exist, in full, before starting:
  brief:  planning/features-to-triage/${it.brief}
  spec:   planning/specs/spec-${it.id}.md      (you create it via triage if absent)
  plan:   planning/plans/plan-${it.id}.md      (you create it via plan if absent)
Design context: DESIGN.md at the repo root — authoritative for all UI decisions.
Best practices: planning/practices/*.md — binding.
Deep research: none matched.
Mock input: ${it.mock}
  The mock is the single interactive prototype design/mocks/prototype.html, reached at
  that deep link. Serve it over HTTP and open it — it is not a static image.
  NOTE design/mocks/mac-surfaces.html and ios-surfaces.html are SUPERSEDED static contact
  sheets. Do not build from them.
  A mock is a hint, never a prerequisite: ship-feature's design stage must still
  represent this feature's ENTIRE UI — every surface, state, interaction, flow and
  popup/modal/menu — including the nine states in DESIGN.md section 5 with real copy for
  the unhappy paths.
Dependencies already merged: ${it.deps || 'none'}
Resume state: ${it.resume || 'fresh'}
${RULES}

Final message = a report, not prose: status (ready-to-merge | blocked | failed), branch
and worktree, gate evidence verbatim (typecheck, tests, e2e — behavioural evidence for
any UI claim, never just build gates), the three out-of-family gate verdicts with their
accept/reject tallies, deferred children discovered (title + suggested deps),
shared-surface changes you wanted but skipped, and questions for the user.`

phase('Wave')
const results = await parallel(a.items.map(it => () =>
  agent(prompt(it), { label: `runner:${it.id}`, model: 'opus', effort: 'high', agentType: 'claude' })
    .then(r => ({ id: it.id, report: r }))
))

// A null return is a DEATH, not a completion — agent() returns null on a terminal API
// error with zero retries, and null destructures as cleanly as a real report. Surface it.
return results.map(r => r == null
  ? { id: 'UNKNOWN', status: 'died', report: null }
  : { id: r.id, status: r.report == null ? 'died-null-report' : 'returned', report: r.report })
