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
# runs, adopts what it can, and exits. Four observations per binary: it ran at load, a stamped
# change written to the path its own plist watches was OBSERVED by the run that followed, it did
# not stay resident, and which streams carry bytes. The second of those lives in
# `parity-install-watch.sh`, which is also what the mutation harness runs — see its header.
#
# Nothing in this lane restarts a real router. The staged `mcpServers` holds nothing adoptable, so
# neither binary reaches its `restartRouter()`, and the Swift side additionally runs under a scratch
# MCPR_LAUNCHD_LABEL.
#
# ROWS THIS LANE OWNS:  install: install-launchd-serve install-launchd-watch
#                               install-import-servers install-claude-json
#                               install-rollback
#
# CAVEAT, printed into the gate's report: two real agents under real launchd supervision, one per
# binary, compared observation by observation. It does NOT run `docs/install.sh` itself — that would
# rewrite the user's own `~/.claude.json` and load agents into their session.
#
# P2 added the two on-disk rows the installer produces, and both are driven the same way the
# supervision rows are: the step is reproduced under installer-equivalent conditions rather than by
# running the installer. `install-import-servers` runs `import` exactly as `install.sh:77` does —
# no `--from`, no `MCP_ROUTER_HOME`, scratch `HOME`. `install-claude-json` runs the `node -e` body
# EXTRACTED FROM install.sh at run time on the reference side, against `install-entry` on the Swift
# side.
#
# What that does NOT establish, and the manifest note says so too: `docs/install.sh` still invokes
# `node` for both steps. Flipping the caller is `D-p2-b` / R4-C's, and this lane going green is not
# evidence that it happened.
#
# `install-rollback` extracts the restore `node -e` from `docs/uninstall.sh` the same way
# `install-claude-json` extracts install.sh. It never runs uninstall.sh: that script bootouts
# `gg.rhodes.mcp-router*` and deletes `$HOME/Library/LaunchAgents` plists regardless of a scratch
# HOME. The fixture is Swift-cutover shaped — adopted servers live only in servers.json; claude.json
# holds the mcp-router HTTP entry plus a hand-defined name — because import does not strip stdio
# keys, and a restore against leftovers is a no-op (`if (claude.mcpServers[name]) continue`).
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
  # The watch half's labels come from a file, not from `$LABELS`. Both `observe` and `observe_watch`
  # are called through command substitution, so the accumulator they append to belongs to a subshell
  # and is empty here — which means this loop has never had anything to boot out, and a run killed
  # part-way through would leave a scratch agent loaded in the user's session.
  while read -r watch_label; do
    [ -n "$watch_label" ] && launchctl bootout "gui/$(id -u)/$watch_label" >/dev/null 2>&1
  done < "${WATCH_LABELS:-/dev/null}"
  rm -rf "$WORK"
}
trap cleanup EXIT

record() {
  [ -n "$RESULTS" ] || return 0
  case "$1/$2" in
    install/install-launchd-serve|install/install-launchd-watch) ;;
    install/install-import-servers|install/install-claude-json) ;;
    install/install-rollback) ;;
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

# ---------------------------------------------------------------------------------------------
# `install-launchd-watch` — the watch agent's observation, sourced rather than written here.
#
# It moved into its own file (P8) so the mutation harness that proves its terms can go red runs THE
# SAME CODE this lane runs. The alternative — a harness with its own copy of the observation — is
# how a term stays green under a mutation aimed at the copy; and a term of this row's is on record
# as having agreed sixteen times while measuring the wrong thing.
#
# It needs `WORK`, `STAMP`, `LAUNCHD_PATH` and `LABELS`, all set above, and it appends to `LABELS`
# so this lane's `cleanup` boots out what it bootstrapped.
. "$REPO_ROOT/scripts/acceptance/parity-install-watch.sh"

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
echo "  (ran-at-load, observed-the-staged-change, one-shot-not-resident, log-streams-written)"
echo "  launchd's own accounting: $(cat "$WATCH_EVIDENCE" 2>/dev/null)"
echo "  \`stages\` is deliveries used over deliveries allowed: how many times the watched file had to"
echo "  be changed before a run observed one. More than 1 is launchd coalescing or dropping a"
echo "  delivery, not a router misbehaving. \`stamp\` is WHICH staged change came back, named by the"
echo "  run that saw it, and it is what makes the second term an observation rather than a spawn"
echo "  count. \`watched=self\` means the agent watches the file it reads."
echo

