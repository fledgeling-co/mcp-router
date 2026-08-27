#!/usr/bin/env bash
#
# P4 — does `parity-manifest-check.sh` actually go red?
#
# The manifest is the census the whole gate reports against, so a check that reconciles it against
# the source is only worth what its ability to FAIL is worth. Written carefully is not evidence, and
# this file exists for the reason `parity-lane-selftest.sh` gives for its own existence: a paragraph
# in an evidence file is re-run by nothing.
#
# The case that matters most is deletion. A blocked row deleted from the manifest leaves the
# numerator alone and shrinks the denominator, so the reported coverage GOES UP — the gate's own
# worst failure mode, and the reason `cli`, `mcp` and cross-cited row ids are now reconciled
# against source instead of maintained by hand.
#
# Every case asserts the exit code AND the message. A mutation that reddens through some other
# check proves nothing about the one it was aimed at, and exit-code-only assertions are how that
# goes unnoticed.
#
# Nothing here mutates the real tree. Each case gets a fresh scratch repo — copied src, manifest and
# scripts, with app/ and node_modules symlinked because no case touches them — so a case that dies
# half way cannot leave a mutated source file behind.
#
# Exit codes: 0 every case behaved, 1 a case did not (which is the finding), 2 the environment
# could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d -t parity-manifest-selftest)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

command -v node    >/dev/null 2>&1 || { echo "environment: node is not installed"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "environment: python3 is not installed"; exit 2; }
[ -d "$REPO_ROOT/node_modules/@modelcontextprotocol/sdk" ] || {
  echo "environment: the MCP SDK is not installed. Run npm install."
  echo "             The mcp method names are read from it, so this check cannot run without it."
  exit 2; }

pass=0; fail=0

# A fresh scratch repo. `src`, `planning` and `scripts` are copied because cases mutate them;
# `app` and `node_modules` are symlinked because no case does.
#
# `mktemp -d`, not a counter: this runs inside `$(scratch)`, which is a SUBSHELL, so an incremented
# variable never reaches the caller. The first draft used a counter and every case therefore reused
# one directory and inherited the previous case's mutation — fifteen cases reported red against a
# cumulatively broken tree. It was caught only because each case asserts the MESSAGE and not just
# the exit code, which is the argument for asserting messages.
scratch() {
  local dir
  dir="$(mktemp -d "$WORK/caseXXXXXX")"
  cp -R "$REPO_ROOT/src"      "$dir/src"
  cp -R "$REPO_ROOT/planning" "$dir/planning"
  cp -R "$REPO_ROOT/scripts"  "$dir/scripts"
  ln -s "$REPO_ROOT/app"          "$dir/app"
  ln -s "$REPO_ROOT/node_modules" "$dir/node_modules"
  printf '%s' "$dir"
}

# edit <file> <python-old> <python-new> — literal replacement, asserted to have happened. A
# mutation that silently fails to apply reports the unmutated tree as green, which is the same
# false pass this whole file is about.
edit() {
  python3 - "$1" "$2" "$3" <<'PY' || { echo "  the mutation did not apply — the anchor text was not found"; return 1; }
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
if old not in text:
    sys.exit(1)
open(path, 'w').write(text.replace(old, new, 1))
PY
}

# delete_row <tsv> <row id> — read fully, then write. `open(p,'w').writelines([... open(p) ...])`
# truncates before the comprehension runs, which empties the file and reddens every check at once;
# the assertion below makes that impossible to ship unnoticed.
delete_row() {
  python3 - "$1" "$2" <<'PY'
import sys
path, rid = sys.argv[1], sys.argv[2]
lines = open(path).readlines()
kept = [l for l in lines if l.split('\t')[1:2] != [rid]]
if len(kept) != len(lines) - 1:
    sys.exit(f'expected to drop exactly one row, dropped {len(lines) - len(kept)}')
with open(path, 'w') as handle:
    handle.writelines(kept)
PY
}

# check <dir> — run the copy of the check inside a scratch repo, capture status unpiped.
check() {
  bash "$1/scripts/acceptance/parity-manifest-check.sh" > "$WORK/out.txt" 2>&1
  echo $?
}

