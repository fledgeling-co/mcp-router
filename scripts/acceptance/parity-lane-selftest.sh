#!/usr/bin/env bash
#
# R2-R — do the new lanes actually go red?
#
# A lane that stays green while the product is broken is undetectable by anything else in this
# design. `parity-gate.sh:95-99` fires only when a lane produces **zero** rows, so a lane recording
# trivially-passing rows satisfies every automated check the gate has. The five lanes this item adds
# produce all of its new coverage, and "we wrote them carefully" is not evidence.
#
# So each one is run against a deliberately broken Swift router and must FAIL. This is a script
# rather than a paragraph in an evidence file for one reason: a paragraph is re-run by nothing.
#
# The defect per lane is the one that lane exists to catch:
#
#   | lane    | seeded defect                          | what should notice |
#   |---------|----------------------------------------|--------------------|
#   | cli     | one word of stdout altered             | the stdout diff |
#   | cli     | the product name altered on BOTH streams | help, usage, status, index, refresh, tools |
#   | mcp     | --idle-ms forced to 999999             | pool-reap-traffic, mcp-status |
#   | mcp     | the Swift side serves toolset `b`      | tools/list |
#   | log     | --idle-ms forced to 999999             | the reap lines, and the idle-window line |
#   | state   | served from an empty config            | the tools/list corpus |
#   | install | the binary exits immediately            | RunAtLoad never comes up |
#   | mcp     | a phantom server in servers.json       | mcp-health |
#   | mcp     | FIXTURE_CALL_SUFFIX on every upstream  | mcp-tools-call |
#   | mcp     | --idle-ms forced to 50                 | pool-reap-traffic (see below) |
#   | cli     | one extra stdout line from `status`    | cli-status |
#   | cli     | one extra stdout line from `import`    | cli-import |
#   | cli     | one extra line before `serve` starts   | cli-serve |
#
# The last six were added by `D-g1-e`, which measured that eight of the nineteen rows had never
# been shown able to fail. Five of them hit their target and the roll-up moved from 11 of 19 to
# 16 of 19. The sixth did not: `--idle-ms 50` was aimed at `pool-p4` and the row stayed green,
# because the router withholds reaping on a call being OUTSTANDING rather than on the timer, so no
# idle window can break it. That seed is kept — it reddens `pool-reap-traffic` from the opposite
# direction to the 999999 one — but it is NOT counted as demonstrating the row it was aimed at.
# The roll-up at the end says which three rows remain and exactly what each would need.
#
# One defect does NOT exercise every row its lane owns, and this script used to report only
# "every lane went red", which invited the reader to assume it did. It now prints a per-row
# failability roll-up at the end naming every row it has NOT shown able to fail, because a row
# whose oracle is inert looks exactly like a row that agrees.
#
# The break is injected through a **shim on `$SWIFT_BIN`**, never through a hook in the router. A
# test-only branch inside the product is a branch that can ship.
#
# Exit codes: 0 every lane noticed its defect, 1 a lane stayed green (which is the finding), 2 the
# environment could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_BIN="${SWIFT_BIN:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
WORK="$(mktemp -d -t parity-selftest)"

# D-g1-g. This selftest seeds ports 8981-8986 and 8996-8997, two of which are the gate's own
# `state` and `install` defaults, so `make parity` and `make parity-selftest` genuinely contend.
. "$REPO_ROOT/scripts/acceptance/parity-lock.sh"
cleanup() { parity_lock_release; rm -rf "$WORK"; }
trap cleanup EXIT INT TERM HUP
parity_lock_acquire "parity-lane-selftest.sh"

[ -x "$REAL_BIN" ] || { echo "environment: no Swift router at $REAL_BIN"; exit 2; }

