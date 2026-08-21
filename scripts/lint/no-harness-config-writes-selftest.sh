#!/usr/bin/env bash
#
# R7 — can `no-harness-config-writes.sh` actually refuse?
#
# The gate it tests was green while a realistic applier walked straight through it. Both of its
# rules were line-scoped, so an applier that asked for the target path on one line and wrote the
# file on a later line — which is how anybody would actually write one — was reported as
# `none writes one`. The gate was cited in ORCHESTRATOR.md as the reason R7's write refusal holds,
# so the gate passing was worse than the gate being absent.
#
# The three plants below are the verifier's, kept verbatim in shape, plus five more for the write
# tokens, the seam rule and the two directions a gate fails in. **P3 and P5 are the
# discriminators**: they are the cases a line-scoped rule cannot see, so reverting either rule to
# `grep -rnE … | grep -E …` turns this selftest red. P6, P7 and P9 run the opposite way — a gate
# that fires on prose, on a block comment or on `print` is a gate somebody deletes, so all three
# are asserted to stay green. **P10 asserts a miss**: the split-file applier this gate cannot see,
# written down as an assertion so the limit is visible from the run rather than only from a
# paragraph, and so that closing it turns this file red on purpose.
#
# Every plant is written into a scratch tree under `mktemp`. Nothing under `app/Sources` is
# touched, and the gate is pointed at the scratch tree through its own `$1`.
#
# Exit codes: 0 every case held · 1 a case did not hold · 2 the environment could not run one.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/scripts/lint/no-harness-config-writes.sh"
WORK="$(mktemp -d -t r7-write-gate)"
TREE="$WORK/Sources"
pass=0
fail=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM HUP

[ -x "$GATE" ] || { echo "environment: no gate at $GATE"; exit 2; }

ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }

# The baseline tree: everything the gate needs to run, and nothing it should refuse.
build_baseline() {
  rm -rf "$TREE"
  mkdir -p "$TREE/RouterCore/Discovery" "$TREE/RouterCore/Watch" "$TREE/MCPRouterCLI" \
           "$TREE/RouterCore/Log" "$TREE/RouterCore/IO"

  # Names every harness path literal in code — this is what satisfies the gate's anti-vacuity
  # guard, exactly as the real `ClientConfigs.swift` does.
  cat > "$TREE/RouterCore/Discovery/ClientConfigs.swift" <<'SWIFT'
enum ClientConfigs {
    static func path(for client: MCPClient, homeDirectory: String) -> String? {
        switch client {
        case .claudeCode: return homeDirectory + "/.claude.json"
        case .geminiCLI: return homeDirectory + "/.gemini/settings.json"
        case .grokCLI: return homeDirectory + "/.grok/config.toml"
        case .codexCLI: return homeDirectory + "/.codex/config.toml"
        case .cursor: return homeDirectory + "/.cursor/mcp.json"
        }
    }
}
SWIFT

  cat > "$TREE/RouterCore/Discovery/HarnessReconciliation.swift" <<'SWIFT'
enum HarnessReconciliation {
    static func report(_ entries: [String]) -> HarnessReport { HarnessReport(entries: entries) }
}
SWIFT

  cat > "$TREE/MCPRouterCLI/HarnessesVerb.swift" <<'SWIFT'
enum HarnessesVerb {
    static func run() {
        FileHandle.standardOutput.write(Data(render().utf8))
    }
}
SWIFT

  # Writes a file, and discusses `~/.claude.json` only in prose — the pre-existing `watch` shape.
  # It must NOT be a finding, or the gate is unrunnable against the tree it ships in.
  cat > "$TREE/RouterCore/Watch/WatchBackup.swift" <<'SWIFT'
/// `~/.claude.json` is ~268 KB and holds live session state, so the watcher copies it first.
enum WatchBackup {
    static func save(_ contents: String, atPath path: String) throws {
        try fileSystem.writeFile(Data(contents.utf8), atPath: path)
    }
}
SWIFT
}