# expect_red <label> <dir> <substring>
expect_red() {
  local label="$1" dir="$2" want="$3" status
  status="$(check "$dir")"
  if [ "$status" = 0 ]; then
    fail=$((fail + 1))
    printf '  STAYED GREEN  %s\n' "$label"
    printf '                the mutation was applied and the check exited 0\n'
    return
  fi
  if ! grep -qF "$want" "$WORK/out.txt"; then
    fail=$((fail + 1))
    printf '  WRONG REASON  %s (exit %s)\n' "$label" "$status"
    printf '                wanted a message containing: %s\n' "$want"
    printf '                got: %s\n' "$(grep -m2 '^  ' "$WORK/out.txt" | tr '\n' ' ')"
    return
  fi
  pass=$((pass + 1))
  printf '  red   %-62s exit %s\n' "$label" "$status"
}

# expect_red_any <label> <dir> <substring> <substring> — red for EITHER of two reasons.
#
# Used where more than one guard legitimately catches the same mutation and which one fires first
# is not the property under test. It is deliberately not the default: a case that will accept any
# red is a case that cannot tell the right failure from a coincidental one.
expect_red_any() {
  local label="$1" dir="$2" first="$3" second="$4" status
  status="$(check "$dir")"
  if [ "$status" = 0 ]; then
    fail=$((fail + 1))
    printf '  STAYED GREEN  %s\n' "$label"
    printf '                the mutation was applied and the check exited 0\n'
    return
  fi
  if ! grep -qF "$first" "$WORK/out.txt" && ! grep -qF "$second" "$WORK/out.txt"; then
    fail=$((fail + 1))
    printf '  WRONG REASON  %s (exit %s)\n' "$label" "$status"
    printf '                wanted either: %s | %s\n' "$first" "$second"
    printf '                got: %s\n' "$(grep -m2 '^  ' "$WORK/out.txt" | tr '\n' ' ')"
    return
  fi
  pass=$((pass + 1))
  printf '  red   %-62s exit %s\n' "$label" "$status"
}

# expect_green <label> <dir> — the check must PASS on this tree.
#
# Every other case here asks whether a guard can fire. This one asks whether it can stay quiet, and
# it exists because the failure P10 repaired was of that kind: `# rows: N` went red on a manifest
# that was CORRECT, and a guard that reddens on correct trees is a guard whose reds stop being
# read. A ratchet plus an addition case is the only shape with both properties, so both are armed.
expect_green() {
  local label="$1" dir="$2" status
  status="$(check "$dir")"
  if [ "$status" != 0 ]; then
    fail=$((fail + 1))
    printf '  WENT RED      %s (exit %s)\n' "$label" "$status"
    sed 's/^/                /' "$WORK/out.txt"
    return
  fi
  pass=$((pass + 1))
  printf '  green %-62s exit 0\n' "$label"
}

echo "parity-manifest-selftest — can the manifest check fail?"
echo

# ---------------------------------------------------------------------------------------- green
# The unmutated tree must pass, or every red below is meaningless.
dir="$(scratch)"
status="$(check "$dir")"
if [ "$status" = 0 ]; then
  pass=$((pass + 1))
  printf '  green %-62s exit 0\n' "the unmutated tree"
else
  fail=$((fail + 1))
  printf '  NOT GREEN     the unmutated tree exits %s — every red below proves nothing\n' "$status"
  sed 's/^/                /' "$WORK/out.txt"
fi
echo

# ------------------------------------------------------------------------------------ cli rows
echo "cli — the ten verbs, against src/index.ts"

dir="$(scratch)"
python3 - "$dir/planning/parity/surface.tsv" <<'PY'
import sys
path = sys.argv[1]
lines = [l for l in open(path) if not l.startswith('cli\tcli-import\t')]
open(path, 'w').writelines(lines)
PY
expect_red "a cli row DELETED (import)" "$dir" \
  'src/index.ts dispatches "import"'

