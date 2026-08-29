#!/bin/bash
# R22 — arm every case this item calls armed, watch it go red, and put the source back.
#
# An assertion nobody has watched fail is not known to bite. Each arm below reverts ONE behaviour a
# case names, runs the suite that guards it, and requires a non-zero failure count; the last two
# entries are the green baseline and a byte-identical restore, so a run that mutated and did not put
# it back is a red rather than a quiet one.
#
# EIGHT ARMS. TWO OF THEM EXIST BECAUSE THERE ARE TWO LAYERS, and the pair is the point. Arm 1 removes the
# STRUCTURAL layer and arm 2 removes the VALUE-SCRUB layer, and they redden DIFFERENT cases:
# CASE-0270 plants its secret in config only, CASE-0271 plants it in a log line only. A single
# "no secret in the bundle" case would have gone green under arm 2 and the second layer would have
# been unwitnessed while looking guarded.
#
# `--filter` takes a TYPE name, not a `@Suite` display name — R27's arming pass recorded that after
# four arms reported "0 tests passed" and would have passed as four arms that compared nothing. Each
# run below is required to report a NON-ZERO test count and this script exits 1 if one does not.
#
# PWD IS PINNED to the physical spelling. `.worktrees` is a symlink and `swift-frontend` resolves a
# relative module-cache path against `$PWD` rather than `getcwd()`; a cache filled under one
# spelling and read under the other exits 139 with a message that names one file twice.
# `scripts/worktree-preflight.sh` carries the measurement.
set -u
REPO="$(cd "$(dirname "$0")/../../.." && pwd -P)"
cd "$REPO" || exit 1
export PWD="$REPO"

LOG=planning/test-campaign/evidence/arming/r22-diagnostics.log
mkdir -p "$(dirname $LOG)"
: > $LOG
say() { printf '%s\n' "$*" | tee -a $LOG; }
say "== R22 arming pass — every armed case, watched red then restored =="
say "recorded at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "tree:        $(git rev-parse HEAD)"
say "command:     swift test --filter ControlDiagnosticsTests --package-path app"
say ""

JSON=app/Sources/RouterCore/Control/ControlDiagnosticsJSON.swift
NEEDLES=app/Sources/RouterCore/Diagnostics/SecretNeedles.swift
REDACT=app/Sources/RouterCore/Diagnostics/SecretRedactor.swift
PATHS=app/Sources/RouterCore/Control/ControlToken.swift
DIAG=app/Sources/RouterCore/Control/ControlDiagnostics.swift
for f in $JSON $NEEDLES $REDACT $PATHS $DIAG; do cp "$f" "/tmp/r22-$(basename $f).bak"; done
restore() { for f in $JSON $NEEDLES $REDACT $PATHS $DIAG; do cp "/tmp/r22-$(basename $f).bak" "$f"; done; }
held=0; arms=0

run() { # label expect-red|green
  local all out ran failed which
  all=$(cd app && PWD="$REPO/app" swift test --filter ControlDiagnosticsTests 2>&1)
  out=$(printf '%s' "$all" | grep -E "Test run with" | tail -1)
  ran=$(printf '%s' "$out" | sed -n 's/.*with \([0-9]*\) test.*/\1/p')
  failed=$(printf '%s' "$out" | grep -c "failed")
  # WHICH tests went red, not just how many. An arm that reddens the wrong case is an arm that
  # proved something other than what its label claims, and a count cannot tell the two apart.
  which=$(printf '%s' "$all" | grep -E 'Test "[^"]*" failed after' \
          | grep -oE '(CASE-[0-9]{4}|R22-[a-z])' | sort -u | tr '\n' ' ')
  arms=$((arms + 1))
  say "  $1"
  say "      $out"
  say "      cases red: ${which:-none}"
  if [ "${ran:-0}" -eq 0 ]; then
    say "      REFUSED: the filter matched no tests, so this arm compared nothing."
  elif [ "$2" = red ] && [ "$failed" -eq 1 ]; then
    say "      held: the arm went red over $ran tests."
    held=$((held + 1))
  elif [ "$2" = green ] && [ "$failed" -eq 0 ]; then
    say "      green: $ran tests, unmutated."
    held=$((held + 1))
  else
    say "      DID NOT HOLD: wanted $2 and the run says otherwise."
  fi
}

say "-- ARM 1 (CASE-0270): LAYER 1 removed — the env value is emitted instead of its shape ----"
python3 - <<'PY'
import pathlib
p = pathlib.Path('app/Sources/RouterCore/Control/ControlDiagnosticsJSON.swift')
s = p.read_text()
old = """            JSONMember(key: "value", value: .string(JSString(
                DiagnosticsBundle.shape(of: pair.value.string).rawValue
            )))"""
assert old in s, "arm 1 anchor moved"
p.write_text(s.replace(old, '            JSONMember(key: "value", value: .string(pair.value))'))
PY
run "a configured token now reaches the bundle:" red
restore
say ""

