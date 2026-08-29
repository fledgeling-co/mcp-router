#!/bin/bash
# R27 — the effect witness for the upstream health probe.
#
# The claim under test is `REQ-029`: a health probe is an effect outside this process. A probe that
# decided an upstream was healthy without ever reaching it would satisfy every assertion in the
# Swift suite — the suite's transport is a double — and would be worth nothing, which is the
# vacuity this rung exists to refuse. `REQ-016` is the recorded instance in this repository: it
# declared an `outbound-socket` effect with no provider anywhere in production source and was moved
# to `vacuous` rather than left reading as satisfied.
#
# FOUR PARTS, and the fourth is the one that is easy to skip.
#
#   1. driven from a PRODUCTION ENTRY POINT — `POST /servers/:name/probe` over the daemon's own
#      socket, not by calling the prober from a test;
#   2. an ATTEMPT recorded at the boundary — the child writes its own `getpid getppid` to a path
#      handed to it in the environment, and the product never reads that file back;
#   3. COMPLETION confirmed by something other than the code under test — the shell's own `$!` for
#      the daemon, and `ps(1)`, which is the kernel's answer to who spawned what;
#   4. SABOTAGE flips it — a second upstream whose command does not exist is probed the same way,
#      and the recorder must see NO child and the route must report the failure. Without part 4 a
#      witness proves an attempt happened near the test rather than because of it.
#
# THE PORTABLE FLOOR, declared. There is no `bpf`, no `eslogger` and no root here, so this is the
# floor rather than the kernel bar: a real spawned process writing a sentinel file the witness then
# reads. It cannot pass when nothing runs, which is the property that matters.
#
# ONE MORE READING, and it is the one this feature is arranged around. Before any probe, the report
# says every upstream is `unprobed` and the process table holds no fixture child — `REQ-001` is
# that at rest there are zero child processes, and a background health check that cold-started
# every server would invert it. Recorded as `restAtStart` below.
#
# Everything runs against a scratch MCP_ROUTER_HOME on a port the campaign reserves, so the user's
# own router at 127.0.0.1:8879 is never touched, read or restarted.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
CLI="$REPO/app/.build/debug/MCPRouterCLI"
HOME_DIR="${WITNESS_HOME:-/tmp/mcp-witness-health}"
PORT=8978
OUT="$REPO/planning/test-campaign/evidence/witness"
LOG="$OUT/health-probe.log"

mkdir -p "$OUT"
: > "$LOG"
say() { printf '%s\n' "$*" | tee -a "$LOG"; }

fail=0
ROUTER_PID=""
cleanup() {
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null
  wait "$ROUTER_PID" 2>/dev/null
}
trap cleanup EXIT INT TERM HUP

say "== R27 health-probe effect witness =="
say "recorded at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "binary:      $CLI"
[ -x "$CLI" ] || { say "environment: no MCPRouterCLI at $CLI (run: make build-cli-debug)"; exit 2; }
say "sha256:      $(shasum -a 256 "$CLI" | cut -d' ' -f1)"
say "router home: $HOME_DIR   (the user's own home is untouched)"
say "port:        127.0.0.1:$PORT"
say ""

PRE_LISTEN=$(lsof -nP -iTCP@127.0.0.1:$PORT 2>/dev/null | grep -c LISTEN)
if [ "$PRE_LISTEN" -ne 0 ]; then
  say "REFUSING: something already holds 127.0.0.1:$PORT; a daemon found now would not be ours."
  exit 2
fi

# ------------------------------------------------------------------ the fixture
rm -rf "$HOME_DIR"
bash "$REPO/planning/test-campaign/bin/witness-fixture/seed.sh" "$HOME_DIR" || exit 2
# Two upstreams: the one that answers, and the sabotage arm whose command does not exist. Written
# here rather than into the shared template, because the template is the OTHER witness's fixture
# and a second server would change what that one measures.
python3 - "$HOME_DIR" <<'PY' || exit 2
import json, sys, pathlib
home = pathlib.Path(sys.argv[1])
path = home / "servers.json"
config = json.loads(path.read_text())
config["port"] = 8978
config["mcpServers"]["witness-broken"] = {
    "type": "stdio",
    "command": str(home / "there-is-no-such-binary"),
    "args": [],
}
path.write_text(json.dumps(config, indent=2))
PY

