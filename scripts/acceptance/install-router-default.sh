#!/usr/bin/env bash
#
# R4-C, first half — which router `docs/install.sh` points the two launchd agents at.
#
# The installer's default moved from the TypeScript router to the Swift one. That is the change the
# owner licensed once parity read 82 of 83, and it is the change that decides what serves their own
# live Claude Code sessions, so it gets an assertion rather than a reading of the diff.
#
# **It extracts the decision out of install.sh and drives it; it never runs the installer.**
# `parity-install.sh` says why in its own header: running `docs/install.sh` would rewrite the
# user's `~/.claude.json` and bootstrap agents into their session. The same file already
# establishes the pattern — `install-claude-json` extracts the `node -e` body at run time and
# compares against that rather than a retyped copy. Three blocks are extracted here: the selector,
# the binary choice, and `program_args`.
#
# **An extraction that finds nothing must go red, not pass.** A stale anchor silently yields an
# empty block, every assertion then runs against a function that does not exist, and the lane
# reports a clean sweep of nothing — `examined=0` is a gate that never ran. Each block is therefore
# checked for a line count before it is evaluated.
#
# Exit codes: 0 every arm agreed, 1 an arm did not, 2 a block could not be extracted.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/docs/install.sh"
[ -f "$INSTALLER" ] || { echo "environment: no installer at $INSTALLER"; exit 2; }

extract() { awk "$1" "$INSTALLER"; }

# The bound is checked in THIS shell, never inside the command substitution that captured the
# block. The first version put the check inside `extract`, so its `exit 2` ended the subshell and
# the refusal text was captured into the variable it was refusing to fill — the script carried on
# and every arm then failed with a bash syntax error against an empty function. A red for the wrong
# reason is worth exactly as little as a green for the wrong reason, and this one was hiding a gate
# that could not stop itself.
require_block() { # variable-name description minimum-lines
  local n
  n="$(printf '%s\n' "${!1}" | grep -c . || true)"
  [ "$n" -ge "$3" ] && return 0
  echo "environment: extracted $n line(s) for $2, expected at least $3."
  echo "             The anchor in this lane no longer matches docs/install.sh. That is a"
  echo "             locator failure, not a pass: fix the anchor rather than lowering the bound."
  exit 2
}

SELECTOR="$(extract '/^MCPR_ROUTER="\$\{MCPR_ROUTER:-swift\}"$/,/^esac$/')"
require_block SELECTOR 'the router selector' 5
CHOICE="$(extract '/^ROUTER_BINARY=""$/,/^fi$/')"
require_block CHOICE 'the binary choice' 10
PROGRAM_ARGS="$(extract '/^program_args\(\) \{ # verb$/,/^\}$/')"
require_block PROGRAM_ARGS 'program_args' 8

pass=0
fail=0
note() { printf '  %-4s %-52s %s\n' "$1" "$2" "$3"; }
ok()   { pass=$((pass + 1)); note ok "$1" "$2"; }
bad()  { fail=$((fail + 1)); note FAIL "$1" "$2"; }

# One arm: evaluate the three extracted blocks with controlled inputs and print what the plist
# would carry for `serve`. `die` and `say` are stubbed — `die` exits 9 so a refusal is
# distinguishable from a shell error.
arm() { # env-assignments
  env -i PATH="$PATH" HOME="$HOME" FAKE_SWIFT_BIN="$FAKE_SWIFT_BIN" $1 bash -s <<INNER 2>&1
set -uo pipefail
say()  { :; }
die()  { printf 'DIED: %s\n' "\$1"; exit 9; }
NODE_BIN=/usr/bin/node
REPO_ROOT=/scratch/repo
SWIFT_BIN=\$FAKE_SWIFT_BIN
$SELECTOR
$CHOICE
$PROGRAM_ARGS
program_args serve | tr -d '\t' | tr '\n' ' '
INNER
}

# A real executable, because the installer checks for one — the fixture stands in for a release
# build without pretending a path that does not exist is a binary.
FAKE_SWIFT_BIN="$(mktemp -t MCPRouterCLI)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_SWIFT_BIN"
chmod +x "$FAKE_SWIFT_BIN"
trap 'rm -f "$FAKE_SWIFT_BIN"' EXIT

echo "install-router-default — what docs/install.sh points the agents at"
echo

SWIFT_ARGS="<string>$FAKE_SWIFT_BIN</string> <string>serve</string>"
NODE_ARGS='<string>/usr/bin/node</string> <string>/scratch/repo/dist/index.js</string> <string>serve</string>'

out="$(arm '')"
case "$out" in
  *"$SWIFT_ARGS"*) ok "the default is the Swift binary" "no MCPR_ROUTER set" ;;
  *) bad "the default is the Swift binary" "got: $out" ;;
esac

out="$(arm 'MCPR_ROUTER=node')"
case "$out" in
  *"$NODE_ARGS"*) ok "MCPR_ROUTER=node is the way back" "node dist/index.js serve" ;;
  *) bad "MCPR_ROUTER=node is the way back" "got: $out" ;;
esac

# The way back has to be reachable, and the way back is the only thing keeping this reversible.
out="$(arm 'MCPR_ROUTER=node')"
case "$out" in
  *"$FAKE_SWIFT_BIN"*) bad "MCPR_ROUTER=node names no Swift binary" "got: $out" ;;
  *) ok "MCPR_ROUTER=node names no Swift binary" "the fallback is not half-applied" ;;
esac

out="$(arm 'MCPR_ROUTER=bogus')"
case "$out" in
  DIED:*) ok "an unrecognised MCPR_ROUTER is refused" "${out%%$'\n'*}" ;;
  *) bad "an unrecognised MCPR_ROUTER is refused" "got: $out" ;;
esac

out="$(arm 'MCPR_ROUTER_BINARY=/bin/echo')"
case "$out" in
  *'<string>/bin/echo</string> <string>serve</string>'*)
    ok "MCPR_ROUTER_BINARY overrides the built path" "the install lanes drive this" ;;
  *) bad "MCPR_ROUTER_BINARY overrides the built path" "got: $out" ;;
esac

out="$(arm 'MCPR_ROUTER_BINARY=/no/such/binary')"
case "$out" in
  DIED:*) ok "a non-executable MCPR_ROUTER_BINARY is refused" "${out%%$'\n'*}" ;;
  *) bad "a non-executable MCPR_ROUTER_BINARY is refused" "got: $out" ;;
esac

echo
echo "$((pass + fail)) checks — examined=$((pass + fail)) failures=$fail"
[ "$fail" = 0 ] || exit 1
echo "the installer's default is Swift, and MCPR_ROUTER=node is one reinstall away."
