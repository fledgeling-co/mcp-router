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
# Resolved before the cd below, and that ordering is load-bearing: the summary counts this file's
# own check invocations to get a denominator, and a relative `$0` stops resolving the moment the
# script changes directory. It did, on the first run after the counter was added — the gate refused
# rather than printing counts over an empty base, which is the behaviour, but the cause was here.
GATE_SELF="${0:A}"
REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$REPO_ROOT/app" || exit 90

# The actor is split across two files (file-length limit), so both are mutated and both restored.
CORE=Sources/RouterCore/Pool/UpstreamPool.swift
REAP=Sources/RouterCore/Pool/UpstreamPoolReaping.swift
TRANS=Sources/RouterCore/Pool/StdioUpstreamTransport.swift
# The forced-termination escalation used to live in the transport. It moved to the session type,
# and because this list did not follow it, the SIGKILL mutation stopped applying: the gate reported
# SKIP indefinitely while measuring nothing about the one behaviour that stops a wedged child
# holding the router's shutdown open. A file the gate mutates must be a file the gate restores, so
# it is added to all four places at once.
SESS=Sources/RouterCore/Pool/StdioUpstreamSession.swift
CORE_BACKUP=$(mktemp); cp "$CORE" "$CORE_BACKUP"
REAP_BACKUP=$(mktemp); cp "$REAP" "$REAP_BACKUP"
TRANS_BACKUP=$(mktemp); cp "$TRANS" "$TRANS_BACKUP"
SESS_BACKUP=$(mktemp); cp "$SESS" "$SESS_BACKUP"
restore() {
  cp "$CORE_BACKUP" "$CORE"; cp "$REAP_BACKUP" "$REAP"
  cp "$TRANS_BACKUP" "$TRANS"; cp "$SESS_BACKUP" "$SESS"
}
trap restore EXIT

# Outcome bookkeeping. `fail` alone could not answer the question the gate is asked — "was every
# guard proved?" — because it collapsed six different outcomes into one bit and the summary line
# then asserted "all thirteen guards proved load-bearing" from it. A run in which one check found a
# hole and another never applied printed the same FAILED as a run in which the suite would not
# build, and a run in which every check merely *ran* would have printed the same success as a run in
# which every check killed its guard.
#
# Six outcomes, and the two that read most alike are kept furthest apart:
#   proved       OK    the guard was removed and its test went red. The only thing that counts.
#   holes        HOLE  the test ran and passed WITHOUT the guard. The guard is unproved.
#   stale        STALE the mutation no longer applies; the source moved out from under the pattern.
#                      Distinguishable from OK by construction: nothing was measured at all.
#   inconclusive BUILD/HANG/NORUN — the mutation did not compile, the suite timed out, or the
#                      filter matched no test. None of these is a pass and none is a failure of the
#                      guard; they are failures of the check.
#   withdrawn    N/A   the check is deliberately retired, with its reason printed on the line. A
#                      pass is allowed over one of these, which is exactly why it must be visible.
proved=0
holes=0
stale=0
inconclusive=0
withdrawn=0

mutate() {
  local name="$1" test="$2" find="$3" replace="$4"
  restore
  FIND="$find" REPLACE="$replace" python3 - "$CORE" "$REAP" "$TRANS" "$SESS" <<'PY'
import os, sys
find, replace = os.environ["FIND"], os.environ["REPLACE"]
for path in sys.argv[1:]:
    text = open(path).read()
    if find in text:
        open(path, "w").write(text.replace(find, replace))
PY
  if ! grep -q "MUTATED" "$CORE" "$REAP" "$TRANS" "$SESS"; then
    echo "STALE $name — the mutation did not apply; the source has moved out from under it,"
    echo "      so this check measured NOTHING. It is not a pass."
    stale=$((stale + 1))
    return
  fi

  out=$(perl -e 'alarm 240; exec @ARGV' swift test --filter "$test" 2>&1)
  local rc=$?

  if echo "$out" | grep -qE "^/.*error:|error: fatalError"; then
    echo "BUILD $name — mutation did not compile (inconclusive)"
    inconclusive=$((inconclusive + 1))
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
    inconclusive=$((inconclusive + 1))
    return
  fi

  if printf '%s\n' "$out" | grep -q "Test run with .* passed"; then
    echo "HOLE  $name — '$test' ran ($ran) and still passed without the guard"
    holes=$((holes + 1))
  else
    echo "OK    $name — '$test' ran ($ran) and fails without the guard"
    proved=$((proved + 1))
  fi
}

# A check retired on purpose. It costs nothing to run and it is not a proof, so it prints its own
# reason on its own line and is counted apart from the guards that were actually proved. There are
# none on this tree; the function exists so that withdrawing one is a recorded act rather than a
# deletion nobody sees.
withdraw() { # withdraw <name> <reason>
  echo "N/A   $1 — WITHDRAWN: $2"
  withdrawn=$((withdrawn + 1))
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

# The denominator, counted from this file rather than written into it. "all thirteen guards proved
# load-bearing" was a literal thirteen in an echo, so it stayed thirteen while the gate ran twelve
# checks and while one of the thirteen measured nothing — a number that could not disagree with the
# gate no matter what the gate found. Counting the check invocations means adding a mutation without
# a verdict, or losing one, shows up here instead of nowhere.
declared=$(grep -cE '^(mutate|withdraw) ' "$GATE_SELF")
accounted=$((proved + holes + stale + inconclusive + withdrawn))

echo "Checks: $declared declared, $accounted accounted for."
echo "  proved load-bearing (OK):        $proved/$declared"
echo "  guard unproved (HOLE):           $holes/$declared"
echo "  measured nothing (STALE):        $stale/$declared"
echo "  check failed (BUILD/HANG/NORUN): $inconclusive/$declared"
echo "  withdrawn with a reason (N/A):   $withdrawn/$declared"

fail=0

# Every count above is over $declared, so a mismatch means the counts are over the wrong base and
# none of them is readable. That is a failure of the gate, reported as one.
if [ "$accounted" -ne "$declared" ]; then
  echo "MUTATION GATE: FAILED — $declared checks are declared but $accounted produced a verdict."
  echo "               The figures above are over the wrong denominator and none of them is evidence."
  fail=1
fi

# A pass requires that every check either proved its guard or declared why it cannot. A hole, a
# stale pattern and an inconclusive run are each a check that did not prove anything, and none of
# them may be read as a guard that holds.
if [ "$holes" -ne 0 ] || [ "$stale" -ne 0 ] || [ "$inconclusive" -ne 0 ]; then
  echo "MUTATION GATE: FAILED — $((holes + stale + inconclusive)) of $declared checks proved no guard."
  echo "               HOLE means the guard could be deleted today and nothing would say so."
  echo "               STALE means the mutation no longer applies, so that check measured nothing."
  echo "               BUILD/HANG/NORUN means the check itself failed, which is not a verdict."
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  if [ "$withdrawn" -eq 0 ]; then
    echo "MUTATION GATE: PASSED — $proved of $declared guards proved load-bearing, none withdrawn."
  else
    echo "MUTATION GATE: PASSED — $proved of $declared guards proved load-bearing;"
    echo "               $withdrawn check(s) withdrawn with a reason, listed above as N/A."
  fi
fi
exit "$fail"
