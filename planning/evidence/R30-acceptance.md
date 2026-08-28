# R30 — acceptance evidence

**Item:** R30, ingest what Claude acquires · **Branch:** `ai/r30` · **Worktree:** `.worktrees/R30`
**Spec:** `planning/specs/spec-R30.md` · **Brief:** `planning/features-to-triage/R30-ingest-what-claude-acquires.md`

Append-only. Each row names the screen or surface, how it was verified — the actual command — the
commit it was verified at, and the result.

---

## 0 · The boundary, and how it is checked rather than promised

This item builds an ingestion and does **not** run it against the live tree. Three mechanisms hold
that, and each is a thing a reader can run:

| the promise | what enforces it |
|---|---|
| no test or gate reads or writes the real `~/.claude` | every fixture descends from `NSTemporaryDirectory()` (`IngestBench.init`) or `mktemp -d` (`r30-ingest.sh`) |
| the acceptance lane cannot silently reach the real file | it stats `$HOME/.claude/settings.json` before its run and compares size and mtime after — `r30-ingest.sh`, the assertion labelled *the real ~/.claude/settings.json was not touched* |
| the live run is a command the owner types | `mcp-router ingest` with neither `--claude-home` nor `--live` exits 1; `--apply` is not the default |

The one reading taken from the real tree was the **read-only measurement** in `spec-R30.md` §1,
taken 2026-08-28 with `python3` walking `~/.claude`. It reports shape and counts. No value from any
file under `~/.claude` is reproduced in this repository, and the fixture's `settings.json` carries
the real file's member *shape* with invented values.

---

## 1 · The requirement table

Each row is the brief's own acceptance sketch, with the oracle that settles it.

| # | requirement (brief's words) | oracle | verdict |
|---|---|---|---|
| A1 | a skill, plugin or marketplace that appears in Claude's directories is registered in the router | `G1` names all six fixture entries; `G6` reads them back through the store with `problem == nil` | see §2 |
| A2 | after ingestion the router's copy is the only one | `G6` — the source path no longer exists and the store's copy has the source's SHA-256 tree digest | see §2 |
| A2b | …and the extension still works | **partly unproven, and declared as such.** The bytes are complete and the store reads them; whether Claude resolves an ingested extension is a fact about Claude, and establishing it needs the live tree. `--link-back` is the mechanism, off by default. `spec-R30.md` §3.1 | declared |
| A3 | nothing is removed until the router's copy is readable and complete — copy, verify, then remove | `ExtensionIngest.verify` — the source is re-fingerprinted, the copy's digest must match, the store's reader must return no problem; `G6` | see §2 |
| A4 | an extension the router cannot identify is reported and left alone | `G2` — three refusals by slug, and the two unidentifiable trees are asserted **still on disk**; `r30-ingest.sh` repeats it against the binary | see §2 |
| A5 | the removal is reversible from the router without re-downloading | `G10` (bytes and keys back), `G13` (a manifest parsed from its own file drives an undo in a process that never saw the run), `G11` (an occupied path is refused, not clobbered) | see §2 |
| A6 | ingestion never runs against a directory a person is editing | `G3` — the settle window, with its own presence control; plus the post-copy re-fingerprint in `verify` | see §2 |
| A7 | `settings.json` is edited by a writer that preserves everything it does not own | `G7` (six untouched members compared by value **and** position; top-level count before == after), `G8` (a no-op leaves the file byte-identical, with a presence control), `G9` (an unparsable file is not rewritten), `G15` (order restored, not just membership) | see §2 |

---

## 2 · Runs

