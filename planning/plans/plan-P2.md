# plan-P2 — implementation plan

Spec: `planning/specs/spec-P2.md`. Branch `ai/p2`, worktree `.worktrees/P2`.
Baseline **73 of 83 proven, 9 blocked, 1 DIVERGED, gate exit 1**, from `.worktrees/P2`.

**Revision 2** — amended after a grok plan review returned AMEND with 21 findings, all accepted.
§9 carries the disposition. Two were safety catches: the `div-r1-d3` lane as first drafted would
have written the developer's real `~/.claude/mcp-router/servers.json`, and the lock test as first
drafted could not redden its own mutation.

---

## 0. The constraint that shapes the file layout

**`MCPRouterCLI` is an executable target with no test target.** `app/Tests/` holds
`RouterCoreTests`, `MCPRouterKitTests`, `MCPRouterUITests` and nothing else. Logic placed in
`app/Sources/MCPRouterCLI/` is **unreachable by `swift test`**.

`WatchVerb.swift` is 16 lines calling `RouterCore/Watch/`. P2 follows it: **logic in `RouterCore`,
verbs are shims.** Any behaviour an acceptance criterion names must therefore sit in `RouterCore`,
including the home-pairing rule — which is why A1 below extracts a type rather than leaving the
pairing as two lines inside the verb where nothing can test it.

---

## 1. Phase A — one home, one rule (S1)

### A1 · `ImportPaths` — new, `app/Sources/RouterCore/Config/ImportPaths.swift`

```swift
public struct ImportPaths: Sendable {
    public let claudeJSON: String
    public let routerHome: RouterHome
    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                homeDirectory: String = NSHomeDirectory())
}
```

Resolves `HOME` **once** (rejecting empty, falling back to `homeDirectory`) and derives both from
that one string — the rule and the invariant `WatchPaths.swift:5-21` already record for the watcher.

A type rather than two lines in `ImportVerb`, because A2.2 is the *pairing* and the pairing has to
be somewhere `swift test` can reach. Testing `RouterHome(homeDirectory: alreadyResolved)` would
assert that `RouterHome.init` does what it already does — identity, and green against the mutation
it is supposed to catch.

The resolution rule itself moves to `RouterHome.resolvedHomeDirectory(environment:homeDirectory:)`,
and **`WatchPaths.init:42` is changed to call it** so there is one implementation, not two.
Behaviour identical; R2-W's existing `WatchPaths` tests are the guard and must stay green
**unedited**. If one needs editing the refactor is wrong and gets reverted.

### A2 · `ImportVerb` uses it

```swift
let paths = ImportPaths()
let from = options.value("from") ?? paths.claudeJSON
let home = paths.routerHome        // was RouterHome()
```

`ImportPaths` honours `MCP_ROUTER_HOME` through `RouterHome.init`, so every existing lane behaves
exactly as before.

### A3 · Tests — `app/Tests/RouterCoreTests/ImportPathsTests.swift`

| Test | Asserts |
|---|---|
| `homeComesFromTheEnvironment` | `HOME=/tmp/x` → `claudeJSON == /tmp/x/.claude.json` |
| `anEmptyHomeFallsBackToTheAccount` | `HOME=""` → the `homeDirectory` argument |
| `anAbsentHomeFallsBackToTheAccount` | no `HOME` key → the `homeDirectory` argument |
| `bothPathsComeFromOneHome` | with `MCP_ROUTER_HOME` **unset**, `routerHome.configPath` is under the same `HOME` as `claudeJSON` — the A2.2 invariant, and what kills M2 |
| `mcpRouterHomeStillWins` | `MCP_ROUTER_HOME` set → `routerHome.root` is it, `claudeJSON` still under `HOME` |

---

## 2. Phase B — the import writer (S2)

### B1 · `ImportConfigWriter` — new, `app/Sources/RouterCore/Config/ImportConfigWriter.swift`

```swift
public static func write(
    adopted: [JSONMember], port: Int, toPath path: String,
    fileSystem: any FileSystem & FileModeWriting,
    processIdentifier: Int32, lockTimeoutMs: Int
) throws
```

Note the signature: `any FileSystem & FileModeWriting` (not `some FileSystem`) and an explicit
`processIdentifier`, both because `WatchBackup.writeAtomic` requires them. `ImportVerb.writeAdopted`
widens its own `fileSystem` parameter to match and passes
`ProcessInfo.processInfo.processIdentifier`.

Body, in order:

