# MCP Router landing copy

Routed: create-luke-content → marketing persona. Every figure traces to PRD.md or to
this machine's own `~/.claude/mcp-router/manifest.json`.

## Nav

Store · How it works · Verified · What it costs · GitHub
Download for macOS  (persistent CTA, stays visible when the links collapse under 860px)

## Hero

Free · macOS 15+ · signed and notarised

# Every MCP server, skill and plugin in one place. None of them running.

MCP Router is a free Mac app with a store for verified servers, skills and plugins, and a
router underneath that keeps them switched off. Install what you want from one place, use it
in Claude Code, Cursor, Codex, Grok, Antigravity and OpenCode, and nothing starts a process
until something actually calls a tool.

Install
`/bin/bash -c "$(curl -fsSL https://mcp-router.fledgeling.app/install.sh)"`

It takes your existing setup with it. Nothing to reconnect.

Readout: 12 servers · 134 tools · 0 running

## The store

### One place to get them, and they work in all six.

Servers, skills and plugins come from GitHub marketplaces in four different formats. MCP
Router reads all four and normalises them, so a skill written as a Claude plugin installs
into Cursor and Codex as well, and you stop keeping six copies of the same config.

Add a few and watch the counter.

Your rig: processes · resident · cold start

Note: that counter is what your rig costs the ordinary way, one child process per server per
harness window. It is not what it costs through the router.

## Why it adds up

### You didn't install 190 things. You installed about 32, six times.

MCP models stdio as one client to one server process. Every harness window you open starts
its own copy of every server you have declared, whether you touch it or not. Six harnesses
with a few sessions each puts you at roughly 190 child processes and about 12 GB resident, on
a machine that is also trying to compile something.

Note: `--strict-mcp-config` limits which servers a session declares at boot. It does not share
a process between two sessions, and it does not hold off a spawn until a tool is called.

## How it works

### Nothing starts until something calls it.

**The manifest is cached.** Your harness asks for the tool list and gets it instantly, off
disk. That answer never needed a process, so none of them start.

**A child spawns on the first real call.** Someone calls a tool on `dossier`, and only
`dossier` starts. Two sessions hitting the same cold server share one spawn rather than
racing each other.

**The reaper closes it.** Five minutes idle by default, and the child is gone. Back to zero.

At rest: 0 children · under 30 MB resident

Measured with `ps -o rss` against the router's own process. What would make this a bad trade
for you: three servers, one harness, and calls all day. In that case the flag is enough and
you can close this tab.

## Six harnesses

### Six config files, one line each.

Claude Code · `~/.claude.json`
Cursor · `~/.cursor/mcp.json`
Grok CLI · `~/.grok/config.toml`
Codex · `~/.codex/config.toml`
Antigravity · `~/.gemini/settings.json`
OpenCode · `~/.opencode/mcp.json`

The watcher does this for you. When it finds a new stdio server in one of those files it
indexes it once on its own, moves it into the router, and takes the direct entry out so you
are not paying for it twice. If the index fails, the entry stays where it was and you get the
error rather than a silent removal.

## Verified

### "Verified" is a check that can fail, and you can read the ones that did.

Every listing is health-checked and its tool schemas are recorded. When an update changes a
tool's description or its input schema, that update goes into quarantine and stays there until
you have read the diff. A tool that is held cannot be called.

This matters more than it sounds. A tool description is model-facing instruction, so a server
that quietly rewrites its own description between versions is editing what your agent believes
it has been told to do. Version pinning does not catch it, because the version did change.

## Cleanup

### Most of what you have installed has never been called.

Across the sessions the analyser has measured, over 90% of declared servers go uncalled.
Cleanup counts real invocations over 7, 30 and 90 days and shows you what has never fired,
with the argument for keeping each one next to it. Nothing goes without you selecting it, and
you have 30 days to undo.

Note: that 90% is measured on the fleet the product was built against, not on your machine.
Yours will be its own number, and the app counts it rather than assuming it.

## What it costs

### The parts that are not free.

**The first call after a reap pays cold start.** That is the trade for nothing at rest. If a
server is one you genuinely hit all day, pin it warm and skip the trade.

**One endpoint in series is one place for everything to fail.** If the router is down, every
harness loses its tools at once. That is a real change to your failure surface and it is
worth knowing before you install.

**It is unsandboxed, and it has to be.** It spawns your developer subprocesses and reads your
dotfiles, which the App Sandbox forbids, so it ships as a signed and notarised DMG rather than
through the App Store.

**It listens on loopback only.** It binds to 127.0.0.1 and rejects any request whose Host
header is not loopback, because binding to localhost on its own does not stop a web page
pointing a domain at your machine.

## Removing it

### How to take it back out.

`/bin/bash -c "$(curl -fsSL https://mcp-router.fledgeling.app/uninstall.sh)"`

It puts the entries back in the harness files it took them from. Add `--purge` and it takes
the cached manifests and history with it as well.

## Footer

Free, MIT, and it stays that way.