case "$ts_watch$swift_watch" in
  *bootstrap-refused*)
    echo "environment: launchd refused to bootstrap a scratch watch agent in this session, so the"
    echo "             watch supervision contract could not be exercised on either side."
    exit 2 ;;
  *no-watchpaths-in-plist*)
    echo "environment: the generated watch plist carried no readable WatchPaths entry, so the lane"
    echo "             could not tell where to deliver the stimulus. Recording agreement without"
    echo "             knowing that would be the false green this row exists to refuse."
    exit 2 ;;
esac

# `install-launchd-watch` — MEASURED AND RECORDED (P8). The term, its defect and its fix are
# argued in `parity-install-watch.sh`; the rates behind this claim are measured by
# `parity-install-watch-mutations.sh`, which runs that same file.
#
# The bar for this one row is higher than for any other in the manifest, and it was earned. It was
# `proven` once on a term that counted launchd spawns, and a proven row whose lane disagrees reports
# DIVERGED — which reads as "the two routers behave differently" when what happened was a lane
# losing a coin toss. P1 measured six consecutive runs agreeing 1 in 6. G1 fixed two real mechanisms
# and DELIBERATELY DID NOT CLAIM THE ROW. P5 fixed both terms, ran an eight-pair series that passed
# on all sixteen observations, and withdrew the claim anyway — on a mutation the series could not
# see, because a series bounds the AGREEMENT rate and what was broken was what the term MEASURED.
#
# So the claim is made here on the mutation, not on a series. `reran` now requires the run to name
# the change it observed, and the stimulus goes to the path the agent's own plist declares, so an
# agent watching something nothing it reads will ever see cannot satisfy it. The harness scores the
# `runs`-only term it replaces on the SAME trials, which makes the improvement a measured delta
# rather than an argument.
if [ "$ts_watch" = "$swift_watch" ] && [ "${swift_watch%,*}" = "yes,yes,yes" ]; then
  echo "  ok   both binaries ran at load, observed the stamped change staged into the path their own"
  echo "       plist watches, and stayed one-shot ($ts_watch)"
  record install install-launchd-watch ok \
    "both: ran at load; re-ran on the watched change and named the stamp that run observed; stayed one-shot; $(tr -s ' ' <"$WATCH_EVIDENCE")"
else
  echo "  FAIL the two binaries did not answer the same watch supervision"
  echo "       (reference=$ts_watch swift=$swift_watch; ran,reran,one-shot,logged)"
  record install install-launchd-watch fail \
    "reference=$ts_watch swift=$swift_watch (ran,reran,one-shot,logged); $(tr -s ' ' <"$WATCH_EVIDENCE")"
  failures=$((failures + 1))
fi

echo
# ---------------------------------------------------------------------------------------------
# P2 — the two on-disk rows the installer produces.
#
# Both are differentials over the SAME inputs with the destination isolated per side. Every
# invocation carries a scratch HOME, because `import` with no `--from` reads `~/.claude.json` and
# writes `$HOME/.claude/mcp-router/` — running either binary without one would adopt from, and
# rewrite, the developer's own files.

# `<home>` for the two scratch directories and `<epoch>` for import's backup stamp. Clocks and
# coordinates only; no message text, ordering or count is touched. Without this the rows are
# permanently red on absolute paths, and the tempting fix is to stop comparing stdout at all.
norm() { sed -e "s|$1|<home>|g" -e 's/\.bak-[0-9][0-9]*/.bak-<epoch>/g'; }

mode_of() { stat -f '%Lp' "$1" 2>/dev/null || echo "missing"; }