# D-n's headline is a BLOCKED row disappearing: the numerator is untouched and the denominator
# shrinks, so 73/83 becomes 73/82 and the reported coverage goes UP. cli-auth is the blocked one.
dir="$(scratch)"
python3 - "$dir/planning/parity/surface.tsv" <<'PY'
import sys
path = sys.argv[1]
lines = [l for l in open(path) if not l.startswith('cli\tcli-auth\t')]
open(path, 'w').writelines(lines)
PY
expect_red "the BLOCKED cli row deleted (auth) — pure denominator" "$dir" \
  'src/index.ts dispatches "auth"'

dir="$(scratch)"
printf 'cli\tcli-doctor\tdoctor\tproven\t-\tinvented\n' >> "$dir/planning/parity/surface.tsv"
expect_red "a cli row INVENTED (doctor)" "$dir" \
  'the manifest carries cli row "doctor", which src/index.ts does not dispatch'

dir="$(scratch)"
edit "$dir/src/index.ts" "case 'tools':" "case 'toolz':" || true
expect_red "a verb RENAMED in source (tools -> toolz)" "$dir" \
  'src/index.ts dispatches "toolz"'

dir="$(scratch)"
edit "$dir/src/index.ts" "    case 'serve':" "    case '--serve':
    case 'serve':" || true
expect_red "a new FLAG SPELLING added (--serve)" "$dir" \
  'src/index.ts dispatches "--serve"'

# The alias-only group must redden for the RIGHT rule. Adding two UNDECLARED labels trips the
# "neither a row nor a declared alias" rule first, which proves that rule and says nothing about
# this one. So they are declared here, exactly as a maintainer would declare them, and the group
# is then the only thing wrong with the tree.
dir="$(scratch)"
edit "$dir/scripts/acceptance/parity-manifest-check.sh" "CLI_ALIASES='--help
-h'" "CLI_ALIASES='--help
-h
-q
-z'" || true
edit "$dir/src/index.ts" "    case 'help':" "    case '-q':
    case '-z':
      return usage();
    case 'help':" || true
expect_red "an ALIAS-ONLY case group, aliases properly DECLARED" "$dir" \
  'has no label carrying a cli manifest row'

dir="$(scratch)"
edit "$dir/src/index.ts" "    case '-h':
" "" || true
expect_red "a DECLARED ALIAS removed from source (-h)" "$dir" \
  'declared cli alias "-h" is not a case label'

dir="$(scratch)"
edit "$dir/src/index.ts" "  mcp-router status" "  mcp-router doctor" || true
expect_red "usage() advertises a verb nothing dispatches" "$dir" \
  'usage() advertises "doctor"'

# Column-aligned help. The first sed took exactly one space, so a verb in a tab- or double-space
# aligned help line was not extracted at all and A3 stayed green over an advertised lie.
dir="$(scratch)"
edit "$dir/src/index.ts" "  mcp-router status" "  mcp-router	doctor" || true
expect_red "usage() advertises a verb, TAB-aligned" "$dir" \
  'usage() advertises "doctor"'

# Two labels on one line. Reading only the first quoted string dropped the second entirely.
dir="$(scratch)"
edit "$dir/src/index.ts" "    case 'serve':" "    case 'serve': case '--serve':" || true
expect_red "a second label on the SAME line (--serve)" "$dir" \
  'src/index.ts dispatches "--serve"'

# A double-quoted arm produced no group at all, so the whole verb vanished from both sides.
dir="$(scratch)"
edit "$dir/src/index.ts" "    case 'status':" "    case \"doctor\":
      return cmdStatus();
    case 'status':" || true
expect_red "a DOUBLE-QUOTED case arm" "$dir" \
  'src/index.ts dispatches "doctor"'

dir="$(scratch)"
edit "$dir/src/index.ts" "const run = async ()" "if (cmd === 'doctor') { void cmdIndex(); }
const run = async ()" || true
expect_red "a verb dispatched OUTSIDE the switch, switch intact" "$dir" \
  'reads the command outside the switch'

echo

# ------------------------------------------------------------------------------------ mcp rows
echo "mcp — three paths and two JSON-RPC methods, against src/router.ts"

dir="$(scratch)"
python3 - "$dir/planning/parity/surface.tsv" <<'PY'
import sys
path = sys.argv[1]
lines = [l for l in open(path) if not l.startswith('mcp\tmcp-health\t')]
open(path, 'w').writelines(lines)
PY
expect_red "an mcp row DELETED (GET /health)" "$dir" \
  'src/router.ts answers "/health" and the manifest has no mcp row for it'

