# plan-R2W — the `~/.claude.json` watcher and its adoption protocol

**Spec:** `planning/specs/spec-R2W.md` (child of `planning/specs/spec-R2.md`, W1–W10)
**Branch:** `ai/r2w` **Worktree:** `.worktrees/R2W`
**Tier:** Standard. One new module in `RouterCore`, one CLI verb, one installer edit, three parity
lanes extended.
**Revision:** rewritten after the in-family plan review returned REJECT (2 critical, 3 high,
6 medium, 2 low). The dispositions are in `spec-R2W.md` §Triage; the design changes they forced are
marked **[rev]** below.

## The shape of the change

Everything the watcher needs already exists in `RouterCore` — the JSON layer, `ServerParser`,
`UpstreamHash`, `SelfReference`, `ManifestIO`, `ManifestBookkeeping`, `UpstreamPool`,
`FileModeWriting`. This item adds the *protocol* around them, not a second copy of any of it.

```
app/Sources/RouterCore/Config/ConfigMutationLock.swift     new   the sidecar flock (X1, X2b, X4, X4a)
app/Sources/RouterCore/Config/ConfigEdit.swift             edit  take the lock, 2 000 ms bound (X2, X4a)
app/Sources/RouterCore/Watch/WatchPaths.swift              new   HOME resolution, the paths, the label (X10, X8a)
app/Sources/RouterCore/Watch/WatchState.swift              new   hash + failures + restartPending
app/Sources/RouterCore/Watch/StableHash.swift              new   canonical key-sorted sha256 (W1)
app/Sources/RouterCore/Watch/WatchBackup.swift             new   backup, prune, mode-preserving write (W4)
app/Sources/RouterCore/Watch/WatchIndexing.swift           new   index-before-adopt, fresh manifest (W3, X4b)
app/Sources/RouterCore/Watch/WatchAdoption.swift           new   the merge under the lock (W5, W10, X2a)
app/Sources/RouterCore/Watch/WatchRun.swift                new   the run, top to bottom
app/Sources/RouterCore/Watch/WatchRestart.swift            new   kickstart + restartPending (X6, X7, X8a)
app/Sources/RouterCore/Watch/WatchLog.swift                new   watch.log, the normative strings
app/Sources/MCPRouterCLI/WatchVerb.swift                   new   the verb (X9)
app/Sources/MCPRouterCLI/MCPRouterCLI.swift                edit  dispatch `watch`
docs/install.sh                                            edit  point the watch agent at the binary (X11)
scripts/fixtures/mcp-fixture-server.mjs                    edit  sentinel gate for the D7 lane (X12d)
scripts/acceptance/parity-cli.sh                           edit  cli-watch
scripts/acceptance/parity-divergence.sh                    edit  div-r2-d7
scripts/acceptance/parity-install.sh                       edit  install-launchd-watch
planning/parity/surface.tsv                                edit  three verdicts, only after the lanes report
```

Every file stays under the 400-line cap; `WatchRun` is deliberately split from `WatchAdoption` and
`WatchIndexing` on the two seams that already exist in the reference — decide, index, adopt.

---

## Phase 0 — the lock, first, because everything else writes through it

Built and proven before a line of the watcher exists. If it does not hold, the rest of this item is
a data-loss window with tests around it.

**`ConfigMutationLock.withExclusiveLock(forConfigAt:timeoutMs:body:)`**

- `open("<path>.lock", O_CREAT | O_RDWR | O_CLOEXEC, 0600)`, then `flock(fd, LOCK_EX | LOCK_NB)` in
  a bounded retry loop (2 ms backoff), `flock(fd, LOCK_UN)` and `close(fd)` on every exit path
  including a throw.
- **Sidecar, never `servers.json` itself (X1).** Every writer commits by rename, so the inode under
  a lock taken on the config is the *old* one within microseconds of the first write.
- `O_CLOEXEC` so a spawned MCP child never inherits the descriptor and holds the lock past our own
  exit. The daemon is the real beneficiary: its pool spawns children constantly while `edit` holds
  the lock briefly.
- **[rev] Re-entrancy throws, it does not block (X2b).** A process-wide guarded set of held lock
  paths; a nested acquire throws `LockProblem.reentrant(path:)` immediately. `flock` is per open
  file description, so without this a nested acquire spins the full timeout and then reports that
  *another process* is writing — a false statement about a bug in this one.
- **[rev] Two bounds (X4a).** `ConfigEdit.edit` passes 2 000 ms because it runs synchronously inside
  the daemon's async control handlers and its spin parks a cooperative-pool thread; the watcher
  passes 10 000 ms because nothing is waiting on a one-shot. `MCPR_CONFIG_LOCK_TIMEOUT_MS` overrides
  both.
