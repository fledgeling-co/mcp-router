#!/usr/bin/env bash
#
# R4 — the divergence lane.
#
# R1 declared five divergences from the reference. spec-R1 line 585 records something this gate
# has to act on: **D1, D3 and D4 have no vector, only suite tests** — TypeScript cannot be the
# oracle for a deliberate difference, so the generated corpus cannot carry them. R1 wrote it down
# for R4 specifically: "R4 should know its gate does not cover them."
#
# That is the gap this lane closes. Without it the corpus passes, the suite passes, and the
# absence of a divergence is indistinguishable from agreement — the divergence could be silently
# lost in a refactor and every gate in the repo would stay green.
#
# Each row is asserted in BOTH directions: the reference must really do the thing it is recorded
# as doing, AND Swift must really do the other thing. A one-sided assertion goes green when the
# reference changes, which is how a "known divergence" list outlives its reason.
#
# D4 (a logging failure is contained) and D5 (the log API takes a structured event) are not
# observable from outside the process at all; spec-R1 line 149 says so. They stay
# proven-by-suite in the manifest with their tests named, and are not faked here.
#
# Exit codes: 0 every divergence is exactly as declared, 1 one has gone stale, 2 the environment
# could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/ControlDiff}"
SWIFT_CLI="${SWIFT_CLI:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
PORT="${DIVERGENCE_PORT:-8965}"
WORK="$(mktemp -d -t parity-divergence)"
RESULTS="${PARITY_RESULTS:-}"
ROUTER_PID=""

MAIN_PID=$$
cleanup() {
  [ "$BASHPID" != "$MAIN_PID" ] && return 0
  [ -n "$ROUTER_PID" ] && kill "$ROUTER_PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

record() {
  [ -n "$RESULTS" ] || return 0
  printf '%s\t%s\t%s\t%s\n' "divergence" "$1" "$2" "$3" >> "$RESULTS"
}

# A stdio server held at the door: it announces itself, waits for a release file, then becomes the
# ordinary fixture server. This is what makes D7's window deterministic — a `sleep` racing an index
# that may finish first would exercise the ordinary path and report it as a pass.
gated_child() { # started gate
  cat <<'SH'
#!/bin/sh
touch "$1"
while [ ! -e "$2" ]; do sleep 0.05; done
exec node "$3" stdio
SH
}

command -v node >/dev/null 2>&1 || { echo "environment: node is not installed"; exit 2; }
[ -f "$REPO_ROOT/dist/index.js" ] || {
  echo "environment: no built reference at dist/index.js. Run npm run build."
  echo "             A skipped lane is recorded as blocked, not as a pass."; exit 2; }
[ -x "$SWIFT_BIN" ] || {
  echo "environment: no ControlDiff oracle at $SWIFT_BIN. Run swift build from app/."; exit 2; }
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "environment: something is already listening on :$PORT. This harness never shares a port"
  echo "             and never touches the router on 8975/8976."
  exit 2
fi

pass=0; fail=0

# ---------------------------------------------------------------------------------------------
# D1 — an unrecognisable `mcpServers`.
#
# The reference treats anything it cannot recognise as "no servers" and serves an empty list, so a
# config typed wrongly looks exactly like a config with nothing in it. Swift refuses to load it.
# The divergence is the whole point: silence about a broken config is the failure mode.
echo "D1 — an unrecognisable mcpServers"
home="$WORK/d1"; mkdir -p "$home"
printf '{"mcpServers": 42}\n' > "$home/servers.json"

MCP_ROUTER_HOME="$home" node "$REPO_ROOT/dist/index.js" serve --port "$PORT" \
  >"$home/router.log" 2>&1 &
ROUTER_PID=$!
ts_body=""
for _ in $(seq 1 100); do
  if [ -f "$home/control.token" ]; then
    token="$(cat "$home/control.token")"
    ts_body="$(curl -fsS -m 2 -H "x-mcpr-token: $token" "http://127.0.0.1:$PORT/servers" 2>/dev/null)" \
      && break
  fi
  kill -0 "$ROUTER_PID" 2>/dev/null || break
  sleep 0.1
done

swift_out="$(MCPR_CONFIG="$home/servers.json" "$SWIFT_BIN" GET /servers 2>&1)"; swift_code=$?
kill "$ROUTER_PID" 2>/dev/null || true; ROUTER_PID=""

# The reference is expected to answer, and to answer with an empty server list.
ts_ok=0
case "$ts_body" in *'"servers":[]'*) ts_ok=1 ;; esac
# Swift is expected NOT to serve this config: a non-zero exit, or an error in what it printed.
swift_ok=0
[ "$swift_code" != 0 ] && swift_ok=1
case "$swift_out" in *error*|*Error*) swift_ok=1 ;; esac

