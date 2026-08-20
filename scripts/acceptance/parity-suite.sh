#!/usr/bin/env bash
#
# R4 — the suite lane.
#
# A `proven-by-suite` row is a claim that a named test carries what no wire observation can. Until
# this lane existed, that claim was checked only by `parity-manifest-check.sh` confirming a
# function of that name EXISTS somewhere in app/Tests. A test that exists and fails, or exists and
# asserts something else entirely, satisfied it. Four rows counted toward coverage on that basis,
# and `div-r1-d5` counted because a lint script was present on disk and never run.
#
# So this lane runs them. Every citation in the manifest — `Suite/File.testName` for a test, a
# `scripts/…​.sh` path for a mechanical gate — is executed, and the row is proven only if it passes.
#
# It also supplies the SWIFT half of the pool rows. The pool lane measures the reference live and
# names a Swift test; before this lane it never ran that test and computed its verdict entirely
# from the reference, which made "the routers make the same decision" a one-sided measurement
# wearing a test's name. Both halves now have to pass in the same run, and the gate requires an
# `ok` from each lane for those rows.
#
# The trap this lane must not fall into: `swift test --filter` that matches NOTHING exits 0 and
# reports "with 0 tests ... passed". A green zero is the canonical way a test gate lies, so the
# reported test count is asserted to be non-zero for every citation.
#
# Exit codes: 0 every cited test ran and passed, 1 one failed or matched nothing, 2 the
# environment could not run swift.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${PARITY_MANIFEST:-$REPO_ROOT/planning/parity/surface.tsv}"
RESULTS="${PARITY_RESULTS:-}"

record() {
  [ -n "$RESULTS" ] || return 0
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$RESULTS"
}

command -v swift >/dev/null 2>&1 || { echo "environment: swift is not installed"; exit 2; }
[ -f "$MANIFEST" ] || { echo "environment: no manifest at $MANIFEST"; exit 2; }

pass=0; fail=0

# One `swift test` invocation per citation. Slower than one combined filter, and worth it: a
# combined run reports a total, and a total cannot say WHICH row's test is the one that failed.
run_test() { # group id citation
  local group="$1" id="$2" citation="$3"
  local test_name="${citation##*.}"
  local out count

  out="$(cd "$REPO_ROOT/app" && swift test --filter "$test_name" 2>&1)"
  local status=$?

  # "Test run with N tests in M suites passed" — N is the number that matters.
  count="$(printf '%s' "$out" | sed -n 's/.*Test run with \([0-9]*\) test.*/\1/p' | tail -1)"
  [ -z "$count" ] && count=0

  if [ "$status" != 0 ]; then
    fail=$((fail + 1))
    printf '  FAIL %-58s %s\n' "$citation" "the test failed"
    record "$group" "$id" fail "$citation failed"
    return
  fi
  if [ "$count" = 0 ]; then
    fail=$((fail + 1))
    printf '  FAIL %-58s %s\n' "$citation" "matched NO test — a green zero, not a pass"
    record "$group" "$id" fail "$citation matched no test; swift test reported 0 tests and exited 0"
    return
  fi
  pass=$((pass + 1))
  printf '  ok   %-58s %s test(s) passed\n' "$citation" "$count"
  record "$group" "$id" ok "$citation ran and passed ($count test(s))"
}

# A cited script's output is kept, not discarded, and printed when it fails.
#
# The first version sent both streams to /dev/null and printed "the gate reported findings" — a
# verdict with no evidence under it, which cost a whole gate run to diagnose: `parity-oauth.sh`
# failed here inside a full `parity-gate.sh` and passed every way it was run afterwards, and the
# reason it failed was in bytes this function had already thrown away. A gate that hides why it
# failed is the failure this repository keeps arguing against, so the log survives the run and its
# tail is printed inline.
run_script() { # group id script
  local group="$1" id="$2" script="$3"
  local log
  log="$(mktemp -t parity-suite-script)"
  if bash "$REPO_ROOT/$script" > "$log" 2>&1; then
    pass=$((pass + 1))
    printf '  ok   %-58s %s\n' "$script" "the gate ran and is clean"
    record "$group" "$id" ok "$script ran and passed"
    rm -f "$log"
  else
    fail=$((fail + 1))
    printf '  FAIL %-58s %s\n' "$script" "the gate reported findings"
    printf '       its last 20 lines, kept in full at %s:\n' "$log"
    sed -e 's/^/       | /' < <(tail -20 "$log")
    record "$group" "$id" fail "$script reported findings; output kept at $log"
  fi
}

# A row proven on the wire by its own lane can still cite a script, and that script then runs
# twice in one gate — once here and once as that lane. `control-auth-post-http` is the case: it
# cites `parity-oauth.sh`, which is also lane 13 of 13. That is kept rather than deduplicated, and
# it earned its keep on 20 Aug 2026: the citation run recorded `fail — the Swift router never
# reached the token endpoint` while the dedicated lane, twenty minutes later in the same gate,
# recorded ok over 21 checks. Neither a standalone run of the script, a standalone run of this
# lane, nor a second whole gate reproduced it. A single run would have reported a clean 82 of 83
# and nobody would have known. Both runs record under the same row id and a `fail` wins, which is
# the right precedence for a finding nobody can explain yet — DEF-033.
echo "running every citation the manifest rests on"
echo

while IFS=$'\t' read -r group id _subject verdict _owner note; do
  case "$group" in ''|'#'*) continue ;; esac
  [ "$verdict" = "blocked" ] && continue
  : "${_subject:-}" "${_owner:-}"   # read into, deliberately unused here

  # A row may cite a test, a script, or nothing. Rows citing nothing are proven on the wire by
  # another lane and are not this lane's business.
  for citation in $(printf '%s' "$note" | grep -oE '[A-Za-z]+Tests/[A-Za-z]+\.[a-zA-Z][a-zA-Z0-9]*' | sort -u); do
    run_test "$group" "$id" "$citation"
  done
  for script in $(printf '%s' "$note" | grep -oE 'scripts/[a-z/-]+\.sh' | sort -u); do
    run_script "$group" "$id" "$script"
  done
done < "$MANIFEST"

echo
echo "suite: $pass citation(s) ran and passed, $fail failed"
if [ "$((pass + fail))" = 0 ]; then
  echo "environment: the manifest cited nothing runnable, so this lane proved nothing."
  exit 2
fi
[ "$fail" -gt 0 ] && exit 1
exit 0
