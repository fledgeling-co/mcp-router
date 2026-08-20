# R6 — acceptance evidence

**Item:** R6 — the PATH a spawned child inherits · **Branch:** `ai/r6`
**Worktree:** `.worktrees/R6` · **Date:** 2026-08-21 · **Base:** `e642f65`

Append-only. Each row names how a thing was verified, at which commit, and the result. A later
runner reads this before re-testing: a row whose files have not changed since its SHA is the
evidence.

This item has **no SwiftUI surface**. It changes the environment a stdio child inherits, in both
routers. No app was launched, no window was driven, and nothing took the user's screen.

---

## 0 · The user's live router was never contacted

`gg.rhodes.mcp-router` was listening on 8879 as `node 98273` before this work started and was
still holding it after. The parity lanes below ran on 8971 and 8990–8999, and every lane refuses to
start if its port is already listening. The acceptance lane binds no port at all — it indexes a
fixture server under a scratch `HOME` and `MCP_ROUTER_HOME`, both inside its own `mktemp`
directory.

**The user's launchd plist was read and not written.** It is worth recording that it has been
hand-edited since the brief was filed: its PATH now leads with
`/Users/lukerhodes/.local/bin:/Users/lukerhodes/.grok/bin`, and `docs/install.sh` still generates
the five-entry list, so a reinstall discards that edit. This item does not touch the installer, so
the hand-edit is neither preserved nor destroyed by it.

## 1 · The PATH line, before and after

The brief asked for the evidence in the form it was found: the actual `PATH=` a child saw.

Read off a real child spawned by `mcp-router index` under a scratch home, at both routers, by
`scripts/acceptance/r6-child-path.sh`. The fixture `mcpr-r6-fixture` exists in exactly one place —
`$SCRATCH_HOME/.fixture/bin` — and the routers are given the PATH `docs/install.sh` writes into
the plist.

**Before** (the same routers, with a home holding no `bin` directory — the pre-change environment
reproduced rather than remembered):

```
no child started: spawn mcpr-r6-fixture ENOENT
```

**After**, identical at both routers, compared as strings:

```
PATH=/Users/lukerhodes/.nvm/versions/node/v22.23.1/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/var/folders/b3/hwz3nk4d1kz8x6mzk7qrbpsc0000gn/T/r6-child-path.VDrv2RR4Ed/home/.fixture/bin
```

The launchd entries keep their order and their place at the front; the discovered directory is
appended.

## 2 · What was run

| # | Check | How | Result |
|---|---|---|---|
| 1 | The acceptance lane | `./scripts/acceptance/r6-child-path.sh` | `examined=6 failures=0`, exit 0 |
| 2 | The lane can fail | The node half's `augmentPath` call replaced by a passthrough, rebuilt, re-run | `failures=2`, exit 1, naming `node: no child started` and `the two routers disagree`. Restored, re-run: `failures=0`, exit 0 |
| 3 | Swift unit and real-process tests | `swift test --filter ChildPath` | 14 tests in 2 suites passed |
| 4 | The full Swift suite | `make test` | 1543 tests in 193 suites passed |
| 5 | Lint | `make lint` | 0 violations in 486 files; `no-raw-design-values` clean; `no-wire-codable` clean |
| 6 | Mac app builds | `make build-mac` | `** BUILD SUCCEEDED **` |
| 7 | TypeScript builds | `npm run build` | exit 0, no diagnostics |
| 8 | Vector parity | `make parity` | 358 vector cases compared, floor 358 |
| 9 | Census untouched | `./scripts/acceptance/parity-manifest-check.sh` | 83 rows, consistent; the pin did not move |
| 10 | Pool lane | `./scripts/acceptance/parity-pool.sh` (POOL_PORT=8971) | 5 decisions match, 0 do not |
| 11 | CLI lane | `./scripts/acceptance/parity-cli.sh` | 17 verbs agreed, 0 did not — including `cli-import`, the row that diffs the `spawn <cmd> ENOENT` text |

Rows 1, 3, 4, 5, 10 and 11 were run again after the review fixes in §4 and are reported at their
second values. Rows 6, 7, 8 and 9 were run once, before those fixes; 7 was re-run (`tsc` exit 0)
because `src/pool.ts` changed.

## 3 · The three mutations, each seen to fail

SWIFT_PRACTICES §7: a test that has never failed is not known to work. Each mutation was applied,
the suite run, the named assertion observed red, and the source restored.

