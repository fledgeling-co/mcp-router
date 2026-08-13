# Trawl — UI and feature ideas for the capability manager

**Receipt.** Standard tier, 5 frames (night-shift support lead · one-screen constraint ·
adversary · cross-domain transplant · toy designer/wild seat), 39 ideas generated →
21 after mechanism dedup → 9 floored → shortlist below. The one-screen frame largely
self-apoptosed: six of its eight ideas are living-organism or spatial-canvas metaphors that
fail fit for a security-sensitive professional tool, but the two that survived are strong
enough that the frame earned its seat.

**Frozen baseline** (what every frame had to beat): a `NavigationSplitView` Mac app with
Activity / Servers / Skills / Discover / Cleanup panes plus a `MenuBarExtra` popover;
standard SwiftUI rows with spring transitions; a phone app that is a search-and-browse
client with a "send to Mac" button, paired by QR over CloudKit.

---

## The reframe the run produced

Four frames arrived independently at the same structural insight, and it changes what the
app is: **trust is not established at install time, it decays per version.**

The baseline — and every app-store-shaped UI — treats install as the moment of judgment and
everything after as maintenance. The adversary frame named why that is already broken: the
patient supply-chain move is to pass review clean once and ship the payload two releases
later through an unattended auto-update. The cross-domain frame reached the same place from
livestock quarantine and aviation MELs. The night-shift frame reached it from six-weeks-later
debugging.

So the spine of this product is not a store. It is **a gate that re-arms itself on every
version**, with the store as its front door.

---

## Shortlist

### ★ 1. The diff *is* the changelog — a real git repo of everything installed
*(night-shift frame · BEATS baseline)*

Keep every installed skill and server's files in a local git repo. "Changelog" is not vendor
prose; it is the actual `git diff` of what is about to land, syntax-highlighted, with a
Time-Machine-style scrubber across every past version and a real `git revert` to roll back.
Auto-updates commit automatically, so the history exists whether or not anyone reads it.

**Why it wins on the stated ask:** the user asked for "changelogs" and "auto update". Vendor
changelogs are marketing copy about code that runs on your machine, and they are written by
the same party you are trying to verify. The diff is the only artifact that cannot lie about
itself. It also makes rollback a real operation rather than a reinstall, which is what makes
auto-update safe enough to leave on.

**First step in the stack:** `git init` in `~/.mcp-router/installed/`, commit on every
install and update, and render the diff with an existing highlighter. No new format, no
server, no schema.

**Load-bearing risk:** a large skill's diff is unreadable, and an unreadable diff gets
click-through-approved like every other wall of text. Mitigation is the next item.

### ★ 2. Capability diff, not content diff — the shadow copy that must earn promotion
*(adversary frame · BEATS baseline)*

A new version never applies live. It lands as a translucent shadow copy in the library —
ghosted, dashed border — while the eval suite re-runs against it. Promotion is automatic
**only when the capability diff is empty**: no new network hosts, no widened filesystem
scope, no new binaries invoked, no new shell invocation. A version that grew capability
stays ghosted and requires an explicit promote, which shows exactly what grew as a checklist.

**Why it beats a plain diff:** it answers "is this change safe" instead of "what changed",
and it is what makes item 1 readable — you read the capability delta, and drop into the full
diff only when it is non-empty.

**Non-obvious consequence:** this makes auto-update *more* aggressive, not less. Empty-diff
versions promote silently with no notification at all, which is most of them.

### ★ 3. The description is the payload — quarantine metadata changes as their own class
*(adversary frame · TIES baseline, marked non-obvious)*

Already half-built in the router: a server that rewrites its tool descriptions has its change
held while the approved text keeps being served. The frame's contribution is generalising it
to skills, where the exposure is worse. **A skill's markdown body is loaded into a model's
context as literal instruction, and needs no script at all to be a payload.** So the review
surface for a skill is its prose, with imperative and tool-invoking sentences highlighted,
not its shell scripts.

**Why only TIES:** the mechanism is right and the router already proves it works, but the
"instruction highlighter" heuristic will have a false-positive rate on ordinary skill
markdown, which is *written* in imperatives. Ships as a reading aid, never as a gate.

---

## Adopted as rules (not features)

- **The menu bar squawks, it does not report.** From the aviation transponder: the glyph is
  quiet at rest and changes only on an exceedance. Already built this way. Rejected the rest
  of that transplant (a 2-hour discard-everything loop) because the cleanup feature depends
  on complete lifetime counts.
- **Per-project loading over global on/off.** The pharmacy pill-organizer transplant landed
  exactly on the per-project scoping already built, from a completely different direction.
  Independent convergence on a shipped feature is the strongest signal in this run.
- **Probation scaled by requested scope.** New capabilities are watched more closely for a
  window whose length scales with what they asked for; read-only clears fast, shell/network
  holds longer. Combines with the shadow copy above.
- **Dormancy triggers a provenance re-check.** Before cleanup offers to delete anything
  unused, re-fetch the source repo and compare against the hash installed. Owner changed or
  history force-pushed → refuse the delete and show "this changed hands since you installed
  it". A dormant capability is precisely the one nothing else re-checks.
- **Fork lineage is visible.** From museum type specimens: a marketplace fork can be held up
  against its canonical original and diffed. Real git operation, real relationship.
