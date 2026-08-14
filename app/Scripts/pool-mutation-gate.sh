#!/bin/zsh
# Mutation gate for the pool's race guards.
#
# A guard adopted on principle is machinery nobody can justify. Each mutation removes exactly one
# guard and asserts the test that exists for it FAILS.
#
# Three things this gate learned the hard way, each of which made an earlier version lie:
#   * `swift test --filter` matches the test FUNCTION name, not its display string, and a filter
#     that matches nothing prints "Test run with 0 tests ... passed" — which reads as a pass.
#   * A test that did not run is not evidence, so the executed count is parsed and required to be
#     non-zero before any verdict is taken.
#   * A mutation that deadlocks the suite is not a failure either; it is a timeout, and it is
#     reported separately so nobody reads a hang as a proof.
set -u
cd /Users/lukerhodes/Dev/mcp-router/.worktrees/R2/app || exit 90

# The actor is split across two files (file-length limit), so both are mutated and both restored.
CORE=Sources/RouterCore/Pool/UpstreamPool.swift
REAP=Sources/RouterCore/Pool/UpstreamPoolReaping.swift
TRANS=Sources/RouterCore/Pool/StdioUpstreamTransport.swift
CORE_BACKUP=$(mktemp); cp "$CORE" "$CORE_BACKUP"
REAP_BACKUP=$(mktemp); cp "$REAP" "$REAP_BACKUP"
TRANS_BACKUP=$(mktemp); cp "$TRANS" "$TRANS_BACKUP"
restore() { cp "$CORE_BACKUP" "$CORE"; cp "$REAP_BACKUP" "$REAP"; cp "$TRANS_BACKUP" "$TRANS"; }
trap restore EXIT

fail=0

mutate() {
  local name="$1" test="$2" find="$3" replace="$4"
  restore
  FIND="$find" REPLACE="$replace" python3 - "$CORE" "$REAP" "$TRANS" <<'PY'
import os, sys
find, replace = os.environ["FIND"], os.environ["REPLACE"]
for path in sys.argv[1:]:
    text = open(path).read()
    if find in text:
        open(path, "w").write(text.replace(find, replace))
PY
  if ! grep -q "MUTATED" "$CORE" "$REAP" "$TRANS"; then
    echo "SKIP  $name — the mutation did not apply; the source has moved"
    fail=1
    return
  fi

  out=$(perl -e 'alarm 240; exec @ARGV' swift test --filter "$test" 2>&1)
  local rc=$?

  if echo "$out" | grep -qE "^/.*error:|error: fatalError"; then
    echo "BUILD $name — mutation did not compile (inconclusive)"
    fail=1
    return
  fi

  ran=$(printf '%s\n' "$out" | grep -oE 'Test run with [0-9]+ test' | grep -oE '[0-9]+' | tail -1)
  ran=${ran:-0}
  if [ "$ran" -eq 0 ]; then
    if [ "$rc" -ne 0 ]; then
      echo "HANG  $name — the suite timed out under mutation; a hang is not a proof"
    else
      echo "NORUN $name — filter '$test' matched no test, so nothing was proved"
    fi
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
  '            await session.shutdown()' \
  '            // MUTATED: decline to install, and leak the live child'

mutate "P4a exactly-once release" "releaseIsExactlyOnce" \
  'guard entry.activeLeases.remove(lease.id) != nil else { return }' \
  'entry.activeLeases.remove(lease.id) // MUTATED: no exactly-once check'

mutate "P6a reap epoch" "staleTimerCannotReap" \
  'entry.reap?.epoch == epoch,' \
  'true, // MUTATED: no epoch check'

mutate "P6a reap deadline" "staleTimerCannotReap" \
  'ContinuousClock.now >= deadline' \
  'true // MUTATED: no deadline check'

mutate "P8a close identity" "staleCloseCannotEvict" \
  'guard var entry = entries[name], let live = entry.handle, live.id == handle else { return }

        // Evict first' \
  'guard var entry = entries[name], let live = entry.handle else { return } // MUTATED: no identity
        _ = handle

        // Evict first'

mutate "P4a waiter reservation" "reaperCannotBeatTheWaitingLease" \
  'guard entry.inFlight == 0, entry.pendingWaiters == 0, let handle = entry.handle else { return }' \
  'guard entry.inFlight == 0, let handle = entry.handle else { return } // MUTATED: no reservation'

mutate "P8b evict before suspending" "endedSessionIsEvictedBeforeAnySuspension" \
  'guard var entry = entries[name], let live = entry.handle, live.id == handle else { return }

        // Evict first' \
  'guard var entry = entries[name], let live = entry.handle, live.id == handle else { return }
        await log?.record(PoolLogEvent.closedItself(server: name)) // MUTATED: suspend first

        // Evict first'

mutate "P8b close on self-end" "selfEndedSessionIsClosed" \
  '        await live.session.shutdown()' \
  '        _ = live // MUTATED: evict without closing'

mutate "P9 shutdown barrier" "shutdownIsABarrier" \
  '        if let flight = shutdownFlight {
            await flight.value
            return
        }' \
  '        if shutdownFlight != nil { return } // MUTATED: not a barrier'

mutate "single-flight cohort join" "singleFlight" \
  '            return try await flight.task.value' \
  '            _ = flight // MUTATED: no cohort join'

# The real-process guards. Each of these is a thing a fake transport cannot have an opinion about,
# which is the whole argument for E0: the evidence has to be produced against real OS resources.
mutate "E0 stderr drain" "chattyChildDoesNotWedge" \
  '        drainStandardError(of: pipes, named: upstream.name)' \
  '        _ = pipes // MUTATED: stderr is never drained'

mutate "E0 timeout teardown" "timedOutStartLeavesNoOrphan" \
  '        case .timedOut:
            // A throwing open must leave nothing behind, so the half-open child is closed here
            // rather than left for a reaper that will never be told it exists.
            await session.shutdown()' \
  '        case .timedOut:
            _ = session // MUTATED: leave the orphan running'

mutate "E0 SIGKILL escalation" "stubbornChildIsKilled" \
  '            kill(process.processIdentifier, SIGKILL)' \
  '            // MUTATED: no escalation past SIGTERM'

restore
echo "---"
if [ "$fail" -eq 0 ]; then
  echo "MUTATION GATE: all thirteen guards proved load-bearing"
else
  echo "MUTATION GATE: FAILED — see above"
fi
exit "$fail"
