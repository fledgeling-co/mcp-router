# R10 — acceptance evidence

**Item:** R10, `index` prints two counts that disagree, and neither is checked
**Brief:** `planning/features-to-triage/R10-index-reports-a-write-that-did-not-land.md`
**Defect:** DEF-049 (major), the CLI half. **Requirements:** REQ-019, REQ-007.
**Branch:** `ai/r10` · **Worktree:** `.worktrees/R10`

R10 renders nothing — no view, no surface, no interaction — so `UI_VERIFICATION.md`'s screen ledger
has no rows here and no app was launched. What follows is the behavioural evidence in its place.
Append only.

**This branch was recovered.** The first runner was killed by the harness's no-progress detector with
seven paths uncommitted and nothing on the branch. Everything below was re-measured on the recovered
tree rather than carried over: the tree as recovered failed `make lint` on four violations, and the
two review lanes were re-run against the final diff. Where an earlier sitting's number is quoted it
is marked as such.

---

## What changed, and what deliberately did not

`ManifestIndexer.record` called `try? ManifestIO.save(...)`. The one call that makes an index durable
was the one call whose failure nothing downstream could observe, so `index --force` against a router
home the process may read and traverse but not write printed

```
  ok    witness-fixture (1 tools)
…
0 tools cached -> /tmp/.../manifest.json
```

and exited 0, over a `manifest.json` that does not exist.

- `IndexOutcome` gains `cacheFailure: String?` — **why the save refused**, `nil` when it landed or
  was never attempted — and a derived `cached: Bool`. It is not folded into `error`, because `error`
  is the *upstream's* failure and the control API turns it into `error ? 422 : 200`.
- `IndexOutcome` gains `heldChanges: Int?`, the bookkeeping's held-for-approval count. This is the
  half of the same disagreement with **no filesystem in it**: a server whose surface changed has its
  new tools held as pending while the manifest keeps serving the approved set, so `ok fixture
  (2 tools)` printed over `1 tools cached` on a perfectly writable home.
- `ManifestIndexer.record` returns the refusal instead of discarding it, and the indexer logs
  `IndexLogEvent.manifestNotWritten` — a new `LoggableEvent` type of its own, so `LogEvent`'s "every
  string is the reference's" invariant is untouched. The control API's reindex route has no field to
  carry the failure, so without the log line that path stays as silent as the CLI's was.
- The `index` verb prints a third, deliberately unaligned status, `not cached <server> …`, and closes
  with a sentence that reconciles the per-server lines against the on-disk count. The per-upstream
  accumulation lives in a file-scope `IndexReport`, because the three lines are not exclusive.

**The exit code is unchanged and is pinned by a test that says so.** Propagating the error would move
the CLI's exit-code contract, which is the owner's call and sits on `M28-decision-docket.md`; the
project has already taken the opposite decision on a sibling path, pinned at
`ControlApproveDispatchTests.swift:114-118`.

## The one sentence that took five attempts

The closing line has to be true in every shape the verb reaches, and four wordings died on four
different shapes. All four are recorded at the call site so the next reader does not re-derive them:

| Wording | The shape that falsifies it |
|---|---|
| "these are missing from that count" | a server's previous row is still on disk and being counted |
| "the count is as it stood before this run" | a **sibling** server's write landed and moved it |
| "nothing this run read from them is in that count" | the refused update carried the **same** tools the older row already holds — `echo` is then both what this run read and what the count includes |
| "whatever they contribute to it is from an earlier run" | the shape the defect was **found** in: a home never written has no earlier run and no file, and the line sends a reader looking for one |

The fourth was found by both out-of-family lanes independently, after the first three had already
been fixed. What survives is a claim about the **write**, which is the thing that did not happen:

> `2 server(s) above did not reach the manifest, so nothing this run indexed for them was recorded in that count.`

The log line carried the third wording and then the fourth, and now says the same true thing:
`nothing from this run was recorded for it`.

## What the verb prints now — four shapes, measured

Against a home holding one working stdio fixture and one server whose command does not exist. stderr
(the router log) is suppressed here; the log line is asserted separately.

