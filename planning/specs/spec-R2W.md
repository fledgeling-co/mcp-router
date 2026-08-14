# R2-W: Swift router — the `~/.claude.json` watcher and its adoption protocol

**ID:** R2W
**Status:** Ready for Implementation Plan
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Parent:** R2 (`planning/specs/spec-R2.md` — the W-clauses)
**Depends on:** R2 (merged), R2-R (merged), R3 (merged)

## Feature description

A child spec. The contract was written at R2's triage and is not being invented here:
`spec-R2.md` §*Watch — specified now, delivered by child spec R2-W* (line 239) states **W1–W10**,
and this spec's acceptance criteria are those clauses with the evidence that settles each one
attached. Where this spec says something the parent did not, it is marked **new**.

The parent's scope note, `spec-R2.md:60`, is the reason it was deferred and the reason it is hard:

> the watcher's central correctness requirement is a **cross-process** one: the watcher and the
> daemon are separate processes, both write `servers.json`, and R3's control-API PATCH writes it
> too. An adoption that reads the config, spends seconds indexing a child, then writes back a stale
> object will erase a concurrent PATCH, and no actor or lock inside one process can fix it.

Two further things the parent registered as this item's:

- **D7 / D-i** — the TypeScript reference carries a latent bug: an adopted server can never reach
  the running router when `~/.claude.json` stops parsing between the initial read and the pre-delete
  re-read. R2-W **must not reproduce it**, and the divergence is declared so R4 reads the difference
  as intended rather than as a regression.
- **`docs/install.sh` installs a second launchd agent** (`gg.rhodes.mcp-router-watch`) that still
  runs `node dist/index.js watch` even when `MCPR_ROUTER_BINARY` is set, because no Swift watcher
  existed to point it at (`docs/install.sh:100-107`). Fixing that is part of this item.

### The three parity rows this unblocks

`planning/parity/surface.tsv` carries three rows whose owner is `R2-W`, and all three are blocked
on this item alone:

| Row | Lane | What the lane must show |
|---|---|---|
| `cli-watch` | `cli` | both binaries run the `watch` verb over identical inputs and agree on stdout, stderr, exit code **and the files they leave behind** |
| `div-r2-d7` | `divergence` | D7 asserted **in both directions** — the reference loses the restart, the Swift watcher does not |
| `install-launchd-watch` | `install` | the watch agent's supervision contract exercised under real launchd, once per binary |

The gate reads **69 of 82** before this item. It is expected to read **72 of 82** after, and to
still exit 1: the remaining 10 belong to D-j, D-k, D-l, D-m and R4-C.

---

## What this item is really for

Every other item in the router port moves bytes the user asked for. This one moves a file the user
did not ask it to touch — `~/.claude.json` holds live session state for every project on the
machine, is ~268 KB, and is rewritten constantly by Claude Code. The reference's header says the
design is shaped by two facts, and both survive the port unchanged: the common case must be a read,
a hash and an exit; and a write must be backed up, atomic, and abandoned rather than derived from a
parse that failed.

What does **not** survive unchanged is the concurrency story. In Node the watcher is the only writer
of `servers.json` that anyone worried about, because the reference's control API and its watcher are
rarely both mutating. In the Swift product they are three writers — the watcher, R3's control API
inside the daemon, and the Mac app driving that control API — and R3 has already shipped
`ConfigEdit.edit`, a read-modify-write with **no lock at all** (`ConfigEdit.swift:38-95`). The
daemon's window is microseconds; the watcher's, because it spawns and indexes a child first, is
**seconds**. A protocol has to exist, and W10 is where this spec earns its separate existence.

---

## Acceptance criteria

The oracle. Each clause names the evidence that settles it. **X0** is what stops the rest being
stub-satisfiable, and is the parent's E0 restated for this item's resources.

- **X0** *(new)* — Every clause is discharged against **real OS resources**: a real
  `~/.claude.json` on disk under a scratch `HOME`, a real spawned child for the indexing clauses,
  two real concurrent processes for the cross-process clauses, and the built `MCPRouterCLI`
  executable for the verb and parity clauses. No clause may be discharged by a double standing in
  for the thing under test. The completion note records the evidence type per clause.

### W1–W9 — ported from the reference, verbatim in behaviour

- **W1** — Fast path: an unchanged `mcpServers` hash means a read, a hash and an exit — nothing
  spawned, nothing written. Hashing canonicalises object-key order.
  *Evidence:* a second run over an untouched file writes no file and starts no process; asserted on
  file mtimes and on the absence of a child.
