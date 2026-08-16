# D3 — two copy decisions, drafted for the owner

`D-i3-g` and `D-i3-h` are spec-level: the strings are specified verbatim and passed the spec gate,
so amending them is a spec change and belongs to whoever owns the copy. **Nothing in this file has
been applied to the code.** Each is written so it can be accepted or edited in one pass.

Both premises were reproduced first. Both hold.

---

## D-i3-g — the commit button says "Send" on a surface where nothing sends

### Reproduced

| | |
|---|---|
| The button | `"Send {count} to Mac"` — `TriageCopyStates.swift:22` (`.ready`) and `:28` (`.neverPaired`) |
| Its own hint, directly beneath | `"Queues them for review on {mac}."` |
| What pressing it does | `TriageModel.queueSelected()` → `queue.enqueue(…)` per selected entry. A write to **this phone's own storage**. Nothing is transmitted |
| Can anything send? | No. `D-i3-f`: the phone's `LiveControlAPIClient` default `baseURL` is `http://127.0.0.1:8879`, which on an iPhone is the *phone's* loopback. There is no transport at all |
| What the code already does | Renamed away from the verb on purpose: the predicate is `canQueue`, never `canSend`, and `ConnectionState` carries a comment explaining why |

So the button and its own hint use different verbs for one act, and the button's verb names the one
thing the product cannot do.

### Recommendation

**`"Queue {count} for your Mac"`** — for both `.ready` and `.neverPaired`. Bodies unchanged.

```swift
case .ready:
    Entry(
        body: "Queues them for review on {mac}.",
        actionLabel: "Queue {count} for your Mac",
        carriesNarrowing: true
    )
case .neverPaired:
    Entry(
        body: "No Mac paired yet, so there is nowhere to send this. Pair one in Settings.",
        actionLabel: "Queue {count} for your Mac",
        isDisabled: true,
        carriesNarrowing: true
    )
```

**Why this exact wording rather than something near it:** the product already says it. The undo
toast for this same act is `TriageCopy.commit(.undoQueued)` = `"{count} queued for your Mac"`. Take
this and the button, its hint and its confirmation all describe one act with one verb. It also
keeps `DESIGN.md` §3.4's rule intact — verb-first, count carried, no ellipsis, commits now.

**What it claims:** these items are being put in a queue whose destination is your Mac. True — the
write is local, the destination is real, and arrival is not promised.

### Rejected, and why

| Option | Why not |
|---|---|
| **Keep `"Send {n} to Mac"`** | It is the only string in the product that states an act the product cannot perform, and its own hint contradicts it one line below. This is the defect, not a tolerance |
| **Keep "Send" and change the hint to match** | Resolves the inconsistency by making *both* strings claim a transfer that never happens. The one option that makes the product less honest |
| **`"Add {n} to Queue"`** | Accurate but drops the destination, which is the single most useful thing the bar says. Also collides with Discover's "Add" vocabulary |
| **`"Save {n} for Mac"`** | "Save" is already the failure vocabulary here — `"Some of those were not saved."`, `"That was not saved."`. Reusing it for the happy path muddies the failure state |
| **`"Queue {n} for review"`** | Drops the Mac, and "review" is already carried by the hint. The button would then name neither the destination nor the device |

### If accepted, these move together

1. `TriageCopyStates.swift:22, :28` — the two `actionLabel`s.
2. `DESIGN.md:278` — currently *`Buttons are verb-first and name the action. "Send 2 to Mac", never
   "Submit" or "OK".`* The **rule** is right and stays; only the example changes, to
   `"Queue 2 for your Mac"`.
3. `design/app/mobbin-ledger-2.md:76` — the provenance line "Adopted verbatim as **"Send 2 to
   Mac"**". Amend the adopted string, keep the provenance.
4. `spec-I3.md` — A11's body, the summary at line 36, and the copy table at line 498.
5. `planning/features-to-triage/I3-ios-triage.md:16`.
6. **Widen the guard.** `queuePromisesNothing` forbids nine paraphrases of an automatic transfer
   (`"waiting for"`, `"to collect"`, `"on its way"`, …) but not the bare verb the rule is about,
   and it scans `QueueCopy` only — so the button making the promise is outside its reach. It should
   scan `TriageCopy` and `TriageCopyStates` too, and forbid `Send`/`Sends` in commit copy for an
   act that queues.

