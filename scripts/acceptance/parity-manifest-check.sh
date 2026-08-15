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
INDEX_TS="$REPO_ROOT/src/index.ts"
ROUTER_TS="$REPO_ROOT/src/router.ts"
FIXTURE_DIR="$REPO_ROOT/app/Sources/MCPRouterKit/Control/Fixtures"

[ -f "$MANIFEST" ]    || { echo "environment: no manifest at $MANIFEST"; exit 2; }
[ -f "$CONTROL_TS" ]  || { echo "environment: no reference at $CONTROL_TS"; exit 2; }
[ -f "$INDEX_TS" ]    || { echo "environment: no reference CLI at $INDEX_TS"; exit 2; }
[ -f "$ROUTER_TS" ]   || { echo "environment: no reference router at $ROUTER_TS"; exit 2; }
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

# ------------------------------------------------------------------ cli verbs
# Same argument as the control block above, for the group that had none. Until P4 the ten `cli`
# rows were hand-maintained: nothing tied them to `src/index.ts`, so a row could be DELETED and the
# coverage fraction would go UP — the numerator is untouched and the denominator shrinks. `cli-auth`
# is blocked today, so deleting it alone moved 73/83 to 73/82 with every check still green. That is
# the gate's own worst failure mode and the reason this section exists.
#
# Nothing here classifies a label by its SPELLING. The first design called any label beginning with
# `-` a flag and waved it through, which meant `case '--serve':` could add a CLI spelling that the
# gate never compares and never counts — D-n's failure mode rebuilt inside the fix for it. Instead
# every case label must be either a manifest row or a DECLARED alias, and an undeclared label is an
# error. New CLI surface cannot arrive silently.
CLI_ALIASES='--help
-h'

cli_switch="$(awk '/switch \(cmd\) \{/,/^  \}$/' "$INDEX_TS")"
if [ -z "$cli_switch" ]; then
  echo "environment: no \`switch (cmd) {\` block in $INDEX_TS. The CLI dispatch shape has changed"
  echo "             and this check would otherwise report a clean manifest against nothing."
  exit 2
fi

# Fall-through GROUPS, one per line, labels space-separated. A `case` line joins the current group;
# any other line that is not blank and not a comment closes it — including `default:`. The grouping
# is what lets an alias be checked against the verb it falls through with.
cli_groups="$(printf '%s\n' "$cli_switch" | awk '
BEGIN { gi = 0 }
/^[[:space:]]*case[[:space:]]/ {
  if (match($0, /\047[^\047]*\047/)) {
    lab = substr($0, RSTART + 1, RLENGTH - 2)
    group[gi] = (gi in group ? group[gi] " " : "") lab
  }
  next
}
/^[[:space:]]*$/              { next }
/^[[:space:]]*(\/\/|\*|\/\*)/ { next }
{ if (gi in group) gi++ }
END { for (i = 0; i <= gi; i++) if (i in group) print group[i] }
')"

cli_labels="$(printf '%s\n' "$cli_groups" | tr ' ' '\n' | grep -v '^$' | sort -u)"
if [ -z "$cli_labels" ]; then
  echo "environment: the \`switch (cmd)\` block in $INDEX_TS yielded no case labels."
  exit 2
fi
cli_rows="$(awk -F'\t' '$1 == "cli" { print $3 }' "$MANIFEST" | sort -u)"

while IFS= read -r label; do
  [ -z "$label" ] && continue
  if printf '%s\n' "$cli_rows"    | grep -qxF -e "$label"; then continue; fi
  if printf '%s\n' "$CLI_ALIASES" | grep -qxF -e "$label"; then continue; fi
  note "src/index.ts dispatches \"$label\", which is neither a cli manifest row nor a declared"
  note "  alias. A verb with no row is CLI surface the gate does not count."
done <<< "$cli_labels"

while IFS= read -r row; do
  [ -z "$row" ] && continue
  printf '%s\n' "$cli_labels" | grep -qxF -e "$row" \
    || note "the manifest carries cli row \"$row\", which src/index.ts does not dispatch"
done <<< "$cli_rows"

while IFS= read -r alias; do
  [ -z "$alias" ] && continue
  printf '%s\n' "$cli_labels" | grep -qxF -e "$alias" \
    || note "declared cli alias \"$alias\" is not a case label — the declaration is stale"
