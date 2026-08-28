#!/usr/bin/env bash
# M31's presence control for `theMockDimsTheUnfilledVariants` in MockButtonFidelityTests.
#
# The assertion it arms was added because M31's sweep could not see this defect: the sweep resolves
# every rule painting `var(--accent-ink)`, and `.btn.destructive` paints `--fail-ink` while
# `.btn.quiet` paints `--accent-text`, so neither was ever in its denominator. Both drew as though
# enabled while disabled and no instrument in the repo was looking.
#
# Each arm plants a defect that was real on this file, and arm 4 is the one that matters: it was
# added *after* an earlier arm 4 turned out to be a bad arm rather than a hole. That arm re-declared
# `.btn.quiet` after the disabled rule — the mechanism by which the original defect arrived — and
# the test correctly stayed green, because the fix here is specificity (0-3-0 over 0-2-0) rather
# than order, and the renderer agreed: `DISA fg=rgb(154,154,162)`, still dimmed. `!important` is
# what actually defeats specificity, and planting it rendered `LIVE fg=rgb(0,96,196)
# DISA fg=rgb(0,96,196)` — the M31 defect exactly — while the test stayed green. That was a real
# hole, and the `!important` assertion closes it. A plant that does not go red is a question about
# which of the two is wrong; here it was the arm once and the guard once.
#
# Restores are sha256-verified, and a plant that does not go red prints so rather than passing.
set -u
cd "$(git rev-parse --show-toplevel)"
F=design/mcp-router-console.html
sha(){ shasum -a 256 "$1" | cut -d' ' -f1; }
issues(){ swift test --package-path app --filter theMockDimsTheUnfilledVariants 2>&1 \
  | grep -cE "✘|recorded an issue"; }

cp "$F" "/tmp/m31-unfilled.bak.$$"; BASE=$(sha "$F"); RC=0
B=$(issues); echo "baseline issues=$B"; [ "$B" -eq 0 ] || { echo "*** BASELINE NOT GREEN ***"; RC=1; }

arm(){ # name  perl-expr
  perl -i -pe "$2" "$F"
  local i; i=$(issues)
  if [ "$i" -gt 0 ]; then echo "ARM $1: RED (issue lines=$i)"; else echo "ARM $1: *** DID NOT GO RED ***"; RC=1; fi
  cp "/tmp/m31-unfilled.bak.$$" "$F"
  if [ "$(sha "$F")" = "$BASE" ]; then echo "  restored byte-identical"; else echo "  *** RESTORE MISMATCH ***"; RC=1; fi
}

# 1 — the pre-fix state: the whole rule gone, both variants draw their live label while disabled.
arm "rule-deleted" 's/^\.btn\.destructive:disabled,\.btn\.destructive\.disabled,\.btn\.quiet:disabled,\.btn\.quiet\.disabled\{color:var\(--t4\);\}\n$//'
# 2 — half a fix: destructive covered, quiet left behind. This is how the primary defect survived
#     its first pass, one spelling at a time.
arm "quiet-dropped" 's/^\.btn\.destructive:disabled,\.btn\.destructive\.disabled,\.btn\.quiet:disabled,\.btn\.quiet\.disabled\{/.btn.destructive:disabled,.btn.destructive.disabled{/'
# 3 — a rule that exists and dims to a live tier: --t2 is body text, not the disabled tier.
arm "wrong-tier" 's/(\.btn\.quiet\.disabled\{color:var\()--t4(\);\})/${1}--t2${2}/'
# 4 — the escalation that beats specificity, and the hole this control found.
arm "important-escalation" 's/^\.btn\.quiet\{background:none;border-color:transparent;box-shadow:none;color:var\(--accent-text\);\}$/.btn.quiet{background:none;border-color:transparent;box-shadow:none;color:var(--accent-text) !important;}/'

rm -f "/tmp/m31-unfilled.bak.$$"
echo "arm-unfilled-variants: exit $RC"
exit $RC