if [ "$ts_ok" = 1 ] && [ "$swift_ok" = 1 ]; then
  pass=$((pass + 1))
  echo "  ok   the reference serves an empty list; Swift refuses the config"
  record div-r1-d1 ok "reference: empty servers list. Swift: exit $swift_code, $(printf '%s' "$swift_out" | tail -1 | cut -c1-80)"
else
  fail=$((fail + 1))
  echo "  STALE the declared divergence no longer describes both sides"
  echo "        reference: $(printf '%s' "$ts_body" | cut -c1-90)"
  echo "        swift:     exit $swift_code — $(printf '%s' "$swift_out" | tail -1 | cut -c1-90)"
  record div-r1-d1 fail "stale: ts_ok=$ts_ok swift_ok=$swift_ok — the divergence record has outlived its reason"
fi

# ---------------------------------------------------------------------------------------------
# D3 — an unknown top-level key survives a write.
#
# Read carefully, spec-R1 line 148 is narrower than it first appears. The writer it calls
# non-atomic and four-keyed is the one in `src/index.ts`, and it says so in the row itself; it also
# says "extra preserved keys are expected". That writer is reached through the `import` and `index`
# CLI verbs, which Swift does not implement (D-k), so it cannot be driven from here.
#
# The CONTROL-API writer is a different code path, and this lane's first version asserted a
# divergence on it that R1 never claimed — then reported the divergence "stale" when both sides
# preserved the key. Measured directly: the reference rewrites servers.json on a PATCH, reformats
# it, adds the member, and keeps `unknownTopLevel`. Swift does the same.
#
# So on the path that IS comparable the two agree, and that agreement is what gets asserted. A
# preserved key on both sides is the pass; either side dropping it is the failure. The declared
# divergence about the src/index.ts writer stays uncompared and is recorded as such in the manifest.
echo
echo "D3 — an unknown top-level key survives a control-API write, on both sides"
home="$WORK/d3"; mkdir -p "$home"
seed='{"mcpServers":{"d3":{"command":"/bin/echo","args":["hi"]}},"unknownTopLevel":{"putHereBy":"another tool"}}'

# Swift's writer.
printf '%s\n' "$seed" > "$home/servers.json"
MCPR_CONFIG="$home/servers.json" "$SWIFT_BIN" PATCH /servers/d3 '{"warm":true}' >"$home/swift.out" 2>&1 || true
swift_kept=0
grep -q 'unknownTopLevel' "$home/servers.json" && swift_kept=1

# The reference's writer, driven over its own control API so it is the real code path.
printf '%s\n' "$seed" > "$home/servers.json"
MCP_ROUTER_HOME="$home" node "$REPO_ROOT/dist/index.js" serve --port "$PORT" \
  >"$home/router.log" 2>&1 &
ROUTER_PID=$!
ts_patched=0
for _ in $(seq 1 100); do
  if [ -f "$home/control.token" ]; then
    token="$(cat "$home/control.token")"
    if curl -fsS -m 2 -H "x-mcpr-token: $token" -H 'content-type: application/json' \
         -X PATCH --data-binary '{"warm":true}' \
         "http://127.0.0.1:$PORT/servers/d3" >/dev/null 2>&1; then
      ts_patched=1; break
    fi
  fi
  kill -0 "$ROUTER_PID" 2>/dev/null || break
  sleep 0.1
