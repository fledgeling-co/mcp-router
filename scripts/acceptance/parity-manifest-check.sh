#!/usr/bin/env bash
#
# R4: the manifest may not drift from the reference.
#
# `planning/parity/surface.tsv` is the census the whole gate reports against, which makes it the
# one file in this item that can lie without anything noticing. A route added to `src/control.ts`
# with no row here does not make the gate go red — it shrinks the denominator, and the coverage
# fraction goes UP. That is the precise failure this item exists to prevent, expressed as a
# maintenance accident rather than as a decision.
#
# So the control rows are checked against the reference mechanically, both ways:
#   · a route in control.ts with no manifest row  -> the manifest is stale (missing a row)
#   · a manifest row matching no route            -> the manifest is inflated (a row that
#                                                    cannot be proven because it does not exist)
#
# The second direction matters as much as the first. Rows can be added to raise a total that is
# then reported as coverage, and nothing else in the gate would catch it.
#
# Fixture rows are checked the same way, against the directory that holds them.
#
# Exit codes follow the house pattern: 1 is a manifest that disagrees with the source, 2 is an
# environment that could not run the check.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${PARITY_MANIFEST:-$REPO_ROOT/planning/parity/surface.tsv}"
CONTROL_TS="$REPO_ROOT/src/control.ts"
FIXTURE_DIR="$REPO_ROOT/app/Sources/MCPRouterKit/Control/Fixtures"

[ -f "$MANIFEST" ]    || { echo "environment: no manifest at $MANIFEST"; exit 2; }
[ -f "$CONTROL_TS" ]  || { echo "environment: no reference at $CONTROL_TS"; exit 2; }
[ -d "$FIXTURE_DIR" ] || { echo "environment: no fixtures at $FIXTURE_DIR"; exit 2; }

problems=0
note() { printf '  %s\n' "$1"; problems=$((problems + 1)); }

# ------------------------------------------------------------------ shape
# Every row carries six tab-separated fields, a verdict from the closed set, and an owner
# whenever it is blocked. A blocked row with no owner is a gap nobody has been given.
# Checked before anything else: a malformed row would otherwise be silently skipped by the
# comparisons below, which read specific fields.
line_no=0
while IFS= read -r row; do
  line_no=$((line_no + 1))
  case "$row" in ''|'#'*) continue ;; esac

  fields="$(printf '%s' "$row" | awk -F'\t' '{print NF}')"
  [ "$fields" = "6" ] || { note "line $line_no: $fields fields, expected 6"; continue; }

  verdict="$(printf '%s' "$row" | cut -f4)"
  owner="$(printf '%s' "$row" | cut -f5)"
  case "$verdict" in
    proven|proven-by-suite|blocked) ;;
    *) note "line $line_no: verdict \"$verdict\" is not proven | proven-by-suite | blocked" ;;
  esac
  if [ "$verdict" = "blocked" ] && { [ "$owner" = "-" ] || [ -z "$owner" ]; }; then
    note "line $line_no: blocked with no owning item — a gap with no owner is a gap nobody has"
  fi
  if [ "$verdict" != "blocked" ] && [ "$owner" != "-" ]; then
    note "line $line_no: verdict $verdict carries owner \"$owner\"; only a blocked row takes one"
  fi
done < "$MANIFEST"

# ------------------------------------------------------------------ control routes
# The reference's dispatch is three `if` shapes. Extracted rather than hand-listed, so this
# check keeps working when a route is added.
# The character classes accept hyphens, digits, underscores and uppercase. The first version took
# only [a-z/], so a route named /oauth-callback or /usage/v2 extracted NOTHING, demanded no
# manifest row, and shrank the denominator — the coverage percentage would have gone UP. That is
# the precise drift this file exists to catch, arriving as a maintenance accident.
routes_from_source="$(sed -n \
  "s/.*p === .\(\/[a-zA-Z0-9_\/-]*\). \&\& req\.method === .\([A-Z]*\).*/\2 \1/p;
   s/.*!sub \&\& req\.method === .\([A-Z]*\).*/\1 \/servers\/:name/p;
   s/.*sub === .\(\/[a-zA-Z0-9_-]*\). \&\& req\.method === .\([A-Z]*\).*/\2 \/servers\/:name\1/p" \
  "$CONTROL_TS" | sort -u)"

if [ -z "$routes_from_source" ]; then
  echo "environment: extracted no routes from $CONTROL_TS — the dispatch shape has changed and"
  echo "             this check would otherwise report a perfectly clean manifest against nothing."
  exit 2
fi

