#!/usr/bin/env bash
#
# The mutation gate — plan P6's last requirement, and the one that decides whether the parity corpus
# is evidence or decoration.
#
# A vector that is present, unique, and compared still proves nothing unless breaking the behaviour
# it guards makes it fail. The registry tests can establish the first three; only this can establish
# the fourth. So for each named adversarial input (N1-N13) and each observable divergence (D1, D3,
# D4), this breaks exactly that behaviour in the source, requires the parity gate to go RED, and
# restores.
#
# Three outcomes, deliberately distinguished:
#
#   · the parity gate goes red      -> the vector is load-bearing. Pass.
#   · the parity gate stays green   -> the vector is a DECORATION. It is present and compared and
#                                      it does not constrain the implementation. Reported by name.
#   · the edit did not apply        -> a FAILURE, never a pass. A mutation whose pattern has drifted
#                                      away from the source leaves the tree unmutated, the gate green,
#                                      and would otherwise be reported as a decorative vector — an
#                                      accusation against the corpus for a defect in this script.
#
# Slow by construction: each mutation is a rebuild plus a test run. Kept out of `make all` for that
# reason and run before a merge, not on every save.
#
# Usage:  scripts/parity/mutation-gate.sh [id ...]
#         with no arguments, every mutation runs.

set -Eeuo pipefail

cd "$(dirname "$0")/../.."
readonly ROOT="$PWD"
readonly SRC="app/Sources/RouterCore"

