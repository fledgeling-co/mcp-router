# R7 gap-fix 2 — the Gemini harness reads a file R7 has never opened

**Parent:** R7 — The router's thesis is unmet for every harness but Claude Code
**Status:** Untriaged · gap-fix, second pass
**Verdict that produced it:** Needs More Work, 2026-08-21, rung `effect-witness`
**Worktree:** `.worktrees/R7`, branch `ai/r7`, base `fd8ae22`

## Why there is a second pass

The first gap-fix closed F1 by adding `httpUrl` to Gemini's endpoint-key list. That is a
route. The property F1 was filed for is *R7 reports the truth about the Gemini harness*, and
it is still false — one level above where anyone was looking. R7 reads
`~/.gemini/settings.json`; `agy` reads `~/.gemini/config/mcp_config.json`; and the key in
that file is neither `url` nor `httpUrl` but `serverUrl`.

This is the shape M23 bounced on twice — closing the route a finding named rather than the
property behind it — arriving in the item whose verifier was briefed to look for it.

## B1 — the blocking finding

Measured on this machine, twice, by the verifier and again independently:

| | `~/.gemini/settings.json` | `~/.gemini/config/mcp_config.json` |
|---|---|---|
| servers | 18 | 20 |
| member keys | `command`, `args`, `env` | `serverUrl` ×6, `command`, `args`, `env`, `headers` |
| the router entry | `npx -y mcp-remote http://127.0.0.1:8879/mcp` | `serverUrl: http://127.0.0.1:8879/mcp` |
| mtime | 14 Aug 18:27 | 16 Aug 00:51 |

`diolog-admin` and `diolog-tasks` exist only in `mcp_config.json`, so R7 cannot see two of
the twenty servers the harness runs. `url` and `httpUrl` appear **zero** times in it.
`serverUrl` and `mcp_config` appear **zero** times in this repository.

Four independent lines say `mcp_config.json` is the file `agy` reads: its changelog string
(*"for managing MCP servers in your user-level `mcp_config.json`"*), its help text
(*"`serverUrl` (string, required)"*), its error string (`MCP server %q must have either
command or serverUrl`), and its struct tags. `~/.gemini/config/.migrated`, dated 14 Aug,
marks the migration that moved it. `agy mcp list` reflects `mcp_config.json` exactly — 20
rows, with `router`, `mobbin`, `linear` and `pocketsmith` typed `http`, a transport
`settings.json` cannot express.

The consequence is not a cosmetic mislabel. R7 currently reports the Gemini harness as
*wired via a stdio shim (mcp-remote) — one child process per session*, counts 12 duplicates
over 17 entries, and proposes `~ replace router (stdio shim -> direct HTTP)` — advising a
migration the user performed on 14 Aug. The verifier settled it at `effect-witness`: during
a live `agy` session, seven stdio MCP children spawned and **zero** processes referenced
`127.0.0.1:8879`. The shim R7 reports does not exist.

## What to build

Resolve Gemini's config the way `agy` resolves it, rather than at a fixed path. Both files
exist on this machine and they disagree, which is the case the fix has to get right — a
straight path swap breaks a pre-migration install, and preferring the older file is what
produced this finding.

The endpoint-key work from pass 1 stands and needs `serverUrl` added to Gemini's dialect.
Keep the per-client `HarnessDialect` shape: a `serverUrl` key leaking into Cursor or Codex
detection is F1 inverted a second time, which is the defect all three panel lanes caught in
pass 1.

`ClientConfigs.swift:100` and spec §1.2 both name `agy` as this harness, so the spec needs
the same correction — leaving it naming `settings.json` reproduces the defect for the next
reader.

## Three more blockers, all reproduced by the verifier

**B2 — rule 3's header overclaims, and five appliers walk through it.** The header says the
gate refuses *"any file write at all inside the seam … however the path was obtained"*.
Against a copy of `app/Sources` (baseline exit 0, two controls exit 1), five plants exited
**0**: a wrapped `ClientConfigs.path(` call; a path built by chained
`.appendingPathComponent`; an `fopen`/`fputs` applier inside `RouterCore/Discovery`; a
`Process` running `/bin/sh -c '… > target'` inside the seam; and a write on a line opening
with a block comment. The wrapping case is the one that will happen by itself — this repo's
own `line_length: warning 110` pushes calls onto second lines. The block-comment case is the
trailing-comment evasion `file_writes` was hardened against, left open one function along in
`code_lines`, and selftest P9 asserts only the benign direction of that blanking. This is the
same class of header overclaim F3 was filed for, so fix the header or fix the gate — and say
which in the commit.

