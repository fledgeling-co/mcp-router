# R6: the PATH a spawned child inherits

**Category:** router · **Brief:** `planning/features-to-triage/R6-child-process-path.md`
**Depends on:** nothing. Independent of R4-C.

The router hands every stdio child the environment launchd handed it. Launchd's PATH is
whatever the installer wrote into the plist, and the installer writes a fixed five-entry
list, so a routed MCP server cannot execute a developer CLI that lives under the user's
home. This spec makes the routers add the user's own tool directories to a child's PATH by
a rule that is written down, and names the missing-command failure as its own error.

## 1 · What was measured

The brief's measurement, 2026-08-15: the listening router ran with
`PATH=/Users/lukerhodes/.nvm/versions/node/v22.23.1/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`,
and `~/.local/bin` and `~/.grok/bin` were absent. Five installed CLIs — `claude`, `codex`,
`cursor-agent`, `grok`, `agy` — were unreachable to every child, and the `dossier` server
running as a child reported all five `NOT INSTALLED` while holding successful probes for
three of them in its own cache.

Four measurements taken while writing this spec, on the same machine, 2026-08-21:

| What | Result |
|---|---|
| Where the five CLIs live | `claude`, `codex`, `cursor-agent`, `agy` in `~/.local/bin`; `grok` in `~/.grok/bin` |
| `env -i PATH=<launchd's> /bin/zsh -l -c 'echo $PATH'` | 1.69s, 607 bytes, **`~/.grok/bin` absent** — a login non-interactive zsh does not read `~/.zshrc`, and `~/.grok/bin` is set at `.zshrc:128` |
| The same with `-i` instead of `-l` | 14.43s, both directories present |
| `bin` directories under `$HOME` and its dot-directories | 9, found in 0.05s: `.bun` `.cargo` `.docker` `.grok` `.lifeline` `.local` `.omlx` `.resend` `.yarn` |

The user's live plist has been hand-edited since the brief was filed — its PATH now leads
with `~/.local/bin:~/.grok/bin` and it carries an extended attribute the installer does not
write. `docs/install.sh` still generates the five-entry list, so the next reinstall
discards that edit.

## 2 · The mechanism, and why the brief's first two candidates were rejected

**Both routers augment the PATH a stdio child inherits with every `bin` directory that
exists directly under `$HOME` or under one of `$HOME`'s dot-directories, appended to the
inherited PATH in sorted order, skipping any already present.**

The brief ranked its candidates 1 (bake the resolved PATH into the plist at install time),
2 (resolve a login-shell PATH at router start), 3 (per-server config). The measurements
above rule out the first two as written.

Candidate 2 fails on its own terms here: `$SHELL -l -c 'echo $PATH'` under a launchd-like
environment does not return `~/.grok/bin`, one of the two directories the brief names,
because zsh reads `~/.zshrc` only for an interactive shell. The variant that does return it
costs 14.43 seconds, and this router is `launchctl kickstart -k`'d every time the watcher
adopts a server. A mechanism that pays a user's shell startup on every restart and still
half-misses the defect it was chosen for is not worth its failure modes.

Candidate 1 fixes both routers at once and needs no router code, which is why the brief
ranked it first, but it freezes whatever happened to be on `$PATH` in the terminal that ran
the installer — on this machine that included per-session directories from a Claude Code
plugin cache — and it goes stale the moment a tool is installed. It also changes the bytes
of the generated plist, which the `install-launchd` and `install-launchd-watch` parity
lanes compare, and the second of those is the row this fleet has already spent two items
stabilising. `docs/install.sh` is therefore left alone.

Candidate 3 stays available and unchanged: a server that declares `env.PATH` still
overrides the router's PATH completely, because the server's own environment is merged
last. That is the escape hatch for a prefix this rule does not find.

The rule chosen executes no shell, reads no rc file, and costs one directory listing plus
one `stat` per dot-directory. It is self-updating in the sense that matters: install a tool
that creates `~/.newtool/bin` and the next router start finds it, with no reinstall.

