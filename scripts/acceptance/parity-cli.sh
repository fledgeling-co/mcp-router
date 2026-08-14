#!/usr/bin/env bash
#
# R2-R — the cli lane.
#
# The ten verbs `src/index.ts` dispatches. Eight are compared here; two are not, and saying which is
# the point of this header:
#   · `cli-watch` is R2-W's. There is no Swift watcher and this lane does not pretend otherwise.
#   · `cli-auth` is blocked on D-j. The verb exists on both sides, but the Swift router answers 405
#     on `POST /servers/:name/auth` where the reference answers 400, because `AuthRoutes` is never
#     reached from `ControlHandler`'s dispatch. Comparing the verb would compare that defect.
#
# **stdout, stderr and the exit code are captured separately and compared separately.** They differ
# per verb and a combined capture hides it: `status` writes "no router answering" to stdout and sets
# exitCode 1, while `usage` throws the same sentence, which `run().catch` writes to stderr behind a
# `mcp-router: ` prefix. A harness using `2>&1` would call those identical.
#
# Two per-run values are normalised, each a coordinate rather than a behaviour:
#   · the absolute home path, because the two binaries are run against two scratch homes;
#   · the millisecond epoch in `import`'s backup filename (`servers.json.bak-<Date.now()>`), which
#     is different on every run of either binary and cannot be made to agree.
# Nothing else is normalised.
#
# ROWS THIS LANE OWNS — asserted before any write, because the gate binds no script to a group:
#   cli: cli-serve cli-import cli-index cli-refresh cli-status cli-tools cli-usage cli-help
#
# CAVEAT, printed into the gate's report: every row here is a simultaneous comparison of two
# binaries run over identical inputs, which is as strong as this gate's control lane.
#
# Exit codes: 0 agreed, 1 a mismatch, 2 the environment could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWIFT_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
PORT="${CLI_PORT:-8994}"
WORK="$(mktemp -d -t parity-cli)"
RESULTS="${PARITY_RESULTS:-}"
SERVE_PID=""

MAIN_PID=$$
cleanup() {
  [ "$BASHPID" != "$MAIN_PID" ] && return 0
  [ -n "$SERVE_PID" ] && kill "$SERVE_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

OWNED="cli/cli-serve cli/cli-import cli/cli-index cli/cli-refresh cli/cli-status cli/cli-tools
cli/cli-usage cli/cli-help"

record() {
  [ -n "$RESULTS" ] || return 0
  case " $(echo $OWNED) " in
    *" $1/$2 "*) ;;
    *) echo "  LANE BUG: refusing to record $1/$2, which this lane does not own" >&2; return 1 ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$RESULTS"
}

pass=0; fail=0
verdict() { # id ok? message
  if [ "$2" = 1 ]; then
    pass=$((pass + 1)); printf '  ok   %-28s %s\n' "$1" "$3"; record cli "$1" ok "$3"
  else
    fail=$((fail + 1)); printf '  FAIL %-28s %s\n' "$1" "$3"; record cli "$1" fail "$3"
  fi
}

command -v node >/dev/null 2>&1 || { echo "environment: node is not installed"; exit 2; }
[ -f "$REPO_ROOT/dist/index.js" ] || { echo "environment: no dist/index.js. Run npm run build."; exit 2; }
[ -x "$SWIFT_BIN" ] || { echo "environment: no Swift router at ${SWIFT_BIN#"$REPO_ROOT/"}"; exit 2; }
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "environment: something is already listening on :$PORT"; exit 2
fi

