# spec-P2 — the `import` verb and the `~/.claude.json` rewrite

| | |
|---|---|
| Item | **P2** — router lane |
| Register entries | `D-k` (the remaining CLI verbs) · `D-w2` (`ImportVerb` uses `NSHomeDirectory()`) |
| Deps | R2-R ✓ · R2-W ✓ |
| Branch | `ai/p2` · worktree `.worktrees/P2` |
| Status | Spec — **amended after an out-of-family REJECT-adjacent AMEND**, see §11 |
| Review lane | grok-4.6, out-of-family. Smoke-tested before use (§10) |
| Parity BEFORE | **73 of 83 proven, 9 blocked, 1 DIVERGED, gate exit 1** — measured from `.worktrees/P2` |

---

## 1. What the brief said, and what turned out to be true

The brief reads *"R2-R shipped the Swift CLI and proved 8 of 10 verbs. `import` and the
`~/.claude.json` rewrite it performs remain."*

**Half of that premise is wrong, and the wrong half changes the work.** Measured on `317d957`:

- `import` **is** implemented (`app/Sources/MCPRouterCLI/ImportVerb.swift`, 154 lines) and its
  parity row `cli-import` reads **`proven`** (`mcp — the endpoint the brief's tool-list and call-result corpora travel over.`, `planning/parity/surface.tsv:97` at `7babd97`). Not a missing verb.
- The reference's `import` (`src/index.ts:80` `cmdImport`) **does not touch `~/.claude.json`**. It
  reads it and writes only `servers.json`. The rewrite is a **separate installer step** —
  `project and Claude Code rewrites it constantly, so touch only the router key.`, `docs/install.sh:167` at `7babd97`, an inline `node -e` script — and is a verb of no binary today.

So P2 is not "write the import verb". It is three rows, and the useful question is what each needs.

### The three rows, and the true blocker of each

| Row | Group | What the manifest says blocks it | What actually blocks it |
|---|---|---|---|
| `install-import-servers` | install | "`install.sh:77` runs `node dist/index.js import` … this row is the on-disk RESULT it produces" | The installer runs `import` with **no `--from`** and **no `MCP_ROUTER_HOME`**, so *both* defaults are exercised — and both resolve through the `NSHomeDirectory()` of **`D-w2`**. Under a scratch `HOME` the two binaries read and write **different files**, so the row cannot be measured without eating the developer's real `~/.claude.json` |
| `div-r1-d3` | divergence | "reached only through the import and index CLI verbs Swift does not implement" | Swift **does** implement them — but `ImportVerb.writeAdopted` is a *faithful port* of the reference's four-key writer, so **spec-R1's declared divergence D3 is not implemented on this path**. The lane cannot assert a divergence the code does not have |
| `install-claude-json` | install | "`install.sh:141` rewrites the user's own config through a `node -e` script … the step that actually points Claude Code at the router" | Genuinely absent. No Swift code performs this rewrite |

`div-r1-d3` is worth dwelling on. The divergence lane already records `div-r1-d3-control`, and
`record div-r1-d3-control ok "swift and the reference both preserve unknownTopLevel across`, `parity-divergence.sh:180` at `7babd97` is explicit that it measured the **control-API** writer, not this one,
because *"recording that as proof of this claim would be proving a capability by measuring another
one"*. That honesty is why the row is still open, and P2 must not spend it.

---

## 2. Scope

**In.** Four changes, three rows.

1. **S1 — `ImportVerb` honours `$HOME`** (`D-w2`), resolving **one** home for both
   `~/.claude.json` and `RouterHome`.
2. **S2 — `ImportVerb.writeAdopted` becomes a third `servers.json` writer**: atomic, preserving
   unknown top-level keys, holding the config mutation lock across read-modify-write, and using the
   **import verb's own** mode rule.
3. **S3 — a Swift `~/.claude.json` router-entry rewrite**, reproducing `if [[ -f "$CLAUDE_JSON" ]]; then`, `docs/install.sh:162-188` at `7babd97`
   on disk, exposed as a CLI verb the installer can call after the cutover.
