#!/usr/bin/env bash
#
# One-line install for mcp-router.
#
#   /bin/bash -c "$(curl -fsSL https://fledgeling-co.github.io/mcp-router/install.sh)"
#
# What it does, in order, and nothing else:
#   0. fetches the source into ~/.local/share/mcp-router, if you piped this in
#   1. builds the router
#   2. copies your stdio MCP servers out of ~/.claude.json into the router's own list
#   3. indexes them once, so `tools/list` can be served with nothing running
#   4. writes two launchd agents with THIS machine's absolute paths and loads them
#   5. adds a single `router` HTTP entry to ~/.claude.json
#
# It backs ~/.claude.json up before touching it, and `docs/uninstall.sh`
# puts every server back where it came from.
set -euo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; DIM=$'\033[2m'; RST=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$GRN" "$RST" "$1"; }
warn() { printf '%s!!!%s %s\n' "$YLW" "$RST" "$1"; }
die()  { printf '%sxxx%s %s\n' "$RED" "$RST" "$1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "This installer is macOS-only: it uses launchd. On Linux, build with \`npm run build\` and run \`node dist/index.js serve\` under systemd."

# ---------------------------------------------------------------- prerequisites
command -v node >/dev/null 2>&1 || die "node not found on PATH. Install Node 20 or newer."
NODE_BIN="$(command -v node)"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
(( NODE_MAJOR >= 20 )) || die "Node $NODE_MAJOR is too old; this needs 20 or newer (tested on 22)."

# ---------------------------------------------------------------- source
# Resolve the repo from this script's own location so the launchd agents point
# at wherever it actually lives rather than a path baked in by the author. When
# the script arrives down a pipe there is no file on disk to resolve from, so
# BASH_SOURCE is unusable and the source has to be fetched.
REPO_URL="${MCP_ROUTER_REPO:-https://github.com/fledgeling-co/mcp-router.git}"
APP_DIR="${MCP_ROUTER_HOME:-$HOME/.local/share/mcp-router}"
REPO_ROOT=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  [[ -f "$CANDIDATE/package.json" ]] && REPO_ROOT="$CANDIDATE"
fi

if [[ -z "$REPO_ROOT" ]]; then
  command -v git >/dev/null 2>&1 || die "git not found on PATH, and it is needed to fetch the source."
  if [[ -d "$APP_DIR/.git" ]]; then
    say "updating $APP_DIR"
    git -C "$APP_DIR" fetch --quiet origin
    git -C "$APP_DIR" reset --quiet --hard origin/HEAD
  else
    say "fetching $REPO_URL -> $APP_DIR"
    mkdir -p "$(dirname "$APP_DIR")"
    git clone --quiet --depth 1 "$REPO_URL" "$APP_DIR"
  fi
  REPO_ROOT="$APP_DIR"
fi
[[ -f "$REPO_ROOT/package.json" ]] || die "no package.json at $REPO_ROOT — the source is not where it should be."

ROUTER_HOME="$HOME/.claude/mcp-router"
CLAUDE_JSON="$HOME/.claude.json"
AGENTS="$HOME/Library/LaunchAgents"
PORT="${MCP_ROUTER_PORT:-8879}"

say "source  $REPO_ROOT"
say "node    $NODE_BIN (v$(node -p 'process.versions.node'))"
say "port    $PORT"
mkdir -p "$ROUTER_HOME" "$AGENTS"

# ---------------------------------------------------------------- build
say "building"
( cd "$REPO_ROOT" && npm install --silent && npm run build --silent )
[[ -f "$REPO_ROOT/dist/index.js" ]] || die "build produced no dist/index.js"

# ---------------------------------------------------------------- adopt + index
if [[ -f "$CLAUDE_JSON" ]]; then
  say "importing stdio servers from ~/.claude.json"
  ( cd "$REPO_ROOT" && node dist/index.js import ) || warn "import found nothing to take"
else
  warn "no ~/.claude.json — starting with an empty server list"
fi

say "indexing (spawns each server once, then shuts it down)"
( cd "$REPO_ROOT" && node dist/index.js index ) || warn "some servers failed to index; \`mcpr status\` names them"

# ---------------------------------------------------------------- launchd
# PATH is set explicitly: launchd inherits none of the user's shell environment,
# so a bare `node` in ProgramArguments resolves to nothing.
NODE_DIR="$(dirname "$NODE_BIN")"
LAUNCHD_PATH="$NODE_DIR:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

write_plist() {
  local label="$1" verb="$2" extra="$3"
  cat > "$AGENTS/$label.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$label</string>
	<key>ProgramArguments</key>
	<array>
		<string>$NODE_BIN</string>
		<string>$REPO_ROOT/dist/index.js</string>
		<string>$verb</string>
	</array>
	<key>EnvironmentVariables</key>
	<dict><key>PATH</key><string>$LAUNCHD_PATH</string></dict>
	<key>WorkingDirectory</key><string>$REPO_ROOT</string>
	<key>RunAtLoad</key><true/>
	<key>ThrottleInterval</key><integer>10</integer>
	<key>StandardOutPath</key><string>$ROUTER_HOME/$verb.out.log</string>
	<key>StandardErrorPath</key><string>$ROUTER_HOME/$verb.err.log</string>
$extra
</dict>
</plist>
PLIST
}

# Do NOT add ProcessType: Background here. It throttles startup I/O hard enough
# that the process never reaches listen(), while launchctl reports it running
# with an empty log — indistinguishable from a hang. Measured, not theorised.
write_plist gg.rhodes.mcp-router serve \
	'	<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>'

write_plist gg.rhodes.mcp-router-watch watch \
	"	<key>WatchPaths</key><array><string>$CLAUDE_JSON</string></array>"

say "loading launchd agents"
for label in gg.rhodes.mcp-router gg.rhodes.mcp-router-watch; do
  launchctl bootout "gui/$UID/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$UID" "$AGENTS/$label.plist"
done

# ---------------------------------------------------------------- point Claude at it
if [[ -f "$CLAUDE_JSON" ]]; then
  BACKUP="$CLAUDE_JSON.bak-mcp-router-$(date +%Y%m%d-%H%M%S)"
  cp "$CLAUDE_JSON" "$BACKUP"
  say "backed up ~/.claude.json -> $(basename "$BACKUP")"
  # Re-read and rewrite in one pass: this file holds live session state for every
  # project and Claude Code rewrites it constantly, so touch only mcpServers.router.
  node -e '
    const fs = require("fs");
    const p = process.argv[1], port = process.argv[2];
    const d = JSON.parse(fs.readFileSync(p, "utf8"));
    d.mcpServers = d.mcpServers || {};
    d.mcpServers.router = { type: "http", url: `http://127.0.0.1:${port}/mcp` };
    // Carry the original permissions onto the replacement. A temp file plus rename
    // gets fresh 0644 from the umask otherwise, so a ~/.claude.json the user keeps
    // at 0600 — the file this comment describes as holding live session state for
    // every project — comes back world-readable.
    const mode = fs.statSync(p).mode & 0o777;
    fs.writeFileSync(p + ".tmp", JSON.stringify(d, null, 2), { mode });
    fs.chmodSync(p + ".tmp", mode);
    fs.renameSync(p + ".tmp", p);
  ' "$CLAUDE_JSON" "$PORT"
  say "added the router entry to ~/.claude.json"
fi

# ---------------------------------------------------------------- verify
sleep 2
if curl -fsS --max-time 5 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  TOOLS="$(curl -fsS --max-time 5 "http://127.0.0.1:$PORT/status" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{const d=JSON.parse(s);console.log(`${d.tools} tools from ${d.children.length} upstreams, ${d.children.filter(c=>c.state==="running").length} running`)})')"
  printf '\n%s✓ mcp-router is up on 127.0.0.1:%s%s — %s\n' "$GRN" "$PORT" "$RST" "$TOOLS"
  printf '%sStart a new Claude Code session to pick up the tools.%s\n' "$DIM" "$RST"
else
  warn "the router is not answering yet — check $ROUTER_HOME/serve.err.log"
  exit 1
fi