- **W2** — A `~/.claude.json` that does not parse **on the initial read** abandons the run and
  writes nothing. Deliberately narrower than "any parse failure" — see W-D1.
- **W3** — A server is indexed **before** adoption. A failure is retried only after a five-minute,
  **hash-sensitive** backoff — an edited definition retries immediately. Manifest entries that are
  current are not re-indexed, failed entries are **removed** rather than cached as indexed, and the
  temporary indexing pool is always shut down.
- **W4** — Every write **to `~/.claude.json` or `servers.json`** is preceded by a backup and
  performed temp-plus-rename; `~/.claude.json`'s file mode is preserved; backups are pruned to ten.
  Watcher state is exempt — it is derived and recoverable.
- **W5** — `~/.claude.json` is re-read immediately before the delete, and an entry that changed
  while it was being indexed is left in place.
- **W6** — Reserved names and the router's own self-reference are never adopted. Reuses
  `SelfReference.isSelfReference` rather than a second implementation.
- **W7** — The state hash is taken **after** our own write, so the fire our write triggers takes the
  fast path.
- **W8** — Anything still pending withholds the state hash so the next fire retries. A missing input
  or missing router config likewise exits without sealing the hash. Corrupt watcher state recovers
  as empty state.
- **W9** — Adoption covers **every parseable transport**, not only stdio: `candidateOf` applies no
  stdio filter. The brief's "new stdio entries" describes the common case, not the contract.

### W10 — the cross-process mutation protocol

The parent left the choice open between a file lock plus re-read-and-merge, a content-hash CAS, and
routing adoption through the daemon. **This spec chooses the file lock plus re-read-and-merge**, and
states it as clauses so the choice is testable rather than described.

- **W10** — Adoption must not erase a concurrent control-API PATCH of `servers.json`.
  *Evidence:* an unrelated PATCH issued **while an adoption is indexing** survives the adoption, and
  the adopted server is present too. Both processes real, both writes real.
- **X1** *(new)* — The lock object is a **sidecar** file, `servers.json.lock`, not `servers.json`
  itself. Every writer commits by temp-plus-rename, which replaces the inode; a lock taken on the
  original inode would not exclude a writer holding the replacement, so locking the file being
  replaced is the one implementation of this that looks right and is not.
  *Evidence:* red-green — a variant locking `servers.json` itself admits a lost update; the sidecar
  does not.
- **X2** *(new)* — `ConfigEdit.edit` — the daemon's and the Mac app's only path into `servers.json`
  — takes the same lock across its whole read-modify-write. A lock only the watcher takes excludes
  nothing. The change is additive: single-process behaviour, byte output and error cases are
  unchanged.
- **X2a** *(new, from review C1)* — The watcher **shares the lock, not the writer**. It does not
  route its own write through `ConfigEdit.edit`, for three measured reasons: `edit` writes
  unconditionally where the reference writes only when `configChanged` (`watch.ts:279`), which would
  issue a restart the reference does not; `edit` emits no trailing newline at mode `0600`
  (`ConfigEdit.swift:87-91`) where the watcher's reference writes `JSON.stringify(…, null, 2) + "\n"`
  at `0644` (`watch.ts:282`), which `cli-watch`'s byte diff would fail on; and nesting the two would
  have the watcher's own `edit` call block on the watcher's own outer lock.
- **X2b** *(new, from review C1)* — A **re-entrant acquire throws** `LockProblem.reentrant` rather
  than blocking. `flock` is per open file description, so a second `open` in the same process
  deadlocks against the first for the whole timeout and then fails with a message about *another*
  process. Turning that into an immediate, named programming error is the difference between a bug
  found at compile-adjacent time and one found as a ten-second stall in production.
- **X3** *(new)* — The watcher holds the lock **only** for its read-merge-write, never across
  indexing. Indexing spawns a child and can take seconds; a lock held across it would convert a lost
  update into a stalled control API, which is worse and harder to see.
  *Evidence:* the lock is observably free while a child is being indexed.
- **X4** *(new)* — Lock acquisition is **bounded**. A wait that cannot be satisfied within the
  caller's timeout fails the run with a stated reason and writes nothing, rather than blocking a
  launchd job forever. A stale lock file left by a killed process does not deadlock the next run —
  `flock(2)` is released by the kernel on close, including on crash.
  *Evidence:* a held lock makes a second writer fail with the timeout message inside the bound, and
  a `SIGKILL`ed lock holder does not block the next acquire.
