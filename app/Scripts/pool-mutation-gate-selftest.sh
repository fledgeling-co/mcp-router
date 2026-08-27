#!/bin/zsh
# G13 — can the pool mutation gate's VERDICT go red?
#
# The gate removes one race guard at a time and requires the covering test to fail. Its summary
# line used to be `echo "MUTATION GATE: all thirteen guards proved load-bearing"` behind a single
# `fail` bit, so six different outcomes collapsed into one, and the literal thirteen could not
# disagree with the gate no matter what the gate found. It said FAILED identically for a guard
# nothing proves, a mutation that no longer applies, and a suite that would not compile — and the
# specification then recorded it as having proved every guard, which the gate itself contradicted.
#
# So the verdict logic needs its own red, and it cannot get one from a real run: thirteen mutations
# are thirteen rebuilds, and a check that costs half an hour is a check nobody arms. This file runs
# the REAL gate with `swift` replaced on PATH by a shim that prints a chosen suite result. No build,
# no test, and every outcome class reachable in seconds.
#
# What this does NOT cover, stated rather than implied: whether each mutation actually removes the
# guard it names, and whether the covering test is strong enough to notice. That is what a real
# `pool-mutation-gate.sh` run establishes, and nothing here substitutes for it.
#
# Exit codes: 0 every case behaved, 1 a case did not, 2 the environment could not run the gate.
set -u

HERE="${0:A:h}"
GATE="$HERE/pool-mutation-gate.sh"
REPO_ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || echo "")"

[ -f "$GATE" ] || { echo "environment: no gate at $GATE"; exit 2 }
[ -n "$REPO_ROOT" ] || { echo "environment: $HERE is not inside a git worktree"; exit 2 }
command -v python3 >/dev/null 2>&1 || { echo "environment: no python3"; exit 2 }

# The four files the gate mutates. Their hashes bracket every case: the gate restores from its own
# backups on the way out, and a selftest that ran it five times without checking that would be the
# most expensive way yet found to corrupt a working tree.
SOURCES=(
  "$REPO_ROOT/app/Sources/RouterCore/Pool/UpstreamPool.swift"
  "$REPO_ROOT/app/Sources/RouterCore/Pool/UpstreamPoolReaping.swift"
  "$REPO_ROOT/app/Sources/RouterCore/Pool/StdioUpstreamTransport.swift"
  "$REPO_ROOT/app/Sources/RouterCore/Pool/StdioUpstreamSession.swift"
)
for f in $SOURCES; do
  [ -f "$f" ] || { echo "environment: the gate mutates $f, which does not exist"; exit 2 }
done
SHA_BEFORE="$(shasum -a 256 $SOURCES | awk '{print $1}' | tr '\n' ' ')"

DECLARED=$(grep -cE '^(mutate|withdraw) ' "$GATE")
[ "$DECLARED" -ge 2 ] || { echo "environment: read $DECLARED checks out of $GATE"; exit 2 }

WORK="$(mktemp -d -t pool-mutation-gate-selftest)"
cleanup() { rm -rf "$WORK"; rm -f "$REPO_ROOT/app/Scripts/.selftest-mutant-"*.sh }
trap cleanup EXIT

# The shim. SUITE_OUT is what `swift test` prints; SUITE_RC is what it exits.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/swift" <<'SHIM'
#!/bin/sh
printf '%s\n' "$SUITE_OUT"
exit "${SUITE_RC:-0}"
SHIM
chmod +x "$WORK/bin/swift"

pass=0; fail=0
report() {
  if [ "$1" = ok ]; then
    pass=$((pass + 1)); printf '  ok    %s\n' "$2"
  else
    fail=$((fail + 1)); printf '  FAIL  %s\n        %s\n' "$2" "$3"
  fi
}

run_gate() { # run_gate <script> <suite-output> <suite-rc>  -> sets OUT and CODE
  OUT="$(PATH="$WORK/bin:$PATH" SUITE_OUT="$2" SUITE_RC="$3" "$1" 2>&1)"; CODE=$?
}

RED="Test run with 3 tests in 1 suite failed after 0.1 seconds with 1 issue."
GREEN="Test run with 3 tests in 1 suite passed after 0.1 seconds."
EMPTY="Test run with 0 tests in 0 suites passed after 0.1 seconds."

echo "pool-mutation-gate-selftest: $DECLARED checks declared in the gate"
echo

# --- 1. every covering test goes red -> a pass, with a denominator ------------------------------
run_gate "$GATE" "$RED" 1
[ "$CODE" -eq 0 ] && report ok "all guards red -> exit 0" \
                  || report no "all guards red -> exit 0" "exit $CODE: $OUT"