1. `ConfigMutationLock.withExclusiveLock(forConfigAt: path, timeoutMs:)` — **everything below,
   the read included.**
2. **Read inside the lock.** Parse; on absence or a parse that is not an object, start from empty
   members. A parse failure is **not** an error: the reference overwrites unconditionally, and
   throwing would wedge an import the user cannot escape.
3. **Merge.** Set `port`, `host`, `idleMs`, `mcpServers` in place where present; append in that
   order where absent; every other member keeps its **position**. A fresh file is therefore
   byte-identical to the reference's four-key document.
4. **Mode.** `fileSystem.fileExists(atPath: path) ? .preserveExisting : .fixed(0o600)`.
   A comment on this line records why neither obvious alternative may be used bare:
   `writeAtomic(.fixed(0o600))` writes a **new inode** and so always lands 0600, narrowing an
   existing 0644 config; and `fileSystem.writeFile(path, mode:)` `fchmod`s unconditionally
   (`FileModeWriting.swift:46-48`), which is wrong the same way.
5. `WatchBackup.writeAtomic(JSStringify.prettyTwoSpace(.object(root)), …)` — **no trailing
   newline.** `JSON.stringify` emits none and the current writer emits none;
   `WatchAdoption` appends one under the *watcher's* rules and copying that reddens `cli-import`.

**The backup stays in `ImportVerb`, outside the lock.** Revision 1 said both that it moved inside
and that it stayed in the verb, which cannot both be true. It stays out, for two reasons: the
`backed up existing config -> <path>` line is stdout, and `RouterCore` does not write to stdout
(`WatchVerb.swift:12-14` — it is linked into the MCP process); and the reference backs up outside
any lock too. **Consequence, stated rather than discovered:** the backup is a snapshot from before
the lock, so under contention it can differ from the pre-image the merge saw. That matches the
reference and is not worsened here.

### B2 · Tests — `app/Tests/RouterCoreTests/ImportConfigWriterTests.swift`

| Test | Asserts | Spec |
|---|---|---|
| `unknownTopLevelKeysSurviveInPlace` | full member list compared — **position and value**, not presence. Presence alone passes a rewrite that moves the key to the end | A3 |
| `theFourKeysAreOverwritten` | port/host/idleMs/mcpServers take the new values | A3 |
| `aFreshFileIsCreatedAt0600` | mode `0o600` | A5 |
| `anExisting0644FileStaysAt0644` | 0644 in → 0644 out | A5 |
| `anExisting0600FileStaysAt0600` | 0600 in → 0600 out. **Without this, `fileExists ? .fixed(0o644) : .fixed(0o600)` passes every other mode test while widening the file that holds API keys** | A5 |
| `aFirstWriteMatchesTheReferenceBytes` | compared to a literal **captured from `node -e`**, not from `JSStringify` — a pre-image recorded from Swift is the writer agreeing with itself | A7 |
| `thereIsNoTrailingNewline` | last byte is `}` | A7 |
| `aRenameFailureLeavesTheDestinationUntouched` | see below | A4 |
| `aHeldLockRefusesTheWrite` | `LockProblem.notAcquired`; destination unchanged | A6 |
| `theReadHappensInsideTheLock` | see below | A6 |
| `anUnparseableDestinationIsOverwritten` | matches the reference | B1.2 |

**`aRenameFailureLeavesTheDestinationUntouched`** uses a `RealFileSystem` decorator that throws from
`moveItem` **and records that it was called**. Three assertions: the decorator saw `moveItem`; the
temp `<path>.mcpr-tmp-<pid>` exists carrying the new bytes; the destination is byte-identical to its
pre-image. Without the first two, a writer that threw before any I/O passes — "nothing happened"
read as "the rename failed atomically".

**`theReadHappensInsideTheLock` — the interleaving, because the obvious one is vacuous.** Revision 1
said: holder takes the lock, writes a marker key, releases; the writer "which blocked" must contain
the key. That passes for **both** implementations — a read-outside-lock writer that starts after the
marker is written also sees it. The distinguishing order is: the writer must be **waiting on the
lock** before the marker is written.

```
FS decorator signals semaphore S the moment it reads the config path.
A: acquire the lock (long timeout) ; signal "locked"
main: wait "locked" ; start B on its own thread ; wait "B started"
A: wait on S for up to 2 s      <- buggy impl signals it; correct impl never does
A: write marker key K by raw file write (NOT ConfigEdit — same thread, reentrant)
A: release
B: (buggy) already snapshotted without K -> writes without K   -> ASSERT K PRESENT = RED
   (correct) blocked, reads after acquire, sees K              -> GREEN
```

