#!/usr/bin/env bash
#
# G12 — can the mutation harness's filter go red?
#
# `mutation-gate.sh` is what other checks are measured against: "the mutation gate passed" is meant
# to be the strongest evidence this repository produces. It accepts a filter naming which mutations
# to run, and until this file existed a filter naming a mutation that does not exist selected
# nothing, ran nothing, and exited 0 with a summary reading `0 — none` on both oracles — the same
# success a run that selected everything and killed it produces.
#
# That is the failure the harness exists to catch, occurring in the harness. It was taken as
# evidence twice in one session before a third filter happened to match.
#
# So this file asserts the SELECTION, which is the half that decides what a run means, and it
# asserts it cheaply: the harness resolves its filter before the dirty-tree guard and before the
# baseline, so every case here costs milliseconds and needs no build, no clean tree and no router.
# A selftest that needed a rebuild would be run before a merge, which is exactly when nobody runs
# it.
#
# What this file does NOT cover, stated rather than implied: the mutation loop itself — applying a
# pattern, running the two oracles, restoring the tree. Proving that needs a real build per row and
# lives in `make mutation`. The run-count assertion at the end of the harness (selected == verdicts)
# is defence-in-depth over that loop and is not armed here.
#
# Exit codes: 0 every case behaved, 1 a case did not — which is the finding, 2 the environment
# could not run the harness at all.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/scripts/parity/mutation-gate.sh"

[ -f "$GATE" ] || { echo "environment: no mutation gate at $GATE"; exit 2; }
[ -x "$GATE" ] || { echo "environment: $GATE is not executable"; exit 2; }

# The harness's own shebang picks its interpreter. Resolve the same one here so a parse failure is
# reported as an environment fault rather than as thirty-five failing cases.
GATE_BASH="$(command -v bash || true)"
[ -n "$GATE_BASH" ] || { echo "environment: no bash on PATH"; exit 2; }
if ! "$GATE_BASH" -n "$GATE" 2>/dev/null; then
  echo "environment: $GATE does not parse under $GATE_BASH ($("$GATE_BASH" --version | head -1))."
  echo "             Every case below would fail for that reason and none of them would be about"
  echo "             the filter, so this is a skip-with-a-cause rather than a finding."
  exit 2
fi

# The denominator, counted from the table in the harness rather than from the harness's own report
# of it — a count that reads its own answer back proves nothing.
TABLE_IDS="$(sed -n "/^MUTATIONS=\$(cat <<'TABLE'\$/,/^TABLE\$/p" "$GATE" \
             | sed '1d;$d' | grep -c '@@')"
if [ "${TABLE_IDS:-0}" -lt 2 ]; then
  echo "environment: could not read the mutation table out of $GATE (found ${TABLE_IDS:-0} rows)."
  echo "             Its shape has changed and this file would be measuring nothing."
  exit 2
fi

pass=0; fail=0

report() { # report <ok|no> <label> <detail>
  if [ "$1" = ok ]; then
    pass=$((pass + 1)); printf '  ok    %s\n' "$2"
  else
    fail=$((fail + 1)); printf '  FAIL  %s\n        %s\n' "$2" "$3"
  fi
}

run_gate() { # run_gate <args...>  -> sets OUT and CODE
  OUT="$("$GATE" "$@" 2>&1)"; CODE=$?
}

echo "mutation-gate-selftest: ${TABLE_IDS} mutations in the table"
echo

# --- 1. a filter that selects nothing is a failure, on the REAL run path -------------------------
#
# No --list here, deliberately: the defect was in the path a person actually invokes.
run_gate NO-SUCH-MUTATION
[ "$CODE" -eq 2 ] \
  && report ok "a filter naming no mutation exits 2 (not 0)" \
  || report no "a filter naming no mutation exits 2 (not 0)" "exit was $CODE, output: $OUT"

case "$OUT" in
  *"matched no mutation"*) report ok "the failure says the filter matched nothing" ;;
  *) report no "the failure says the filter matched nothing" "output: $OUT" ;;
esac

# The distinction the whole item is about: this must not read like a run that happened and passed.
case "$OUT" in
  *"Every named behaviour is load-bearing."*)
    report no "an empty selection never prints the success line" "it printed the success line" ;;
  *) report ok "an empty selection never prints the success line" ;;
esac

