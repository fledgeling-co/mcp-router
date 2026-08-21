# R7 — acceptance evidence

Branch `ai/r7`. Spec `planning/specs/spec-R7.md`, plan `planning/plans/plan-R7.md`.
Everything below was taken on the author's machine on **2026-08-21**. No harness config was
written at any point, by this item or by this lane; see spec §7.

## A4 — the measurement, reproduced from the shipped binary

The brief's table was produced by hand with `python3 -c` against four files. This is the same
question asked of `mcp-router harnesses`, which is the criterion:

```
$ ./app/.build/debug/MCPRouterCLI harnesses
    router on 127.0.0.1:8879 — 13 upstream(s)

    Claude Code
      /Users/lukerhodes/.claude.json
      wired via HTTP, and carrying 1 duplicate direct upstream(s)
      speaks streamable HTTP — measured on claude, 2026-08-21: ~/.claude.json carries type:http and the router serves this repository's own sessions through it
      the router already serves:
        namecheap
      Remove the duplicate entries below; the router already serves them.

    Claude Desktop
      /Users/lukerhodes/Library/Application Support/Claude/claude_desktop_config.json
      not wired
      speaks streamable HTTP — taken on documentation: Anthropic's desktop MCP documentation; no binary was probed here
      Point this harness at http://127.0.0.1:<port>/mcp.

    Codex CLI
      /Users/lukerhodes/.codex/config.toml
      not wired — 1 of its 5 servers are ones the router already fronts
      speaks streamable HTTP — measured on codex 0.146.0, 2026-08-21: `codex mcp add <NAME> --url <URL>` documents a streamable HTTP MCP server; links rmcp-1.8.0 streamable_http_client
      the router already serves:
        docker-mcp
      Point this harness at http://127.0.0.1:<port>/mcp.

    ChatGPT CLI
      /Users/lukerhodes/Dev/mcp-router/.worktrees/R7/.chatgpt/config.toml
      no config file — this harness is not configured on this machine

    Cursor
      /Users/lukerhodes/.cursor/mcp.json
      not wired
      speaks streamable HTTP — measured on cursor-agent 2026.08.11, 2026-08-21: shipped bundle selects type "streamableHttp" when the mcp.json entry carries a url
      Point this harness at http://127.0.0.1:<port>/mcp.

    Gemini CLI
      /Users/lukerhodes/.gemini/settings.json
      wired via a stdio shim (mcp-remote), and carrying 12 duplicate direct upstream(s)
      speaks streamable HTTP — measured on agy 1.1.17, 2026-08-21: embeds mcp.StreamableClientTransport from the Go MCP SDK; server config struct carries json:"httpUrl"
      the router already serves:
        mobbin
        Ref (the router calls it ref-tools-mcp — same command, different name)
        namecheap
        docker-mcp
        dossier
        google-search
        media-gen-pro
        yt-transcript
        sift
        lifeline
        obscura
        ai-elements
      This harness speaks streamable HTTP: point it at the router directly and drop the shim. Remove the duplicate entries below; the router already serves them.

    grok
      /Users/lukerhodes/.grok/config.toml
      wired via HTTP, and carrying 1 duplicate direct upstream(s)
      speaks streamable HTTP — measured on grok 1.0.5, 2026-08-21: links rmcp-2.1.0 streamable_http_client and documents [mcp_servers.<name>] url
      the router already serves:
        mobbin
      Remove the duplicate entries below; the router already serves them.

    opencode
      /Users/lukerhodes/.config/opencode/opencode.json
      no config file — this harness is not configured on this machine

    Global scope only: project-scoped entries are not read (R7-C4).
    Nothing here writes a harness config. The plans below apply themselves to nothing.

    Claude Code — /Users/lukerhodes/.claude.json
      - remove  namecheap   (the router already serves it)
      nothing applies this plan — see planning/specs/spec-R7.md §7
    Claude Desktop — /Users/lukerhodes/Library/Application Support/Claude/claude_desktop_config.json
      + add     mcp-router   (this router's endpoint)
      nothing applies this plan — see planning/specs/spec-R7.md §7
    Codex CLI — /Users/lukerhodes/.codex/config.toml
      - remove  docker-mcp   (the router already serves it)
      + add     mcp-router   (this router's endpoint)
      nothing applies this plan — see planning/specs/spec-R7.md §7
    Cursor — /Users/lukerhodes/.cursor/mcp.json
      + add     mcp-router   (this router's endpoint)
      nothing applies this plan — see planning/specs/spec-R7.md §7
    Gemini CLI — /Users/lukerhodes/.gemini/settings.json
      - remove  mobbin   (the router already serves it)
      - remove  Ref   (the router already serves it)
      - remove  namecheap   (the router already serves it)
      - remove  docker-mcp   (the router already serves it)
      - remove  dossier   (the router already serves it)
      - remove  google-search   (the router already serves it)
      - remove  media-gen-pro   (the router already serves it)
      - remove  yt-transcript   (the router already serves it)
      - remove  sift   (the router already serves it)
      - remove  lifeline   (the router already serves it)
      - remove  obscura   (the router already serves it)
      - remove  ai-elements   (the router already serves it)
      ~ replace router   (stdio shim -> direct HTTP)
      nothing applies this plan — see planning/specs/spec-R7.md §7
    grok — /Users/lukerhodes/.grok/config.toml
      - remove  mobbin   (the router already serves it)
      nothing applies this plan — see planning/specs/spec-R7.md §7

```