4. **S4 — parity lanes** that measure S1–S3 as the three rows above.

**Out, and named rather than silently skipped.**

- **`docs/` is never written.** It is the published GitHub Pages source of a public repo. S3 gives
  the binary the *capability*; wiring `install.sh` to call it is **R4-C's** commit (`D-p2-b`).
- **`D-w3`** — `manifest.json`'s other writers stay unlocked. Not fixed, not made worse (A13).
- **`D-v1f`** — the watcher's staging rewrite stays unlocked. See §5.3, which is why S3 takes **no**
  lock on `~/.claude.json`.
- **`D-p2-c`** — the import backup's file mode. Named, not fixed; the reference has the same bug.
- `cli-auth`, `D-l`, `D-m`, `install-rollback` — other items' rows.
- `parity-gate.sh` and `parity-fixture.sh` — **P4 owns both this wave.** Untouched.

---

## 3. S1 — one home, read from the environment

`ImportVerb.swift:22` is `(NSHomeDirectory() as NSString).appendingPathComponent(".claude.json")`.
The reference is `join(homedir(), '.claude.json')`, and `homedir()` reads `$HOME`.
`NSHomeDirectory()` does not: R2-W measured this and wrote it into "/// **`~/.claude.json` is resolved from `HOME` in the environment**, not from", `WatchPaths.swift:5-10` at `7babd97` — under
`HOME=/tmp/fakehome`, node returns `/tmp/fakehome` and `NSHomeDirectory()` returns the real account
directory.

**A2.1** The `--from` default resolves `HOME` from the process environment, falling back to
`NSHomeDirectory()` only when `HOME` is unset or empty — the exact rule `WatchPaths.init` uses. Same
fix, second of the two places that needed it.

**A2.2** `RouterHome` is derived from **that same resolved home**. `ImportVerb` currently calls
`RouterHome()` bare, which re-reads `NSHomeDirectory()`. The reference derives both from one
`homedir()` (`export const ROUTER_HOME = process.env.MCP_ROUTER_HOME`, `src/config.ts:79` at `7babd97`), so **two homes in one run is not a shape the reference can
produce** — the invariant "/// The router's own home, resolved from the **same** `HOME` as everything above.", `WatchPaths.swift:16-21` at `7babd97` records.

**This is not cosmetic and the first draft of this spec said it was.** `docs/install.sh:60,77` sets
`ROUTER_HOME="$HOME/.claude/mcp-router"` and then runs a **bare** `node dist/index.js import` — no
`MCP_ROUTER_HOME` in the environment. So the installer's invocation depends on `homedir()` for the
router home too, and A2.2 is exactly what `install-import-servers` measures. A lane that set
`MCP_ROUTER_HOME` would test a path the installer never takes and would leave A2.2 unobservable;
§6's lane therefore sets `HOME` only.

**A2.3 — a safety property, not only a parity one.** Without it, the moment a lane runs `import`
with no `--from` it adopts out of, and later steps rewrite, the developer's own `~/.claude.json` —
the reasoning `/// reference therefore *requires* reading the environment — and a watcher that did not`, `WatchPaths.swift:8-10` at `7babd97` records. This is why the row was blocked.

---

## 4. S2 — the import writer

"The `servers.json` writer is **atomic** and **preserves top-level keys it did not set**.", `spec-R1.md:148` at `7babd97` declares D3: the Swift `servers.json` writer is **atomic** and **preserves
top-level keys it did not set**, where the reference's writer *in `src/index.ts`* writes four keys
non-atomically. `ImportVerb.writeAdopted` (lines 113-131) does neither: it builds a fresh four-key
object and calls the mode-less `fileSystem.writeFile(_:atPath:)`.

**This is a third writer, not "the D3 writer".** The repo already has two, and conflating them is
how the mode gets set wrong:

