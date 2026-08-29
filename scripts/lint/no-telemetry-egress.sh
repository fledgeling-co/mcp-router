#!/bin/bash
#
# F5 — nothing under the invocation-history directory may reach the network.
#
# The brief for F5 uses the word "telemetry", and the word hides a decision: telemetry that stays on
# the machine and telemetry that is shipped somewhere are the same feature to a reader and opposite
# products to the person whose sessions are being read. `planning/specs/spec-F5.md` §3 states the
# answer — three files under the router home, one read-only corpus, nothing sent — and this is what
# holds it true as the code changes.
#
# A prose promise in a spec is not a property of a program. The router's own posture is
# loopback-only and the owner keeps credentials in a broker rather than in config files; a `URLSession`
# added here in six months' time by someone wiring up "just a crash report" would contradict all of
# that and would read as ordinary Swift in review.
#
# Exit codes follow the house pattern used by no-wire-codable.sh:
#   0  clean
#   1  a refused symbol was found
#   2  the check could not run, or it examined nothing — which is not a pass
#
# The last clause is the point of `planning/null-run-gate.py`: a gate pointed at a directory that
# was renamed reports success over code it never read.

set -euo pipefail

cd "$(dirname "$0")/../.."

ROOT="${TELEMETRY_EGRESS_ROOT:-app/Sources/RouterCore/Invocations}"

if [[ ! -d "$ROOT" ]]; then
  echo "no-telemetry-egress: $ROOT does not exist" >&2
  exit 2
fi

# `mapfile` is bash 4 and this Makefile's SHELL is /bin/bash, which is 3.2 on macOS. A `while read`
# with a null-safe delimiter is the portable spelling, and it fails loudly rather than silently
# reading zero files the way an unavailable builtin does.
FILES=()
while IFS= read -r file; do
  FILES+=("$file")
done < <(find "$ROOT" -type f -name '*.swift' | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "no-telemetry-egress: examined 0 files under $ROOT; a gate that compared nothing is not a pass" >&2
  exit 2
fi

# Every name by which Swift on this platform reaches a remote host. `Socket` and `Network` are here
# as whole words so `NetworkExtension` and a variable called `socketPath` do not match, while an
# `import Network` does.
PATTERNS=(
  'URLSession'
  'URLRequest'
  'URLConnection'
  'NWConnection'
  'NWBrowser'
  'CFSocket'
  'dataTask'
  'downloadTask'
  'uploadTask'
  '^[[:space:]]*import[[:space:]]+Network[[:space:]]*$'
  '^[[:space:]]*import[[:space:]]+NetworkExtension[[:space:]]*$'
  'getaddrinfo'
  'https\?://'
)

fail=0
for pattern in "${PATTERNS[@]}"; do
  # -n for the line number so a finding is citable as path:line, which is what this repository's
  # citation rules ask of any gate's own output.
  if hits=$(grep -nE "$pattern" "${FILES[@]}" 2>/dev/null); then
    echo "no-telemetry-egress: refused symbol matching /$pattern/" >&2
    echo "$hits" >&2
    fail=1
  fi
done

# The zero this gate reports is the finding, so it is COUNTED rather than asserted. An earlier
# version printed the words "0 outbound-network symbols" without computing anything, which is the
# defect the whole repository's gate family is about: a sentence about a measurement, in the place a
# measurement belongs. `grep -c` over the same file set answers it, and the count is printed beside
# the population it was taken over so the number carries its own denominator.
matched=0
for pattern in "${PATTERNS[@]}"; do
  for file in "${FILES[@]}"; do
    hits=$(grep -cE "$pattern" "$file" 2>/dev/null || true)
    matched=$((matched + hits))
  done
done

if [[ $fail -eq 0 ]]; then
  if [[ $matched -ne 0 ]]; then
    echo "no-telemetry-egress: internal disagreement — the scan reported clean while the count" >&2
    echo "                    found $matched matching line(s). Neither figure can be trusted." >&2
    exit 2
  fi
  lines=$(cat "${FILES[@]}" | wc -l | tr -d ' ')
  echo "no-telemetry-egress: ${#FILES[@]} files, $lines lines under $ROOT; $matched matched any of ${#PATTERNS[@]} refused patterns"
fi
exit $fail
