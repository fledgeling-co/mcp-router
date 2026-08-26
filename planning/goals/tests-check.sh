#!/bin/bash
# `make test`, with the failing test named LAST so a tail-capture can diagnose it.
#
# WHY THIS EXISTS. The goal's `tests` gate ran `make test` directly. swift-testing prints an issue
# inline, at the point of failure, and then carries on for thousands more lines; the guard captures
# the TAIL. So on 2026-08-26 the gate went red with `1 issue` and every line the guard showed was a
# pass. The failure was real and undiagnosable in the same breath, and the re-run was green, which
# is the worst combination — a flake you cannot name is a flake you cannot fix or attribute.
#
# This does not weaken the gate. `make test`'s exit code passes through untouched. All it does is
# re-print the issue lines at the end so they survive truncation.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

# The reader's own control, run before the gate does any work — a control invoked by nothing is
# the defect blocking G9, and this one has already caught a live bug in this reader.
if ! bash planning/goals/tests-reader-control.sh; then
  echo "tests: reader control did not hold; the failure section below cannot be trusted."
  echo "tests: INCONCLUSIVE at exit 2."
  exit 2
fi

log=$(mktemp -t mcpr-tests); trap 'rm -f "$log"' EXIT
make test > "$log" 2>&1; rc=$?

tail -n 3 "$log"

if [ $rc -eq 0 ]; then exit 0; fi

echo
echo "=============== FAILING TESTS (re-printed from earlier in the log) ==============="
# PRECISE MARKERS ONLY. The first version of this reader included `Test .* failed`, and this
# repository names dozens of tests after the failure they exercise — "a failed poll appends no
# sample", "a failed rename leaves the temp file in place". On a GREEN run that pattern matched 59
# lines, none of them a failure, and `head -40` then truncated before any real marker could appear.
# So the reader printed a wall of passes under a heading that said FAILING TESTS. That is the
# sentinel-matches-what-it-is-searching-past defect M32's brief records, in the reader written to
# diagnose it.
#
# `error:` is likewise excluded unless it carries a compiler's file:line:col shape, because the
# router's own fixtures log `error failed to index ...` on the paths that test error handling.
if ! grep -hE '✘|recorded an issue|^[^ ]+\.swift:[0-9]+:[0-9]+: error:|Test run with .* (failed|issue)' "$log" | head -40; then
  echo "(no issue line matched — the failure is not one this reader recognises)"
  echo "FULL LOG TAIL, 60 lines, since the reader found nothing:"
  tail -n 60 "$log"
fi
echo "================================================================================="
echo "tests: make test exited $rc"
exit $rc