# One shim FILE PER MODE, with the mode written into the file.
#
# The first version read the mode from an environment variable, and the install lane reported a
# clean pass against a router that exits immediately — because a launchd agent inherits nothing from
# the shell that wrote its plist, so `SEED_DEFECT` never reached the shim and it ran the real binary.
# The self-test found a hole in the self-test, which is the only reason it is worth having: a seeded
# defect that does not arrive is a green run that means nothing.
make_shim() { # mode -> path
  local mode="$1"
  local path="$WORK/shim-$mode"
  printf '%s' "$REAL_BIN" > "$WORK/real-bin"
  printf '%s' "$mode" > "$WORK/mode-$mode"
  # A QUOTED heredoc: nothing in this body is expanded when it is written, so the shim cannot be
  # broken by a `$` that means something to the writing shell. The first version used an unquoted
  # one and the shell evaluated part of the body at generation time.
  cat > "$path" <<'SHIM'
#!/usr/bin/env bash
DIR="$(dirname "$0")"
REAL="$(cat "$DIR/real-bin")"
MODE="${0##*/shim-}"
case "$MODE" in
  stdout)
    # Every verb still runs; one word of its stdout is wrong. The subtlest of the defects, and the
    # one a lane checking only "did it exit 0" would miss entirely.
    #
    # `serve` is exempt and execs instead. A pipeline makes the real binary a CHILD of this shim, so
    # killing the shim orphans a listening router — which happened: a stray process held :8981 and
    # the next run reported the cli lane as "could not run". A harness that leaks a daemon makes its
    # own next run inconclusive.
    if [ "$1" = serve ]; then exec "$REAL" "$@"; fi
    "$REAL" "$@" | sed 's/tools from/toolz from/'
    exit ${PIPESTATUS[0]}
    ;;
  streams)
    # Both streams mangled, not just the one word `stdout` reaches. The `stdout` defect rewrites
    # "tools from", which only `index`, `refresh` and `tools` ever print — so `cli-help`,
    # `cli-usage`, `cli-status` and `cli-import` had no demonstrated ability to go red at all. This
    # rewrites the product's own name, which appears in the help block, in the `mcp-router: ` prefix
    # the offline `usage` error carries on stderr, and in `status`'s output.
    #
    # `serve` is exempt for the reason `stdout` gives: a pipeline makes the real binary a CHILD of
    # the shim, and killing the shim then orphans a listening router.
    if [ "$1" = serve ]; then exec "$REAL" "$@"; fi
    out="$(mktemp)"; err="$(mktemp)"
    "$REAL" "$@" >"$out" 2>"$err"; rc=$?
    sed 's/mcp-router/mcp-rooter/g' "$out"
    sed 's/mcp-router/mcp-rooter/g' "$err" >&2
    rm -f "$out" "$err"
    exit $rc
    ;;
  toolset)
    # The Swift side serves a DIFFERENT tool surface. The fixture server picks its toolset from the
    # file named by FIXTURE_TOOLSET_FILE, and `b` is a real variant of it, so indexing still
    # succeeds and the upstream still answers — only the corpus differs. That matters: emptying
    # servers.json instead would make reindex fail and the lane exit 2, which is "could not run",
    # not a demonstration. This is what gives `mcp-tools-list` and `mcp-tools-call` — the two
    # largest corpora in the whole gate — a demonstrated ability to go red.
    [ -f "$MCP_ROUTER_HOME/toolset" ] && printf 'b' > "$MCP_ROUTER_HOME/toolset"
    exec "$REAL" "$@"
    ;;
  idle)
    # The idle window is replaced with one that never expires, so nothing is ever reaped. A router
    # that never closes a child is the exact failure the pool exists to prevent.
    args=(); skip=0
    for a in "$@"; do
      if [ "$skip" = 1 ]; then skip=0; continue; fi
      if [ "$a" = "--idle-ms" ]; then skip=1; continue; fi
      args+=("$a")
    done
    exec "$REAL" "${args[@]}" --idle-ms 999999
    ;;
  emptyconfig)
    # Serves from a config with no servers at all, so its tool corpus is empty where the
    # reference's is not.
    printf '{"mcpServers":{}}' > "$MCP_ROUTER_HOME/servers.json"
    exec "$REAL" "$@"
    ;;
  nostart)
    # Comes up and dies. launchd's RunAtLoad brings it back, and it dies again.
    exit 1
    ;;
  # ------------------------------------------------------------------------------------- D-g1-e
  # Six further defects, one per row that the four original seeds never reddened. Each is aimed at
  # ONE row's own assertion rather than at whatever was easiest to break, because a seed that
  # reddens a lane through some other row demonstrates that other row and leaves this one exactly
  # as unproven as before.
  reap)
    # The mirror of `idle`. That one makes the router never reap and reddens `pool-reap-traffic`;
    # this one makes it reap almost immediately, which is what `pool-p4` asserts cannot happen —
    # a call still outstanding must survive the idle window.
    args=(); skip=0
    for a in "$@"; do
      if [ "$skip" = 1 ]; then skip=0; continue; fi
      if [ "$a" = "--idle-ms" ]; then skip=1; continue; fi
      args+=("$a")
    done
    exec "$REAL" "${args[@]}" --idle-ms 50
    ;;
  healthskew)
    # A server the reference does not have, so `GET /health` enumerates a different set. Aimed at
    # `mcp-health`, whose comparison is the whole status/headers/body of that one response.
    if [ -n "${MCP_ROUTER_HOME:-}" ] && [ -f "$MCP_ROUTER_HOME/servers.json" ]; then
      python3 - "$MCP_ROUTER_HOME/servers.json" <<'PY'