done <<< "$CLI_ALIASES"

# A group of aliases with no row-backed verb is a CLI surface with nothing to represent it: every
# label in it is excused as an alias, and the thing they are aliases OF has no row.
while IFS= read -r group; do
  [ -z "$group" ] && continue
  group_has_row=0
  for label in $group; do
    if printf '%s\n' "$cli_rows" | grep -qxF -e "$label"; then group_has_row=1; fi
  done
  [ "$group_has_row" = 1 ] \
    || note "case group \"$group\" has no label carrying a cli manifest row"
done <<< "$cli_groups"

# One direction only. A verb the help text advertises and the switch does not dispatch is a lie
# printed to the user; a dispatched verb the help text omits is an editorial choice (`refresh` and
# `help` are both deliberately undocumented today).
usage_verbs="$(sed -n 's/^[[:space:]]*mcp-router \([a-z][a-z-]*\).*/\1/p' "$INDEX_TS" | sort -u)"
while IFS= read -r verb; do
  [ -z "$verb" ] && continue
  printf '%s\n' "$cli_labels" | grep -qxF -e "$verb" \
    || note "usage() advertises \"$verb\" and no case label dispatches it"
done <<< "$usage_verbs"

# The independent signal, in the shape the control block uses above. The extractor reads exactly one
# idiom — the switch. A verb dispatched in a SECOND shape, `if (cmd === 'doctor')` above an intact
# switch, extracts nothing, demands no row, and leaves both directions of the comparison agreeing.
# The zero-guard cannot see it, because the switch still yields ten labels.
cmd_outside="$(grep -cE "cmd ===|cmd ==" "$INDEX_TS" || true)"
if [ "$cmd_outside" != 0 ]; then
  note "src/index.ts compares \`cmd\` outside the switch on $cmd_outside line(s)."
  note "  A verb dispatched in a shape this check cannot read is absent from BOTH the source list"
  note "  and the manifest, which reads as agreement and raises the coverage figure."
fi

# ------------------------------------------------------------------ mcp surface
# The five `mcp` rows, reconciled against src/router.ts the same way, for the same reason.
mcp_literals="$(sed -n "s/.*url\.pathname === '\([^']*\)'.*/\1/p" "$ROUTER_TS" | sort -u)"
mcp_path="$(sed -n "s/^const MCP_PATH = '\([^']*\)';.*/\1/p" "$ROUTER_TS" | head -1)"

if [ -z "$mcp_path" ]; then
  echo "environment: MCP_PATH is no longer a top-level literal in $ROUTER_TS, so the endpoint's"
  echo "             own path cannot be resolved and its row would go undemanded."
  exit 2
fi
grep -q 'url.pathname !== MCP_PATH' "$ROUTER_TS" \
  || note "src/router.ts no longer gates the MCP endpoint on \`url.pathname !== MCP_PATH\`"

# The control API is delegated wholesale at `isControlPath(url.pathname)`, and those paths carry
# `control` rows — they must NOT also demand `mcp` rows, which is why the extractor above reads
# only literal comparisons. The delegation is asserted rather than extracted: without this line it
# could be deleted while the mcp reconciliation stayed green and sixteen control rows described a
# surface the router had stopped routing to.
grep -q 'isControlPath(url.pathname)' "$ROUTER_TS" \
  || note "src/router.ts no longer delegates to isControlPath — the 16 control rows describe a surface it does not reach"

pathname_lines="$(grep -cE "url\.pathname [!=]== " "$ROUTER_TS" || true)"
extracted_paths="$(printf '%s\n%s\n' "$mcp_literals" "$mcp_path" | grep -c . || true)"
if [ "$pathname_lines" != "$extracted_paths" ]; then
  note "src/router.ts compares url.pathname on $pathname_lines line(s) but $extracted_paths path(s)"
  note "  could be extracted. A path answered in a shape this check cannot read has no row."
fi