Three of those rows contradict the brief, and the contradiction is the point of having a verb
rather than a paragraph:

- **Claude Code**, which the brief recorded as "1 router entry — working as designed", carries a
  duplicate today (`namecheap`). The exempt harness drifted into the defect state in six days, on
  the machine the brief was written on. That is the brief's own rule 2 happening.
- **grok** was never audited and is wired via HTTP, carrying one duplicate.
- **Gemini** carries **12** duplicates, not the brief's ten. Eleven match by name; `Ref` matches
  the router's `ref-tools-mcp` by config identity, both hashing to `30da6798334b2466`.

## A1, A2, A5, A6 — unit

`app/Tests/RouterCoreTests/HarnessReconciliationTests.swift`, 22 cases, all green:

```
Test run with 22 tests in 1 suite passed after 0.004 seconds.
```

The two duplicate cases in it are transcribed from the machine and they point opposite ways:
Gemini's `Ref` is invisible to a name comparison, grok's `mobbin` is invisible to an identity
comparison. Neither basis alone is correct here, which is why both run and each duplicate records
the basis that found it.

## A3, A8 — red-green, and the arming that makes it mean something

`scripts/acceptance/r7-harness-reconciliation.sh`, in `make acceptance`:

```
r7: a fixture harness carrying three duplicates
  ok    duplicateCount = 3
  ok    the names = obscura,dossier,Ref
  ok    state = wired-with-duplicates
  ok    route = stdio-shim
r7: the same harness after reconciliation
  ok    duplicateCount = 0
  ok    the names =
  ok    state = wired-shim
  ok    route unchanged = stdio-shim
r7: arming - the same three entries against a router that fronts nothing
  ok    duplicateCount = 0
  ok    state = wired-shim
r7: the harness fixture was not modified by the run
  ok    the file this lane wrote is the file that is still there

r7-harness-reconciliation: pass
```

The third pass is the one that stops the first two being a pair of numbers that agree with the
fixture that produced them: the harness still declares three duplicates and the router fronts
nothing, so the only correct answer is zero. A detector that counts the harness's own entries
answers three there.

**The lane was shown able to go red**, by changing `byName.contains(entry.name)` to `true` so the
comparison counts every harness entry, rebuilding, and re-running:

```
  FAIL  duplicateCount: expected 3, got 4
  FAIL  the names: expected obscura,dossier,Ref, got github,obscura,dossier,Ref
  FAIL  duplicateCount: expected 0, got 1
  FAIL  state: expected wired-shim, got wired-with-duplicates
  FAIL  duplicateCount: expected 0, got 4      <- the arming pass
r7-harness-reconciliation: 7 failing check(s)
```

The mutation was reverted and the lane returns to `pass`.

## A7 — the write seam is empty, and a gate keeps it empty

`scripts/lint/no-harness-config-writes.sh`, in `make lint`:

```
no-harness-config-writes: 22 file(s) name a harness config, none writes one
```

