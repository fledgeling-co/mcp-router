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
#                               install-import-servers install-claude-json
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
    install/install-import-servers|install/install-claude-json) ;;
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
  # Written temp-then-rename. `cat >` truncates and then fills, so a watcher can observe the file
  # twice (empty, then complete) or parse it mid-write — either of which presents as a spurious or
  # a malformed event rather than as the single change this is meant to be.
  cat > "$1.staging" <<JSON
{
  "numStartups": 41,
  "mcpServers": { "notadoptable-$2": { "note": "no command and no url" } }
}
JSON
  mv "$1.staging" "$1"
}

# ---------------------------------------------------------------------------------------------
# P5 — the two watch terms, each given its OWN named fix, with the bound written down here rather
# than discovered by re-running until the answer was nice.
#
# What was measured first, on this machine, with a scratch launchd agent whose program was a plain
# bash script — NEITHER node NOR Swift, so neither router could be the cause:
#
#   · `launchctl print` carries `runs = N` and `state = not running`. That is launchd's OWN
#     accounting of how many times it has spawned the job, and it is the observable both terms were
#     missing. Everything before this inferred them from a file the job writes and from whether a
#     `pid` line happened to be present at the instant it was sampled.
#   · one `mv` onto the watched path incremented `runs` in FOUR of five trials, 9-14s later
#     (ThrottleInterval is 10, so the floor is the throttle). In the fifth it never incremented at
#     all inside 60s. The event was dropped.
#
# That fifth trial is the whole story: WatchPaths delivery is lossy, the loss is launchd's, and it
# happens with no router involved. A lane that treats one `mv` as a reliable stimulus is therefore
# nondeterministic BY CONSTRUCTION, and no amount of waiting on the observer side fixes a stimulus
# that was never delivered.
#
# TERM `oneshot` — FIX: stop inferring residency from the absence of a `pid` sample.
#   The old predicate was "`agent_pid` printed nothing", which is equally true when the job has
#   finished and when it is BETWEEN two runs. A second run — a spurious WatchPaths delivery, or the
#   throttled re-run of a stimulus staged earlier — makes the second case real, and the two are
#   indistinguishable to a pid probe. `runs` distinguishes them exactly, because it changes when a
#   new run STARTS. So settled now means: launchd says `not running` AND the run counter has not
#   moved for a whole settling window.
#
# TERM `reran` — FIX: stop deciding it from the CONTENT OF A FILE THE JOB WRITES, and stop treating
#   one `mv` as a reliable stimulus.
#   Deciding it from `watch-state.json` asks the wrong question twice over: it is written by the
#   process rather than by launchd, so it cannot see a run that started and it cannot see a run that
#   wrote nothing. `runs` answers the actual question — did launchd spawn it again. And because
#   delivery is lossy, the stimulus is RE-DELIVERED on a schedule until the counter moves or the
#   bound expires.
#
#   RE-DELIVERING THE STIMULUS IS NOT RE-RUNNING UNTIL GREEN, and the difference is worth stating
#   because this fleet has made that mistake once. Re-running until green repeats the MEASUREMENT
#   and keeps the answer it likes. This repeats the INPUT — a change to the watched file, which is
#   the thing a user's ~/.claude.json does many times a day — and keeps whatever the first delivered
#   event produces. The claim it supports is correspondingly weaker and is stated as such: the
#   watcher re-runs when a change is DELIVERED, not that launchd delivers every change. The stronger
#   claim is false of launchd, which is precisely why asserting it produced a coin toss.
#
# THE BOUNDS, fixed here in advance:
WATCH_SETTLE_TICKS=240        # 60s at 0.25s — how long a first run may take before it is resident
WATCH_SETTLE_STABLE=12        # 3s of `not running` with an unmoved counter is "settled"
WATCH_RESTAGE_ATTEMPTS=6      # re-deliver the change up to six times
WATCH_RESTAGE_TICKS=30        # 15s at 0.5s per attempt, so 90s total against a 10s throttle
# Per-side evidence for the report: what launchd's counter did, and how many deliveries it took.
# A FILE rather than a variable, because `observe_watch` is invoked through command substitution and
# anything it assigns dies with that subshell. Printed rather than merely kept, because "it agreed"
# and "it agreed on the first delivery" are different facts, and a future reader deciding whether to
# promote this row needs the second one.
WATCH_EVIDENCE="$WORK/watch-evidence"
: > "$WATCH_EVIDENCE"

agent_state() { launchctl print "gui/$(id -u)/$1" 2>/dev/null | awk -F'= ' '/^\tstate = /{print $2; exit}'; }
agent_runs() { launchctl print "gui/$(id -u)/$1" 2>/dev/null | awk '/^\truns = /{print $3; exit}'; }

