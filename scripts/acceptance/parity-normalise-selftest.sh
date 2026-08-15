#!/usr/bin/env bash
#
# P4 — does the fixture lane's normaliser normalise the right things, and only those?
#
# `parity-fixture.sh` compares a recorded body against a freshly captured one, and both go through
# one normalisation pass first. Everything that pass removes is a fact about the RUN rather than
# about the wire contract, so every rule in it trades two failure modes against each other:
#
#   under-normalise -> a false DIVERGED. Noisy, and someone eventually looks.
#   over-normalise  -> a real difference between the routers disappears. Silent, and nobody does.
#
# The second is much worse for a parity harness, and it is the one a test can be written for. This
# file writes it.
#
# The rule under the most tension is `project`. It used to be matched by shape —
# "project":"[A-Za-z0-9]+" — a class with no hyphen, so a call attributed to a directory named
# `mcp-router` did not normalise while one attributed to `F3` did. Project attribution is
# basename(cwd) (src/usage.ts:305), so THE GATE'S VERDICT DEPENDED ON THE NAME OF THE DIRECTORY IT
# RAN FROM. Widening the class would have fixed that by introducing over-normalisation, because an
# earlier path rule rewrites any checkout path to `<repo>` and a wide class then rewrites `<repo>`
# to `<project>`. So the value is checked against its own `cwd` instead.
#
# The normaliser is not reimplemented here. It is EXTRACTED from the shipped script at run time —
# a copy would prove the copy.
#
# Exit codes: 0 every case behaved, 1 a case did not (which is the finding), 2 the environment
# could not run.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LANE="$REPO_ROOT/scripts/acceptance/parity-fixture.sh"
RECORDED="$REPO_ROOT/app/Sources/MCPRouterKit/Control/Fixtures/usage.json"
SUMMARY="$REPO_ROOT/app/Sources/MCPRouterKit/Control/Fixtures/usage-summary.json"
WORK="$(mktemp -d -t parity-normalise-selftest)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

command -v python3 >/dev/null 2>&1 || { echo "environment: python3 is not installed"; exit 2; }
[ -f "$LANE" ]     || { echo "environment: no fixture lane at $LANE"; exit 2; }
[ -f "$RECORDED" ] || { echo "environment: no recorded usage fixture at $RECORDED"; exit 2; }
[ -f "$SUMMARY" ]  || { echo "environment: no recorded usage-summary fixture at $SUMMARY"; exit 2; }

# The comparison program the lane actually writes, lifted out of its heredoc.
sed -n '/^cat > "\$WORK\/normalise.py" <<.PY.$/,/^PY$/p' "$LANE" | sed '1d;$d' > "$WORK/normalise.py"
if ! python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$WORK/normalise.py" 2>/dev/null; then
  echo "environment: could not lift a parseable normaliser out of $LANE."
  echo "             The heredoc's shape has changed, and this check would otherwise be testing"
  echo "             nothing while reporting that the normaliser is sound."
  exit 2
fi

pass=0; fail=0

# case <label> <expected-exit> <recorded.json> <live.json>
case_is() {
  local label="$1" want="$2" rec="$3" live="$4" got detail
  detail="$(python3 "$WORK/normalise.py" "$rec" "$live" 2>&1)"; got=$?
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
    printf '  ok    %-56s exit %s\n' "$label" "$got"
  else
    fail=$((fail + 1))
    printf '  WRONG %-56s exit %s, wanted %s\n' "$label" "$got" "$want"
    [ -n "$detail" ] && printf '        %s\n' "$detail"
  fi
}

REPO='/Users/someone/Dev/mcp-router'

# build <out> <cwd> <project>  — one record, cwd and project as given
build() {
  python3 - "$RECORDED" "$@" <<'PY'
import json, sys
src, out, cwd, project = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d = json.load(open(src))
d['records'][0]['cwd'] = cwd
d['records'][0]['project'] = project
json.dump(d, open(out, 'w'), separators=(',', ':'))
PY
}

echo "parity-normalise-selftest — does the fixture normaliser hide anything?"
echo

# ------------------------------------------------------------------ the recording, untouched
cp "$RECORDED" "$WORK/rec.json"
case_is "the recording against itself" 0 "$WORK/rec.json" "$WORK/rec.json"

