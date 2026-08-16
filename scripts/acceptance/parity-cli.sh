#!/usr/bin/env bash
#
# R2-R — the cli lane.
#
# The ten verbs `src/index.ts` dispatches. Nine are compared here, and saying which is the point of
# this header:
#   · `cli-auth` was blocked on this lane having no running router for the verb: `auth` POSTs to a
#     live daemon and then polls the auth dir, so with `run_both` starting none, a comparison was
#     two connection failures agreeing with each other. P5 closed that (D-p1-d) with the
#     serve-backed `auth_case` below, which starts a router per side and refuses to pass a run in
#     which either router failed to answer. Its non-stdio path stays uncompared and is carried by
#     the `control-auth-post-http` row, not duplicated here — see that block's own header.
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
#        cli-watch cli-auth
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
cli/cli-usage cli/cli-help cli/cli-watch cli/cli-auth"

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

# ---------------------------------------------------------------------------------------------
# `auth` — D-p1-d, closed here.
#
# This is the one verb in the lane that is meaningless without a router already listening. It POSTs
# to `/servers/:name/auth` on a LIVE daemon, reads the reply, and only then either opens a browser
# or reports the router's own `error` member. `run_both` starts no router, so running `auth` through
# it compared two *connection failures* — both binaries printing
# `no router answering on 127.0.0.1:<port> (fetch failed) — start it first` and agreeing about it.
# That is the canonical false green: the sentence agrees precisely because neither side reached any
# of the code the row is meant to cover.
#
# So the router is started first, per side, and the verb is run against it. Two guards make the old
# false green unreachable rather than merely unlikely, because the failure mode is *silent*:
#
#   1. `/health` must have answered on that side. A router that never bound sends the verb straight
#      back down the connection-failure path, where the two binaries agree for the wrong reason.
#      A missing health answer is therefore an environment failure, never a pass.
#   2. The captured stderr must NOT carry `no router answering`. That is the same failure caught a
#      second way, independent of the health probe — a router that bound and then died between the
#      probe and the verb would clear guard 1 and be caught here.
#
# WHAT IS COMPARED, AND WHAT IS NOT. Two invocations, both of which reach the router and come back
# with a status and a JSON body the verb has to interpret:
#
#   · a STDIO upstream — the reference answers 400 `stdio servers do not authorize; their
#     credentials are env vars`, and the verb has to lift `error` out of the body and fail with it;
#   · an UNKNOWN server — a different status and a different body, so the same extraction is
#     exercised on a second shape rather than on one.
#
# The NON-STDIO path is not compared here and its absence is not agreement: the reference answers
# 200 with an `authorizationUrl` and this router answers 405, because nothing conforms to
# `AuthTransport`. That is `D-p1-a`, and it is already enumerated as its own manifest row,
# `control-auth-post-http`. It is deliberately NOT duplicated as a second blocked cli row: one
# missing capability counted twice would understate coverage exactly as double-counting a proven
# row would overstate it, and the row that carries it already names the same owner.
#
# It is also not something this lane could run even once D-p1-a lands. A successful start binds the
# fixed callback port :8880 for the flow's lifetime and shells out to `/usr/bin/open`, which on this
# machine would put a real browser window in front of whoever is running the gate.
auth_side() { # home side -- args...  -> prints "health|exit"
  local home="$1" side="$2"; shift 3
  if [ "$side" = node ]; then
    MCP_ROUTER_HOME="$home" node "$REPO_ROOT/dist/index.js" serve --port "$PORT" \
      >"$home/authserve.out" 2>&1 &
  else
    MCP_ROUTER_HOME="$home" "$SWIFT_BIN" serve --port "$PORT" >"$home/authserve.out" 2>&1 &
  fi
  SERVE_PID=$!
  local health=missing
  for _ in $(seq 1 80); do
    if curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then health=ok; break; fi
    kill -0 "$SERVE_PID" 2>/dev/null || break
    sleep 0.25
  done
  local code=0
  if [ "$side" = node ]; then
    MCP_ROUTER_HOME="$home" node "$REPO_ROOT/dist/index.js" "$@" --port "$PORT" \
      >"$home/auth.out" 2>"$home/auth.err"; code=$?
  else
    MCP_ROUTER_HOME="$home" "$SWIFT_BIN" "$@" --port "$PORT" \
      >"$home/auth.out" 2>"$home/auth.err"; code=$?
  fi
  kill -TERM "$SERVE_PID" 2>/dev/null
  wait "$SERVE_PID" 2>/dev/null
  SERVE_PID=""
  printf '%s|%s' "$health" "$code"
}

