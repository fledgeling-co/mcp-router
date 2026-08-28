#!/usr/bin/env bash
#
# R32 — can `r32-desktop-entry.sh` go red?
#
# The lane it drives asserts twenty things about a binary, and every one of them is an assertion
# about a *command that ran*. An assertion like that fails in only one interesting direction, and it
# is the direction nobody looks: a lane pointed at something that cannot do the thing still prints
# `ok` for every case it happens to phrase as an inequality. This repository has already published a
# green report from an instrument aimed at the wrong subject.
#
# So this drives the same lane against three stubs whose behaviour is known in advance, and requires
# it to go red for each — and against the real binary, and requires it to go green, because a
# harness that reddens on everything has proved nothing either.
#
# **Arm 3 is the one that matters.** The lane's central claim is that a dry run writes nothing, and
# a stub that quietly rewrites the fixture is exactly the defect that claim exists to catch. If the
# lane cannot see that stub, the sentence "the dry run leaves the file byte-identical" is decoration.
#
# Exit codes: 0 every arm held · 1 an arm did not hold · 2 the environment could not run one.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LANE="$REPO_ROOT/scripts/acceptance/r32-desktop-entry.sh"
REAL_CLI="$REPO_ROOT/app/.build/debug/MCPRouterCLI"
WORK="$(mktemp -d -t r32-lane-selftest)"
pass=0
fail=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM HUP

[ -x "$LANE" ] || { echo "environment: no lane at $LANE"; exit 2; }
[ -x "$REAL_CLI" ] || {
  echo "environment: no CLI at $REAL_CLI — run: make build-cli-debug"
  exit 2
}

ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }

# Run the lane against one CLI and report its exit status and transcript.
drive() {
  LANE_OUT="$(R32_CLI="$1" "$LANE" 2>&1)"
  LANE_RC=$?
}

echo "r32-desktop-entry-selftest: can the lane fail?"

# ---------------------------------------------------------------- arm 1 — a binary that never fails
cat > "$WORK/always-zero" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$WORK/always-zero"
drive "$WORK/always-zero"
if [ "$LANE_RC" -eq 1 ]; then
  ok "arm 1 — a binary that exits 0 for every refusal is caught (lane exit 1)"
else
  bad "arm 1 — the lane accepted a binary that refuses nothing (exit $LANE_RC)"
fi

# ---------------------------------------------------------------- arm 2 — a binary that always fails
cat > "$WORK/always-one" <<'SH'
#!/bin/sh
exit 1
SH
chmod +x "$WORK/always-one"
drive "$WORK/always-one"
if [ "$LANE_RC" -eq 1 ]; then
  ok "arm 2 — a binary that refuses everything is caught too (lane exit 1)"
else
  bad "arm 2 — the lane accepted a binary that can do nothing (exit $LANE_RC)"
fi

# ---------------------------------------------------------------- arm 3 — a dry run that writes
#
# Says all the right things and rewrites the fixture anyway. Everything the lane greps stdout for is
# present, so only the digest comparison can catch it — which is the point.
cat > "$WORK/writes-anyway" <<'SH'
#!/bin/sh
config=""
prev=""
for arg in "$@"; do
  [ "$prev" = "--config" ] && config="$arg"
  prev="$arg"
done
echo "NOT exercised"
echo '+      "command": "/x"'
[ -n "$config" ] && printf '{"mcpServers":{"sneaked":{}}}' > "$config"
exit 0
SH
chmod +x "$WORK/writes-anyway"
drive "$WORK/writes-anyway"
if [ "$LANE_RC" -eq 1 ] && printf '%s' "$LANE_OUT" | grep -q "byte-identical"; then
  ok "arm 3 — a dry run that writes is caught by the digest, not by the transcript"
else
  bad "arm 3 — a dry run that rewrote the fixture was not caught (exit $LANE_RC)"
fi

# ---------------------------------------------------------------- arm 4 — the real binary is green
#
# The presence control for arms 1-3. Without it a lane that returned 1 unconditionally would satisfy
# all three and this file would certify a harness that measures nothing.
drive "$REAL_CLI"
if [ "$LANE_RC" -eq 0 ]; then
  ok "arm 4 — the shipped binary passes, so arms 1-3 are about the stubs"
else
  bad "arm 4 — the lane is red against the real binary (exit $LANE_RC)"
  printf '%s\n' "$LANE_OUT" | sed 's/^/          /'
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "r32-desktop-entry-selftest: $pass arm(s) held"
  exit 0
fi
echo "r32-desktop-entry-selftest: $fail of $((pass + fail)) arm(s) did not hold"
exit 1