say "-- ARM 2 (CASE-0271): LAYER 2 removed — the value scrub never runs -----------------------"
python3 - <<'PY'
import pathlib
p = pathlib.Path('app/Sources/RouterCore/Control/ControlDiagnosticsJSON.swift')
s = p.read_text()
old = "        let (scrubbed, tally) = redactor.redact(gathered)"
assert old in s, "arm 2 anchor moved"
p.write_text(s.replace(
    old, "        let (scrubbed, tally) = (gathered, SecretRedactor.Tally())"))
PY
run "a token quoted back in a log line now survives:" red
restore
say ""

say "-- ARM 3 (CASE-0272): the needle floor removed — a 3-character value becomes a needle ----"
python3 - <<'PY'
import pathlib
p = pathlib.Path('app/Sources/RouterCore/Diagnostics/SecretNeedles.swift')
s = p.read_text()
old = "    public static let minimumNeedleLength = 8"
assert old in s, "arm 3 anchor moved"
p.write_text(s.replace(old, "    public static let minimumNeedleLength = 1"))
PY
run "scrubbing 'dev' now corrupts every log line that contains it:" red
restore
say ""

say "-- ARM 4 (CASE-0273): the encoded forms removed — only the literal is a needle -----------"
python3 - <<'PY'
import pathlib
p = pathlib.Path('app/Sources/RouterCore/Diagnostics/SecretNeedles.swift')
s = p.read_text()
old = "        var forms = [literal]"
assert old in s, "arm 4 anchor moved"
p.write_text(s.replace(old, "        return [literal]\n        var forms = [literal]"))
PY
run "a percent-encoded or base64 token now survives:" red
restore
say ""

say "-- ARM 5 (CASE-0274): the ungated preview now carries the log tail ----------------------"
python3 - <<'PY'
import pathlib
p = pathlib.Path('app/Sources/RouterCore/Control/ControlDiagnosticsJSON.swift')
s = p.read_text()
old = """        case let .lines(lines):
            categories.append(categoryValue("routerLog", available: true, count: lines.count))"""
assert old in s, "arm 5 anchor moved"
p.write_text(s.replace(old, """        case let .lines(lines):
            categories.append(.object([
                JSONMember(key: "category", value: .string(JSString("routerLog"))),
                JSONMember(key: "tail", value: .array(lines.map { JSONValue.string(JSString($0)) }))
            ]))"""))
PY
run "an untokened GET now serves log content:" red
restore
say ""

say "-- ARM 6 (CASE-0275): the bundle answers GET, so the token gate never runs ---------------"
python3 - <<'PY'
import pathlib
p = pathlib.Path('app/Sources/RouterCore/Control/ControlDiagnostics.swift')
s = p.read_text()
old = '        case ("/diagnostics/bundle", "POST"):'
assert old in s, "arm 6 anchor moved"
p.write_text(s.replace(old, '        case ("/diagnostics/bundle", "GET"):'))
PY
run "the bundle is reachable without the token:" red
restore
say ""

say "-- ARM 7 (R22-d): longest-first ordering removed — a short needle truncates a long one ---"
python3 - <<'PY'
import pathlib
p = pathlib.Path('app/Sources/RouterCore/Diagnostics/SecretRedactor.swift')
s = p.read_text()
old = "            .sorted { $0.text.count > $1.text.count }"
assert old in s, "arm 7 anchor moved"
p.write_text(s.replace(old, "            .sorted { $0.text.count < $1.text.count }"))
PY
run "the remainder of a longer secret is left beside a redaction marker:" red
restore
say ""

say "-- ARM 8 (R22-f): the redaction block appended unscrubbed ----------------------------"
python3 - <<'ARM8'
import pathlib
p = pathlib.Path('app/Sources/RouterCore/Control/ControlDiagnosticsJSON.swift')
s = p.read_text()
old = "        let block = elision.elide(redactor.redact(appliedRedactionValue(redactor, tally)).0)"
assert old in s, "arm 8 anchor moved"
p.write_text(s.replace(old, "        let block = appliedRedactionValue(redactor, tally)"))
ARM8
run "a credential written into an env KEY escapes through unscrubbable:" red
restore
say ""

say "-- BASELINE: unmutated ------------------------------------------------------------------"
run "the suite is green with every layer in place:" green
say ""

say "-- RESTORE: every source file byte-identical to the tree ---------------------------------"
# Compared against the copies taken at the top rather than against `git status`, because three of
# these files are NEW on this branch: an untracked file is reported modified by git whatever this
# pass did to it, so a git-based check here reads red on a clean run and proves nothing.
dirty=0
for f in $JSON $NEEDLES $REDACT $PATHS $DIAG; do
  cmp -s "$f" "/tmp/r22-$(basename $f).bak" || dirty=$((dirty + 1))
done
if [ "$dirty" -eq 0 ]; then
  say "  held: all five files this pass mutated are byte-identical to the copies taken at the top."
  held=$((held + 1)); arms=$((arms + 1))
else
  say "  DID NOT HOLD: $dirty file(s) left modified. A pass that mutated and did not restore is a red."
  arms=$((arms + 1))
fi

say ""
say "arms: $held of $arms held"
[ "$held" -eq "$arms" ] || exit 1