# `install.sh:77` — `node dist/index.js import`, with no --from and no MCP_ROUTER_HOME.
import_side() { # home binary...
  local home="$1"; shift
  mkdir -p "$home"
  echo "toolset" > "$home/toolset"
  cat > "$home/.claude.json" <<JSON
{
  "mcpServers": {
    "probe": {
      "command": "node",
      "args": ["$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs", "stdio"],
      "env": { "FIXTURE_TOOLSET_FILE": "$home/toolset" }
    }
  }
}
JSON
}

# The seeded destination is EXACTLY the four keys the reference writes, in the reference's order.
# Any extra top-level key would make the two sides differ by `div-r1-d3`'s own declared divergence
# and redden this row for a reason that has nothing to do with the installer.
seed_existing_config() { # home
  mkdir -p "$1/.claude/mcp-router"
  printf '{\n  "port": 8879,\n  "host": "127.0.0.1",\n  "idleMs": 300000,\n  "mcpServers": {}\n}' \
    > "$1/.claude/mcp-router/servers.json"
  chmod 644 "$1/.claude/mcp-router/servers.json"
}

import_scenario() { # label seed-existing(yes|no) expected-mode  -> prints "" or a problem string
  local label="$1" seed="$2" expect_mode="$3"
  local base="$WORK/imp-$label"
  rm -rf "$base"
  local ts="$base/ts" sw="$base/swift"
  import_side "$ts"
  import_side "$sw"
  if [ "$seed" = yes ]; then seed_existing_config "$ts"; seed_existing_config "$sw"; fi

  env -u MCP_ROUTER_HOME HOME="$ts" node "$REPO_ROOT/dist/index.js" import \
    >"$base/ts.out" 2>"$base/ts.err"; local ts_code=$?
  env -u MCP_ROUTER_HOME HOME="$sw" "$SWIFT_BIN" import \
    >"$base/sw.out" 2>"$base/sw.err"; local sw_code=$?

  local problems="" tsc="$ts/.claude/mcp-router/servers.json"
  local swc="$sw/.claude/mcp-router/servers.json"
  [ "$ts_code" = "$sw_code" ] || problems="$problems $label/exit:[ts=$ts_code swift=$sw_code]"
  diff <(norm "$ts" <"$base/ts.out") <(norm "$sw" <"$base/sw.out") >"$base/d.out" 2>&1 \
    || problems="$problems $label/stdout:[$(head -4 "$base/d.out" | tr '\n' ' ' | cut -c1-90)]"
  # The destination path itself is the assertion that both binaries resolved ONE home from $HOME.
  [ -f "$tsc" ] || problems="$problems $label/reference-wrote-nowhere"
  [ -f "$swc" ] || problems="$problems $label/swift-wrote-nowhere"
  if [ -f "$tsc" ] && [ -f "$swc" ]; then
    diff <(norm "$ts" <"$tsc") <(norm "$sw" <"$swc") >"$base/d.cfg" 2>&1 \
      || problems="$problems $label/servers.json:[$(head -6 "$base/d.cfg" | tr '\n' ' ' | cut -c1-90)]"
    local tm sm; tm="$(mode_of "$tsc")"; sm="$(mode_of "$swc")"
    [ "$tm" = "$sm" ] && [ "$tm" = "$expect_mode" ] \
      || problems="$problems $label/mode:[ts=$tm swift=$sm want=$expect_mode]"
    # Both sides ADOPTING NOTHING is the way this row passes without the capability it names: two
    # empty `mcpServers` objects are byte-identical and agree at the same mode. So the fixture
    # server has to be in both files, which is what makes the agreement about `import` rather than
    # about two skeletons. Same third observation `div-r1-d3` carries.
    grep -q '"probe"' "$tsc" || problems="$problems $label/reference-adopted-nothing"
    grep -q '"probe"' "$swc" || problems="$problems $label/swift-adopted-nothing"
  fi
  printf '%s' "$problems"
}

echo "install-import-servers — import as install.sh:77 runs it (no --from, no MCP_ROUTER_HOME)"
# Two scenarios: a fresh home must CREATE at 0600, an existing 0644 file must KEEP 0644. One alone
# hides half of the mode rule, and `cli-import`'s own seeded home only ever sees the second.
import_problems="$(import_scenario fresh no 600)$(import_scenario existing yes 644)"
if [ -z "$import_problems" ]; then
  echo "  ok   both binaries adopt into \$HOME/.claude/mcp-router at the same mode"
  record install install-import-servers ok \
    "fresh (created 0600) and pre-existing (kept 0644); stdout, exit, servers.json and mode agree"