`lockTimeoutMs` for B is set well above A's hold, or a correct implementation dies `notAcquired`
and never reaches the assertion. The 2 s wait on S is only ever *reached to expiry* by the correct
implementation; the buggy one signals it promptly, so the timeout is not load-bearing for the red.
The residual — a buggy B not scheduled within 2 s — is mitigated by waiting for "B started" first
and is recorded in the evidence file rather than papered over.

### B3 · `ImportVerb.writeAdopted`

Keeps `createDirectory`, the backup and its stdout line; the four-key construction and
`fileSystem.writeFile` are replaced by `ImportConfigWriter.write(…, lockTimeoutMs:
ConfigMutationLock.watcherTimeoutMs, processIdentifier: ProcessInfo.processInfo.processIdentifier)`.

---

## 3. Phase C — the `~/.claude.json` rewrite (S3)

### C1 · `ClaudeStagingEntry` — new, `app/Sources/RouterCore/Watch/ClaudeStagingEntry.swift`

Under `Watch/`, where every other `~/.claude.json` rule already lives.

```swift
public static let entryName = "mcp-router"
public static let legacyEntryName = "router"
public static func url(port: Int) -> String
/// Pure. Takes and returns a whole document; NEVER optional.
public static func rewritten(_ root: JSONValue, port: Int) -> JSONValue
public static func apply(atPath:port:fileSystem:processIdentifier:now:) throws -> Outcome
```

**`rewritten` takes and returns `JSONValue`, not `[JSONMember]`, and never returns `nil`.** Node
does `JSON.parse` → mutate → `JSON.stringify(d, null, 2)` on **whatever the root is**, every time
the file exists. An optional return would let a no-op re-run keep the original whitespace and skip
the backup, where Node always re-stringifies and `install.sh` always `cp`s.

| Root / `mcpServers` | Node | Swift |
|---|---|---|
| object root, `mcpServers` absent / `null` / `0` / `false` / `""` | `\|\|` yields `{}`, entry added | same |
| object root, `mcpServers` is `[]` | **`[]` is truthy in JS** — kept as an array; the named property dies in `JSON.stringify` | array kept, no entry added |
| object root, `mcpServers` is a truthy non-object (string, number) | property write is a silent no-op | value kept unchanged |
| array / string / number root | property write is a no-op; stringify emits the pretty-printed value | same |
| `null` root | **throws** `Cannot set properties of null` — *after* `install.sh`'s `cp` | throws, after the backup |

Delete `router` **only if** its `url` equals the new url. Every other member and key keeps position
and value.

**`apply`:** `fileExists` false → `.noStagingFile`, nothing written, exit 0 (A4.8). Parse; a parse
**failure** throws **before** the backup, so nothing is left behind (A4.9). Then `cp` to
`<path>.bak-mcp-router-<yyyyMMdd-HHmmss>` — **local time**, formatted from a `Date` with a fixed
`DateFormatter`, *not* `WatchBackup.stamp`, which is UTC ISO-8601 and would ship a name shape
`install.sh:162`'s `date +%Y%m%d-%H%M%S` does not produce. Then
`WatchBackup.writeAtomic(…, mode: .preserveExisting)`, no trailing newline.

**No `ConfigMutationLock`** — spec §5.3, `D-p2-a`. The doc comment carries the reason, including the
verified fact that nothing under `MCPRouterUI`/`MCPRouterKit` writes this file, so the next reader
does not "fix" the omission.

### C2 · `InstallEntryVerb.swift` — `app/Sources/MCPRouterCLI/`

Thin. `--port` **defaults to `RouterHome.defaultPort`**, `--claude-json` defaults to
`ImportPaths().claudeJSON`. One line printed per outcome. The port default is pinned here and tested
(C4), because the lane always passes `--port` and would never exercise it.

### C3 · Dispatch — `MCPRouterCLI.swift`

`case "install-entry": try InstallEntryVerb.run(arguments)` before `default`. The comment at
:37-38 ("one arm per verb `src/index.ts` dispatches, and nothing else") is rewritten in the same
edit to name the eleventh arm and cite P2-D1. `Copy.usage` is **not** touched.

### C4 · Tests — `app/Tests/RouterCoreTests/ClaudeStagingEntryTests.swift`