# The JSON-RPC method names are NOT hand-mapped here. The symbol is read out of the source and the
# name is read out of the SDK schema that pins it, so renaming a method upstream moves this check
# with it. A symbol that will not resolve is an environment failure, never a skipped handler: a
# skipped handler is a JSON-RPC method with no row.
mcp_symbols="$(grep -oE "setRequestHandler\([A-Za-z][A-Za-z0-9]*" "$ROUTER_TS" | sed 's/.*(//' | sort -u)"
if [ -z "$mcp_symbols" ]; then
  echo "environment: no setRequestHandler(...) call found in $ROUTER_TS. The registration shape"
  echo "             has changed and every JSON-RPC row would go undemanded."
  exit 2
fi
if ! mcp_methods="$(cd "$REPO_ROOT" && node -e '
  const t = require("@modelcontextprotocol/sdk/types.js");
  for (const s of process.argv.slice(1)) {
    const v = t[s] && t[s].shape && t[s].shape.method && t[s].shape.method.value;
    if (!v) { console.error("cannot resolve " + s + " to a method name"); process.exit(3); }
    console.log(v);
  }' $mcp_symbols 2>&1)"; then
  echo "environment: $mcp_methods"
  echo "             The MCP method names are read from the installed SDK rather than from a table"
  echo "             in this file. Run npm install, or fix the handler registration."
  exit 2
fi

mcp_from_source="$(printf '%s\n%s\n%s\n' "$mcp_literals" "$mcp_path" "$mcp_methods" \
  | grep -v '^$' | sort -u)"
# Row subjects carry an HTTP verb for the http rows ("GET /health") and none for the JSON-RPC ones
# ("tools/list"), so they are compared on their last field.
mcp_from_manifest="$(awk -F'\t' '$1 == "mcp" { print $3 }' "$MANIFEST" | awk '{ print $NF }' | sort -u)"

while IFS= read -r subject; do
  [ -z "$subject" ] && continue
  printf '%s\n' "$mcp_from_manifest" | grep -qxF -e "$subject" \
    || note "src/router.ts answers \"$subject\" and the manifest has no mcp row for it"
done <<< "$mcp_from_source"

while IFS= read -r subject; do
  [ -z "$subject" ] && continue
  printf '%s\n' "$mcp_from_source" | grep -qxF -e "$subject" \
    || note "the manifest carries mcp row \"$subject\", which src/router.ts does not answer"
done <<< "$mcp_from_manifest"

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

# ------------------------------------------------------------------ cited row ids must exist
# The same principle as the two blocks above — a citation has to keep being true — applied to the
# thing they did not cover: rows that cite OTHER ROWS.
#
# This closes a hole the source reconciliations cannot reach. `control-auth-post` and
# `control-auth-post-http` deliberately share the subject `POST /servers/:name/auth`, because the
# control block reconciles SUBJECTS against src/control.ts and a descriptive subject on the second
# row would read as a row for a route the reference does not answer. The consequence is that
# deleting `control-auth-post-http` — blocked, so pure denominator — leaves the subject carried by
# its sibling, keeps both directions of the control comparison satisfied, and moves 73/83 to 73/82
# with this file exiting 0. A blocked row inside the "mechanically checked" group could be deleted
# to raise the figure.
#
# Each of that pair names the other in its note, and div-r1-d3 names div-r1-d3-control. Resolving
# those citations makes the deletion break something. No list is maintained here: the citations are
# already in the manifest, and this only insists they still resolve.
KNOWN_NON_IDS='mcp-router'
row_ids="$(awk -F'\t' '!/^#/ && NF == 6 { print $2 }' "$MANIFEST" | sort -u)"
# Tokenised by splitting on every character an id cannot contain, rather than with \b, which is not
# portable between BSD and GNU grep.
cited_ids="$(awk -F'\t' '!/^#/ && NF == 6 { print $6 }' "$MANIFEST" \
  | tr -c 'a-zA-Z0-9-' '\n' \
  | grep -E '^(control|fixture|divergence|div|pool|mcp|cli|install|state|log)-[a-z0-9]+(-[a-z0-9]+)*$' \
  | sort -u || true)"

while IFS= read -r token; do
  [ -z "$token" ] && continue
  if printf '%s\n' "$row_ids"       | grep -qxF -e "$token"; then continue; fi
  if printf '%s\n' "$KNOWN_NON_IDS" | grep -qxF -e "$token"; then continue; fi
  note "a note cites \"$token\", which is not a row id in this manifest."
  note "  Either the row it names was deleted, or the word is not an id and belongs in KNOWN_NON_IDS."
done <<< "$cited_ids"

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