else
  echo "  FAIL$import_problems"
  record install install-import-servers fail "import —$import_problems"
  failures=$((failures + 1))
fi
echo

# `install.sh:168-189`. The oracle is EXTRACTED from the installer at run time rather than retyped:
# a hand-copied copy drifts silently and would then certify agreement with a script nobody runs.
NODE_BODY="$(awk "/^  node -e '\$/{f=1;next} f&&/^  ' /{f=0} f" "$REPO_ROOT/docs/install.sh")"
# Three guards, because both obvious failure modes of a range extraction fail OPEN: a range whose
# end anchor stops matching emits start-to-EOF (non-empty), and `node -e ''` is a successful no-op.
extract_ok=1
[ -n "$NODE_BODY" ] || extract_ok=0
case "$NODE_BODY" in *mcpServers*renameSync*) ;; *) extract_ok=0 ;; esac
case "$NODE_BODY" in *curl*|*launchctl*) extract_ok=0 ;; esac

claude_scenario() { # label json port -> prints "" or a problem string
  local label="$1" json="$2" port="$3"
  local base="$WORK/cj-$label"
  rm -rf "$base"; mkdir -p "$base/ts" "$base/swift"
  printf '%s' "$json" > "$base/ts/.claude.json"
  printf '%s' "$json" > "$base/swift/.claude.json"
  chmod 600 "$base/ts/.claude.json" "$base/swift/.claude.json"

  # install.sh:162's `cp` is the shell's on the reference side; `install-entry` owns its own, so
  # the harness must NOT copy for Swift or there would be two backups on one side.
  cp "$base/ts/.claude.json" "$base/ts/.claude.json.bak-mcp-router-$(date +%Y%m%d-%H%M%S)"
  local oracle_port="$port"; [ "$port" = default ] && oracle_port=8879
  node -e "$NODE_BODY" "$base/ts/.claude.json" "$oracle_port" >/dev/null 2>&1; local ts_code=$?
  # `--port` is omitted for the `default-port` scenario, which is the ONLY thing that exercises
  # `install-entry`'s own `?? RouterHome.defaultPort`; a unit test cannot reach it, because
  # MCPRouterCLI has no test target.
  if [ "$port" = default ]; then
    env -u MCP_ROUTER_HOME "$SWIFT_BIN" install-entry \
      --claude-json "$base/swift/.claude.json" >/dev/null 2>&1; local sw_code=$?
  else
    env -u MCP_ROUTER_HOME "$SWIFT_BIN" install-entry \
      --claude-json "$base/swift/.claude.json" --port "$port" >/dev/null 2>&1; local sw_code=$?
  fi

  local problems=""
  # A non-zero oracle used to `return 0`, i.e. record no problem, i.e. pass. `docs/install.sh` runs
  # under `set -e`, so a failing `node -e` aborts the install; a lane that reads it as agreement is
  # the fail-open shape this gate exists to prevent.
  [ "$ts_code" = 0 ] || problems="$problems $label/reference-exit:[$ts_code]"
  [ "$sw_code" = 0 ] || problems="$problems $label/swift-exit:[$sw_code]"
  # Both sides must actually have CHANGED. All three scenarios add or rewrite `mcp-router`, so an
  # unchanged file means the oracle no-opped — an environment failure, never an agreement.
  for side in ts swift; do
    if [ "$(cat "$base/$side/.claude.json")" = "$json" ]; then
      problems="$problems $label/$side-unchanged"
    fi
    ls "$base/$side"/.claude.json.bak-mcp-router-* >/dev/null 2>&1 \
      || problems="$problems $label/$side-no-backup"
  done
  diff "$base/ts/.claude.json" "$base/swift/.claude.json" >"$base/d" 2>&1 \
    || problems="$problems $label/body:[$(head -6 "$base/d" | tr '\n' ' ' | cut -c1-90)]"
  local tm sm; tm="$(mode_of "$base/ts/.claude.json")"; sm="$(mode_of "$base/swift/.claude.json")"
  [ "$tm" = "$sm" ] && [ "$tm" = 600 ] || problems="$problems $label/mode:[ts=$tm swift=$sm]"
  for side in ts swift; do
    local backup; backup="$(ls "$base/$side"/.claude.json.bak-mcp-router-* 2>/dev/null | head -1)"
    if [ -n "$backup" ] && [ "$(cat "$backup")" != "$json" ]; then
      problems="$problems $label/$side-backup-not-the-pre-image"
    fi
  done
  printf '%s' "$problems"
}

