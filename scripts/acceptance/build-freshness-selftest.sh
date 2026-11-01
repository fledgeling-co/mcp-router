#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/acceptance/build-freshness.sh"
CASE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/router-freshness.XXXXXX")"
trap 'rm -rf "$CASE_ROOT"' EXIT
mkdir -p "$CASE_ROOT/app/MCPRouter" "$CASE_ROOT/app/Sources/MCPRouterKit" \
    "$CASE_ROOT/app/Sources/MCPRouterUI"
printf 'fixture\n' > "$CASE_ROOT/app/MCPRouter/Fixture.swift"
printf 'fixture\n' > "$CASE_ROOT/app/project.yml"
printf 'fixture\n' > "$CASE_ROOT/app/Package.swift"

echo 'measure with optional Package.resolved absent'
ABSENT="$(build_freshness_digest Debug "$CASE_ROOT")"
[[ "$ABSENT" =~ ^[0-9a-f]{64}$ ]]
build_freshness_begin Debug "$CASE_ROOT"
[[ "$(cat "$CASE_ROOT/app/.derived/.mcprouter-build-pre-Debug")" == "$ABSENT" ]]

printf 'first resolution\n' > "$CASE_ROOT/app/Package.resolved"
PRESENT="$(build_freshness_digest Debug "$CASE_ROOT")"
[[ "$PRESENT" != "$ABSENT" ]]
printf 'changed resolution\n' > "$CASE_ROOT/app/Package.resolved"
CHANGED="$(build_freshness_digest Debug "$CASE_ROOT")"
[[ "$CHANGED" != "$PRESENT" ]]
rm "$CASE_ROOT/app/Package.resolved"
[[ "$(build_freshness_digest Debug "$CASE_ROOT")" == "$ABSENT" ]]

# A failed read before an absent final input must still fail the whole measurement.
find() { return 66; }
if build_freshness_digest Debug "$CASE_ROOT" >/dev/null; then
    echo 'FAIL: a failed input traversal was accepted' >&2
    exit 1
fi
if build_freshness_begin Debug "$CASE_ROOT" >/dev/null; then
    echo 'FAIL: preflight accepted a failed input traversal' >&2
    exit 1
fi
unset -f find
echo 'build freshness: 7 controls passed (absent, begin, present, changed, removed, read failure, begin failure)'
