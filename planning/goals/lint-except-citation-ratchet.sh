#!/bin/bash
# `make lint` minus the citation ratchet's veto, and nothing else.
#
# The ratchet is NOT skipped: its blocking classes are judged by the `citations` gate beside this
# one, and the baseline is untouched, so `make lint` by hand still shows the debt. What is waived
# here is only the ratchet's *veto over the other eight steps*, because the bare citations over
# baseline live partly in an uncommitted third-party edit this run's brief forbids committing.
#
# ---------------------------------------------------------------------------------------------
# WHY THIS READS EXIT CODES AND NOT TEXT.
#
# The first version of this script asked `make lint` for one combined exit code and then guessed
# which step had failed by grepping the combined output for `error:|Violation|FAIL|did not pass
# lint`. G8's sweep-control-gate flagged it, and G8's verifier named the hole exactly: a step that
# fails with a message matching none of those four patterns, while `ratchet: BARE` appears anywhere
# in the output, made this script exit 0 and a real lint failure passed unnoticed. It was an
# absence sweep with no presence control, written by the party that spent the run demanding them.
#
# The fix is structural rather than a fifth pattern. `make lint` aggregates nine steps under one
# `fail=1`, so this script runs each step ITSELF and requires that the only non-zero one is
# `citation-gate.py`. Any other step failing fails this gate by construction, whatever it prints.
#
# The step list is PARSED FROM THE MAKEFILE, never copied. A copied list silently stops covering a
# step the moment someone adds one to `lint:`, which is the same fail-open one level up.
# ---------------------------------------------------------------------------------------------
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

WAIVED='planning/citation-gate.py'
MIN_STEPS=8   # presence control on the PARSER: lint had 9 steps when this was written.

mapfile -t STEPS < <(
  sed -n '/^lint:/,/^$/p' Makefile |
  grep -oE '^[[:space:]]*[^|]+ \|\| fail=1' |
  sed -E 's/[[:space:]]*\|\| fail=1$//; s/^[[:space:]]*//'
)

if [ "${#STEPS[@]}" -lt "$MIN_STEPS" ]; then
  echo "lint-gate: parsed only ${#STEPS[@]} steps from the Makefile's lint recipe, expected >= $MIN_STEPS."
  echo "lint-gate: the recipe's shape changed and this gate can no longer see every step."
  echo "lint-gate: INCONCLUSIVE — no verdict printed, because a verdict here would be an absence this instrument cannot see."
  exit 2
fi

echo "lint-gate: $(( ${#STEPS[@]} )) steps parsed from Makefile:lint"
fail_other=0; fail_waived=0
for s in "${STEPS[@]}"; do
  out=$(eval "$s" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then
    printf '  %-52s 0\n' "$s"
  elif [[ "$s" == *"$WAIVED"* ]]; then
    printf '  %-52s %s  (waived: ratchet only)\n' "$s" "$rc"
    fail_waived=1
    echo "$out" | grep -E 'ratchet|BARE|blocking' | tail -3 | sed 's/^/      /'
  else
    printf '  %-52s %s  <-- FAILS THIS GATE\n' "$s" "$rc"
    echo "$out" | tail -12 | sed 's/^/      /'
    fail_other=1
  fi
done

if [ "$fail_other" -ne 0 ]; then
  echo "lint: failed on a step that is not the citation ratchet"; exit 1
fi
if [ "$fail_waived" -ne 0 ]; then
  echo "lint: only the citation-ratchet veto failed — filed as debt, see citation-debt-surfaced-by-its-own-gate.md"
  exit 0
fi
echo "lint: clean"; exit 0
