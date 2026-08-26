#!/bin/bash
# The finish line, counted. Exit 0 only when every enumerated item is Done-or-parked.
# A row that is neither is the remaining work, and it is named rather than summarised.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
L=planning/features-to-triage/LEDGER.md
open=0
for id in G6 G8 G9 G10 M30 M31 M32 M33; do
  row=$(grep -E "^\| $id \|" "$L" | tail -1)
  if [ -z "$row" ]; then echo "worklist: $id has no ledger row"; open=$((open+1)); continue; fi
  # Done-and-merged, or deliberately parked, both terminal. Anything else is open.
  if printf '%s' "$row" | grep -qiE 'Verified DONE|MERGED to `main`|parked:|Held \(owner'; then
    continue
  fi
  echo "worklist: $id is still open"
  open=$((open+1))
done
echo "worklist: $open of 8 still open"
[ "$open" -eq 0 ]
