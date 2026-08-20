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