- **The server list is a breaker panel.** *(toy-designer frame, and the run's best answer to
  "make it a joy".)* Each server is a breaker that sits dormant, **flips itself up with a
  spring-snap the instant an agent calls it**, and eases back down over ~600ms when the idle
  reaper closes it. Nothing about this is decorative: it is a literal, honest rendering of the
  one mechanism the whole product exists for, and it means you watch lazy-spawn happen instead
  of reading that it happened. The delight and the explanation are the same object.
- **Eval status is a property, not a report.** Strip the frame's wax-seal metaphor and keep
  its mechanism: the pass/fail mark lives **on the card in every view** — library, discover,
  cleanup, phone — so "has this ever been evaluated" is answerable at a glance anywhere,
  and never-evaluated is visibly distinct from passed. A standalone eval report that you have
  to go and open is a report nobody opens.
- **Client compatibility is a row of slots, not a list of badges.** One slot per installed
  client (Claude Code, Codex, Cursor, opencode…), filled or empty. Same frame's pegboard,
  minus the drag-to-seat conceit.
- **The phone can queue but cannot install.** See below.

## Phone: queue, never install

The adversary frame killed the baseline's remote-install button, and the reasoning survives
scrutiny: phones get lost, unlocked, and run apps with clipboard and URL-scheme access far
more often than a person sits at their own Mac. So the phone's send lands in a tray, and the
install completes only at the Mac.

The one-screen frame supplied the phone's shape independently — **triage on the go is
yes / no / later**, which is a card deck with swipe verbs, not a browse-and-tap store. The two
compose: the phone is a deck you swipe, and swiping right means *queued for the Mac*, which
is honest about what it does.

This is a deliberate reduction of what the user asked for ("or the user can remote install
them"), and it is flagged as such rather than silently applied — see the delivery note.

---

## Floored, with mechanisms

| Idea | Frame | Fails |
|---|---|---|
| Creature tank / living organism / desktop garden — capabilities as pets that droop when unused | night-shift, one-screen | **FIT.** Three frames independently produced a variant. The audience is a developer auditing what executes on their machine; anthropomorphising the thing under audit works against the judgment being asked for. |
| Physics leaderboard — rows jostling live as popularity changes | night-shift | **SOUNDNESS.** Requires continuous popularity deltas that neither registry publishes. The motion would be animating polling noise. |
| Luthier tap-tone evals — score mapped to a synthesized resonance | cross-domain | **SOUNDNESS**, and the frame said so itself: a luthier's ear is trained against thousands of known-good tops; a tone mapped to an arbitrary score has no perceptual grounding, so users must learn a vocabulary before it means anything. |
| Dairy yield curve → automatic cull list | cross-domain | **SOUNDNESS**, self-named: invocation count conflates "unused because worthless" with "unused because rare but critical". A migration skill used once a year is not a cull candidate, and milk yield never has that ambiguity. |
| MEL countdown to *automatic* removal ("47 sessions remaining") | cross-domain | **SOUNDNESS** as auto-removal — an irreversible action on a heuristic. The placard itself is already shipped; the countdown survives only as a prompt. |
| Trending as installer-topology constellation | adversary | **FEASIBILITY.** Needs opt-in telemetry keyed on org identity that this app does not collect and should not start collecting to power a browse screen. Good idea, wrong product stage. |
| Fling-to-Mac over Bluetooth RSSI direction-finding | night-shift | **FEASIBILITY.** RSSI direction-finding is unreliable at desk distances, and the failure mode is sending to the wrong Mac silently. |
| Sandbox-evasion tripwire in the eval harness | adversary | **FEASIBILITY** at v1 — a genuinely good idea that needs an eval sandbox to exist first. Parked, not rejected. |
| Menu bar icon as a live oscilloscope trace | night-shift | **FIT** with the squawk rule: an icon that changes constantly is one the eye filters, and then it filters the one change that mattered. |
| Gumball-machine crank — install requires a 270° drag with ramping resistance | toy designer | **FIT.** Friction on install buys nothing here; the safety comes from the capability diff, and a person installing eleven things pays the tax eleven times for a thrill that lasts two. |
| Jukebox record with scuff texture encoding popularity | toy designer | **SOUNDNESS.** Same defect as the physics leaderboard: renders a wear metric neither registry publishes. |
| Ant-farm tunnels that collapse when unused | toy designer | **FIT**, and it is the fourth independent variant of decay-as-metaphor across three frames — a strong signal about where this model reaches by default, and about what to keep refusing. |
| Message-in-a-bottle handoff with drift time | toy designer | **FIT.** Dresses an unknown delivery state as whimsy. The honest version is a queue item with a state, which is what the phone tray already is. |
| Two-man-rule vault pairing (both devices turn a dial simultaneously) | toy designer | **FIT.** Requires holding both devices at once, which defeats the entire premise of finding something while away from the Mac. |

---

## Provocation

Every mechanism above defends the user from the marketplace. None defends the marketplace
from a bad actor *publishing* through it — and this user runs one (`fledgeling-plugins`, 20
plugins). What would the publisher-side surface look like: the thing that tells you your own
skill has been forked, that the fork mutated its instructions, and that the fork is now
outranking you in the trending list?
