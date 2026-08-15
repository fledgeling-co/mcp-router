#!/usr/bin/env bash
#
# R4 — the fixture lane.
#
# The 23-plus-one recorded bodies in app/Sources/MCPRouterKit/Control/Fixtures are the wire
# contract: every Swift decode test is written against them. That makes them load-bearing and
# unverified in one specific way — nothing checks that the REFERENCE still emits them. A fixture
# recorded once and never re-measured is a contract with the past, and the Swift side can be
# perfectly faithful to a shape the reference stopped sending.
#
# So this lane re-runs F3's own recorder against a live reference and diffs what comes back
# against what is committed. The fixtures are never written to: the lane captures into a scratch
# directory and compares. A lane that edits its own oracle proves nothing.
#
# What this lane proves is REFERENCE CURRENCY — that the recorded contract is still the live one.
# It is deliberately not the same claim as the control lane's, which compares the two routers
# against each other. The gate reports the two separately for that reason.
#
# It also captures the HTTP STATUS of every fixture, which the recorded set has never carried
# (deferred child D-a): a port could answer every fixture's bytes under the wrong status and the
# whole decode suite would still pass.
#
# Exit codes: 0 every comparable fixture matched, 1 a fixture drifted, 2 the environment could
# not run the capture.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RECORDED="$REPO_ROOT/app/Sources/MCPRouterKit/Control/Fixtures"
PORT="${FIXTURE_PORT:-8963}"
OAUTH_PORT="${FIXTURE_OAUTH_PORT:-8964}"
WORK="$(mktemp -d -t parity-fixture)"
RESULTS="${PARITY_RESULTS:-}"
BASELINE="${PARITY_STATUS_BASELINE:-$REPO_ROOT/planning/parity/fixture-status.tsv}"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

record() {
  [ -n "$RESULTS" ] || return 0
  printf '%s\t%s\t%s\t%s\n' "fixture" "$1" "$2" "$3" >> "$RESULTS"
}

command -v node    >/dev/null 2>&1 || { echo "environment: node is not installed"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "environment: python3 is not installed"; exit 2; }
[ -f "$REPO_ROOT/dist/index.js" ] || {
  echo "environment: no built reference at dist/index.js. Run npm run build."
  echo "             A skipped lane is recorded as blocked, not as a pass."
  exit 2; }
[ -d "$RECORDED" ] || { echo "environment: no recorded fixtures at $RECORDED"; exit 2; }

# The user's own router runs on 8975/8976 and their live Claude Code sessions depend on it. This
# lane starts its own reference and refuses a port it does not own rather than sharing one.
for p in "$PORT" "$OAUTH_PORT"; do
  if lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "environment: something is already listening on :$p. This harness never shares a port,"
    echo "             and never touches the router on 8975/8976. Set FIXTURE_PORT to move it."
    exit 2
  fi
done

mkdir -p "$WORK/recaptured" "$WORK/status"
echo "re-capturing the fixture set against a live reference on :$PORT"
STATUS_DIR="$WORK/status" PORT="$PORT" OAUTH_PORT="$OAUTH_PORT" \
  bash "$REPO_ROOT/scripts/capture-control-fixtures.sh" "$WORK/recaptured" > "$WORK/capture.log" 2>&1
capture_status=$?
if [ "$capture_status" != 0 ]; then
  echo "environment: the capture did not complete, so no fixture was re-measured this run."
  tail -12 "$WORK/capture.log"
  exit 2
fi
echo "  captured $(ls -1 "$WORK/recaptured" | wc -l | tr -d ' ') bodies and \
$(ls -1 "$WORK/status" 2>/dev/null | wc -l | tr -d ' ') statuses"
echo

# ---------------------------------------------------------------------------------------------
# Normalisation. Every member removed here is a fact about the RUN rather than about the
# contract, and each is rewritten to a marker rather than deleted — so a fixture that stops
# carrying one is still a mismatch. Deleting them would let the port drop a member and stay green.
#
# The one substantive concession is `hash`. It is a digest of the server's config, and
# fixture-tools' config embeds the absolute path of the worktree the capture ran in. The recording
# was made in .worktrees/F3, which no longer exists, so the hash cannot match and its difference
# carries no information about the port. It is normalised, and this comment is the record of that.
cat > "$WORK/normalise.py" <<'PY'
import json, posixpath, re, sys

