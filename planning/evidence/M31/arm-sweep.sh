#!/usr/bin/env bash
# M31's presence control for sweep-prominent-disabled.py.
#
# The sweep's first form could not fail: `failures` was initialised, read twice and never appended
# to, so `failures=0 examined=23` was structurally guaranteed. A denominator is not a control.
#
# Each arm plants a real defect, and the assertion is the DIFF of the sweep's verdict lines against
# baseline plus the movement in its failure count — not a grep for a word. Grepping was tried first
# and was wrong twice in one run: arm 2's pattern found nothing while the sweep went red anyway (it
# had classified the plant more severely than expected), and arm 4's pattern matched five verdict
# lines that were already there, so a plant that changed nothing would have "passed". A control
# that reports the wrong reason for going red is the failure this whole item is about.
#
# Every arm re-creates a defect this item actually fixed, so each is a regression the sweep owns.
set -euo pipefail
SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
# These are negative controls, so their subject must not be the checkout other
# readers inspect. Keep the sweep's normal relative roots in a private source copy.
mkdir -p "$SCRATCH/app" "$SCRATCH/design" "$SCRATCH/docs" "$SCRATCH/planning/evidence/M31"
cp -R "$SOURCE_ROOT/app/Sources" "$SCRATCH/app/Sources"
cp "$SOURCE_ROOT/design/mcp-router-console.html" "$SOURCE_ROOT/design/banner.html" "$SCRATCH/design/"
cp "$SOURCE_ROOT/docs/mcp-router-store.html" "$SOURCE_ROOT/docs/index.html" "$SCRATCH/docs/"
cp "$SOURCE_ROOT/planning/evidence/M31/sweep-prominent-disabled.py" "$SCRATCH/planning/evidence/M31/"
cd "$SCRATCH"
RC=0
ARMS=0
MOCK=design/mcp-router-console.html
STORE=docs/mcp-router-store.html
SWIFT=app/Sources/MCPRouterUI/Controls.swift
SWEEP=planning/evidence/M31/sweep-prominent-disabled.py

sha(){ shasum -a 256 "$1" | cut -c1-16; }
sweep_report(){ local code=0; python3 "$SWEEP" "$@" 2>&1 || code=$?; [ "$code" -le 1 ]; }
verdicts(){ sweep_report | grep -E "^      (DIMS|UNDRAWN|UNREADABLE|DRAWS-AS-ENABLED|MARKER-MISMATCH)|^  FAIL " | sed 's/  */ /g'; }
fails(){ sweep_report | grep -oE "TOTAL failures=[0-9]+" | grep -oE "[0-9]+"; }

BASE_V="$SCRATCH/baseline.verdicts"
python3 "$SWEEP" >/dev/null
verdicts > "$BASE_V"; BASE_F=$(fails)

arm(){ # name  file  sed-expression
  local name="$1" file="$2" expr="$3" before after pf pv
  ARMS=$((ARMS + 1))
  before=$(sha "$file"); cp "$file" "$SCRATCH/arm.backup"
  sed -i '' "$expr" "$file"
  echo "ARM $name"
  if [ "$(sha "$file")" = "$before" ]; then
    echo "    VACUOUS — the plant did not apply; this arm proves nothing"
    cp "$SCRATCH/arm.backup" "$file"; rm -f "$SCRATCH/arm.backup"; RC=1; return 0
  fi
  echo "    planted   $file  $before -> $(sha "$file")"
  pf=$(fails); pv="$SCRATCH/planted.verdicts"; verdicts > "$pv"
  if [ "$pf" -le "$BASE_F" ] || cmp -s "$BASE_V" "$pv"; then RC=1; fi
  echo "    failures  $BASE_F -> $pf  $([ "$pf" -gt "$BASE_F" ] && echo 'WENT RED' || echo '*** DID NOT GO RED ***')"
  echo "    verdicts that changed:"
  diff "$BASE_V" "$pv" | grep -E "^[<>]" | sed 's/^/      /' || echo "      (none — the sweep did not notice)"
  rm -f "$pv"
  cp "$SCRATCH/arm.backup" "$file"; rm -f "$SCRATCH/arm.backup"
  after=$(sha "$file")
  if [ "$after" != "$before" ]; then RC=1; fi
  echo "    restored  $after  $([ "$after" = "$before" ] && echo IDENTICAL || echo '*** DIVERGED ***')"
  echo
}

echo "=== BASELINE ===  failures=$BASE_F  exit=$(python3 "$SWEEP" >/dev/null 2>&1; echo $?)"
echo "  $MOCK  $(sha $MOCK)"
echo "  $STORE  $(sha $STORE)"
echo "  $SWIFT  $(sha $SWIFT)"
echo

arm "1 DRAWS-AS-ENABLED — un-enumerate .tb-btn so .on wins the cascade again" \
    "$MOCK" 's|\.tb-btn\.disabled,\.tb-btn:disabled,\.tb-btn\.on\.disabled,\.tb-btn\.on:disabled|.tb-btn.disabled,.tb-btn:disabled|'

arm "2 UNREADABLE (descendant) — drop the .trow.disabled descendant block, leaving --on-accent on --f3" \
    "$MOCK" '/^\.trow\.disabled \.c-sub,/,/^\.trow\.disabled \.pub \.vf{color:var(--t4);}$/d'

arm "3 DRAWS-AS-ENABLED (row) — take the fill back off .trow.disabled" \
    "$MOCK" 's|\.trow\.disabled{color:var(--t4);background:var(--f3);}|.trow.disabled{color:var(--t4);}|'

arm "4 MARKER-MISMATCH — respell the switch rule for :disabled only, as it was" \
    "$MOCK" 's|\.switch\.disabled,\.switch:disabled{background|.switch:disabled{background|'

arm "5 UNDRAWN(reachable) — delete the store page's disabled rule entirely" \
    "$STORE" '/^\.btn\[disabled\],\.btn\.disabled{/d'

# The shorthand/longhand hide, found by an out-of-family review. The accent rule is respelled
# `background-color` and the disabled rule is un-enumerated so the accent legitimately wins. The
# resolver's first form tried `background` first and fell back, so it read the LOSING disabled
# `background` and reported DIMS over a control drawing its accent. This arm is the regression.
arm "6 DRAWS-AS-ENABLED via background-color — the shorthand/longhand hide" \
    "$MOCK" 's|\.tb-btn\.on{background:var(--accent-ink);|.tb-btn.on{background-color:var(--accent-ink);|; s|\.tb-btn\.disabled,\.tb-btn:disabled,\.tb-btn\.on\.disabled,\.tb-btn\.on:disabled|.tb-btn.disabled,.tb-btn:disabled|'

arm "7 Swift FAIL — paint the prominent fill unconditionally, the M18 defect shape" \
    "$SWIFT" 's|\.fill(tokens\.fill\.color)|.fill(ColorToken.accent.color)|'

echo "=== RESTORED ===  failures=$(fails)  exit=$(python3 "$SWEEP" >/dev/null 2>&1; echo $?)"
echo "  $MOCK  $(sha $MOCK)"
echo "  $STORE  $(sha $STORE)"
echo "  $SWIFT  $(sha $SWIFT)"
if diff "$BASE_V" <(verdicts) >/dev/null; then
  echo "  verdict table identical to baseline"
else
  echo "  *** VERDICT TABLE DRIFTED ***"; RC=1
fi
echo "  $ARMS planted controls ran in an isolated source copy; original checkout was never written"
exit "$RC"
