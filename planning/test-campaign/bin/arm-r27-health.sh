#!/bin/bash
# R27 — arm every case this item calls armed, watch it go red, and put the source back.
#
# An assertion nobody has watched fail is not known to bite. Each arm below reverts ONE behaviour
# the case names, runs the suite that guards it, and requires a non-zero failure count; the last
# two entries are the green baseline and a byte-identical restore, so a run that mutated and did
# not put it back is a red rather than a quiet one.
#
# `--filter` takes a TYPE name, not a `@Suite` display name. The first version of this pass
# filtered on the suite string, swift-testing matched nothing, and all four arms reported
# "0 tests passed" — four arms that compared nothing, wearing a green. That is why every run here
# is required to report how many tests it ran.
set -u
cd "$(cd "$(dirname "$0")/../../.." && pwd)"
LOG=planning/test-campaign/evidence/arming/r27-health.log
: > $LOG
say() { printf '%s\n' "$*" | tee -a $LOG; }
say "== R27 arming pass — every armed case, watched red then restored =="
say "recorded at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "command:     swift test --filter <TypeName> --package-path app"
say ""
say "THE FILTER IS A TYPE NAME, not a suite display name. A first version of this pass filtered on"
say "the @Suite string; swift-testing matched nothing, every arm reported \"0 tests passed\", and the"
say "pass would have recorded four arms that compared nothing. Each run below is required to report"
say "a NON-ZERO failure count, and this script exits 1 if one does not."
say ""

MON=app/Sources/RouterCore/Health/UpstreamHealthMonitor.swift
REC=app/Sources/RouterCore/Health/UpstreamHealthRecord.swift
DSP=app/Sources/RouterCore/Service/RouterServiceDispatch.swift
cp $MON /tmp/MON.bak; cp $REC /tmp/REC.bak; cp $DSP /tmp/DSP.bak
held=0; arms=0

run() { # label filter expect-red
  local out ran failed
  out=$(cd app && swift test --filter "$2" 2>&1 | grep -E "Test run with" | tail -1)
  ran=$(printf '%s' "$out" | sed -n 's/.*with \([0-9]*\) test.*/\1/p')
  failed=$(printf '%s' "$out" | grep -c "failed")
  arms=$((arms + 1))
  say "  $1"
  say "      $out"
  if [ "${ran:-0}" -eq 0 ]; then
    say "      REFUSED: the filter matched no tests, so this arm compared nothing."
  elif [ "$3" = red ] && [ "$failed" -eq 1 ]; then
    say "      held: the arm went red over $ran tests."
    held=$((held + 1))
  elif [ "$3" = green ] && [ "$failed" -eq 0 ]; then
    say "      green: $ran tests, unmutated."
    held=$((held + 1))
  else
    say "      DID NOT HOLD: wanted $3 and the run says otherwise."
  fi
}

say "-- ARM 1 (CASE-0220): the scheduled sweep's liveness term removed --------"
python3 - <<'PY'
import pathlib
p = pathlib.Path('app/Sources/RouterCore/Health/UpstreamHealthMonitor.swift')
s = p.read_text()
old = '            if reason == nil, await !probing.isLive(name) {'
assert old in s
s = s.replace(old, '            if reason == nil, false {')
p.write_text(s)
PY
run "a sweep now cold-starts an upstream that is not live:" UpstreamHealthMonitorTests red
cp /tmp/MON.bak $MON
say ""

say "-- ARM 2 (CASE-0219): recovery removed — a success no longer clears -------"
python3 - <<'PY'
import pathlib
p = pathlib.Path('app/Sources/RouterCore/Health/UpstreamHealthRecord.swift')
s = p.read_text()
old = '                consecutiveFailures = 0\n                lastOkAtMs = atMs'
assert old in s
s = s.replace(old, '                lastOkAtMs = atMs')
p.write_text(s)
PY
run "a tripped upstream can no longer recover:" UpstreamHealthPolicyTests red
cp /tmp/REC.bak $REC
say ""

say "-- ARM 3 (CASE-0222): refusals dropped instead of carried ----------------"
python3 - <<'PY'
import pathlib
p = pathlib.Path('app/Sources/RouterCore/Health/UpstreamHealthMonitor.swift')
s = p.read_text()
old = '                refusals: globalRefusals + resolved.refusals'
assert old in s
s = s.replace(old, '                refusals: []')
p.write_text(s)
PY
run "the wire stops saying which settings were ignored:" "UpstreamHealthMonitorTests|ControlHealthRoutesTests" red
cp /tmp/MON.bak $MON
say ""

say "-- ARM 4 (CASE-0221): the disabled term removed --------------------------"
python3 - <<'PY'
import pathlib
p = pathlib.Path('app/Sources/RouterCore/Health/UpstreamHealthMonitor.swift')
s = p.read_text()
old = '        if disabledNames.contains(name) { return "the server is disabled" }\n'
assert old in s
s = s.replace(old, '')
p.write_text(s)
PY
run "a disabled server is probed like any other:" UpstreamHealthMonitorTests red
cp /tmp/MON.bak $MON
say ""

say "-- ARM 5 (CASE-0218): the health dependency unwired in the daemon --------"
python3 - <<'PY'
import pathlib
p = pathlib.Path('app/Sources/RouterCore/Service/RouterServiceDispatch.swift')
s = p.read_text()
old = '            health: health\n'
assert old in s
p.write_text(s.replace(old, '            health: nil\n'))
PY
(cd app && swift build --product MCPRouterCLI >/dev/null 2>&1)
LANE_OUT=$(bash scripts/acceptance/r27-health.sh 2>&1 | tail -3)
arms=$((arms + 1))
say "  the acceptance lane against a daemon that ships the dependency nil:"
printf '%s\n' "$LANE_OUT" | sed 's/^/      /' | tee -a $LOG >/dev/null
printf '%s\n' "$LANE_OUT" | sed 's/^/      /'
case "$LANE_OUT" in
  *"0 failed"*) say "      DID NOT HOLD: the lane stayed green over an unwired daemon." ;;
  *) say "      held: the lane went red, which is the one oracle that can see this line missing."
     held=$((held + 1)) ;;
esac
python3 - <<'PY'
import pathlib
p = pathlib.Path('app/Sources/RouterCore/Service/RouterServiceDispatch.swift')
s = p.read_text()
p.write_text(s.replace('            health: nil\n', '            health: health\n'))
PY
(cd app && swift build --product MCPRouterCLI >/dev/null 2>&1)
say ""

say "-- restored: every mutated source back byte-identical --------------------"
# Against the copies taken BEFORE the arms, not against HEAD: two of the three files are part of
# this item's own change, so a diff against HEAD is the feature and says nothing about the restore.
restored=0
for pair in "$MON /tmp/MON.bak" "$REC /tmp/REC.bak" "$DSP /tmp/DSP.bak"; do
  set -- $pair
  if cmp -s "$1" "$2"; then say "  byte-identical: $1"; restored=$((restored + 1))
  else say "  NOT RESTORED: $1"; fi
done
arms=$((arms + 1))
[ "$restored" -eq 3 ] && held=$((held + 1)) || say "  the restore did not hold."
say ""

say "-- the green baseline ----------------------------------------------------"
run "unmutated:" "UpstreamHealthPolicyTests|UpstreamHealthMonitorTests|UpstreamHealthProbeTests|ControlHealthRoutesTests" green
say ""
say "arms: $held of $arms held"
[ "$held" -eq "$arms" ] || exit 1
exit 0