**B3 — an unrouted harness reads routed.** `{"health":{"command":"curl","args":["-s",
"http://127.0.0.1:8879/health"]}}` reports `state=wired-shim route=stdio-shim entries=0`.
No MCP route exists; a health-check curl makes the tool declare the harness wired and the
entry vanishes from the count. Separately `{"fs":{"command":"npx","args":[…],"url":"http://
127.0.0.1:8879/mcp"}}` reports `state=wired-http route=http entries=0`, because `detect`
tests endpoint keys before `command`, so a leftover URL beats a live stdio server.

**B4 — a decoy `url` erases a real duplicate.** With router upstream `mobbin`,
`{"Mobbin":{"httpUrl":"https://api.mobbin.com/mcp"}}` gives `duplicateCount=1`; adding
`"url":"https://decoy.example/mcp"` gives `duplicateCount=0, unparsed=[]`. The
`declaredURL?.isEmpty != false` guard returns before canonicalising, so the entry is neither
counted as a duplicate nor reported unreadable — which spec §4 forbids in those words:
*"never silently counted as no-duplicate"*. `D-r7-p` records the same guard's other face as
*"the right answer for a yes/no question"*; B1's evidence contradicts that note, since agy's
HTTP transports are `serverUrl` and `httpUrl`, never `url`. Correct the note with the fix.

## Acceptance

Each fix argued as a property, and the acceptance naming a route nobody has named yet. The
route nobody named here is the live one: **both Gemini config files present and disagreeing.**
That is this machine's actual state and neither pass has an assertion for it.

1. A Gemini config wired on `serverUrl` reports wired, over HTTP, with no shim — and the
   router entry is not proposed for replacement. Red before, green after.
2. With both files present and disagreeing, R7 reports the harness `agy` actually runs. Name
   in the test which file wins and why.
3. With only `settings.json` present, R7 still reads it. A pre-migration install must not
   regress.
4. A `serverUrl` key in a Cursor or Codex entry does **not** read as an endpoint. The
   per-client dialect holds under the second key just as it holds under the first.
5. B2: either the five walk-throughs exit 1, or rule 3's header states what it actually
   checks. Whichever you choose, the five plants are in the selftest as cases.
6. B3: a `command` entry whose args merely mention the router endpoint is not `wired`. A
   stdio server carrying a stale `url` is not `wired-http`.
7. B4: the decoy-`url` shape reports either a duplicate or an unreadable entry, never a
   silent zero.
8. `duplicateCount` over the real `mcp_config.json` is a number you can defend against
   `agy mcp list`'s twenty rows.

## Bundle claims to correct rather than repeat

Three of pass 1's stated numbers did not survive re-measurement: the lane passes at **29**
`ok` lines, not 27; the Gemini-keys mutation **crashes the bundle** (`Fatal error: Index out
of range`, signal 5, `HarnessDialectTests.swift:163`, `found.duplicates[0]` unguarded)
rather than turning 24 of 38 tests red; and `D-r7-m`'s "an applier split across two files
walks through" understates it — five appliers walk through, three inside the seam, none
split across files.

## Scope

`app/Sources/RouterCore/Discovery/`, the R7 verb and its dialect, the write gate and its
selftest, `planning/specs/spec-R7.md` §1.2, and the R7 acceptance lane. Do not touch
`ServerParser` or `UpstreamHash` — pass 1's reasoning holds: both are shared with adoption,
`import`/`watch` and the TypeScript reference, and `UpstreamHash` digests `raw.member("url")`
rather than the parsed value, so an entry parsed from one key and hashed from another
digests a null endpoint and misses its own twin. Normalise at the seam as pass 1 does.

`D-r7-r` … `D-r7-w` are registered and deferred; do not take them.