# Settled: launchd reports the job not running, and its run counter has stopped moving.
#
# Both halves are load-bearing. `not running` alone is momentarily true in the gap between two runs;
# an unmoved counter alone is true while a long single run is still going. Requiring both, for a
# whole window, is what separates "this is a one-shot that has finished" from "this is a one-shot
# that is about to be started again" — the two the old pid probe could not tell apart.
watch_settled() { # label ticks
  local label="$1" bound="$2" tick stable=0 last="" state runs
  for ((tick = 0; tick < bound; tick++)); do
    state="$(agent_state "$label")"
    runs="$(agent_runs "$label")"
    if [ "$state" = "not running" ] && [ -n "$runs" ] && [ "$runs" = "$last" ]; then
      stable=$((stable + 1))
      [ "$stable" -ge "$WATCH_SETTLE_STABLE" ] && return 0
    else
      stable=0
    fi
    last="$runs"
    sleep 0.25
  done
  return 1
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
  # `ran` stays on the state file deliberately. `runs` proves LAUNCHD spawned something; the state
  # file proves the BINARY got as far as doing its job, and that second one is the parity claim.
  for _ in $(seq 1 80); do [ -s "$state" ] && { ran=yes; break; }; sleep 0.25; done

  # TERM `oneshot`, decided from launchd's own state and run counter — see the block above
  # `watch_settled` for why the pid probe this replaces could not tell a finished one-shot from a
  # one-shot between two runs.
  local settled=yes
  watch_settled "$label" "$WATCH_SETTLE_TICKS" || settled=no
  [ "$settled" = yes ] && oneshot=yes

  # TERM `reran`, decided from `runs` rather than from the file the job writes, and with the
  # stimulus RE-DELIVERED because launchd's WatchPaths delivery is lossy — measured 4 of 5 with a
  # bash agent, so neither router is implicated. The distinction between re-delivering an input and
  # re-running a measurement is argued in full in that same block.
  local before_runs attempt tick now
  before_runs="$(agent_runs "$label")"
  for ((attempt = 0; attempt < WATCH_RESTAGE_ATTEMPTS; attempt++)); do
    stage "$claudehome/.claude.json" "two-$attempt"
    for ((tick = 0; tick < WATCH_RESTAGE_TICKS; tick++)); do
      now="$(agent_runs "$label")"
      if [ -n "$now" ] && [ -n "$before_runs" ] && [ "$now" -gt "$before_runs" ]; then
        reran=yes
        break 2
      fi
      sleep 0.5
    done
  done
  local delivered=$((attempt + 1))
  [ "$delivered" -gt "$WATCH_RESTAGE_ATTEMPTS" ] && delivered="$WATCH_RESTAGE_ATTEMPTS"
  # Appended to a FILE, not to a variable. `observe_watch` is called through `$( … )`, which runs it
  # in a subshell, so an assignment here would be discarded the moment it returned — the same trap
  # the harness lock documents for its own release guard.
  printf '%s:runs=%s->%s:stages=%s ' \
    "$side" "${before_runs:-?}" "$(agent_runs "$label")" "$delivered" >> "$WATCH_EVIDENCE"

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
echo "  launchd's own accounting: $(cat "$WATCH_EVIDENCE" 2>/dev/null)"
echo "  \`stages\` is how many times the watched file had to be changed before launchd delivered an"
echo "  event. More than 1 is launchd coalescing or dropping a delivery, not a router misbehaving."
echo

case "$ts_watch$swift_watch" in
  *bootstrap-refused*)
    echo "environment: launchd refused to bootstrap a scratch watch agent in this session, so the"
    echo "             watch supervision contract could not be exercised on either side."
    exit 2 ;;
esac