```
=== 1. writable, first run ===
2 upstreams, 2 need indexing (forced: all)
  ok    fixture (1 tools)
  FAIL  broken: spawn /tmp/r10a/no-such-binary ENOENT

1 tools cached -> /tmp/r10a/home/manifest.json
All upstreams closed; none will open again until a tool is called.
exit=0

=== 2. denied, with the row from run 1 still on disk ===
2 upstreams, 1 need indexing (forced: all)
  FAIL  broken: spawn /tmp/r10a/no-such-binary ENOENT
  not cached  broken (the failure was not recorded either): You don’t have permission to save the file “manifest.json.tmp-66481” in the folder “home”.
  not cached  fixture (1 tools indexed): You don’t have permission to save the file “manifest.json.tmp-66481” in the folder “home”.

1 tools cached -> /tmp/r10a/home/manifest.json
2 server(s) above did not reach the manifest, so nothing this run indexed for them was recorded in that count.
All upstreams closed; none will open again until a tool is called.
exit=0

=== 3. denied, on a home that has never been written ===
2 upstreams, 2 need indexing (forced: all)
  FAIL  broken: spawn /tmp/r10b/no-such-binary ENOENT
  not cached  broken (the failure was not recorded either): You don’t have permission to save the file “manifest.json.tmp-66508” in the folder “home”.
  not cached  fixture (1 tools indexed): You don’t have permission to save the file “manifest.json.tmp-66508” in the folder “home”.

0 tools cached -> /tmp/r10b/home/manifest.json
2 server(s) above did not reach the manifest, so nothing this run indexed for them was recorded in that count.
All upstreams closed; none will open again until a tool is called.
exit=0
manifest.json present: no

=== 4. writable, a surface that CHANGED between runs ===
  ok    fixture (1 tools)
  FAIL  broken: spawn /tmp/r10c/no-such-binary ENOENT

1 tools cached -> /tmp/r10c/home/manifest.json
All upstreams closed; none will open again until a tool is called.
2 upstreams, 1 need indexing (forced: all)
  ok    fixture (1 change(s) held for approval)
  FAIL  broken: spawn /tmp/r10c/no-such-binary ENOENT

1 tools cached -> /tmp/r10c/home/manifest.json
All upstreams closed; none will open again until a tool is called.
exit=0
```

Shape 1 is byte-for-byte what the verb printed before this item: the closing block was one
`Out.print` and is now three, and the reconciliation sentence is emitted only when something was
lost. `parity-cli.sh`'s `cli-index` and `cli-refresh` rows run on a writable home and both still
agree with the reference.

Shape 3 is the one the denial control found, and it is the one the fourth wording was false on.
Shape 4 has no filesystem in it at all, and shows **both** runs — the seed at one tool, then the same
server listing two — because the held disposition only exists relative to a surface already approved.
Its first run's `2 upstreams…` header is the only line trimmed from any of these captures.

## Gates, each exit code captured on its own line, never through a pipe

| Gate | Result | Exit |
|---|---|---|
| `swiftformat --lint . --config .swiftformat` | `0/493 files require formatting, 192 files skipped` | 0 |
| `swiftlint lint --strict --config .swiftlint.yml` | `Found 0 violations, 0 serious in 486 files` | 0 |
| `./scripts/lint/no-raw-design-values.sh` | `clean` over 75 files under the geometry rules | 0 |
| `./scripts/lint/no-wire-codable.sh` | `clean · 2 exemption(s) recorded` | 0 |
| `make test` | `discovered 1550 test lines` · `Test run with 1546 tests in 193 suites passed` · `executed 1546 tests` | 0 |
| `make parity` | `parity: 358 vector cases compared (floor 358)` | 0 |
| `./scripts/acceptance/parity-cli.sh` | `cli: 17 verbs agreed, 0 did not` | 0 |

`make lint` was **red on the tree as recovered** — two swiftformat rules and three swiftlint rules,
across the CLI and the new end-to-end test file. Cleared by moving the per-upstream accumulation out
of `MCPRouterCLI.index` into a file-scope `IndexReport` and the test fixture, home builder and runner
out of the suite into a file-scope `IndexCLIHarness`. No assertion changed.