| Writer | Stringify | Mode rule | Lock |
|---|---|---|---|
| `ConfigEdit.commit` (daemon) | `prettyTwoSpace`, **no** trailing newline | temp at `.fixed(0o600)` + rename → **always lands 0600** | yes |
| `WatchAdoption.merge` (watcher) | `prettyTwoSpace` **+ `"\n"`** | `.fixed(0o644)` | yes |
| **`ImportVerb.writeAdopted` (this)** | `prettyTwoSpace`, **no** trailing newline | **0600 only when the destination does not exist** | yes, new |

**A3.1 — preserve unknown top-level keys.** Read the existing `servers.json`; set `port`, `host`,
`idleMs`, `mcpServers`; leave every other top-level member in place, in its original position. A
file that is absent or does not parse as an object yields the four keys alone, so a first install is
unchanged. *Why it matters:* dropping `startupTimeoutMs` on a rewrite silently resets a supported
setting the user configured, which R1 wrote down eight items ago.

**A3.2 — atomic, and byte-identical to today.** Temp-plus-rename in the same directory, via
`WatchBackup.writeAtomic`. **The string passed in carries no trailing newline** — `JSON.stringify`
emits none and the current writer emits none, which is why `cli-import` is green. Adding one because
`WatchAdoption` adds one would redden a proven row. Likewise the `servers.json.bak-<epoch>` backup
and its `backed up existing config -> …` stdout line are unchanged.

**A3.3 — the mode rule, stated as an implementation constraint because two obvious ways to write it
are wrong.** The reference passes `{ mode: 0o600 }` to an **in-place** `writeFileSync`
(`{ mode: 0o600 }`, `src/index.ts:141` at `7babd97`). Measured on this machine, 2026-08-15:

```
in-place writeFileSync(dest, …, {mode:0o600}) over an existing 0644 file  ->  644
writeFileSync(tmp, …, {mode:0o600}) + renameSync(tmp, dest)               ->  600
```

Node's `mode` applies **only when the file is created**. So:

- `writeAtomic(…, mode: .fixed(0o600))` writes a **new inode** and therefore **always** lands 0600.
  Using it unconditionally would silently narrow every existing `0644` `servers.json` — the file
  holding every server's `env`, i.e. its API keys — on every import.
- `fileSystem.writeFile(dest, mode: 0o600)` is equally wrong in the other direction:
  `// O_CREAT honours the mode only when the file is new; an existing record keeps its old`, `FileModeWriting.swift:46-48` at `7babd97` **always `fchmod`s**, deliberately, so it too narrows an existing
  file. Neither call may be used bare.

**The rule:** resolve `.fixed(0o600)` when the destination does **not** exist, `.preserveExisting`
when it does. Both directions are tested (A5), because a one-directional test passes for the wrong
implementation.

Swift writing at the umask default today is an **undeclared divergence and a real defect** —
V1 found and fixed this class in `control.token` and the daemon's `servers.json`; this path was
missed because nothing reached it. Fixing it moves Swift *toward* the reference, so it is a
correction, not a divergence.

**A3.4 — hold the config mutation lock across the whole read-modify-write.** `servers.json` is the
file `ConfigMutationLock` exists for, and the import writer is the one writer that never took it.
The critical section is the **re-read, merge and write** — not the 60 s indexing pass — for exactly
the reason `/// Re-reading **inside** the lock is what makes a concurrent control-API PATCH survive:`, `WatchAdoption.swift:16-17` at `7babd97` gives: the object the delta is applied to must be the one
currently on disk. Reading outside the lock and writing inside it would let a control-API PATCH
landing in the window be clobbered by a stale snapshot, and A3.1's "preserved" keys would be
preserved from the wrong file.

`ConfigMutationLock.watcherTimeoutMs` (10 s), not the daemon's 2 s: `import` is a one-shot with
nothing waiting on it, and failing an import the user waited through a 60 s index for — because a
PATCH held the lock 100 ms — is the worse of the two failures.

**A3.5 — `cli-import` must stay green, and here is every way this change could redden it.** Checked
before writing a line: `cat > "$1/servers.json" <<JSON`, `parity-cli.sh:81-93` at `7babd97` — its `seed` writes a `servers.json` containing **exactly**
the four keys, so preservation has nothing to preserve there. The three live risks are the trailing
newline (A3.2), the backup filename and its stdout line (A3.2), and the file mode — which `seed`
creates at the umask default, so both sides take the `.preserveExisting` branch. Each is asserted,
not assumed.

