#!/bin/zsh
# Runs one codex gate, preserving its exit code (no pipe masking) and recording
# completion explicitly so a poller can tell "still running" from "finished".
set -u
STAGE="$1"; PROMPT_FILE="$2"; TIMEOUT="${3:-1500}"
OUT="/tmp/gate-R2-${STAGE}.md"
LOG="/tmp/gate-R2-${STAGE}.log"
DONE="/tmp/gate-R2-${STAGE}.done"
rm -f "$OUT" "$LOG" "$DONE"
REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo ".")"
cd "$REPO_ROOT" || exit 90
perl -e 'alarm shift @ARGV; exec @ARGV' "$TIMEOUT" \
  codex exec -m gpt-5.6-sol -c model_reasoning_effort="max" -s read-only \
  -o "$OUT" "$(cat "$PROMPT_FILE")" < /dev/null > "$LOG" 2>&1
echo "$?" > "$DONE"
