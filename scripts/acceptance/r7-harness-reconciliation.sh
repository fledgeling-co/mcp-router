#!/usr/bin/env bash
#
# R7 — a fixture harness config carrying three duplicates is reported as three, and zero after
# reconciliation. `planning/specs/spec-R7.md` A3 and A8.
#
# It never reads and never writes the developer's own harness configs. HOME points at a scratch
# directory for the whole run, both fixtures are written by this script, and the verb under test
# opens every file read-only. The one thing this lane must not do is the one thing the item itself
# refuses to do — see spec §7.
#
# Three passes, and the third is the one that makes the first two mean anything:
#   green->zero  three duplicates reported as three, then the same file with them removed as zero
#   arming       the router's own upstream set emptied, three duplicates still declared: a detector
#                that answers "3" from the harness file alone reports three here and fails, because
#                a duplicate is a RELATION between two files and cannot be counted from one
#
# Exit codes: 0 pass, 1 a wrong answer, 2 the environment could not run the lane.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d -t r7-harness)"
SWIFT_BIN="${MCPR_ROUTER_BINARY:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
PORT=8879
FAILURES=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

[ -x "$SWIFT_BIN" ] || {
  echo "environment: no router binary at $SWIFT_BIN."
  echo "             Run (cd app && swift build --product MCPRouterCLI)."
  echo "             A skipped lane is recorded as blocked, not as a pass."; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "environment: python3 is not installed"; exit 2; }

SCRATCH_HOME="$WORK/home"
mkdir -p "$SCRATCH_HOME/.gemini" "$SCRATCH_HOME/.claude/mcp-router"

# The router's own upstream set. Three stdio servers, one of which the fixture harness will declare
# under a DIFFERENT name — so a name-only comparison cannot reach three and the lane would go red.
write_router_config() {
  local servers="$1"
  cat > "$SCRATCH_HOME/.claude/mcp-router/servers.json" <<JSON
{ "port": $PORT, "host": "127.0.0.1", "idleMs": 300000, "mcpServers": $servers }
JSON
}

FULL_UPSTREAMS='{
    "obscura":       { "command": "/usr/bin/obscura", "args": ["mcp"] },
    "dossier":       { "command": "npx", "args": ["-y", "dossier-research-mcp@latest"] },
    "ref-tools-mcp": { "command": "npx", "args": ["-y", "ref-tools-mcp@3.0.3"] }
  }'

# The harness. It is wired through an mcp-remote stdio shim, exactly as the measured one is, and it
# declares four servers besides: three the router already fronts (one of them RENAMED, so the
# identity basis has to find it) and one it does not.
write_harness() {
  local duplicates="$1"
  cat > "$SCRATCH_HOME/.gemini/settings.json" <<JSON
{
  "mcpServers": {
    "router":  { "command": "npx", "args": ["-y", "mcp-remote", "http://127.0.0.1:$PORT/mcp"] },
    "github":  { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"] }$duplicates
  }
}
JSON
}

THREE_DUPLICATES=',
    "obscura": { "command": "/usr/bin/obscura", "args": ["mcp"] },
    "dossier": { "command": "npx", "args": ["-y", "dossier-research-mcp@latest"] },
    "Ref":     { "command": "npx", "args": ["-y", "ref-tools-mcp@3.0.3"] }'

# Read one field out of the verb's own JSON. The lane asserts on the shipped output rather than on
# a re-implementation of the comparison, which is the difference between measuring the product and
# measuring a copy of it.
probe() {
  HOME="$SCRATCH_HOME" MCP_ROUTER_HOME="$SCRATCH_HOME/.claude/mcp-router" \
    "$SWIFT_BIN" harnesses --json --port "$PORT" 2>"$WORK/stderr.txt"
}

field() {
  python3 -c '
import json, sys
doc = json.load(sys.stdin)
row = next(h for h in doc["harnesses"] if h["harness"] == "geminiCLI")
key = sys.argv[1]
value = row[key]
print(",".join(d["harnessName"] for d in value) if key == "duplicates" else value)
' "$1"
}

check() {
  local what="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ok    $what = $actual"
  else
    echo "  FAIL  $what: expected $expected, got $actual"
    FAILURES=$((FAILURES + 1))
  fi
}

# ---------------------------------------------------------------- pass 1: three
echo "r7: a fixture harness carrying three duplicates"
write_router_config "$FULL_UPSTREAMS"
write_harness "$THREE_DUPLICATES"
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "duplicateCount"    3                       "$(printf '%s' "$OUT" | field duplicateCount)"
check "the names"         "obscura,dossier,Ref"   "$(printf '%s' "$OUT" | field duplicates)"
check "state"             wired-with-duplicates   "$(printf '%s' "$OUT" | field state)"
check "route"             stdio-shim              "$(printf '%s' "$OUT" | field route)"

# ---------------------------------------------------------------- pass 2: zero
echo "r7: the same harness after reconciliation"
write_harness ""
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "duplicateCount"    0                       "$(printf '%s' "$OUT" | field duplicateCount)"
check "the names"         ""                      "$(printf '%s' "$OUT" | field duplicates)"
check "state"             wired-shim              "$(printf '%s' "$OUT" | field state)"
check "route unchanged"   stdio-shim              "$(printf '%s' "$OUT" | field route)"

# ---------------------------------------------------------------- pass 3: arming
# Same three harness entries, an empty router. A duplicate is a relation between two files, so the
# only correct answer is zero. A detector that counts the harness's own entries answers three and
# this pass turns red — which is what stops the two passes above from being a pair of numbers that
# happen to agree with the fixture that produced them.
echo "r7: arming — the same three entries against a router that fronts nothing"
write_router_config '{}'
write_harness "$THREE_DUPLICATES"
OUT="$(probe)" || { echo "the verb failed:"; cat "$WORK/stderr.txt"; exit 1; }
check "duplicateCount"    0                       "$(printf '%s' "$OUT" | field duplicateCount)"
check "state"             wired-shim              "$(printf '%s' "$OUT" | field state)"

# ---------------------------------------------------------------- the boundary
echo "r7: the harness fixture was not modified by the run"
if grep -q '"Ref"' "$SCRATCH_HOME/.gemini/settings.json"; then
  echo "  ok    the file this lane wrote is the file that is still there"
else
  echo "  FAIL  the fixture changed under the verb — it is supposed to open configs read-only"
  FAILURES=$((FAILURES + 1))
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "r7-harness-reconciliation: pass"
  exit 0
fi
echo "r7-harness-reconciliation: $FAILURES failing check(s)"
exit 1