SUBS = [
    # Any ISO-8601 value, whatever its key. Written as one rule rather than a list of member
    # names because the list was wrong twice: `indexedAt` and `firstSeen` were both missing, and
    # each cost a full re-capture to discover. A timestamp is a fact about when the capture ran,
    # and a field added later should not quietly break this lane.
    # Across the 24 fixtures this covers since, ts, seenAt, firstSeen, indexedAt, lastUsed,
    # pushedAt and updatedAt.
    (r'"([A-Za-z]+)":"\d{4}-\d{2}-\d{2}T[^"]*"', r'"\1":"<stamp>"'),
    (r'"pid":\d+',                          '"pid":"<pid>"'),
    (r'"ms":\d+',                           '"ms":"<ms>"'),
    (r'"port":\d+',                         '"port":"<port>"'),
    # How long a child has sat idle is a fact about how fast the capture ran, not about the wire
    # contract. The recording caught 0s; a machine under load catches 2s. Normalised rather than
    # deleted, so a body that stops carrying idleSec at all is still a mismatch.
    (r'"idleSec":\d+',                      '"idleSec":"<idleSec>"'),
    # `+` not `*`. With `*`, a body carrying "hash":"" normalised to the same marker as a real
    # digest, so a reference that stopped hashing would have passed. The normalisation itself is
    # unavoidable — the digest covers a config that embeds the capturing worktree's absolute path,
    # and the recording was made in a worktree that no longer exists — but it must not also accept
    # the field being empty.
    (r'"hash":"[0-9a-f]+"',                 '"hash":"<hash>"'),
    (r'code_challenge=[A-Za-z0-9_\-]+',     'code_challenge=<challenge>'),
    (r'client_id=[A-Za-z0-9_\-]+',          'client_id=<client>'),
    (r'127\.0\.0\.1%3A\d+',                 '127.0.0.1%3A<port>'),
    (r'127\.0\.0\.1:\d+',                   '127.0.0.1:<port>'),
    # Any checkout of this repo, whichever worktree the capture ran in.
    #
    # ONE PATH SEGMENT for the worktree name, and every character a directory name may legally
    # carry. It read [A-Za-z0-9]+ until P4: every worktree so far had been called F3, R2R, P1, so
    # the class had never been asked for a hyphen. A worktree named `my-tree` normalises
    # `.worktrees/my` and leaves `-tree` behind, producing `<repo>-tree` against a recorded
    # `<repo>` — reported as a divergence in the ROUTER, caused by a directory name.
    # It is [^"/]+ and not [^"]+ because a greedy match to the closing quote swallows the rest of
    # the path: `.worktrees/P4/app/Sources` would collapse to one marker and take real structure
    # with it.
    (r'/Users/[^"]*?/mcp-router/\.worktrees/[^"/]+', '<repo>'),
    (r'/Users/[^"]*?/mcp-router',           '<repo>'),
    # The scratch home each run mints.
    (r'/var/folders/[^"]*?mcprouter-[A-Za-z0-9.]+', '<tmp>'),
    (r'/tmp/mcprouter-[A-Za-z0-9.]+',       '<tmp>'),
    # `+` not `*`, for the reason spelled out on `hash` above: with `*`, a body carrying
    # "cwd":"" normalised to the same marker as a real directory.
    (r'"cwd":"[^"]+"',                      '"cwd":"<cwd>"'),
]