---

## 5. S3 — the `~/.claude.json` router-entry rewrite

### 5.1 What the reference does

`if [[ -f "$CLAUDE_JSON" ]]; then`, `docs/install.sh:162-188` at `7babd97`, as one installer step:

1. `cp "$CLAUDE_JSON" "$CLAUDE_JSON.bak-mcp-router-$(date +%Y%m%d-%H%M%S)"`.
2. Parse the file.
3. `d.mcpServers = d.mcpServers || {}` — note `||`, so `null` and any other falsy value become `{}`.
4. Set `d.mcpServers["mcp-router"] = { type: "http", url: "http://127.0.0.1:${port}/mcp" }`.
5. Delete a legacy `d.mcpServers.router` **only if its `url` equals the new entry's** — an upgrade
   must not leave two entries on one endpoint, which would double every tool in the list.
6. Read the destination's mode; write `path + ".tmp"` at that mode; `chmod`; rename over.

### 5.2 Shape: a verb that backs up, and is absent from `help`

**A4.1** A verb `install-entry`, dispatched by `MCPRouterCLI.dispatch`, taking `--port` (default
`RouterHome.defaultPort`) and `--claude-json` (default: the S1-resolved `$HOME/.claude.json`).

**A4.2 — it performs step 1's backup itself.** The first draft left the backup in `install.sh` and
reproduced only the `node -e` script. That would ship an **undocumented verb that destructively
rewrites ~268 KB of live session state with no recovery** — a footgun for anyone who types it, and
the review was right that "the backup lives in the caller" is not an answer when the caller is a
file P2 may not edit. Folding the `cp` into the verb makes it equal to the whole installer step,
lets R4-C replace two lines with one, and leaves the net on-disk result identical. The backup name
reproduces install.sh's shape exactly, second-resolution collision included, because that is the
reference's behaviour and not P2's to improve.

**A4.3 — it does not appear in `Copy.usage`.** **`cli-help` is a `proven` row**, and
`run_both cli-help "help prints the usage block" -- help`, `parity-cli.sh:144-147` at `7babd97` compares `help`, `--help`, `-h` **and the unknown-verb arm** between the two
binaries. A line in the Swift usage block reddens it — trading one row for another and calling it
progress.

The review pressed on whether hiding is therefore "forced", and it is right that it is not: the
alternatives are (a) no verb at all, leaving R4-C's shell script with a library function it cannot
call, and (b) a visible verb plus a lane amended to ignore a line, which is weakening a test to make
a change pass. (a) does not deliver the row; (b) is the antipattern this repo names. So the verb is
hidden **and that is a compromise, not a necessity** — the honest statement of it is that
`install-entry` is an installer-internal step whose absence from a user-facing verb list is
defensible on its own, and that keeping `cli-help` green is the second reason rather than the only
one. Declared as **P2-D2** with a vector.

**A4.4 — `MCPRouterCLI.dispatch`'s own contract changes with it.** Its comment reads "one arm per
verb `src/index.ts` dispatches, and nothing else" (`/// The whole verb surface: the reference's, plus **one verb it does not have**.`, `MCPRouterCLI.swift:37-38` at `7babd97`). An eleventh verb
breaks that invariant, so the comment is rewritten in the same patch rather than left to read as a
promise the code no longer keeps.

**A4.5 — the unknown-verb arm keeps its contract.** `not-a-real-verb` still prints usage and exits 1
identically on both binaries.

### 5.3 The write, and why there is no lock on this file

**A4.6** The rewrite goes through `WatchBackup.writeAtomic(…, mode: .preserveExisting)` — R2-W's
writer, which already reproduces `statSync → write tmp at mode → rename`. `.preserveExisting` has
**no fallback mode** by deliberate design ("/// `~/.claude.json` — `statSync(CLAUDE_JSON).mode & 0o777` at", `WatchBackup.swift:57-64` at `7babd97`): if the file vanished mid-run
the `stat` throws and nothing is written, rather than recreating session state the user just
discarded. Inherited, not re-derived.

