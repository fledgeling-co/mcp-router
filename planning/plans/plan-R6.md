# plan-R6 — the PATH a spawned child inherits

Spec: `planning/specs/spec-R6.md`. Tier: Small. One new Swift file, three edited Swift
files, one edited TypeScript file, two new test files, one evidence file and one acceptance
script.

## Steps

**1 · `app/Sources/RouterCore/Pool/ChildPath.swift`** (new). A `DirectoryProbing` protocol
with two questions — the entries of a directory, and whether a path is a directory — plus a
`FileManager`-backed default. `ChildPath.userBinDirectories(home:probe:limit:)` returns the
sorted, deduplicated, capped list; `ChildPath.augment(_:home:probe:)` returns the merged
PATH string. Acceptance: A2, A6.

A dedicated probe rather than `RouterCore`'s `FileSystem`: that protocol has seven
implementations, and adding a method to it to answer one question would edit six test
doubles that do not care about PATH.

**2 · `StdioUpstreamTransport`.** Take `environment` and a probe as defaulted init
parameters, in the shape the rest of `RouterCore` uses for `environment:`. Resolve the
augmented environment **once, in `init`** — one transport is built per router start, so the
scan costs one directory listing for the life of the process — and pass it both to
`resolve(command:environment:)` and to the child. The server's own `env` still merges last.
Acceptance: A1, A3.

**3 · `PoolError.commandNotFound(name:command:searchedPath:)`.** `message` returns
`spawn <command> ENOENT`; `description` names the command, the directory count and the two
fixes. `spawnFailed` keeps every other use. Acceptance: A5.

**4 · `src/pool.ts`.** The same rule in `buildEnv`: read `$HOME`, list it, keep entries whose
`bin` is a directory, sort by UTF-8 bytes, cap at 64, append the ones the inherited PATH
lacks. Synchronous `fs` calls, as the surrounding file already uses, memoised by home so the
scan does not run on the event loop once per spawn. Acceptance: A1, A7.

**5 · Tests.** `app/Tests/RouterCoreTests/ChildPathTests.swift` drives the probe with a fake:
discovery, the file-named-`bin` case, dedup against the inherited PATH, append-not-prepend,
empty components surviving, byte ordering, the cap, an absent home, an empty PATH — and the
wire-text guard, which asserts `PoolError.commandNotFound.message` is exactly
`spawn foo ENOENT` and is the one to break deliberately and watch go red.
`ChildPathSpawnTests.swift` writes an executable into a scratch home's `.fixture/bin` and
asserts resolution fails under the bare PATH and succeeds under the augmented one, then
spawns a real child through both. Acceptance: A2, A4, A5, A6, A7.

**6 · `scripts/acceptance/r6-child-path.sh`.** Starts each router under a scratch `HOME`
containing `.fixture/bin/mcpr-r6-fixture`, with a launchd-like five-entry PATH, and reads
`PATH=` off the spawned child. Compares the two routers' child PATH strings. Acceptance: A7,
A8.

**7 · `planning/evidence/R6-acceptance.md`.** The `PATH=` lines before and after, the command
that read them, the SHA. Acceptance: A8.

## Test seams

`ChildPath` takes its probe, so discovery is unit-testable without a filesystem.
`StdioUpstreamTransport` takes `home` and `environment`, so a test can present a launchd-like
environment without touching the developer's own. The acceptance script uses `HOME` and a
scratch directory, never the user's home.

## Gates

`make lint`, `make build-mac`, `make test`, `npm run build`, then the acceptance script
against both routers. `make parity` to show the census is untouched and no lane moved.

## Open

Three deferred children came out of the out-of-family review and are written up in
`spec-R6.md` §9 and §10: `D-r6-a` and `D-r6-b`, two pre-existing defects in
`StdioUpstreamTransport.resolve` about relative commands and empty PATH components, and
`D-r6-c`, the owner's call on whether a discovered directory should be rejected for its owner
or its mode.

The 64-directory cap is a judgement call with no measurement behind the number; 9 were found
on the machine this was written on. It exists to bound `execve`'s environment, not because a
larger home was observed.

Whether a router-level setting should exist for an unusual prefix is left open in the spec
and not built. The per-server `env.PATH` override already covers it, and nothing measured
says a second mechanism is needed.