echo "install-claude-json — the router entry, against install.sh's own extracted node script"
if [ "$extract_ok" = 0 ]; then
  echo "environment: the node -e block could not be extracted from docs/install.sh."
  echo "             Comparing against an empty oracle would pass for the wrong reason."
  exit 2
fi
# Three scenarios: the delete is conditional, and a lane that never sees its false branch has not
# tested it.
cj_problems="$(claude_scenario plain '{"projects":{"a":1}}' 8879)"
cj_problems="$cj_problems$(claude_scenario legacy-same \
  '{"mcpServers":{"router":{"type":"http","url":"http://127.0.0.1:8879/mcp"},"keep":{}}}' 8879)"
cj_problems="$cj_problems$(claude_scenario legacy-other \
  '{"mcpServers":{"router":{"type":"http","url":"http://127.0.0.1:9999/mcp"}}}' 8879)"
# No `--port` at all: the only exercise of the verb's own default.
cj_problems="$cj_problems$(claude_scenario default-port '{"projects":{"a":1}}' default)"
if [ -z "$cj_problems" ]; then
  echo "  ok   both write the same ~/.claude.json at the same mode, each with its own backup"
  record install install-claude-json ok \
    "three scenarios vs the node -e body extracted from install.sh; body, mode and backup agree"
else
  echo "  FAIL$cj_problems"
  record install install-claude-json fail "claude.json —$cj_problems"
  failures=$((failures + 1))
fi
echo

# ---------------------------------------------------------------------------------------------
# install-rollback — the restore half of docs/uninstall.sh, extracted, never the script.
#
# The script itself is not scratch-safe: it bootouts gg.rhodes.mcp-router and
# gg.rhodes.mcp-router-watch and deletes $HOME/Library/LaunchAgents plists, and those labels
# are hardcoded. Running it under a scratch HOME would still take the live agents down.
# The restore node -e is the half the row names ("putting a cut-over machine back on
# TypeScript") and the half that can run without touching launchd.
#
# The fixture is the POST-CUTOVER shape, not the post-import shape. Import copies adoptable
# stdio servers into servers.json and leaves the same names in ~/.claude.json. Restore skips
# any name already present, so seeding leftover stdio keys makes the merge a no-op and would
# green a row that never put a server back. After watch has adopted, those names live only in
# servers.json; claude.json holds mcp-router (HTTP) plus anything the user defined by hand.
# That is the shape this measures.

RESTORE_BODY="$(awk "/node -e '\$/{f=1;next} f&&/^  ' /{f=0} f" "$REPO_ROOT/docs/uninstall.sh")"
restore_extract_ok=1
[ -n "$RESTORE_BODY" ] || restore_extract_ok=0
# Order in uninstall.sh: mcpServers, then the clobber skip, then renameSync.
case "$RESTORE_BODY" in *mcpServers*Never\ clobber*renameSync*) ;; *) restore_extract_ok=0 ;; esac
case "$RESTORE_BODY" in *curl*|*launchctl*|*bootout*|*PURGE*) restore_extract_ok=0 ;; esac

echo "install-rollback — restore extracted from uninstall.sh, against a Swift-cutover fixture"
if [ "$restore_extract_ok" = 0 ]; then
  echo "environment: the restore node -e block could not be extracted from docs/uninstall.sh."
  echo "             Comparing against an empty oracle would pass for the wrong reason."
  exit 2
fi