**The merge policy is append-only, and that is the load-bearing half.** The inherited PATH
keeps its order and its position at the front; discovered directories go after it, and a
directory already present is not added twice. So no command that resolved before the change
can resolve to a different binary after it — the change can only add capability. Prepending
would let a version manager under `$HOME` capture `node` and `npx` for every child,
including servers the installer never exercised, and the measured defect is a missing
binary rather than a wrong one.

Ordering is sorted and deduplicated so the two routers produce the same string from the same
home directory, and so the string does not depend on directory-enumeration order.

At most 64 discovered directories are added. A home directory with thousands of
dot-directories would otherwise build a PATH long enough to matter to `execve`, and a cap
with a number in it is easier to reason about than an unbounded loop.

## 3 · Where it applies

Both routers, identically, so the change declares no divergence.

- **Swift** — `ChildPath` in `RouterCore`, called from `StdioUpstreamTransport`. Every path
  that spawns a child goes through that one transport: `serve`, `index`, `import`, the
  watcher's indexer and the control API's re-index.
- **TypeScript** — `UpstreamPool.buildEnv` in `src/pool.ts`, the one place the reference
  builds a child environment.

`src/` was unfrozen by the owner for R8 (`2a4e811`, ledger row R8) and the same reasoning
holds here: the reference is still installable as `MCPR_ROUTER=node`, so a defect fixed only
in Swift leaves the fallback broken and buys a divergence row the parity census would have
to carry. Neither router's own PATH changes; only the environment handed to children.

## 4 · The early resolution check must search the same PATH

`StdioUpstreamTransport` resolves the command itself before spawning, because it spawns
through `/usr/bin/env` and `env` always exists — without the pre-check a missing command
becomes a 60-second startup timeout rather than an immediate error (R2's finding, recorded
at `planning/evidence/R2R-acceptance.md:190`). That check reads `PATH` out of the router's
own environment today.

It must read the augmented PATH instead. A pre-check that searches a narrower PATH than the
child gets would reject a command `/usr/bin/env` would have found, which is the defect this
item exists to close, rebuilt inside the fix for it.

## 5 · The missing-command error

`PoolError` gains `commandNotFound(name:command:searchedPath:)`, replacing the use of
`spawnFailed` at the pre-check.

The **wire text does not change**. `PoolError.message` is what `mcp-router import` and the
control API report, and for this failure it is `spawn <command> ENOENT` byte for byte,
because that is what Node produces and what the `cli-import` comparison diffs. Changing it
would redden a parity row over a rewording.

`description` — which is not on the wire, and which `UpstreamPoolReaping` already logs
through the existing `warm upstream "x" did not start: <reason>` line — says what happened
and what to do:

> `upstream "aseprite" could not be started: spawn aseprite ENOENT — "aseprite" is not in any of the 14 directories on the router's PATH. Install it, or give this server an absolute command.`

The directory count is observed, not asserted: it is the length of the PATH actually
searched. `searchedPath` carries that PATH for tests and for anything that later wants to
print it.

No new log event and no new wire field. `PoolLogEvent`'s copy is normative against the
reference (`PoolLogEvent.swift:9`), and a Swift-only line at a code point the reference does
not have would be a divergence needing a census row — which would move `# rows:` and force
`PARITY_CUTOVER_TARGET`, a number the owner set on 2026-08-16. That is not a runner's to
move for a log line.

## 6 · What renders

Nothing new. The Servers board already renders a failed server's `indexError`, and the
mocks already carry this exact string — `design/mocks/html/f3-connection-states.html:470`
reads `spawn ENOENT — aseprite is not on PATH`. The wire text is unchanged, so no surface
changes and no screen needs re-verifying.

## 7 · Acceptance

- **A1** A child spawned by either router sees a PATH whose entries are the inherited PATH
  in its original order, followed by the discovered directories not already present.