done
sleep 0.3
ts_kept=0
grep -q 'unknownTopLevel' "$home/servers.json" && ts_kept=1
kill "$ROUTER_PID" 2>/dev/null || true; ROUTER_PID=""

if [ "$ts_patched" = 0 ]; then
  echo "  environment: the reference never accepted the PATCH, so its writer was never exercised."
  tail -5 "$home/router.log"
  exit 2
fi

if [ "$swift_kept" = 1 ] && [ "$ts_kept" = 1 ]; then
  pass=$((pass + 1))
  echo "  ok   both writers preserved the unknown key"
  record div-r1-d3-control ok "swift and the reference both preserve unknownTopLevel across a control-API write"
else
  fail=$((fail + 1))
  echo "  FAIL swift_kept=$swift_kept reference_kept=$ts_kept — a writer dropped a key it did not set"
  record div-r1-d3-control fail "a writer dropped an unknown top-level key: swift_kept=$swift_kept reference_kept=$ts_kept"
fi

# ---------------------------------------------------------------------------------------------
# R2 D7 — the reference loses a router restart; the Swift watcher does not.
#
# `watch.ts` writes `servers.json` (line 279-283), then re-reads `~/.claude.json` before deleting
# the adopted entry. When that re-read fails to parse it returns at line 299 — **past** the
# `restartRouter()` at line 336. The next fire finds the config already matching, so `configChanged`
# is false and the restart is never issued: the adopted server can never reach the running router.
# spec-R2 declares this as D7 and forbids R2-W from reproducing it (spec-R2W W-D1).
#
# The oracle is `watch.log`, and the assertion is that a restart was **issued** — either the success
# line or the `could not restart` line. Asserting the success line would make this row pass only on
# a machine where the label happens to be loaded, and pass by restarting a real service.
#
# SIDE EFFECT, stated because it is real: the reference's kickstart target is hardcoded
# (`watch.ts:49`) and it calls `/bin/launchctl` by absolute path, so it cannot be redirected. This
# scenario relies on the reference NOT reaching its restart — which is the divergence itself. If
# that ever stops being true this row fails STALE, and the developer's own router will have been
# restarted once on the way. The Swift side is redirected to a scratch label and cannot touch it.
echo
echo "R2 D7 — a lost restart on an unparseable ~/.claude.json"
d7run() { # side binary...
  local side="$1"; shift
  local home="$WORK/d7-$side" claudehome="$WORK/d7-$side-home"
  mkdir -p "$home" "$claudehome"
  local started="$WORK/d7-$side.started" gate="$WORK/d7-$side.gate"
  rm -f "$started" "$gate"

  gated_child > "$WORK/d7-$side-child.sh"
  chmod +x "$WORK/d7-$side-child.sh"
  cat > "$claudehome/.claude.json" <<JSON
{
  "numStartups": 41,
  "mcpServers": {
    "probe": {
      "command": "$WORK/d7-$side-child.sh",
      "args": ["$started", "$gate", "$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs"]
    }
  }
}
JSON
  cat > "$home/servers.json" <<'JSON'
{
  "port": 8879,
  "host": "127.0.0.1",
  "idleMs": 300000,
  "mcpServers": {}
}
JSON

  # Corrupt the staging file while the child is held, then release it. The watcher therefore writes
  # servers.json and then finds ~/.claude.json unparseable — D7's exact window.
  (
    for _ in $(seq 1 600); do [ -e "$started" ] && break; sleep 0.05; done
    printf '{ truncated mid-write' > "$claudehome/.claude.json"
    touch "$gate"
  ) &
  local saboteur=$!

  HOME="$claudehome" MCP_ROUTER_HOME="$home" \
    MCPR_LAUNCHD_LABEL="gg.rhodes.mcp-router-parity-$$" \
    "$@" watch >"$home/watch.out" 2>&1
  wait "$saboteur" 2>/dev/null || true

  # Three observables: the config was written, the re-read failed, and whether a restart was issued.
  local wrote=no reread=no restarted=no
  grep -q '"probe"' "$home/servers.json" 2>/dev/null && wrote=yes
  grep -q 'no longer parses' "$home/watch.log" 2>/dev/null && reread=yes
  grep -Eq 'restarted gg\.rhodes|could not restart gg\.rhodes' \
    "$home/watch.log" 2>/dev/null && restarted=yes
  printf '%s,%s,%s' "$wrote" "$reread" "$restarted"
}