`rewritten` (pure): entry added to a file with no `mcpServers`; `null` → object; `0`/`false`/`""` →
object; **`[]` left as an array with no entry**; truthy string left unchanged; legacy `router` on
the same url deleted; legacy `router` on another url kept; an existing `mcp-router` replaced **in
place**; every other key keeps position and value; array/string/number roots round-trip with no
entry; a `null` root throws.

`apply` (filesystem): mode preserved both ways (0600→0600, 0644→0644); a backup exists whose bytes
equal the pre-image; an absent file writes nothing and does not throw; an unparseable file writes
**neither file nor backup**; no trailing newline; the default port is `RouterHome.defaultPort`.

**The "absent from `help`" assertion is not a unit test and the plan does not pretend otherwise.**
`Copy` lives in `MCPRouterCLI`, which `swift test` cannot import. It is a named mechanical step in
Phase E (E6) plus the `cli-help` row itself.

---

## 4. Phase D — the lanes (S4)

### D1 · `scripts/acceptance/parity-install.sh`

Extend `record()`'s ownership guard to the two new rows, **and update the header's `ROWS THIS LANE
OWNS` line and the `CAVEAT` paragraph at :31-35**, which currently say this lane does not own
`install-claude-json`. Same edit, or the next reader treats the new rows as someone else's.

Add a `normalise()` modelled on `parity-cli.sh:100-103`, rewriting the scratch home to `<home>` and
`.bak-<epoch>` / `.bak-mcp-router-<stamp>` to a fixed token. Without it both rows are permanently
red on absolute paths and timestamps, and the implementer's escape is to drop stdout from the
comparison — weakening a test to make a change pass.

**`install-import-servers`** — `env -u MCP_ROUTER_HOME HOME=<scratch>`, no `--from`, exactly
`install.sh:77`. The `~/.claude.json` seed is the **same adoptable fixture `parity-cli.sh:163-174`
uses** (`mcp-fixture-server.mjs` over stdio), so `mcpServers` on disk is genuinely the adopted set;
an empty or unadoptable seed would make both binaries write the same four-key skeleton without
reading the source and sell that as the row.

Two sub-scenarios:

- *fresh* — only `$HOME/.claude.json` present. Both must create
  `$HOME/.claude/mcp-router/servers.json` (the path itself is the A2.2 assertion) at mode **0600**.
- *pre-existing* — `servers.json` seeded at 0644 first, containing **exactly `port`, `host`,
  `idleMs`, `mcpServers` in that order and nothing else**. Any extra key, or another order, makes
  the two sides differ by `div-r1-d3`'s own divergence and reddens this row for the wrong reason.
  Both must leave the file at **0644**.

Compared per scenario: normalised stdout, exit code, `servers.json` bytes, `servers.json` mode.
Only those four — **not** a directory listing, since the Swift side also leaves `servers.json.lock`
(P2-D3), `manifest.json` and `router.log`.

**`install-claude-json`** — reference side: `cp`, then the `node -e` body **extracted from
`docs/install.sh` at run time**. Swift side: `install-entry --port`, which owns its own backup, so
the harness does **not** `cp` for it.

The extraction is guarded three ways, because a `sed` range that stops matching its end line emits
start-to-EOF and `node -e ''` is a successful no-op — both of which fail *open*:

1. the extracted body is non-empty **and** contains `mcpServers` and `renameSync`;
2. it does not contain `curl` or `launchctl` (i.e. the range did not run past the block);
3. **after the oracle runs, the reference's file must differ from its pre-image** — all three
   scenarios add or rewrite `mcp-router`, so "unchanged" is an environment failure, never `ok`.
   The identical check runs on the Swift side.

Three scenarios: no `mcpServers`; legacy `router` on the same url (deleted); legacy `router` on
another url (kept). Compared: file bytes, file mode, and a backup on each side whose bytes equal
that side's pre-image.

### D2 · `scripts/acceptance/parity-divergence.sh` — `div-r1-d3`

**Each side gets its own `MCP_ROUTER_HOME`.** `import --from` sets only the *read* path; the write
goes to `ROUTER_HOME`. Without this the lane writes the developer's real
`~/.claude/mcp-router/servers.json` — the exact footgun `WatchPaths.swift:8-10` exists for.

Each side's `servers.json` is seeded with the four keys **plus `startupTimeoutMs: 45000`**, and with
an `mcpServers` that is **not** the adopted set (a differently-named entry), so "Swift wrote" is
observable. `~/.claude.json` carries one adoptable fixture server.

Three assertions, recorded together in the detail string as `div-r2-d7` does:

