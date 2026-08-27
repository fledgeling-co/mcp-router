#!/usr/bin/env bash
#
# P10 — the census of `planning/parity/surface.tsv`, derived from the file itself.
#
# It prints one number per line, tab-separated, and nothing else:
#
#     total   <n>
#     group   <group>  <n>
#
# **Why this exists.** The manifest used to carry its own size on line 3 as `# rows: N`, a number a
# person retyped whenever a row moved. `git log -L3,3` on that line shows it bumped five times, once
# per change that touched the file, and the fifth bump was already wrong when it was written:
# `ebe3165` set it to 95 against a file that already held 97. `b1160ef` inherited that, and from
# that merge onward `parity-manifest-check.sh` exited 1 on the UNMUTATED tree — which put
# `parity-manifest-selftest.sh` into its "NOT GREEN — every red below proves nothing" state and, in
# `make parity-selftest`, stopped the four selftests behind it from running at all.
#
# So the count is derived here and the *expectation* is hand-written where it is read. That is the
# split `destination-oracle.swift` landed for `mac-shell.sh` (M35) and `surface-oracle.swift` landed
# for the campaign's denominator (G18): derive what a thing IS from the thing itself, hand-write
# what it must DO. A derived count cannot go stale; a floor beside it can only be edited by somebody
# deliberately removing a row.
#
# **A count of zero is a broken oracle, never an empty surface.** Every consumer turns this into a
# comparison, and a zero would pass a floor of nothing while reporting a census that does not exist
# — the stale answer wearing the derivation's clothes, which is the failure this file is about.
#
# **A row that is not six fields is counted by nobody, and that is deliberately not this file's
# finding to report.** `NF == 6` is how every reader of this manifest selects rows, so a row with a
# missing tab is invisible to the count and to every reconciliation at once. `parity-manifest-check.sh`
# already names it, per line, as a problem and exits 1. Repeating the guard here would turn that
# named finding into this file's exit 2 — an environment failure where the tree has a real defect —
# so the census simply reports what the readers can see, and the check reports what they cannot.
#
# Exit codes follow the house pattern: 0 the census printed, 2 the census could not be taken. There
# is no exit 1 — this file measures and never judges. The judging is the caller's.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${PARITY_MANIFEST:-$REPO_ROOT/planning/parity/surface.tsv}"

[ -f "$MANIFEST" ] || { echo "environment: no manifest at $MANIFEST" >&2; exit 2; }

total="$(awk -F'\t' '!/^#/ && NF == 6' "$MANIFEST" | wc -l | tr -d ' ')"
if [ "$total" -eq 0 ]; then
  echo "environment: $MANIFEST yielded no rows. That is a broken reader or an emptied file, never" >&2
  echo "             a surface with nothing in it — this census has held rows since R4." >&2
  exit 2
fi

printf 'total\t%s\n' "$total"
awk -F'\t' '!/^#/ && NF == 6 { count[$1]++ } END { for (g in count) printf "group\t%s\t%d\n", g, count[g] }' \
  "$MANIFEST" | sort
