#!/usr/bin/env bash
#
# R32 — `mcp-router desktop-entry`, against a fixture, never against the machine's own Desktop.
#
# The lane exists because the item's two halves fail in opposite directions and only one of them
# looks like a failure. Writing the wrong entry is loud: Claude Desktop drops it and puts a dialog
# up. Writing when nobody asked is silent, and the file it would write to is the owner's.
#
# ## What it refuses to do
#
# It never reads or writes `~/Library/Application Support/Claude/claude_desktop_config.json`. Every
# case passes an explicit `--config` under `mktemp`, and the guard below refuses to run at all if
# the fixture path ever resolves inside `$HOME/Library` — a lane that could touch the real file
# once is a lane that will.
#
# It also never launches Claude Desktop. The reload half of this item is established by reading the
# shipped bundle (`planning/evidence/R32-acceptance.md`), and the one thing this lane asserts about
# it is that the verb *says* the change does not reach a running Desktop.
#
# ## The control, and why it is not optional
#
# Six of these seven cases assert an exit code, and an exit-code comparator that has been broken
# reports every case as held. So the lane runs its own comparator against a pair it knows disagrees
# and requires it to say so. A run where the control does not fire measured nothing, and exits 2
# rather than 0 — this repository has already paid for a green report from an instrument that was
# looking at the wrong thing.
#
# Exit codes: 0 every case held · 1 a case did not hold · 2 the environment or the control failed.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The binary under test. The override exists for `r32-desktop-entry-selftest.sh`, which drives this
# lane against stubs with known behaviour to prove its assertions can fail; it is not read in a
# normal run, and a lane whose assertions have never been watched failing is a lane that reports
# what it was pointed at rather than what happened.
CLI="${R32_CLI:-$REPO_ROOT/app/.build/debug/MCPRouterCLI}"
WORK="$(mktemp -d -t r32-desktop-entry)"
CONFIG="$WORK/claude_desktop_config.json"
BRIDGE="$WORK/bridge"
pass=0
fail=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM HUP

