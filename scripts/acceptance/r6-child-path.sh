#!/usr/bin/env bash
#
# R6 — the PATH a spawned child inherits, measured at both routers.
#
# The defect: launchd hands the router a fixed PATH, every stdio child inherits it, and a routed
# server that shells out to a CLI installed under the user's home reports the capability
# unavailable rather than failing. `planning/specs/spec-R6.md` carries the measurement.
#
# This lane spawns a real child through each router and reads the PATH the child actually saw. It
# never touches the developer's `$HOME`, their launchd session or their `~/.claude.json`: HOME and
# MCP_ROUTER_HOME both point at a scratch directory, and the servers.json it indexes is one this
# script wrote.
#
# The fixture is deliberately reachable through exactly one directory — `$SCRATCH_HOME/.fixture/bin`
# — and the PATH the routers are given names none of it. So a child that starts at all is proof the
# discovery ran, and a child that does not start under the pre-change PATH is the red half.
#
# Exit codes: 0 both routers gave the child the same PATH and it carried the fixture directory,
# 1 they did not, 2 the environment could not run the lane.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d -t r6-child-path)"
# The PATH docs/install.sh writes into the plist, with the node directory filled in at run time.
NODE_BIN="$(command -v node 2>/dev/null || true)"
SWIFT_BIN="${MCPR_ROUTER_BINARY:-$REPO_ROOT/app/.build/release/MCPRouterCLI}"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

[ -n "$NODE_BIN" ] || { echo "environment: node is not installed"; exit 2; }
[ -f "$REPO_ROOT/dist/index.js" ] || {
  echo "environment: no built reference at dist/index.js. Run npm run build."
  echo "             A skipped lane is recorded as blocked, not as a pass."; exit 2; }
[ -x "$SWIFT_BIN" ] || {
  echo "environment: no Swift router at $SWIFT_BIN."
  echo "             Run (cd app && swift build -c release --product MCPRouterCLI)."; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "environment: python3 is not installed"; exit 2; }

LAUNCHD_PATH="$(dirname "$NODE_BIN"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
SCRATCH_HOME="$WORK/home"
FIXTURE_DIR="$SCRATCH_HOME/.fixture/bin"
mkdir -p "$FIXTURE_DIR"

# A minimal MCP server over stdio that answers `initialize`, then writes the environment it was
# launched with and exits when its input closes. It is the oracle: whatever it records is what the
# router actually handed it.
cat > "$WORK/report-env.py" <<'PY'
import json, os, sys

out = os.environ["R6_REPORT_TO"]
with open(out, "w") as handle:
    json.dump({"PATH": os.environ.get("PATH", "")}, handle)

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    message = json.loads(line)
    if message.get("method") == "initialize":
        sys.stdout.write(json.dumps({
            "jsonrpc": "2.0", "id": message["id"],
            "result": {
                "protocolVersion": message["params"]["protocolVersion"],
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "r6-report-env", "version": "0"},
            },
        }) + "\n")
        sys.stdout.flush()
    elif message.get("method") == "tools/list":
        sys.stdout.write(json.dumps({
            "jsonrpc": "2.0", "id": message["id"], "result": {"tools": []},
        }) + "\n")
        sys.stdout.flush()
PY

# The wrapper is what the config names, and it exists nowhere on the given PATH. python3 is called
# by absolute path so what is proved is the resolution of the wrapper, not a second lookup inside it.
PYTHON_BIN="$(command -v python3)"
cat > "$FIXTURE_DIR/mcpr-r6-fixture" <<SHIM
#!/bin/sh
exec "$PYTHON_BIN" "\$@"
SHIM
chmod +x "$FIXTURE_DIR/mcpr-r6-fixture"

failures=0
examined=0
fail() { echo "  FAIL: $*"; failures=$((failures + 1)); }
ok() { echo "  ok: $*"; }

# No PARITY_RESULTS row is written. `parity-gate.sh` reports a result whose id is not in
# `planning/parity/surface.tsv` as an orphan, and adding a census row would move `# rows:` and
# force `PARITY_CUTOVER_TARGET`, which the owner set on 2026-08-16. This lane is dispatched by
# `make acceptance-r6`, not by the parity suite.