# Runs the gate against the scratch tree and compares its exit code.
expect() {
  local what="$1" wanted="$2"
  local output status
  output="$("$GATE" "$TREE" 2>&1)"
  status=$?
  if [ "$status" -eq "$wanted" ]; then
    ok "$what (exit $status)"
  else
    bad "$what: expected exit $wanted, got $status"
    printf '%s\n' "$output" | sed 's/^/          /'
  fi
}

echo "no-harness-config-writes-selftest: the gate's own scope"

# ---------------------------------------------------------------- the clean tree
build_baseline
expect "a tree with no applier passes" 0

# ---------------------------------------------------------------- P1 — literal beside a write
build_baseline
cat > "$TREE/MCPRouterCLI/BluntApplier.swift" <<'SWIFT'
enum BluntApplier {
    static func apply(_ text: String, home: String) throws {
        try text.write(toFile: home + "/.gemini/settings.json", atomically: true, encoding: .utf8)
    }
}
SWIFT
expect "P1  a harness path literal beside a write, one line, is refused" 1

# ---------------------------------------------------------------- P2 — plan beside a write
build_baseline
cat > "$TREE/MCPRouterCLI/PlanApplier.swift" <<'SWIFT'
enum PlanApplier {
    static func apply(_ plan: ReconciliationPlan, _ text: String) throws {
        try ReconciliationPlan.rendered(plan).write(toFile: plan.path, atomically: true, encoding: .utf8)
    }
}
SWIFT
expect "P2  a reconciliation plan beside a write, one line, is refused" 1

# ---------------------------------------------------------------- P3 — the realistic applier
# This is the plant the line-scoped gate reported as `none writes one`. The path is asked for on
# one line and written on another, which is how a person writes an applier. Reverting either rule
# to line-scoped turns THIS case green and this selftest red.
build_baseline
cat > "$TREE/MCPRouterCLI/RealisticApplier.swift" <<'SWIFT'
enum RealisticApplier {
    static func apply(_ plan: ReconciliationPlan, home: String) throws {
        guard let target = ClientConfigs.path(for: plan.client, homeDirectory: home) else { return }
        let original = try String(contentsOfFile: target, encoding: .utf8)
        let rewritten = removeEntries(plan.remove, from: original)
        try rewritten.write(toFile: target, atomically: true, encoding: .utf8)
    }
}
SWIFT
expect "P3  a realistic applier, path and write on different lines, is refused" 1

# ---------------------------------------------------------------- P4 — an applier in the seam
# It names no harness path and touches no R7 type: the target arrives as a bare `String`. Rules 1
# and 2 cannot see it. Rule 3 can, because it lives where an applier would live.
build_baseline
cat > "$TREE/RouterCore/Discovery/HarnessApplier.swift" <<'SWIFT'
enum HarnessApplier {
    static func apply(_ text: String, to target: String) throws {
        try text.write(toFile: target, atomically: true, encoding: .utf8)
    }
}
SWIFT
expect "P4  a bare-String applier inside the seam is refused by the seam rule" 1

# ---------------------------------------------------------------- P5 — the missing write token
# `FileHandle(forWritingTo:)` was absent from the gate's write vocabulary, which listed only
# `forWritingAtPath`. An applier using the URL form wrote a harness config past a gate that had
# been told to look for writes.
build_baseline
cat > "$TREE/MCPRouterCLI/HandleApplier.swift" <<'SWIFT'
enum HandleApplier {
    static func apply(_ data: Data, home: String) throws {
        let url = URL(fileURLWithPath: home + "/.codex/config.toml")
        let handle = try FileHandle(forWritingTo: url)
        try emit(data, through: handle)
    }
}
SWIFT
expect "P5  forWritingTo: is the only write token in the file, and counts" 1

# ---------------------------------------------------------------- P8 — the update handle
# Same isolation as P5. An applier that opens the config for UPDATE rather than for writing is
# still an applier, and `forUpdatingTo:` was outside the vocabulary too.
build_baseline
cat > "$TREE/MCPRouterCLI/UpdateApplier.swift" <<'SWIFT'
enum UpdateApplier {
    static func apply(_ data: Data, home: String) throws {
        let url = URL(fileURLWithPath: home + "/.grok/config.toml")
        let handle = try FileHandle(forUpdatingTo: url)
        try emit(data, through: handle)
    }
}
SWIFT
expect "P8  forUpdatingTo: is the only write token in the file, and counts" 1

