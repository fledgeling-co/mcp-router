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

log=$(mktemp -t mcpr-tests); trap 'rm -f "$log"' EXIT
make test > "$log" 2>&1; rc=$?

tail -n 3 "$log"

if [ $rc -eq 0 ]; then exit 0; fi

echo
echo "=============== FAILING TESTS (re-printed from earlier in the log) ==============="
# swift-testing marks an issue with ✘ (U+2718) and records "recorded an issue"; xcodebuild uses
# "error:". Print all three, plus the file:line each names.
if ! grep -hE '✘|recorded an issue|error:|Fatal error|Test .* failed' "$log" | head -40; then
  echo "(no issue line matched — the failure is not one this reader recognises)"
  echo "FULL LOG TAIL, 60 lines, since the reader found nothing:"
  tail -n 60 "$log"
fi
echo "================================================================================="
echo "tests: make test exited $rc"
exit $rc
