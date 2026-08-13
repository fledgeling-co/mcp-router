#!/usr/bin/env bash
#
# Remove mcp-router and put everything back the way it was.
#
#   ./scripts/uninstall.sh            # restore servers, remove agents, keep state
#   ./scripts/uninstall.sh --purge    # ...and delete ~/.claude/mcp-router entirely
#
# The important half is the restore: every stdio server the router adopted is
# written back into ~/.claude.json before the agents go, so Claude Code is left
# working rather than with no MCP servers at all.
set -euo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; DIM=$'\033[2m'; RST=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$GRN" "$RST" "$1"; }
warn() { printf '%s!!!%s %s\n' "$YLW" "$RST" "$1"; }

PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

ROUTER_HOME="$HOME/.claude/mcp-router"
CLAUDE_JSON="$HOME/.claude.json"
AGENTS="$HOME/Library/LaunchAgents"
SERVERS="$ROUTER_HOME/servers.json"

# ------------------------------------------------- stop the agents first
# Before restoring, so the watcher cannot re-adopt a server mid-write.
say "stopping launchd agents"
for label in gg.rhodes.mcp-router-watch gg.rhodes.mcp-router; do
  if launchctl print "gui/$UID/$label" >/dev/null 2>&1; then
    launchctl bootout "gui/$UID/$label" 2>/dev/null || true
    say "  booted out $label"
  fi
  rm -f "$AGENTS/$label.plist"
done

# ------------------------------------------------- give the servers back
if [[ -f "$SERVERS" && -f "$CLAUDE_JSON" ]]; then
  BACKUP="$CLAUDE_JSON.bak-mcp-router-uninstall-$(date +%Y%m%d-%H%M%S)"
  cp "$CLAUDE_JSON" "$BACKUP"
  say "backed up ~/.claude.json -> $(basename "$BACKUP")"

  RESTORED="$(node -e '
    const fs = require("fs");
    const [claudePath, serversPath] = process.argv.slice(1);
    const claude = JSON.parse(fs.readFileSync(claudePath, "utf8"));
    const routerCfg = JSON.parse(fs.readFileSync(serversPath, "utf8"));
    const servers = routerCfg.mcpServers || {};
    claude.mcpServers = claude.mcpServers || {};
    let n = 0;
    for (const [name, cfg] of Object.entries(servers)) {
      // Never clobber a name the user has since defined by hand.
      if (claude.mcpServers[name]) continue;
      claude.mcpServers[name] = cfg;
      n++;
    }
    delete claude.mcpServers.router;
    fs.writeFileSync(claudePath + ".tmp", JSON.stringify(claude, null, 2));
    fs.renameSync(claudePath + ".tmp", claudePath);
    console.log(n);
  ' "$CLAUDE_JSON" "$SERVERS")"
  say "restored $RESTORED stdio server(s) to ~/.claude.json and removed the router entry"
  warn "those servers now start eagerly again, one copy per session — that is the cost this tool removed"
else
  warn "no $SERVERS to restore from; leaving ~/.claude.json alone"
fi

# ------------------------------------------------- state
if (( PURGE )); then
  rm -rf "$ROUTER_HOME"
  say "deleted $ROUTER_HOME"
else
  printf '%sKept %s (config, manifest, logs, backups). Use --purge to delete it.%s\n' "$DIM" "$ROUTER_HOME" "$RST"
fi

printf '\n%s✓ mcp-router removed.%s Start a new Claude Code session to pick up the change.\n' "$GRN" "$RST"
