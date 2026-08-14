# spec-I3 — iPhone: Triage, Queue and Library

**Status:** Ready for Work
**Depends on:** I1 (shell and pairing) ✓ merged `d582d43`, I2 (Discover and detail) ✓ merged
`ba139d4`, F2 ✓, F3 ✓. M6 (Mac inbox) ✓ merged `6b3e940` — and its transport is **not** built, which
is the single fact that shapes this spec most.
**Design authority:** `DESIGN.md` (root). **Design representation:**
`design/mocks/i3-phone-triage.html`.
**Practices:** `planning/practices/SWIFT_PRACTICES.md`, `CODING_PRACTICES.md`,
`NEW_PROJECT_BEST_PRACTICES.md`, `UI_VERIFICATION.md` — all binding.

I3 completes the phone. `PhoneShell.Tab.triage`, `.queue` and `.library` all resolve to `AwaitingTab`
today; when this lands, `awaitingKey` returns nil for every tab and `AwaitingTab` has no caller.

---

## Feature description

Verbatim from `planning/features-to-triage/I3-ios-triage.md`:

> # I3 — iPhone: Triage, Queue, Library, Settings
>
> **Depends on:** I2.
>
> Triage is the surface with the most design history and the tightest constraints.
>
> **It is a checklist, not a swipe deck.** The deck was built and rejected for a reason
> that is not taste: a swipe commits a security decision on a gesture, one item at a time,
> with no undo and no record of what was dismissed. What replaces it:
>
> - Buckets as segmented tabs with counts — Undecided / Queued / Not for me — so
>   dismissals have a home and are revisitable from the desk.
> - A checkbox per row, and a one-line colour-coded capability summary on every row so the
>   security fact is visible without opening anything.
> - Tap to expand for the full capability list.
> - A commit bar carrying the count (`Send 2 to Mac`), disabled until something is
>   selected, with a line stating that nothing installs from the phone.
> - Inline Undo after any batch action. No confirmation dialog — the commit bar already
>   states what will happen and Undo already exists.
>
> Two bugs found in the prototype that must not survive into the build: every checkbox
> rendered ticked by default on a screen whose whole job is deliberate selection, and the
> capability lines truncated. Rows are a fixed height and never ellipsise.
>
> **Queue** — what has been sent and its status on the Mac. **Library** — what is
> installed, read-only. **Settings** — the paired Mac, notifications, and unpairing.
>
> Deep link: `?only=phone&tab=triage`.

**Settings is I1's and is already shipped** (`PhoneSettingsScreen`, merged `d582d43`: the paired Mac,
unpairing, the camera-permission recovery). It is named in the brief because the brief enumerates the
phone's remaining tabs, not because it is unbuilt. This item does not touch it, and re-verifying it
would be exactly the repetition `UI_VERIFICATION.md` §2 forbids.

---

## What the router actually observes

Everything below derives from this section, so it comes first. Every claim was read out of
`src/control.ts`, `src/registry.ts`, the merged `MCPRouterKit` sources and `planning/specs/spec-M6.md`
for this item, not carried over on trust.

### There is no transport, and this is the governing fact

| Piece | State | Evidence |
|---|---|---|
| The Mac's inbox UI and session logic | **Shipped** (M6) | merged `6b3e940` |
| The wire envelope the phone would send | **Specified** (M6) | `spec-M6.md` §"What the phone is allowed to say about an item" — `t`/`v`/`id`/`entry`/`name`/`queued`/`device` |
| A listener on the Mac, a network client on the phone | **Does not exist** | `spec-M6.md` §Scope: *"M6 does not build a network transport"*; deferred child **D-m6-a** |
| The phone's pairing service | `FixturePairingService` only | `MCPRouterIOSApp.swift`, and I1 recorded the decision |

**Consequences, and each one kills something the prototype draws.** Nothing this phone queues can
currently reach a Mac. The phone can therefore observe **no Mac-side disposition at all** — not
"added", not "rejected", not "seen". `ConnectionState` on the shipped phone is a hardcoded
`.reachable` default (`MCPRouterIOSApp.swift` passes no `connection:`), so it is not an observation
either. Any surface that renders a Mac-side outcome is rendering an invention.

### The candidate feed for Triage

`GET /registry/search` defaults `q` to `''` (`src/control.ts:480`) and `limit` to 30, capped at 60.
An empty query is legal and returns the top N **by popularity** — `searchRegistries` sorts by
`useCount → stars → updatedAt` (`src/registry.ts:342`) and then truncates with `slice(0, limit)`
(`:353`).

**So Triage's candidate set is the same page Discover browses, requested with no query**, and I2's
constraint carries over unchanged and unweakened: the page was selected by popularity *before the app
saw it*, so **no copy on this surface may make an index-wide claim**.

**There is no feed, no cursor and no seen-state.** No `since` parameter, no offset, no per-user read
marker anywhere in this product. "New since Tuesday" — which the prototype's empty state asserts — is
not a thing the router can be asked. Undecided is therefore a **derived** set, defined in A7.

### Per-entry fields

Exactly I2's A7 set, re-verified against `RegistryModels.swift` for this item: `useCount`, `stars`,
`forks`, and dates from `updatedAt` / `pushedAt`, plus the non-numeric `source`, `archived`,
`install`, `installed`, `verified`. **There is no eval count, no licence, no category and no install
count.** The prototype's triage rows carry three of those four.

### The Library's data

`GET /servers` exists and returns `ServersResponse { port, idleMs, since, pendingAuth, servers }`.
`MCPServer` carries `name`, `transport`, `state`, `tools`, `toolNames`, `idleSec`, `callsServed`,
`warm`, `auth`, `usage` and more.

**There is no `/skills` route on either router** — grepped again for this item across `src/*.ts`;
zero hits. `ControlAPIClient.skills()` exists in F3's client and the reference router does not serve
it; M4's own fixtures record that its endpoint does not exist and that a Release build never reaches
them. **The Library lists servers.** The skills absence is stated as a fact (A20), not drawn as an
empty list.

### The queue