The suite stood at 1539 before this item (an earlier sitting's figure) and reports 1546 now: seventeen
cases across the two files, with `ManifestIndexerWriteFailureTests` rewritten in place rather than
added.

`make build-mac`, `make build-ios` and the two simulator lanes were **not run**. Nothing in this diff
reaches `MCPRouterUI`, `MCPRouterIOS` or any rendered surface — the changed files are `RouterCore`,
the CLI, and two test files in `RouterCoreTests` — and `UI_VERIFICATION.md` rule 2 is explicit that a
screen whose files have not changed is not re-tested. Declared as a skip, not claimed as a pass.

## Arming — every guard was seen to fail, against the defect it exists for

`SWIFT_PRACTICES.md` §7: a test that has never failed is not known to work. Each arm reverts one
thing, runs both suites, and is restored from a byte copy. Run against the final tree, not an earlier
one; the script restores under `finally` and `git status` was clean afterwards.

| Arm | What was broken | Result |
|---|---|---|
| 1 | `try? ManifestIO.save(...)` restored in `ManifestIndexer.record` — the original defect | **20 issues** |
| 2 | The CLI takes the `ok` branch again for a lost row | **1 issue** |
| 3 | The reconciliation sentence removed | **3 issues** |
| 4 | `if !report.lost.isEmpty { exit(1) }` — the exit code moved | **2 issues.** The pin bites |
| 5 | The denial itself removed (`0o700` instead of `0o500`) | **10 issues**, including the manifest-is-absent control |
| 6 | The lost row folded back under `upstreamFailure == nil` | **2 issues** |
| 7 | The log line's third wording restored | **1 issue** |
| 8 | The closing sentence's fourth wording restored | **4 issues** |

Arms 2, 3, 4, 6 and 8 change only `MCPRouterCLI.swift` and each went red, which also settles a
question the end-to-end tests depend on: **`swift test` rebuilds the executable target before
running**, so those tests measure the binary on this branch and not a stale one.

## The instrument, and why it is a Swift test rather than a shell lane

`planning/test-campaign/bin/witness-arm-denial.sh` is the arming control that found the defect, and it
was read and used read-only. It is a campaign instrument rather than a gate — nothing in `make all`
runs it — so a regression there would not have been blocked. The denial is therefore rebuilt inside
`RouterCoreTests`, where `make test` runs it.

`CLIIndexWriteDeniedTests` writes a router home with one real stdio MCP fixture, sets the home to
`0o500`, runs the **built `MCPRouterCLI` binary** as a subprocess with `MCP_ROUTER_HOME` pointed at
it, and reads stdout, stderr and the exit status separately. The fixture script lives outside the
home, so making the home unwritable changes exactly one thing. A missing binary is a hard failure
naming the paths searched, not a skip: a skip and a pass are indistinguishable from the outside.

| Case | What it proves |
|---|---|
| `aWritableHomeStillPrintsOK` | control: `ok fixture (1 tools)`, `1 tools cached`, no `not cached`, manifest on disk |
| `aDeniedHomeIsNotReportedAsOK` | no `ok` line, `not cached fixture`, `0 tools cached`, the reconciliation sentence, **no claim about an earlier run**, and the manifest really absent |
| `theExitCodeIsUnchanged` | exit 0, with the message saying a red here is a decision to record rather than a regression to patch |
| `aFailedUpstreamWhoseFailureRowIsAlsoLostSaysSo` | `FAIL broken:` **and** `not cached broken (the failure was not recorded either)` **and** the working sibling's own lost row **and** `2 server(s)` |
| `anOlderRowIsNotClaimedMissingFromTheCount` | with a row already on disk: `1 tools cached`, not 0, the surviving wording, and all three dead ones absent |
| `aHeldSurfaceReportsChangesRatherThanTools` | `ok fixture (1 change(s) held for approval)`, never `(2 tools)`, over `1 tools cached`, with no `not cached` |

`ManifestIndexerWriteFailureTests` carries the unit half over `MemoryFileSystem`: both write arms
refused, the **rename arm alone** (proved through the operation recorder rather than by pinning a
leaked temp file), an upstream failure whose failure row is also lost, an older row surviving a
refused update, a held surface whose row is **also** lost, an upstream whose answer has no tools
array reporting no cache failure, the log line firing, and a control proving it does not always fire.

**That file already existed, untracked, in the main checkout**, written by the sitting that found the
defect; it characterised the behaviour without correcting it and said so in its own doc comment. It
was read first, as the brief asks, and this branch rewrites it in place. **Its untracked twin in the
main checkout will block `git merge`** until whoever owns it moves it aside.

## Out-of-family review — two families ran, and both found the same unfixed defect

The codex lane is available again: `model: gpt-5.6-sol`, `reasoning effort: high`, both confirmed in
its header, and the `-o` file asserted **non-empty and freshly written** rather than by exit code —
a stale `-o` file from the killed runner's sitting sat at that path throughout, and its mtime is what
distinguished the two.

| Lane | Family | Findings | Accepted | Declined |
|---|---|---|---|---|
| `codex exec -m gpt-5.6-sol` (high) | OpenAI | 5 | 4 | 1 (deferred, see below) |
| `agy --model gemini-3.7-flash-high` | Google | 6 | 4 | 2 |
| `grok -m grok-4.6` (xhigh) | xAI | — | — | — |

**The grok lane produced no findings and is recorded as incomplete, not as a pass.** It emitted 456
bytes of narration ("I'll check ManifestIO, bookkeeping, the TypeScript reference…"), then ran to
the 900-second wall clock and was killed by `SIGALRM` (exit 144) having written nothing further. It
had also begun re-reading the working tree, which by then had moved past the diff it was given. Two families answered, which is what the gate asks for; this is the third, and it did not.

**Accepted and fixed:**

1. *(codex and gemini, independently)* Both the closing sentence and the log line claimed the row on
   disk came "from an earlier run" — on the shape the defect was found in there is neither. Rewritten
   as a claim about the write. This is the fourth wording, and it is armed twice (arms 7 and 8).
2. *(codex and gemini, independently)* The end-to-end harness drained stdout to EOF and only then
   stderr, which deadlocks whenever the child fills the second pipe's buffer first. It writes to
   files now, which have no buffer to fill.
3. *(codex and gemini, independently)* `aFailedUpstreamWhoseFailureRowIsAlsoLostSaysSo` left the
   working sibling's `not cached` line and the `2 server(s)` count unasserted, so a regression that
   dropped the successful sibling's row still passed. Both are asserted; the mixed shape is the point.
4. *(codex)* A held surface whose row is **also** lost had no test at all, so a refactor making
   `heldChanges` and `cacheFailure` mutually exclusive in that reachable state would have gone
   unnoticed. `aHeldSurfaceWithARefusedWriteReportsBoth` pins all three fields together.
5. *(gemini)* The no-tools-array arm fabricated a `cacheFailure`, so a **protocol** error printed
   `not cached … check that directory's permissions` on a perfectly writable disk. That arm returns
   no `cacheFailure`, and the field is documented as "the save was refused" rather than "no row
   exists". *(Fixed in the earlier sitting; kept and still tested.)*

**Declined, with reasons:**

- *(codex, finding 2)* **`ManifestIO.save` names its temp file `manifest.json.tmp-<pid>`, so two
  concurrent `index()` calls in one process race on the same path.** A writes its temp, B overwrites
  it, A renames B's bytes successfully, B's rename gets `ENOENT`, and B reports a `cacheFailure` for a
  row that is in fact on disk. Real, and it is a **false refusal** rather than a false success — the
  opposite direction to DEF-049. Not fixed here on three grounds: the root cause is in
  `ManifestIO.swift`, which the brief's Scope section does not include; the CLI's `index` verb walks
  its upstreams sequentially in one loop and cannot reach it; and the race predates this item, where
  `try?` swallowed the same outcome silently. **Reported as a follow-up** — it needs an owner for
  `ManifestIO`'s temp naming and for `record`'s unisolated read-modify-write together.
- *(gemini, finding 2)* **`LogEvent.serverIndexed` is emitted before `IndexLogEvent.manifestNotWritten`**,
  so a consumer reading only the first sees a success for a row that was dropped. Kept: the line is
  true — the index did read N tools — and the order is fact then consequence. Suppressing
  `serverIndexed` on a lost write loses a true line and diverges from the reference's log sequence.
  A two-way door, named rather than left implicit.
- *(gemini, finding 5)* `IndexCLIHarness.binary()` looks only for the debug build. `make test` is a
  debug build; a release run fails loudly with the paths it searched, which is the designed behaviour
  rather than a silent skip.
- *(gemini, finding 1)* On a held surface whose row is also lost, the `not cached` line reports
  `(2 tools indexed)` rather than the held change count. Kept: the upstream did list two tools and
  the indexer did read them, so the line is true, and it opens with `not cached` rather than a
  success. Pinned by the test in accepted-item 4 so a later change to it is deliberate.

**Also recorded and out of scope:** `ImportVerb.probe` (`ImportVerb.swift:109`) still prints
`ok <name> (\(outcome.tools) tools)` and reads neither `cacheFailure` nor `heldChanges`, so `import`
can adopt a server and exit 0 with no manifest row. The brief fences this item to `ServicePorts.swift`
and the `index` verb expressly ("Recorded here so the fix is not mistaken for a sweep"), and
`cli-import` is a proven parity row. **Reported as a follow-up.**

## A divergence from the reference that this change narrows

`src/manifest.ts:135` `saveManifest` does **not** guard its `writeFileSync`/`renameSync`, and
`src/index.ts:186` calls it **before** the `ok`/`FAIL` print loop. So the reference, on the same
denied home, throws out of `cmdIndex`, is caught by `run().catch`, writes `mcp-router: EACCES…` to
stderr and exits **1** — it never prints a lying `ok` line at all. The Swift port's exit 0 is
therefore an **undeclared divergence that predates this item**, and it is exactly the half
`M28-decision-docket.md` holds. This change removes the false `ok` line without moving the exit code,
which narrows the gap in the only direction available inside this item's scope.

## Reviewing models

`writer: claude-opus-5[1m]` · `reviewers: gpt-5.6-sol (high) — answered; gemini-3.7-flash-high —
answered; grok-4.6 (xhigh) — incomplete, recorded as incomplete` · no downgrade taken: the codex lane
answered on **content and file mtime**, never on its exit code.
