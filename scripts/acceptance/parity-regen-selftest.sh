#!/usr/bin/env bash
#
# P9 — does parity-regen actually detect vector divergence?
#
# `make parity-regen` verifies that the committed vectors in
# app/Tests/RouterCoreTests/Vectors match what the TypeScript reference produces.
#
# This selftest exercises parity-regen under:
#   1. Clean reference and clean committed vectors (must PASS, exit 0).
#   2. Diverged vector file — value modified (must FAIL, exit 1).
#   3. Diverged vector file — missing vector (must FAIL, exit 1).
#   4. Diverged vector file — extra vector (must FAIL, exit 1).
#   5. Missing dist directory (must FAIL, exit 1).
#   6. Mutated *reference* — a colour changed in dist/auth.js (must FAIL, exit 1).
#   7. Reference stops exporting PAGE (must FAIL, exit 1).
#   8. Mutated *reference* — the registry row cap changed in dist/control.js (must FAIL, exit 1).
#
# Arms 6 and 7 are P9's gap-fix. Arms 1-5 all vary the *vectors* and hold the reference still,
# which is only half the question a regeneration check exists to answer: the verifier changed a
# colour in the built reference and `make parity-regen` still exited 0, because the auth-pages
# vector carried a hand-copied duplicate of the reference's page template instead of importing
# it. A vector that cannot see its own reference move is the defect this whole item was filed to
# close, so the control that would have caught it lives here rather than in a run log.
#
# Exit codes: 0 every case held · 1 a case did not hold · 2 environment error.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST="${MCP_ROUTER_DIST:-$REPO_ROOT/dist}"
VECTORS_DIR="$REPO_ROOT/app/Tests/RouterCoreTests/Vectors"

if [ ! -f "$DIST/config.js" ]; then
  echo "parity-regen-selftest: SKIPPED — no $DIST/config.js. This is a skip, not a pass:"
  echo "  run 'npm install && npm run build' and re-run 'make parity-selftest' to prove"
  echo "  vector regeneration works."
  exit 0
fi

WORK="$(mktemp -d -t parity-regen-selftest)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM HUP

pass=0
fail=0

run_regen() {
  local target_vectors="$1"
  local target_dist="${2:-$DIST}"
  local scratch="$WORK/scratch-$RANDOM-$RANDOM"
  mkdir -p "$scratch"

  if [ ! -f "$target_dist/config.js" ]; then
    return 1
  fi

  MCP_ROUTER_DIST="$target_dist" MCP_ROUTER_VECTORS="$scratch" \
    node "$REPO_ROOT/scripts/parity/generate-vectors.mjs" >/dev/null 2>&1 || return 1

  diff -ru "$target_vectors" "$scratch" >/dev/null 2>&1
  return $?
}

# Test 1: Clean vectors match
if run_regen "$VECTORS_DIR" "$DIST"; then
  pass=$((pass + 1))
  printf '  ok    clean vectors match reference exactly (exit 0)\n'
else
  fail=$((fail + 1))
  printf '  FAIL  clean vectors failed to match reference\n'
fi

# Test 2: Diverged vector value fails
TEST_DIR_2="$WORK/vectors-val-diverge"
cp -R "$VECTORS_DIR" "$TEST_DIR_2"
/usr/bin/python3 -c "
p = '$TEST_DIR_2/json-roundtrip.json'
with open(p, 'r') as f: c = f.read()
with open(p, 'w') as f: f.write(c.replace('\"empty-object\"', '\"empty-object-mutated\"'))
"
if ! run_regen "$TEST_DIR_2" "$DIST"; then
  pass=$((pass + 1))
  printf '  ok    mutated vector value is detected as divergence (exit != 0)\n'
else
  fail=$((fail + 1))
  printf '  FAIL  mutated vector value was not detected\n'
fi

# Test 3: Missing vector file fails
TEST_DIR_3="$WORK/vectors-missing-file"
cp -R "$VECTORS_DIR" "$TEST_DIR_3"
rm -f "$TEST_DIR_3/build-manifest.json"
if ! run_regen "$TEST_DIR_3" "$DIST"; then
  pass=$((pass + 1))
  printf '  ok    missing vector file is detected as divergence (exit != 0)\n'
else
  fail=$((fail + 1))
  printf '  FAIL  missing vector file was not detected\n'
fi

# Test 4: Extra vector file fails
TEST_DIR_4="$WORK/vectors-extra-file"
cp -R "$VECTORS_DIR" "$TEST_DIR_4"
echo '{"extra": true}' > "$TEST_DIR_4/extra-file.json"
if ! run_regen "$TEST_DIR_4" "$DIST"; then
  pass=$((pass + 1))
  printf '  ok    extra ungenerated vector file is detected as divergence (exit != 0)\n'
