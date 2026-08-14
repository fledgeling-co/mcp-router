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
#   | mcp     | --idle-ms forced to 999999             | pool-p4 / pool-reap-traffic |
#   | log     | --idle-ms forced to 999999             | the reap lines, and the idle-window line |
#   | state   | served from an empty config            | the tools/list corpus |
#   | install | the binary exits immediately            | RunAtLoad never comes up |
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
trap 'rm -rf "$WORK"' EXIT

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
  *)
    exec "$REAL" "$@"
    ;;
esac
SHIM
  chmod +x "$path"
  printf '%s' "$path"
}

failures=0
check() { # lane defect ports...
  local lane="$1" defect="$2"; shift 2
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
  if [ "$status" = 2 ]; then
    echo "could not run (exit 2) — inconclusive, not a pass"
    failures=$((failures + 1))
    tail -8 "$WORK/$lane.log" | sed 's/^/      /'
    return
  fi
  echo "went red ($reds of $rows rows failed)"
  awk -F'\t' '$3 == "fail" { printf "      %s/%s: %s\n", $1, $2, substr($4, 1, 120) }' \
    "$WORK/results.tsv"
}

echo "seeding a defect per lane and requiring the lane to notice"
echo

# Ports distinct from the ones the lanes use by default, so a self-test can run while nothing else
# is in flight and still never collide with 8975/8976.
check cli     stdout      env CLI_PORT=8981
check mcp     idle        env MCP_TS_PORT=8982 MCP_SWIFT_PORT=8983
check log     idle        env LOG_PORT=8984
check state   emptyconfig env STATE_PORT=8985
check install nostart     env INSTALL_PORT=8986

echo
if [ "$failures" = 0 ]; then
  echo "every new lane went red against a broken router. The lanes can fail."
  exit 0
fi
echo "$failures lane(s) did not notice their seeded defect. A lane that cannot go red is not a"
echo "check, and any row it proves should be read as unproven."
exit 1
