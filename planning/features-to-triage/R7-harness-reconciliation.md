---
status: completed
shipped-by: d285298
---

# R7 — the router's own thesis is unmet for every harness except Claude Code

**Category:** router · **Found:** 2026-08-15, by measurement on the author's own machine
**Related:** R6 (child PATH). This is the evidence layer under the multi-harness want.

## What was measured

Five agent harnesses are installed and on PATH: `claude`, `codex`, `cursor-agent`, `grok`,
`agy`, plus `opencode`. Their MCP configuration, read directly:

| Harness | Config | MCP entries | Transport |
|---|---|---|---|
| Claude Code | `~/.claude.json` (271 KB) | 1 router entry | HTTP — working as designed |
| Gemini CLI | `~/.gemini/settings.json` | **18** | **18 stdio, 0 HTTP** |
| Codex | `~/.codex/config.toml` (944 KB) | 7 `[mcp_servers.*]` | not audited here |
| Cursor | `~/.cursor/mcp.json` (22 bytes) | **0** — `{"mcpServers": {}}` | — |

The Gemini row is the finding. Its 18th entry is:

```
router → npx -y mcp-remote http://127.0.0.1:8879/mcp
```

So Gemini *does* reach the router — through a per-session stdio shim process, which is the
exact per-client process the router exists to eliminate, and which was already rejected for
Claude Desktop for that reason. And it reaches it **alongside** 17 directly-configured
stdio servers, of which **ten are servers the router already fronts**: `Ref`, `docker-mcp`,
`dossier`, `google-search`, `media-gen-pro`, `yt-transcript`, `sift`, `lifeline`,
`obscura`, `ai-elements`.

Net effect on this machine: a Gemini session spawns **18 processes at init** to reach a
capability set the router serves with **0 at rest**, and ten of those spawns are pure
duplication of the router's own upstreams.

## Why this reframes the multi-harness item

The natural reading of "support more harnesses" is a config-writing chore: learn Codex's
TOML, learn Cursor's JSON, point each at the endpoint. On the evidence above that reading
is wrong in two ways.

**It is not new work, it is unrealised work.** The README's headline number — 190 processes
and ~12 GB down to 0 at rest — is true for exactly one harness. Every other harness on the
same machine is still paying the original cost, and one of them is paying it *while also
running the router*. The product's central claim is currently a claim about a single
client.

**Pointing a harness at the endpoint is not sufficient, and Gemini proves it.** Gemini is
already pointed at the endpoint. It still spawns 18 children, because nothing removed the
direct entries when the router entry was added. Config *writing* is the easy half; the half
that produces the benefit is noticing that a harness has direct upstreams which duplicate
the router and reconciling them.

## What "fixed" should mean

1. **Adopt-and-reconcile, not just add.** When wiring a harness to the router, the same
   step should detect direct entries that duplicate a router upstream and offer to remove
   them, showing the diff. Adding the router entry while leaving the duplicates is the
   current state and it is worse than either alternative.
2. **Drift detection afterwards.** A harness config is not a write-once artifact: an
   engineer adds a server by hand, an upgrade rewrites the file, a dotfiles repo restores
   an old copy. The interesting event is drift, and answering "is this harness actually
   routed" should be a query rather than a belief.
3. **Decide the shim question deliberately.** `mcp-remote` is how a harness with no HTTP
   MCP transport reaches the router at all, so it is not simply a mistake — but it
   reintroduces one process per session, and the Servers board should say so rather than
   showing that harness as routed with no qualification. Which harnesses genuinely speak
   streamable HTTP is the first thing the research panel was asked.

## Acceptance

- For each supported harness, the app can state which of: not wired · wired via HTTP ·
  wired via a stdio shim · wired but carrying duplicate direct upstreams.
- The duplicate case is detected by comparing the harness's entries against the router's
  own upstream set, and is shown with the specific overlapping names.
- Red-green: a fixture harness config carrying three duplicates is reported as three, and
  reported as zero after reconciliation.
- The measurement in this file is reproducible from the shipped app rather than from ad-hoc
  shell commands.

## Not in scope

Writing every harness's config dialect. That is the mechanical part and it follows from
this, rather than the reverse.