ts_d7="$(d7run ts node "$REPO_ROOT/dist/index.js")"
swift_d7="$(d7run swift "$SWIFT_CLI")"
echo "  reference: $ts_d7"
echo "  swift:     $swift_d7"
echo "  (servers.json written, re-read failed, restart issued)"

if [ "$ts_d7" = "yes,yes,no" ] && [ "$swift_d7" = "yes,yes,yes" ]; then
  pass=$((pass + 1))
  echo "  ok   the reference loses the restart on this path; the Swift watcher issues it"
  record div-r2-d7 ok "reference=$ts_d7 swift=$swift_d7 (written,re-read-failed,restart-issued)"
else
  fail=$((fail + 1))
  echo "  STALE the declared divergence no longer describes both sides"
  record div-r2-d7 fail "stale: reference=$ts_d7 swift=$swift_d7 — expected yes,yes,no vs yes,yes,yes"
fi

echo
# ---------------------------------------------------------------------------------------------
# R1 D3 on the writer D3 was actually written about — `src/index.ts`'s four-key import writer.
#
# `div-r1-d3-control` above measured the CONTROL-API writer and said so, because proving a
# capability by measuring another one is the failure this gate exists to prevent. This is the
# missing half: spec-R1:148 scopes D3 to the non-atomic writer reached through `import`, and until
# P2 the Swift import writer was a faithful port of it, so there was no divergence to assert.
#
# **Each side gets its own MCP_ROUTER_HOME.** `import --from` sets only the READ path; the write
# goes to ROUTER_HOME (`src/config.ts:79`). Without this the lane would rewrite the developer's own
# `~/.claude/mcp-router/servers.json` — the footgun `WatchPaths.swift:8-10` exists for.
echo "div-r1-d3 — the import writer preserves a top-level key the reference drops"
d3home="$WORK/d3import"
rm -rf "$d3home"
for side in ts swift; do
  mkdir -p "$d3home/$side"
  echo "toolset" > "$d3home/$side/toolset"
  # `startupTimeoutMs` is a key the router genuinely supports, so losing it resets a real setting
  # rather than dropping a synthetic marker. `mcpServers` deliberately holds a name that is NOT in
  # the staging file, so "Swift wrote" is observable rather than assumed.
  cat > "$d3home/$side/servers.json" <<'JSON'
{
  "port": 8879,
  "host": "127.0.0.1",
  "idleMs": 300000,
  "startupTimeoutMs": 45000,
  "mcpServers": { "seedOnly": { "command": "/bin/true" } }
}
JSON
done
cat > "$d3home/claude.json" <<JSON
{
  "mcpServers": {
    "probe": {
      "command": "node",
      "args": ["$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs", "stdio"],
      "env": { "FIXTURE_TOOLSET_FILE": "$d3home/ts/toolset" }
    }
  }
}
JSON
MCP_ROUTER_HOME="$d3home/ts" node "$REPO_ROOT/dist/index.js" import \
  --from "$d3home/claude.json" >/dev/null 2>&1
MCP_ROUTER_HOME="$d3home/swift" "$SWIFT_CLI" import \
  --from "$d3home/claude.json" >/dev/null 2>&1

