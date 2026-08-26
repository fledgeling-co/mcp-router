#!/bin/bash
# Install the tracked fleet hooks into .git/hooks, or check the installed copies against them.
#
#   planning/hooks/install.sh           install, then report each sha256
#   planning/hooks/install.sh --check   report drift only; exit 1 if any copy differs or is absent
#
# `.git/hooks` is not tracked, so the tracked files here are the source of record and the
# installed copies are derived state that can drift from them without anything going red. That is
# the same shape as the defect this item exists for (G9): a control that is believed armed, and
# nothing checks. `--check` is the thing that was missing — the README's `cp` line told a fresh
# clone how to install and gave it no way to find out afterwards whether it had worked.
#
# The repository root is derived, never pinned.
#
# `.git/hooks` is shared by every linked worktree, so installing from inside one changes the
# controls under every runner in flight. Run this from the orchestrating session.

set -u
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel) || { echo "FATAL: not in a checkout"; exit 2; }
SRC="$ROOT/planning/hooks"
DEST=$(git -C "$ROOT" rev-parse --git-common-dir)/hooks
case "$DEST" in /*) ;; *) DEST="$ROOT/$DEST" ;; esac

mode=install
[ "${1-}" = "--check" ] && mode=check

mkdir -p "$DEST"
rc=0
for h in pre-commit pre-push; do
    s="$SRC/$h"; d="$DEST/$h"
    [ -f "$s" ] || { echo "FATAL: no tracked hook at planning/hooks/$h"; exit 2; }
    if [ "$mode" = install ]; then install -m 0755 "$s" "$d"; fi
    if [ ! -f "$d" ]; then printf '  %-12s ABSENT      (tracked %s)\n' "$h" "$(shasum -a 256 "$s" | cut -c1-12)"; rc=1; continue; fi
    ss=$(shasum -a 256 "$s" | cut -d' ' -f1); ds=$(shasum -a 256 "$d" | cut -d' ' -f1)
    if [ "$ss" = "$ds" ]; then
        x=$([ -x "$d" ] && echo "" || echo "  NOT EXECUTABLE"); [ -n "$x" ] && rc=1
        printf '  %-12s in sync     %s%s\n' "$h" "${ss:0:12}" "$x"
    else
        printf '  %-12s DRIFTED     tracked %s  installed %s\n' "$h" "${ss:0:12}" "${ds:0:12}"; rc=1
    fi
done
echo "  hooks dir: $DEST"
[ "$mode" = check ] && [ $rc -ne 0 ] && echo "  the installed hooks do not match the tracked source — run planning/hooks/install.sh"
exit $rc