**Shown able to go red**, by appending a function to `ReconciliationPlan.swift` that writes a
rendered plan to `~/.gemini/settings.json`:

```
no-harness-config-writes: a harness config path appears beside a write:
  .../Discovery/ReconciliationPlan.swift:90: try fileSystem.writeFile(... "/.gemini/settings.json")
exit=1
```

It also exits 2 rather than 0 when it finds no file naming a harness config at all, because a gate
whose pass and whose could-not-run look identical is not a measurement.

## Two defects the verb found in code that already built and passed

Both were found by running the thing against the real machine rather than against its own fixtures,
and both are recorded because the second is the more dangerous shape.

1. **`MiniTOML` refused `~/.grok/config.toml` outright**, on `[[marketplace.sources]]` at line 8 —
   an array of tables in a section that has nothing to do with MCP servers, eighteen lines above
   the `[mcp_servers.router]` entry that answers the question. It then refused the same file again
   on a multi-line `args` array inside a server table. Arrays of tables are now refused **only**
   under a server table name, where guessing would change what a server is, and a value whose
   brackets do not balance consumes continuation lines. Both are still errors where they are
   genuinely ambiguous, and `parse` gained tests for the refusing direction as well as the reading
   one.
2. **An unread config produced a confident wrong plan.** Because the reader failed, grok arrived at
   `ReconciliationPlan.from` as "not wired with no entries", and the plan offered to **add** a
   router entry to a harness that was already wired via HTTP. `from` now returns an empty plan when
   the file is absent or unreadable. Absence of evidence proposes nothing — and the failure that
   made it visible was in an unrelated parser, which is how a reading defect turns into a writing
   recommendation.

## What is not established

- Every "speaks streamable HTTP" row except Claude Code's is a **capability claim about a shipped
  binary** — a symbol and a config key found in the artifact — not an end-to-end connection. The
  distinction is carried in `HTTPCapability` rather than only here.
- **opencode is `.unknown`** and displays as unknown. It has no config on this machine and its
  launcher is a shim whose bundle was not probed. R7-C3.
- **Project-scoped entries are not read.** `~/.claude.json` carries 8 more across 5 projects and
  Codex has `[projects.*]`. The verb prints the scope it read rather than letting a global-only
  count read as a whole-machine one. R7-C4.

---

# The gap-fix — three findings closed, 2026-08-21

Verified at `metamorphic`, **Needs More Work**, three blocking (`R7-gapfix.md`). Everything above
still reproduces: the real-machine measurement below is byte-identical to §A4's, so all three
*contradicts-the-brief* rows stand unchanged.

## F1 — Gemini is wired on `httpUrl`, and the reader could not see it

`HarnessRoute.detect` read `url` and nothing else, so `.wiredViaHTTP` was **unreachable for
Gemini** — the harness this item exists for. The block printed `json:"httpUrl"` as its own evidence
and three lines later failed to read an `httpUrl` entry, reported `not wired`, and emitted a plan
offering to add a router entry to an already-routed harness. Self-triggering: the remedy told the
user to create the state the tool could not read.

`HarnessDialect` now carries the endpoint spellings **per client** — `["url", "httpUrl"]` for
Gemini, `["url"]` for everything else, on the same rule `HTTPCapability` follows, because reading
Gemini's key out of a Cursor file is a claim about Cursor that nothing has established. Endpoints
must be strings. Detection tests every spelling, so a decoy `url` cannot hide a real `httpUrl`.
`ServerParser` and `UpstreamHash` are untouched; the harness entry is normalised to `url` at this
seam, and it is the **raw** JSON that is normalised because `UpstreamHash` digests
`raw.member("url")` rather than the parsed value.

**Red-green, three mutations, each restored from a `cp` backup:**

| Mutation | Result |
|---|---|
| Gemini's `endpointKeys` back to `["url"]` | unit **24 of 38 tests red**; lane **8 failing checks** — `route: expected http, got none`, `state: got not-wired`, and `no + add line for a harness that is already wired: expected 0, got 1`, which is the original defect reproduced verbatim |
| `detect` back to `entry.raw.member("url")` | unit red, 9 issues over 5 tests |
| the comparison no longer canonicalises | lane **5 failing checks** — `duplicateCount: expected 4, got 3`, and the `httpUrl` duplicate reads `ABSENT` |