| Mutation | Assertion that reddened |
|---|---|
| `PoolError.commandNotFound.message` returns `could not find <cmd>` | `(error.message → "could not find aseprite") == "spawn aseprite ENOENT"` — the parity guard |
| `ChildPath.augment` prepends instead of appending | 5 issues across both suites, including the real child's PATH losing `hasPrefix(launchdPath)` |
| `ChildPath.augmentedEnvironment` returns its input unchanged | The red-green test's green half, and the real spawn threw `upstream "seeing" could not be started: spawn mcpr-r6-fixture ENOENT — "mcpr-r6-fixture" is not in any of the 4 directories on the router's PATH.` |

## 4 · The out-of-family review, and what it changed

`codex exec -m gpt-5.6-sol` at high effort, briefed to refute rather than approve and told that
finding nothing is a failed review. Its output is at `/tmp` and its findings are reproduced below
because four of them changed the code. A second lane (`grok -m grok-4.6 --effort xhigh`) was
started in parallel and was killed by the 10-minute wall clock with only its narration written; it
had independently reached "sort and join already disagree", which is finding 2. That lane is
recorded as **incomplete**, not as a pass.

| Finding | Severity claimed | Disposition |
|---|---|---|
| `resolve` runs before `currentDirectoryURL` is set, so a relative command resolves against the router's cwd rather than the child's | HIGH | **Confirmed, pre-existing, deferred** as `D-r6-a`. It is R2's pre-check, unchanged by this item, and the fix is about relative paths rather than PATH |
| Swift `String` ordering and JavaScript's `Array.sort` disagree above the BMP, so the two routers can build different PATHs and select different directories at the cap | HIGH | **Confirmed and fixed.** Measured: node's default sort puts `.\u{1F600}` before `.\u{E000}` and byte order puts `.\u{E000}` first. Both routers now sort by UTF-8 bytes |
| Discovered directories are not checked for symlink target, owner or mode | MEDIUM | **Answered, not fixed** — `spec-R6.md` §9 carries the argument, `D-r6-c` carries the owner's override |
| Empty PATH components are dropped, where `execvp` reads one as the current directory | MEDIUM | **Confirmed and fixed** in `augment` and `augmentPath`; the same defect inside `resolve` is pre-existing and deferred as `D-r6-b` |
| The 64-entry cap bounds the PATH but not the scan, which ran per spawn and blocked node's event loop | MEDIUM | **Confirmed and fixed.** Swift resolves once per transport, which is once per router start; node memoises by home |
| The lane's red half accepted any failure, so a crash or a timeout would have reported `ok` | MEDIUM | **Confirmed and fixed.** It now asserts the exact `spawn mcpr-r6-fixture ENOENT` text and prints the exit status |

The hardened red half was seen to fail: with the before-arm's command changed to `false`, which
resolves and then does not handshake, the lane reports
`FAIL: before: no child started, but not for the reason this lane is about (exit 0)` and exits 1,
printing the 60-second timeout it actually hit. Before the fix that run reported `ok`.

The UTF-8 sort in Swift is defensive rather than corrective and is recorded as such: Swift's own
`sorted()` already agrees with byte order (measured — both put `U+E000` first), so no mutation of
the Swift comparator alone can redden its test. The divergence lived on the node side, and that is
where the fix bites.

## 5 · The measurements behind the mechanism

Taken on this machine, 2026-08-21, and recorded because `spec-R6.md` §2 rejects the brief's own
first two candidates on them.

| Command | Result |
|---|---|
| `env -i HOME=… PATH=<launchd's> /bin/zsh -l -c 'echo $PATH'` | real 1.69s, 607 bytes, `~/.local/bin` present, **`~/.grok/bin` absent** |
| the same with `-i` | real 14.43s, both present |
| `grep -n grok/bin ~/.zshrc` | `128:export PATH="$HOME/.grok/bin:$PATH"` — a login non-interactive zsh does not read it |
| `command -v` for the five named CLIs | `claude`, `codex`, `cursor-agent`, `agy` in `~/.local/bin`; `grok` in `~/.grok/bin` |
| `bin` directories under `$HOME` and its dot-directories | 9, in 0.05s |

## 6 · What is not established

The lane proves the child's PATH under `mcp-router index`. It does not drive `serve` with an MCP
call, because the pool's spawn path is the same code and `parity-pool.sh` already compares the two
routers' spawn decisions over live traffic on the reference side.

Nothing here establishes that a real routed server — `dossier`, the one the brief measured —
now finds `claude`. That needs the user's own router restarted on this build, which is a merge-time
observation rather than a branch one.