export MCP_ROUTER_HOME="$HOME_DIR"
"$CLI" serve --port $PORT >"$HOME_DIR/serve.out" 2>&1 &
ROUTER_PID=$!
ready=""
for _ in $(seq 1 50); do
  curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && { ready=ok; break; }
  kill -0 "$ROUTER_PID" 2>/dev/null || break
  sleep 0.2
done
if [ "$ready" != ok ]; then
  say "environment: the daemon never answered /health on :$PORT — its output:"
  sed -n '1,40p' "$HOME_DIR/serve.out" | tee -a "$LOG"
  exit 2
fi
TOKEN="$(cat "$HOME_DIR/control.token" 2>/dev/null || echo '')"
[ -n "$TOKEN" ] || { say "environment: the daemon minted no control token"; exit 2; }

probe() { # server -> body on stdout
  curl -sS -m 20 -X POST "http://127.0.0.1:$PORT/servers/$1/probe" \
    -H 'content-type: application/json' -H "x-mcpr-token: $TOKEN" --data-binary '{}' 2>/dev/null
}
children() { ps -Ao pid=,ppid=,command= 2>/dev/null | awk -v p="$ROUTER_PID" '$2==p'; }

# ------------------------------------------------- rest at start: REQ-001, measured not assumed
say "-- at rest, before any probe ------------------------------------------"
REST_REPORT=$(curl -sS -m 5 "http://127.0.0.1:$PORT/upstreams/health" 2>/dev/null)
REST_CHILDREN=$(children | grep -c fixture-server.py)
say "recorder: ps(1), rows whose ppid is the daemon's own pid $ROUTER_PID"
say "  report:   $(printf '%s' "$REST_REPORT" | cut -c1-160)"
say "  children: $REST_CHILDREN"
REST_OK=no
case "$REST_REPORT" in *'"state":"unprobed"'*) [ "$REST_CHILDREN" -eq 0 ] && REST_OK=yes ;; esac
if [ "$REST_OK" = yes ]; then
  say "VERDICT:  at rest the report is unprobed and the process table holds no child."
else
  say "VERDICT:  NOT held — a child exists, or the report claims a probe nobody ran."
  fail=1
fi
say ""

# ------------------------------------------------------------- the witness itself
say "-- REQ-029 subprocess, driven by POST /servers/witness-fixture/probe ---"
rm -f "$HOME_DIR/child.pid"
BEFORE_PIDFILE=$([ -e "$HOME_DIR/child.pid" ] && echo present || echo absent)
say "recorder: two records, neither written by the router. The SHELL records the daemon's pid"
say "          through \$!. The CHILD records its own getppid() into a path passed in the"
say "          environment and never read back by the product. ps(1) is the third reading."
say "before:   child.pid $BEFORE_PIDFILE"

OK_BODY="$(probe witness-fixture)"
PS_ROW="$(children | grep fixture-server.py | head -1)"
SELF=""
[ -s "$HOME_DIR/child.pid" ] && SELF="$(cat "$HOME_DIR/child.pid")"

say "route said: $(printf '%s' "$OK_BODY" | cut -c1-200)"
say "ps row:     ${PS_ROW:-none}"
say "child says: ${SELF:-none}"

WITNESSED=0
if [ -n "$SELF" ]; then
  CPID=$(printf '%s' "$SELF" | awk '{print $1}')
  CPPID=$(printf '%s' "$SELF" | awk '{print $2}')
  if [ "$CPPID" = "$ROUTER_PID" ]; then
    WITNESSED=1
    say "VERDICT:  witnessed — count=1. The child names pid $CPPID as its parent and the shell"
    say "          launched the daemon as pid $ROUTER_PID. Two records that cannot have"
    say "          coordinated name the same parent, so the probe spawned this child."
  else
    say "VERDICT:  spawn witnessed, parent NOT attributed — child names $CPPID, shell launched"
    say "          $ROUTER_PID. The spawn is not attributed to the router by this run."
    fail=1
  fi
