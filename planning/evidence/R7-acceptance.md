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