# ---------------------------------------------------------------- P9 — a block comment
# `app/Sources` carries one real `/* … */` block. A gate that reads a block comment as code fires
# on a writer that merely documents a harness path, and a gate that fires on innocent code is a
# gate somebody deletes.
build_baseline
cat > "$TREE/RouterCore/Log/BlockCommented.swift" <<'SWIFT'
/*
 * `~/.claude.json` is discussed here, in the shape Describe.swift uses.
 * Nothing in this type opens it.
 */
enum BlockCommented {
    static func save(_ text: String, atPath path: String) throws {
        try fileSystem.writeFile(Data(text.utf8), atPath: path)
    }
}
SWIFT
expect "P9  a harness path in a block comment is documentation too" 0

# ---------------------------------------------------------------- P10 — the declared blind spot
# **This case asserts that the gate MISSES something, and it is here so that nobody has to
# rediscover it.** An applier split across two neutrally-named files outside the seam satisfies no
# intersection and lives in no watched name. Registered as `D-r7-m`; the fix named there is a
# closed-world census of every writing file against a declared allowlist, which is a real trade
# (it taxes every unrelated feature that adds a file write) and is the owner's to take.
#
# The day somebody takes it, this case turns red — which is the point of writing it down as an
# assertion rather than as a paragraph.
build_baseline
cat > "$TREE/MCPRouterCLI/SplitCoordinator.swift" <<'SWIFT'
enum SplitCoordinator {
    static func apply(_ plan: ReconciliationPlan, home: String) throws {
        guard let target = ClientConfigs.path(for: plan.client, homeDirectory: home) else { return }
        try FileStore.save(render(plan), to: target)
    }
}
SWIFT
cat > "$TREE/RouterCore/IO/FileStore.swift" <<'SWIFT'
enum FileStore {
    static func save(_ text: String, to target: String) throws {
        try text.write(toFile: target, atomically: true, encoding: .utf8)
    }
}
SWIFT
expect "P10 a split applier outside the seam is NOT caught — the gate's declared blind spot" 0

# ---------------------------------------------------------------- P6 — prose is not a finding
build_baseline
cat > "$TREE/RouterCore/Watch/WatchState.swift" <<'SWIFT'
/// Hash of the `mcpServers` object only — the rest of `~/.claude.json` churns constantly.
/// The staging file lives beside `~/.gemini/settings.json` and is never written by this type.
enum WatchState {
    static func save(_ text: String, atPath path: String) throws {
        try fileSystem.writeFile(Data(text.utf8), atPath: path)
    }
}
SWIFT
expect "P6  a harness path discussed in a doc comment is documentation, not a write" 0

# ---------------------------------------------------------------- P7 — printing is not writing
build_baseline
cat > "$TREE/MCPRouterCLI/Support.swift" <<'SWIFT'
enum Out {
    static let usage = "mcp-router import [--from <path>]   Adopt servers from ~/.claude.json"
    static func print(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}
SWIFT
expect "P7  writing to standard output is printing, not writing a config" 0

# ---------------------------------------------------------------- vacuity: nothing to examine
build_baseline
rm -f "$TREE/RouterCore/Discovery/ClientConfigs.swift"
expect "a tree naming no harness config at all is an environment failure, not a pass" 2

build_baseline
rm -rf "$TREE/RouterCore/Discovery" "$TREE/MCPRouterCLI/HarnessesVerb.swift"
mkdir -p "$TREE/RouterCore/Discovery"
cat > "$TREE/RouterCore/Other.swift" <<'SWIFT'
enum Other { static let path = "~/.gemini/settings.json" }
SWIFT
expect "a tree with an empty seam is an environment failure, not a pass" 2

echo
if [ "$fail" -eq 0 ]; then
  echo "no-harness-config-writes-selftest: $pass case(s) held"
  exit 0
fi
echo "no-harness-config-writes-selftest: $fail of $((pass + fail)) case(s) did not hold"
exit 1