```
ts_kept     reference still declares startupTimeoutMs?          expect no
swift_kept  Swift still declares it?                            expect yes
swift_wrote Swift's mcpServers == the adopted set (not seed's)?  expect yes
```

`ok` requires `no,yes,yes`. Everything else is `fail` — **including `no,yes,no`**, the shape a Swift
side that threw and wrote nothing produces, which revision 1 would have recorded as a pass.

This row measures the **preservation** half of D3. The **atomicity** half is B2's rename-failure
test, and the row's manifest note says so.

### D3 · Proving each lane can fail

| Row | Forced failure |
|---|---|
| `install-import-servers` | give one side a **different `HOME`** so the destination paths diverge. *(Not `--from`: that changes only the source, both sides still write `$HOME/.claude/mcp-router/servers.json`, and with the same seed content the "forced failure" comes out green.)* |
| `install-claude-json` | pass a different `--port` to one side → the url differs |
| `div-r1-d3` | revert `ImportConfigWriter`'s preservation for one run → `no,no,yes` |

### D4 · `planning/parity/surface.tsv`

Three rows `blocked` → `proven`, each note rewritten to state what the lane drives and what it does
not. `install-claude-json`'s note carries the caveat verbatim: the lane compares the Swift binary
against the installer's own extracted script, `docs/install.sh` still invokes `node`, and the flip
is `D-p2-b` / R4-C's. `div-r1-d3`'s note records that only the preservation half is measured here.

`parity-gate.sh` and `parity-fixture.sh` are **not touched** (P4 owns both).

---

## 5. Phase E — gates

From `/Users/lukerhodes/Dev/mcp-router/.worktrees/P2`; Makefile at the **worktree root**. Exit codes
as `cmd > /tmp/f.txt 2>&1; echo $?`, never through a pipeline.

| # | Gate |
|---|---|
| E1 | `make lint` — swiftformat runs **first and short-circuits**; check the exit code, not "0 violations". New files under the 400-line cap, split on real seams, no limit raised |
| E2 | `swift test --package-path app` — count must not drop; any `--filter` takes the **function name** and is confirmed to match before a red or green is believed |
| E3 | `make build-mac` — `RouterCore` is linked by it |
| E4 | `bash scripts/acceptance/parity-cli.sh` — `cli-import` and `cli-help` must still read ok |
| E5 | full `parity-gate.sh` — the AFTER number, from `.worktrees/P2`, same directory as BEFORE |
| E6 | **mechanical**: `grep -c 'install-entry' <(swift-source of Copy.usage)` expecting 0, fail-closed if the usage function cannot be located |
| E7 | **mechanical (A15)**: grep the diff for a `writeFile`/`writeAtomic` whose destination involves `manifestPath`; expect none |

**Before believing any red: rebuild.** `rm -rf app/.build && swift build --package-path app`;
for the mac check `rm -rf app/.derived/Build/Products/Debug/MCPRouter.app && make build-mac`,
because `make build-mac` exiting 0 does not clear the mtime freshness check after a rebase
(`D-m11-a`).

---

## 6. Phase F — mutations

A mutation that **cannot** redden is a finding about the test, re-aimed rather than swapped.

| # | Mutation | Killed by |
|---|---|---|
| M1 | `resolvedHomeDirectory` ignores `HOME` | `homeComesFromTheEnvironment`; `install-import-servers` |
| M2 | `ImportPaths` derives `routerHome` from `NSHomeDirectory()` instead of the resolved home | `bothPathsComeFromOneHome`. **Unit level only** — run through the install lane it would write the developer's live `servers.json` |
| M3 | `ImportConfigWriter` drops unknown top-level keys | `unknownTopLevelKeysSurviveInPlace`; `div-r1-d3` |
| M4 | mode always `.fixed(0o600)` | `anExisting0644FileStaysAt0644` |
| M5 | mode always `.preserveExisting` | `aFreshFileIsCreatedAt0600` |
| M6 | mode `fileExists ? .fixed(0o644) : .fixed(0o600)` | `anExisting0600FileStaysAt0600` — the case M4/M5 alone do not cover |
| M7 | the read moves outside the lock | `theReadHappensInsideTheLock` |
| M8 | a trailing `"\n"` is appended | `thereIsNoTrailingNewline`; `cli-import` |
| M9 | the legacy-`router` delete drops its url check | `aLegacyRouterEntryOnAnotherUrlSurvives`; `install-claude-json` scenario 3 |

---

## 7. Phase G — evidence and commit