# A SECOND, independent count of the same thing.
#
# The extractor above only recognises three dispatch idioms. A route added in a fourth shape — a
# switch, a table, a differently-spelled condition — extracts nothing and is silently absent from
# both sides of the comparison, so the manifest agrees with a source it has stopped reading. The
# guard above fires only when the extractor gets ZERO routes; it cannot notice 15 where there are
# 16.
#
# Counting dispatch LINES with a different pattern catches that. `const mutating = req.method ===
# 'POST' || …` is deliberately not counted: it is a guard, not a route, and it is why this counts
# `if (` lines rather than every mention of req.method.
dispatch_lines="$(grep -cE "^[[:space:]]*if \(.*req\.method === '" "$CONTROL_TS")"
extracted_count="$(printf '%s\n' "$routes_from_source" | grep -c .)"
if [ "$dispatch_lines" != "$extracted_count" ]; then
  note "control.ts has $dispatch_lines dispatch lines but $extracted_count routes could be extracted."
  note "  A route is being dispatched in a shape this check cannot read, so it is missing from BOTH"
  note "  the source list and the manifest — which reads as agreement and raises the coverage figure."
fi

routes_from_manifest="$(awk -F'\t' '$1 == "control" { print $3 }' "$MANIFEST" | sort -u)"

while IFS= read -r route; do
  [ -z "$route" ] && continue
  printf '%s\n' "$routes_from_manifest" | grep -qxF "$route" \
    || note "control.ts answers \"$route\" and the manifest has no row for it"
done <<< "$routes_from_source"

while IFS= read -r route; do
  [ -z "$route" ] && continue
  printf '%s\n' "$routes_from_source" | grep -qxF "$route" \
    || note "the manifest carries control row \"$route\", which control.ts does not answer"
done <<< "$routes_from_manifest"

# ------------------------------------------------------------------ fixtures
fixtures_on_disk="$(find "$FIXTURE_DIR" -name '*.json' -exec basename {} .json \; | sort)"
fixtures_in_manifest="$(awk -F'\t' '$1 == "fixture" { print $3 }' "$MANIFEST" | sort)"

while IFS= read -r fixture; do
  [ -z "$fixture" ] && continue
  printf '%s\n' "$fixtures_in_manifest" | grep -qxF "$fixture" \
    || note "fixture \"$fixture\" is on disk and has no manifest row"
done <<< "$fixtures_on_disk"

while IFS= read -r fixture; do
  [ -z "$fixture" ] && continue
  printf '%s\n' "$fixtures_on_disk" | grep -qxF "$fixture" \
    || note "the manifest carries fixture row \"$fixture\", which is not on disk"
done <<< "$fixtures_in_manifest"

# ------------------------------------------------------------------ cited tests must exist
# A `proven-by-suite` row is a claim that some named test carries the weight no wire observation
# can. That claim is worth exactly as much as the citation, and a citation is the one thing here
# that can be written from memory and look right.
#
# This is not hypothetical. Three of this manifest's first six citations named tests that do not
# exist — they were written from the divergence prose rather than read out of the suite. Nothing
# in the gate noticed, because a fabricated citation reads exactly like a real one.
#
# So every `Suite/File.testName` token in any note is resolved against app/Tests, and every
# scripts/ path is resolved on disk. A renamed test breaks the row that depends on it, which is
# the point: the citation has to keep being true, not merely have been true once.
TEST_ROOT="$REPO_ROOT/app/Tests"
if [ -d "$TEST_ROOT" ]; then
  while IFS= read -r citation; do
    [ -z "$citation" ] && continue
    file="${citation%%.*}"        # RouterCoreTests/RealProcessTests
    test_name="${citation##*.}"   # poolSpawnsAndReapsARealChild
    if [ ! -f "$TEST_ROOT/$file.swift" ]; then
      note "cited test file \"$file.swift\" does not exist under app/Tests"
    elif ! grep -q "func $test_name" "$TEST_ROOT/$file.swift"; then
      note "cited test \"$test_name\" is not in $file.swift — the citation is stale or invented"
    fi
  done <<< "$(grep -oE '[A-Za-z]+Tests/[A-Za-z]+\.[a-zA-Z][a-zA-Z0-9]*' "$MANIFEST" | sort -u)"
fi

while IFS= read -r script; do
  [ -z "$script" ] && continue
  [ -f "$REPO_ROOT/$script" ] || note "cited script \"$script\" does not exist"
done <<< "$(grep -oE 'scripts/[a-z/-]+\.sh' "$MANIFEST" | sort -u)"

# ------------------------------------------------------------------ ids are unique
# Two rows sharing an id means one lane's result overwrites the other's during reconciliation,
# and a row silently inherits a verdict it never earned.
dupes="$(awk -F'\t' '!/^#/ && NF == 6 { print $2 }' "$MANIFEST" | sort | uniq -d)"
if [ -n "$dupes" ]; then
  while IFS= read -r id; do note "duplicate row id \"$id\""; done <<< "$dupes"
fi

total="$(awk -F'\t' '!/^#/ && NF == 6' "$MANIFEST" | wc -l | tr -d ' ')"

if [ "$problems" -gt 0 ]; then
  echo
  echo "manifest-check: $problems problem(s). The coverage fraction is computed from this file,"
  echo "                so a stale manifest reports a higher pass rate than the port has earned."
  exit 1
fi
echo "manifest-check: $total rows, consistent with control.ts and the fixture directory."