**A4.7 — no `ConfigMutationLock` on `~/.claude.json`, and this is a deliberate deviation from the
brief's instruction, taken with the reason on the record.** The brief says to use R2-W's sidecar
flock for this rewrite. That instruction is honoured where it bites — A3.4 puts the import's
`servers.json` write under it, which is the file with three writers and the one writer that was
missing. On `~/.claude.json` the same lock would exclude **nothing**:

- **Claude Code itself rewrites the file constantly and will never take an advisory lock of ours.**
  Temp-plus-rename (A4.6) is what actually protects that writer.
- **The Swift watcher's staging rewrite is unlocked** — `D-v1f`, which V1 left deliberately because
  closing it is a *new declared divergence and R4's call*.
- **Nothing else writes it.** Verified rather than assumed: no reference to `.claude.json` or
  `claudeJSON` exists anywhere under `app/Sources/MCPRouterUI` or `app/Sources/MCPRouterKit`, so the
  first draft's "the Mac app driving it while a script runs" was false.

What the lock **would** do is create `~/.claude.json.lock` — `0600`, never read, never deleted
("/// **The lock object is a sidecar, `servers.json.lock`, never `servers.json` itself", `ConfigMutationLock.swift:11-16` at `7babd97`) — a permanent new file in the user's home directory, next to a
document the installer itself describes as live session state, in exchange for excluding a verb
nobody runs two of. A lock believed to exclude more than it does is worse than no lock. Registered as
**`D-p2-a`**: neither writer locks this file, and giving both of them the lock is R4's call
alongside `D-v1f`.

### 5.4 Behaviour

**A4.8** Missing `~/.claude.json`: exit 0, write nothing, print one line. `install.sh` guards with
`[[ -f "$CLAUDE_JSON" ]]` and skips the node call, so "absent" must not be an error here either.

**A4.9** Unparseable: exit non-zero, write **nothing** — neither the file nor a backup. The node
script throws and `install.sh` inherits the failure. Never write anything derived from a parse that
failed, the rule "/// `~/.claude.json` is ~268 KB and holds live session state for every project on the", `WatchBackup.swift:5-7` at `7babd97` already states for this file.

**A4.10** `mcpServers` absent, `null`, or any other falsy value becomes a fresh object, matching
`||`. A **truthy non-object** (a string, a number, an array) is left in place and the member
assignment is a no-op that JavaScript performs silently; Swift reproduces the resulting file rather
than refusing. Note this differs from `WatchAdoption.serversObject`'s refusal (W-D7), which guards
`servers.json` — a different file whose reference behaviour is different. Two files, two rules,
stated so the next reader does not "unify" them.

**A4.11** Every other top-level key and every other `mcpServers` member keeps its position and
value. This is what makes the on-disk diff meaningful.

---

## 6. S4 — how each row gets measured

Written into `parity-install.sh` and `parity-divergence.sh` — **not** `parity-gate.sh` or
`parity-fixture.sh`, which P4 owns.

**A5.1 `install-import-servers`** — both binaries run `import` with **no `--from` and no
`MCP_ROUTER_HOME`**, each under its own scratch `HOME`, over an identical seeded
`$HOME/.claude.json`. That is `install.sh:77`'s invocation exactly. Compared: stdout, exit code, the
`servers.json` each wrote **at `$HOME/.claude/mcp-router/`** (which is itself the A2.2 assertion),
and its file mode.

Two sub-scenarios, because one hides half of A3.3: a **fresh** home, where both sides must create
the file at `0600`; and a home whose `servers.json` already exists at `0644`, where both sides must
leave it `0644`. Seeding first — which `cli-import`'s `seed()` does — makes the create path
invisible, so the fresh case exists precisely to see it.

**A5.2 `install-claude-json`** — one `~/.claude.json` fixture copied to two scratch homes. The
reference side runs `cp` plus the `node -e` script **extracted from `docs/install.sh` at run time**,
not a retyped copy: a hand-copied oracle drifts from the installer silently and would then certify
agreement with a script nobody runs. The Swift side runs `install-entry`. Compared: the resulting
file byte-for-byte, its mode, and that a backup exists whose bytes equal the pre-image.