All three restored, all green.

## F2 — `--json` can say "could not be read"

`unreadable` carries the parser's own sentence, or JSON `null`. The verb's doc comment says to read
it first, because the rest of that row is the empty report and a consumer switching on `state`
alone still sees a clean unwired harness (`D-r7-l`).

The lane asserts **both directions and the binding between them**: a readable config carries
`null`, an unreadable one carries a reason, the whole empty row is pinned (`state`,
`duplicateCount`, `entries`), and the screen must carry the *same sentence* the wire does — so a
field hard-coded to any plausible string fails. Dropping the member from the encoder gives
**3 failing checks**, including `a readable config carries no reason: expected null, got MISSING`.

## F3 — the write-boundary gate enforces what it claims, and declares what it cannot

Both rules were line-scoped. A realistic applier — path on one line, `write(toFile:)` on a later
one — exited 0 with `none writes one`, while `ORCHESTRATOR.md` cited the gate as the reason the
refusal holds. Now:

- both rules are **file-scoped**, over comment-blanked code (line numbers preserved);
- a third rule refuses **any** file write inside the seam — `RouterCore/Discovery`,
  `HarnessesVerb.swift`, and any `Harness*`/`Reconciliation*`/`ClientConfig*` file anywhere —
  which catches an applier that names nothing recognisable;
- the write vocabulary is **argument labels** (`forWritingTo:`, `forUpdatingTo:`,
  `forUpdatingAtPath`, `toFileAtPath:`, `OutputStream(`, `/bin/cp`…), so `FileHandle(forWritingTo:)`
  and `FileHandle.init(forWritingTo:)` are the same call to it;
- printing is neutralised **within** a line rather than the line being dropped, so a trailing
  `// FileHandle.standardOutput` no longer erases a real write;
- eight **pattern-integrity probes** run before any file is read, so a gutted pattern exits 2
  instead of passing everything.

```
no-harness-config-writes: 313 file(s) examined, 8 name a harness config, 20 write a file,
                          8 in the seam — none writes one
exit=0
```

`scripts/lint/no-harness-config-writes-selftest.sh`, in `make lint` beside its subject, **13 cases**:

```
  ok    a tree with no applier passes (exit 0)
  ok    P1  a harness path literal beside a write, one line, is refused (exit 1)
  ok    P2  a reconciliation plan beside a write, one line, is refused (exit 1)
  ok    P3  a realistic applier, path and write on different lines, is refused (exit 1)
  ok    P4  a bare-String applier inside the seam is refused by the seam rule (exit 1)
  ok    P5  forWritingTo: is the only write token in the file, and counts (exit 1)
  ok    P8  forUpdatingTo: is the only write token in the file, and counts (exit 1)
  ok    P9  a harness path in a block comment is documentation too (exit 0)
  ok    P10 a split applier outside the seam is NOT caught — the gate's declared blind spot (exit 0)
  ok    P6  a harness path discussed in a doc comment is documentation, not a write (exit 0)
  ok    P7  writing to standard output is printing, not writing a config (exit 0)
  ok    a tree naming no harness config at all is an environment failure, not a pass (exit 2)
  ok    a tree with an empty seam is an environment failure, not a pass (exit 2)

no-harness-config-writes-selftest: 13 case(s) held
```

**P3 is the verifier's plant that walked through, and it now exits 1.** **P10 asserts that the gate
misses something** — a split applier across two neutrally-named files outside the seam — so the
limit is visible from a run rather than from a paragraph, and closing it turns this file red on
purpose. `D-r7-m`.

**Six mutations of the gate's own rules, each turning the selftest red:**

| Mutation | Result |
|---|---|
| rule 1 back to line-scoped | red — and the gate exits **2**, refusing to run, because a probe no longer matches |
| rule 2 back to line-scoped | red — **P3 exits 0**: the realistic applier walks through again |
| the seam rule stops reporting | red — P4 exits 0 |
| `forWritingTo:` dropped from the vocabulary | red at exit 2 — the pattern probe refuses |
| `forUpdatingTo:` dropped | red at exit 2, same reason |
| comment blanking removed | red — P9 and P10 exit 1, the gate fires on documentation |