- **X4a** *(new, from review M3)* — The two callers get **different bounds**, because they are
  different kinds of process. `ConfigEdit.edit` runs synchronously inside the daemon's async control
  handlers, so its spin parks a cooperative-pool thread: its default is **2 000 ms**, chosen so a
  contended PATCH fails fast and visibly rather than stalling the control API. The watcher is a
  one-shot with nothing waiting on it: **10 000 ms**. Both are overridable by
  `MCPR_CONFIG_LOCK_TIMEOUT_MS`.

### The second contended file — `manifest.json`

- **X4b** *(new, from review C2)* — The watcher **never holds a `manifest.json` snapshot across
  indexing**. The reference loads the manifest at `watch.ts:212`, spends seconds spawning and
  indexing children, and saves at `:253` — and the daemon writes the same file throughout
  (`ServicePorts.swift:341`, `AuthRoutes.swift:120`, `control.ts:195,361`). A user approving a held
  tool-change in the Mac app mid-adoption would have that approval erased. This is W10's own
  argument applied to the file the parent's clause did not name.
  *Evidence:* an approval written to `manifest.json` while an adoption is indexing is still there
  afterwards, and the newly indexed entry is there too. Red-green against a variant that saves a
  pre-index snapshot.
- **X4c** *(new)* — What X4b does **not** claim: `manifest.json` writes are still unlocked, so the
  microsecond-wide window between the daemon's own writers is unchanged by this item. Closing that
  means every manifest writer taking a lock, which reaches R3 and R5 code this item does not own. It
  is registered as deferred child **D-w3** and declared as **W-D6**, not left for R4 to find.

- **X5** *(new)* — The protocol's residual is **declared, not hidden**: `flock` is advisory, and the
  TypeScript router does not take it. Only one watcher is installed at a time
  (`docs/install.sh:154`), so this is a statement about the migration window, not a live hole. It is
  recorded as divergence **W-D4** and as a note on the `div-r2-d7` row's neighbours, not left for
  R4 to discover.

### W-D1 — D7, and how this item diverges from it

- **X6** *(new)* — The restart is issued **as soon as `servers.json` has been written**, before
  `~/.claude.json` is touched at all. No later early return can skip it, which is precisely the
  reference's failure (`watch.ts:285-300` returns at 299, past the `restartRouter()` at 336).
- **X7** *(new)* — A restart that fails is **owed, not lost**: watcher state carries
  `restartPending`, **persisted before the `servers.json` write** and cleared only after a
  successful `launchctl kickstart`. Any later fire that sees it retries. The order matters and the
  review found it: setting the flag *after* the write leaves a `SIGKILL` between the rename and the
  state save reproducing D7's exact end state — the next fire finds the entry already present,
  writes nothing, owes nothing, and seals the hash. Persisting first costs at most one restart that
  was not needed, which is the cheap side of that trade.