# ------------------------------------------------------------------ D-o: every legal directory
# The recorded fixtures were captured in a worktree called F3. Each of these is the same body
# captured somewhere else, which is the only difference. Every one of them was a false DIVERGED
# before P4 except an alphanumeric name.
echo
echo "D-o — the same body, captured in a directory with another name"
for name in mcp-router my_project my-tree 'a.b c' P4 F3; do
  build "$WORK/live.json" "$REPO/.worktrees/$name" "$name"
  case_is "captured in a directory called '$name'" 0 "$WORK/rec.json" "$WORK/live.json"
done
# and in the checkout root itself, whose basename is the hyphenated one that started this
build "$WORK/live.json" "$REPO" "mcp-router"
case_is "captured in the checkout root, not a worktree" 0 "$WORK/rec.json" "$WORK/live.json"

# ------------------------------------------------------------------ what must NOT be normalised
# `project` is basename(cwd). Each of these breaks that, and each must survive to the comparison.
echo
echo "the contract — project is basename(cwd), and a body that says otherwise must go red"
build "$WORK/live.json" "$REPO" "$REPO"
case_is "project carries the WHOLE cwd" 1 "$WORK/rec.json" "$WORK/live.json"

build "$WORK/live.json" "$REPO" ""
case_is "project is empty" 1 "$WORK/rec.json" "$WORK/live.json"

# The one the old character class HID. `F3` is alphanumeric, so the old rule normalised it on both
# sides and the bodies matched — while the live body attributed a call to a directory it did not
# come from. This is the case that distinguishes checking the value against its own cwd from
# matching it by shape, and the reason a wider class was refused.
build "$WORK/live.json" "$REPO/.worktrees/P4" "F3"
case_is "project is alphanumeric and NOT basename(cwd)" 1 "$WORK/rec.json" "$WORK/live.json"

# And the one that defeats collecting the legitimate values and then substituting them globally:
# two records sharing a project string, one honest and one not. Both sides carry two records, so
# the array length is not what fails.
python3 - "$RECORDED" "$WORK/twin-rec.json" "$WORK/twin-live.json" "$REPO" <<'PY'
import copy, json, sys
src, rec_out, live_out, repo = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d = json.load(open(src))
r = d['records'][0]

rec = copy.deepcopy(d)
rec['records'] = [copy.deepcopy(r), copy.deepcopy(r)]
json.dump(rec, open(rec_out, 'w'), separators=(',', ':'))

honest = copy.deepcopy(r); honest['cwd'] = repo + '/.worktrees/P4'; honest['project'] = 'P4'
liar   = copy.deepcopy(r); liar['cwd']   = repo + '/app/Sources';   liar['project']   = 'P4'
live = copy.deepcopy(d); live['records'] = [honest, liar]
json.dump(live, open(live_out, 'w'), separators=(',', ':'))
PY
case_is "two records, one honest, one lying, same project string" 1 \
  "$WORK/twin-rec.json" "$WORK/twin-live.json"

# ------------------------------------------------------------------ usage-summary's call counts
# A rule that predated P4 claimed to preserve this array's LENGTH. It was written for an array of
# strings and the corpus holds an array of objects, so it split one entry on its internal commas
# and substituted a marker for the `calls` count along the way — a per-project count of 1 and of
# 900 normalised identically.
echo
echo "usage-summary — the per-project call counts"
cp "$SUMMARY" "$WORK/sum-rec.json"
python3 - "$SUMMARY" "$WORK/sum-same.json" "$WORK/sum-bumped.json" "$REPO" <<'PY'
import copy, json, sys
src, same_out, bumped_out, repo = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d = json.load(open(src))
for server in d['servers']:
    if server.get('projectNames'):
        server['projectNames'][0]['cwd'] = repo
        server['projectNames'][0]['project'] = 'mcp-router'
        server['projects'] = {repo: 1}
json.dump(d, open(same_out, 'w'), separators=(',', ':'))
for server in d['servers']:
    if server.get('projectNames'):
        server['projectNames'][0]['calls'] = 900
json.dump(d, open(bumped_out, 'w'), separators=(',', ':'))
PY
case_is "captured elsewhere, same counts" 0 "$WORK/sum-rec.json" "$WORK/sum-same.json"
case_is "a per-project calls count moved 1 -> 900" 1 "$WORK/sum-rec.json" "$WORK/sum-bumped.json"

echo
echo "───────────────────────────────────────────────────────────────────────"
echo "normalise selftest: $pass behaved, $fail did not"
if [ "$fail" -gt 0 ]; then
  echo
  echo "A case wanting exit 1 that returned 0 is a difference between the two routers that the"
  echo "normaliser erases. A case wanting 0 that returned 1 is a verdict that depends on where the"
  echo "gate was run from. Either is the finding."
  exit 1
fi
exit 0
