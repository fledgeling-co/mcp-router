# R16 — adoption reads global scope only, so a project-scoped server is invisible to it

**Status:** Untriaged
**Raised by:** the owner, 2026-08-21, from a live failure — "I tried to use proctor mcp which I think mcp relay has added to it, but it couldn't find it so I had to add it to the claude mcp manually"
**Category:** router

## What happened

`proctor` was never a router upstream. The router serves 13 and none of them is it. The owner
reasonably expected adoption to have picked it up, and it never could have.

`proctor` is declared **project-scoped**, three times, with three different argument sets:

```
~/Dev              proctor → proctor-shim serve
~/Dev/proctor-mcp  proctor → proctor-shim serve --profile core
~/Dev/sidetone     proctor → proctor-shim serve --profile scripting
```

The owner's global `mcpServers` holds only `namecheap`, `pocketsmith` and `router`.

`src/index.ts:85-86` reads `src.mcpServers` — the top-level key. It never reads `projects`. So
`import` and `watch` see globally-scoped servers and nothing else, and **every project-scoped
server in `~/.claude.json` is invisible to adoption by construction**, not by accident or by a
race. No amount of waiting or re-running `watch` would have adopted it.

Confirmed empirically as well as by reading: no upstream the router currently serves carries a
`projects` field.

## The sharper half

The router's own configuration type already models this. `src/config.ts:16-21`:

> A global on/off switch cannot say "this server for that repo and not this one"

with `projects?: string[]` on both the raw and resolved shapes. So the router **can express**
per-project scoping for an upstream. It simply cannot **learn** it from the harness it adopts
from — the one field that would carry the answer is never populated by the adoption path.

That is the gap worth fixing, and it is narrower than "support project scope": the model exists,
the reader does not.

## The part that is not merely a missing read

`proctor` is one name over three different commands. The router keys upstreams by name and
namespaces tools as `<name>__<tool>`, so adopting "proctor" would have to pick one of the three,
and a call made from a different project would silently run the wrong profile — `--profile core`
answering where `--profile scripting` was configured.

So a fix that reads `projects` and adopts the first match is worse than today's behaviour, which
at least fails visibly. Whatever is built has to decide what a name means when the harness binds
it to different commands in different directories. Three shapes, none obviously right:

1. **Adopt per-project**, carrying `projects` through so the router serves the right command by
   caller cwd. The router already receives caller cwd — `CallerIdentity` carries it, and `usage`
   reports the project that made each call — so the information is present at call time. This is
   the most faithful and the most work.
2. **Adopt only where the name resolves to one command across every project that declares it**,
   and report the rest as unadoptable with the reason. Cheap, honest, and leaves `proctor`
   exactly where it is today while saying *why* rather than staying silent.
3. **Adopt under a disambiguated name** (`proctor@proctor-mcp`), which changes the tool namespace
   the model sees and so changes prompts that name a tool. Probably wrong for that reason alone,
   recorded so it is not rediscovered.

Shape 2 is the floor: whatever else is decided, **a server adoption skipped should be reported
rather than absent**, which is the same defect class as R14's silent upstreams.

## Acceptance

1. `import` and `watch` see project-scoped entries — they are read, whatever is then decided
   about them.
2. A name bound to different commands in different projects is **never silently adopted as one
   of them**. Either it is scoped correctly, or it is reported unadoptable with the collision
   named.
3. `mcpr status` or the R14 report names servers the harness declares that the router did not
   adopt, and why. Today the count is 13 and the reason for every absence is nowhere.
4. A test fixture carrying one name with two different commands in two project scopes, arming
   whichever behaviour is chosen.

## Scope

`src/index.ts`'s adoption path and its Swift counterpart, `src/config.ts`'s `projects` handling,
`ImportVerb` and `WatchVerb`. Related but distinct: `D-r7-i` records that `HarnessesVerb` prints
`"Global scope only"` while reading a project-scoped file, so R7's reader has the mirror-image
defect — it reads project scope while claiming global. Both should be settled with one decision
about what scope this product works in.

## What the owner should do meanwhile

Nothing to undo. Adding `proctor` directly to Claude Code was the correct move and stays correct:
a per-project profile is exactly what the router cannot currently express through adoption, and
three profiles under one name is exactly what it must not flatten.

---

## Triage — 2026-08-22

**Verdict: To Do.** Standard tier, scoped to shape 2. Not blocked, but it must not reach shape 1
before the scope decision `R7` owes.

### Both halves of the finding confirmed at HEAD

`cmdImport` at `src/index.ts:85` reads `src.mcpServers` and nothing else, so `projects` is never
enumerated. And the model really is already there: `projects?: string[]` on both config shapes
(`src/config.ts:21`, `:126`), carried through resolution at `:164` and `:189`, and **editable
through the control API PATCH** at `src/control.ts:450`. So today an owner can hand-scope an
upstream to a project and the router will honour it — it simply cannot learn that scoping from the
harness it adopts from. The gap is the reader, exactly as the brief says.

### One thing the brief did not know, and it shrinks the item

**The reporting channel criterion 3 asks for is already built.** `cmdImport` collects `skipped`
(`src/index.ts:93`) and prints it as `not adoptable:` at `:153-155`, with a per-server reason.
Today it only ever holds servers `parseServer` refused. Nothing needs inventing for criterion 3 —
project-scoped and collision cases go into the list that already exists and already prints.

So the work is enumeration plus the collision decision, not enumeration plus a new report.

### Scope: shape 2, and shape 1 is not deferred by preference

Shape 2 — adopt only where a name resolves to one command across every project that declares it,
and report the rest as unadoptable with the collision named — is the floor this brief states, and
the floor is not a choice. The only open question was whether to take shape 1 (adopt per-project,
serve by caller cwd) in the same item.

It cannot be taken here, and the reason is not cost. Shape 1 decides what scope this product works
in, and `D-r7-i` records `HarnessesVerb` printing `"Global scope only"` while reading a
project-scoped file — the mirror image of this defect. The brief's own closing line says both
should be settled with one decision, and that decision is not made. Building shape 1 now would make
it by implication, from the side with less evidence.

Filed as **R16-C1** in the deferred register: *adopt project-scoped upstreams and serve them by
caller cwd*, blocked on the same scope decision as `D-r7-i`. The information it needs is present at
call time — `CallerIdentity` carries cwd and `usage` already reports per-project call counts — so
it is a decision problem rather than a plumbing one.

Shape 3 (disambiguated names like `proctor@proctor-mcp`) stays refused for the reason the brief
gives: it changes the tool namespace the model sees, so it changes prompts that name a tool.

### What the owner sees when this lands

`proctor` stays exactly where they put it, by hand, in Claude Code — which was and remains the
correct move. What changes is that `import` stops being silent about it: three declarations, one
name, three different argument sets, reported as unadoptable with the collision named. The count
that reads `13` today gains a reason for every absence.