# id | file | perl search pattern | replacement | what the mutation does
#
# Each search pattern must match exactly once. The replacement expresses the *plausible wrong
# implementation* — the one a careful port reaches for — rather than arbitrary damage, because a
# vector that only catches nonsense is not catching anything a real port would do.
MUTATIONS=$(cat <<'TABLE'
N1|JSON/JSString.swift|static func < (lhs: JSString, rhs: JSString) -> Bool {|static func < (lhs: JSString, rhs: JSString) -> Bool { return lhs.string < rhs.string } private static func unusedOriginal(lhs: JSString, rhs: JSString) -> Bool {|order env/header keys by Unicode scalar (Swift's default) instead of UTF-16 code unit
N2|Config/UpstreamHash.swift|upstream.raw.member("args") ?? .array([]),|.array((upstream.raw.member("args")?.asArray ?? []).sorted { ($0.asString?.string ?? "") < ($1.asString?.string ?? "") }),|sort args before hashing, so ["z","a"] and ["a","z"] collide
N3|Config/ConfigLoader.swift|port: options.port ?? intMember(raw, "port")|port: options.port.flatMap { $0 == 0 ? nil : $0 } ?? intMember(raw, "port")|make option precedence truthy, so an explicit port 0 falls through to the file
N4|Manifest/ToolUnion.swift|                index = start\n                break|                index = start|split the tool name at the LAST separator instead of the first
N5|Manifest/ToolUnion.swift|cwd == project \|\| cwd.hasPrefix(project.hasSuffix("/") ? project : "\\(project)/")|cwd == project \|\| cwd.hasPrefix(project)|drop the separator requirement, so /a/b matches /a/bc
N6|Manifest/ToolsDigest.swift|case .orderedSame: lhs.index < rhs.index|case .orderedSame: lhs.index > rhs.index|reverse arrival order for equal-named tools, so the sort is no longer stable
N7|Manifest/ToolsDigest.swift|private static func material(for tool: CachedTool) -> JSONValue {|private static func material(for tool: CachedTool) -> JSONValue { return sortedDeep(materialOriginal(for: tool)) } private static func sortedDeep(_ v: JSONValue) -> JSONValue { if case let .object(m) = v { return .object(m.sorted { $0.key < $1.key }.map { JSONMember(key: $0.key, value: sortedDeep($0.value)) }) }; if case let .array(a) = v { return .array(a.map(sortedDeep)) }; return v } private static func materialOriginal(for tool: CachedTool) -> JSONValue {|sort schema members before hashing, so member order stops being significant
N8|Manifest/ManifestBookkeeping.swift|            entry.set("tools", .array(\[\]))\n            entry.set("error", .string(JSString(message)))|            entry.set("error", .string(JSString(message)))|stop destroying the approved tools on an indexing failure
N9|Config/ServerParser.swift|return url.port == String(port)|return url.port.isEmpty ? (port == 80 \|\| port == 443) : url.port == String(port)|resolve the effective default port instead of comparing what the URL reports
N10|JSON/JSString.swift|guard !units.isEmpty, units.count <= 10 else { return nil }|guard false else { return nil }|stop classifying integer-like keys as array indices, losing JS enumeration order
N11|Manifest/DiffTools.swift|0x2060 ... 0x2064, // WORD JOINER through INVISIBLE PLUS|0x2060 ... 0x2069, // WORD JOINER through INVISIBLE PLUS|widen the invisible range to include U+2066, which the reference does not report
N12|Config/ServerParser.swift|guard JSURL(text) != nil else {|guard let probe = JSURL(text), probe.scheme == "http" \|\| probe.scheme == "https" else {|validate the URL by scheme instead of by parseability, rejecting ftp://
N13|Config/ServerParser.swift|upstream.transport = typeName == "sse" ? .sse : .http|upstream.transport = .http|collapse sse into http, losing the transport's own identity
D1|Config/ConfigLoader.swift|        guard let servers = raw.member("mcpServers") else {\n            throw ConfigProblem.unrecognisedShape(path: path, found: .missingKey)\n        }|        let servers = raw.member("mcpServers") ?? .object([])|load zero servers silently where the divergence requires a named error
D3|Config/ConfigWriter.swift|        if let existingMembers = existingTopLevel(path: path, fileSystem: fileSystem) {\n            members = existingMembers|        if false, let existingMembers = existingTopLevel(path: path, fileSystem: fileSystem) {\n            members = existingMembers|stop preserving top-level keys the writer did not set
D4|Log/RouterLog.swift|try? fileSystem.createDirectory(atPath: (file as NSString).deletingLastPathComponent)|try! fileSystem.createDirectory(atPath: (file as NSString).deletingLastPathComponent)|let a directory-creation failure escape, which the divergence contains
TABLE
)

# ---------------------------------------------------------------------------------------------

want=("$@")
wanted() {
  [ ${#want[@]} -eq 0 ] && return 0
  local id
  for id in "${want[@]}"; do [ "$id" = "$1" ] && return 0; done
  return 1
}

restore() { git -C "$ROOT" checkout -- "$SRC" 2>/dev/null || true; }
trap 'restore' EXIT

# A dirty tree would be silently reverted by the restore, which is a good way to lose work.
if ! git -C "$ROOT" diff --quiet -- "$SRC"; then
  echo "error: $SRC has uncommitted changes. This script reverts it after every mutation and"
  echo "       would destroy them. Commit or stash first."
  exit 1
fi

echo "Baseline: the gate must be green before any mutation means anything."
if ! make parity >/tmp/mutation-baseline.log 2>&1; then
  echo "error: the parity gate is already red. Nothing below would be interpretable."
  tail -20 /tmp/mutation-baseline.log
  exit 1
fi
echo "  $(grep -oE 'parity: .*' /tmp/mutation-baseline.log | tail -1)"
echo

declare -a decorations=() misapplied=() held=()

while IFS='|' read -r id file pattern replacement description; do
  [ -z "${id:-}" ] && continue
  wanted "$id" || continue

  printf '%-4s %-44s ' "$id" "$description"

  target="$SRC/$file"
  before=$(shasum "$target" | cut -d' ' -f1)
  # -0777 so a pattern may span lines; \Q…\E is not used because the patterns carry deliberate
  # regex (\n), so each pattern above escapes its own metacharacters.
  PATTERN="$pattern" REPLACEMENT="$replacement" perl -0777 -i -pe '
    my $p = $ENV{PATTERN}; my $r = $ENV{REPLACEMENT};
    $r =~ s/\\n/\n/g; $p =~ s/\\n/\n/g;
    s/\Q$p\E/$r/;
  ' "$target"
  after=$(shasum "$target" | cut -d' ' -f1)

  if [ "$before" = "$after" ]; then
    echo "MUTATION DID NOT APPLY — pattern has drifted from the source"
    misapplied+=("$id")
    restore
    continue
  fi

  if make parity >"/tmp/mutation-$id.log" 2>&1; then
    echo "STAYED GREEN — decoration"
    decorations+=("$id")
  else
    echo "red"
    held+=("$id")
  fi
  restore
done <<< "$MUTATIONS"

echo
echo "Held (breaking the behaviour turned the gate red): ${#held[@]} — ${held[*]:-none}"

status=0
if [ ${#misapplied[@]} -gt 0 ]; then
  echo
  echo "error: ${#misapplied[@]} mutation(s) did not apply: ${misapplied[*]}"
  echo "       This is a defect in this script, not in the corpus — the source moved under a"
  echo "       pattern. Those vectors are UNPROVEN, not decorative."
  status=1
fi
if [ ${#decorations[@]} -gt 0 ]; then
  echo
  echo "error: ${#decorations[@]} vector(s) are decorations: ${decorations[*]}"
  echo "       The behaviour was broken and the parity gate still passed, so nothing in the"
  echo "       corpus constrains it."
  status=1
fi
[ $status -eq 0 ] && echo "Every named behaviour is load-bearing."
exit $status