- Never deletes the lock file. Unlinking it while another process holds a descriptor is how a lock
  stops excluding anything.

**`ConfigEdit.edit`** gains the lock around its existing body (X2) — no required parameter change,
no output change, no error-case change.

**Tests — `ConfigMutationLockTests.swift`, `ConfigEditLockTests.swift`:**

| # | Assertion |
|---|---|
| L1 | two `withExclusiveLock` bodies never overlap — a shared counter proves serialisation, not a sleep |
| L2 | a held lock makes a second acquire fail with `notAcquired` **within** the timeout (`waitUntil`) |
| L3 | **mutation.** A variant locking `servers.json` itself admits a lost update across a rename; the sidecar does not (X1) |
| L4 | a `SIGKILL`ed holder does not block the next acquire — real second process, real signal (X4) |
| L5 | `ConfigEdit.edit`'s bytes, error cases and preserved top-level members are unchanged by the lock |
| L6 | **[rev]** a nested acquire throws `.reentrant` **immediately** — asserted on elapsed time, not only on the error (X2b) |

L3 is the mutation that matters: it is the only test that fails if the lock is put on the wrong
object, and putting it on the wrong object is the mistake this design guards against.

---

## Phase 1 — the pieces the run is assembled from

**`WatchPaths`** — `HOME` from the environment first, `NSHomeDirectory()` as fallback (X10, W-D2);
`claudeJSON`, `statePath`, `logPath`, `backupDir` off `RouterHome`; and **[rev]** `launchdLabel`
from `MCPR_LAUNCHD_LABEL`, defaulting to `gg.rhodes.mcp-router` (X8a). Environment injected, so no
test can reach the developer's own files or the developer's own router.

**`StableHash`** — `stable()` then `JSON.stringify` then sha256-hex, first **32** characters. Reuses
`JSStringify.compact`, the function `UpstreamHash` already trusts for ECMA-compatible output, and
sorts object keys recursively by `JSString` ordering — the UTF-16 code-unit comparison
`Object.keys().sort()` performs. Note the width: 32 here, 16 in `UpstreamHash`; two different
truncations in the reference, and the state file is read back, so getting them the right way round
matters.

**`WatchState`** — `mcpServersHash?`, `failures: [name: {hash, at, error}]`, `restartPending: Bool`
*(new, X7)*. Corrupt file recovers as empty (W8); saved temp-plus-rename, two-space pretty, exempt
from backup by W4.

**`WatchBackup`** — `backup(path)` stamps `<name>.<ISO with : and . replaced by ->` into
`<home>/backups`, prunes to ten by sorted name, never fails the run. `writeAtomic(path:contents:
mode:)` through `FileModeWriting`, reading the destination's current mode first (W4).

**`WatchLog`** — appends `<ISO8601> <msg>\n` to `watch.log`, creating the home; a logging failure is
swallowed (`watch.ts:73-80`). Every string in the spec's copy table is a case on one enum, so they
are asserted as a set rather than scattered as literals.

**Tests:** `StableHashTests` — key order, nesting, arrays, the 32-char width, agreement with a
`node -e` computation of the same input (the reference is the oracle), and **[rev]** `1e400 → null`
and `-0 → 0` (L1). `WatchStateTests` — corrupt → empty, round-trip, unknown keys preserved.
`WatchBackupTests` — mode preserved on a 0644 and a 0600 file, pruning at exactly 10 and 11, atomic
replace.

---

## Phase 2 — indexing before adoption (W3), against a manifest that is never stale

Mirrors `watch.ts:231-257` and `buildManifest`, with one deliberate departure the review forced.

1. Partition candidates into `live` and `backedOff` on the five-minute, hash-sensitive rule.
2. **[rev]** Prune failure records for names no longer staged (`watch.ts:207-209`, M6c).
3. `toIndex` = those `ToolUnion.isStale` says need it.
4. **One** `UpstreamPool` for the whole set — `idleMs 60_000`, the config's `startupTimeoutMs` —
   shut down on every path including a throw (W-D5, W3).
5. Observe each upstream: lease → `listTools()` → `.tools([CachedTool])`, or `.failure(message:)`.
6. **[rev, X4b] Apply each observation to a freshly loaded `manifest.json`**, one at a time, rather
   than to a snapshot taken before indexing. `ManifestBookkeeping.build` is still what applies it —
   called per upstream with `force: true`, since staleness was already decided — so the reference's
   exact `built` and `failed` strings still come from the one function that owns them. This is the
   whole of C2's fix: the window in which a concurrent approval could be erased shrinks from seconds
   to the same microseconds the daemon's own writers already have.