auth_case() { # label -- verb args...
  local label="$1"; shift 2
  rm -rf "$WORK/ts" "$WORK/swift"; seed "$WORK/ts"; seed "$WORK/swift"
  local ts sw
  ts="$(auth_side "$WORK/ts" node -- "$@")"
  sleep 1
  sw="$(auth_side "$WORK/swift" swift -- "$@")"

  local problems=""
  # Guard 1 — both routers answered. Checked BEFORE the diff, because a diff of two
  # connection-failure messages is the pass this row exists to stop being possible.
  [ "${ts%%|*}" = ok ] || problems="$problems reference-router:[did not answer /health]"
  [ "${sw%%|*}" = ok ] || problems="$problems swift-router:[did not answer /health]"
  # Guard 2 — and the verb reached it.
  grep -q "no router answering" "$WORK/ts/auth.err" 2>/dev/null &&
    problems="$problems reference:[fell back to the no-router path]"
  grep -q "no router answering" "$WORK/swift/auth.err" 2>/dev/null &&
    problems="$problems swift:[fell back to the no-router path]"

  diff <(normalise <"$WORK/ts/auth.out") <(normalise <"$WORK/swift/auth.out") >"$WORK/d.out" 2>&1 \
    || problems="$problems stdout:[$(head -4 "$WORK/d.out" | tr '\n' ' ' | cut -c1-110)]"
  diff <(normalise <"$WORK/ts/auth.err") <(normalise <"$WORK/swift/auth.err") >"$WORK/d.err" 2>&1 \
    || problems="$problems stderr:[$(head -4 "$WORK/d.err" | tr '\n' ' ' | cut -c1-110)]"
  [ "${ts##*|}" = "${sw##*|}" ] || problems="$problems exit:[ts=${ts##*|} swift=${sw##*|}]"

  if [ -z "$problems" ]; then
    verdict cli-auth 1 "$label (both routers answered; exit ${ts##*|}, stdout and stderr identical)"
  else
    verdict cli-auth 0 "$label —$problems"
  fi
}

auth_case "auth against a stdio upstream, router listening" -- auth probe
auth_case "auth against an unknown server, router listening" -- auth nope

# `watch` — the config watcher. Each side gets its OWN scratch $HOME as well as its own
# MCP_ROUTER_HOME, because `~/.claude.json` is the input and it is NOT under the router home. node's
# `os.homedir()` honours $HOME and the Swift watcher reads the same variable (spec-R2W X10); a
# watcher that read `NSHomeDirectory()` instead would run this against the developer's own file.
#
# NOTHING HERE RESTARTS A ROUTER. Measured 2026-08-15: `gg.rhodes.mcp-router` is loaded and serving
# on this machine, and the reference's kickstart label is hardcoded and absolute
# (`/bin/launchctl`, watch.ts:367), so a scenario that changed servers.json would bounce the
# developer's live router from the reference side. Scenario 2 therefore pre-seeds servers.json with
# the same definition that is staged: the entry is still indexed, still adopted and still deleted
# from ~/.claude.json, but `configChanged` stays false on both sides (watch.ts:273) and neither
# router issues a restart. The Swift side additionally runs under a scratch MCPR_LAUNCHD_LABEL.
#
# The FILES are the point of this verb, as `import` already recognised, so `servers.json` and the
# remaining `~/.claude.json` are diffed as well as the three streams. `manifest.json` is NOT: its
# entries carry `builtAt` at millisecond resolution, two binaries run in sequence cannot produce
# equal bytes, and normalising that away would mean adding a time normaliser to a lane whose header
# says only clocks and coordinates are normalised. Manifest parity is the fixture and state lanes'.
watch_seed() { # dir  -- writes a scratch HOME with the given staging file on stdin
  mkdir -p "$1/.claude/mcp-router"
  cat > "$1/.claude.json"
}

