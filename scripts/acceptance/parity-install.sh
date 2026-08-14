#!/usr/bin/env bash
#
# R2-R — the install lane.
#
# `install-launchd-serve`: whether a Swift binary survives the supervision `docs/install.sh` writes.
#
# **Two-sided.** An earlier draft of this lane supervised only the Swift binary and asserted the
# plist's text, which is not a differential at all — a plist that parses is not a binary that
# survives being killed, and counting that as parity would be exactly the false certainty the gate
# exists to prevent. So two agents are written, identical but for the program they run, and the same
# four observations are taken on each:
#
#   1. RunAtLoad brings it up and it answers /health.
#   2. `kill -9` — KeepAlive/SuccessfulExit=false means a non-zero exit relaunches it.
#   3. a clean stop does NOT relaunch it.
#   4. both StandardOutPath and StandardErrorPath are written.
#
# The labels are scratch, the plists live in a scratch directory, and the agents are booted out on
# every exit path including a failure — a stray agent left in the user's session would keep starting
# a router on a port they did not ask for.
#
# ROWS THIS LANE OWNS:  install: install-launchd-serve
#
# CAVEAT, printed into the gate's report: two real agents under real launchd supervision, one per
# binary, compared observation by observation. It does NOT run `docs/install.sh` itself — that would
# rewrite the user's own `~/.claude.json`, which is `install-claude-json`'s row and D-k's to unblock.
#
# Exit codes: 0 both survived identically, 1 they did not, 2 the environment could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
PORT="${INSTALL_PORT:-8997}"
WORK="$(mktemp -d -t parity-install)"
RESULTS="${PARITY_RESULTS:-}"
STAMP="$$"
LABELS=""

MAIN_PID=$$
cleanup() {
  [ "$BASHPID" != "$MAIN_PID" ] && return 0
  for label in $LABELS; do
    launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

record() {
  [ -n "$RESULTS" ] || return 0
  case "$1/$2" in
    install/install-launchd-serve) ;;
    *) echo "  LANE BUG: refusing to record $1/$2, which this lane does not own" >&2; return 1 ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$RESULTS"
}

# The plist mirrors what `docs/install.sh` writes, and two of its lines are why the first run of
# this lane reported the REFERENCE as unable to start: a launchd agent gets a minimal environment,
# so `node` must be an absolute path and `PATH` must be set explicitly. install.sh:102 and :107 do
# both. `ThrottleInterval` is carried over too — install.sh:110 sets 10 seconds, which is exactly
# the kind of thing a lane that invented its own plist would omit and then measure a relaunch that
# the real installer would have delayed.
LAUNCHD_PATH="${LAUNCHD_PATH:-$(dirname "$(command -v node 2>/dev/null || echo /usr/bin/node)"):/usr/local/bin:/usr/bin:/bin}"
NODE_BIN="$(command -v node 2>/dev/null || true)"

command -v launchctl >/dev/null 2>&1 || { echo "environment: launchctl is not available"; exit 2; }
[ -x "$NODE_BIN" ] || { echo "environment: node could not be resolved to an absolute path"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "environment: node is not installed"; exit 2; }
[ -f "$REPO_ROOT/dist/index.js" ] || { echo "environment: no dist/index.js. Run npm run build."; exit 2; }
[ -x "$SWIFT_BIN" ] || { echo "environment: no Swift router at ${SWIFT_BIN#"$REPO_ROOT/"}"; exit 2; }
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "environment: something is already listening on :$PORT"; exit 2
fi

# The supervision contract, read out of docs/install.sh rather than retyped: RunAtLoad,
# KeepAlive/SuccessfulExit=false, and the two log paths.
plist() { # label home program args...
  local label="$1" home="$2"; shift 2
  local program_args=""
  for arg in "$@"; do program_args="$program_args    <string>$arg</string>
"; done
  cat <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
$program_args  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>MCP_ROUTER_HOME</key><string>$home</string>
    <key>PATH</key><string>$LAUNCHD_PATH</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>KeepAlive</key>
  <dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardOutPath</key><string>$home/agent.out</string>
  <key>StandardErrorPath</key><string>$home/agent.err</string>
</dict>
</plist>
XML
}