**One thing that must NOT change:** `SendCommitBar.commitLabel` in `ConnectionBanner.swift:120` is
also `"Send \(itemCount) to Mac"`. That is I1's orphan component (`D-i3-c`), built for a Queue send
step that does not exist yet. If it is ever landed with the transport it will genuinely send, and
`"Send"` is the correct verb there. Leave it — or delete it under `D-i3-c` — but do not
sweep-rename it.

---

## D-i3-h — the Dismissed empty state claims a durability it does not deliver

### Reproduced

`TriageBuckets.resolve` (`TriageBuckets.swift:83`) iterates `results` and nothing else:

```swift
for entry in results {
    if queuedIDs.contains(entry.id) { queued.append(entry) }
    else if dismissedIDs.contains(entry.id) { dismissed.append(entry) }
    else { undecided.append(entry) }
}
```

Both decided buckets are therefore **the intersection of the stored sets with the current 30-item
results page**. Dismiss something while searching "github", then search "weather": the Dismissed
segment reads 0, and its empty state says

> **Nothing turned down**
> Anything you turn down stays here, so a decision made on a train is still readable at your desk.

with no control to restore it. `DismissedCapability` stores `displayName` expressly so a row is
readable without a second registry search, and that field is never used for this.

**The store is durable. The view is not.** The sentence is true about the store and false about the
screen it is printed on.

### Recommendation — take the copy now, register the behaviour

Change the copy in this pass; register "render the decided buckets from the stores" as a separate
spec'd item. Reasons, in order:

1. The false claim is live in the product **today**, and copy is the cheap, reversible half.
2. Rendering from the stores is not a copy fix wearing a behaviour hat. It changes what a row in
   those buckets *is*: the store holds a `displayName`, not a `RegistryEntry`, so store-backed rows
   would carry no capability clauses and no install descriptor while sitting next to Undecided rows
   that do. Rows that look identical but say less is a new honesty problem, and it wants a spec.

```swift
case .queued:
    Entry(
        headline: "Nothing queued in these results",
        body: """
        Tick something in Undecided to queue it for your Mac. This list shows only what the \
        current results contain.
        """,
        actionLabel: "Go to Undecided"
    )
case .dismissed:
    Entry(
        headline: "Nothing turned down in these results",
        body: """
        Turning something down is remembered, so a decision made on a train holds at your desk. \
        This list shows only what the current results contain.
        """
    )
```

**What changed and what it claims.** The headlines gain "in these results", which is the scope the
data actually has. The Dismissed body keeps the train sentence — it is the reason anyone trusts
"Not for me" and it is **true about the store** — and adds one sentence saying what the list shows.
The Queued body also loses `"and send it across"`, which is the same false verb as `D-i3-g`; if
`D-i3-g` is accepted, this line has to move with it anyway.

### The honest limit of this fix, stated rather than buried

**Copy alone does not make the surface honest, and this proposal does not pretend it does.** The
empty state only renders when the bucket is *empty*. Dismiss seven things, search something that
matches one of them, and the segment reads `1` with no empty state and no explanation — the count
is still an intersection and still unexplained. Only rendering from the stores fixes that. That is
why the behaviour item is *registered*, not optional.

### Rejected, and why

| Option | Why not |
|---|---|
| **Render the decided buckets from the stores now** | The right end state, and it should be built — but it is a behaviour change to a merged surface that needs a decision about what a store-backed row shows. Taken inside D3 it would be an unspec'd design call on someone else's item |
| **Delete the durability sentence** | The sentence is the reason a user trusts dismissing at all, and the store really is durable. Deleting it understates the product to fix a scoping error |
| **Add a "show everything turned down" control** | New surface, wants a spec, and does not remove the false claim in the meantime |
| **Leave it; the sets are complete on disk** | True of the data and irrelevant to the reader, who is looking at a screen that says a thing they can check and find wrong |

---

## What the owner is being asked

1. **D-i3-g** — accept `"Queue {count} for your Mac"`, or supply the string you want; then the six
   sites and the widened guard move together.
2. **D-i3-h** — accept the two empty states above as an interim, **and** confirm that "render the
   decided buckets from the stores" should be raised as its own item.