- **A2** The discovery finds `bin` under `$HOME` and under each dot-directory of `$HOME`,
  skips a `bin` that is a file rather than a directory, skips a dot-directory with no `bin`,
  sorts, deduplicates, and stops at 64.
- **A3** The pre-spawn command resolution searches the augmented PATH, so a command that
  exists only in a discovered directory resolves.
- **A4** Red-green: a fixture executable reachable only through a discovered directory fails
  to resolve under the un-augmented PATH and resolves under the augmented one, in the same
  test, with both directions asserted.
- **A5** A command that resolves nowhere produces `PoolError.commandNotFound`, whose
  `message` is exactly `spawn <command> ENOENT` and whose `description` names the command,
  the number of directories searched, and what to do.
- **A6** A missing `$HOME`, an unreadable `$HOME`, and an empty inherited PATH each yield a
  PATH rather than an error.
- **A7** The Swift and TypeScript implementations produce the same PATH string from the same
  home directory and the same inherited PATH, asserted by running both.
- **A8** `PATH=` read off a real router process under a launchd-like environment, before and
  after, recorded in `planning/evidence/R6-acceptance.md`.

## 8 · What this does not do

A server that resolves its own dependency by shelling out through a *shell* rather than
through `PATH` is unaffected, and so is one that reads `~/.zshrc` itself. The router can only
control the environment it hands over.

The discovery rule finds `~/.tool/bin`. It does not find a prefix like `/opt/custom/bin` or
`~/Library/Something/bin`, and there is no config key for one — the per-server `env.PATH`
override is the answer, and it is the third of the brief's candidates left in place. Whether
that deserves a router-level setting is a real question and is deliberately unanswered here;
nothing measured says it is needed.

The router's own PATH is unchanged, so the router still finds `node` and `launchctl` exactly
where the plist says. Fixing the plist itself remains available and is not done here.

## 9 · The permission question, answered rather than omitted

A discovered directory is not checked for its symlink target, its owner or its mode. That was
raised by the out-of-family review as a way for another local user to plant a command a routed
child would then execute, and it is a real mechanism. It is not guarded here, for two reasons and
one that cuts the other way.

Every directory added is inside `$HOME`. Anyone who can write into `~/.tool/bin` can already write
`~/.zshrc`, which executes in every terminal the user opens, so the router grants no access that is
not already granted — and macOS creates home directories at `0700`. The append-only ordering means
no command that already resolved can be shadowed; the exposure is limited to a command that is
absent today.

The reason it cuts the other way: a router that silently skipped a group-writable `~/.local/bin`
would reintroduce this item's defect invisibly, which is the failure mode the brief was filed
about. A guard that cannot say why it declined is worse here than no guard.

What the router does gain is continuous exposure: an interactive shell has to be opened, and the
daemon is always running. That is the residue, and it is the owner's to overrule — registered as
`D-r6-c`.

## 10 · Deferred children

Two pre-existing defects in the same function, both found by the out-of-family review of this
change and neither introduced by it. They are recorded rather than fixed because both are about
relative-path resolution rather than PATH augmentation, and both change behaviour the parity
harness has rows for.

- **D-r6-a** — `StdioUpstreamTransport.resolve` checks a relative `command`, and any relative PATH
  entry, against the **router's** working directory. The child runs in `upstream.cwd`, and the
  reference resolves against it because Node's spawn does the lookup after the `chdir`. So a
  config of `{command: "./bin/server", cwd: "/tmp/project"}` works at the reference and is refused
  here, and the converse passes the pre-check and then times out.
- **D-r6-b** — the same function drops empty PATH components, where `execvp` reads an empty entry
  as the current directory. Its own bug, and it can only be fixed alongside `D-r6-a` because the
  fix is the same missing piece of information.
- **D-r6-c** — the permission question in §9, for the owner rather than a runner.