else
  say "VERDICT:  NOT witnessed — no child recorded itself."
  fail=1
fi
case "$OK_BODY" in
  *'"state":"healthy"'*) say "          and the route reported the upstream healthy." ;;
  *) say "          BUT the route did not report healthy, so the reading and the effect disagree."
     fail=1 ;;
esac
say ""

# ------------------------------------------------------------------ part 4: sabotage
say "-- sabotage: the same route against an upstream whose command does not exist -"
say "recorder: the same three. Denying the effect must flip every one of them."
rm -f "$HOME_DIR/child.pid"
BEFORE_BROKEN=$(children | grep -c fixture-server.py)
BROKEN_BODY="$(probe witness-broken)"
AFTER_BROKEN=$(children | grep -c fixture-server.py)
BROKEN_PIDFILE=$([ -e "$HOME_DIR/child.pid" ] && echo present || echo absent)
say "route said: $(printf '%s' "$BROKEN_BODY" | cut -c1-200)"
say "children before/after: $BEFORE_BROKEN / $AFTER_BROKEN"
say "child.pid: $BROKEN_PIDFILE"
SABOTAGE_OK=no
case "$BROKEN_BODY" in
  *'"state":"degraded"'*)
    [ "$BROKEN_PIDFILE" = absent ] && [ "$AFTER_BROKEN" -eq "$BEFORE_BROKEN" ] && SABOTAGE_OK=yes ;;
esac
if [ "$SABOTAGE_OK" = yes ]; then
  say "VERDICT:  the arm held — no child appeared, the pidfile stayed absent, and the route"
  say "          reported degraded rather than healthy. The witness discriminates."
else
  say "VERDICT:  the arm did NOT hold. A witness that cannot be made to fail has measured nothing."
  fail=1
fi
say ""

# ------------------------------------------------------------------ the record
BROKEN_STATE=$(printf '%s' "$BROKEN_BODY" | sed -n 's/.*"state":"\([a-z]*\)".*/\1/p' | head -1)
OK_STATE=$(printf '%s' "$OK_BODY" | sed -n 's/.*"state":"\([a-z]*\)".*/\1/p' | head -1)
cat > "$OUT/health-probe.json" <<JSON
{
  "recordedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "binary": "$CLI",
  "binarySha256": "$(shasum -a 256 "$CLI" | cut -d' ' -f1)",
  "routerHome": "$HOME_DIR",
  "port": $PORT,
  "entryPoint": "POST /servers/:name/probe over the daemon's own socket",
  "lane": "portable floor: a real spawned process writing a sentinel the witness reads. No bpf, no eslogger, no root.",
  "restAtStart": { "reportState": "unprobed", "fixtureChildren": $REST_CHILDREN, "held": "$REST_OK" },
  "witnesses": [
    {
      "req": "REQ-029",
      "effect": "subprocess",
      "recorder": "the shell's \$! for the daemon and the child's own getppid(); ps(1) sampled alongside",
      "count": $WITNESSED,
      "daemonPid": $ROUTER_PID,
      "childReported": "${SELF:-none}",
      "psRow": "${PS_ROW:-none}",
      "routeState": "${OK_STATE:-none}"
    }
  ],
  "sabotage": {
    "server": "witness-broken",
    "command": "a path that does not exist",
    "childrenBefore": $BEFORE_BROKEN,
    "childrenAfter": $AFTER_BROKEN,
    "pidfile": "$BROKEN_PIDFILE",
    "routeState": "${BROKEN_STATE:-none}",
    "held": "$SABOTAGE_OK"
  }
}
JSON
say "wrote $OUT/health-probe.json"
say "exit: $fail"
exit $fail