## The gates, re-run whole

| Gate | Result | Exit |
|---|---|---|
| `swiftformat --lint` | `0/507 files require formatting` | 0 |
| `swiftlint --strict` | `Found 0 violations, 0 serious in 500 files` | 0 |
| `swift test` (`make test`) run 1 | `executed 1621 tests` | 0 |
| `swift test` (`make test`) run 2 | `executed 1621 tests` | 0 |
| `make parity` | `358 vector cases compared (floor 358)` | 0 |
| `parity-lock-selftest` | `12 held, 0 did not` | 0 |
| `parity-normalise-selftest` | `14 behaved, 0 did not` | 0 |
| `parity-manifest-selftest` | `the MCP SDK is not installed` — **blocked, not passed** | 2 |
| `no-raw-design-values` | `clean` | 0 |
| `no-wire-codable` | `2 exemption(s) recorded` | 0 |
| `no-harness-config-writes` | `313 examined … none writes one` | 0 |
| `no-harness-config-writes-selftest` | `13 case(s) held` | 0 |
| `r7-harness-reconciliation.sh` | `pass`, 27 checks over five passes | 0 |

`make test` was run twice deliberately: `PoolReapingTests.swift:61` is non-deterministically red
under whole-suite load (`G3`). **It did not flake in either run**, on top of two earlier runs in
the same session that also passed — four green runs, no reds.

`make lint` and `make all` remain blocked at the `tools` guard in a fresh worktree with no
`node_modules`; the six lint steps were run individually and all pass. `parity-manifest-selftest`
is blocked for the same missing SDK. Both are recorded as blocked rather than as passes.

## A4 re-taken from the rebuilt binary

`./app/.build/debug/MCPRouterCLI harnesses` against the machine's real configs is **byte-identical
to §A4 above** — the same five states, the same 12 Gemini duplicates, the same `Ref` on the
identity basis. The dialect fix changes nothing on this machine, and that is the correct outcome:
this machine's Gemini reaches the router through the `mcp-remote` shim, not through `httpUrl`. It
changes what happens the moment the user follows the tool's own printed advice — *"point it at the
router directly and drop the shim"* — which is exactly the state the old reader could not see.

Every row of `--json` now carries `"unreadable": null`, and the eight rows are otherwise unmoved.

---

# Second gap-fix — the file R7 had never opened

Taken **2026-08-21**, after `R7-gapfix-2.md`. Everything below is read-only against the machine's
own configs, and the digest at the end proves it.

## B1 — which file, measured rather than assumed

`agy` 1.1.17 moved its MCP configuration out of `~/.gemini/settings.json` on 14 Aug and left the
old file behind. Both exist here, and they disagree:

| | `~/.gemini/settings.json` | `~/.gemini/config/mcp_config.json` |
|---|---|---|
| servers | 18 | 20 |
| member keys | `command`, `args`, `env` | `serverUrl` ×6, `command` ×14, `args` ×14, `env` ×7, `headers` ×3 |
| the router entry | `npx -y mcp-remote http://127.0.0.1:8879/mcp` | `serverUrl: http://127.0.0.1:8879/mcp` |
| mtime | 14 Aug 18:27 | 16 Aug 00:51 |

`agy mcp list` prints the second file exactly — twenty rows, with `router`, `diolog-admin`,
`diolog-tasks`, `linear`, `mobbin` and `pocketsmith` typed `http`. `~/.gemini/config/.migrated`
(14 Aug 10:47, zero bytes) marks the move. The only MCP config paths in the shipped binary are
`.gemini/config/mcp_config.json` and `config/mcp_config.json`; `~/.gemini/settings.json` appears in
it only as the settings file, and its own changelog names the legacy path as a **fixed bug**:
*"pressing the `[Disable]` button wrote to the legacy `mcp_config.json` path instead of the
migrated `config/mcp_config.json` path"*.

## The Gemini row, from the shipped binary

