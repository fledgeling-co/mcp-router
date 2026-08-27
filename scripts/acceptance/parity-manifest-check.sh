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
# `note` opens a finding: it prints and it counts. `detail` continues one: it prints and it does
# NOT count.
#
# Every multi-line finding here used to call `note` once per line, so the gate whose entire subject
# is that numbers are not inflated inflated its own — one problem reporting as two, three or four.
# The split is the fix, and it changes no finding, no threshold and no verdict: only the number
# that follows the word "problem(s)".
note() { printf '  %s\n' "$1"; problems=$((problems + 1)); }
detail() { printf '  %s\n' "$1"; }

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
  detail "  A route is being dispatched in a shape this check cannot read, so it is missing from BOTH"
  detail "  the source list and the manifest — which reads as agreement and raises the coverage figure."
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

# Comment lines are dropped before anything is extracted. Otherwise a commented-out arm keeps
# demanding its row, and a real one deleted alongside its comment reads as still present.
strip_comments() { sed -e 's://.*::' -e '/^[[:space:]]*\*/d' -e '/^[[:space:]]*\/\*/d' "$1"; }

cli_switch="$(strip_comments "$INDEX_TS" | awk '/switch \(cmd\) \{/,/^  \}$/')"
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
  # EVERY quoted label on the line, in either quote style. Reading only the first match dropped
  # the second arm of `case \047serve\047: case \047--serve\047:` written on one line — a new
  # spelling with no row and no error, which is the hole this whole section exists to close. And
  # a double-quoted `case "doctor":` produced no group at all, so the arm vanished from both
  # sides of the comparison.
  rest = $0
  while (match(rest, /\047[^\047]*\047|"[^"]*"/)) {
    lab = substr(rest, RSTART + 1, RLENGTH - 2)
    group[gi] = (gi in group ? group[gi] " " : "") lab
    rest = substr(rest, RSTART + RLENGTH)
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
  detail "  alias. A verb with no row is CLI surface the gate does not count."
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
usage_verbs="$(sed -n 's/^[[:space:]]*mcp-router[[:space:]]\{1,\}\([a-z][a-z-]*\).*/\1/p' \
  "$INDEX_TS" | sort -u)"
while IFS= read -r verb; do
  [ -z "$verb" ] && continue
  printf '%s\n' "$cli_labels" | grep -qxF -e "$verb" \
    || note "usage() advertises \"$verb\" and no case label dispatches it"
done <<< "$usage_verbs"

# The independent signal, in the shape the control block uses above. The extractor reads exactly one
# idiom — the switch. A verb dispatched in a SECOND shape, `if (cmd === 'doctor')` above an intact
# switch, extracts nothing, demands no row, and leaves both directions of the comparison agreeing.
# The zero-guard cannot see it, because the switch still yields ten labels.
# Written as "account for every mention", not as one spelling. The first version grepped
# `cmd ===` with spaces, and stayed silent on `cmd==='doctor'`, `cmd !== 'help'`,
# `['doctor'].includes(cmd)` and `process.argv[2] === 'doctor'` — four ways to dispatch a verb
# that demands no row. Anything that reads `cmd` or argv[2] outside the two lines that legitimately
# do is named, because the extractor can only read the switch.
while IFS= read -r cmd_use; do
  [ -z "$cmd_use" ] && continue
  case "$cmd_use" in
    *"const cmd = process.argv[2]"*) continue ;;
    *"switch (cmd)"*)                continue ;;
    *"//"*)                          continue ;;
  esac
  note "src/index.ts reads the command outside the switch:"
  detail "  ${cmd_use}"
  detail "  A verb dispatched in a shape this check cannot read is absent from BOTH the source list"
  detail "  and the manifest, which reads as agreement and raises the coverage figure."
done <<< "$(grep -nE '(^|[^A-Za-z])cmd([^A-Za-z]|$)|argv\[2\]' "$INDEX_TS" || true)"

