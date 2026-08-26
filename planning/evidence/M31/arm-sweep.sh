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
set -u
cd "$(git rev-parse --show-toplevel)"
MOCK=design/mcp-router-console.html
STORE=docs/mcp-router-store.html
SWIFT=app/Sources/MCPRouterUI/Controls.swift
SWEEP=planning/evidence/M31/sweep-prominent-disabled.py

sha(){ shasum -a 256 "$1" | cut -c1-16; }
verdicts(){ python3 "$SWEEP" 2>&1 | grep -E "^      (DIMS|UNDRAWN|UNREADABLE|DRAWS-AS-ENABLED|MARKER-MISMATCH)|^  FAIL " | sed 's/  */ /g'; }
fails(){ python3 "$SWEEP" 2>&1 | grep -oE "TOTAL failures=[0-9]+" | grep -oE "[0-9]+"; }

BASE_V=$(mktemp); verdicts > "$BASE_V"; BASE_F=$(fails)

arm(){ # name  file  sed-expression
  local name="$1" file="$2" expr="$3" before after pf pv
  before=$(sha "$file"); cp "$file" "/tmp/m31.arm.$$"
  sed -i '' "$expr" "$file"
  echo "ARM $name"
  if [ "$(sha "$file")" = "$before" ]; then
    echo "    VACUOUS — the plant did not apply; this arm proves nothing"
    cp "/tmp/m31.arm.$$" "$file"; rm -f "/tmp/m31.arm.$$"; return 1
  fi
  echo "    planted   $file  $before -> $(sha "$file")"
  pf=$(fails); pv=$(mktemp); verdicts > "$pv"
  echo "    failures  $BASE_F -> $pf  $([ "$pf" -gt "$BASE_F" ] && echo 'WENT RED' || echo '*** DID NOT GO RED ***')"
  echo "    verdicts that changed:"
  diff "$BASE_V" "$pv" | grep -E "^[<>]" | sed 's/^/      /' || echo "      (none — the sweep did not notice)"
  rm -f "$pv"
  cp "/tmp/m31.arm.$$" "$file"; rm -f "/tmp/m31.arm.$$"
  after=$(sha "$file")
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

arm "6 Swift FAIL — paint the prominent fill unconditionally, the M18 defect shape" \
    "$SWIFT" 's|\.fill(tokens\.fill\.color)|.fill(ColorToken.accent.color)|'

echo "=== RESTORED ===  failures=$(fails)  exit=$(python3 "$SWEEP" >/dev/null 2>&1; echo $?)"
echo "  $MOCK  $(sha $MOCK)"
echo "  $STORE  $(sha $STORE)"
echo "  $SWIFT  $(sha $SWIFT)"
diff "$BASE_V" <(verdicts) >/dev/null && echo "  verdict table identical to baseline" || echo "  *** VERDICT TABLE DRIFTED ***"
git status --porcelain "$MOCK" "$STORE" "$SWIFT" | sed 's/^/  git: /'
rm -f "$BASE_V"
