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
# `install-launchd-watch`: the SECOND agent, whose contract is different and whose difference is the
# point. It is `RunAtLoad` plus `WatchPaths` and **no** `KeepAlive`, because it is a one-shot: it
# runs, adopts what it can, and exits. Four observations per binary: it ran at load, touching the
# watched file ran it again, it did not stay resident, and which streams carry bytes.
#
# Nothing in this lane restarts a real router. The staged `mcpServers` holds nothing adoptable, so
# neither binary reaches its `restartRouter()`, and the Swift side additionally runs under a scratch
# MCPR_LAUNCHD_LABEL.
#
# ROWS THIS LANE OWNS:  install: install-launchd-serve install-launchd-watch
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
    install/install-launchd-serve|install/install-launchd-watch) ;;
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
  # buffering. This records WHICH streams carry bytes, as a two-character pattern (`o`/`e`, `-` for
  # an empty stream), and the caller compares the pattern between the two binaries.
  #
  # It used to be `[ -f out ] && [ -f err ]`. launchd creates both files at bootstrap whether or not
  # the program writes a byte, so that term was `yes` for any agent that got as far as being loaded:
  # it could not tell the two binaries apart, and a Swift router that logged nothing at all to
  # either stream still scored it `yes` under a note claiming it "wrote both log paths". Requiring
  # non-empty makes silence visible; recording the pattern rather than a boolean makes a router that
  # logs to the OTHER stream than the reference visible too.
  logged="$([ -s "$home/agent.out" ] && printf o || printf -)$([ -s "$home/agent.err" ] && printf e || printf -)"
  [ "$logged" = "--" ] && logged=none

  # 3 — a clean stop must not relaunch it. `bootout` is the clean stop.
  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1
  wait_gone 20 && stayed_down=yes

  printf '%s,%s,%s,%s' "$up" "$relaunched" "$stayed_down" "$logged"
}

# The watch agent's plist. The same supervision skeleton as `plist`, minus KeepAlive and plus
# WatchPaths — exactly the difference `docs/install.sh:147-151` writes between the two agents.
watch_plist() { # label home claudejson label-override program args...
  local label="$1" home="$2" claude="$3" override="$4"; shift 4
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
    <key>HOME</key><string>$(dirname "$claude")</string>
    <key>MCPR_LAUNCHD_LABEL</key><string>$override</string>
    <key>PATH</key><string>$LAUNCHD_PATH</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>WatchPaths</key><array><string>$claude</string></array>
  <key>StandardOutPath</key><string>$home/agent.out</string>
  <key>StandardErrorPath</key><string>$home/agent.err</string>
</dict>
</plist>
XML
}

# Nothing adoptable, deliberately: the watcher still runs, still hashes and still writes its state,
# and never reaches a config write — so no router is restarted (X12b).
stage() { # claude-json-path marker
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<JSON
{
  "numStartups": 41,
  "mcpServers": { "notadoptable-$2": { "note": "no command and no url" } }
}
JSON
}