# `install-launchd-watch` — MEASURED HERE AND STILL BLOCKED. The lane records nothing for it.
#
# The history is kept because it is the reason the bar for this one row is higher than for any other
# in the manifest. It was `proven` once, and a proven row whose lane disagrees reports DIVERGED —
# which reads as "the two routers behave differently" when what actually happened is that a racy
# lane lost a coin toss. P1 measured six consecutive runs: agreed 1 in 6, both terms unstable on
# BOTH binaries, the losing side alternating. G1 then fixed two real mechanisms — judging one-shot
# while the writing process was still alive, and staging into a job launchd still considered running
# — and DELIBERATELY DID NOT CLAIM THE ROW. The rule the row then stated was: name a fix for each
# term SEPARATELY, fix a bound IN ADVANCE, then measure.
#
# THE FIXES ABOVE ARE REAL AND ARE KEPT. Reading launchd's own `runs` counter instead of a file the
# job writes, requiring `not running` AND an unmoved counter for a settling window, re-delivering a
# lossy stimulus, and printing the counter as evidence are all strictly better than what preceded
# them. Nothing here argues otherwise. What follows is only about whether they are enough to CLAIM
# the row, and one of the two terms is not.
#
# A PROMOTION WAS ATTEMPTED AND IS WITHDRAWN. An eight-pair series was run and it passed: eight
# consecutive pairs, sixteen observations, every one `yes,yes,yes,--`, all four terms agreeing in
# all eight, `stages=1` on every side of every pair. That series was then INDEPENDENTLY REPRODUCED —
# eight more consecutive pairs, sixteen more observations, identical in every term, at one-minute
# loads 5.5 to 10.3. The agreement rate is genuinely a change of regime from P1's 1-in-6.
#
# IT WAS WITHDRAWN ON THE MUTATION, NOT ON THE SERIES. Each term was then aimed at separately:
#
#   · `oneshot` DISCRIMINATES. Give the Swift side a program that writes its state and then stays
#     resident (`sh -c '<router> watch; sleep 300'`) and it reads `yes,no,no` with
#     `runs=1->1:stages=6`. The settled check refuses to settle and the bound expires, where the old
#     pid probe would have seen no `pid` line between runs and called it settled. Row recorded fail,
#     lane exit 1. This term is sound.
#
#   · `reran` DOES NOT DISCRIMINATE RELIABLY. Point the Swift agent's `WatchPaths` at a decoy .json
#     in a freshly created `mktemp -d` directory that this lane never touches, so a genuine delivery
#     is IMPOSSIBLE, and the correct answer is unambiguously `no`. The generated plist was dumped
#     and confirmed to carry the decoy path. Six trials:
#         4 of 6  reran=no,  `runs=N->N:stages=6`  — correct, row recorded fail
#         2 of 6  reran=yes, `runs=1->2:stages=1`  — SPURIOUS: the counter moved with no stimulus
#     A seventh trial with the decoy in a sibling directory under the same $WORK also read `yes`
#     (`stages=2`). So a spurious `runs` increment happens roughly one run in three, and in the
#     report it is BYTE-IDENTICAL to a genuine first-delivery re-run — `stages=1` either way.
#
# WHY THAT IS DISQUALIFYING, STATED AS THE ARITHMETIC IT IS. The gate runs this lane ONCE. A Swift
# watcher that never re-ran on a file change at all would still read `yes` on this term about one
# gate run in three, and paired with the reference's genuine `yes` would record the row GREEN. That
# is a false green on the row's actual parity claim, and it is the exact failure this census exists
# to refuse — an absent vector must not be read as parity. The eight-pair series does not rescue it:
# a series bounds the AGREEMENT rate, and what is broken here is what the term MEASURES.
#
# The earlier note claimed the decoy mutation went red and read the limit as "WatchPaths fires on
# churn in the file's DIRECTORY". Six trials do not support that: a decoy in its own private
# directory still went green twice. The limit is wider and less well characterised than stated, and
# recording the number is more useful than recording the theory.
#
# TO PROMOTE, from here: make `reran` ATTRIBUTABLE rather than merely counted — tie the observed
# re-run to the specific staged change that should have caused it, so a spurious launchd spawn
# cannot satisfy it — then re-measure with the decoy mutation required to go red every trial. Until
# then this lane measures the row, prints everything it saw, and records NOTHING, so the row stays
# blocked under its note rather than reporting a divergence neither binary caused.
if [ "$ts_watch" = "$swift_watch" ] && [ "${swift_watch%,*}" = "yes,yes,yes" ]; then
  echo "  note both binaries answered the watch agent's supervision identically this run"
  echo "       ($ts_watch), and launchd's own counter is the witness for the one-shot term."
  echo "       The row stays BLOCKED and NOTHING is recorded: the \`reran\` term reads yes about"
  echo "       one run in three even when no stimulus can reach the watched path (4 of 6 decoy"
  echo "       trials correct, 2 of 6 spurious), so agreement on it is not evidence of parity."
else
  echo "  note the two binaries did not answer the same watch supervision this run"
  echo "       (reference=$ts_watch swift=$swift_watch; ran,reran,one-shot,logged). The row is"
  echo "       BLOCKED, so this is an observation rather than a divergence — which is the point:"
  echo "       a lane with a known false-positive term must not be able to report DIVERGED."
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

echo "install: four real agents under real launchd supervision, two per binary."
[ "$failures" -gt 0 ] && exit 1
exit 0