# One declaration, two homes. Each verb runs against its own side's copy so neither can see what the
# other wrote.
seed() { # dir
  mkdir -p "$1"
  echo "toolset" > "$1/toolset"
  cat > "$1/servers.json" <<JSON
{
  "port": 8879,
  "host": "127.0.0.1",
  "idleMs": 300000,
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

# `<home>` for the directory, `<epoch>` for import's backup stamp, `<ts>` for the ISO timestamp that
# opens every log line, and `<ms>` for a measured duration. All four are clocks or coordinates; no
# message text, level, ordering or count is touched.
normalise() { sed -e "s|$WORK/ts|<home>|g" -e "s|$WORK/swift|<home>|g" \
                  -e 's/\.bak-[0-9][0-9]*/.bak-<epoch>/g' \
                  -e 's/^[0-9][0-9]*-[0-9][0-9]-[0-9][0-9]T[0-9:.]*Z/<ts>/' \
                  -e 's/[0-9][0-9]*ms/<ms>ms/g' -e 's/[0-9][0-9]*s alive/<s>s alive/g'; }

# Run one verb at both binaries against fresh copies, and compare the three observables.
run_both() { # id label -- args...
  local id="$1" label="$2"; shift 3
  rm -rf "$WORK/ts" "$WORK/swift"; seed "$WORK/ts"; seed "$WORK/swift"
  # An optional preparation verb, run on each side with its OWN binary. Without it every verb here
  # runs against a freshly seeded home, so a verb whose output depends on built state — `tools`
  # reading a manifest — was only ever compared in its empty case, and a populated surface that
  # sorted differently or aligned its columns differently could not be seen.
  if [ -n "${PREP:-}" ]; then
    MCP_ROUTER_HOME="$WORK/ts" node "$REPO_ROOT/dist/index.js" $PREP >/dev/null 2>&1
    MCP_ROUTER_HOME="$WORK/swift" "$SWIFT_BIN" $PREP >/dev/null 2>&1
  fi

  MCP_ROUTER_HOME="$WORK/ts" node "$REPO_ROOT/dist/index.js" "$@" \
    >"$WORK/ts.out" 2>"$WORK/ts.err"; local ts_code=$?
  MCP_ROUTER_HOME="$WORK/swift" "$SWIFT_BIN" "$@" \
    >"$WORK/swift.out" 2>"$WORK/swift.err"; local sw_code=$?

  local problems=""
  diff <(normalise <"$WORK/ts.out") <(normalise <"$WORK/swift.out") >"$WORK/d.out" 2>&1 \
    || problems="$problems stdout:[$(head -4 "$WORK/d.out" | tr '\n' ' ' | cut -c1-110)]"
  diff <(normalise <"$WORK/ts.err") <(normalise <"$WORK/swift.err") >"$WORK/d.err" 2>&1 \
    || problems="$problems stderr:[$(head -4 "$WORK/d.err" | tr '\n' ' ' | cut -c1-110)]"
  [ "$ts_code" = "$sw_code" ] || problems="$problems exit:[ts=$ts_code swift=$sw_code]"

  if [ -z "$problems" ]; then
    verdict "$id" 1 "$label (exit $ts_code, stdout and stderr identical)"
  else
    verdict "$id" 0 "$label —$problems"
  fi
}

echo "comparing both binaries verb by verb"
echo

# `help` is four separate arms in src/index.ts:360-365 — `help`, `--help`, `-h`, and the default arm
# an unknown verb falls through to. The note claimed all four and ran only the first, so an `-h` that
# printed nothing, or an unknown verb exiting 0 where the reference exits 1, would have stayed green.
# Four invocations, one row: parity-gate.sh:172 makes any `fail` beat a later `ok`.
run_both cli-help   "help prints the usage block"        -- help
run_both cli-help   "--help is the same arm"             -- --help
run_both cli-help   "-h is the same arm"                 -- -h
run_both cli-help   "an unknown verb falls to help"      -- not-a-real-verb
run_both cli-tools  "tools lists the cached surface"     -- tools
# And the populated case. `run_both` re-seeds before every verb, so `tools` above only ever saw an
# empty manifest — the case where both binaries printing nothing agrees trivially.
PREP=index
run_both cli-tools  "tools lists a populated surface"    -- tools
PREP=""
run_both cli-index  "index builds the manifest"          -- index
run_both cli-refresh "refresh is the same arm as index"  -- refresh
run_both cli-usage  "usage with nothing listening"       -- usage --port "$PORT"
run_both cli-status "status with nothing listening"      -- status --port "$PORT"

# `import`, against one `~/.claude.json` copy. The written `servers.json` is compared as well as the
# stdout, because the file is the point of the verb and identical output over different files would
# be the most misleading pass available.
rm -rf "$WORK/ts" "$WORK/swift"; seed "$WORK/ts"; seed "$WORK/swift"
cat > "$WORK/claude.json" <<JSON
{
  "mcpServers": {
    "probe": {
      "command": "node",
      "args": ["$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs", "stdio"],
      "env": { "FIXTURE_TOOLSET_FILE": "$WORK/toolset" }
    },
    "broken": { "command": "/nonexistent/definitely-not-a-server" },
    "notadoptable": { "note": "no command and no url" }
  }
}
JSON
echo "toolset" > "$WORK/toolset"
MCP_ROUTER_HOME="$WORK/ts" node "$REPO_ROOT/dist/index.js" import --from "$WORK/claude.json" \
  >"$WORK/ts.out" 2>"$WORK/ts.err"; ts_code=$?
MCP_ROUTER_HOME="$WORK/swift" "$SWIFT_BIN" import --from "$WORK/claude.json" \
  >"$WORK/swift.out" 2>"$WORK/swift.err"; sw_code=$?
import_problems=""
diff <(normalise <"$WORK/ts.out") <(normalise <"$WORK/swift.out") >"$WORK/d.out" 2>&1 \
  || import_problems="$import_problems stdout:[$(head -4 "$WORK/d.out" | tr '\n' ' ' | cut -c1-110)]"
[ "$ts_code" = "$sw_code" ] || import_problems="$import_problems exit:[ts=$ts_code swift=$sw_code]"
diff <(normalise <"$WORK/ts/servers.json") <(normalise <"$WORK/swift/servers.json") \
  >"$WORK/d.cfg" 2>&1 \
  || import_problems="$import_problems servers.json:[$(head -6 "$WORK/d.cfg" | tr '\n' ' ' | cut -c1-110)]"
if [ -z "$import_problems" ]; then
  verdict cli-import 1 "import adopts the same servers and writes the same servers.json"
else
  verdict cli-import 0 "import —$import_problems"
fi

# `serve`: both bind, both answer /health, both write the same log lines, both exit 0 on SIGTERM.
# The reference emits exactly three distinct lines across a serve-to-SIGTERM session with one
# already-indexed upstream and no traffic — listening, serving, and the signal — so three is what is
# compared, not a rounder number.
serve_side() { # dir binary... -> prints "health-status|exit-code"
  local home="$1"; shift
  if [ "$1" = node ]; then
    MCP_ROUTER_HOME="$home" node "$REPO_ROOT/dist/index.js" serve --port "$PORT" \
      >"$home/serve.out" 2>&1 &
  else
    MCP_ROUTER_HOME="$home" "$SWIFT_BIN" serve --port "$PORT" >"$home/serve.out" 2>&1 &
  fi
  SERVE_PID=$!
  local health=missing
  for _ in $(seq 1 80); do
    if curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then health=ok; break; fi
    kill -0 "$SERVE_PID" 2>/dev/null || break
    sleep 0.25
  done
  kill -TERM "$SERVE_PID" 2>/dev/null
  wait "$SERVE_PID" 2>/dev/null; local code=$?
  SERVE_PID=""
  # The WHOLE of what serve wrote, normalised for clocks and coordinates only.
  #
  # This used to be a three-literal `grep -oE` allowlist, which discarded every other line either
  # binary wrote instead of comparing it — the one place in these five lanes where normalisation
  # removed content rather than a clock or a coordinate. A Swift runtime warning, an NWListener
  # error, or a duplicated listening line all survived it untouched. It was also concealing a real
  # line: both routers open with `wrote a new control token -> <path>`, which the allowlist dropped.
  # Both sides get their own freshly seeded home, so that line appears on both or neither.
  normalise < "$home/serve.out" | tr '\n' ',' > "$home/serve.lines"
  printf '%s|%s' "$health" "$code"
}
rm -rf "$WORK/ts" "$WORK/swift"; seed "$WORK/ts"; seed "$WORK/swift"
MCP_ROUTER_HOME="$WORK/ts" node "$REPO_ROOT/dist/index.js" index >/dev/null 2>&1
MCP_ROUTER_HOME="$WORK/swift" "$SWIFT_BIN" index >/dev/null 2>&1
ts_serve="$(serve_side "$WORK/ts" node)"
sleep 1
sw_serve="$(serve_side "$WORK/swift" swift)"
ts_lines="$(cat "$WORK/ts/serve.lines" 2>/dev/null)"
sw_lines="$(cat "$WORK/swift/serve.lines" 2>/dev/null)"
if [ "$ts_serve" = "$sw_serve" ] && [ "$ts_serve" = "ok|0" ] && [ "$ts_lines" = "$sw_lines" ]; then
  verdict cli-serve 1 "both bound, answered /health, logged [$ts_lines] and exited 0 on SIGTERM"
else
  verdict cli-serve 0 "reference=$ts_serve lines=[$ts_lines]; swift=$sw_serve lines=[$sw_lines]"
fi

echo
echo "cli: $pass verbs agreed, $fail did not"
echo "     Every row is a simultaneous comparison of two binaries over identical inputs, with"
echo "     stdout, stderr and the exit code compared separately."
echo "     cli-watch stays blocked on R2-W and cli-auth on D-j; neither is claimed here."
[ "$fail" -gt 0 ] && exit 1
exit 0