rollback_home="$WORK/rollback"
rm -rf "$rollback_home"
mkdir -p "$rollback_home/.claude/mcp-router"
# Hand-defined name must survive; leftover stdio names must NOT be seeded here.
cat > "$rollback_home/.claude.json" <<JSON
{
  "mcpServers": {
    "mcp-router": {
      "type": "http",
      "url": "http://127.0.0.1:8879/mcp"
    },
    "router": {
      "type": "http",
      "url": "http://127.0.0.1:8879/mcp"
    },
    "keep-hand": {
      "command": "echo",
      "args": ["user-defined"]
    }
  }
}
JSON
chmod 600 "$rollback_home/.claude.json"
pre_image="$(cat "$rollback_home/.claude.json")"
cat > "$rollback_home/.claude/mcp-router/servers.json" <<JSON
{
  "port": 8879,
  "host": "127.0.0.1",
  "idleMs": 300000,
  "mcpServers": {
    "probe": {
      "command": "node",
      "args": ["$REPO_ROOT/scripts/fixtures/mcp-fixture-server.mjs", "stdio"],
      "env": { "FIXTURE_TOOLSET_FILE": "$rollback_home/toolset" }
    },
    "keep-hand": {
      "command": "echo",
      "args": ["stale-from-router"]
    }
  }
}
JSON

# Same backup naming uninstall.sh:47 uses, written by the harness the way install-claude-json
# writes install.sh:162's cp — the extracted body does not copy.
rb_backup="$rollback_home/.claude.json.bak-mcp-router-uninstall-$(date +%Y%m%d-%H%M%S)"
cp "$rollback_home/.claude.json" "$rb_backup"

restored_n="$(node -e "$RESTORE_BODY" "$rollback_home/.claude.json" \
  "$rollback_home/.claude/mcp-router/servers.json" 2>"$rollback_home/restore.err")"
rb_code=$?

rb_problems=""
[ "$rb_code" = 0 ] || rb_problems="$rb_problems exit:[$rb_code]"
# uninstall.sh prints the count the node -e wrote; one name (probe) should come back.
[ "$restored_n" = 1 ] || rb_problems="$rb_problems restored-count:[$restored_n want=1]"
[ "$(cat "$rollback_home/.claude.json")" != "$pre_image" ] || rb_problems="$rb_problems unchanged"
[ -f "$rb_backup" ] || rb_problems="$rb_problems no-backup"
if [ -f "$rb_backup" ] && [ "$(cat "$rb_backup")" != "$pre_image" ]; then
  rb_problems="$rb_problems backup-not-the-pre-image"
fi
[ "$(mode_of "$rollback_home/.claude.json")" = 600 ] \
  || rb_problems="$rb_problems mode:[$(mode_of "$rollback_home/.claude.json") want=600]"

# The four claims the row is about. Parsed, not grepped: a leftover "probe" inside a comment
# or a keep-hand value must not satisfy the adopted-name assertion.
rb_check="$(node -e '
  const fs = require("fs");
  const d = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const s = d.mcpServers || {};
  const problems = [];
  if (!s.probe) problems.push("probe-not-restored");
  else if (s.probe.command !== "node") problems.push("probe-wrong-command");
  if (s["mcp-router"]) problems.push("mcp-router-still-present");
  if (s.router) problems.push("router-still-present");
  if (!s["keep-hand"]) problems.push("keep-hand-missing");
  else if (JSON.stringify(s["keep-hand"].args) !== JSON.stringify(["user-defined"]))
    problems.push("keep-hand-clobbered");
  process.stdout.write(problems.join(" "));
' "$rollback_home/.claude.json")"
[ -z "$rb_check" ] || rb_problems="$rb_problems $rb_check"

if [ -z "$rb_problems" ]; then
  echo "  ok   probe restored, mcp-router/router gone, keep-hand unclobbered, mode 0600, backup is pre-image"
  record install install-rollback ok \
    "extracted uninstall restore; Swift-cutover fixture; probe back, router keys gone, hand name kept, mode 0600"
else
  echo "  FAIL$rb_problems"
  record install install-rollback fail "rollback —$rb_problems"
  failures=$((failures + 1))
fi
echo

echo "install: four real agents under real launchd supervision, two per binary."
[ "$failures" -gt 0 ] && exit 1
exit 0