```
Gemini CLI
  /Users/lukerhodes/.gemini/config/mcp_config.json
  wired via HTTP, and carrying 12 duplicate direct upstream(s)
  the router already serves:
    mobbin
    Ref (the router calls it ref-tools-mcp — same command, different name)
    namecheap
    docker-mcp
    dossier
    google-search
    media-gen-pro
    yt-transcript
    sift
    lifeline
    obscura
    ai-elements
  Remove the duplicate entries below; the router already serves them.
```

```json
{"harness": "geminiCLI", "path": "/Users/lukerhodes/.gemini/config/mcp_config.json",
 "exists": true, "unreadable": null, "state": "wired-with-duplicates", "route": "http",
 "entries": 19, "duplicateCount": 12}
```

**The count, defended against the harness's own answer.** `agy mcp list` prints 20 rows. One is
the router, which `entries` excludes, leaving 19. Twelve of those the router already fronts; the
seven it does not are `agy-plugins`, `chrome-devtools`, `diolog-admin`, `diolog-tasks`, `github`,
`linear` and `pocketsmith`. 12 + 7 = 19. Two of the seven — `diolog-admin` and `diolog-tasks` —
exist only in the migrated file, so the same arithmetic against `settings.json` cannot reach 20 at
all, which is the arithmetic pass 1 was doing.

**What changed in the answer.** Before: `wired via a stdio shim (mcp-remote) — one child process
per session`, 12 duplicates over 17 entries, and a plan proposing
`~ replace router (stdio shim -> direct HTTP)` — a migration the user performed on 14 Aug. After:
`wired via HTTP`, 12 duplicates over 19 entries, and no replacement proposed. The other seven
harness rows are unmoved.

## The read-only boundary, on the real files

```
$ shasum -a 256 ~/.gemini/settings.json ~/.gemini/config/mcp_config.json   # before
$ ./app/.build/debug/MCPRouterCLI harnesses --port 8879
$ ./app/.build/debug/MCPRouterCLI harnesses --port 8879 --json
$ shasum -a 256 ~/.gemini/settings.json ~/.gemini/config/mcp_config.json   # after
→ identical
```

## Gates, second pass

| Gate | Result | Exit |
|---|---|---|
| `swiftformat --lint` | `0/509 files require formatting` | 0 |
| `swiftlint --strict` | `Found 0 violations, 0 serious in 502 files` | 0 |
| `make test` #1 | `1642 tests in 202 suites passed` | 0 |
| `make test` #2 | `1 issue` — `CallbackLifecycleTests.swift:238`, an unrelated bind race | 1 |
| `make test` #3 | `1642 tests in 202 suites passed` | 0 |
| `make test` #4 | `1642 tests in 202 suites passed` | 0 |
| `make parity` | `358 vector cases compared (floor 358)` | 0 |
| `no-raw-design-values` | `clean` | 0 |
| `no-wire-codable` | `2 exemption(s) recorded` | 0 |
| `no-harness-config-writes` | `313 examined, 8 name a harness config, 20 write a file, 8 in the seam — none writes one` | 0 |
| `no-harness-config-writes-selftest` | `22 case(s) held` | 0 |
| `r7-harness-reconciliation.sh` | `pass`, 55 checks over ten passes | 0 |
| `make lint` | **blocked** at the `tools` guard — `node_modules is missing` | 2 |