Three scenarios, because one is a coincidence: no `mcpServers`; a legacy `router` entry whose url
matches (must be deleted); a `router` entry whose url does **not** match (must be kept). The third
exists because the delete is conditional and a lane that never sees the false branch has not tested
it.

**The caveat this row carries, and it is written into the manifest note, not only here.** The lane
drives the Swift binary against the installer's own extracted script under installer-equivalent
conditions. It does **not** run `docs/install.sh`, and after P2 the installer still invokes `node`.
That is the same standard `install-launchd-serve` is held to — `CAVEAT, printed into the gate's report: two real agents under real launchd supervision,`, `parity-install.sh:33-35` at `7babd97` states it
does not run the installer either, and that row reads `proven` — but the review argued the row
should stay blocked until R4-C flips the caller, and that argument is recorded in §11 rather than
resolved unilaterally by the runner who benefits from resolving it.

**A5.3 `div-r1-d3`** — a `servers.json` seeded with an extra top-level key (`startupTimeoutMs`, a
key the router genuinely supports, so the loss is real rather than synthetic). Both binaries run
`import`. **Three assertions, not one:** the reference dropped the key; Swift kept it; **and Swift
actually wrote** — its `mcpServers` equals the adopted set, not the seed's. Without the third, a
Swift side that threw and wrote nothing leaves the seed key in place, the files differ, and the row
goes green for the opposite of the reason it claims. Agreement **or** a Swift-side no-write is a
fail.

A5.3 measures the **preservation** half of D3 only. The **atomicity** half is A4's unit test, and
the row's note says so — "the writer is `WatchBackup.writeAtomic`" is identity, not evidence, and a
completed non-atomic write also leaves no partial file.

**A5.4 — the guard against the easy pass.** A lane that exits 0 having recorded nothing is an
environment failure, not a pass (`3. A lane that exits 0 having printed nothing did not run. A lane that produces no result`, `parity-gate.sh:20-23` at `7babd97`); the new lanes record through the same
`PARITY_RESULTS` mechanism. Each new lane is additionally **made to fail once, deliberately**, and
that is recorded in the evidence file.

**A5.5 — `cli-import` and `cli-help` are re-run and must still read `proven`.** Both are rows this
change could plausibly redden (A3.5, A4.3). Named here so the report cannot quietly omit them.

---

## 7. Acceptance criteria

| # | Criterion | How it is proven |
|---|---|---|
| A1 | `import`'s default `--from` follows `$HOME` | Unit test under a scratch `HOME`; `install-import-servers` |
| A2 | One resolved home feeds `~/.claude.json` **and** `RouterHome`, with `MCP_ROUTER_HOME` unset | Unit test; `install-import-servers` asserts the written path |
| A3 | `import` preserves unknown top-level keys | Unit test; `div-r1-d3` |
| A4 | `import`'s write is atomic | Unit test with a `FileSystem` that **fails between temp and rename**, asserting the destination is byte-identical to its pre-image |
| A5 | `import` creates `servers.json` at `0600` and leaves an existing file's mode alone | Two unit tests, both directions; both sub-scenarios of A5.1 |
| A6 | The lock is held across `import`'s **read**-modify-write | Unit test: a lock held by another descriptor makes the write fail `notAcquired`; a second asserting the merged output reflects a change written after the pre-index read |
| A7 | `import`'s output bytes are unchanged — no trailing newline, same backup name, same stdout | Unit test comparing to a recorded pre-image; `cli-import` |
| A8 | `install-entry` reproduces the installer step byte-for-byte, mode and backup included | `install-claude-json`, three scenarios |
| A9 | A legacy `router` entry is deleted **only** when its url matches | Scenarios 2 and 3 of A5.2 |
| A10 | Absent → exit 0, nothing written; unparseable → non-zero, **neither file nor backup** written | Two unit tests asserting the directory is unchanged afterwards |
| A11 | `mcpServers: null` becomes an object; a truthy non-object is left in place | Two unit tests |
| A12 | `install-entry` is absent from `help`; `cli-help` still `proven` | Unit test on `Copy.usage`; the row itself |
| A13 | `cli-import` still `proven` | The row itself, re-run |
| A14 | Parity coverage rises, measured before and after **from `.worktrees/P2` both times** | Full `parity-gate.sh` |
| A15 | No new `manifest.json` writer (`D-w3` not made worse) | Mechanical: `grep` the diff for `writeFile`/`writeAtomic` calls whose destination expression involves `manifestPath`, expecting none |