| when | surface | command | commit | result |
|---|---|---|---|---|
| 2026-08-28 | `make lint`, whole | `make lint` (through `governor-run --weight 2`) | `a17b5fd`+wt | **exit 0.** All 24 members produced output; `swiftlint --strict` *Done linting! Found 0 violations, 0 serious in 688 files*. Transcript: `planning/evidence/R30/make-lint-summary.txt` |
| 2026-08-28 | `make test`, whole | `make test` (through `governor-run --weight 4`) | `a17b5fd`+wt | **exit 2 — 2041 tests in 259 suites, 3 issues, all three pre-existing.** Both R30 suites passed; all 15 R30 tests green. Transcript: `planning/evidence/R30/make-test-r30-suites.txt` |
| 2026-08-28 | R30 acceptance lane | `./scripts/acceptance/r30-ingest.sh` | `a17b5fd`+wt | **exit 0 — 35 ok, 0 failed, 35 assertions against a floor of 20.** Transcript: `planning/evidence/R30/lane-r30-ingest.txt` |
| 2026-08-28 | the CLI, by hand | `MCPRouterCLI ingest --claude-home <tmp> --settle-seconds 0` then `--apply` | `a17b5fd`+wt | plan printed 3 to ingest and 1 left alone and changed nothing; apply ingested 3, withdrew 2 keys, kept 3 top-level members, printed the undo command |

### 2.1 · The three failures in `make test`, and why they are not R30's

`make test` exits 2 on this branch. The three issues are `MockTokenLiteralTests` (1) and
`MockTokenParityTests` (2), and they are **inherited, not caused**. Three readings say so, and none
of them is an assertion about intent:

1. `git diff --quiet bb3359a -- design/mcp-router-console.html` — the file the tests read is
   **identical to this branch's base**. Same for both test files.
2. `git blame -L 692,694 bb3359a -- design/mcp-router-console.html` puts all three offending lines
   on `95fbc21`, *"fix(M31): dim the two button variants that resolve no accent fill"*.
3. `git merge-base --is-ancestor 95fbc21 bb3359a` succeeds — that commit is already on `main`.

Same input file, same test code, same result. R30 touches no file under `design/`.

**This is a red gate, and it is reported as one.** It is not a claim that `make test` is green.

### 2.2 · One failure that WAS R30's, and what it changed

The first full run reported **four** issues. The fourth was
`LogParityTests` A31 — *"no source file in the router core writes to stdout"* — naming
`ExtensionFingerprint.swift:76`. The rule refuses any line under `app/Sources/RouterCore`
containing `print(`, because a router speaking MCP over stdio must keep that stream clean, and its
own comment records that scanning for the `FileHandle` names alone would miss the likeliest
regression. `TreeFingerprint(` contains that substring.

The fix was to rename the type — `TreeFingerprint` → `TreeStamp`, `ExtensionFingerprint` →
`ExtensionStamp` — not to narrow the rule. `FileStamp` was already this repository's word for the
same idea, so the gate cost a noun and kept its strength. The reasoning is recorded on
`ExtensionStamp.swift` rather than only here.

### 2.3 · Two environment failures that were not defects, recorded so they are not re-diagnosed

* `make test` twice reported `error: fatalError` with **no source location**, which reads exactly
  like a compiler kill under memory pressure — the machine was at load 993 at the time. It was
  not. It was SwiftPM's generic wrapper over a real compile error in
  `ExtensionIngestApplyTests.swift:135`: `#expect(try? f() == "x")` parses as `try? (f() == "x")`
  and yields `Bool?`. `swift build --build-tests` named it in one line where `make test` did not.
* `make lint` once died mid-run with `shell-init: error retrieving current directory: getcwd`, and
  every gate after that point failed to open its own file. The tree was intact; a re-run went
  green. Four sibling fleet runners were live in the same repository at the time. Recorded as
  transient concurrency rather than as a finding.

---

## 3 · What was NOT done, stated as a boundary rather than left to be found

| not done | why | where it goes |
|---|---|---|
| the ingestion has never been run against the real `~/.claude` | the owner's standing answer for this shape of work is *prepare it, don't run it* | the owner types `mcp-router ingest --live --apply` |
| `--link-back` is not proven to make Claude resolve an ingested extension | establishing it needs the live tree | flagged in `spec-R30.md` §3.1; the mode ships off by default |
| no control-API route for the plan | R30's deliverable is the owner-invoked command | deferred, `spec-R30.md` §5 |
| no continuous watcher | the brief's own assumption, kept | deferred, `spec-R30.md` §5 |