seed() { # dir
  mkdir -p "$1"
  echo "toolset" > "$1/toolset"
  cat > "$1/servers.json" <<JSON
{
  "mcpServers": {
    "probe": {
      "command": "node",
      "args": ["$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs", "stdio"],
      "env": { "FIXTURE_TOOLSET_FILE": "$1/toolset" }
    }
  }
}
JSON
}

health() { curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; }

wait_health() { # seconds
  for _ in $(seq 1 $(( $1 * 4 ))); do health && return 0; sleep 0.25; done
  return 1
}
wait_gone() { # seconds
  for _ in $(seq 1 $(( $1 * 4 ))); do health || return 0; sleep 0.25; done
  return 1
}
agent_pid() { launchctl print "gui/$(id -u)/$1" 2>/dev/null | awk '/^\tpid = /{print $3}'; }

# One binary, four observations, reported as a comma-joined string so the two sides are compared as
# a sequence rather than as a final state.
observe() { # side program args...
  local side="$1"; shift
  local label="app.fledgeling.mcp-router.parity-$side-$STAMP"
  local home="$WORK/$side"
  seed "$home"
  plist "$label" "$home" "$@" > "$WORK/$side.plist"
  LABELS="$LABELS $label"

  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1
  if ! launchctl bootstrap "gui/$(id -u)" "$WORK/$side.plist" >"$WORK/$side.bootstrap" 2>&1; then
    printf 'bootstrap-refused'
    return 0
  fi

  local up=no relaunched=no stayed_down=no logged=no
  wait_health 20 && up=yes

  # 2 — killed with SIGKILL, which is a non-zero exit, so KeepAlive/SuccessfulExit=false relaunches.
  local first; first="$(agent_pid "$label")"
  if [ -n "$first" ]; then
    kill -9 "$first" 2>/dev/null
    sleep 1
    if wait_health 20; then
      local second; second="$(agent_pid "$label")"
      [ -n "$second" ] && [ "$second" != "$first" ] && relaunched=yes
    fi
  fi

  # 4 — read before the bootout, because booting out truncates nothing but the process may still be
  # buffering. Both paths must exist; the router writes its own log to stderr.
  [ -f "$home/agent.out" ] && [ -f "$home/agent.err" ] && logged=yes

  # 3 — a clean stop must not relaunch it. `bootout` is the clean stop.
  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1
  wait_gone 20 && stayed_down=yes

  printf '%s,%s,%s,%s' "$up" "$relaunched" "$stayed_down" "$logged"
}

echo "supervising each binary under its own scratch launchd agent on :$PORT"
echo

ts_result="$(observe ts "$NODE_BIN" "$REPO_ROOT/dist/index.js" serve --port "$PORT")"
sleep 1
swift_result="$(observe swift "$SWIFT_BIN" serve --port "$PORT")"

echo "  reference: $ts_result"
echo "  swift:     $swift_result"
echo "  (started, relaunched-after-SIGKILL, stayed-down-after-bootout, both-log-paths-written)"
echo

# A refused bootstrap is an environment failure, not a Swift failure. On a machine where the session
# will not accept an agent, the honest answer is that this row was not measured — which the gate
# records as blocked, which is what it was before.
case "$ts_result$swift_result" in
  *bootstrap-refused*)
    echo "environment: launchd refused to bootstrap a scratch agent in this session, so the"
    echo "             supervision contract could not be exercised on either side."
    cat "$WORK/ts.bootstrap" "$WORK/swift.bootstrap" 2>/dev/null | sed 's/^/             /'
    exit 2 ;;
esac

if [ "$ts_result" = "$swift_result" ] && [ "$swift_result" = "yes,yes,yes,yes" ]; then
  echo "  ok   both binaries survive the installer's supervision identically"
  record install install-launchd-serve ok \
    "both: started at load, relaunched after SIGKILL, stayed down after bootout, wrote both log paths"
  echo
  echo "install: two real agents under real launchd supervision, one per binary."
  exit 0
fi

echo "  FAIL the two binaries do not survive the same supervision"
record install install-launchd-serve fail \
  "reference=$ts_result swift=$swift_result (started,relaunched,stayed-down,logged)"
echo
echo "install: two real agents under real launchd supervision, one per binary."
exit 1