---

## 8. Declared divergences added by P2

| # | Divergence | Why | Vector |
|---|---|---|---|
| P2-D1 | The Swift binary has an **eleventh verb**, `install-entry`, which `src/index.ts` does not dispatch | The reference performs this step inline in `install.sh`. **R4-C removes Node from the installer entirely** (`spec-R4.md:257-261` — `swift build`, drop the Node 20 check, delete `package.json`), so the step cannot stay a `node -e` block. *(The first draft said "after the cutover there is nothing to run it", which was wrong: the `node -e` uses only `fs` and never loads `dist/`.)* | `install-claude-json` compares the on-disk result against the script extracted from `install.sh` |
| P2-D2 | `install-entry` is **absent from the usage block** | The reference's usage block has no such line; printing one diverges on `cli-help`, a proven row comparing all four help arms. A compromise, argued in §5.2 | `cli-help` stays `proven` (A12) |
| P2-D3 | `import` holds the config mutation lock across its `servers.json` read-modify-write; the reference takes none | R2-W's scheme extended to the one writer that never took it. Not a content difference; observable as a `servers.json.lock` sidecar | Declared so R4 does not read the sidecar as drift |
| P2-D4 | `install-entry` performs the backup that `install.sh` performs with `cp` | So the verb is the whole installer step rather than a destructive fragment (§5.2). Net on-disk result identical | `install-claude-json` asserts a backup with the pre-image bytes on **both** sides |

**Not divergences, corrections:** A3.3 (mode `0600` on create) and A3.1/A3.2 (preserve + atomic)
move Swift toward the reference and toward R1's already-declared D3. Recorded in the evidence file
as defects found.

---

## 9. Deferred children registered by P2

| # | Child | Absorbed by | Why |
|---|---|---|---|
| `D-p2-a` | **Neither** Swift writer of `~/.claude.json` takes the config mutation lock — not the watcher (`D-v1f`), not `install-entry` | R4, with `D-v1f` | Taking it in one of the two would exclude nothing and would put a permanent `~/.claude.json.lock` in the user's home. §5.3 |
| `D-p2-b` | `install.sh` still calls `node -e` for the rewrite, and still calls `node dist/index.js import` | R4-C | `docs/` is the published site of a public repo; the cutover commit is specified in `spec-R4.md`. P2 supplies the capability, R4-C flips the caller |
| `D-p2-c` | `import`'s `servers.json.bak-<epoch>` backup is written mode-less, so a `0600` config yields a world-readable backup of a file holding API keys | R4 | The reference has the identical bug ("writeFileSync(backup, readFileSync(DEFAULT_CONFIG_PATH));", `src/index.ts:135` at `7babd97`), so fixing it is a **new declared divergence** rather than a fix, and P2's job on this path is parity. Named rather than left for someone to find |

---

## 10. Review lane

`codex` is account-limited until 2026-08-20 by the owner's instruction; the lane is **grok-4.6**.