# ---------------------------------------------------------------------------------------------
# `project` is NOT in the table above, and the difference is the point.
#
# It used to be, as "project":"[A-Za-z0-9]+" — a class with no `-`, so a call attributed to a
# directory called `mcp-router` did not normalise while one attributed to `F3` did. Project
# attribution is `basename(cwd)` (src/usage.ts:305), so that made THE GATE'S VERDICT DEPEND ON THE
# NAME OF THE DIRECTORY IT WAS RUN FROM: from the repo root the `usage` fixture read DIVERGED, and
# from any alphanumerically-named worktree the same tree read clean. Every runner works in such a
# worktree, which is why it survived three adversarial reviews of the harness.
#
# The obvious repair — widening the class to [^"]+ — is WORSE, and was rejected in review. The
# substitutions run in order, and the repo-path rules above rewrite any checkout path to `<repo>`
# BEFORE a project rule would run. So if the reference ever regressed to putting the whole cwd in
# `project` instead of its basename:
#     live "project":"/Users/…/mcp-router"  ->  "project":"<repo>"  ->  "project":"<project>"
# and the recorded body is already "<project>". The bodies would match and a real change to what
# the reference reports would be invisible. Today that regression is caught only by accident,
# because `<repo>` contains characters the narrow class rejects. Fixing under-matching by
# introducing over-matching is the wrong trade for a parity harness: a missed normalisation costs a
# false red, a missed difference costs a false green.
#
# So the value is not matched by shape at all. It is checked against the contract: a project is
# normalised exactly where it equals basename(cwd) of its own object and is non-empty. That accepts
# every legal directory name — hyphens, underscores, dots, spaces — and accepts nothing else. A
# whole cwd, "/", "." and "" all fail it and survive to the comparison.
#
# It also retires a second rule that used to sit beside the old one:
#
#     (r'"projectNames":\[([^\]]*)\]',
#      lambda m: … ','.join('"<project>"' for x in m.group(1).split(',') …
#
# whose comment claimed it preserved the array's LENGTH. It was written for an array of strings and
# the corpus holds an array of OBJECTS — {"cwd":…,"project":"F3","calls":1} — so it split one entry
# on its internal commas and emitted three markers, substituting "<project>" for the `calls` count
# along the way. A per-project call count of 1 and of 900 normalised identically. It never failed
# because it mangled both sides the same way; it was also blind. Every `project` inside that array
# has a sibling `cwd`, so the rule below covers it, and the array length and every `calls` value
# now compare for the first time.
def legitimate_projects(node, out):
    if isinstance(node, dict):
        cwd, proj = node.get('cwd'), node.get('project')
        if isinstance(cwd, str) and isinstance(proj, str) and proj \
           and proj == posixpath.basename(cwd.rstrip('/')):
            out.add(proj)
        for value in node.values():
            legitimate_projects(value, out)
    elif isinstance(node, list):
        for value in node:
            legitimate_projects(value, out)


def normalise(text):
    # Structural first, and by literal substitution rather than by re-serialising the parsed
    # document: the comparison downstream is byte-level, so dumping JSON back out would also
    # normalise away whitespace and member order, which ARE compared today.
    #
    # A body that will not parse skips this pass, keeps its raw project value, and mismatches.
    # That is the safe direction.
    try:
        projects = set()
        legitimate_projects(json.loads(text), projects)
    except Exception:
        projects = set()
    for value in projects:
        text = re.sub(r'"project"\s*:\s*"' + re.escape(value) + '"',
                      '"project":"<project>"', text)
    for pattern, replacement in SUBS:
        text = re.sub(pattern, replacement, text)
    return text


def first_difference(a, b, path=''):
    """The first differing leaf, named by its path. A truncated dump of two 4KB bodies is
    unreadable, and the reader stops at the first difference that matters anyway."""
    if type(a) is not type(b):
        return f'{path or "<root>"}: recorded is {type(a).__name__}, live is {type(b).__name__}'
    if isinstance(a, dict):
        for key in sorted(set(a) | set(b)):
            if key not in a:
                return f'{path}.{key}: absent in the recording, live={json.dumps(b[key])[:90]}'
            if key not in b:
                return f'{path}.{key}: recorded={json.dumps(a[key])[:90]}, absent live'
            found = first_difference(a[key], b[key], f'{path}.{key}')
            if found:
                return found
        return None
    if isinstance(a, list):
        if len(a) != len(b):
            return f'{path}: recorded has {len(a)} entries, live has {len(b)}'
        for i, (x, y) in enumerate(zip(a, b)):
            found = first_difference(x, y, f'{path}[{i}]')
            if found:
                return found
        return None
    if a != b:
        return f'{path or "<root>"}: recorded={json.dumps(a)[:90]} live={json.dumps(b)[:90]}'
    return None

