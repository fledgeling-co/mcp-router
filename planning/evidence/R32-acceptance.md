# R32 — Claude Desktop takes the config and has no live reload

Every measurement below was taken on 2026-08-28 against **Claude Desktop 1.30096.1**
(`/Applications/Claude.app`, `CFBundleShortVersionString` and `CFBundleVersion` both `1.30096.1`),
by reading `Contents/Resources/app.asar` — 38 MB, minified, read as bytes. Nothing here launched
Claude Desktop, drove it, or wrote to the owner's config.

Tree: `972b875`.

## 0. The starting state, re-measured

    $ ls -l ~/Library/Application\ Support/Claude/claude_desktop_config.json
    -rw-------@ 1 lukerhodes  staff  1441 12 Aug 15:27 …/claude_desktop_config.json
    $ head -2 …/claude_desktop_config.json
    {
      "mcpServers": {},

1,441 bytes, mode `0600`, `mcpServers` empty. The rest of the file is the owner's window state,
account preferences and editor paths — which is why the writer carries every member it does not own
through untouched and re-stringifies rather than reconstructs.

## 1. The finding that reshapes the easy half

Desktop validates each `mcpServers` entry against one zod object. Quoted from the bundle:

    xb = P({command:A(),args:N(A()).optional(),env:I(A(),A()).optional(),extensionId:A().optional()})

`P` is `z.object`, `A` `z.string`, `N` `z.array`, `I` `z.record`. **`command` is required, and there
is no `url` and no `type`.** The record type that reads the file is `Sb = I(A(), xb)`, reached from
the app-config schema as `mcpServers: I(A(), xb).optional()`.

An entry that fails `safeParse` is not an error: it is **filtered out and reported in a dialog**.
The bundle carries the copy —

    The following entries in claude_desktop_config.json are not valid MCP server configurations
    and were skipped: {names}

So the entry `install-entry` writes into `~/.claude.json` — `{"type":"http","url":"…/mcp"}` — would
be accepted by the file, dropped by the app, and visible only in a dialog. `D1` in
`app/Tests/RouterCoreTests/DesktopEntryTests.swift` asserts that shape is refused before anything is
written.

Two consequences, both shipped rather than noted:

* **Desktop can only be pointed at a command.** `mcp-router serve` speaks streamable HTTP and has no
  stdio mode, and `mcp-remote` is not installed on this machine (`which mcp-remote` → not found).
  There is therefore no bridge to name today, and the verb refuses instead of inventing one.
* **zod's default object strips rather than rejects**, so `type` and `url` beside a valid `command`
  are *dropped*, not fatal. `Conformance` reports the two separately (`D2`), because collapsing them
  would either refuse a working entry or promise that a stripped member arrives.

This also **corrects R7's table for one client, in scope**. `HTTPCapability.known(for: .claudeDesktop)`
is `.documented(source: "Anthropic's desktop MCP documentation; no binary was probed here")`. That
claim is about Desktop's remote-MCP support in general, which goes through the in-app Connectors
surface; it is *not* true of `claude_desktop_config.json`, whose schema is stdio-only. The table is
left alone — narrowing a `.documented` row to a file is R7's call, not this item's — and the
divergence is recorded here so the next reader does not resolve it by trusting the row.

## 2. The reload half: four readings, one conclusion

| # | Question | What was read | Answer |
|---|---|---|---|
| 1 | Is the config re-read? | `G9e()` is `readFileSync` + `JSON.parse`; `KS(e=!1)` memoises it into module-global `GS` and re-reads only when called truthy | read once per process, then cached |
| 2 | Does anything watch the file? | `watch:!0` occurs **0** times in the bundle; the single `watchFile(` is `electron-store`'s own `_watch()`, entered only by a store constructed with watching on | no watcher |
| 3 | Can the cache be forced? | `KS(e)` → `osn(e)` → `gJ(e)`; the only truthy call in the bundle is `gJ(!0)`, and its one call site is a menu item: `Reload MCP Configuration` under the Developer menu, `click:async()=>void pon(await gJ(!0))` | yes — by a person |
| 4 | Is there a way in from outside? | `CFBundleURLSchemes` are `claude` and `msauth.com.anthropic.claudefordesktop`; no CLI ships in the bundle; no local control socket | no |

So a path exists and only a human can take it. `ReloadPath.claudeDesktopConfigChange` records that as
`locatedNotExercised`, and `isReliable` is **false** for every case but `exercised` (`D14`). The
distinction is the item's whole argument: a located path is a lead, and treating it as a capability
is the propagate-and-assume the brief exists to refuse.

**What was not measured, and why.** The menu item was not clicked. Claude Desktop was not running
when this was taken (`ps aux | grep Claude.app` → no match), and starting it to find out would put a
window in front of whoever owns the machine. Driving that menu item in a running Desktop is the
measurement that would move this row from `locatedNotExercised` to `exercised`, and it is left for
somebody who is at the keyboard. The static read also cannot say whether the Developer menu is
present in every build: the item itself carries no `visible:!1` flag, but the enclosing menu's
conditions were not traced.

## 3. The registration half, proven on a fixture

`scripts/acceptance/r32-desktop-entry.sh` — 20 cases, run against `mktemp` fixtures, refusing to
start if the fixture path resolves inside `$HOME/Library`.

    r32-desktop-entry: 20 case(s) held      (exit 0)

The two that carry the item's rules:

* **A4 — the dry run leaves the file byte-identical**, compared by `shasum` before and after.
* **A5 — the apply preserves `0600`, keeps `coworkUserFilesPath`, and leaves a backup holding the
  pre-image.**

And the transcript of a dry run against a fixture, which is what a person would see:

    --- …/claude_desktop_config.json
    +++ …/claude_desktop_config.json (proposed)
    @@ -1,5 +1,12 @@
     {
    -  "mcpServers": {},
    +  "mcpServers": {
    +    "mcp-router": {
    +      "command": "…/bridge",
    +      "args": [
    +        "http://127.0.0.1:8879/mcp"
    +      ]
    +    }
    +  },
       "coworkUserFilesPath": "/u/Documents/Claude",

## 4. The lane can be watched failing

`scripts/acceptance/r32-desktop-entry-selftest.sh` — 4 arms, exit 0. Arms 1 and 2 drive the lane
against a stub that exits 0 for every refusal and one that refuses everything, and require it red
for both, so neither an always-pass nor an always-fail lane satisfies the set. Arm 4 requires the
shipped binary green.

Arm 3 is the one that matters: a stub that prints every string the lane greps stdout for **and
rewrites the fixture anyway**. Only the digest comparison catches it, which is what turns A4 from a
sentence into a claim that has been observed failing.

## 5. Gates

| Gate | Exit | Note |
|---|---|---|
| `make lint` (24 members) | see §6 | run whole |
| `no-harness-config-writes.sh` | 0 | `417 file(s) examined … 2 write while naming a client, all 2 declared` |
| `no-harness-config-writes-selftest.sh` | 0 | 32 cases, up from 27 — P23-P27 are rule 4's |
| `sweep-control-gate.py` | 0 | 92 discovered sweeps, all disposed; both new scripts at `V1,V2`, read back through `markers_for` |
| `acceptance-lanes-selftest.sh` | 0 | 13 arms |
| `r32-desktop-entry.sh` | 0 | 20 cases |
| `r32-desktop-entry-selftest.sh` | 0 | 4 arms |
| `swift test` | see §6 | |

## 6. What is not green, and whose it is

`make test` is red on this branch at **2 issues in `MockTokenParityTests` and 1 in
`MockTokenLiteralTests`**, over three `rgba(…)`/`rgb(…)` literals at `design/mcp-router-console.html`
lines 692-694. **They are not R32's.** `git diff --name-only bb3359a HEAD -- design/
app/Sources/MCPRouterKit app/Tests/MCPRouterKitTests` returns **0 paths**: this branch changes
neither the file the assertion reads nor the suite that reads it, so the outcome is determined
entirely by files it did not touch. The lines were introduced by `95fbc21` and are deleted by
`0d59545`, which exists in the repository and which `main` does not currently point at — so a `main`
that advances to it clears this without R32 doing anything.

## 7. What this item did not deliver

* **No stdio bridge.** Desktop can only launch a command and this product ships none, so nothing on
  this machine can complete a registration today; the verb says so and exits 1. Building one is
  feature-sized — the router's endpoint is `StreamableHTTPServerTransport` with session ids and SSE,
  so session handling, cancellation and reconnects are the work, not a shim. Referred out of family
  (`codex`, `gpt-5.6-sol`, effort `high`) and its answer was to keep it out of R32 for exactly that
  reason: folding it in "would obscure the live-reload boundary R32 is intended to expose". The two
  refinements it added — absolute paths only, and separating "schema-valid" from "end-to-end
  verified" — are both in the shipped verb.
* **`harnesses` was not changed.** `ReloadPath` is reported by `desktop-entry` alone. R7's lane
  asserts on that verb's output, and widening it to carry a reload row is R7's call.
* **`HTTPCapability.known(for: .claudeDesktop)` was not flipped.** See §1.