d3_ts_kept=no;    grep -q 'startupTimeoutMs' "$d3home/ts/servers.json"    && d3_ts_kept=yes
d3_swift_kept=no; grep -q 'startupTimeoutMs' "$d3home/swift/servers.json" && d3_swift_kept=yes
# The third observation, and the one revision 1 of this lane did not have. Without it a Swift side
# that threw and wrote nothing leaves the seed key in place, the two files differ, and the row goes
# green for the exact opposite of the reason it claims.
d3_swift_wrote=no
if grep -q '"probe"' "$d3home/swift/servers.json" \
   && ! grep -q '"seedOnly"' "$d3home/swift/servers.json"; then
  d3_swift_wrote=yes
fi
echo "  reference kept the key: $d3_ts_kept"
echo "  swift kept the key:     $d3_swift_kept"
echo "  swift actually wrote:   $d3_swift_wrote"

if [ "$d3_ts_kept" = no ] && [ "$d3_swift_kept" = yes ] && [ "$d3_swift_wrote" = yes ]; then
  pass=$((pass + 1))
  echo "  ok   the reference drops the unknown key on import; Swift preserves it"
  record div-r1-d3 ok \
    "import: ts_kept=$d3_ts_kept swift_kept=$d3_swift_kept swift_wrote=$d3_swift_wrote (preservation half; atomicity is ImportConfigWriterTests W9)"
else
  fail=$((fail + 1))
  echo "  STALE the declared divergence no longer describes both sides"
  record div-r1-d3 fail \
    "stale: ts_kept=$d3_ts_kept swift_kept=$d3_swift_kept swift_wrote=$d3_swift_wrote — expected no,yes,yes"
fi
echo

# ---------------------------------------------------------------------------------------------
# M22 — two routes this router answers that the reference does not.
#
# `GET /harnesses` and `GET /insights` are Swift-only surface. The reference has no such paths, so
# `isControlPath` never claims them, the dispatch ladder falls through, and it answers the MCP
# endpoint's 404. This router answers 200 with the board's own envelope.
#
# **Declared here rather than left to be discovered.** `parity-manifest-check.sh` derives the
# `control` group from `src/control.ts` in BOTH directions, so a control row for a route the
# reference does not answer is a red — which means a Swift-only route demands no row at all and
# would silently shrink nothing while being counted nowhere. These two rows are what stop the
# addition being invisible to the census, and this arm is what stops the rows being paperwork.
#
# Asserted in BOTH directions, like every row in this lane: the reference must really 404, and
# Swift must really serve. A one-sided assertion goes green the day the reference grows the route.
#
# **HOME is a scratch directory**, and that is load-bearing rather than tidiness: the harness
# inventory reads whatever `$HOME` names, and a lane pointed at the developer's own home would
# report a different body on every machine — and would put somebody's real `~/.claude.json` inside
# a gate run. With a scratch home the answer is an empty harness list, which is exactly what the
# assertions below are written against: the SHAPE of the envelope and its fixed members, never a
# row's contents.
echo "M22 — /harnesses and /insights are answered here and 404 at the reference"
m22home="$WORK/m22"
mkdir -p "$m22home/router" "$m22home/home"
cat > "$m22home/router/servers.json" <<'JSON'
{
  "port": 8879,
  "host": "127.0.0.1",
  "idleMs": 300000,
  "mcpServers": {}
}
JSON

# One side at a time on the same port, because this harness never shares one.
m22probe() { # side binary...
  local side="$1"; shift
  local out="$m22home/$side.out"
  HOME="$m22home/home" MCP_ROUTER_HOME="$m22home/router" \
    "$@" serve --port "$PORT" >"$out" 2>&1 &
  local pid=$!
  local up=""
  for _ in $(seq 1 60); do
    curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && { up=ok; break; }
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done
  if [ "$up" != ok ]; then
    kill "$pid" 2>/dev/null || true
    printf 'nostart|nostart'
    return 0
  fi
  # `-o /dev/null` is deliberately NOT used: a status with the wrong bytes is still a divergence,
  # and on the Swift side the envelope is the whole of what this row claims.
  local h i
  h="$(curl -s -m 5 -w '\n%{http_code}' "http://127.0.0.1:$PORT/harnesses" 2>/dev/null | tr -d '\r')"
  i="$(curl -s -m 5 -w '\n%{http_code}' "http://127.0.0.1:$PORT/insights" 2>/dev/null | tr -d '\r')"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  printf '%s|%s' "$h" "$i"
}