watch_both() { # label -- staged-json router-servers-json
  local label="$1" staged="$2" servers="$3"
  rm -rf "$WORK/home-ts" "$WORK/home-swift" "$WORK/ts" "$WORK/swift"
  mkdir -p "$WORK/ts" "$WORK/swift"
  for side in ts swift; do
    local home="$WORK/home-$side"
    mkdir -p "$home"
    printf '%s' "$staged" | watch_seed "$home"
    printf '%s' "$servers" > "$WORK/$side/servers.json"
  done

  HOME="$WORK/home-ts" MCP_ROUTER_HOME="$WORK/ts" \
    node "$REPO_ROOT/dist/index.js" watch --verbose \
    >"$WORK/ts.out" 2>"$WORK/ts.err"; local ts_code=$?
  HOME="$WORK/home-swift" MCP_ROUTER_HOME="$WORK/swift" \
    MCPR_LAUNCHD_LABEL="gg.rhodes.mcp-router-parity-$$" \
    "$SWIFT_BIN" watch --verbose \
    >"$WORK/swift.out" 2>"$WORK/swift.err"; local sw_code=$?

  local problems=""
  diff <(normalise <"$WORK/ts.out") <(normalise <"$WORK/swift.out") >"$WORK/d.out" 2>&1 \
    || problems="$problems stdout:[$(head -4 "$WORK/d.out" | tr '\n' ' ' | cut -c1-110)]"
  diff <(normalise <"$WORK/ts.err") <(normalise <"$WORK/swift.err") >"$WORK/d.err" 2>&1 \
    || problems="$problems stderr:[$(head -4 "$WORK/d.err" | tr '\n' ' ' | cut -c1-110)]"
  [ "$ts_code" = "$sw_code" ] || problems="$problems exit:[ts=$ts_code swift=$sw_code]"
  diff <(normalise <"$WORK/ts/servers.json") <(normalise <"$WORK/swift/servers.json") \
    >"$WORK/d.cfg" 2>&1 \
    || problems="$problems servers.json:[$(head -6 "$WORK/d.cfg" | tr '\n' ' ' | cut -c1-110)]"
  diff <(normalise <"$WORK/home-ts/.claude.json") <(normalise <"$WORK/home-swift/.claude.json") \
    >"$WORK/d.stage" 2>&1 \
    || problems="$problems claude.json:[$(head -6 "$WORK/d.stage" | tr '\n' ' ' | cut -c1-110)]"

  if [ -z "$problems" ]; then
    verdict cli-watch 1 "$label (exit $ts_code; streams, servers.json and ~/.claude.json identical)"
  else
    verdict cli-watch 0 "$label —$problems"
  fi
}

WATCH_PROBE='{
  "numStartups": 41,
  "mcpServers": {
    "probe": {
      "command": "node",
      "args": ["'"$REPO_ROOT"'/scripts/fixtures/mcp-fixture-server.mjs", "stdio"],
      "env": { "FIXTURE_TOOLSET_FILE": "'"$WORK"'/toolset" }
    }
  }
}'
WATCH_EMPTY='{ "numStartups": 41, "mcpServers": {} }'
WATCH_SERVERS_EMPTY='{
  "port": 8879,
  "host": "127.0.0.1",
  "idleMs": 300000,
  "mcpServers": {}
}'
WATCH_SERVERS_SEEDED='{
  "port": 8879,
  "host": "127.0.0.1",
  "idleMs": 300000,
  "mcpServers": {
    "probe": {
      "command": "node",
      "args": ["'"$REPO_ROOT"'/scripts/fixtures/mcp-fixture-server.mjs", "stdio"],
      "env": { "FIXTURE_TOOLSET_FILE": "'"$WORK"'/toolset" }
    }
  }
}'
echo "toolset" > "$WORK/toolset"

watch_both "nothing staged takes the fast path" "$WATCH_EMPTY" "$WATCH_SERVERS_EMPTY"
watch_both "a staged server is indexed, adopted and unstaged" "$WATCH_PROBE" "$WATCH_SERVERS_SEEDED"
watch_both "an unparseable ~/.claude.json writes nothing" "{ truncated" "$WATCH_SERVERS_EMPTY"

echo
echo "cli: $pass verbs agreed, $fail did not"
echo "     Every row is a simultaneous comparison of two binaries over identical inputs, with"
echo "     stdout, stderr and the exit code compared separately."
echo "     cli-auth IS claimed here now (D-p1-d, closed by P5): the verb is run against a router"
echo "     this lane started, and a run in which either router failed to answer /health is a"
echo "     failure rather than a pass — without that guard the two binaries agree on the"
echo "     no-router sentence and the row passes having reached none of its own code."
echo "     Its non-stdio path is NOT compared here and is not counted twice: the reference"
echo "     answers 200 with an authorizationUrl where this router answers 405, which is D-p1-a"
echo "     and is carried by the control-auth-post-http row."
[ "$fail" -gt 0 ] && exit 1
exit 0