recorded, recaptured = sys.argv[1], sys.argv[2]
a = normalise(open(recorded).read().strip())
b = normalise(open(recaptured).read().strip())
if a == b:
    sys.exit(0)
try:
    detail = first_difference(json.loads(a), json.loads(b))
    print(detail or 'the bodies differ only in whitespace or member order')
except Exception:
    print(f'recorded={a[:150]} live={b[:150]}')
sys.exit(1)
PY

# ---------------------------------------------------------------------------------------------
# registry-search is the one fixture with no stable oracle: the reference calls live registries
# and two runs a second apart differ. It is blocked in the manifest with that reason, and is not
# compared here rather than being compared and excused.
pass_count=0; fail_count=0
echo "fixture                        status  verdict"
for recorded in "$RECORDED"/*.json; do
  name="$(basename "$recorded" .json)"
  id="fixture-$name"
  live="$WORK/recaptured/$name.json"
  status="$(cat "$WORK/status/$name.status" 2>/dev/null || echo '---')"

  if [ "$name" = "registry-search" ]; then
    printf '  %-28s %-7s %s\n' "$name" "$status" "not compared — live registry, no stable oracle"
    continue
  fi

  if [ ! -f "$live" ]; then
    fail_count=$((fail_count + 1))
    printf '  %-28s %-7s %s\n' "$name" "$status" "NOT RE-CAPTURED — the recorder no longer produces it"
    record "$id" fail "the recorder produced no body for this fixture"
    continue
  fi

  # The STATUS is asserted, not merely captured. Once planning/parity/fixture-status.tsv exists it
  # is the baseline, and a fixture whose body is byte-identical under a different status code is a
  # failure — that combination is exactly what deferred child D-a was raised about, and capturing
  # the number without comparing it would have left the gap open while looking closed.
  status_note=""
  if [ -f "$BASELINE" ]; then
    want="$(awk -F'\t' -v n="$name" '$1 == n { print $2 }' "$BASELINE" | head -1)"
    if [ -n "$want" ] && [ "$want" != "$status" ]; then
      fail_count=$((fail_count + 1))
      printf '  %-28s %-7s %s\n' "$name" "$status" "STATUS CHANGED — the baseline records $want"
      record "$id" fail "status changed: baseline $want, live $status"
      continue
    fi
    [ -z "$want" ] && status_note=" (no baseline status recorded for this fixture)"
  fi

  if detail="$(python3 "$WORK/normalise.py" "$recorded" "$live" 2>&1)"; then
    pass_count=$((pass_count + 1))
    printf '  %-28s %-7s %s\n' "$name" "$status" "matches the recording$status_note"
    record "$id" ok "reference still emits the recorded body; status $status matches the baseline"
  else
    fail_count=$((fail_count + 1))
    printf '  %-28s %-7s %s\n' "$name" "$status" "DRIFTED"
    printf '        %s\n' "$detail"
    record "$id" fail "the recording no longer matches the reference — $detail"
  fi
done

# The status census (D-a). Written only where asked, so the lane has no side effects by default.
if [ -n "${PARITY_STATUS_OUT:-}" ]; then
  : > "$PARITY_STATUS_OUT"
  for f in "$WORK/status"/*.status; do
    [ -f "$f" ] || continue
    printf '%s\t%s\n' "$(basename "$f" .status)" "$(cat "$f")" >> "$PARITY_STATUS_OUT"
  done
fi

echo
echo "fixtures: $pass_count match the live reference, $fail_count drifted"
[ "$fail_count" -gt 0 ] && exit 1
exit 0