case "$OUT" in
  *Baseline:*)
    report no "an empty selection fails before the baseline build" "it reached the baseline" ;;
  *) report ok "an empty selection fails before the baseline build" ;;
esac

# Exit 2 rather than 1 is what makes a filter fault distinguishable, by code alone, from mutations
# that ran and reported a decoration. Assert the harness still reserves 1 for that.
if grep -q '^exit \$status$' "$GATE" && grep -q 'status=1' "$GATE"; then
  report ok "exit 1 is still reserved for mutations that ran and reported a finding"
else
  report no "exit 1 is still reserved for mutations that ran and reported a finding" \
            "no 'status=1' / 'exit \$status' pair found in $GATE"
fi

# --- 2. one good id and one typo is still a failure ----------------------------------------------
FIRST_ID="$(sed -n "/^MUTATIONS=\$(cat <<'TABLE'\$/,/^TABLE\$/p" "$GATE" \
            | sed '1d;$d' | grep '@@' | head -1 | sed 's/@@.*//')"
run_gate "$FIRST_ID" NO-SUCH-MUTATION
[ "$CODE" -eq 2 ] \
  && report ok "a partly-mistyped filter ($FIRST_ID + a typo) exits 2" \
  || report no "a partly-mistyped filter ($FIRST_ID + a typo) exits 2" "exit was $CODE: $OUT"

# --- 3. a filter that selects some checks selects exactly those ----------------------------------
SECOND_ID="$(sed -n "/^MUTATIONS=\$(cat <<'TABLE'\$/,/^TABLE\$/p" "$GATE" \
             | sed '1d;$d' | grep '@@' | sed -n '2p' | sed 's/@@.*//')"
run_gate --list "$FIRST_ID" "$SECOND_ID"
if [ "$CODE" -eq 0 ] && [ "$OUT" = "Selected 2 of ${TABLE_IDS} mutations: $FIRST_ID $SECOND_ID" ]; then
  report ok "a two-id filter selects exactly those two, with a denominator"
else
  report no "a two-id filter selects exactly those two, with a denominator" \
            "exit $CODE, output: $OUT"
fi

# A repeated id must not inflate the selection: the count is a denominator other numbers divide by.
run_gate --list "$FIRST_ID" "$FIRST_ID"
if [ "$CODE" -eq 0 ] && [ "$OUT" = "Selected 1 of ${TABLE_IDS} mutations: $FIRST_ID" ]; then
  report ok "a repeated id counts once"
else
  report no "a repeated id counts once" "exit $CODE, output: $OUT"
fi

# --- 4. an unfiltered run is unchanged: every row, and the count says so -------------------------
run_gate --list
all_ok=0
[ "$CODE" -eq 0 ] || all_ok=1
case "$OUT" in "Selected ${TABLE_IDS} of ${TABLE_IDS} mutations: "*) ;; *) all_ok=1 ;; esac
if [ "$all_ok" -eq 0 ]; then
  report ok "no filter selects all ${TABLE_IDS} mutations"
else
  report no "no filter selects all ${TABLE_IDS} mutations" "exit $CODE, output: $OUT"
fi

# Every id in the table must appear in the unfiltered selection — a count can match while the set
# does not.
missing=""
for id in $(sed -n "/^MUTATIONS=\$(cat <<'TABLE'\$/,/^TABLE\$/p" "$GATE" \
            | sed '1d;$d' | grep '@@' | sed 's/@@.*//'); do
  case " ${OUT#*: } " in *" $id "*) ;; *) missing="$missing $id" ;; esac
done
[ -z "$missing" ] \
  && report ok "the unfiltered selection contains every id in the table" \
  || report no "the unfiltered selection contains every id in the table" "missing:$missing"

# --- 5. an unknown option is a usage failure, not a silent no-op ---------------------------------
run_gate --no-such-flag
[ "$CODE" -eq 2 ] \
  && report ok "an unknown option exits 2" \
  || report no "an unknown option exits 2" "exit was $CODE: $OUT"

echo
echo "cases: $pass passed, $fail failed, of $((pass + fail))"
[ "$fail" -eq 0 ] || {
  echo "error: the mutation harness's filter does not fail closed. A run that selects nothing"
  echo "       would report the same success as a run that selected everything and killed it."
  exit 1
}
echo "The mutation harness fails closed on a filter that selects nothing."