# Index one server through one router, under a scratch home, and print the PATH its child saw.
# Prints nothing and returns 1 when the child never started.
read_child_path() { # label, command-words...
  local label="$1"; shift
  local home="$WORK/$label"
  mkdir -p "$home"
  cat > "$home/servers.json" <<JSON
{"mcpServers":{"reporter":{"command":"mcpr-r6-fixture","args":["$WORK/report-env.py"],"env":{"R6_REPORT_TO":"$home/child-env.json"}}}}
JSON
  HOME="$SCRATCH_HOME" \
  MCP_ROUTER_HOME="$home" \
  PATH="$LAUNCHD_PATH" \
    "$@" index > "$home/index.out" 2> "$home/index.err"
  [ -f "$home/child-env.json" ] || return 1
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["PATH"])' "$home/child-env.json"
}

echo "R6 — the PATH a spawned child inherits"
echo "  launchd PATH: $LAUNCHD_PATH"
echo "  fixture:      $FIXTURE_DIR/mcpr-r6-fixture"
echo

# The red half. A child given only the launchd PATH cannot resolve the fixture, so no child starts
# and no environment is recorded. This runs the SAME routers with discovery disabled by pointing
# HOME at a directory with no bin directories in it — the pre-change environment, reproduced rather
# than remembered.
BARE_HOME="$WORK/bare-home"
mkdir -p "$BARE_HOME"
examined=$((examined + 1))
before_home="$WORK/before"
mkdir -p "$before_home"
cat > "$before_home/servers.json" <<JSON
{"mcpServers":{"reporter":{"command":"mcpr-r6-fixture","args":["$WORK/report-env.py"],"env":{"R6_REPORT_TO":"$before_home/child-env.json"}}}}
JSON
HOME="$BARE_HOME" MCP_ROUTER_HOME="$before_home" PATH="$LAUNCHD_PATH" \
  "$SWIFT_BIN" index > "$before_home/index.out" 2> "$before_home/index.err"
before_status=$?
# The red half asserts the REASON, not merely the absence of a child. A crash, a config the router
# could not read, or a removed pre-check that turns into a startup timeout all produce no
# child-env.json, and accepting any of them would report a green for a lane that measured nothing.
if [ -f "$before_home/child-env.json" ]; then
  fail "the fixture resolved with no discoverable directory; the lane is measuring the wrong thing"
elif ! grep -q 'spawn mcpr-r6-fixture ENOENT' "$before_home/index.out" "$before_home/index.err"; then
  fail "before: no child started, but not for the reason this lane is about (exit $before_status)"
  sed -n '1,6p' "$before_home/index.out" "$before_home/index.err" | sed 's/^/    /'
else
  ok "before: no child started — spawn mcpr-r6-fixture ENOENT (exit $before_status)"
fi

examined=$((examined + 1))
if swift_path="$(read_child_path swift "$SWIFT_BIN")"; then
  ok "swift: the child started"
else
  fail "swift: no child started under the augmented PATH"
  swift_path=""
fi

examined=$((examined + 1))
if node_path="$(read_child_path node "$NODE_BIN" "$REPO_ROOT/dist/index.js")"; then
  ok "node:  the child started"
else
  fail "node:  no child started under the augmented PATH"
  node_path=""
fi

examined=$((examined + 1))
if [ -n "$swift_path" ] && [ "$swift_path" = "$node_path" ]; then
  ok "both routers handed the child the same PATH"
else
  fail "the two routers disagree"
  echo "    swift: $swift_path"
  echo "    node:  $node_path"
fi

examined=$((examined + 1))
case ":$swift_path:" in
  *":$FIXTURE_DIR:"*) ok "the fixture directory is on the child's PATH" ;;
  *) fail "the fixture directory is absent from the child's PATH" ;;
esac

examined=$((examined + 1))
case "$swift_path" in
  "$LAUNCHD_PATH"*) ok "launchd's entries keep their order and their place at the front" ;;
  *) fail "the inherited PATH was reordered; a child could resolve a different binary than before" ;;
esac

echo
echo "child PATH after: $swift_path"
echo "examined=$examined failures=$failures"
if [ "$failures" -eq 0 ]; then
  exit 0
fi
exit 1