- **X7a** *(new, from review M5)* — The reference's own `saveState` writes `{mcpServersHash,
  failures}` with no spread (`watch.ts:342`), so a single TypeScript run on a machine switching back
  **erases** `restartPending`. Declared as part of **W-D4**; it is a migration-window statement, not
  a live hole.
- **X8** *(new)* — The mechanism stays `launchctl kickstart -k gui/<uid>/<label>`. A reload endpoint
  would be better engineering and is **refused**: the parent's Phase D finding 6 rejected it as
  inventing behaviour R4 diffs against, and nothing here changes that.
- **X8a** *(new, from review H1)* — The label is `gg.rhodes.mcp-router` by default and overridable
  by `MCPR_LAUNCHD_LABEL`. This is a safety requirement, not a convenience. Measured on this machine,
  2026-08-15: `gg.rhodes.mcp-router` is loaded and serving on **pid 89259**. Without the override,
  every lane run that adopts a server would `kickstart -k` the developer's **live** router, dropping
  its in-flight calls — a test whose cost is the thing under test. The reference has no such
  override, so the lanes are additionally arranged (X12b) so the reference is never driven down a
  path that restarts anything.
- **X13** *(new, from review M4)* — The port handed to `SelfReference.isSelfReference` is the
  literal **8879**, not the configured port. `watch.ts:182` hardcodes `const routerPort = 8879`, so
  reading the real port would make Swift skip a self-URL on a non-default port that the reference
  adopts. It looks like a bug and is parity; it is written down here so no later runner "fixes" it.
- **X14** *(new, from review L2)* — A **flat `servers.json`** — one whose servers sit at the top
  level with no `mcpServers` object — is **refused**, logged, and left untouched. The reference's
  `routerCfg.mcpServers ?? {}` (`watch.ts:203`) creates an empty object over it and writes back,
  discarding every server the file declared: R1's D1, reached through the watcher. Reproducing a
  destructive bug is not parity worth having. Declared as **W-D7**.

### The verb, the installer, and the lanes

- **X9** *(new)* — `mcp-router watch` exists on the Swift CLI, with the reference's `--verbose` arm,
  the reference's stdout text, the reference's exit code, and the reference's silence otherwise.
- **X10** *(new)* — `~/.claude.json` is resolved from **`HOME` in the environment**, falling back to
  `NSHomeDirectory()`. Measured on this machine, 2026-08-15: under `HOME=/tmp/fakehome`, node's
  `os.homedir()` returns `/tmp/fakehome` and Swift's `NSHomeDirectory()` returns
  `/Users/lukerhodes`. Reproducing the reference requires the environment; and a watcher that
  ignored `HOME` would, the first time the parity lane ran it, adopt and delete servers out of the
  **developer's own** `~/.claude.json`. This clause is a safety property as much as a parity one.
- **X11** *(new)* — `docs/install.sh` points the `watch` agent at `MCPR_ROUTER_BINARY` when it is
  set, alongside the `serve` agent, and its comment states what is now true instead of what was.
- **X12** *(new)* — The three parity rows are unblocked by lanes that **compare**, never by a
  manifest edit. Each row's `verdict` moves to `proven` only because a lane reported it; the
  reconciliation is against the manifest, so a row nobody measured stays blocked.
- **X12a** *(new, from review H1)* — `div-r2-d7`'s oracle is **that a restart was issued**, which is
  either the success line or the `could not restart` line. Asserting the success line would make the
  row pass only on a machine where the label happens to be loaded, and pass *by restarting a real
  service*. Issuance is the behaviour D7 is about; whether launchd then obliges is not.
- **X12b** *(new, from review H1)* — No lane scenario drives **the reference** down a restarting
  path. Two arrangements do it: `cli-watch`'s adoption scenario pre-seeds `servers.json` with the
  same definition that is staged, so the entry is indexed, adopted and deleted from `~/.claude.json`
  while `configChanged` stays false on both sides (`watch.ts:273`); and in `div-r2-d7` the reference
  reaches its early return, which is the divergence itself. The Swift side, which does restart in
  the second case, runs under a scratch `MCPR_LAUNCHD_LABEL`.
- **X12c** *(new, from review H3)* — `cli-watch` diffs `servers.json` and the remaining
  `~/.claude.json`, and **not** `manifest.json`. Manifest entries carry `builtAt` at millisecond
  resolution (`ManifestBookkeeping.swift:51`) and failure records carry an epoch, so two binaries run
  in sequence cannot produce equal bytes; normalising them away would mean adding a time normaliser
  to a lane whose header says nothing but coordinates are normalised. Manifest parity is the fixture
  and state lanes', and is already proven there.
- **X12d** *(new, from review M2)* — `div-r2-d7` corrupts `~/.claude.json` **deterministically**,
  not on a timer. The fixture child is gated on a sentinel file: the lane waits for the child to
  announce it has started, corrupts the config, then releases the child. A `sleep` racing an index
  that may finish first would fail the lane in the wrong direction and read as a Swift defect.

### Standing constraints

- **S1** — Extends `RouterCore` and `MCPRouterCLI`. No new package dependency; the `0.12.1` SDK pin
  and the swift-nio pin are unchanged.
- **S2** — Swift 6 language mode, strict concurrency, no `@unchecked Sendable`.
- **S3** — Neither app target links `RouterCore`.
- **S4** — `src/*.ts` untouched. The TypeScript watcher keeps running and keeps adopting until R4-C.
  `docs/install.sh` **is** touched, by X11 — the parent's S5 froze it while no Swift watcher existed,
  and this item is the thing that condition was waiting for.
- **S5** — No file over 400 lines; no lint limit raised.

---

## Declared divergences from the TypeScript reference

R4 must not read any of these as a regression.

| # | Divergence | Why | R4 impact |
|---|---|---|---|
| **W-D1** | **The restart is never lost.** Issued immediately after the `servers.json` write, and owed in watcher state until it succeeds. | `watch.ts:285-300` returns before line 336's `restartRouter()` when the pre-delete re-read fails, having already written `servers.json`; the next fire sees `configChanged === false` and never restarts. Declared as D7 by the parent and registered as deferred child **D-i** for the TypeScript side. | This is the `div-r2-d7` row. Asserted in **both** directions: the reference logs no restart line in the D7 scenario, the Swift watcher logs one. |
| **W-D2** | **`~/.claude.json` is resolved from `HOME`**, not from `NSHomeDirectory()`. | Measured: `NSHomeDirectory()` ignores `$HOME`, `os.homedir()` honours it. Matching the reference *requires* reading the environment. | Parity-**restoring**, not a difference. Recorded because the mechanism differs even though the behaviour agrees. |
| **W-D3** | **`servers.json` writes take an advisory `flock` on `servers.json.lock`.** The reference takes no lock anywhere. | W10. Without it a seconds-long adoption erases a concurrent PATCH. | A file the reference never creates appears in the router home. It is a lock, holds no data, and is never read. |
| **W-D4** | **The lock is advisory and the TypeScript router does not take it**, and a TypeScript run erases `restartPending` (`watch.ts:342` saves without a spread). | `flock` is advisory by definition, and modifying `src/*.ts` is refused by S4. | Only one watcher is installed at a time, so the two never race in a supported configuration. Stated so R4 does not read the asymmetry as an unexplained gap. |
| **W-D5** | The watcher's temporary indexing pool is constructed **once for the whole stale set**, matching `watch.ts:232-236`, rather than per upstream as `ManifestIndexer` does. | The reference's shape; and `ManifestBookkeeping.build` already produces the reference's `built`/`failed` strings from an observation set, so reusing it is both closer and less code. | None observable. Recorded because it differs from the Swift `index` verb's own path. |
| **W-D6** | **`manifest.json` is written per upstream from a freshly loaded copy**, where the reference loads once, indexes for seconds, and saves the stale object (`watch.ts:212,253`). | The reference erases a concurrent approval; X4b refuses to. The residual microsecond window between the daemon's own manifest writers is unchanged and is deferred child **D-w3**. | The file's *content* agrees; the number of writes differs. Nothing compares write counts. |
| **W-D7** | **A flat `servers.json` is refused**, where the reference creates an `mcpServers` object over it and discards every server it declared (`watch.ts:203`). | R1's D1, reached through the watcher rather than through the control API. Reproducing a data-loss bug is not parity worth having. | The same divergence R1 already declared for the config reader and R3 for the control API's writer; this extends it to the third writer. |
| **W-D8** | **`MCPR_LAUNCHD_LABEL` overrides the restart target.** The reference hardcodes `gg.rhodes.mcp-router` (`watch.ts:49`). | X8a: measured, that label is loaded and serving on this machine, so an un-overridable label makes every lane run bounce the developer's live router. | The default is the reference's value, so an un-set environment behaves identically. |
| **W-D9** | **The lock serialises writes; it does not arbitrate intent.** A PATCH that *deletes or edits the very server being adopted*, landing during indexing, is overwritten by the merge: the watcher re-adds its own version and then deletes the entry from `~/.claude.json`, so the user's deletion reverses with no trace in the file they touched. | The staged entry is also fresh user intent, and the watcher cannot tell "deleted deliberately" from "not yet adopted". W10's evidence clause says an *unrelated* PATCH, and this is the case that wording does not cover. | Behaviour is defined and asserted rather than accidental. Not a regression against the reference, which loses the PATCH entirely. |
| **W-D10** | **The watcher-state bytes differ on three paths the reference reaches too**, with the same retry semantics: a failed pre-delete re-read nils `mcpServersHash` where the reference preserves the stale value (`watch.ts:298` spreads `...state`); a non-object root at that re-read withholds the hash where the reference would seal the hash of `{}`; and `WatchState` drops top-level keys it does not model, where the reference's spread preserves them. | Found by the Phase D critic. Each is a *file* difference rather than a behaviour difference — every one of them produces the same next fire — and `watch-state.json` is derived and recoverable (W4 exempts it). | `watch-state.json` is compared by no lane, deliberately: it is per-run state, not a wire surface. Declared so the difference is not discovered later and read as drift. |
| **W-D11** | **A filesystem with no advisory locking is written unlocked** rather than refused. `flock` answering `ENOTSUP`, `EOPNOTSUPP` or `EINVAL` proceeds to the body. | Refusing would turn a control-API PATCH that worked before this item into one that fails, on a mount that never had exclusion to lose. Degrading to the status quo ante is the smaller harm, and `ConfigEdit.edit`'s "error cases unchanged" claim is only true with this branch present. | No lane reaches such a filesystem. Declared because the alternative — a PATCH that fails on a network home directory — is exactly the kind of regression R4 would attribute to the port. |

---

## Design representation — 2026-08-15

**R2-W renders nothing.** It is a launchd-triggered one-shot CLI verb with no view, no surface and
no interaction. Inventing screens for it would be fabrication, and `DESIGN.md` §5's nine states have
no subject here. Scaled honestly, the design stage covers the two things this item genuinely owns:
the **words** it emits (§6), and the **state a later surface can tell apart** because of them.

`watch.log` is not decoration. It is the only account of a process that runs unattended, mutates the
user's own config, and is invisible when it works. `DESIGN.md` §6 — say what happened and what to do,
next to the thing that failed, blame nobody — applies to a log line read at 2am exactly as it applies
to a banner.

### The copy — normative

Carried **verbatim** from the reference unless marked. A rewording would make R4 report a difference
that is only a rewording, so these are asserted by the watcher's tests and by the `cli-watch` lane.

| Condition | Copy | |
|---|---|---|
| Initial read did not parse | `~/.claude.json did not parse (<message>); abandoned, nothing written` | verbatim |
| Entry rejected by the parser | `skipped "<name>": <reason>` | verbatim |
| No router config | `no router config at <path>; adoption skipped` | verbatim |
| Index failed | `failed to index "<name>: <error>"; left in ~/.claude.json, will retry` | verbatim |
| Adopted | `adopted <name> (<n> tools) from ~/.claude.json` | verbatim |
| Adopted, surface held | `adopted <name> (<n> change(s) held for approval) from ~/.claude.json` | verbatim |
| Re-read did not parse | `indexed <names> but ~/.claude.json no longer parses (<message>); left it untouched, will retry` | verbatim |
| Edited while indexing | `"<name>" changed in ~/.claude.json while it was being indexed; left it there for the next fire` | verbatim |
| Removed from staging | `removed <n> adopted stdio entr(y\|ies) from ~/.claude.json: <names>` | verbatim |
| Still pending | `still pending (not adopted): <names>` | verbatim |
| Restart issued | `restarted gg.rhodes.mcp-router to pick up the new upstream` | verbatim |
| Restart failed | `could not restart gg.rhodes.mcp-router (<message>); run it manually` | verbatim |
| `--verbose`, fast path (stdout) | `mcpServers unchanged; nothing to do` | verbatim |
| `--verbose`, nothing to adopt (stdout) | `no entries to adopt` | verbatim |
| Lock not acquired | `could not lock <path> within <n>ms; another process is writing it. Nothing was changed.` | new — R2-W owns it |
| Restart owed from an earlier fire | `retrying a restart owed from an earlier fire` | new — R2-W owns it |
| Flat router config (W-D7) | `<path> has no "mcpServers" object, so adopting into it would overwrite the servers already there. Nothing was changed.` | new — R2-W owns it |

The three new strings are new because the reference has no analogue: it never locks, never owes a
restart, and writes over a flat config rather than refusing it. Each says what happened and what
follows, and none blames the user.

### Which `DESIGN.md` §5 state this item feeds

| State | What R2-W supplies | Surfaced by |
|---|---|---|
| Default | a newly adopted server appears in `servers.json` and in the manifest, so it is an ordinary row | M3 |
| Partial | a server indexed but held for approval — adopted, with its changed tools withheld | M3, M8 |
| Error | a server that failed to index is **left in `~/.claude.json`** and named in `watch.log`, rather than adopted into a list that cannot serve it | — the log only; no surface reads `watch.log` today |
| Empty · Loading · Offline · Success · Disabled · Overflow | — not this item | — |

The Error row is the honest one: nothing renders `watch.log`, so a server that keeps failing to
index is invisible in the product. That is a real gap, it is not this item's to close, and it is
registered below as deferred child **D-w1** rather than left unsaid.

---

## Triage — 2026-08-15

**Ready for Implementation Plan.**

### Out-of-family spec/plan review — unavailable, downgraded in-family

The codex out-of-family lane is **account-limited**. Measured rather than assumed, 2026-08-15:

```
codex exec -m gpt-5.6-sol -c model_reasoning_effort=high -s read-only -o /tmp/r2w-codex-probe.md
  → exit 1, "You've hit your usage limit … try again at Aug 20th, 2026 1:29 PM", no -o file written
```

Logged as `codex: usage limit -> claude (downgrade)`. The review below is in-family
(`claude-fable-5`, effort `high`), and is a **logged downgrade carried into the pre-merge
evidence** — not a pass, and not a reason to have skipped the review.

**Verdict on the first draft: REJECT** — 2 critical, 3 high, 6 medium, 2 low. Report at
`/tmp/r2w-plan-review.md`. Every finding is dispositioned; none is silent. The spec and plan above
are the rewrite.

| # | Finding | Disposition |
|---|---|---|
| **C1** | Phase 3 contradicted itself three ways by routing the watcher's write through `ConfigEdit.edit`: `flock` is per open file description so the nested acquire self-deadlocks; `edit` writes unconditionally where the reference writes only on `configChanged`, which would issue a restart the reference does not; and `edit`'s bytes (no trailing newline, mode 0600) are the control API's shape, not the watcher's (`+ "\n"`, 0644), which `cli-watch`'s byte diff would fail on. | **Accepted, all three.** X2a: the watcher shares the **lock**, not the writer, and owns its own `configChanged` test and byte shape. X2b: a re-entrant acquire now throws rather than stalling for the timeout and then blaming another process. |
| **C2** | `manifest.json` has the identical seconds-wide window and was outside the protocol entirely — an approval made in the Mac app mid-adoption would be erased by the watcher's post-index save of its stale snapshot. W10's own argument, applied to the file the parent's clause did not name. | **Accepted.** X4b: no manifest snapshot is held across indexing; each entry is applied to a freshly loaded manifest. X4c + W-D6 declare the residual microsecond window the daemon's own writers already have, and register **D-w3** to close it across R3 and R5. |
| **H1** | The hardcoded `launchctl kickstart` label means every lane run restarts the developer's real router, and makes the D7 oracle environment-dependent. | **Accepted, and it was worse than stated.** Measured: `gg.rhodes.mcp-router` is loaded and serving on pid 89259 on this machine. X8a adds `MCPR_LAUNCHD_LABEL`; X12a redefines the oracle as *issuance*, either string; X12b arranges both lanes so the reference is never driven down a restarting path at all. |
| **H2** | Setting `restartPending` after the write leaves a `SIGKILL` between rename and state save reproducing D7's end state with no retry. | **Accepted.** X7 persists the flag **before** the write. The cost is at most one unnecessary restart. |
| **H3** | `cli-watch` cannot diff `manifest.json`: `builtAt` is per-run and the lane's header forbids adding a time normaliser silently. | **Accepted.** X12c drops the manifest from the diff and says why; manifest parity stays the fixture and state lanes'. |
| **M1** | The lock cannot arbitrate intent: a PATCH deleting the very server being adopted is reversed by the merge. W10's "unrelated PATCH" wording dodges it. | **Accepted as a declared residual**, W-D9, and asserted so the behaviour is defined rather than accidental. |
| **M2** | `div-r2-d7`'s sleep-then-corrupt is a wall-clock race that fails in the wrong direction when the index wins. | **Accepted.** X12d: sentinel-gated fixture child. |
| **M3** | The bounded spin parks a Swift-concurrency pool thread for up to 10 s inside the daemon's synchronous `ConfigEdit.edit`. | **Accepted.** X4a splits the bound: 2 000 ms for the daemon, 10 000 ms for the one-shot watcher. |
| **M4** | The reference hardcodes `routerPort = 8879` for the self-reference check; reading the real port would be an undeclared divergence. | **Accepted.** X13 writes it down so it is not "fixed" later. |
| **M5** | A TypeScript run erases `restartPending`, because `saveState` writes without a spread. | **Accepted** into W-D4 as a migration-window residual. |
| **M6** | W1's mtime/no-child evidence, W8's missing-input and missing-router-config exits, and the reference's pruning of failure records for names no longer staged had no test. | **Accepted.** All three are in the plan's test tables. |
| **L1** | `StableHashTests` should cover `1e400 → null` and `-0 → 0`. | **Accepted**, both added. The reviewer's own note that the scarier unicode cases dissolve — `JSString` holds raw UTF-16 units — was verified against `JSString.swift` before accepting it. |
| **L2** | A flat `servers.json` diverges silently on the watcher path. | **Accepted and made explicit.** X14 + W-D7: refused, logged, nothing written — the reference's behaviour there is R1's D1 data loss. |

**Rejected: none.** Two claims were checked first-hand before acceptance rather than taken on
trust: the launchd label really is loaded and serving (H1), and `flock`'s per-description semantics
really do make the nested acquire block (C1).

### Phase D completeness critic — in-family (logged downgrade), verdict ACCEPT

Same measured codex unavailability, same `codex: usage limit -> claude (downgrade)` line. Report at
`/tmp/r2w-phased.md`. **No critical and no high finding.** The critic executed the suites itself
(33 tests, 6 suites) and looked specifically for a path that could damage a real machine, finding
none. Every finding is dispositioned; four changed code.

| Severity | Finding | Disposition |
|---|---|---|
| medium | An unparseable `servers.json` was discovered only at the merge, so the Swift watcher spawned and tore down real children the reference never spawns (`watch.ts:200` parses first). | **Fixed.** `requireParseableRouterConfig()` runs before any indexing, with `unparseableRouterConfigSpawnsNothing` asserting no child started — proved red by removing the guard. |
| medium | `still pending (not adopted)` was logged on *every* pending path; the reference logs it only in the adopted-something branch (`watch.ts:346` vs `:352-355`). | **Fixed.** `sealOrWithhold` takes `announcing:`, and the no-adoption path passes `false`. |
| medium | `WatchAdoption`'s header claimed `cli-watch` diffs the written `servers.json` bytes. Under X12b no lane scenario ever writes that file, so the check named cannot run. | **Fixed — the comment was wrong, not the code.** It now names the checks that do prove it (`modesAreHonoured`, `JSStringify`'s parity suite) and says why the lane structurally cannot. |
| medium | The re-entrancy guard was keyed by the path as spelled, so two spellings of one file defeat it; and on a filesystem without advisory locking, `ConfigEdit.edit` would newly fail where R3 worked. | **Both fixed.** `lockPath` standardises the path before keying; `ENOTSUP`/`EOPNOTSUPP`/`EINVAL` proceed unlocked, declared as **W-D11**. |
| low | The plan promised a red half for X4b's manifest guard. | **Already done, invisible to the critic.** Mutation 2 in `planning/evidence/R2W-acceptance.md` is exactly that: a pre-index manifest snapshot, proved red (`approvedByTheUser → nil`), then restored. |
| low | `kept.last?.hasSuffix("-011Z") == true \|\| kept.last != nil` is a tautology. | **Fixed.** Both ends of the pruned list are now asserted by exact name. |
| low | Three watcher-state byte differences from the reference, all with identical retry semantics. | **Declared as W-D10** rather than changed: matching the bytes would mean modelling keys this watcher does not use. |
| low, favourable | Swift catches an after-hash re-read failure that `watch.ts:340` leaves unprotected. | **Declared in W-D10's neighbourhood.** A robustness improvement, recorded so it is not read as drift. |
| low, process | `spec-R2W.md` and `plan-R2W.md` are in the main tree, not on the branch; `dist/` sits untracked in the worktree. | **Correct as-is for the first** — the pipeline keeps docs in the main working tree and code on the branch. The `dist` symlink was scaffolding for the parity lanes and is removed before the commit. |

### Assumptions carried forward

1. **The file lock is the protocol**, not a CAS and not routing adoption through the daemon. A CAS
   needs a retry loop whose failure mode under contention is a livelock, and routing through the
   daemon makes adoption impossible while the daemon is down — which is exactly when a machine is
   being set up. The lock is the option W10 lists first, and it is the one that leaves the watcher
   able to work alone.
2. **`ConfigEdit.edit` is modified.** It is R3's merged code and this is the only way X2 can hold.
   The change wraps the existing body; it adds no parameter callers must pass and changes no output.
3. **The restart mechanism stays `launchctl kickstart`.** Settled by the parent's Phase D finding 6.

### Deferred children discovered

Reported to the orchestrator, not registered here.

| Suggested id | Title | Deps | Why |
|---|---|---|---|
| **D-w1** | Surface a server that keeps failing to index | M3 | Nothing in the product reads `watch.log`; a server that fails adoption three days running is invisible |
| **D-w2** | `ImportVerb` resolves `~/.claude.json` from `NSHomeDirectory()`, not `HOME` | R4 | `ImportVerb.swift:22` — the same defect W-D2 fixes in the watcher, still present in `import`. Not reached by `cli-import`, which passes `--from` |
| **D-w3** | Take the config mutation lock across **every** `manifest.json` writer | R3, R5 | X4c / W-D6 — this item removes the watcher's seconds-wide window, but `ServicePorts.swift:341` and `AuthRoutes.swift:120` still race each other on a microsecond one |