import json, sys
path = sys.argv[1]
try:
    doc = json.load(open(path))
except Exception:
    sys.exit(0)
doc.setdefault('mcpServers', {})['seeded-phantom'] = {'command': '/bin/echo', 'args': ['phantom']}
json.dump(doc, open(path, 'w'))
PY
    fi
    exec "$REAL" "$@"
    ;;
  callskew)
    # The fixture appends FIXTURE_CALL_SUFFIX to every tools/call result, so the Swift side's call
    # ANSWERS differ while the tool LIST stays identical. Aimed at `mcp-tools-call`: seeding a
    # toolset changes what is listed and leaves every call result the same, which is why the
    # original `toolset` seed demonstrated `mcp-tools-list` and never this row.
    if [ -n "${MCP_ROUTER_HOME:-}" ] && [ -f "$MCP_ROUTER_HOME/servers.json" ]; then
      python3 - "$MCP_ROUTER_HOME/servers.json" <<'PY'
import json, sys
path = sys.argv[1]
try:
    doc = json.load(open(path))
except Exception:
    sys.exit(0)
for entry in doc.get('mcpServers', {}).values():
    if isinstance(entry, dict) and 'command' in entry:
        entry.setdefault('env', {})['FIXTURE_CALL_SUFFIX'] = '-seeded'
json.dump(doc, open(path, 'w'))
PY
    fi
    exec "$REAL" "$@"
    ;;
  statusskew)
    # One extra line on stdout, for `status` alone. Gated on the verb so the seed cannot redden a
    # different cli row and be counted as this one.
    [ "${1:-}" = "status" ] && printf 'seeded: an extra line from status\n'
    exec "$REAL" "$@"
    ;;
  importskew)
    [ "${1:-}" = "import" ] && printf 'seeded: an extra line from import\n'
    exec "$REAL" "$@"
    ;;
  serveskew)
    # `cli-serve` compares the WHOLE of what serve wrote, so one extra line before the router starts
    # is enough. Printed BEFORE `exec` deliberately: wrapping `serve` instead would leave the shim
    # holding the pid the lane signals, and killing the shim orphans a listening router — which has
    # already happened in this harness and stranded a port.
    [ "${1:-}" = "serve" ] && printf 'seeded: an extra line before serve\n'
    exec "$REAL" "$@"
    ;;
  *)
    exec "$REAL" "$@"
    ;;
esac
SHIM
  chmod +x "$path"
  printf '%s' "$path"
}