dir="$(scratch)"
printf 'mcp\tmcp-metrics\tGET /metrics\tproven\t-\tinvented\n' >> "$dir/planning/parity/surface.tsv"
expect_red "an mcp row INVENTED (GET /metrics)" "$dir" \
  'the manifest carries mcp row "/metrics", which src/router.ts does not answer'

dir="$(scratch)"
edit "$dir/src/router.ts" "server.setRequestHandler(ListToolsRequestSchema" \
                          "server.registerListHandler(ListToolsRequestSchema" || true
expect_red "a JSON-RPC handler REMOVED (tools/list)" "$dir" \
  'the manifest carries mcp row "tools/list", which src/router.ts does not answer'

dir="$(scratch)"
edit "$dir/src/router.ts" "if (isControlPath(url.pathname)) {" "if (isControlPathDisabled(url.pathname)) {" || true
expect_red "the control delegation REMOVED" "$dir" \
  'no longer dispatches on isControlPath'

# ... and removed while a comment still names it. A bare `grep -q` of the string stayed green here,
# so the delegation could be deleted and described in the same edit.
dir="$(scratch)"
edit "$dir/src/router.ts" "      if (isControlPath(url.pathname)) {" \
  "      // isControlPath(url.pathname) used to run here
      if (false) {" || true
expect_red "the delegation removed but NAMED IN A COMMENT" "$dir" \
  'no longer dispatches on isControlPath'

# A path answered in a shape the extractor cannot read. The first count shared the extractor's own
# idiom, so both sides missed this and the manifest agreed with a source it had stopped reading.
dir="$(scratch)"
edit "$dir/src/router.ts" "      if (url.pathname === '/health') {" \
  "      if (url.pathname.startsWith('/metrics')) { return json(res, 200, {}); }
      if (url.pathname === '/health') {" || true
expect_red "a path matched with .startsWith, unreadable by the extractor" "$dir" \
  'uses url.pathname in a shape this check cannot read'

# A third JSON-RPC handler registered across two lines: no symbol extracted, no row demanded, and
# the zero-guard silent because the other two still extract.
dir="$(scratch)"
edit "$dir/src/router.ts" "  server.setRequestHandler(ListToolsRequestSchema" \
  "  server.setRequestHandler(
    PingRequestSchema, async () => ({}));
  server.setRequestHandler(ListToolsRequestSchema" || true
expect_red "a handler registered ACROSS TWO LINES" "$dir" \
  'schema symbol(s)'

# The method names are read out of the installed SDK rather than a table in the check. Proven by
# giving one scratch repo its own SDK whose schema pins a DIFFERENT literal: if the check followed a
# hand-written table it would keep reporting `tools/list` and stay green.
dir="$(scratch)"
rm "$dir/node_modules"
mkdir -p "$dir/node_modules/@modelcontextprotocol/sdk"
cat > "$dir/node_modules/@modelcontextprotocol/sdk/package.json" <<'JSON'
{ "name": "@modelcontextprotocol/sdk", "version": "0.0.0-selftest" }
JSON
cat > "$dir/node_modules/@modelcontextprotocol/sdk/types.js" <<'JS'
module.exports = {
  ListToolsRequestSchema: { shape: { method: { value: 'tools/listv2' } } },
  CallToolRequestSchema:  { shape: { method: { value: 'tools/call'   } } },
};
JS
expect_red "the SDK renames a method (tools/list -> tools/listv2)" "$dir" \
  'src/router.ts answers "tools/listv2" and the manifest has no mcp row for it'

echo

# ------------------------------------------------------------------------------- cited row ids
echo "cited row ids — the deletion the source reconciliations cannot see"

# control-auth-post and control-auth-post-http share a subject deliberately, so deleting the
# blocked one leaves the subject carried by its sibling and every source reconciliation satisfied.
# Only the citation in the surviving row's note notices.
dir="$(scratch)"
python3 - "$dir/planning/parity/surface.tsv" <<'PY'
import sys
path = sys.argv[1]
lines = [l for l in open(path) if not l.startswith('control\tcontrol-auth-post-http\t')]
open(path, 'w').writelines(lines)
PY
expect_red "a BLOCKED row deleted whose subject a sibling still carries" "$dir" \
  'a note cites "control-auth-post-http", which is not a row id in this manifest'

dir="$(scratch)"
python3 - "$dir/planning/parity/surface.tsv" <<'PY'
import sys
path = sys.argv[1]
lines = [l for l in open(path) if not l.startswith('divergence\tdiv-r1-d3-control\t')]
open(path, 'w').writelines(lines)
PY
expect_red "a cited divergence row deleted (div-r1-d3-control)" "$dir" \
  'a note cites "div-r1-d3-control", which is not a row id in this manifest'

echo

# ----------------------------------------------------------------------------- the derived census
# The four groups above are derived from a source file, and parity-gate.sh notices any row a LANE
# speaks for. Neither reaches a BLOCKED row in `divergence`, `install`, `pool`, `state` or `log`:
# no lane speaks for it, and no file exposes it. Four rows were in exactly that position, and
# deleting one moved 74/83 to 74/82 with every other check green — the coverage figure going UP,
# which is the whole of D-n.
#
# These cases were aimed at `# rows: N` — an equality between the census and a number a person
# retyped. P10 replaced that with `surface-census.sh`, which derives the count, and
# `SURFACE_ROW_FLOOR`, which is a ratchet. So the cases are re-aimed rather than retired, and there
# are more of them than there were: the four deletions and the twin still have to go red, an
# addition now has to stay GREEN, and the oracle the count comes from has to be unable to fail
# silently.
echo "the derived census — the deletion neither derivation nor the lanes can see"

# The wanted substring is the check's REASON, not its arithmetic.
#
# These four read `holds 82 rows and pins itself at 83` until M22, and all four had been reporting
# WRONG REASON since the census outgrew 83 — the check was going red, with the correct finding, and
# the selftest was comparing it against a sentence from an earlier size. A selftest that fails
# whenever a row is legitimately added is a selftest that gets read as noise, which is how the one
# case that matters would go unnoticed.
#
# `div-r1-d3` additionally trips the citation check first, because `div-r1-d3-control`'s note names
# it — a stronger guard than the floor, and one that fires for a better reason. So each row is
# accepted on EITHER finding rather than on one spelling of one of them: what this case asserts is
# that deleting a blocked row cannot pass, not which of the two guards catches it.
for row in div-r1-d3 install-claude-json install-import-servers install-rollback; do
  dir="$(scratch)"
  delete_row "$dir/planning/parity/surface.tsv" "$row" || true
  expect_red_any "a blocked row deleted: $row" "$dir" \
    'against a floor of' 'which is not a row id in this manifest'
done

# A duplicate blocked twin sharing an existing subject satisfies every derivation above, because
# those reconcile SUBJECTS and reduce the manifest side with `sort -u`. It used to be caught only by
# the `# rows: N` equality — this case wanted that equality's own message — so removing the pin
# without putting something in its place would have retired a guard rather than replaced it. What
# catches it now is the one-row-per-source-subject rule, which names the claimants.
dir="$(scratch)"
printf 'cli\tcli-auth-2\tauth\tblocked\tD-x\ta twin sharing an existing subject\n' \
  >> "$dir/planning/parity/surface.tsv"
expect_red "a duplicate blocked twin ADDED" "$dir" \
  'is claimed by more than one manifest row'

# The deliberately shared subject must still pass, or that rule is a rule against the manifest this
# repository actually ships. `control-auth-post` and `control-auth-post-http` are the two halves of
# POST /servers/:name/auth and are declared in SHARED_SUBJECTS; this case is what would notice the
# declaration being dropped.
dir="$(scratch)"
expect_green "the DECLARED shared subject (POST /servers/:name/auth) passes" "$dir"

# An ordinary row addition must stay green with NOTHING else edited. This is the case the pin could
# not pass: `ebe3165` added rows and set the pin to 95 against a file that held 97, and every run
# from `b1160ef` onward reported a correct manifest as broken.
dir="$(scratch)"
printf 'pool\tpool-selftest-probe\ta row added with nothing else touched\tblocked\tD-x\tproves the census follows the file\n' \
  >> "$dir/planning/parity/surface.tsv"
expect_green "a row ADDED, and no second number to move" "$dir"

# The census the floor is compared against comes from an oracle, so an oracle that fails silently is
# how this whole block goes quiet. Both halves are armed: a census that yields nothing, and the
# oracle missing altogether. Neither may read as a clean manifest.
dir="$(scratch)"
python3 - "$dir/planning/parity/surface.tsv" <<'PY'
import sys
path = sys.argv[1]
lines = [l for l in open(path).readlines() if l.startswith('#')]
with open(path, 'w') as handle:
    handle.writelines(lines)
PY
expect_red "the census EMPTIED — an empty surface is a broken oracle" "$dir" \
  'yielded no rows'

dir="$(scratch)"
rm -f "$dir/scripts/acceptance/surface-census.sh"
expect_red "the census oracle REMOVED" "$dir" \
  'this check has no denominator'

echo

# --------------------------------------------------------------------- dispatch shapes, revisited
# Every one of these left the check green while adding CLI or HTTP surface the gate never counts.
# They are here because an extractor that returns the WRONG list is invisible to a zero-guard: the
# switch still yields ten labels, so nothing looks broken.
echo "dispatch shapes that used to be silent"

dir="$(scratch)"
edit "$dir/src/index.ts" "const run = async ()" "if (cmd==='doctor') { void cmdIndex(); }
const run = async ()" || true
expect_red "cmd==='doctor', no spaces around ===" "$dir" \
  'reads the command outside the switch'

dir="$(scratch)"
edit "$dir/src/index.ts" "const run = async ()" "if (process.argv[2] === 'doctor') { void cmdIndex(); }
const run = async ()" || true
expect_red "dispatch on process.argv[2], never naming cmd" "$dir" \
  'reads the command outside the switch'

dir="$(scratch)"
edit "$dir/src/index.ts" "const run = async ()" "if (['doctor'].includes(cmd)) { void cmdIndex(); }
const run = async ()" || true
expect_red "dispatch through Array.includes(cmd)" "$dir" \
  'reads the command outside the switch'

dir="$(scratch)"
edit "$dir/src/index.ts" "const run = async ()" "if (cmd !== 'help') { void cmdIndex(); }
const run = async ()" || true
expect_red "dispatch on cmd !== , not ===" "$dir" \
  'reads the command outside the switch'

# A second path on the same line as a recognised one. A substring test waves the whole line
# through; only removing the shapes it understands and looking at the RESIDUE catches it.
dir="$(scratch)"
edit "$dir/src/router.ts" "if (url.pathname === '/health') {" \
  "if (url.pathname === '/health' || url.pathname.startsWith('/admin')) {" || true
expect_red "a second path beside a recognised one, same line" "$dir" \
  'uses url.pathname in a shape this check cannot read'

# The real compare commented out. The literal extractor read the comment and kept demanding the
# row, so the row stayed satisfied by a route the router no longer answered.
dir="$(scratch)"
edit "$dir/src/router.ts" "      if (url.pathname === '/health') {" \
  "      // if (url.pathname === '/health')
      if (false) {" || true
expect_red "the /health compare COMMENTED OUT" "$dir" \
  'the manifest carries mcp row "/health", which src/router.ts does not answer'

# Two registrations on one line. `grep -c` counts the line once, so the handler count matched the
# symbol count and the second method demanded no row.
dir="$(scratch)"
edit "$dir/src/router.ts" "  server.setRequestHandler(ListToolsRequestSchema" \
  "  server.setRequestHandler( PingRequestSchema, async () => ({})); server.setRequestHandler(ListToolsRequestSchema" || true
expect_red "a registration whose symbol the regex cannot read" "$dir" \
  'schema symbol(s)'

echo
echo "───────────────────────────────────────────────────────────────────────"
echo "manifest selftest: $pass behaved, $fail did not"
if [ "$fail" -gt 0 ]; then
  echo
  echo "A case that stays green is a mutation the manifest check cannot see, which means the"
  echo "coverage fraction can be moved without the gate noticing. That is the finding."
  exit 1
fi
exit 0