`planning/evidence/P2-acceptance.md`: every gate with its exit code; the three forced lane failures
with transcripts; the mutation table red/green per row; grok verdicts and byte counts; parity
BEFORE/AFTER **both from `.worktrees/P2`**.

Commit code, lanes and `surface.tsv` on `ai/p2`. `spec-P2.md` and `plan-P2.md` stay in the main
tree, **uncommitted on this branch**. Stop before merge — no push, no merge.

---

## 8. Risk register

| Risk | Mitigation |
|---|---|
| `cli-import` reddens (newline, backup name, mode) | B1.5, B3, A3.5; E4 runs before the full gate |
| `cli-help` reddens | `Copy.usage` untouched; E6 + E4 |
| A lane writes the developer's real files | every lane invocation carries a scratch `HOME` and, in D2, a per-side `MCP_ROUTER_HOME` |
| A lane passes for the wrong reason | D1's three extraction guards + the differs-from-pre-image check; D2's `swift_wrote`; D3's forced failures |
| The mode branch written wrong in any of three ways | M4/M5/M6 as a triple |
| `WatchPaths` refactor changes watcher behaviour | identical rule, R2-W's tests unedited; revert the refactor if one needs editing |
| Concurrency with P4 | P2 opens `parity-install.sh` and `parity-divergence.sh` only |

---

## 9. Disposition of the plan review

grok-4.6, exit 0, 11,854 bytes, 21 findings, **VERDICT: AMEND**. **All 21 accepted.**

| # | Sev | Finding | Where it landed |
|---|---|---|---|
| 1 | high | The lock test's interleaving cannot distinguish read-inside from read-outside | B2, rewritten with the semaphore handshake and the ordering spelled out |
| 2 | high | `oneHomeFeedsBothPaths` was identity; M2 unkillable because `ImportVerb` is untestable | A1 extracts `ImportPaths` into `RouterCore`; the test now exercises the real pairing |
| 3 | high | M4+M5 do not pin "leave the existing mode alone" | `anExisting0600FileStaysAt0600` + M6 |
| 4 | high | B1 and B3 contradicted each other on where the backup lives; `RouterCore` cannot print | B1: backup stays in the verb, outside the lock, with the consequence stated |
| 5 | high | The atomicity test passes for a writer that throws before any I/O | B2: assert `moveItem` was called and the temp carries the new bytes |
| 6 | high | A byte pre-image recorded from Swift is the writer agreeing with itself | B2: literal captured from `node -e` |
| 7 | high | The lane compares stdout containing absolute homes and epoch backup names | D1: `normalise()` copied from `parity-cli.sh` |
| 8 | high | The pre-existing seed could redden the row via `div-r1-d3`'s own divergence | D1: seed pinned to exactly four keys in order |
| 9 | high | The forced failure used `--from`, which does not diverge the destination | D3: different `HOME` on one side |
| 10 | high | `div-r1-d3` set no `MCP_ROUTER_HOME` — would write the developer's real config | D2: per-side `MCP_ROUTER_HOME`; seed `mcpServers` differs from the adopted set |
| 11 | high | The `sed` oracle extraction fails **open** | D1: three guards plus a differs-from-pre-image check on both sides |
| 12 | high | `rewritten` returning nil / `[JSONMember]` cannot represent non-object roots | C1: takes and returns `JSONValue`, never nil, with a Node-behaviour table |
| 13 | medium | The backup stamp would ship UTC where `install.sh` uses local time | C1: local `yyyyMMdd-HHmmss`, explicitly not `WatchBackup.stamp` |
| 14 | medium | B3 would not compile — `some FileSystem`, missing `processIdentifier` | B1 signature and B3 call site |
| 15 | medium | Presence-only preservation test passes a rewrite that reorders | B2: full member list |
| 16 | medium | The usage-absence check was listed as a unit test then retracted | C4 says plainly it is not one; E6 is the named mechanical step |
| 17 | medium | `--port`'s default was unpinned and untested | C2 + C4 |
| 18 | medium | The seed was unspecified; an unadoptable one sells mode-only as the row | D1: the `parity-cli.sh` adoptable fixture |
| 19 | medium | `[]` is truthy in JS; `0`/`false`/`""` are falsy | C1 table + C4 |
| 20 | low | M2 through the install lane would write the live file | M2 marked unit-level only |
| 21 | low | `parity-install.sh`'s header still disclaims the new row | D1 updates `ROWS THIS LANE OWNS` and the caveat |