failures=0
blocked=0
check() { # lane defect expected-row ports...
  local lane="$1" defect="$2" expect="$3"; shift 3
  printf '  %-8s seeded with %-12s ... ' "$lane" "$defect"
  : > "$WORK/results.tsv"
  local shim; shim="$(make_shim "$defect")"
  SWIFT_BIN="$shim" PARITY_RESULTS="$WORK/results.tsv" \
    "$@" bash "$REPO_ROOT/scripts/acceptance/parity-$lane.sh" >"$WORK/$lane.log" 2>&1
  local status=$?
  local rows; rows="$(grep -c . "$WORK/results.tsv" 2>/dev/null || echo 0)"
  local reds; reds="$(awk -F'\t' '$3 == "fail"' "$WORK/results.tsv" 2>/dev/null | wc -l | tr -d ' ')"

  if [ "$status" = 0 ]; then
    echo "STAYED GREEN — the lane did not notice ($rows rows, 0 red)"
    failures=$((failures + 1))
    tail -12 "$WORK/$lane.log" | sed 's/^/      /'
    return
  fi
  # A lane that could not START has told us nothing about whether it can go red. Counting it with
  # the lanes that ran and stayed green would report an environment fact — a port held by a
  # concurrent run, a missing binary — as a claim that this check is inert. That is the confusion
  # this whole item exists to remove, so it is counted separately and it exits 2, not 1.
  if [ "$status" = 2 ]; then
    echo "could not run (exit 2) — inconclusive, not a pass and not a failure"
    blocked=$((blocked + 1))
    tail -8 "$WORK/$lane.log" | sed 's/^/      /'
    return
  fi
  # A non-zero exit with no `fail` row is NOT a demonstration. The lane may have exited 1 for an
  # unrelated reason — a curl that failed, a guard that tripped — while the seeded defect went
  # unnoticed by every comparison. Scoring that as "went red" credited the lane with a failability
  # it had not shown.
  if [ "$reds" = 0 ]; then
    echo "exited $status but recorded NO failing row — not a demonstration ($rows rows)"
    failures=$((failures + 1))
    tail -12 "$WORK/$lane.log" | sed 's/^/      /'
    return
  fi
  echo "went red ($reds of $rows rows failed)"
  # A lane going red is not the same as the SEEDED ROW going red. A seed aimed at `mcp-health` that
  # actually trips `mcp-status` reddens the lane, satisfies every check above, and leaves the row it
  # was written for exactly as undemonstrated as before — while the roll-up counts it. That is the
  # miscount this whole script exists to prevent, one level down, and an oracle changing later is
  # precisely when it would happen silently.
  if [ "$expect" != "-" ]; then
    if awk -F'\t' -v want="$expect" '$3 == "fail" && $2 == want { found = 1 }
        END { exit found ? 0 : 1 }' "$WORK/results.tsv"; then
      printf '      (aimed at %s, and %s went red)\n' "$expect" "$expect"
    else
      printf '      SEED MISSED ITS TARGET: aimed at %s, which did NOT go red\n' "$expect"
      failures=$((failures + 1))
    fi
  fi
  awk -F'\t' '$3 == "fail" { print $1 "/" $2 }' "$WORK/results.tsv" >> "$WORK/failable.txt"
  awk -F'\t' '$3 == "fail" { printf "      %s/%s: %s\n", $1, $2, substr($4, 1, 120) }' \
    "$WORK/results.tsv"
}

echo "seeding a defect per lane and requiring the lane to notice"
echo

# Ports distinct from the ones the lanes use by default, so a self-test can run while nothing else
# is in flight and still never collide with 8975/8976.
check cli     stdout      -                  env CLI_PORT=8981
check cli     streams     -                  env CLI_PORT=8981
check mcp     idle        pool-reap-traffic  env MCP_TS_PORT=8982 MCP_SWIFT_PORT=8983 MCP_HUB_PORT=8996
check mcp     toolset     mcp-tools-list     env MCP_TS_PORT=8982 MCP_SWIFT_PORT=8983 MCP_HUB_PORT=8997
check log     idle        log-bytes          env LOG_PORT=8984
check state   emptyconfig state-ondisk-compat env STATE_PORT=8985
check install nostart     install-launchd-serve env INSTALL_PORT=8986

# D-g1-e — six seeds aimed at rows the four above never reddened. The checks run serially, so the
# ports are reused rather than multiplied. Each names the row it is aimed at, and `check` fails if
# that row does not go red — a seed that reddens a lane through some OTHER row would otherwise be
# counted as demonstrating this one.
#
# `reap` names pool-reap-traffic, not pool-p4. It was WRITTEN for pool-p4 and did not move it, so
# it is declared against what it actually demonstrates rather than what was hoped for.
check mcp     healthskew  mcp-health         env MCP_TS_PORT=8982 MCP_SWIFT_PORT=8983 MCP_HUB_PORT=8996
check mcp     callskew    mcp-tools-call     env MCP_TS_PORT=8982 MCP_SWIFT_PORT=8983 MCP_HUB_PORT=8997
check mcp     reap        pool-reap-traffic  env MCP_TS_PORT=8982 MCP_SWIFT_PORT=8983 MCP_HUB_PORT=8996
check cli     statusskew  cli-status         env CLI_PORT=8981
check cli     importskew  cli-import         env CLI_PORT=8981
check cli     serveskew   cli-serve          env CLI_PORT=8981

