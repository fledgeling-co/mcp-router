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

echo
echo "divergences: $pass as declared, $fail stale"
[ "$fail" -gt 0 ] && exit 1
exit 0
