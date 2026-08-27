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

echo "parity-regen-selftest: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
