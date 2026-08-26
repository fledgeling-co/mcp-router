#!/usr/bin/env bash
# M31's presence control for MockButtonFidelityTests.
#
# Each arm plants one defect and watches ONE named test redden. The assertion is the set of failing
# test names against baseline, not a grep for the word "failed", and every file is checked back to
# its pre-plant sha256 — the previous version of this script claimed byte-identical restores in its
# commit message without ever comparing a hash.
#
# The sweep has its own control in arm-sweep.sh; this one covers the Swift assertions.
set -u
cd "$(git rev-parse --show-toplevel)"
MOCK=design/mcp-router-console.html
STORE=docs/mcp-router-store.html
DESIGN=DESIGN.md

sha(){ shasum -a 256 "$1" | cut -c1-16; }
failing(){ swift test --package-path app --filter MockButtonFidelityTests 2>&1 \
  | grep -oE 'Test "[^"]+" recorded an issue' | sort -u; }
count(){ swift test --package-path app --filter MockButtonFidelityTests 2>&1 \
  | grep -oE "with [0-9]+ test[s]? in 1 suite (passed|failed)" | tail -1; }

BASE=$(mktemp); failing > "$BASE"
echo "=== BASELINE ===  $(count)  failing tests: $(wc -l < "$BASE" | tr -d ' ')"
for f in "$MOCK" "$STORE" "$DESIGN"; do echo "  $f  $(sha "$f")"; done
echo

arm(){ # name  file  sed-expression
  local name="$1" file="$2" expr="$3" before after now
  before=$(sha "$file"); cp "$file" "/tmp/m31.guard.$$"
  sed -i '' "$expr" "$file"
  echo "ARM $name"
  if [ "$(sha "$file")" = "$before" ]; then
    echo "    VACUOUS — the plant did not apply; this arm proves nothing"
    cp "/tmp/m31.guard.$$" "$file"; rm -f "/tmp/m31.guard.$$"; return 1
  fi
  echo "    planted   $file  $before -> $(sha "$file")"
  now=$(mktemp); failing > "$now"
  echo "    $(count)"
  if diff "$BASE" "$now" | grep -q "^>"; then
    diff "$BASE" "$now" | grep "^>" | sed 's/^> /    reddened: /'
  else
    echo "    *** NO TEST REDDENED ***"
  fi
  rm -f "$now"
  cp "/tmp/m31.guard.$$" "$file"; rm -f "/tmp/m31.guard.$$"
  after=$(sha "$file")
  echo "    restored  $after  $([ "$after" = "$before" ] && echo IDENTICAL || echo '*** DIVERGED ***')"
  echo
}

arm "1 restore cursor:not-allowed (targets: declares no cursor, §3 rule 8)" \
    "$MOCK" 's|border-color:var(--line);}|border-color:var(--line);cursor:not-allowed;}|'

arm "2 add an unclaimed property to .btn.primary (targets: the cascade guard)" \
    "$MOCK" 's|^\.btn\.primary{background:var(--accent-ink);|.btn.primary{opacity:1;background:var(--accent-ink);|'

arm "3 perturb the ratio in DESIGN.md (targets: the design authority states the semantics)" \
    "$DESIGN" 's|2\.94:1 in dark|2.95:1 in dark|'

arm "4 drop the §3 generalisation (targets: the rule binds the fill, not the button)" \
    "$DESIGN" 's|\*\*Every control that resolves an accent fill|**Some controls that resolve an accent fill|'

arm "5 un-enumerate .tb-btn (targets: dims every control that resolves an accent fill)" \
    "$MOCK" 's|,\.tb-btn\.on\.disabled,\.tb-btn\.on:disabled{color|{color|'

arm "6 take the fill back off .trow.disabled (targets: the same test, row branch)" \
    "$MOCK" 's|\.trow\.disabled{color:var(--t4);background:var(--f3);}|.trow.disabled{color:var(--t4);}|'

arm "7 respell the switch rule for :disabled only (targets: the same test, switch branch)" \
    "$MOCK" 's|\.switch\.disabled,\.switch:disabled{background|.switch:disabled{background|'

arm "8 restore opacity dimming on the store page (targets: the store page test)" \
    "$STORE" 's|\.btn\[disabled\],\.btn\.disabled{background:var(--f3); color:var(--t4); border-color:var(--line); pointer-events:none}|.btn[disabled]{opacity:.45; cursor:not-allowed; pointer-events:none}|'

echo "=== RESTORED ===  $(count)"
for f in "$MOCK" "$STORE" "$DESIGN"; do echo "  $f  $(sha "$f")"; done
diff "$BASE" <(failing) >/dev/null && echo "  failing-test set identical to baseline" || echo "  *** DRIFTED ***"
git status --porcelain "$MOCK" "$STORE" "$DESIGN" | sed 's/^/  git: /'
rm -f "$BASE"