`make test` run #2's failure is `a listener binds once — reuse is refused rather than quietly
racing`, which binds a loopback TCP port and raced under whole-suite concurrency. It is **0 of 8**
in isolation and 3 of 4 green under the full suite, and nothing in this diff touches a listener.
Registered as `D-r7-x` rather than re-run away from. `PoolReapingTests` (`G3`) did not flake in any
of the four runs.

---

# Third round: out-of-family review of the second pass's own diff

Three families were asked to review the diff before it was reported ready. Two delivered on the
first attempt, one was down, and the fourth family was substituted for it rather than retrying.

| Lane | Header proving how it ran | Bytes | Verdict |
|---|---|---|---|
| OpenAI — `codex exec` | `model: gpt-5.6-sol` · `reasoning effort: high` · `sandbox: read-only` | 4,327 | six findings, all on the shell gate |
| Google — `agy` | `--model gemini-3.7-flash-high` (effort baked into the model id) | 4,469 | three findings, all on the Swift seam |
| xAI — `grok` | — | **0** | lane down: empty output and empty log at a 16.5 KB packet, having already failed at 64 KB. Reported once and substituted |
| Anthropic (substitute) — `claude` | `--model claude-fable-5 --effort high` | 5,783 | four findings; independently reproduced Google's endpoint-comparison one |

Nine distinct findings across the three lanes. **Six were taken**, two were overruled on a
measurement, and one was registered as deferred.

## Taken — the seam

**A stdio entry was being promoted to HTTP by its own leftovers.** `HarnessDialect.resolve` rewrote
any non-standard endpoint key to `url` without asking what the entry was. `ServerParser` selects the
transport from a truthy `url` whenever `type` is absent, so an entry of `{"command": "uvx", "args":
[…], "serverUrl": "http://…/stale"}` was digested as an HTTP upstream: the stdio duplicate against
the router's own stdio server was lost, and a false HTTP one could be invented against whatever sat
at the stale address. The route rule already knew this entry was stdio; the comparison did not ask
it. It asks now, through the same predicate.

**Two spellings differing only in a trailing slash were called a conflict.** `endpointPath` folds a
single trailing slash, so the route rule and the conflict rule disagreed about whether `/mcp` and
`/mcp/` are one endpoint — and the entry went to `unparsed`, which is B4's silent loss arriving
through formatting instead of a decoy. Endpoints are now compared normalised, and `JSURL` supplies
scheme, host and port so host case and a default port fold with it.

**One trailing slash is tolerated; two are not.** The old loop stripped every one, so
`http://127.0.0.1:8879/mcp///` read as this router. `new URL()` keeps `/mcp//` as `/mcp//` and a
router serving `/mcp` answers 404 there, so folding it claimed a route that does not exist.

## Taken — the gate

**The comment reader was wrong in both directions at once, and the first direction was silent.**
`let marker = " /*"` is a Swift string containing a slash-star; the reader opened a block on it and
blanked every line after it to end of file, so an applier under one reported clean. That is the
vacuity this gate exists to refuse, arriving through the gate's own stripper. The mirror image: a
`//` inside a URL string was read as a line comment and suppressed the real block opener after it,
so a file documenting what it refuses to do became a finding. The reader now tracks the string
state, which is the rule Swift itself applies, and both directions are cases.

**The relink group was named routes rather than the property.** `createSymbolicLink`, `createLink`
and `setAttributes` were in the vocabulary; `symlink`, `link`, `chmod`, `rename` and `truncate` were
not, so the same mutation in its POSIX spelling walked through. The reviewer called this the
diff's own defect in miniature and was right.

**Three of the widened path names were generic enough to refuse this product.** `settings.json`,
`config.toml` and `mcp.json` are among the commonest file names in software, and rule 1 fires across
all 313 sources, so a file writing its own `config.toml` became a finding with no suppression
comment to answer it. Those three now count only where a harness home is named too. The distinctive
names — `mcp_config.json`, `claude_desktop_config.json`, `.claude.json`, `opencode.json` — still
count alone.

**The probes did not establish what the header claimed.** The wrapped-call probe contained no
newline, so it proved the pattern tolerated whitespace while never exercising the line-joining it
was added for; one subject matched two vocabulary entries and could not discriminate them; and five
subjects were counted against twenty-two alternatives under a header saying every entry was probed.
There is now a subject per alternative and a closure check that splits `SEAM_MUTATING` on `|` and
exits 2 for any alternative no subject matches. **It failed on its first run** — `link\(` had no
subject — which is the check doing its job before anything else did.

## Overruled, on a measurement rather than a preference

**"`url` should leave Gemini's dialect, because agy's error string names only `command` and
`serverUrl`."** The inference is that the error string enumerates the accepted keys. It does not:
`strings -a ~/.local/bin/agy` returns `json:"httpUrl"` as a struct tag on the same binary, and that
key appears in neither the error string nor the help text. So the prose is not an enumeration, and
dropping `url` would risk reporting a working config as not wired and then offering to wire it —
which is F1, the self-triggering defect this whole item exists for. Kept, with the reasoning.