# ------------------------------------------------------------------ mcp surface
# The five `mcp` rows, reconciled against src/router.ts the same way, for the same reason.
mcp_literals="$(strip_comments "$ROUTER_TS" \
  | sed -n "s/.*url\.pathname === '\([^']*\)'.*/\1/p" | sort -u)"
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
#
# Anchored to a dispatch line rather than to the bare string, because `grep -q` of the call was
# kept green by any COMMENT that mentioned it — so the delegation could be deleted and described
# in the same edit.
grep -qE '^[[:space:]]*if \(isControlPath\(url\.pathname\)\)' "$ROUTER_TS" \
  || note "src/router.ts no longer dispatches on isControlPath — the 16 control rows describe a surface it does not reach"

# The same argument for the authorization server, whose rows are delegated the same way. Anchored
# to a dispatch line rather than the bare name, so the delegation cannot be deleted and described
# in the same edit.
grep -qE '^[[:space:]]*if \(isAuthServerPath\(url\.pathname\)\)' "$ROUTER_TS" \
  || note "src/router.ts no longer dispatches on isAuthServerPath — the authserver rows describe a surface it does not reach"

# R15's guard. It is not a route, so no row describes it as one; what the authserver-host-authority
# row asserts is that it runs AHEAD of the ladder. A guard that has been moved, renamed or deleted
# leaves that row describing a property the reference no longer has.
grep -qE '^[[:space:]]*if \(hostRefusal\(req, res, url\.pathname, allowedHosts\)\) return;' "$ROUTER_TS" \
  || note "src/router.ts no longer applies hostRefusal ahead of the dispatch ladder — every route inherited the authority check from it (R15)"

# The independent signal. Counting `url.pathname [!=]== ` lines and comparing them to what the
# same idiom extracted is not independent at all: `url.pathname==='/metrics'` without spaces,
# `url.pathname.startsWith('/admin')` and `['/a'].includes(url.pathname)` are each invisible to
# BOTH sides, which reads as agreement. So every line mentioning url.pathname at all must be one
# of the three shapes this check understands, and anything else is named.
while IFS= read -r pathname_use; do
  [ -z "$pathname_use" ] && continue
  # The recognised shapes are REMOVED and the residue is inspected, rather than the line being
  # waved through because it contains one of them. A line reading
  #     if (url.pathname === '/health' || url.pathname.startsWith('/admin')) {
  # contains an allowed substring and dispatches a second path the extractor cannot read; a
  # substring test lets it past, and both sides of the comparison then miss it.
  pathname_rest="$(printf '%s' "$pathname_use" \
    | sed -e "s/url\.pathname === '[^']*'//g" \
          -e 's/url\.pathname !== MCP_PATH//g' \
          -e 's/isControlPath(url\.pathname)//g' \
          -e 's/isAuthServerPath(url\.pathname)//g' \
          -e 's/hostRefusal(req, res, url\.pathname, allowedHosts)//g')"
  case "$pathname_rest" in
    *url.pathname*) ;;
    *) continue ;;
  esac
  note "src/router.ts uses url.pathname in a shape this check cannot read:"
  detail "  ${pathname_use}"
  detail "  A path answered in an unreadable shape is absent from both the source list and the"
  detail "  manifest, which reads as agreement and raises the coverage figure."
done <<< "$(grep -n 'url\.pathname' "$ROUTER_TS" || true)"

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

# The handlers get their own independent count, for the reason the control block gives for its
# dispatch-line count. The extractor reads `setRequestHandler(Symbol` on one line; a registration
# written across two lines —
#     server.setRequestHandler(
#       NewRequestSchema, …
# — yields no symbol, so a THIRD JSON-RPC method would be absent from both the source list and the
# manifest and the comparison would agree. The zero-guard above cannot see it, because the other
# two handlers still extract.
# Occurrences, not lines: `grep -c` counts a line once however many calls it carries, so two
# registrations on one line reported a count of 1 and matched a symbol count of 1.
handler_calls="$(grep -o 'setRequestHandler(' "$ROUTER_TS" | grep -c . || true)"
symbol_count="$(printf '%s\n' "$mcp_symbols" | grep -c . || true)"
if [ "$handler_calls" != "$symbol_count" ]; then
  note "src/router.ts registers $handler_calls request handler(s) but $symbol_count schema symbol(s)"
  detail "  could be read. A handler registered in a shape this check cannot read is a JSON-RPC"
  detail "  method with no manifest row."
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

