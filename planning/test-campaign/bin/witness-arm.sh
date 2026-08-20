#!/bin/bash
# Negative controls for witness-effects.sh.
#
# Each recorder is pointed at a world where the effect does NOT happen. A recorder that
# still reports "witnessed" there is reporting its own existence rather than the product's
# behaviour, which is the failure mode this whole rung exists to avoid.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
CLI="$REPO/app/.build/debug/MCPRouterCLI"
OUT="$REPO/planning/test-campaign/evidence/witness"
ARM=/tmp/mcp-witness-arm
LOG="$OUT/arming.log"
mkdir -p "$OUT"; : > "$LOG"
say() { printf '%s\n' "$*" | tee -a "$LOG"; }

rm -rf "$ARM"; mkdir -p "$ARM"
say "== arming the effect witnesses =="
say "recorded at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say ""
bad=0

# --- REQ-013 filesystem-write: a home the router is never pointed at -------------------
say "-- arm REQ-013: run the router against one home, watch a DIFFERENT one --"
cp /tmp/mcp-witness-home/fixture-server.py "$ARM/" 2>/dev/null
sed 's#/tmp/mcp-witness-home#/tmp/mcp-witness-arm#' /tmp/mcp-witness-home/servers.json > "$ARM/servers.json"
DECOY="$ARM/decoy-home"; mkdir -p "$DECOY"
MCP_ROUTER_HOME="$ARM" "$CLI" index --force >>"$LOG" 2>&1
if [ -e "$DECOY/manifest.json" ]; then
  say "   RED FLAG: the decoy home gained a manifest.json. The recorder cannot tell the two apart."
  bad=1
else
  say "   count=0 at the decoy path, count=1 at the real one ($( [ -e "$ARM/manifest.json" ] && echo present || echo ABSENT))."
  say "   The stat recorder discriminates."
  [ -e "$ARM/manifest.json" ] || { say "   ...except the real one is absent, so this arm proved nothing."; bad=1; }
fi
say ""

# --- REQ-012 inbound-socket: sample a port nothing binds ------------------------------
say "-- arm REQ-012: point lsof at a port no router was told to use --"
FREE=8974
while lsof -nP -iTCP@127.0.0.1:$FREE 2>/dev/null | grep -q LISTEN; do FREE=$((FREE+1)); done
MCP_ROUTER_HOME="$ARM" "$CLI" serve --port 8973 >>"$LOG" 2>&1 &
SPID=$!
for _ in $(seq 1 20); do lsof -nP -iTCP@127.0.0.1:8973 2>/dev/null | grep -q LISTEN && break; sleep 0.4; done
ON=$(lsof -nP -iTCP@127.0.0.1:8973 2>/dev/null | grep -c LISTEN)
OFF=$(lsof -nP -iTCP@127.0.0.1:$FREE 2>/dev/null | grep -c LISTEN)
say "   port 8973 (the one serve was given): LISTEN rows = $ON"
say "   port $FREE (never mentioned to it):  LISTEN rows = $OFF"
if [ "$ON" -ge 1 ] && [ "$OFF" -eq 0 ]; then
  say "   The lsof recorder discriminates: it answers about the port it is pointed at."
else
  say "   RED FLAG: on=$ON off=$OFF — the recorder does not separate a bound port from a free one."
  bad=1
fi
kill "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null
sleep 0.5
GONE=$(lsof -nP -iTCP@127.0.0.1:8973 2>/dev/null | grep -c LISTEN)
say "   after the router is killed:          LISTEN rows = $GONE"
[ "$GONE" -ne 0 ] && { say "   RED FLAG: the listener outlived the process it was attributed to."; bad=1; }
say ""

# --- REQ-001/011 subprocess: a config that declares no stdio server -------------------
say "-- arm REQ-001/011: a router home whose config spawns nothing --"
NOSPAWN=/tmp/mcp-witness-nospawn; rm -rf "$NOSPAWN"; mkdir -p "$NOSPAWN"
cat > "$NOSPAWN/servers.json" <<'JSON'
{ "port": 8973, "host": "127.0.0.1", "idleMs": 300000, "mcpServers": {} }
JSON
rm -f "$NOSPAWN/child.pid"
MCP_ROUTER_HOME="$NOSPAWN" "$CLI" index --force >>"$LOG" 2>&1 &
NPID=$!
wait "$NPID" 2>/dev/null
if [ -s "$NOSPAWN/child.pid" ]; then
  say "   RED FLAG: a child recorded itself against a config that declares no servers."
  bad=1
else
  say "   count=0. No child recorded itself, because there was nothing to spawn."
  say "   Re-running the same recorder against the populated home for contrast:"
  rm -f /tmp/mcp-witness-home/child.pid
  MCP_ROUTER_HOME=/tmp/mcp-witness-home "$CLI" index --force >>"$LOG" 2>&1 &
  RPID=$!; wait "$RPID" 2>/dev/null
  if [ -s /tmp/mcp-witness-home/child.pid ]; then
    read -r C P < /tmp/mcp-witness-home/child.pid
    say "   count=1, child pid $C reporting parent $P (shell launched $RPID; agree=$([ "$P" = "$RPID" ] && echo yes || echo NO))"
    [ "$P" = "$RPID" ] || bad=1
  else
    say "   RED FLAG: count=0 on the populated home too — the recorder never sees anything."
    bad=1
  fi
fi
say ""

if [ "$bad" -eq 0 ]; then
  say "ARMED: every recorder reported 0 where the effect does not happen and 1 where it does."
else
  say "NOT ARMED: at least one recorder failed to discriminate. Detail above."
fi
rm -rf "$ARM" "$NOSPAWN"
exit $bad
