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

# ---------------------------------------------------------------- P11 — the wrapped call
# The verifier's first walk-through, and the one that will happen by itself: this repository's own
# `line_length: warning 110` pushes a long call onto a second line, and `ClientConfigs\.path\(for:`
# is a pattern that wants both halves adjacent. The rule was file-scoped; the PATTERN was not.
build_baseline
cat > "$TREE/MCPRouterCLI/WrappedApplier.swift" <<'SWIFT'
enum WrappedApplier {
    static func apply(_ text: String, for client: MCPClient, homeDirectory home: String) throws {
        guard let target = ClientConfigs.path(
            for: client, homeDirectory: home, projectDirectory: nil
        ) else { return }
        try text.write(toFile: target, atomically: true, encoding: .utf8)
    }
}
SWIFT
expect "P11 a wrapped ClientConfigs.path( call is still the R7 API" 1

# ---------------------------------------------------------------- P12 — the assembled path
# The path literal never appears: it is built a component at a time, which is how every other path
# in this repository is built. A vocabulary of whole paths cannot see it, so the gate carries the
# distinguishing FILE NAMES as well.
build_baseline
cat > "$TREE/MCPRouterCLI/AssemblingApplier.swift" <<'SWIFT'
enum AssemblingApplier {
    static func apply(_ text: String, home: NSString) throws {
        let target = home.appendingPathComponent(".gemini")
            .appendingPathComponent("config")
            .appendingPathComponent("mcp_config.json")
        try text.write(toFile: target, atomically: true, encoding: .utf8)
    }
}
SWIFT
expect "P12 a harness path assembled from components is still a harness path" 1

# ---------------------------------------------------------------- P13 — C stdio in the seam
# Rule 3's claim is any file write at all inside the seam, however the path was obtained. `fopen`
# and `fputs` obtain it perfectly well and were in no vocabulary.
build_baseline
cat > "$TREE/RouterCore/Discovery/HarnessWriteThrough.swift" <<'SWIFT'
enum HarnessWriteThrough {
    static func apply(_ text: String, to target: String) {
        guard let handle = fopen(target, "w") else { return }
        fputs(text, handle)
        fclose(handle)
    }
}
SWIFT
expect "P13 an fopen/fputs applier inside the seam is refused" 1

# ---------------------------------------------------------------- P14 — the subprocess in the seam
# A shell redirect writes the file without any Swift write call in the diff at all.
build_baseline
cat > "$TREE/RouterCore/Discovery/HarnessShellApplier.swift" <<'SWIFT'
enum HarnessShellApplier {
    static func apply(_ text: String, to target: String) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "cat > \(target)"]
        try task.run()
    }
}
SWIFT
expect "P14 a /bin/sh redirect inside the seam is refused" 1

# ---------------------------------------------------------------- P15 — the block-comment line
# `code_lines` blanked any line whose first characters opened a block comment, so a write sharing
# that line was erased from the gate. This is the trailing-comment evasion `file_writes` was
# hardened against, left open one function along.
build_baseline
cat > "$TREE/RouterCore/Discovery/HarnessCommentApplier.swift" <<'SWIFT'
enum HarnessCommentApplier {
    static func apply(_ text: String, to target: String) throws {
        /* the plan is rendered above */ try text.write(toFile: target, atomically: true, encoding: .utf8)
    }
}
SWIFT
expect "P15 a write sharing a line with a block comment is still a write" 1

# ---------------------------------------------------------------- P16 — mutation without a write
# **The route nobody had named.** Every plant so far reaches the file through something spelled like
# a write. Replacing a harness config with a symlink, hard-linking one over it, or changing its mode
# mutates the developer's live configuration through calls that contain no write token at all — and
# `D-r7-v` records that even the acceptance lane's byte digest would not see the last of those.
build_baseline
cat > "$TREE/RouterCore/Discovery/HarnessLinkApplier.swift" <<'SWIFT'
enum HarnessLinkApplier {
    static func apply(_ staged: URL, over target: String) throws {
        try FileManager.default.createSymbolicLink(atPath: target, withDestinationPath: staged.path)
    }
}
SWIFT
expect "P16 replacing a harness config with a symlink is a mutation, not an exemption" 1

build_baseline
cat > "$TREE/RouterCore/Discovery/HarnessModeApplier.swift" <<'SWIFT'
enum HarnessModeApplier {
    static func apply(_ target: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target)
    }
}
SWIFT
expect "P16b changing a harness config's mode inside the seam is refused too" 1