7. **Remove** failed entries from the manifest rather than saving them as indexed (W3), record a
   failure with `now` and `UpstreamHash.hash`, log the `failed to index` line.
8. Clear the failure record for anything that built.

**Tests:** a failed index is not in the manifest and is in `failures`; a re-run inside five minutes
does not spawn; a re-run after an **edit** spawns immediately; a re-run after five minutes spawns;
a current manifest entry is not re-indexed; the pool is shut down when `listTools` throws;
**[rev]** a failure record for a name no longer staged is gone; **[rev, X4b]** an approval written
to `manifest.json` mid-index survives, red-green against a pre-index snapshot.

---

## Phase 3 — the adoption, under the lock (W5, W10, X2a)

The item's centre. The order is chosen so the lock is held for microseconds:

```
read ~/.claude.json                      (no lock)
hash → fast path exit                    (W1)
build candidates                         (W6, W9 — SelfReference(port 8879, X13) + RESERVED + ServerParser)
index the stale ones                     (Phase 2 — SECONDS, no lock held: X3)
┌─ withExclusiveLock(servers.json.lock, 10 000 ms) ──────────────┐
│  re-read servers.json fresh                                     │
│  refuse a flat config, log, write nothing        [rev] X14/W-D7 │
│  merge ONLY our own delta: the adopted names                    │
│  configChanged? → persist restartPending FIRST   [rev] X7/H2    │
│                 → backup + write (prettyTwoSpace + "\n", 0644)  │
└─────────────────────────────────────────────────────────────────┘
restart if owed                          (X6 — before ~/.claude.json is touched at all)
re-read ~/.claude.json, delete only unchanged entries   (W5)
backup + mode-preserving atomic write                   (W4)
seal the hash from what is NOW on disk, iff nothing pending (W7, W8)
```

**[rev] The watcher writes its own bytes (X2a).** It shares the lock with `ConfigEdit.edit`, not the
writer. Three measured reasons, all from C1: `edit` writes unconditionally where the reference
writes only on `configChanged`, which would issue restarts the reference does not; `edit` emits no
trailing newline at mode 0600 where the watcher's reference writes `+ "\n"` at 0644, which
`cli-watch`'s byte diff would fail on; and nesting the two would have the watcher block on its own
lock. The shared thing is the *mutual exclusion*, which is the thing W10 is about.

Two properties fall out of the order and are the ones to test:

- The merge reads `servers.json` **inside** the lock, so a PATCH that landed during the seconds of
  indexing is in the object we merge into rather than the object we overwrite.
- `restartPending` is durable **before** the rename, so no crash window reaches D7's end state.

**Tests — `WatchAdoptionTests.swift`, `WatchCrossProcessTests.swift`:**

| # | Assertion |
|---|---|
| A1 | **W10, two real processes.** A helper PATCHes `servers.json` while the watcher indexes a sentinel-gated child. Afterwards the PATCH **and** the adopted server are both present. |
| A2 | **mutation** for A1: a variant that captures `servers.json` before indexing and writes that object back loses the PATCH. The defect the item exists to prevent, seen to fail. |
| A3 | W5 — an entry edited during indexing is left in `~/.claude.json` and named in `pending` |
| A4 | W5 — an entry deleted during indexing is not resurrected |
| A5 | W7 — after our own write the sealed hash equals the hash of what is on disk, so the next fire takes the fast path |
| A6 | W8 — a pending name withholds the hash; a run with none seals it |
| A7 | W6 — `router`, `mcp-router` and a loopback self-URL on **8879** are never adopted (X13) |
| A8 | W9 — an `http` entry is adopted |
| A9 | W2 — an unparseable initial read writes nothing at all: `servers.json`, `~/.claude.json`, the manifest and the state file are byte-identical afterwards |
| A10 | X3 — the lock is acquirable by another process while a child is being indexed |
| A11 | **[rev]** W1 — a second run over an untouched file writes no file and spawns no child; asserted on mtimes and on a child that would have recorded its own start (M6a) |
| A12 | **[rev]** W8 — a missing `~/.claude.json` and a missing `servers.json` each exit writing nothing, including the state file (M6b) |
| A13 | **[rev]** X14 — a flat `servers.json` is refused, logged, and left byte-identical (L2) |
| A14 | **[rev]** W-D9 — a PATCH that deletes the server being adopted is re-added by the merge. Asserted so the behaviour is defined, with the divergence cited in the test's own comment (M1) |

