Here is the adversarial review of the corrected claims.

---

### Finding 1: The retreat to "sufficient, not exclusive" is an UNDER-CLAIM on the live partition evidence

* **Attacked sentence:**
  > *"What was seen on that machine is consistent with either mechanism, so the deleted row is one sufficient explanation of it rather than the only one."* (Section: *The cause, established before the fix*)
* **Defect:** **UNDER-CLAIMED.**
* **Reason:** The live machine evidence (14 configured upstreams, 13 manifest rows, where the *single* missing row is `namecheap`—the only configured upstream that is also staged in `~/.claude.json`) cannot be produced by R19 alone. R19's clobber window is a race condition between concurrent saves and is completely agnostic to whether an upstream is staged in `~/.claude.json`. R19 cannot deterministically select and erase only staged upstreams across periodic 5-minute watch cycles while leaving unstaged failing upstreams (`lifeline`) intact.
* While R19 is sufficient to explain an isolated transient row loss during concurrent runs, the deletion loop in `cmdWatch` is the **necessary** cause for the persistent 13-of-14 partition and the pre-registered prediction (where staging `lifeline` caused its row to vanish too). Calling the deletion mechanism merely *"one sufficient explanation"* under-claims what the measured partition actually proves.

---

### Finding 2: Swift's immunity to R19's race window is OVER-CLAIMED and internally contradicted

* **Attacked sentence:**
  > *"This type re-reads per entry (X4b above) and so does not have R19's window; that difference is a declared divergence rather than a proven agreement."* ([`WatchIndexing.swift`](file:///app/Sources/RouterCore/Watch/WatchIndexing.swift), comment in `apply`)
* **Defect:** **OVER-CLAIMED / FACTUALLY FALSE.**
* **Reason:** Re-reading the manifest per entry immediately before saving shrinks the race window from seconds to microseconds, but it does **not** eliminate it. Because `manifest.json` has no file lock (unlike config writer's `W11`), any write occurring between Swift's re-read and its save will still be clobbered.
* Furthermore, this directly contradicts [`WatchIndexing.swift`](file:///app/Sources/RouterCore/Watch/WatchIndexing.swift)'s own file header, which explicitly states:
  > *"Re-reading per entry shrinks the window from seconds to the same microseconds the daemon's own manifest writers already have; closing it entirely is deferred child D-w3."*
* Claiming in `apply` that Swift *"does not have R19's window"* is false; Swift has the exact same un-locked read-modify-write window, merely narrower.

---

### Finding 3: Criterion 1's bound ("no surface reads it") is CONTRADICTED by the adoption gate claims

* **Attacked sentence:**
  > *"A server staged in `~/.claude.json` and never adopted into `servers.json` now gets a manifest row, and **no surface reads it**..."* (Section: *Criteria 1 and 2*)
* **Defect:** **INTERNAL CONTRADICTION.**
* **Reason:** The text justifies keeping the error row in [`src/watch.ts`](file:///src/watch.ts) and [`WatchIndexing.swift`](file:///app/Sources/RouterCore/Watch/WatchIndexing.swift) by asserting:
  > *"this watcher's own adoption gate rejects `entry.error` a few blocks down"*
* If the watcher's adoption gate inspects `manifest.servers[name]` (or the indexer's output) to reject adopting a failing staged server into `servers.json`, then the adoption gate **is an operational surface reading that exact row**.
* Either the adoption gate reads the row to block adoption (in which case the claim in Criterion 1 that *"no surface reads it"* is false), or no surface reads it (in which case the claim in [`src/watch.ts`](file:///src/watch.ts) that the adoption gate relies on `entry.error` is false).

---

### Finding 4: The claim that manifest deletion was "the only durable record" is SELF-CONTRADICTING

* **Attacked sentence:**
  > *"What the delete actually did was erase the only durable record that this server had been tried at all."* ([`src/watch.ts`](file:///src/watch.ts), comment block 1; and [`WatchIndexing.swift`](file:///app/Sources/RouterCore/Watch/WatchIndexing.swift))
* **Defect:** **OVER-CLAIMED / CONTRADICTORY.**
* **Reason:** In the very next paragraph of the same comment block in [`src/watch.ts`](file:///src/watch.ts), the text states:
  > *"The reason survived only in watch-state.json, which no surface reads."*
* `watch-state.json` is written to disk and persisted across runs. Therefore, the deleted manifest row was never *"the only durable record that this server had been tried at all"*; it was specifically the only record in `manifest.json`.

---

### Finding 5: R20's assertion that "tool loss is not a regression" is an OVER-CLAIM via false equivalence

* **Attacked sentence:**
  > *"The tool loss is not a regression — the old delete removed the row outright and `unionTools` skips a missing entry exactly as it skips a zero-tool one, so the tools vanished before this change too."* (Section: *R20 — The finding*, and Corrected Acceptance)
* **Defect:** **OVER-CLAIMED.**
* **Reason:** This equates a deleted manifest row with a persistent poisoned row.
* Pre-fix, deleting `next.servers[name]` left the key absent. Subsequent background indexing or manual invocations of `index` on the configured upstream could write a valid entry with tools.
* Post-fix, the failing staged definition writes `{tools: [], error: '...', builtAt: <now>}` and retains it. Readers evaluating staleness (`isStale`) or caching now see a fresh, durable error record for that name. The failure state is pinned in place rather than left open for re-evaluation. Equating active manifest poisoning with an absent key ignores state lifecycle differences across hot reloads.

---

### Finding 6: The scope of the `surface.tsv` BL-2 declaration is UNDER-DECLARED relative to R19's timeline

* **Attacked sentence:**
  > *"It does **not** cover the other four `saveManifest` call sites: `src/index.ts:146` and `:186` on the `index` verb, and `src/control.ts:262` and `:432` on the control API."* (Section: *The third divergence*, and `surface.tsv`)
* **Defect:** **UNDER-DECLARED.**
* **Reason:** Blocker 1 and R19 were demonstrated specifically by racing `index --force` against `watch`.
* If `index --force` calls [`src/index.ts:146`](file:///src/index.ts#L146) or [`:186`](file:///src/index.ts#L186), which carry the un-locked read-then-save window, scoping the parity declaration in `surface.tsv` strictly to `src/watch.ts:285` leaves the exact writer that triggered the blocker undeclared in the parity matrix. Declaring divergence on `watch.ts` while leaving `index.ts` unannotated fails to cover the concrete reproduction path.

---

### The Single Check That Would Most Change Confidence

Run a concurrent test against the **Swift** implementation: hold [`WatchIndexer.apply`](file:///app/Sources/RouterCore/Watch/WatchIndexing.swift) open between its per-entry `manifest.json` re-read and its call to `ManifestIO.save`, while executing `index --force` for a separate upstream.

* **If Swift clobbers the row written by `index --force`:** The claim that Swift *"does not have R19's window"* is broken, and BL-2's declaration scoping must be rejected as insufficient.
* **If Swift preserves both rows:** The claim that per-entry re-reads isolate Swift from R19's failure mode holds under realistic race windows.
