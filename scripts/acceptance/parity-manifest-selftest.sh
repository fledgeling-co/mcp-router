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
  'compares `cmd` outside the switch'

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
echo "───────────────────────────────────────────────────────────────────────"
echo "manifest selftest: $pass behaved, $fail did not"
if [ "$fail" -gt 0 ]; then
  echo
  echo "A case that stays green is a mutation the manifest check cannot see, which means the"
  echo "coverage fraction can be moved without the gate noticing. That is the finding."
  exit 1
fi
exit 0