# Which rows this actually demonstrates, and which it does not.
#
# One seeded defect per lane does NOT exercise every row that lane owns, and reporting only
# "every lane went red" invited the reader to assume it did. A defect that trips two of a lane's
# eight rows leaves the other six with no demonstrated ability to fail — they may be sound, but this
# script has not shown it, and a row whose oracle is inert looks exactly like a row that agrees.
echo
echo "failability by row — a row absent here has not been shown able to go red:"
ALL_ROWS="mcp/mcp-endpoint mcp/mcp-tools-list mcp/mcp-tools-call mcp/mcp-health mcp/mcp-status
pool/pool-p4 pool/pool-reap-traffic divergence/div-r2r-d8
cli/cli-serve cli/cli-import cli/cli-index cli/cli-refresh cli/cli-status cli/cli-tools
cli/cli-usage cli/cli-help install/install-launchd-serve state/state-ondisk-compat log/log-bytes"
sort -u "$WORK/failable.txt" 2>/dev/null > "$WORK/failable.sorted" || : > "$WORK/failable.sorted"
shown=0; unshown=0; missing=""
for row in $ALL_ROWS; do
  if grep -qxF "$row" "$WORK/failable.sorted" 2>/dev/null; then
    shown=$((shown + 1))
  else
    unshown=$((unshown + 1)); missing="$missing $row"
  fi
done
echo "  demonstrated: $shown of $((shown + unshown))"
# The `oauth` lane is deliberately absent from ALL_ROWS. It has no lever through this shim — its
# row turns on the bytes of an OAuth cascade the shim cannot reach — and its failability is
# demonstrated by a stronger instrument instead: `scripts/acceptance/p7-mutations.sh` breaks the
# OAuth client six ways in the PRODUCT and requires the lane to go red on every trial. Named here
# so a reader of this roll-up does not read the lane's absence as an unproven row.
echo "  (control/control-auth-post-http is proved failable by scripts/acceptance/p7-mutations.sh,"
echo "   which mutates the product rather than the shim; it has no lever here.)"
if [ "$blocked" != 0 ]; then
  echo "  ($blocked lane(s) could not run, so some rows below are unmeasured, not inert.)"
fi
if [ -n "$missing" ]; then
  echo "  NOT demonstrated:"
  for row in $missing; do echo "    $row"; done
  echo "  These rows are recorded proven by a lane whose ability to fail on THAT row is unproven."
  echo
  echo "  Three of them were ATTEMPTED and have no lever here, which is a different fact from"
  echo "  never having been tried, and is recorded so the next runner does not repeat the attempt:"
  echo "    pool/pool-p4         seeded with --idle-ms 50 and the row still passed. The router"
  echo "                         withholds reaping on a call being OUTSTANDING, not on the timer,"
  echo "                         so no idle window can break it."
  echo "    mcp/mcp-endpoint     the four framing refusals and the 404 are decided entirely inside"
  echo "                         the HTTP layer."
  echo "    divergence/div-r2r-d8 asserts the two parser texts DIFFER, so reddening it means making"
  echo "                         them agree."
  echo "  All three need a fault injected into a response the router has already composed. Every"
  echo "  seed here works through the shim — arguments, \$MCP_ROUTER_HOME files, or refusing to"
  echo "  start — and none of those reaches a composed response. Closing them needs either a"
  echo "  mangling proxy in front of the Swift router or a fault-injection hook in the product,"
  echo "  and a hook in the product is the thing this harness has refused to add throughout."
fi

echo
if [ "$failures" != 0 ]; then
  echo "$failures lane(s) did not notice their seeded defect. A lane that cannot go red is not a"
  echo "check, and any row it proves should be read as unproven."
  [ "$blocked" != 0 ] && echo "($blocked further lane(s) could not run at all — see above.)"
  exit 1
fi
if [ "$blocked" != 0 ]; then
  echo "BLOCKED: $blocked lane(s) could not run, so their failability is unmeasured. Every lane that"
  echo "DID run noticed its seeded defect. The commonest cause is a second parity run holding the"
  echo "lane's fixed port — this harness never shares one. Re-run with nothing else in flight."
  exit 2
fi
echo "every new lane went red against a broken router. The lanes can fail."
exit 0