**"`endpointPath`'s two-slash limit diverges from `JSURL`'s WHATWG slash-skipping."** Conditional in
the reviewer's own words, and measured false: `JSURL.authority` consumes `while consumed < 2`, with
a comment giving the reason (`file:///tmp/x` has an empty host and a path of `/tmp/x`). For
`http:///host/mcp` the authority is empty, which `JSURL` rejects outright for a special scheme other
than `file`, so `isThisRouter` refuses at its first guard and the path reader is never consulted.
The two halves agree, and a test now says so in both directions.

## Deferred

`D-r7-y` — a name duplicate is settled before an entry's endpoints are read, so a conflict inside
one is never reported. The entry is still counted, so nothing goes silently to zero; what is lost is
a second finding about an entry already reported.

## Arms for the third round

| Arm | Mutation | Red |
|---|---|---|
| P1 | the stdio guard removed from `resolve` | unit: `(found.duplicates.count → 0) == 1`. Lane: `FAIL a stdio entry with a stale endpoint is still the stdio server it is: expected 1, got 0` |
| P2 | endpoints compared raw again | unit: `found.unparsed → ["m: declares two different endpoints — url=http://127.0.0.1:9999/x and serverUrl=http://127.0.0.1:9999/x/ …"]`, and `duplicates.count → 0`. Lane: two checks, including `a readable entry was reported unreadable` |
| P3 | `isStdio` reads a display string again | `(found.route → .notWired) == .directHTTP(name: "r", url: "http://127.0.0.1:8879/mcp")` |
| P4 | the path reader insists on `://` again | 3 issues over 2 suites, first `(endpointPath(of: "http:/127.0.0.1:8879/mcp") → "") == "/mcp"` |
| P5 | every trailing slash folded again | `(endpointPath(of: "http://127.0.0.1:8879/mcp//") → "/mcp") == "/mcp/"`, and `isThisRouter` returning true for it |
| gate | the whole pre-panel gate, against the new selftest | **4 of 27 cases** — P19, P20, P21, P22, each with the reviewer's exact failure; P20b passed both ways, as the control direction it is |

**Arm P1 passed on its first run, and the arm was the thing at fault.** The unit fixture named the
harness entry the same as the router's upstream, so it matched on name and `HarnessDialect.resolve`
was never reached — `D-r7-y`, met in the test written to guard against the defect beside it. The
entry is now named `browser` against an upstream named `fetch`, so the identity basis is what is
being exercised, and the arm goes red at both levels. The acceptance lane's own version of this
check was written with the rename from the start.

## Gates, third round

| Gate | Result | Exit |
|---|---|---|
| `swiftformat --lint .` | `0/509 files require formatting` | 0 |
| `swiftlint --strict` | `Found 0 violations, 0 serious in 502 files` | 0 |
| `swift test` #1 | `1648 tests in 202 suites passed` | 0 |
| `swift test` #2 | `1648 tests in 202 suites passed` | 0 |
| `make parity` | `358 vector cases compared (floor 358)` | 0 |
| `no-raw-design-values` | `clean` | 0 |
| `no-wire-codable` | `2 exemption(s) recorded` | 0 |
| `no-harness-config-writes` | `313 examined, 8 name a harness config, 20 write a file, 8 in the seam — none writes one` | 0 |
| `no-harness-config-writes-selftest` | `27 case(s) held` | 0 |
| `r7-harness-reconciliation.sh` | `pass`, 59 checks over eleven passes | 0 |
| `make lint` | **blocked** at the `tools` guard — `node_modules is missing`, the same recorded block as passes 1 and 2. All six of its steps run individually above | 2 |

`D-r7-x`'s bind race did not recur in either run. The real machine re-measures unchanged —
`~/.gemini/config/mcp_config.json`, `wired-with-duplicates`, route `http`, 19 entries, 12
duplicates, `unparsed: []`, and 19 + the router entry is `agy mcp list`'s twenty rows. Both real
Gemini configs are byte-identical before and after every run in this round.

**One process note worth carrying.** `swiftformat --lint . 2>&1 | tail -2; echo exit=$?` reported
`exit=0` over a failing run, because `$?` was `tail`'s. That is the same mistake the brief names for
gate logs, one command shorter, and it hid a real `wrapFunctionBodies` violation until the gate was
re-run unpiped. Capture the exit code from the tool, then read the log.