else
  fail=$((fail + 1))
  printf '  FAIL  extra vector file was not detected\n'
fi

# Test 5: Missing dist fails
if ! run_regen "$VECTORS_DIR" "$WORK/nonexistent-dist"; then
  pass=$((pass + 1))
  printf '  ok    missing dist is rejected (exit != 0)\n'
else
  fail=$((fail + 1))
  printf '  FAIL  missing dist was not rejected\n'
fi

# Test 6: A change in the REFERENCE is detected.
#
# The plant is a single hex digit in the callback page's background colour. It is applied to a
# copy of dist, never to the real one, and the substitution is asserted to have landed — an arm
# that silently fails to plant its fault reports a pass while measuring nothing.
DIST_6="$WORK/dist-reference-mutated"
cp -R "$DIST" "$DIST_6"
if /usr/bin/python3 -c "
import sys
p = '$DIST_6/auth.js'
s = open(p).read()
if s.count('#141220') != 1:
    sys.stderr.write('plant did not land: expected exactly 1 occurrence of #141220, found %d\\n' % s.count('#141220'))
    sys.exit(3)
open(p, 'w').write(s.replace('#141220', '#141221'))
"; then
  if ! run_regen "$VECTORS_DIR" "$DIST_6"; then
    pass=$((pass + 1))
    printf '  ok    a colour changed in the reference is detected as divergence (exit != 0)\n'
  else
    fail=$((fail + 1))
    printf '  FAIL  reference drift was NOT detected — the vector is a copy, not a derivation\n'
  fi
else
  fail=$((fail + 1))
  printf '  FAIL  could not plant the reference mutation; this arm measured nothing\n'
fi

# Test 7: The reference ceasing to export PAGE is refused, not worked around.
#
# This guards the mechanism rather than the bytes. Arm 6 goes green again the moment someone
# reintroduces an inline copy of the template, so the generator asserts that it imported PAGE and
# this arm proves that assertion fires.
DIST_7="$WORK/dist-page-unexported"
cp -R "$DIST" "$DIST_7"
if /usr/bin/python3 -c "
import sys
p = '$DIST_7/auth.js'
s = open(p).read()
if s.count('export const PAGE') != 1:
    sys.stderr.write('plant did not land: expected exactly 1 \'export const PAGE\', found %d\\n' % s.count('export const PAGE'))
    sys.exit(3)
open(p, 'w').write(s.replace('export const PAGE', 'const PAGE'))
"; then
  if ! run_regen "$VECTORS_DIR" "$DIST_7"; then
    pass=$((pass + 1))
    printf '  ok    reference no longer exporting PAGE is refused (exit != 0)\n'
  else
    fail=$((fail + 1))
    printf '  FAIL  generator produced auth-pages without importing PAGE from the reference\n'
  fi
else
  fail=$((fail + 1))
  printf '  FAIL  could not plant the un-export; this arm measured nothing\n'
fi

# Test 8: A change in a SECOND reference module is detected.
#
# Arm 6 covers dist/auth.js. This covers dist/control.js, because the audit that followed P9's
# gap-fix found `registry-limit` in the same state auth-pages was in — its expectation was a
# re-typed copy of `Math.min(Number(x ?? 30) || 30, 60)` rather than a call into the reference,
# and unlike the comparator vectors it had no reference-driven vector covering the same code. The
# plant raises the cap, which is the edit a person would actually make.
DIST_8="$WORK/dist-cap-mutated"
cp -R "$DIST" "$DIST_8"
if /usr/bin/python3 -c "
import sys
p = '$DIST_8/control.js'
s = open(p).read()
old = 'Math.min(Number(raw ?? 30) || 30, 60)'
if s.count(old) != 1:
    sys.stderr.write('plant did not land: expected exactly 1 registry cap, found %d\\n' % s.count(old))
    sys.exit(3)
open(p, 'w').write(s.replace(old, 'Math.min(Number(raw ?? 30) || 30, 100)'))
"; then
  if ! run_regen "$VECTORS_DIR" "$DIST_8"; then
    pass=$((pass + 1))
    printf '  ok    the registry cap changed in the reference is detected as divergence (exit != 0)\n'
  else
    fail=$((fail + 1))
    printf '  FAIL  registry cap drift was NOT detected — the vector re-types the formula\n'
  fi
else
  fail=$((fail + 1))
  printf '  FAIL  could not plant the registry cap mutation; this arm measured nothing\n'
fi

echo "parity-regen-selftest: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
