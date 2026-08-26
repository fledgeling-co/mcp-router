#!/bin/bash
# The finish line, counted. Exit 0 only when every enumerated item is Done-or-parked.
# A row that is neither is the remaining work, and it is named rather than summarised.
#
# ---------------------------------------------------------------------------------------------
# WHY THE MARKER MUST BE BOLD.
#
# The first version grepped the whole row, case-insensitively, for `Verified DONE|MERGED to
# `main`|parked:|Held (owner`. A ledger row's status and its narrative SHARE the last cell — that
# is a documented constraint of this file — so the narrative is several thousand characters of
# free prose, and any of those phrases can appear in it while discussing a DIFFERENT item.
#
# Measured 2026-08-26, on a row written that same day: the prose "`ai/g6` was merged to `main` at
# 03c34c3, so the clause is stale. This item is NOT done." TRIPPED the terminal test. The finish
# line could be crossed by narrative, in the gate whose whole job is deciding when to stop.
#
# The fix is that a verdict is bold and a mention is not. Every genuinely terminal row in this
# ledger writes its verdict bold (`**Verified DONE`, `**Merged `hash`**`); no narrative mention of
# another branch does. Both directions are armed in --selftest below and run on every invocation,
# because an unarmed absence sweep is what G8's sweep-control-gate exists to catch — and it caught
# this script's sibling.
# ---------------------------------------------------------------------------------------------
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2
L=planning/features-to-triage/LEDGER.md

# A terminal verdict: bold-delimited, at the start of a bold run.
TERMINAL='\*\*(Verified[[:space:]]*[—-]*[[:space:]]*DONE|Verified[[:space:]]*[—-]*[[:space:]]*Done|Merged `[0-9a-f]{6,}`|MERGED to `main`|parked:|Held \(owner)'

is_terminal() { printf '%s' "$1" | grep -qE "$TERMINAL"; }

# ---- presence control, both directions, every run ----
POS='| ZZ | t | b | — | — | **Verified DONE** (`outcome`) — merged `abc1234`. |'
NEG='| ZZ | t | b | — | — | Untriaged. Note: `ai/g6` was merged to `main` at 03c34c3, so the clause is stale. This item is NOT done. |'
ctl=0
is_terminal "$POS" || { echo "control: a real terminal verdict was NOT recognised"; ctl=1; }
is_terminal "$NEG" && { echo "control: narrative about ANOTHER branch counted as terminal"; ctl=1; }
if [ "$ctl" -ne 0 ]; then
  echo "worklist: CONTROL DID NOT FIRE — the classifier cannot tell a verdict from a mention."
  echo "worklist: INCONCLUSIVE, no count printed, because the count would be one this instrument cannot see."
  exit 2
fi
echo "worklist: control HELD (verdict recognised, mention rejected)"

open=0
for id in G6 G8 G9 G10 M30 M31 M32 M33; do
  row=$(grep -E "^\| $id \|" "$L" | tail -1)
  if [ -z "$row" ]; then echo "worklist: $id has no ledger row"; open=$((open+1)); continue; fi
  if is_terminal "$row"; then continue; fi
  echo "worklist: $id is still open"
  open=$((open+1))
done
echo "worklist: $open of 8 still open"
[ "$open" -eq 0 ]