case "$OUT" in
  *"PASSED — $DECLARED of $DECLARED guards proved load-bearing"*)
    report ok "the pass names $DECLARED of $DECLARED, not a literal" ;;
  *) report no "the pass names $DECLARED of $DECLARED, not a literal" "summary: ${OUT##*---}" ;;
esac
case "$OUT" in
  *"$DECLARED declared, $DECLARED accounted for"*) report ok "every declared check produced a verdict" ;;
  *) report no "every declared check produced a verdict" "summary: ${OUT##*---}" ;;
esac

# --- 2. a guard nothing proves is a failure, and says which kind --------------------------------
run_gate "$GATE" "$GREEN" 0
[ "$CODE" -ne 0 ] && report ok "a test that passes without its guard -> non-zero" \
                  || report no "a test that passes without its guard -> non-zero" "exit 0: $OUT"
case "$OUT" in
  *"HOLE "*) report ok "the hole is named HOLE on its own line" ;;
  *) report no "the hole is named HOLE on its own line" "output: $OUT" ;;
esac
case "$OUT" in
  *"proved no guard"*) report ok "the verdict says how many checks proved no guard" ;;
  *) report no "the verdict says how many checks proved no guard" "summary: ${OUT##*---}" ;;
esac
case "$OUT" in
  *"PASSED"*) report no "a run full of holes never prints PASSED" "it printed PASSED" ;;
  *) report ok "a run full of holes never prints PASSED" ;;
esac

# --- 3. a filter that matched no test is not a pass ----------------------------------------------
run_gate "$GATE" "$EMPTY" 0
[ "$CODE" -ne 0 ] && report ok "zero tests executed -> non-zero" \
                  || report no "zero tests executed -> non-zero" "exit 0: $OUT"
case "$OUT" in
  *"NORUN "*) report ok "zero tests executed is reported as NORUN" ;;
  *) report no "zero tests executed is reported as NORUN" "output: $OUT" ;;
esac

# --- 4. a mutation that no longer applies is distinguishable from one that applied and passed ----
#
# The gate is copied and ONE find-pattern is corrupted — a mutant of the gate, which is the same
# instrument the gate points at the pool. Running the copy in place keeps `git rev-parse` and the
# `app` cd working; it is removed by the trap above.
MUTANT="$REPO_ROOT/app/Scripts/.selftest-mutant-$$.sh"
python3 - "$GATE" "$MUTANT" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
# Corrupt the first mutation's search pattern so it can no longer match the source.
needle = "'            await session.shutdown()' \\"
assert needle in text, "the first mutation's find-pattern has moved; this selftest needs re-aiming"
open(dst, "w").write(text.replace(needle, "'            await session.shutdownXX()' \\", 1))
PY
[ -f "$MUTANT" ] || { echo "environment: could not build the gate mutant"; exit 2 }
chmod +x "$MUTANT"

run_gate "$MUTANT" "$RED" 1
[ "$CODE" -ne 0 ] && report ok "a mutation that no longer applies -> non-zero" \
                  || report no "a mutation that no longer applies -> non-zero" "exit 0: $OUT"
case "$OUT" in
  *"STALE "*) report ok "a stale mutation is labelled STALE, not OK" ;;
  *) report no "a stale mutation is labelled STALE, not OK" "output: $OUT" ;;
esac
case "$OUT" in
  *"measured NOTHING"*) report ok "the stale line says nothing was measured" ;;
  *) report no "the stale line says nothing was measured" "output: $OUT" ;;
esac
proved_line=$(printf '%s\n' "$OUT" | grep 'proved load-bearing (OK)')
case "$proved_line" in
  *"$((DECLARED - 1))/$DECLARED"*)
    report ok "the stale check is excluded from the proved count ($((DECLARED - 1))/$DECLARED)" ;;
  *) report no "the stale check is excluded from the proved count" "line: $proved_line" ;;
esac

# --- 5. the tree is exactly as it was ------------------------------------------------------------
SHA_AFTER="$(shasum -a 256 $SOURCES | awk '{print $1}' | tr '\n' ' ')"
[ "$SHA_BEFORE" = "$SHA_AFTER" ] \
  && report ok "the four mutated sources are restored byte-identically" \
  || report no "the four mutated sources are restored byte-identically" \
              "before: $SHA_BEFORE  after: $SHA_AFTER"

echo
echo "cases: $pass passed, $fail failed, of $((pass + fail))"
if [ "$fail" -ne 0 ]; then
  echo "error: the pool mutation gate's verdict does not distinguish a guard it proved from one it"
  echo "       could not measure. Its summary line is not evidence."
  exit 1
fi
echo "The pool mutation gate's verdict goes red on a hole, a stale mutation and an empty run."