[ -x "$CLI" ] || {
  echo "environment: no CLI at $CLI — run: make build-cli-debug"
  exit 2
}
case "$WORK" in
  "$HOME"/Library/*|"$HOME"/.claude*)
    echo "environment: the fixture resolved inside the user's own configuration at $WORK"
    exit 2
    ;;
esac

ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }

# The comparator every case goes through, so the control below tests the same code the cases use.
same() {
  local what="$1" wanted="$2" got="$3"
  if [ "$wanted" = "$got" ]; then
    ok "$what"
    return 0
  fi
  bad "$what: expected [$wanted], got [$got]"
  return 1
}

fixture() {
  cat > "$CONFIG" <<'JSON'
{
  "mcpServers": {},
  "coworkUserFilesPath": "/u/Documents/Claude",
  "preferences": {
    "menuBarEnabled": false,
    "keepAwakeEnabled": true
  }
}
JSON
  chmod 600 "$CONFIG"
  rm -f "$CONFIG".bak-mcp-router-*
  printf '#!/bin/sh\nexec /usr/bin/true\n' > "$BRIDGE"
  chmod 755 "$BRIDGE"
}

# stdout+stderr and the status, kept together — every case here asserts on both.
run() {
  OUT="$("$CLI" desktop-entry "$@" 2>&1)"
  RC=$?
}

digest() { shasum "$1" | cut -d' ' -f1; }

echo "r32-desktop-entry: the registration half, on a fixture"

# ---------------------------------------------------------------- the control, run first
#
# Deliberately before the cases: a comparator that cannot report a mismatch would make every line
# below meaningless, and finding that out after printing seven `ok`s is finding it out too late.
control_pass=$pass
control_fail=$fail
same "control" "left" "right" >/dev/null
if [ "$fail" -eq $((control_fail + 1)) ] && [ "$pass" -eq "$control_pass" ]; then
  pass=$control_pass
  fail=$control_fail
  ok "control — the comparator reports a mismatch, so the cases below measured something"
else
  echo "  CONTROL DID NOT FIRE: the comparator accepted two different values."
  echo "  Nothing this run printed is evidence of anything."
  exit 2
fi

# ---------------------------------------------------------------- A1 — the machine's real state
#
# No bridge named, which is where this repository stands today: `mcp-router serve` speaks streamable
# HTTP and has no stdio mode, and Desktop's config takes a command rather than a url. The verb must
# say that rather than write something that loads and fronts nothing.
fixture
run --config "$CONFIG"
same "A1  no bridge is a refusal, not a write" "1" "$RC"
case "$OUT" in
  *"accepts a command to launch, never a url"*) ok "A1  the refusal names the schema, not a guess" ;;
  *) bad "A1  the refusal does not name Desktop's schema: $OUT" ;;
esac

# ---------------------------------------------------------------- A2 — a bare command name
#
# The false-positive install: a name that resolves on the developer's PATH and not in the
# environment Claude Desktop is launched with.
fixture
run --config "$CONFIG" --bridge mcp-remote
same "A2  a relative bridge command is refused" "1" "$RC"
case "$OUT" in
  *"does not inherit a shell's PATH"*) ok "A2  the refusal is about the launch environment" ;;
  *) bad "A2  the refusal does not explain why absolute: $OUT" ;;
esac

# ---------------------------------------------------------------- A3 — an absolute path that isn't
fixture
run --config "$CONFIG" --bridge "$WORK/not-here"
same "A3  an absolute path that is not executable is refused" "1" "$RC"

# ---------------------------------------------------------------- A4 — the dry run writes nothing
fixture
before="$(digest "$CONFIG")"
run --config "$CONFIG" --bridge "$BRIDGE" --bridge-arg "http://127.0.0.1:8879/mcp"
same "A4  a valid plan exits 0" "0" "$RC"
same "A4  the dry run leaves the file byte-identical" "$before" "$(digest "$CONFIG")"
case "$OUT" in
  *'+      "command": "'*) ok "A4  the diff shows the entry it would add" ;;
  *) bad "A4  no added entry in the diff: $OUT" ;;
esac
case "$OUT" in
  *"NOT exercised"*) ok "A4  the reload boundary is reported before anything is offered" ;;
  *) bad "A4  the dry run does not report the reload boundary: $OUT" ;;
esac

# ---------------------------------------------------------------- A5 — --apply, and only --apply
fixture
run --config "$CONFIG" --bridge "$BRIDGE" --bridge-arg "http://127.0.0.1:8879/mcp" --apply
same "A5  the apply exits 0" "0" "$RC"
same "A5  the mode is carried onto the replacement" "600" "$(stat -f '%Lp' "$CONFIG")"
same "A5  the entry is there" "1" \
  "$(grep -c '"mcp-router"' "$CONFIG")"
same "A5  the owner's own keys are still there" "1" \
  "$(grep -c '"coworkUserFilesPath"' "$CONFIG")"
backup="$(ls "$CONFIG".bak-mcp-router-* 2>/dev/null | head -1)"
if [ -n "$backup" ] && grep -q '"mcpServers": {}' "$backup"; then
  ok "A5  a backup holds the pre-image"
else
  bad "A5  no backup carrying the pre-image"
fi
case "$OUT" in
  *"Nothing here restarts it"*) ok "A5  the apply says the change does not reach a running Desktop" ;;
  *) bad "A5  the apply does not report the restart boundary: $OUT" ;;
esac

# ---------------------------------------------------------------- A6 — idempotent
run --config "$CONFIG" --bridge "$BRIDGE" --bridge-arg "http://127.0.0.1:8879/mcp"
same "A6  a second dry run finds nothing to do" "0" "$RC"
case "$OUT" in
  *"already there, byte for byte"*) ok "A6  and says so rather than offering an empty diff" ;;
  *) bad "A6  a no-op run does not say it is one: $OUT" ;;
esac

# ---------------------------------------------------------------- A7 — an mcpServers it must not eat
fixture
printf '{"mcpServers":[]}' > "$CONFIG"
run --config "$CONFIG" --bridge "$BRIDGE"
same "A7  a non-object mcpServers is refused rather than replaced" "1" "$RC"
same "A7  and the file is untouched" '{"mcpServers":[]}' "$(cat "$CONFIG")"

echo
if [ "$fail" -eq 0 ]; then
  echo "r32-desktop-entry: $pass case(s) held"
  exit 0
fi
echo "r32-desktop-entry: $fail of $((pass + fail)) case(s) did not hold"
exit 1