I2 shipped the write port and the item type and explicitly assigned the reader and the storage format
to this item (`spec-I2.md` Assumption C, A22). `QueuedCapability { id, displayName, source, install,
queuedAt }`; `CapabilityQueueWriter { enqueue, contains }`; `FileCapabilityQueueWriter` writing
`capability-queue.json` into Application Support, atomically, with `unreadable` and `writeFailed` as
named errors.

**The shipped app does not use it.** `MCPRouterIOSApp.swift` constructs `PhoneShell` without a
`queue:` argument, so it takes the default `InMemoryCapabilityQueue()`. I2's A22 criterion *"an
enqueued item survives an app relaunch"* is true of the type and **false of the app**. Fixing that
injection is squarely this item's, because this item owns the storage format and is the first surface
that would show the loss. See A18.

---

## Acceptance criteria

### The interaction

**A1 — Triage is a checklist. No gesture commits anything.**
There is no swipe-to-decide, no swipe-to-reveal-an-action, and no numbered stepper. Every act on this
surface is a discrete tap on a labelled control that is visible before it is touched. The three
rejected alternatives and the specific property that disqualified each are recorded in the design
representation's header and in §Rejected interactions below; the criterion here is the negative one,
and it is checkable: **no view in this feature attaches a `DragGesture`, and no row carries a swipe
action.** Asserted by scanning the feature's own sources, not by inspection.

**A2 — nothing is selected by default, and the commit bar does not exist until something is.**
The first of the two prototype bugs, inverted. On a screen whose job is deliberate selection, a
pre-ticked default makes "send all of these to my laptop" the act you get by doing nothing. The
selection set starts empty on every appearance of the surface and on every bucket change; the commit
bar is **absent**, not disabled, when the set is empty — there is nothing to commit, so there is no
commit control. `Select all` is an explicit named control.

