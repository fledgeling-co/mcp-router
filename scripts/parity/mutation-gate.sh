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

# id @@ file @@ perl search pattern @@ replacement @@ what the mutation does
#
# Fields are separated by `@@`, not `|`: half these patterns contain Swift's `||`, and a single-pipe
# separator silently truncated two of them into an unrunnable mutation that then read as a defect in
# the corpus rather than in this table.
#
# Each search pattern must match exactly once. The replacement expresses the *plausible wrong
# implementation* — the one a careful port reaches for — rather than arbitrary damage, because a
# vector that only catches nonsense is not catching anything a real port would do.
MUTATIONS=$(cat <<'TABLE'
N1@@JSON/JSString.swift@@static func < (lhs: JSString, rhs: JSString) -> Bool {@@static func < (lhs: JSString, rhs: JSString) -> Bool { return lhs.string < rhs.string } private static func unusedOriginal(lhs: JSString, rhs: JSString) -> Bool {@@order env/header keys by Unicode scalar instead of UTF-16 code unit
N2@@Config/UpstreamHash.swift@@upstream.raw.member("args") ?? .array([]),@@.array((upstream.raw.member("args")?.asArray ?? []).sorted { ($0.asString?.string ?? "") < ($1.asString?.string ?? "") }),@@sort args before hashing, so ["z","a"] and ["a","z"] collide
N3@@Config/ConfigLoader.swift@@port: options.port ?? intMember(raw, "port")@@port: options.port.flatMap { $0 == 0 ? nil : $0 } ?? intMember(raw, "port")@@make option precedence truthy, so an explicit port 0 falls through
N4@@Manifest/ToolUnion.swift@@                index = start\n                break@@                index = start@@split the tool name at the LAST separator instead of the first
N5@@Manifest/ToolUnion.swift@@cwd == project || cwd.hasPrefix(project.hasSuffix("/") ? project : "\(project)/")@@cwd.hasPrefix(project)@@drop the separator requirement, so /a/b matches /a/bc
N6@@Manifest/ToolsDigest.swift@@case .orderedSame: lhs.index < rhs.index@@case .orderedSame: lhs.index > rhs.index@@reverse arrival order for equal-named tools, unstabilising the sort
N7@@Manifest/ToolsDigest.swift@@private static func material(for tool: CachedTool) -> JSONValue {@@private static func material(for tool: CachedTool) -> JSONValue { return sortedDeep(materialOriginal(for: tool)) } private static func sortedDeep(_ v: JSONValue) -> JSONValue { if case let .object(m) = v { return .object(m.sorted { $0.key < $1.key }.map { JSONMember(key: $0.key, value: sortedDeep($0.value)) }) }; if case let .array(a) = v { return .array(a.map(sortedDeep)) }; return v } private static func materialOriginal(for tool: CachedTool) -> JSONValue {@@sort schema members before hashing, so member order stops mattering
N8@@Manifest/ManifestBookkeeping.swift@@            entry.set("tools", .array([]))\n@@@@stop destroying the approved tools on an indexing failure
N9@@Config/ServerParser.swift@@return url.port == String(port)@@return url.port.isEmpty ? (port == 80 || port == 443) : url.port == String(port)@@resolve the effective default port instead of what the URL reports
N10@@JSON/JSString.swift@@guard !units.isEmpty, units.count <= 10 else { return nil }@@guard false else { return nil }@@stop classifying integer-like keys as array indices, losing JS order
N11@@Manifest/DiffTools.swift@@0x2060 ... 0x2064, // WORD JOINER through INVISIBLE PLUS@@0x2060 ... 0x2069, // WORD JOINER through INVISIBLE PLUS@@widen the invisible range to U+2066, which the reference never reports
N12@@Config/ServerParser.swift@@guard JSURL(text) != nil else {@@guard let probe = JSURL(text), probe.scheme == "http" || probe.scheme == "https" else {@@validate the URL by scheme instead of parseability, rejecting ftp://
N13@@Config/ServerParser.swift@@upstream.transport = typeName == "sse" ? .sse : .http@@upstream.transport = .http@@collapse sse into http, losing the transport's own identity
D1@@Config/ConfigLoader.swift@@        guard let servers = raw.member("mcpServers") else {\n            throw ConfigProblem.unrecognisedShape(path: path, found: .missingKey)\n        }@@        let servers = raw.member("mcpServers") ?? .object([])@@load zero servers silently where the divergence requires a named error
D3@@Config/ConfigWriter.swift@@        if let existingMembers = existingTopLevel(path: path, fileSystem: fileSystem) {@@        if false, let existingMembers = existingTopLevel(path: path, fileSystem: fileSystem) {@@stop preserving top-level keys the writer did not set
D4@@Log/RouterLog.swift@@try? fileSystem.createDirectory(atPath: (file as NSString).deletingLastPathComponent)@@try! fileSystem.createDirectory(atPath: (file as NSString).deletingLastPathComponent)@@let a directory-creation failure escape, which the divergence contains
R1@@Usage/UsageStore.swift@@        let effective = limit ?? 200\n        var start = -effective@@        let effective = limit ?? 200\n        if !effective.isNaN, effective >= 0, effective < 1e9 { return Array(out.suffix(Int(effective))).reversed() }\n        var start = -effective@@read slice(-limit) as suffix(limit), so ?limit=0 returns nothing not everything
R2@@Usage/UsageStore.swift@@    return jsBasename(cwd)@@    return (cwd as NSString).lastPathComponent@@use lastPathComponent, so a call from / records a project named "/"
R3@@Control/ControlPorts.swift@@        status().first { $0.name == name }@@        status().last { $0.name == name }@@take the LAST matching pool row instead of the first
R4@@Registry/RegistrySearch.swift@@        let truthy = (value == 0 || value.isNaN) ? 30 : value@@        let truthy = value@@read the limit default as ?? not ||, so 0 and NaN stop becoming 30
R5@@Registry/JSLocaleCompare.swift@@        switch lhs.compare(rhs, options: [], range: nil, locale: Locale(identifier: "en_US")) {@@        switch (lhs < rhs ? ComparisonResult.orderedAscending : lhs == rhs ? ComparisonResult.orderedSame : ComparisonResult.orderedDescending) {@@rank updatedAt with Swift < instead of ICU root collation
R6@@Control/ControlAPIRequest.swift@@        self.headers = Self.normalized(headers)@@        self.headers = headers@@stop normalising headers, so a repeated name resolves by hash order
R7@@Control/Describe.swift@@        let failed = entry?.hasError ?? false@@        let failed = entry?.member("error") != nil@@test the index error with != nil, zeroing tools when error is ""
R8@@Control/Describe.swift@@            JSONMember(key: "projects", value: rawOrEmptyArray(upstream.raw.member("projects"))),@@            JSONMember(key: "projects", value: .array((upstream.projects ?? []).map { .string(JSString($0)) })),@@serialise the TYPED projects, denying a non-array the router just stored
R9@@Control/Describe.swift@@            members.append(JSONMember(key: "args", value: rawOrEmptyArray(upstream.raw.member("args"))))@@            members.append(JSONMember(key: "args", value: .array(upstream.args.map { .string(JSString($0)) })))@@serialise the TYPED args, stringifying [1,2] into ["1","2"]
R10@@Control/Describe.swift@@            if let raw = upstream.raw.member("cwd") {@@            if let raw = upstream.raw.member("cwd"), raw != .null {@@omit a null cwd as if it were undefined, dropping "cwd":null from the wire
R11@@Control/ControlHandler.swift@@        guard ControlPaths.isControlPath(path) else { return .notHandled }@@        if let refusal = gate(request, tokenPath: deps.tokenPath) { return refusal }; guard ControlPaths.isControlPath(path) else { return .notHandled }@@gate the token before ownership, answering an unauthenticated POST /mcp 401
R12@@Control/ControlHandler.swift@@        func supplied(_ key: String) -> JSONValue?? {@@        for k in ["command", "args", "env"] where body.contains(where: { $0.key == JSString(k) }) { return .error(400, "not writable") }\n        func supplied(_ key: String) -> JSONValue?? {@@REJECT a PATCH carrying command/args/env instead of ignoring those members
R13@@Control/ControlToken.swift@@        let supplied: String = if header.hasPrefix("Bearer ") {@@        let supplied: String = if header.hasPrefix("Bearer "), header.count > 7 {@@let an empty Bearer fall through to x-mcpr-token instead of shadowing it
R14@@Usage/AttributionCache.swift@@        byPid[pid] = identity\n        if byPid.count > Self.bound { byPid.removeAll() }@@        if byPid.count > Self.bound { byPid.removeAll() }\n        byPid[pid] = identity@@check the 512 bound BEFORE the insert, clearing one pid later than the reference
R15@@Registry/RegistryMerge.swift@@                    if before(source[right], source[left]) {@@                    if !before(source[left], source[right]) {@@take the right run on a tie, losing arrival order among equal-ranked rows
R16@@Usage/UsageStore.swift@@            let offset = size - Self.tailWindowBytes@@            let offset = max(0, units.count - Self.tailWindowBytes)@@CORRECT the byte offset into a UTF-16 index, which the reference does not do (N5)
R17@@Usage/UsageStore.swift@@              stamp.size >= Self.maxLogBytes else { return }@@              stamp.size > Self.maxLogBytes else { return }@@rotate strictly above 8 MiB, so a log at exactly the boundary never rotates
R18@@Usage/UsageStore.swift@@        return Array(out.suffix(Self.ringSize))@@        return Array(out.prefix(Self.ringSize))@@warm the ring from the FIRST 500 records of the log instead of the last
R19@@Usage/UsageStore.swift@@        do {\n            try rotateIfBig()\n            try fileSystem.appendFile(@@        try? rotateIfBig()\n        do {\n            try fileSystem.appendFile(@@append the record even when the rotation was refused, as two independent try?s
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

# The dirty-tree guard runs BEFORE the restore trap is armed, and the ordering is the whole point.
#
# It used to be the other way round: `trap 'restore' EXIT` was installed first, then this guard
# called `exit 1`. That fired the trap on the way out, so the check written to protect uncommitted
# work was the one thing guaranteed to destroy it — `git checkout -- app/Sources/RouterCore`, on
# the exact tree it had just refused to touch. It ate an afternoon's edits before anyone noticed,
# because the error message says "would destroy them" in the past-conditional and reads like a
# refusal that already happened.
#
# Arming the trap only after the tree is known clean means the restore can never run over work it
# did not itself create.
if ! git -C "$ROOT" diff --quiet -- "$SRC"; then
  echo "error: $SRC has uncommitted changes. This script reverts it after every mutation and"
  echo "       would destroy them. Commit or stash first."
  echo "       (Nothing was reverted: the restore is armed below this check, deliberately.)"
  exit 1
fi

trap 'restore' EXIT

echo "Baseline: the gate must be green before any mutation means anything."
if ! make parity >/tmp/mutation-baseline.log 2>&1; then
  echo "error: the parity gate is already red. Nothing below would be interpretable."
  tail -20 /tmp/mutation-baseline.log
  exit 1
fi
echo "  $(grep -oE 'parity: .*' /tmp/mutation-baseline.log | tail -1)"
echo

declare -a decorations=() misapplied=() corpus=() suite=()

while IFS= read -r line; do
  [ -z "${line:-}" ] && continue
  id=${line%%@@*};          rest=${line#*@@}
  file=${rest%%@@*};        rest=${rest#*@@}
  pattern=${rest%%@@*};     rest=${rest#*@@}
  replacement=${rest%%@@*}
  description=${rest#*@@}
  wanted "$id" || continue

  printf '%-4s %-58s ' "$id" "$description"

  target="$SRC/$file"
  before=$(shasum "$target" | cut -d' ' -f1)
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

  # Two oracles, and which one catches it is the interesting part. The vector corpus is what R4's
  # differential gate will run, so a behaviour only the wider suite catches is NOT protected by the
  # corpus — it is protected by a hand-written test that the differential gate does not execute.
  if ! make parity >"/tmp/mutation-$id-parity.log" 2>&1; then
    echo "red — caught by the corpus"
    corpus+=("$id")
  elif ! make test >"/tmp/mutation-$id-test.log" 2>&1; then
    echo "red — caught by the suite, NOT the corpus"
    suite+=("$id")
  else
    echo "STAYED GREEN — decoration"
    decorations+=("$id")
  fi
  restore
done <<< "$MUTATIONS"

echo
echo "Caught by the vector corpus:            ${#corpus[@]} — ${corpus[*]:-none}"
echo "Caught by the suite but not the corpus: ${#suite[@]} — ${suite[*]:-none}"

status=0
if [ ${#misapplied[@]} -gt 0 ]; then
  echo
  echo "error: ${#misapplied[@]} mutation(s) did not apply: ${misapplied[*]}"
  echo "       This is a defect in this script, not in the corpus — the source moved under a"
  echo "       pattern. Those behaviours are UNPROVEN, not decorative."
  status=1
fi
if [ ${#decorations[@]} -gt 0 ]; then
  echo
  echo "error: ${#decorations[@]} behaviour(s) are unguarded: ${decorations[*]}"
  echo "       Each was broken and the whole suite still passed, so nothing constrains it."
  status=1
fi
[ $status -eq 0 ] && echo "Every named behaviour is load-bearing."
exit $status