observe_watch() { # side program args...
  local side="$1"; shift
  local label="app.fledgeling.mcp-router.parity-watch-$side-$STAMP"
  local home="$WORK/watch-$side" claudehome="$WORK/watch-$side-home"
  mkdir -p "$home" "$claudehome"
  stage "$claudehome/.claude.json" one
  watch_plist "$label" "$home" "$claudehome/.claude.json" \
    "gg.rhodes.mcp-router-parity-$STAMP" "$@" > "$WORK/watch-$side.plist"
  LABELS="$LABELS $label"

  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1
  if ! launchctl bootstrap "gui/$(id -u)" "$WORK/watch-$side.plist" \
       >"$WORK/watch-$side.bootstrap" 2>&1; then
    printf 'bootstrap-refused'
    return 0
  fi

  local ran=no reran=no oneshot=no logged=none
  local state="$home/watch-state.json"
  for _ in $(seq 1 80); do [ -s "$state" ] && { ran=yes; break; }; sleep 0.25; done
  local first=""
  [ "$ran" = yes ] && first="$(cat "$state")"

  # A one-shot leaves no resident process. Read before the re-run, so a still-running first pass
  # cannot be mistaken for a resident daemon.
  [ -z "$(agent_pid "$label")" ] && oneshot=yes

  # ThrottleInterval is 10s in what the installer writes, so a re-run is allowed to take that long.
  # This waits it out rather than reporting an agent that is merely being throttled as broken.
  stage "$claudehome/.claude.json" two
  for _ in $(seq 1 160); do
    [ -s "$state" ] && [ "$(cat "$state")" != "$first" ] && { reran=yes; break; }
    sleep 0.25
  done

  logged="$([ -s "$home/agent.out" ] && printf o || printf -)$([ -s "$home/agent.err" ] && printf e || printf -)"
  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1
  printf '%s,%s,%s,%s' "$ran" "$reran" "$oneshot" "$logged"
}

echo "supervising each binary under its own scratch launchd agent on :$PORT"
echo

ts_result="$(observe ts "$NODE_BIN" "$REPO_ROOT/dist/index.js" serve --port "$PORT")"
sleep 1
swift_result="$(observe swift "$SWIFT_BIN" serve --port "$PORT")"

echo "  reference: $ts_result"
echo "  swift:     $swift_result"
echo "  (started, relaunched-after-SIGKILL, stayed-down-after-bootout, log-streams-written)"
echo "  the fourth term is which streams carry bytes: o=stdout, e=stderr, - =empty, none=silent."
echo "  Both routers log to stderr only, so \`-e\` is the agreeing answer, not a partial one."
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

failures=0
if [ "$ts_result" = "$swift_result" ] && [ "${swift_result%,*}" = "yes,yes,yes" ] \
   && [ "${swift_result##*,}" != none ]; then
  echo "  ok   both binaries survive the installer's supervision identically"
  record install install-launchd-serve ok \
    "both: started at load, relaunched after SIGKILL, stayed down after bootout, wrote both log paths"
else
  echo "  FAIL the two binaries do not survive the same supervision"
  record install install-launchd-serve fail \
    "reference=$ts_result swift=$swift_result (started,relaunched,stayed-down,logged)"
  failures=$((failures + 1))
fi

# ---------------------------------------------------------------------------------------------
echo
echo "supervising each binary's WATCH agent — RunAtLoad + WatchPaths, no KeepAlive"
echo
ts_watch="$(observe_watch ts "$NODE_BIN" "$REPO_ROOT/dist/index.js" watch)"
sleep 1
swift_watch="$(observe_watch swift "$SWIFT_BIN" watch)"
echo "  reference: $ts_watch"
echo "  swift:     $swift_watch"
echo "  (ran-at-load, re-ran-on-file-change, one-shot-not-resident, log-streams-written)"
echo

case "$ts_watch$swift_watch" in
  *bootstrap-refused*)
    echo "environment: launchd refused to bootstrap a scratch watch agent in this session, so the"
    echo "             watch supervision contract could not be exercised on either side."
    exit 2 ;;
esac

if [ "$ts_watch" = "$swift_watch" ] && [ "${swift_watch%,*}" = "yes,yes,yes" ]; then
  echo "  ok   both binaries answer the watch agent's supervision identically"
  record install install-launchd-watch ok \
    "both: ran at load, re-ran on a WatchPaths change, stayed one-shot, wrote the same streams"
else
  echo "  FAIL the two binaries do not answer the same watch supervision"
  record install install-launchd-watch fail \
    "reference=$ts_watch swift=$swift_watch (ran,reran,one-shot,logged)"
  failures=$((failures + 1))
fi

echo
echo "install: four real agents under real launchd supervision, two per binary."
[ "$failures" -gt 0 ] && exit 1
exit 0
