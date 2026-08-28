#!/bin/bash
#
# P7 — nothing on a path that reaches the wire may use Foundation's JSON stack or a Swift
# Dictionary.
#
# The review of this item's plan defeated its byte-contract clauses (S3, S4, S5) nine times, and
# every single time the mechanism was the same: a reasonable Swift default. `JSONEncoder` sorts or
# reorders members, `Codable` rejects shapes the reference stores, and `[String: …]` loses both the
# member order that is on the wire and the code-unit key identity that decides which server a
# request is about. None of those looks wrong in review — that is the whole problem, and it is why
# this is a mechanical gate rather than a note in a document.
#
# Two classes of finding, treated differently on purpose:
#
#   * `JSONSerialization`, `JSONEncoder`, `JSONDecoder` and a `Codable`/`Encodable`/`Decodable`
#     conformance are refused outright. There is no legitimate use of them under these directories;
#     `JSONValue` + `JSStringify` + `JSONParser` exist precisely to replace them.
#   * `[String: …]` is refused *unless* the line carries an explicit exemption, because a local
#     accumulator inside a function is genuinely fine while a stored property is not, and no grep
#     can tell those apart. Requiring the author to write the reason down is the point: the failure
#     mode being guarded against is reaching for a dictionary without noticing, and an exemption
#     cannot be added without noticing.
#
# Exemption syntax, on the offending line or the line immediately above it:
#
#     // swift-wire-exempt: <why this one cannot reach the wire>
#
# Exit codes follow the house pattern: 1 is a violation, 2 is an environment that could not run the
# check. Collapsing them would report "ripgrep is missing" as "the code is broken".

set -euo pipefail

cd "$(dirname "$0")/../.."

ROOT="app/Sources/RouterCore"
DIRS=(Control Registry Usage Auth Extensions Caches)
EXEMPT_MARKER='swift-wire-exempt:'

# Auth/ does not exist yet — it is R5's. A missing directory is not a failure, but a directory that
# is silently never scanned is: the gate would report success over code it never read. So each one
# is reported by name with what it found.
#
# Extensions/ joined with R28. It is enrolled for the reason the list exists rather than because
# every file in it serialises: `DiskExtensionStore` reads two JSON descriptors off disk and every
# value it lifts out of them reaches `GET /extensions` unaltered, so `JSONSerialization` there
# would decide member order on the wire from inside a type nobody would think of as a wire type.
# Caches/ joined with R31, and for the same reason one step further out: `DiskCacheProbe` reads
# npm's and Claude's own `package.json` files off disk, and the package names and versions it lifts
# out of them reach `GET /caches` as the `refetch` command a person is about to run.
#
# A directory that produces wire bytes and is not on this list is outside the rule with nothing
# saying so — the same silent-scope failure `no-raw-design-values.sh` records for GEOMETRY_DIRS.
present=()
for d in "${DIRS[@]}"; do
  [ -d "$ROOT/$d" ] && present+=("$ROOT/$d")
done

if [ ${#present[@]} -eq 0 ]; then
  echo "error: none of ${DIRS[*]} exist under $ROOT — this gate scanned nothing, which is not a pass" >&2
  exit 2
fi

status=0

report() {
  # $1 = human description, $2 = file, $3 = line number, $4 = the line
  printf '%s\n  %s:%s\n  %s\n\n' "$1" "$2" "$3" "$(printf '%s' "$4" | sed 's/^[[:space:]]*//')" >&2
}

# ---------------------------------------------------------------- hard refusals

# Matched on code only: a mention inside a doc comment explaining why the thing is banned must not
# fail the gate that bans it. Comment-only lines are dropped first.
while IFS=: read -r file line text; do
  [ -z "${file:-}" ] && continue
  report "error: Foundation's JSON stack cannot produce the reference's byte order (S3, S4)." \
    "$file" "$line" "$text"
  status=1
done < <(
  grep -rnE 'JSONSerialization|JSONEncoder|JSONDecoder' "${present[@]}" --include='*.swift' \
    | grep -vE ':[0-9]+:[[:space:]]*(//|///|\*)' || true
)

while IFS=: read -r file line text; do
  [ -z "${file:-}" ] && continue
  report "error: a Codable conformance validates shapes the reference stores verbatim (B42, B44)." \
    "$file" "$line" "$text"
  status=1
done < <(
  grep -rnE '^[[:space:]]*(public |internal |private |fileprivate )?(struct|enum|class|extension)[^:]*:[^{]*\b(Codable|Encodable|Decodable)\b' \
    "${present[@]}" --include='*.swift' \
    | grep -vE ':[0-9]+:[[:space:]]*(//|///|\*)' || true
)

# ---------------------------------------------------------------- exemptible

# `[String:` in any position. Checked against the same line and the one above for an exemption.
while IFS=: read -r file line text; do
  [ -z "${file:-}" ] && continue
  if printf '%s' "$text" | grep -q "$EXEMPT_MARKER"; then continue; fi
  prev=$((line - 1))
  if [ "$prev" -ge 1 ] && sed -n "${prev}p" "$file" | grep -q "$EXEMPT_MARKER"; then continue; fi
  report "error: a Swift Dictionary loses member order and code-unit key identity (S4, S5, B24).
       If this one cannot reach the wire, say so with: // $EXEMPT_MARKER <reason>" \
    "$file" "$line" "$text"
  status=1
done < <(
  grep -rnE '\[String[[:space:]]*:' "${present[@]}" --include='*.swift' \
    | grep -vE ':[0-9]+:[[:space:]]*(//|///|\*)' || true
)

if [ "$status" -eq 0 ]; then
  echo "no-wire-codable: clean over ${present[*]}"
  for d in "${DIRS[@]}"; do
    [ -d "$ROOT/$d" ] || echo "no-wire-codable: $ROOT/$d does not exist yet (R5 owns Auth/)"
  done
  exemptions=$(grep -rn "$EXEMPT_MARKER" "${present[@]}" --include='*.swift' | wc -l | tr -d ' ')
  echo "no-wire-codable: $exemptions exemption(s) recorded"
fi

exit "$status"