**The empty-and-unpaired cell, named rather than left to collide with A12.** When the set is empty
*and* a Mac is paired, the bar is absent. When **no Mac is paired**, the bar is present and dimmed
**from first appearance**, before anything is ticked — because the reason ("there is nowhere to send
this") is a fact about the surface rather than about the selection, and a user who ticks four rows
and only then learns there is no destination has been allowed to waste the work. A12's "never
hidden" governs the unpaired case; A2's "absent" governs the paired-and-empty case. Both cells are
in the state matrix.

**A3 — the row is two targets, each ≥44pt, each doing exactly one thing.**
The leading checkbox toggles selection. The meta block toggles expansion. A row that both selects and
expands from one tap makes the more consequential act an accident of where the thumb landed. Both
targets are asserted at ≥44pt on the hosted view tree.

**A4 — expansion is in place and never a push.**
Discover already owns the read-one-thing-properly path and pushes to `CapabilityDetailView`. Triage's
premise is comparison across rows, and a push destroys it — the user returns having lost their place
and, in the general case, their selection. The full capability list opens under the row; the list
keeps scroll position and the selection set is unchanged by expanding or collapsing.

**A5 — the capability summary is on every row, always visible, derived, and never truncates.**
The second prototype bug, inverted. This is the one line on the row carrying the security fact, so
truncating it hides exactly what the row exists to show. It **wraps**; the row grows. It is **derived
from the `install` descriptor**, never authored per entry, using the same derivations as I2's
capability plate (A6), which is what makes it short by construction rather than by hope.

**A6 — the summary's derivations are `CapabilityPlate.lines`', reduced to one line, and the colour
rule is stated.**

`CapabilityPlate.lines` has **seven** outcomes, not five, and the summary reuses the same seven
rather than a paraphrase of them — one derivation, two renderings, so the row and the plate cannot
come to disagree about the same entry.

| Input | Clause | Colour |
|---|---|---|
| `install.type == .stdio` | Runs a program on your Mac | `--attn` |
| remote transport, host parses | Nothing runs on your Mac · {host} | none |
| remote transport, **`host == nil`** | Nothing runs on your Mac · the index does not say where requests go | none |
| `requires` has an `isSecret`, **non-Smithery host** | needs a credential | `--attn` |
| `requires` has an `isSecret`, **Smithery host** | needs Smithery's key, which every entry there declares | none |
| `archived == true` | repository archived | none |
| `install == nil` | Neither index says how this runs | none, and the row cannot be selected |

Clauses **accumulate** in table order and are joined with ` · `. The line takes `--attn` if any
attn-clause matched, and **no other colour is ever used on it** — `--live` means "a child process is
running" and `--fail` means "failed or tripped", and this row is neither. Colour is never the only
signal: the line carries a glyph and states the fact in words.

**The two rows a five-row table would have dropped are the two that matter most.** A remote install
whose URL will not parse has no host, and a four-row table renders the literal `{host}` or an empty
segment on the one clause that says where the user's tool arguments go. And every Smithery-hosted
install declares a required `Authorization` **unconditionally** (`src/registry.ts:172-179`), so
within that subset the credential clause distinguishes nothing — since Smithery is a majority of the
corpus, an unconditional `--attn` on it fires the attention colour on most rows, which is precisely
the outcome this criterion exists to prevent. `CapabilityPlate` already admits this and its comment
states the rule: *the difference between a warning and noise is whether it admits when it carries no
signal.* The summary inherits the admission, not just the words.

**A7 — three buckets, and Undecided is derived.**
`Undecided = results − queued − dismissed`. `Queued` is what this phone's queue holds. `Not for me` is
what the user dismissed. Each segment carries its count; the counts are **observed** — each is the
size of a set the user's own decisions produced, which is why a count is permitted here at all.
An entry whose `installed` flag is set is **not** filtered out of Undecided: `installed` is a
display-name collision test, not an identity match (I2 A23), and silently hiding a row on a heuristic
is worse than showing it with an honest line.

**A8 — no copy on this surface asserts a recency, a novelty or an index-wide fact.**
There is no feed, no cursor and no seen-state, so "new", "since", "latest" and "unread" are all
unavailable. The empty-Undecided state says what is true — you have decided on everything in *these
results* — and names the act that widens them. Stated positively so it is checkable: **every count
rendered is the size of a locally-held set, and every band-like phrase is scoped to "these
results".**

**A9 — a dismissal persists, has a home, is reversible from it, and its store fails the same way the
queue's does.**
This is the whole reason the deck was rejected, so it is a criterion rather than a nicety. `Not for
me` survives an app relaunch, is listed in its own bucket, and each row there carries `Move back to
Undecided`. A dismissal is never permanent and never invisible.

**The store is specified, because a dismissal set is exactly as load-bearing as the queue and fails
in exactly the same way.** `Undecided = results − queued − dismissed` (A7), so a dismissal store
that will not decode silently re-populates Undecided with things the user already turned down — the
same "failure mode is emptiness" defect A17 exists to forbid, applied to the other persisted set.
It is therefore given the same treatment, not a lesser one:

- A **second file**, `dismissed-capabilities.json`, beside the queue in the same directory. Not a
  second array in the queue's document: A19 keeps the queue's format byte-compatible with what I2
  shipped, and widening that document would break it.
- `DismissalStore { func all() async throws -> [DismissedCapability]; func dismiss(_:) async throws;
  func restore(_ id:) async throws }`, an actor over the file, with
  `DismissalStoreError.unreadable(String)` and `.writeFailed(String)` mirroring
  `CapabilityQueueError` case for case.
- A missing file is an empty set — the one honest emptiness. A present file that will not decode is
  `unreadable`, gets **its own Triage state** with its own copy, and the Undecided bucket is not
  rendered as if the dismissals were empty.
- `DismissedCapability { id, displayName, dismissedAt }` — the coordinate and when, nothing else. No
  reason field: the product never asks for one and a nullable reason nobody supplies is a column.

**A10 — every batch action offers inline Undo, and no action on this surface opens a confirmation
dialog.**
`DESIGN.md` §9: undo over confirm. The commit bar already states what will happen; a dialog after it
would ask the same question twice. Undo is an inline bar **in the list, not over it**, so it cannot
cover a row. It reverses the whole batch. Applies to queueing, to dismissing, and to removing from
the Queue.

### The commit

**A11 — the commit queues locally, its label carries the count, and the narrowing is on it.**
`Send {n} to Mac`, verb-first, no ellipsis — it commits now rather than opening a further view
(`DESIGN.md` §3.4). One prominent accent action per view and this is it; `Not for me` leads and is
never the default. The hint states `Queues {it/them} for review on {mac}` and carries
`PairingCopy.neverInstalls` **verbatim**, the same shared constant I2 puts on all seven of its commit
states. The act performed is `CapabilityQueueWriter.enqueue` per selected entry and nothing else.

**A12 — the commit is disabled only when no Mac is paired, and it dims in place.**
The predicate is `ConnectionState.canQueue` (`!= .neverPaired`), **not** `canSend`. I2 added the
distinction and documented why: queueing writes to local storage and succeeds with the Mac asleep, so
binding a queueing commit to `canSend` refuses an act that works. An entry with no `install`
descriptor cannot be selected at all (A6), so it never reaches the commit. Disabled dims in place
with its reason above it and is never hidden.

**A13 — queueing is idempotent on entry id, across the batch and across repeats.**
`enqueue` is already idempotent on `id`; the criterion is that the *surface* agrees — a batch
containing an already-queued entry produces no second row, the Queued count does not double, and the
original `queuedAt` is kept, because the fact the reviewer cares about is when it was first sent.

**A14 — a refused write renders as a failure and never as a queued item.**
I1's precedent: two `try?` sites made a refused Keychain write render "Paired." while nothing was
stored. A `CapabilityQueueError.writeFailed` on any item of a batch is surfaced, names what was not
saved, and that item does **not** move to Queued. A partial batch reports what did and did not land.

### The Queue

**A15 — the Queue displays no Mac-side status, because there is none to observe.**
The prototype's `WAITING` / `ADDED` / `NO` badges and its `last seen just now` subtitle are removed
rather than reworded. The two facts the surface may state are **what is queued** and **when this
phone queued it**. The stamp is instrument data and is monospace (`DESIGN.md` §2).

**A16 — the Queue ships no send control.**
The send act already happened in Triage; draining the queue is transport behaviour, not a second user
decision. Two independent reasons it must not exist: it would be a false affordance even after
D-m6-a lands, and — the sharper one — `SendCommitBar` binds `.disabled(!state.canSend)` while the app
passes a hardcoded `.reachable`, so it would render **enabled**, an active "Send N to Mac" that does
nothing. The surface instead states what happens next in words.

**A17 — an unreadable queue is never rendered as an empty queue.**
The single most important state on the surface. `CapabilityQueueError.unreadable` gets its own state
with its own copy, distinct from Empty, saying that something is saved, that this version cannot
decode it, and that nothing has been deleted or sent. This is the defect this repo's own TypeScript
router shipped — a flat `servers.json` loading zero servers with no error at all — and
`SWIFT_PRACTICES.md` §2 names it. **A missing file remains an honest empty queue**; only a present
file that will not decode is the error.

**A18 — the shipped app uses the file-backed queue, and an item survives a relaunch in the app.**
`MCPRouterIOSApp.swift` currently takes the `InMemoryCapabilityQueue()` default, so I2's A22
relaunch criterion is true of the type and false of the product. The app injects
`FileCapabilityQueueWriter(directory: try FileCapabilityQueueWriter.defaultDirectory())`. Because
that initializer throws, the failure is **handled and surfaced**, never `try?`-ed into an in-memory
fallback that would silently reproduce exactly the bug being fixed.

**A19 — the reader and the storage format are this item's, and stay the shape of what is locally
true.**
`CapabilityQueueReader { func all() async throws -> [QueuedCapability]; func remove(_ id: String)
async throws }`, implemented by the same `FileCapabilityQueueWriter` actor over the same file. The
format is unchanged from I2's `[QueuedCapability]` array — **no Mac-side field is added**, because
adding a status field now would be designing a status vocabulary against a wire that does not exist.
Removal is undoable (A10) rather than confirmed: removing something from your own outbox has no
blast radius, and the named-consequence dialog `DESIGN.md` §9 reserves is the Mac's.

**One merged type is modified, and it is named rather than discovered at build time.**
`InMemoryCapabilityQueue.all()` is today `public func all() -> [QueuedCapability]` — neither `async`
nor `throws` — so as written it cannot conform to the reader and, more importantly, **cannot produce
the `unreadable` state A17 calls the most important one on the surface**. It becomes
`async throws`, and its `init(failure:)` throws from `all()` as it already does from `enqueue` and
`contains`. Without that change A17's state is reachable only against a real filesystem with a
hand-corrupted file, which is not a state a host test can drive. This is a source-breaking change to
a type I2 merged; its only callers are previews and tests, all of which move in the same change.

So the merged types this item modifies are exactly three, all additively or by widening an
async signature: `PhoneShell` (A30), `PhoneMetric` (A29), `InMemoryCapabilityQueue` (here).

### The Library

**A20 — the Library lists servers, and states the skills absence as a fact.**
There is no skills index and no `/skills` route. The absence is one quiet block stating that the
router publishes no skills endpoint and that the Mac's Skills board is where they appear. It is not
an empty list, not a disabled filter, and not a "coming soon".

**A21 — every fact on a Library row is a named `MCPServer` field, and the never-started case is not
rendered as a freshness.**
Permitted: `name`, `transport`, `tools`, `state`, `idleSec`, and `usage.calls` **only** through the
merged derived property `MCPServer.neverUsed { usage.calls == 0 }`.

**Why `usage.calls` has to be in the set.** `src/control.ts:156,159` compute
`state: live?.state ?? 'idle'` and `idleSec: live?.idleSec ?? 0`, so a server that has **never been
started** reports `idle` with `idleSec: 0` — byte-identical to one that went idle this instant.
Rendering that as "idle" or "idle 0s" states a freshness the router did not observe. So a row with
`neverUsed` renders **"never started"**, which is true, and only a server with `usage.calls > 0`
renders an idle duration. A four-field list would have forbidden the only honest rendering.

Nothing is computed across servers. `--live` appears exactly where it means what it means: a child
process is running.

**A22 — the Library is read-only and offers no action that mutates the Mac.**
No add, no remove, no reset, no patch — the phone queues and never installs, and the Library is the
narrowest surface in the app. Its only control is a client-side filter. Asserted structurally: the
Library's views hold no reference to any mutating `ControlAPIClient` method.

**A23 — Offline means the router is not running, on all three surfaces.**
`ControlAPIError.routerNotRunning` renders as its own state, never as a generic network error
(`SWIFT_PRACTICES.md` §3). `DESIGN.md` §5 asks Offline to "offer to start it"; the phone cannot start
a process on the Mac, so it gives the instruction instead — **recorded as a deviation with its
reason**, exactly as I2 recorded it, not passed off as satisfied.

### States, copy, and the floor

**A24 — all three surfaces ship the nine `DESIGN.md` §5 states with real copy**, or record which are
structurally unreachable and why. Matrices below. Placeholder copy hides both layout and
comprehension failures, so every unhappy path is written out.
**Loading is measured, not asserted in prose.** "The list does not jump when data lands" is an
equality between two rendered heights, so it is one: the skeleton row and the row it replaces are
asserted **equal in height on the hosted tree**, on all three surfaces, using the SwiftUI
environment path I2's `DiscoverSurfaceIOSTests` already measures with. Left as prose it is a claim
no reviewer could check and no regression could fail.

**A25 — every rendered string comes from a copy manifest, keyed surface × state, exhaustive over an
enum** so a tenth state fails to compile rather than shipping blank. **Three sibling manifests —
`TriageCopy`, `QueueCopy`, `LibraryCopy` — split from the start, not after they grow.** That is a
real seam (three surfaces, three vocabularies), and it is written this way because I2's single
manifest hit the 400-line cap mid-item and a previous run silenced three lint rules at file scope
rather than splitting it. Each is a sibling of `PairingCopy` and `DiscoverCopy`, never an extension:
growing a merged shared surface from inside a feature is how two features come to disagree about what
it contains. Asserted as I1's and I2's copy is: pinned literal, rendered-tree assertion, and parity
against the design representation.

**Substitution uses `DiscoverCopy`'s enumerated-token mechanism, not `PairingCopy`'s.** The two
merged manifests resolve differently — `PairingCopy.Entry.resolved(macName:)` substitutes one value
with a `?? "your Mac"` fallback, while `DiscoverCopy.resolved(_ tokens:)` takes a dictionary keyed
by an enumerated `Token` and fails a test on a token no case declares. The enumerated one is chosen
because a typo'd `{mack}` renders literally to the user and passes every other test.
**`{mac}` renders `"your Mac"` when no Mac is paired**, and that is the rendering the shipped app
gets today: `MCPRouterIOSApp` passes no `macName:`, so it is nil. Stated because three copy tables
of shipped strings depend on it.

**A26 — every numeric string rendered maps to a named field or to the size of a locally-held set.**
Stated positively so it is checkable. The permitted set is exactly: `MCPServer.tools`,
`MCPServer.idleSec` (only where `!neverUsed`, A21), the three bucket counts, the commit count, the
queue's `queuedAt`, **the size of the decoded `servers` array**, and **the size of the filtered
result set**. The last two are what `LibraryCopy.subtitle` and the filtered-empty state render; an
earlier draft's enumeration omitted them while its own opening sentence permitted them, which left
two shipped strings depending on which half of the criterion a reviewer applied.
No `useCount`, no stars and no dates are rendered **on Triage rows** — the row's job is the security
fact, and I2's Discover is where an entry's popularity is read.

**A27 — 44pt minimum target, safe area, and colour never the only signal.**
Every interactive element meets 44pt on the hosted view tree. Nothing is occluded by the status bar
or the home indicator; the commit bar sits above the tab bar and inside the safe area. Every `--attn`
line carries a glyph and states its reason in words.

**A28 — motion is transform and opacity only, honours Reduce Motion, and never fades from 0 on
entry.** The commit bar and the undo bar both rise on transform alone.

**A29 — no raw geometry under the new views, and the guard's coverage is a placement rule rather
than a claim.** Every value reads `PhoneMetric` or a token. New constants go in `PhoneMetric` under
an `// MARK: - Triage, Queue, Library (I3)` section.
**The new views live under `app/Sources/MCPRouterUI/Phone/`** — the directory
`PhoneSourceGuardTests` enumerates recursively — so they are scanned by placement. Saying they
"join the scanned set" would have been a no-op that fails open: a file placed in a sibling directory
is silently unscanned and every geometry rule then passes vacuously, and `GuardError.nothingScanned`
only catches a wholly empty root, never a partially covered one. If a later change adds a sibling
root, it adds it to the guard's roots in the same change.

**A30 — all three tabs are reachable and real in the running app, and the dispatch is a `switch`.**
`PhoneShell.content(for:)` becomes an exhaustive `switch` over `Tab` with one case per surface and
`.settings` last.

**This replaces the mechanism an earlier draft described, which was wrong in a way its own test
could not catch.** The shipped dispatch is
`if tab == .discover { … } else if let key = tab.awaitingKey { … } else { PhoneSettingsScreen(…) }`
(`PhoneShell.swift:163-188`). Making `awaitingKey` return nil for the three tabs does **not** make
the awaiting branch unreachable — it routes all three to the final `else`, so Triage, Queue and
Library would each render **Settings**. And the proposed test (no awaiting string compiled into
`MCPRouterUI`) is green in exactly that world, so it could not tell three shipped surfaces from
three tabs showing Settings. A criterion whose verification cannot distinguish success from that
failure is not a criterion.

The assertion is therefore **positive and per tab**: hosting the shell selected on each of
`.triage`, `.queue` and `.library` finds that surface's **own pinned copy** in the rendered tree.

`awaitingKey` and `AwaitingTab` are then dead and are deleted, **with all four keys, not three** —
`.discoverAwaiting` has had no caller since I2 and would survive a scan of `MCPRouterUI` because the
key lives in `MCPRouterKit`.

**Deleting `.libraryAwaiting` moves the narrowing, and that is a shared-surface change made
deliberately rather than discovered at test time.** `PhoneCopyTests.narrowingPlacement` pins
`PairingCopy.narrowingKeys == [.settingsNeverPaired, .pairedSuccess, .libraryAwaiting]` under the
comment *"the narrowing is rendered where permission is being decided, and on the surface most
likely to be mistaken for an install surface"* — and the Library is that surface. So:
`LibraryCopy` gains a `narrowing` key carrying `PairingCopy.neverInstalls` **verbatim**, the Library
renders it, and `narrowingPlacement` is updated to `[.settingsNeverPaired, .pairedSuccess]` with a
sibling assertion that `LibraryCopy.narrowing == PairingCopy.neverInstalls`. The invariant the test
protects is preserved; only the file the Library's copy lives in changes.

**A32 — a Release build of the phone may never render a fixture.**
`ShellClientFactory` carries this rule for the Mac and states it in full: *"A Release build may never
render a fixture … a shell wired to `FixtureControlAPIClient` states '3 of 5 running' in the present
tense, from a JSON file, on a machine with no router at all."* **It is `#if os(macOS)` and the phone
has no equivalent** — `MCPRouterIOSApp.swift` passes no `client:`, so `PhoneShell` takes
`FixtureControlAPIClient()` in every configuration.

I2 shipped under that gap and it went unregistered. **This item cannot**, because the Library is the
one surface whose entire claim is *this is what you have installed*: a fixture there presents four
invented servers as the user's real installed set, in the present tense, on a device with no router.
That is the fabricated-figure defect at its most consequential.

So `PhoneClientFactory` is added, the same two-branch shape as the Mac's and for the same reason:
Release takes `.live` and **ignores the environment**, so a shipped build cannot be talked into a
fixture; Debug takes a scenario from `MCPROUTER_SCENARIO`, which is what gives the acceptance lane a
way to drive Loading, Partial, Error and Offline at all. The decision takes `isDebugBuild` as a
parameter rather than reading it, so a Debug test run can assert the Release branch — the only way
the rule is checkable.

**What a Release build then honestly shows is Offline**, because `LiveControlAPIClient`'s loopback
is the *phone's* loopback and there is no router on it. That is true, it is one of `DESIGN.md` §5's
designed states, and it is what the transport (D-m6-a) resolves. Consequences recorded rather than
hidden: **A20, A21, A23 and Assumption A are exercised on the macOS host and in Debug, and are not
reachable in a Release build on device until the transport lands.** Each is marked in the matrices.

**A31 — the Dynamic Type position is stated rather than silently reproduced.**
No phone surface scales with Dynamic Type: `TypeToken.font` is a fixed `Font.system(size:weight:)`
shared with every Mac surface, and `DESIGN.md` §2 fixes the eight sizes deliberately. **This item
does not change that** — it is a shared design surface and a unilateral change is how a shared
surface stops being shared. What these surfaces do about it: **nothing pins a height that would clip
if the ladder later scaled.** Every row, skeleton and control is a minimum plus intrinsic content, so
the surfaces are ready for the change without making it. Registered as a child (D-i3-a).
**I1's `testTextIsNotClippedAtAccessibilitySizes` is not copied**: it overrides Dynamic Type through
the UIKit trait collection, which measurably does not reach the SwiftUI view, so it is a test that
cannot fail.

---

## Copy matrix — the load-bearing strings

Shared, verbatim, one constant: `PairingCopy.neverInstalls` on every commit surface.

### `TriageCopy`

| Key | Copy |
|---|---|
| `hint` | Tap a name to read what it can do. Tick what is worth your Mac's attention. |
| `bucketUndecided` / `bucketQueued` / `bucketDismissed` | Undecided · Queued · Not for me |
| `selectAll` / `clearSelection` | Select all · Clear |
| `commit` | Send {count} to Mac |
| `commitHint` | Queues {it/them} for review on {mac}. |
| `dismiss` | Not for me |
| `restore` | Move back to Undecided |
| `expandedHeading` | What it would be able to do |
| `undoQueued` | {count} queued for your Mac |
| `undoDismissed` | {count} moved to Not for me |
| `undo` | Undo |

### `QueueCopy`

**Every string here states a local fact and a manual next step.** An earlier draft read "Waiting for
{mac} to collect them" and "it stays here until your Mac has it", which assert a pending automatic
transfer — the thing I2's merged A21 forbids outright (*"no copy promises an automatic send, because
nothing sends automatically"*) and the thing A15 forbids on this surface specifically. Nothing
collects. Nothing sends. The user opens their Mac.

| Key | Copy |
|---|---|
| `subtitle` | On this phone. Open MCP Router on {mac} to review them. |
| `stamp` | Queued {when} |
| `remove` | Remove {name} from the queue |
| `footer` | Your Mac decides. This list is the record of what you have queued, and it stays on this phone. |
| `undoRemoved` | {name} removed from the queue |
| `neverPairedHeadline` | No Mac is paired. |
| `neverPairedBody` | These are kept here. Pair a Mac and you can review them there. |

There is no `sectionWaiting`. The list is one section, so a header partitions nothing, and the only
word it could carry is `Waiting` — the badge vocabulary A15 removes, reintroduced at section scope.
A single-section list needs no header.

### `LibraryCopy`

| Key | Copy |
|---|---|
| `subtitle` | {count} servers · read-only from here |
| `filterPlaceholder` | Filter |
| `skillsAbsentHeadline` | Skills are not listed here. |
| `skillsAbsentBody` | The router publishes no skills endpoint, so this phone has nothing to read. Your Mac's Skills board is the only place they appear. |
| `footer` | Adding, changing and removing all happen at your Mac. This is the same list, so you know what you are carrying. |

## State matrix — Triage (A24)

| State | Copy |
|---|---|
| Default | Undecided, populated, nothing ticked, no commit bar. |
| Empty — Undecided | Glyph. **Nothing left to decide.** You have decided on everything in these results. Search Discover for something specific, or widen what you are looking at. — *Go to Discover* |
| Empty — Queued | **Nothing queued yet.** Tick something in Undecided and send it across. — *Go to Undecided* |
| Empty — Not for me | **Nothing turned down.** Anything you turn down stays here, so a decision made on a train is still readable at your desk. |
| Loading | Skeleton rows built from the real row's layout — three bars, the third the capability line — at the row's own minimum height, so the list does not jump when data lands. Never a spinner over a blank pane. |
| Partial — official down | **Showing Smithery only.** The official registry did not answer, so anything it alone lists is missing. — *Try again* |
| Partial — Smithery down | **Showing the official registry only.** Smithery did not answer, so anything it alone lists is missing. — *Try again* |
| Partial — GitHub limited | **Repository details are incomplete.** GitHub limits how often it can be asked, so archive status is missing for some entries. Everything else is complete. |
| Partial — unrecognised warning | **The search reported a problem.** {warning, verbatim} |
| Error | **The registry search failed.** The router answered, but not with results. Nothing was queued and nothing changed on your Mac. — *Try again* |
| Error — dismissals unreadable | **Your dismissals could not be read.** Something is saved on this phone and this version cannot decode it, so things you turned down may be listed again. Nothing has been deleted. — *Try again* (A9) |
| Success | The rows move to Queued in place, and the Undo bar appears. No toast. |
| Offline | **The router is not running on {mac}.** Triage reads the registries through it, so there is nothing to decide on until it starts. Open MCP Router on your Mac. **(A32: the honest Release state on device today.)** |
| Disabled | No Mac paired: the commit bar is present and dimmed **from first appearance**, reason above it — *No Mac paired yet, so there is nowhere to send this. Pair one in Settings.* Rows still read and still tick, because deciding is useful before there is anywhere to send. **Host-testable only (D-i3-b).** |
| Overflow | A long entry **name** truncates on one line, tail; the full value is one tap away on expand. The capability line always renders whole. |

The three Partial classes are I2's, unchanged — this surface reads the same endpoint, so it inherits
the same degraded states rather than inventing new ones, and classification is by the same
prefix match, **stated as fragile in the code**, with an unmatched warning rendered verbatim.

## State matrix — Queue (A24)

| State | Copy |
|---|---|
| Default | Newest first, no section header, the stamp in monospace. |
| Empty | **Nothing waiting.** Things you send from Triage or Discover collect here until you are back at your Mac. — *Go to Triage* |
| Loading | Skeleton rows at the queue row's minimum height. Reading a local file is fast, so this is usually a single frame — it exists because a slow disk is not a reason to render an empty queue. |
| Partial | **Unreachable** — the queue is one local file, read whole. There is no half of it to arrive. Recorded, not invented. |
| Error — unreadable | **The queue could not be read.** Something is saved on this phone and this version cannot decode it, so it is not being shown. Nothing has been deleted and nothing has been sent. — *Try again* (A17) |
| Error — write refused | **That item was not saved.** This phone refused the write, so it is not in the queue. Try again from Triage. (A14) |
| Success | The row leaves the list in place, and the Undo bar appears. |
| Offline | **Unreachable, and stated rather than invented.** The queue is local: it reads and writes without a router and without a Mac. There is no offline state because there is nothing remote to be offline from. |
| Disabled | No Mac paired: **No Mac is paired.** These are kept here. Pair a Mac and you can review them there. — *Pair a Mac*. Nothing is discarded. **Host-testable only (D-i3-b).** |
| Overflow | A long name truncates on one line; the capability line and the stamp render whole. |

## State matrix — Library (A24)

| State | Copy |
|---|---|
| Default | Servers, the skills-absence block, the read-only footer. |
| Empty | **No servers declared.** {mac} has no MCP servers declared yet. Queue one from Triage and accept it at your Mac, and it will appear here. — *Go to Triage* |
| Empty — filtered | **No server matches "{query}".** Clear the filter to see all {count}. — *Clear filter* |
| Loading | Row-shaped skeletons at the library row's own height. |
| Partial | **Unreachable** — `/servers` returns one document; there is no per-server fetch to half-fail. Recorded, not invented. |
| Error | **The server list could not be read.** The router answered with something this version does not understand. Nothing on your Mac has changed. — *Try again* |
| Success | Not applicable — the Library has no commit. Recorded rather than invented. |
| Offline | **The router is not running on {mac}.** The library is the router's own list of declared servers, so there is nothing to show until it starts. Open MCP Router on your Mac. |
| Disabled | The filter dims in place while the list is empty, reason beside it. |
| Overflow | A long server name truncates on one line; the fact row wraps rather than truncating. |

---

## Rejected interactions, and the property that disqualified each

Recorded because "we considered a swipe deck" is not reviewable. All three are **drawn** in
`design/mocks/i3-phone-triage.html` §F.

| Pattern | Why not |
|---|---|
| **Tinder-style swipe deck** — built once, rejected by the owner | Three structural faults, none of them polish: a gesture commits a security decision with **no undo**; it is **one item at a time** on a surface whose value is comparison; and a dismissal leaves **no record**, so a decision made badly on a train cannot be found again at the desk. The buckets exist because of the third. |
| **Whering's numbered review stepper** ("3 of 18") | A stepper is a queue with a cursor: it **decides the order** for you and has **no batch**. The value here is seeing eight rows at once and picking the two worth the Mac's attention, which a stepper structurally forbids, and it converts "I have seen enough" into eighteen taps. |
| **Apple Mail / Spark swipe-to-reveal** | Genuinely the best of the three — the label is visible and the act is undoable. Still rejected: **one item per gesture**, with the action **hidden until you drag**, on a surface whose subject is a comparison across rows; and a leading-edge drag **collides with the system back-swipe**. The checkbox says the same thing with nothing to learn. |

**What ships, and the two decisions inside it that are mine rather than the brief's:** the row is
**two targets** rather than one, so the consequential act is not an accident of thumb position; and
expansion is **in place rather than a push**, because a push destroys the comparison the surface
exists for.

---

## Triage — 2026-08-15

### Codebase grounding

- **The three tabs are the `AwaitingTab` branch**, selected by `awaitingKey` returning non-nil. This
  item returns nil for all three and deletes the placeholder (A30).
- **The candidate feed is F3's merged `searchRegistry(query:limit:)`** called with `""`. No new
  endpoint is added and none is needed.
- **The queue's write half is I2's, merged**; the reader and the format are handed to this item
  explicitly (`spec-I2.md` Assumption C).
- **`PhoneMetric` is the only file under `Phone/` permitted to write geometry**, enforced by
  `PhoneSourceGuardTests`. New constants go there.
- **`ConnectionState.canQueue` is I2's and is the right predicate** (A12). No merged type is modified
  by this item except `PhoneShell` (the three branches) and `PhoneMetric` (additive).
- **`SendCommitBar` is I1's, unused, and stays unused** (A16). Registered as a finding, not adopted.

### Assumptions — recorded, each falsifiable

**A — Triage's candidate set is `/registry/search` with an empty query.** Falsifiable by the user
saying Triage should only hold things explicitly saved from Discover. Taken because the brief's
buckets require an Undecided population that a save-first model would leave permanently empty — an
item saved from Discover is already decided — and because the endpoint supports the query-less call.

**B — "Not for me" is local, persistent and reversible.** It is genuinely observed state and it is
the one thing the deck could not give.

**C — the Queue reports no Mac-side status and ships no send control.** The strongest assumption
here. Falsifiable by the user preferring a visible send affordance now, ahead of the transport.
Taken because there is nothing to send with, and because `SendCommitBar` bound to `canSend` under the
app's hardcoded `.reachable` would render **enabled** and do nothing. Raised in §Questions.

**D — the Library lists servers only.** Not a preference: there is no skills index.

**E — the storage format gains no Mac-side field.** Adding one now would design a status vocabulary
against a wire that does not exist. When D-m6-a lands, the envelope M6 already specified is what the
phone produces, and `supportedVersions` is how it grows (D-m6-b).

**F — Settings is out of scope**, being I1's and merged.

### Specification Sentinel — product / UX / compliance

- **Product.** The reason to exist survives: decide, in a batch, which of the things you are looking
  at are worth your Mac's attention, with the security fact visible before you tick anything. What is
  lost against the prototype is a Mac-side status nobody can observe and three fabricated fields.
- **UX.** The two decisions that carry the surface are the two-target row and the in-place expansion;
  both are stated on the design representation rather than left to be discovered. The bucket counts
  are the only numbers, and each is the size of a set the user made.
- **Compliance.** The phone queues and never installs (A11, A16, A22); no unobserved number is
  displayed (A8, A15, A21, A26); `command`/`args`/`env` are never writable — **this feature performs
  no PATCH and no mutating control call at all**, and its only writes are to a local file.
- **Accessibility.** 44pt targets, safe area, Reduce Motion, colour never the only signal (A27, A28).
  The Dynamic Type position is stated and not silently reproduced (A31).

### Gate verdict — in-family adversarial review

`codex: usage limit → claude (downgrade).` The out-of-family lane is account-limited until
20 Aug 2026 and **exits 0 on that limit**, so it was neither probed nor keyed on. The gate ran
in-family: a fresh `claude -p` opus-5 reviewer briefed to refute, and told that finding nothing would
be a failed review. **This is the weaker arrangement — Claude auditing Claude — recorded here so the
weakness travels with the evidence.**

*(Findings and dispositions appended below by the gate run.)*

**Returned 17 findings: 5 high, 1 medium/high plus 3 more at medium/high, 6 medium, 3 low. Accepted
17, rejected 0.** Every high was verified against source before acceptance rather than taken on the
reviewer's word. A clean sweep is recorded as what it is: this spec's first draft was wrong in five
load-bearing places, and the gate is the reason they are not in the plan.

The five that changed the design:

- **F5 — A30's stated mechanism was wrong, and its own test could not catch it.** The draft said
  making `awaitingKey` return nil would make the awaiting branch unreachable. It does not: the
  shipped dispatch ends in `else { PhoneSettingsScreen(…) }`, so all three tabs would have rendered
  **Settings** — and the proposed test (no awaiting string compiled into `MCPRouterUI`) is green in
  exactly that world. A30 now specifies an exhaustive `switch` and a positive per-tab assertion.
- **F1 — the phone renders a fixture control client in every configuration**, and the Mac's rule
  forbidding exactly that (`ShellClientFactory`, *"A Release build may never render a fixture"*) is
  `#if os(macOS)`. I2 shipped under the gap unregistered. New **A32** adds the iOS analogue, because
  the Library is the surface where a fixture is most dangerous: it presents invented servers as the
  user's real installed set.
- **F2 — A9 required dismissal persistence and specified no store, no error and no state**, while
  the queue beside it got a file, an actor, two named errors and a dedicated state. An unreadable
  dismissal store silently re-populates Undecided with things the user turned down — the same defect
  A17 exists to forbid, on the other persisted set. Now fully specified.
- **F3 — the Queue's copy promised a collection nothing performs** ("waiting for {mac} to collect
  them", "until your Mac has it"), contradicting I2's merged A21 and this spec's own A15. Rewritten
  to state the local fact and the manual next step.
- **F8 — A6 had five derivations where `CapabilityPlate` has seven**, dropping the nil-host clause
  and the Smithery credential admission. Since Smithery is a majority of the corpus, the draft would
  have fired `--attn` on most rows — the exact outcome the criterion claims to prevent.

Two more worth carrying: **F4**, that `idleSec == 0` is byte-identical for "idle this instant" and
"never started", so A21 needed `usage.calls` to render the honest one; and **F6**, that deleting
`.libraryAwaiting` removes `PairingCopy.neverInstalls` from the Library and breaks a merged test —
so `LibraryCopy` now carries the narrowing and the test's set moves with it.

The gate also **confirmed as true** a set of claims that would have been expensive to get wrong: no
`/skills` route while `ControlAPIClient.skills()` exists; the app does take the
`InMemoryCapabilityQueue` default; `enqueue` is idempotent and keeps the original `queuedAt`; a
missing queue file is empty while a present undecodable one is `unreadable`; `canQueue`/`canSend`
are genuinely two predicates; `SendCommitBar` has no non-test caller; and `--attnWash`/`--attnLine`
are still absent from `ColorToken`.

---

## Out of scope

- **Settings (I1, merged).** Named in the brief only because it enumerates the phone's tabs.
- **The transport (D-m6-a).** Everything this item cannot say about a Mac traces to it.
- **Fixing `ConnectionState`'s hardcoded `.reachable` in the app**, and I2's `Reachable — items you
  send arrive now.` which that value selects. The defect is the **input**, not the copy: nothing
  observes reachability, so the correct branch cannot be chosen. Fixing the input is D-m6-a's;
  registered as **D-i3-b** so it is not mistaken for something this item dropped.
- **The Mac's inbox (M6, merged).** This item writes a local queue; nothing reads it off-device yet.
- **Evaluations, licences, categories and install counts** — nothing on the wire carries them.
- **A skills index** — no route on either router.
- **Shared design tokens.** `--attnWash` / `--attnLine` are still absent from `ColorToken` (I1
  reported it, I2 reported it again); this feature reads `PhoneMetric.tintedBorderOpacity` as both did.

## Deferred children

| # | Child | Absorbed by | Mechanism |
|---|---|---|---|
| D-i3-a | The phone does not scale with Dynamic Type | F2 + a design decision | `TypeToken.font` is a fixed `Font.system(size:weight:)` shared with every Mac surface, and `DESIGN.md` §2 fixes the eight sizes deliberately. Making the phone scale is a change to a merged shared surface and to the design authority, so it is not taken unilaterally inside a feature. These surfaces are written so it can be made without touching them (A31). |
| D-i3-b | The phone's `ConnectionState` is a hardcoded `.reachable`, so **both Disabled states are unreachable on device** | D-m6-a | `MCPRouterIOSApp` passes no `connection:`, so `PhoneShell` takes `connection: .reachable` unconditionally and `canQueue` is always true. Two consequences. (1) Triage's and Queue's no-Mac-paired states cannot render on a device and are exercised on the macOS host only — marked in both matrices, so A24's "record which are structurally unreachable and why" is actually satisfied for the states the register was meant to cover. (2) I2's `Reachable — items you send arrive now.` is shown while the item is still on the phone. **The copy is right for its branch; the branch selection is what is unobserved**, so the fix is a real reachability probe, which is the transport's — patching the copy would fix the wrong layer. |
| D-i3-c | `SendCommitBar` is an orphan | D-m6-a, or deletion | I1 built it for a Queue send step that A16 shows has no honest home, and it binds `.disabled(!canSend)` against the hardcoded `.reachable` above — so if a later runner wires it up "because it is there", it renders **enabled** and does nothing. Either delete it or land it with the transport; do not leave it discoverable and inert. |
| D-i3-d | The registry's `installed` flag is a display-name collision test | R3 | Already registered by I2. Restated here because Triage's Undecided set deliberately does **not** filter on it (A7), and that decision depends on the flag being a heuristic. |
| D-i3-e | **`spec-I2.md` A29 asserts a fact about a merged file that is false** | F2, with D-i3-a | A29 reads *"The row's 44pt is a minimum, not a fixed height: it grows with Dynamic Type"*. `TypeToken.font` is `.system(size:weight:)` with a fixed size, so nothing on the phone grows with the text size and the row cannot. The minimum-not-fixed half is right and this item keeps it (A31); the "grows with Dynamic Type" half is a merged criterion that cannot be met by the merged code. Registered rather than edited: amending another item's merged spec unilaterally is the same shared-surface hazard as amending its copy. It is the reason A31 states the position in its own words instead of citing A29. |
| D-i3-f | **The phone has no `/servers` route to reach even after A32** | D-m6-a | `LiveControlAPIClient`'s default `baseURL` is `http://127.0.0.1:8879` — on an iPhone that is the *phone's* loopback, and there is no router on it. A32 makes a Release build show the honest Offline state rather than a fixture, which is the correct behaviour today, but the reason it is Offline is that the phone has no path to the Mac's control API at all. The transport is what gives it one. |

## Questions for the user

1. **The Queue ships no send control and no Mac-side status (Assumption C).** There is no transport,
   so there is nothing to send with and no outcome to read. The alternative is a visible "Send N to
   Mac" that is bound to a reachability value nothing observes — under the app's hardcoded
   `.reachable` it would render *enabled* and do nothing. Accept the outbox framing, or want the
   control drawn now against the seam?
2. **Triage's Undecided is the query-less registry page minus your decisions (Assumption A).** The
   alternative is that Triage holds only things explicitly saved from Discover — but an item saved
   from Discover is already decided, which would leave Undecided permanently empty. Accept?