status_of() { printf '%s' "$1" | tail -1; }
body_of()   { printf '%s' "$1" | sed '$d'; }

m22_ts="$(m22probe ts node "$REPO_ROOT/dist/index.js")"
m22_swift="$(m22probe swift "$SWIFT_CLI")"

ts_h="${m22_ts%%|*}";       ts_i="${m22_ts##*|}"
swift_h="${m22_swift%%|*}"; swift_i="${m22_swift##*|}"

echo "  reference: /harnesses $(status_of "$ts_h")  /insights $(status_of "$ts_i")"
echo "  swift:     /harnesses $(status_of "$swift_h")  /insights $(status_of "$swift_i")"

# The reference's 404 is the MCP endpoint's, not a control refusal — the path was never claimed.
# Matching its body as well as its status is what tells those two apart.
m22_ts_ok=0
if [ "$(status_of "$ts_h")" = 404 ] && [ "$(status_of "$ts_i")" = 404 ]; then
  case "$(body_of "$ts_h")" in *'MCP endpoint is /mcp'*) m22_ts_ok=1 ;; esac
fi

# Swift: 200, and the envelope's own fixed members. Asserted rather than "not 404", because a
# router answering 200 with an empty body would pass the weaker test and serve nothing.
m22_swift_h_ok=0
if [ "$(status_of "$swift_h")" = 200 ]; then
  case "$(body_of "$swift_h")" in
    *'"scope":"global"'*'"harnesses":['*) m22_swift_h_ok=1 ;;
  esac
fi
m22_swift_i_ok=0
if [ "$(status_of "$swift_i")" = 200 ]; then
  # `windowHours` and `dutyCycle` together, because the first is the window this route is fixed to
  # and the second is the reading only a pool can take — a body carrying one and not the other is
  # a route that answered without the dependency it exists to expose.
  case "$(body_of "$swift_i")" in
    *'"windowHours":24'*'"dutyCycle"'*) m22_swift_i_ok=1 ;;
  esac
fi

if [ "$m22_ts_ok" = 1 ] && [ "$m22_swift_h_ok" = 1 ]; then
  pass=$((pass + 1))
  echo "  ok   the reference 404s /harnesses; this router serves the envelope"
  record div-m22-harnesses ok \
    "reference $(status_of "$ts_h") (MCP 404), swift $(status_of "$swift_h") with scope+harnesses"
else
  fail=$((fail + 1))
  echo "  STALE the declared divergence no longer describes both sides"
  record div-m22-harnesses fail \
    "stale: reference $(status_of "$ts_h"), swift $(status_of "$swift_h") — expected 404 vs 200+envelope"
fi

if [ "$m22_ts_ok" = 1 ] && [ "$m22_swift_i_ok" = 1 ]; then
  pass=$((pass + 1))
  echo "  ok   the reference 404s /insights; this router serves the counted board"
  record div-m22-insights ok \
    "reference $(status_of "$ts_i") (MCP 404), swift $(status_of "$swift_i") with windowHours+dutyCycle"
else
  fail=$((fail + 1))
  echo "  STALE the declared divergence no longer describes both sides"
  record div-m22-insights fail \
    "stale: reference $(status_of "$ts_i"), swift $(status_of "$swift_i") — expected 404 vs 200+body"
fi
echo

echo "divergences: $pass as declared, $fail stale"
[ "$fail" -gt 0 ] && exit 1
exit 0