# ---------------------------------------------------------------- P17 — the block comment's body
# The opposite direction of P15, and the reason it is here: a comment reader that keeps code after
# `*/` must also drop prose INSIDE a block whose lines do not begin with `*`. A gate that reads that
# prose as code fires on a file that only documents what it refuses to do.
build_baseline
cat > "$TREE/RouterCore/Log/LooseBlockComment.swift" <<'SWIFT'
/*
  This type does not write anything. It is documented here that an applier would call
  try text.write(toFile: home + "/.gemini/settings.json", atomically: true, encoding: .utf8)
  and that spec §7 refuses exactly that.
*/
enum LooseBlockComment {
    static func describe() -> String { "nothing is written" }
}
SWIFT
expect "P17 prose inside a block comment is documentation, whatever its lines begin with" 0

# ---------------------------------------------------------------- P18 — a slash-star in a line comment
# `app/Sources` carries `src/*.ts` inside a `///` line. A block-comment reader that took that as an
# opener would blank the rest of the file and report every writer in it as clean — the vacuity this
# gate exists to refuse, arriving through its own comment stripper.
build_baseline
cat > "$TREE/MCPRouterCLI/SlashStarApplier.swift" <<'SWIFT'
/// Transcribed from `src/*.ts` rather than reasoned about.
enum SlashStarApplier {
    static func apply(_ text: String, home: String) throws {
        try text.write(toFile: home + "/.cursor/mcp.json", atomically: true, encoding: .utf8)
    }
}
SWIFT
expect "P18 a /* inside a line comment does not blank the file after it" 1

# ---------------------------------------------------------------- P19 — a slash-star in a STRING
# The critical one an out-of-family reviewer found in the previous comment reader. `" /*"` is a
# Swift string containing a slash-star; a stripper that opened a block on it blanked every line
# after it to end of file, so the applier below reported clean. A gate that goes quiet is the
# vacuity this file exists to refuse, and it was arriving through the gate's own stripper.
build_baseline
cat > "$TREE/RouterCore/Discovery/HarnessCommentEvasion.swift" <<'SWIFT'
enum HarnessCommentEvasion {
    static let marker = " /*"
    static func apply(_ text: String, to target: String) throws {
        try text.write(toFile: target, atomically: true, encoding: .utf8)
    }
}
SWIFT
expect "P19 a slash-star inside a string does not blank the applier under it" 1

# ---------------------------------------------------------------- P20 — a generic file name alone
# The other direction of the same reviewer's finding. `config.toml` is one of the commonest file
# names in software; reading it as a harness config on its own refuses this product for writing its
# own, with no suppression comment to answer it. Nothing here names a harness.
build_baseline
cat > "$TREE/RouterCore/Log/ProjectSettings.swift" <<'SWIFT'
enum ProjectSettings {
    static func cache(_ text: String, under root: NSString) throws {
        let target = root.appendingPathComponent("config.toml")
        try text.write(toFile: target, atomically: true, encoding: .utf8)
    }
}
SWIFT
expect "P20 a generic config file name with no harness named beside it is not a finding" 0

# ---------------------------------------------------------------- P20b — the same name, in company
build_baseline
cat > "$TREE/RouterCore/Log/CodexSettings.swift" <<'SWIFT'
enum CodexSettings {
    static func cache(_ text: String, under home: NSString) throws {
        let dir = home.appendingPathComponent(".codex")
        let target = (dir as NSString).appendingPathComponent("config.toml")
        try text.write(toFile: target, atomically: true, encoding: .utf8)
    }
}
SWIFT
expect "P20b the same generic name beside a harness home is a harness config again" 1

# ---------------------------------------------------------------- P21 — the POSIX spelling
# P16 planted `createSymbolicLink`; the same mutation spelled `symlink()` walked through, which is
# this pass's own defect in miniature — a vocabulary of named routes rather than the property.
build_baseline
cat > "$TREE/RouterCore/Discovery/HarnessRelink.swift" <<'SWIFT'
enum HarnessRelink {
    static func swap(_ staged: String, over target: String) {
        symlink(staged, target)
    }
}
SWIFT
expect "P21 a POSIX symlink over a harness config is refused like the Foundation one" 1

# ---------------------------------------------------------------- P22 — a slash-slash in a STRING
# The mirror of P19. A `//` inside a URL string is not a line comment, and a reader that took it as
# one never opened the block that follows on the same line — so the block's prose was read as code
# and a file that only documents what it refuses to do became a finding.
build_baseline
cat > "$TREE/RouterCore/Log/DocumentedOnly.swift" <<'SWIFT'
enum DocumentedOnly {
    static let reference = "https://example.test" /*
      An applier would write to ~/.gemini/settings.json here, and spec §7 refuses exactly that.
    */
    static func save(_ text: String, atPath path: String) throws {
        try fileSystem.writeFile(Data(text.utf8), atPath: path)
    }
}
SWIFT
expect "P22 a slash-slash inside a string does not suppress the block comment after it" 0

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