---

## Phase 4 — the restart (X6, X7, X8a, W-D1)

`WatchRestart`: persist `restartPending`, then run
`/bin/launchctl kickstart -k gui/<getuid()>/<WatchPaths.launchdLabel>` with a 15 s timeout, clear on
success, log the success or the failure string. A run that starts with `restartPending` already set
logs `retrying a restart owed from an earlier fire` and retries before anything else.

**[rev]** The label is `MCPR_LAUNCHD_LABEL`-overridable (X8a). Measured: the real label is loaded
and serving on pid 89259 on this machine, so an un-overridable label would make every lane run
restart the developer's live router.

**Tests:** the D7 scenario — `servers.json` written, then `~/.claude.json` made unparseable before
the re-read — leaves a restart line in `watch.log`; a failing kickstart leaves `restartPending` set
and the next run retries; a successful one clears it; **[rev]** a crash simulated between the state
save and the write leaves the flag set, so the next fire restarts (H2). The kickstart is injected as
a closure in unit tests; the lanes exercise the real binary under a scratch label.

---

## Phase 5 — the verb and the installer

`WatchVerb.run(arguments)` — `--verbose` only, matching `src/index.ts`'s arm; errors reach stderr
through the existing `mcp-router: ` path.

`docs/install.sh`: `program_args()` special-cases `serve` today; it becomes `serve|watch`, and the
comment at :100-107 plus the `say` at :107 are rewritten to state that the Swift watcher exists and
both agents move together. Nothing else in the installer moves.

---

## Phase 6 — the three lanes

Each lane is extended in its own idiom; none gains a new mechanism.

**`parity-cli.sh` → `cli-watch`.** Add `cli/cli-watch` to `OWNED`, then `run_both`-shaped
invocations with a scratch `HOME` per side. **[rev]** The files compared are `servers.json` and the
remaining `~/.claude.json` — **not** the manifest, whose `builtAt` is per-run (X12c, H3).

Scenarios: (1) nothing staged, `--verbose` → the fast-path line; (2) **[rev]** a fixture server
staged **and already present identically in `servers.json`**, so it is indexed, adopted and deleted
from `~/.claude.json` while `configChanged` stays false and neither binary restarts anything
(X12b, H1); (3) an unparseable `~/.claude.json` → both write nothing.

**`parity-divergence.sh` → `div-r2-d7`.** Two-directional, `watch.log` as the oracle. Stage a
server; **[rev]** the fixture child is sentinel-gated, so the lane waits for it to announce itself,
corrupts `~/.claude.json`, then releases it — deterministic, not a sleep race (X12d, M2). Assert the
reference's log carries **no** restart line and the Swift log carries one. **[rev]** The Swift
assertion is *issuance* — either the success or the `could not restart` string — and the Swift side
runs under a scratch `MCPR_LAUNCHD_LABEL`, so the row does not depend on a service being loaded and
does not restart one (X12a, X8a).

**`parity-install.sh` → `install-launchd-watch`.** A second `observe`-shaped function for the watch
agent's different contract: `RunAtLoad` + `WatchPaths`, **no** `KeepAlive`, because it is one-shot.
Four observations per binary: it ran at load; touching the watched file ran it again; it did not
stay resident; which streams carry bytes. Same scratch labels, same bootout-on-every-path cleanup,
and the same seeding as `cli-watch` scenario 2 so no real router is restarted.

**`planning/parity/surface.tsv`** — the three verdicts move to `proven` and the owner to `-`,
**after** the lanes have reported. `parity-manifest-check.sh` is untouched: it derives control and
fixture rows from source, and these are cli/divergence/install rows.

---

## Gates

`make test`, `make lint`, `make parity`, each with its exit code captured on its own line, never
through a pipe. The parity gate is expected to read **72 of 82** and still exit 1.

Mutations that must be proved red then green: **L3** (the lock on the wrong object), **L6** (nested
acquire), **A2** (the stale-object write), and **Phase 2's** pre-index manifest snapshot. Those four
are the item's load-bearing guards, and a test that has never failed is not known to work.

## What this plan deliberately does not do

- **No cutover.** R4-C is a separate item and needs a decision from the owner.
- **No `src/*.ts` change**, so D-i stays open on the TypeScript side, as registered.
- **No reload endpoint.** Refused by the parent's Phase D finding 6.
- **No lock on `manifest.json`'s other writers.** X4c, W-D6, deferred child D-w3.
- **No surface for `watch.log`.** Registered as D-w1.
