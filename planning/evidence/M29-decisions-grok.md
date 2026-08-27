# M29 decisions — out-of-family lane: grok-4.6 --effort xhigh

Run 2026-08-25, bounded at 540s, exit 0. Prompt `/tmp/m29/prompt2.txt` (not retained) — the same evidence with
the **(c) option order swapped** (deny-list first, global boolean last) and a fourth question
added about whether the router should send a derived status enum. The reply opens with its own
tool narration because this lane read the repository directly and ran referrals of its own; that
narration is left in place rather than trimmed, since it is what shows the lane was on-subject.

Its option letters follow the swapped prompt: "C3" in its answer is the **global boolean**.

Verdict: **(a) A1 · (b) B2 · (c) global boolean · (d) plain `disabled: boolean` on the wire,
not a derived status enum**. It adds that the check belongs on `tools/call`, spawn and warm-up,
not on `unionTools` alone — taken as D5 in the spec.

---

I'll ground this in the actual router code first, then decide the four forks against that rather than the excerpts alone.The router is at `~/Dev/mcp-router`. Next I’ll read the config/manifest/control paths and the app’s row-state chain so the four forks sit on the real code, not the excerpts.M29 already names this fork. I'll read that note plus the real `unionTools` / PATCH / row-state code so the referral lanes get evidence, not the excerpt.The error path I just read still drops the digest — checking whether R18 actually landed, then sending the fork to the other families.Evidence is enough. Sending the same fork to Claude, Gemini, and Codex with the option order swapped, then deciding from that plus the code.🫥 A1, B2, C3, and a `disabled: boolean` on the wire — not a derived status enum. No better fork than that set. Two consequences of B2 that are not extra options: the same config check belongs on `tools/call` (where `visibleTo` already refuses a hidden name at `// A scoped server is not merely hidden from the list — it does not run for a`, `src/router.ts:191` at `9c48d2d` – `:206`) and on spawn / warm / `isStale`, so a disabled server is not indexed and not started. `claude-fable-5` @ high and `gemini-3.7-flash-high` both landed on A1/B2/C3/flag; `gpt-5.6-sol` @ high was down (expired token, empty `-o`).

**(a) A1.** Disable is a config fact, same family as `projects` / `warm` / `placard`. Leave it out of `upstreamHash`, leave `manifest.json` alone, keep the approved tools, digest, and pending hold. The mock’s Tools em-dash and “4 d ago” only work if the router still knows the last surface and usage still has last-call. A2 is the security hole on the sheet that motivated the feature: “Disable mobbin” from a held schema change, then re-enable, is first-sight-approve of the surface you just refused if the row is gone. R18 exists so a missing digest cannot do that; dropping the row on disable recreates it.

A2 is genuinely better at forcing a cold probe on re-enable, so an out-of-band change while dark cannot sit on a stale approved set. The hold already owns that: re-enable serves the old approved surface; the next index (when you ask for one) compares against the kept digest.

**(b) B2.** A `disabled` predicate on the config, evaluated before the manifest, same position and shape as `visibleTo`. `tools.length === 0` already means never indexed, index failed (R18 empties tools and keeps the digest), or a server that truly has no tools. The project’s own note is the reason: a third “serve nothing” stuffed into that test is how the last defect got there. B1 requires A2, which (a) already refuses.

B1 is genuinely better at making disable true in the data so a later caller that forgets the config check still serves nothing. That is real. It is also how emptiness became a grab-bag. One `unionTools` plus the existing `tools/call` `visibleTo` site is the whole serving surface; both take the check.

**(c) C3, `disabled?: boolean`.** The console is a global table with no project selector. The held-change sheet is a kill switch. `projects` already says “live in A, not in B”. A deny-list next to an allow-list needs a composition rule (`projects: [A]` plus disabled-in `[A]`) that nothing in the product can show. Per-project off-ness that is not a security disable stays an allow-list edit.

C1 is genuinely better at “everywhere except this repo” without enumerating every other repo. That need is real and currently inexpressible. It wants its own UI (a project selector) before it wants a second scoping field. C2 is both taxes.

**(d) Add `disabled: boolean` to `describe()`, matching `warm`.** The app already derives row state in `ServerSubtitle.forServer` / `JackState.forServer` from facts the router sent. Disabled is one more branch, and it has to outrank `pendingChange` and `placard` because the sheet disables a server *that has a hold*. A router enum `active | disabled | error | unindexed` cannot encode that overlap, is incomplete against the chain that already handles auth / warm / scoped, and would be derived in both routers under a byte-for-byte parity gate — three copies of a precedence the app already tests without a host. DESIGN.md §6 is the same rule: the router reports what it observed.

The enum is genuinely better for a second control-API consumer that does not have the chain, and at making router and app unable to disagree about “what state is this”. Today there is one consumer, and it already has the chain.

Claude offered a `{ reason, at }` record instead of a boolean. Decline it. “Disabled by you” is copy; “4 d ago” is Last call from usage, not disable time; the sheet’s disable is still the user clicking Disable. A second structured PATCH field next to `placard` is a parity tax for a distinction the mock does not draw.

Do not reuse `placard` for this. Placard keeps tools listed and answers; disable unlists them.