Smoke-tested before use, because grok exits 0 when session init fails (V1's finding): a probe on
2026-08-15 returned exit 0 with 40 bytes of real content identifying the model. Every gate asserts
**both** exit 0 **and** that the output contains review content, never `$?` alone.

Gates: spec review (below) · plan review · Phase D completeness critic. A grok failure falls back
in-family **with the downgrade logged**.

---

## 11. Disposition of the spec review

grok-4.6, exit 0, 12,486 bytes, 17 findings, **VERDICT: AMEND**. Four of its load-bearing factual
claims were **re-measured on this machine before any of them were accepted**, and all four held:
Node's in-place `{mode:0600}` leaves an existing `0644` file alone while tmp-plus-rename lands
`0600`; `// O_CREAT honours the mode only when the file is new; an existing record keeps its old`, `FileModeWriting.swift:46-48` at `7babd97` always `fchmod`s; nothing under `MCPRouterUI`/`MCPRouterKit`
mentions `.claude.json`; `ConfigEdit` writes no trailing newline where `WatchAdoption` writes one.

| # | Severity | Finding | Disposition |
|---|---|---|---|
| 1 | critical | `install-claude-json` is spent on a verb the installer does not call | **Partly accepted.** The capability is built and the lane written, because the row's own group is proven this way today (`install-launchd-serve` does not run `install.sh` either). The reviewer's argument is recorded in §6 and in the manifest note, and the status call is surfaced to the orchestrator rather than taken by the runner who benefits from it |
| 2 | critical | The `install-import-servers` lane set `MCP_ROUTER_HOME`, which the installer does not | **Accepted in full.** §3 A2.2 and §6 A5.1 rewritten: `HOME` only, no `MCP_ROUTER_HOME`, and the written path is now itself the assertion. This makes A2.2 measured instead of "currently unobservable" |
| 3 | high | Hiding the verb is a compromise, not forced; and a hidden verb that rewrites session state with no backup is a footgun | **Accepted.** §5.2 now says plainly that hiding is a compromise and gives both halves of the reason; A4.2 folds the backup into the verb (P2-D4) |
| 4 | high | "becomes the R1-D3 writer" mislabels it; `ConfigEdit` is that writer and lands 0600 always | **Accepted.** §4 now presents three writers in a table and names the mode branch as load-bearing |
| 5 | high | Implementer trap: `writeAtomic(.fixed(0o600))` and `writeFile(dest, mode:)` both narrow an existing file | **Accepted.** A3.3 states the rule and forbids both bare calls; A5 tests both directions |
| 6 | high | A5.3 passes when Swift never writes | **Accepted.** Three assertions now, including "Swift actually wrote" |
| 7 | high | A4 proved atomicity by naming a function | **Accepted.** A4 now injects a failure between temp and rename |
| 8 | high | Drop the `~/.claude.json` lock — it excludes nothing and leaves a permanent file in `$HOME` | **Accepted**, after verifying the claim that nothing in the app writes that file. §5.3 records this as a deliberate deviation from the brief's instruction, with reasons, and `D-p2-a` is reworded |
| 9 | high | Switching writers could add a trailing newline and redden `cli-import` | **Accepted.** A3.2 pins no-newline, the backup name and the stdout line; A3.5 enumerates all three risks; A7 is a new criterion |
| 10 | medium | The critical section must wrap the **read**, not just the write | **Accepted.** A3.4 and A6 rewritten |
| 11 | medium | A5.1 contradicted itself; seeding hides the 0600-on-create path | **Accepted.** Two sub-scenarios, fresh and pre-existing |
| 12 | medium | The `.bak-<epoch>` backup is written mode-less | **Accepted as a named non-goal** — `D-p2-c`. The reference has the same bug, so fixing it is a new divergence |
| 13 | medium | `mcpServers: null` is falsy and not covered | **Accepted.** A4.10 and A11 |
| 14 | medium | A13 (`git diff` inspected) cannot fail | **Accepted.** Now mechanical (A15) |
| 15 | medium | "after the cutover nothing runs it" is the wrong reason | **Accepted.** P2-D1 restated: R4-C removes Node from the installer |
| 16 | low | The coverage fraction is misstated | **Rejected with citation.** The gate's own summary line reads *"73 of 83 rows proven (4 of them by suite only), 9 blocked"*, and the group table sums to 73. The reviewer read `proven` and `proven-by-suite` as disjoint in the raw TSV; the gate counts them together and the spec quotes the gate |
| 17 | low | `MCPRouterCLI.dispatch`'s "nothing else" comment breaks | **Accepted.** A4.4 |
