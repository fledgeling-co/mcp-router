#!/bin/zsh
# Mutation gate for the pool's four race guards, plus single-flight.
#
# A guard adopted on principle is machinery nobody can justify. Each mutation below removes exactly
# one guard and asserts the test that exists for it FAILS.
#
# Two things this gate learned the hard way, both of which made an earlier version lie:
#   * `swift test --filter` matches the test FUNCTION name, not its display string. A filter that
#     matches nothing reports "Test run with 0 tests ... passed", which reads exactly like a pass.
#   * So a test that did not run is not evidence. The executed count is parsed and required to be
#     non-zero before any verdict is taken.
set -u
cd /Users/lukerhodes/Dev/mcp-router/.worktrees/R2/app || exit 90
POOL=Sources/RouterCore/Pool/UpstreamPool.swift
BACKUP=$(mktemp)
cp "$POOL" "$BACKUP"
restore() { cp "$BACKUP" "$POOL"; }
trap restore EXIT

fail=0

mutate() {
  local name="$1" test="$2" python_edit="$3"
  restore
  python3 - "$POOL" <<PY
import sys
p = sys.argv[1]
s = open(p).read()
$python_edit
open(p, 'w').write(s)
PY
  if ! grep -q "MUTATED" "$POOL"; then
    echo "SKIP  $name — the mutation did not apply; the source has moved"
    fail=1
    return
  fi

  out=$(perl -e 'alarm 300; exec @ARGV' swift test --filter "$test" 2>&1)

  if echo "$out" | grep -qE "^/.*error:|error: fatalError"; then
    echo "BUILD $name — mutation did not compile (inconclusive)"
    fail=1
    return
  fi

  ran=$(printf '%s\n' "$out" | grep -oE 'Test run with [0-9]+ test' | grep -oE '[0-9]+' | tail -1)
  ran=${ran:-0}
  if [ "$ran" -eq 0 ]; then
    echo "NORUN $name — filter '$test' matched no test, so nothing was proved"
    fail=1
    return
  fi

  if printf '%s\n' "$out" | grep -q "Test run with .* passed"; then
    echo "HOLE  $name — '$test' ran ($ran) and still passed without the guard"
    fail=1
  else
    echo "OK    $name — '$test' ran ($ran) and fails without the guard"
  fi
}

mutate "P2a stale-open closure" "lateStartIsClosed" \
  's = s.replace("            await session.shutdown()\n            throw shuttingDown", "            // MUTATED: decline to install, and leak the live child\n            throw shuttingDown")'

mutate "P4a exactly-once release" "releaseIsExactlyOnce" \
  's = s.replace("guard entry.activeLeases.remove(lease.id) != nil else { return }", "entry.activeLeases.remove(lease.id) // MUTATED: no exactly-once check")'

mutate "P6a reap epoch" "staleTimerCannotReap" \
  's = s.replace("              entry.reap?.epoch == epoch,          // still the installed timer", "              // MUTATED: no epoch check")'

mutate "P6a reap deadline" "staleTimerCannotReap" \
  's = s.replace("              ContinuousClock.now >= deadline", "              true // MUTATED: no deadline check\n              || false")'

mutate "P8a close identity" "staleCloseCannotEvict" \
  's = s.replace("guard var entry = entries[name], entry.handle?.id == handle else { return }", "guard var entry = entries[name], entry.handle != nil else { return } // MUTATED")'

mutate "single-flight cohort join" "singleFlight" \
  's = s.replace("        if let flight = entry.starting {\n            return try await flight.task.value\n        }", "        // MUTATED: no cohort join\n")'

restore
echo "---"
if [ "$fail" -eq 0 ]; then
  echo "MUTATION GATE: all five guards proved load-bearing"
else
  echo "MUTATION GATE: FAILED — see above"
fi
exit "$fail"