# ------------------------------------------------------------------ authserver routes
# The same argument as the control block, for the group R14 added. The paths are declared once in
# src/oauth.ts as exported constants and read out of there, so a route added to that file with no
# row here is a red rather than a quietly smaller denominator.
OAUTH_TS="$REPO_ROOT/src/oauth.ts"
if [ ! -f "$OAUTH_TS" ]; then
  echo "environment: no authorization server at $OAUTH_TS, and the manifest carries authserver rows"
  exit 2
fi

# `export const NAME = '/path';` — the one shape those constants take.
authserver_paths="$(sed -n "s/^export const [A-Z_]* = '\(\/[a-zA-Z0-9_.\/-]*\)';.*/\1/p" "$OAUTH_TS" | sort -u)"
if [ -z "$authserver_paths" ]; then
  echo "environment: extracted no paths from $OAUTH_TS — the declaration shape has changed and this"
  echo "             check would otherwise report a clean manifest against nothing."
  exit 2
fi

# The independent count, in the shape the control and cli blocks use. `isAuthServerPath` decides
# ownership, so every path it tests must be one of the constants above: a literal compared inline
# there is a route with no constant, no demanded row, and no presence on either side of the
# comparison.
inline_paths="$(sed -n "/export function isAuthServerPath/,/^}/p" "$OAUTH_TS" \
  | grep -oE "pathname (===|\.startsWith\()[^)]*'[^']*'" | grep -oE "'[^']*'" | tr -d "'" || true)"
for inline in $inline_paths; do
  case "$inline" in
    /*) note "isAuthServerPath compares the literal \"$inline\" rather than a declared constant."
        detail "  A path with no constant demands no manifest row and is invisible to both sides." ;;
  esac
done

# Row subjects carry an HTTP verb ("POST /register"); the two non-route rows (instructions, the
# dispatcher check) carry no leading slash and are excluded from this reconciliation by that.
authserver_rows="$(awk -F'\t' '$1 == "authserver" { print $3 }' "$MANIFEST" \
  | awk '{ print $NF }' | grep '^/' | sort -u)"

while IFS= read -r route; do
  [ -z "$route" ] && continue
  printf '%s\n' "$authserver_rows" | grep -qxF "$route" \
    || note "src/oauth.ts declares \"$route\" and the manifest has no authserver row for it"
done <<< "$authserver_paths"

while IFS= read -r route; do
  [ -z "$route" ] && continue
  printf '%s\n' "$authserver_paths" | grep -qxF "$route" \
    || note "the manifest carries authserver row \"$route\", which src/oauth.ts does not declare"
done <<< "$authserver_rows"

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
# Words that match the id SHAPE without being ids. `mcp-router` is the project. `install-entry` is
# a CLI verb P2 added, and it is deliberately not a row: the capability it implements is
# install-claude-json, which has a row and is proven by a lane that drives this very verb. A second
# row for the verb would count one capability twice and inflate the denominator.
KNOWN_NON_IDS='mcp-router
install-entry'
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
  detail "  Either the row it names was deleted, or the word is not an id and belongs in KNOWN_NON_IDS."
done <<< "$cited_ids"

# ------------------------------------------------------------------ every lane is dispatched
#
# P4's orphan detection catches a ROW no lane speaks for. This is the inverse — a LANE SCRIPT that
# nothing dispatches — and nothing caught it.
#
# `parity-stream.sh` sat on disk from R2-R until P3: written, executable, and passing when run by
# hand, while being run by NOTHING, because `stream` was never in `parity-gate.sh`'s LANES list.
# Its rows stayed blocked under their own notes for the whole of that time. The gate's
# missing-script guard cannot reach this: it only fires for a lane the gate was ASKED about, so a
# lane it was never asked about produces no result, no environment failure and no complaint.
#
# A lane script that exists and is dispatched by nothing is worse than an absent one, because it
# reads as covered work. So every `parity-*.sh` must either appear in LANES or be named below with
# the reason it is not a lane.
GATE_SH="$REPO_ROOT/scripts/acceptance/parity-gate.sh"
[ -f "$GATE_SH" ] || { echo "environment: no gate at $GATE_SH"; exit 2; }

# Read the dispatch list out of the gate rather than keeping a second copy of it here. A copy is
# free to drift, and a drifted copy would agree with the wrong answer — which is the failure this
# whole file exists to prevent.
lanes_dispatched="$(sed -n 's/^LANES="\${PARITY_LANES:-\(.*\)}".*/\1/p' "$GATE_SH" | head -1)"
if [ -z "$lanes_dispatched" ]; then
  echo "environment: could not read the LANES list out of $GATE_SH — the declaration has changed"
  echo "             shape, and this check would otherwise pass every script by finding no lanes."
  exit 2
fi

# Scripts under scripts/acceptance/ named parity-*.sh that are deliberately NOT lanes. Each needs a
# reason, so that adding one is a decision a reviewer can see rather than a way to silence this.
NOT_LANES="parity-gate:the dispatcher itself, which runs the lanes
parity-manifest-check:this file, which parity-gate runs before any lane
parity-manifest-selftest:proves this file can fail; run by 'make parity-selftest'
parity-lane-selftest:proves a lane can fail; run by 'make parity-selftest'
parity-normalise-selftest:proves the normaliser can fail; run by 'make parity-selftest'
parity-regen-selftest:proves vector divergence is caught; run by 'make parity-selftest'
parity-lock:the harness lock (D-g1-g); sourced by parity-gate.sh and four other entry points
parity-lock-selftest:proves the lock can refuse; run by 'make parity-selftest'
parity-install-watch:the watch half of the install lane; sourced by parity-install.sh and by parity-install-watch-mutations.sh, so one copy of the observation serves both
parity-install-watch-mutations:proves the watch agent's two terms can go red; run by 'make parity-watch-mutations'"

for script in "$REPO_ROOT"/scripts/acceptance/parity-*.sh; do
  [ -f "$script" ] || continue
  base="$(basename "$script" .sh)"
  lane="${base#parity-}"
  printf '%s\n' $lanes_dispatched | grep -qxF -e "$lane" && continue
  printf '%s\n' "$NOT_LANES" | grep -q "^$base:" && continue
  note "$base.sh exists and no lane dispatches it: \"$lane\" is not in parity-gate.sh's LANES,"
  detail "  and it is not declared as deliberately unwired. A lane script nothing runs passes by"
  detail "  hand forever while its rows stay blocked — which is exactly what parity-stream.sh did"
  detail "  from R2-R until P3. Add it to LANES, or name it in NOT_LANES with the reason."
done

# An exemption naming a script that no longer exists is its own kind of rot: it would keep a future
# script of the same name invisible.
#
# And an exemption is not a waiver. If NOT_LANES only had to NAME a script, it would become the very
# drain this section exists to close — parity-stream.sh with paperwork, executable and passing by
# hand and run by nothing. So each exempted script must be REFERENCED somewhere that runs it: the
# Makefile, or the gate itself. "Not a lane" has to mean "run another way", never "not run".
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  name="${entry%%:*}"
  if [ ! -f "$REPO_ROOT/scripts/acceptance/$name.sh" ]; then
    note "NOT_LANES exempts \"$name\", and no such script exists — remove the stale exemption"
    continue
  fi
  # The referenced-check needs a Makefile to read. `parity-manifest-selftest.sh` builds a MINIMAL
  # scratch REPO_ROOT — a manifest, the reference sources and this script, and no Makefile — so
  # asserting referencedness there would fail on every case and take the selftest's unmutated
  # baseline red with it, which makes every red below the baseline prove nothing. Measured: it
  # reported 3 spurious problems and the selftest said "the unmutated tree exits 1".
  #
  # Where there is no Makefile there is no wiring to have an opinion about, so this sub-check is
  # skipped rather than failed. The LANES membership check above still runs in that tree.
  [ -f "$REPO_ROOT/Makefile" ] || continue
  # A third way to be run: SOURCED BY A DISPATCHED LANE. `parity-install-watch.sh` holds the watch
  # half of the install lane so that the lane and its mutation harness share one copy of the
  # observation, and a file the install lane sources runs every time the install lane runs.
  #
  # The reference has to be the `. "$REPO_ROOT/scripts/acceptance/<name>.sh"` path, and it is only
  # looked for in scripts the gate actually DISPATCHES — never in another exempt script, which is
  # what would let two unrun files vouch for each other. A mention in prose does not match.
  sourced_by_lane=""
  for dispatched in $lanes_dispatched; do
    lane_script="$REPO_ROOT/scripts/acceptance/parity-$dispatched.sh"
    [ -f "$lane_script" ] || continue
    grep -q "scripts/acceptance/$name\.sh" "$lane_script" && { sourced_by_lane="$dispatched"; break; }
  done
  [ -n "$sourced_by_lane" ] && continue
  # `$name.sh`, not `$name`. Unanchored, one script's name is a PREFIX of another's, so
  # `parity-install-watch-mutations.sh` in the Makefile silently vouched for `parity-install-watch`
  # — an exemption satisfied by a script that is not the exempted one.
  if ! grep -q "$name\.sh" "$REPO_ROOT/Makefile" && ! grep -q "$name\.sh" "$GATE_SH"; then
    note "NOT_LANES exempts \"$name\" as not-a-lane, and nothing runs it: it appears in neither the"
    detail "  Makefile nor parity-gate.sh. An exemption has to mean \"run another way\", not \"not"
    detail "  run\" — otherwise this list is just a waiver for the invisible-script defect it exists"
    detail "  to catch. Being sourced by a dispatched lane counts; being mentioned does not."
  fi
done <<< "$NOT_LANES"

# ------------------------------------------------------------------ ids are unique
# Two rows sharing an id means one lane's result overwrites the other's during reconciliation,
# and a row silently inherits a verdict it never earned.
dupes="$(awk -F'\t' '!/^#/ && NF == 6 { print $2 }' "$MANIFEST" | sort | uniq -d)"
if [ -n "$dupes" ]; then
  while IFS= read -r id; do note "duplicate row id \"$id\""; done <<< "$dupes"
fi

total="$(awk -F'\t' '!/^#/ && NF == 6' "$MANIFEST" | wc -l | tr -d ' ')"

# ------------------------------------------------------------------ the census is pinned
# The reconciliations above derive four groups from source. `divergence`, `install`, `pool`,
# `state` and `log` name declarations and scenarios rather than a surface some file exposes, so
# they cannot be derived — and a BLOCKED row in one of them can be deleted with every check here
# still green. That deletion leaves the numerator untouched and shrinks the denominator, so the
# reported coverage GOES UP. Four rows were in that position: div-r1-d3 and the three install
# rows.
#
# `parity-gate.sh` catches any row a LANE speaks for, by noticing a result with no row. It cannot
# reach a blocked row, because no lane speaks for one.
#
# So the size of the census is pinned, here, next to the census. This is a hand-maintained number
# and that is the point: the denominator is what the cutover target is DERIVED from, so moving it
# should be a deliberate line in a diff rather than a side effect. Adding a row is as gated as
# deleting one — a duplicate blocked twin sharing an existing subject satisfies every derivation
# above and would otherwise inflate the total unnoticed.
#
# The denominator is no longer the target ITSELF. It was, while the gate's footer read "requires
# $total of $total". The owner set the target to 82 of 83 on 2026-08-16 (bec9d18) because
# `fixture-registry-search` is a standing exclusion, so the target is now the census MINUS the
# standing exclusions, pinned separately in `parity-gate.sh` as PARITY_CUTOVER_TARGET. Moving this
# pin without moving that one makes the two disagree, and the gate prints that disagreement rather
# than re-deriving a target for itself.
pinned="$(sed -n 's/^# rows: \([0-9][0-9]*\).*/\1/p' "$MANIFEST" | head -1)"
if [ -z "$pinned" ]; then
  note "the manifest carries no \`# rows: N\` pin, so its size is unconstrained and a row can"
  detail "  leave it without anything noticing."
elif [ "$pinned" != "$total" ]; then
  note "the manifest holds $total rows and pins itself at $pinned."
  detail "  A row was added or removed. If that was deliberate, move the pin in the same change and"
  detail "  say so — and check PARITY_CUTOVER_TARGET in parity-gate.sh in the SAME change, because"
  detail "  the cutover target is derived from this denominator and is pinned separately."
fi

if [ "$problems" -gt 0 ]; then
  echo
  echo "manifest-check: $problems problem(s). The coverage fraction is computed from this file,"
  echo "                so a stale manifest reports a higher pass rate than the port has earned."
  exit 1
fi
echo "manifest-check: $total rows, consistent with control.ts, index.ts, router.ts and the fixture"
echo "                directory; every cited test, script and row id resolves."
