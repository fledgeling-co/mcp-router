#!/usr/bin/env bash
#
# The gate above is only worth its exit code if each of its refusals can be made to fire, and if a
# clean tree really passes. This plants subjects in a sandbox and requires the stated outcome from
# each — the same shape `no-harness-config-writes-selftest.sh` uses, and for the same reason: a
# refusal nobody has watched fire is indistinguishable from a refusal that cannot.
#
# It also asserts the two INSTRUMENT failures, because the whole value of exit 2 is that a gate
# which compared nothing does not read as a gate that passed.
#
# And it asserts the limit the gate does not close (P7): an applier split across two neutrally
# named files outside the seam walks through. That is a MISS, planted and expected, so it appears
# in a run rather than only in the header's prose.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/scripts/lint/no-harness-skill-writes.sh"
SANDBOX="$(mktemp -d -t f8-skill-writes)"
trap 'rm -rf "$SANDBOX"' EXIT INT TERM HUP

pass=0
fail=0

plant() { # relative-path body
  local path="$SANDBOX/app/Sources/$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path"
}

reset() {
  rm -rf "$SANDBOX/app"
  mkdir -p "$SANDBOX/app/Sources/RouterCore/Profiles"
  # A seam that mutates nothing, so rule 2 has something to compare and the instrument check
  # passes. Every case below starts from this tree.
  plant "RouterCore/Profiles/SkillRootInventory.swift" <<'SWIFT'
import Foundation
struct Reader { func read(_ p: String) -> Bool { FileManager.default.fileExists(atPath: p) } }
SWIFT
  plant "RouterCore/Profiles/SkillRootLocation.swift" <<'SWIFT'
import Foundation
struct Where { let path: String }
SWIFT
  plant "RouterCore/Profiles/ProfileProjection.swift" <<'SWIFT'
import Foundation
struct Projection { let steps: [String] }
SWIFT
  plant "RouterCore/Profiles/ProfileProjector.swift" <<'SWIFT'
import Foundation
enum Projector { static func project() -> [String] { [] } }
SWIFT
}

check() { # label want-exit
  local label="$1" want="$2"
  "$GATE" "$SANDBOX" >"$SANDBOX/out.txt" 2>&1
  local got=$?
  if [ "$got" -eq "$want" ]; then
    echo "  ok    $label (exit $got)"
    pass=$((pass + 1))
  else
    echo "  FAIL  $label — wanted exit $want, got $got"
    sed -n '1,8p' "$SANDBOX/out.txt" | sed 's/^/        /'
    fail=$((fail + 1))
  fi
}

echo "no-harness-skill-writes-selftest:"

reset
check "P0 a clean tree passes, so every refusal below is about its own plant" 0

reset
plant "RouterCore/Somewhere/Applier.swift" <<'SWIFT'
import Foundation
enum Applier {
    static func run(_ home: String) throws {
        let root = (home as NSString).appendingPathComponent(".cursor/skills")
        try FileManager.default.createSymbolicLink(atPath: root, withDestinationPath: "/x")
    }
}
SWIFT
check "P1 a whole harness skills path beside a link is refused" 1

reset
plant "RouterCore/Somewhere/Assembled.swift" <<'SWIFT'
import Foundation
enum Assembled {
    static func run(_ home: String) throws {
        let base = (home as NSString).appendingPathComponent(".cursor")
        let root = (base as NSString).appendingPathComponent("skills")
        try FileManager.default.removeItem(atPath: root)
    }
}
SWIFT
check "P2 a path assembled a component at a time is still a harness skills root" 1

reset
plant "RouterCore/Somewhere/Distant.swift" <<'SWIFT'
import Foundation
enum Distant {
    static func target(_ home: String) -> String {
        (home as NSString).appendingPathComponent(".gemini/skills")
    }

    // Many lines later, so a line-scoped rule would not see the pair.
    static func run(_ home: String) throws {
        let path = target(home)
        try FileManager.default.moveItem(atPath: path, toPath: path + ".old")
    }
}
SWIFT
check "P3 a path named on one line and written on a later one is still the pair" 1

reset
plant "RouterCore/Profiles/ProfileProjector.swift" <<'SWIFT'
import Foundation
enum Projector {
    static func project(_ destination: String) throws {
        // No harness path anywhere. Rule 2 refuses this because of WHERE it is.
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
    }
}
SWIFT
check "P4 any mutation inside the read-only seam is refused, however the path arrived" 1

reset
plant "RouterCore/Profiles/SkillRootInventory.swift" <<'SWIFT'
import Foundation
enum Sneaky {
    static func run(_ destination: String) {
        _ = Process()
    }
}
SWIFT
check "P5 a subprocess inside the seam is refused too" 1

reset
plant "RouterCore/Somewhere/Consumer.swift" <<'SWIFT'
import Foundation
enum Consumer {
    static func run(_ inventory: SkillRootInventory, _ to: String) throws {
        try FileManager.default.copyItem(atPath: inventory.path, toPath: to)
    }
}
SWIFT
check "P6 handling the seam's API and writing is refused wherever the file lives" 1

reset
plant "RouterCore/Somewhere/Half.swift" <<'SWIFT'
import Foundation
enum Half { static func target(_ home: String) -> String { home + "/.cursor/skills" } }
SWIFT
plant "RouterCore/Somewhere/OtherHalf.swift" <<'SWIFT'
import Foundation
enum OtherHalf {
    static func run(_ path: String) throws { try FileManager.default.removeItem(atPath: path) }
}
SWIFT
check "P7 THE KNOWN MISS — an applier split across two neutral files walks through" 0

reset
plant "RouterCore/Somewhere/Comment.swift" <<'SWIFT'
import Foundation
enum Comment {
    /* a block comment naming .cursor/skills and createSymbolicLink, which is documentation */
    // and a line comment naming .gemini/skills and removeItem, which is also documentation
    static func run() -> Int { 1 }
}
SWIFT
check "P8 a harness path and a write inside comments are documentation, not code" 0

# The mirror image, and it is the one the sibling gate got wrong: a `//` inside a STRING must not
# suppress the code after it, and a path written as a string literal IS a path.
reset
plant "RouterCore/Somewhere/Stringy.swift" <<'SWIFT'
import Foundation
enum Stringy {
    static let marker = "// not a comment"
    static func run() throws {
        try FileManager.default.removeItem(atPath: NSHomeDirectory() + "/.cursor/skills")
    }
}
SWIFT
check "P8b a slash-slash inside a string does not suppress the code after it" 1

# The store writes constantly and must never be refused: it owns the ROUTER's own disk.
reset
plant "RouterCore/Profiles/ProfileStore.swift" <<'SWIFT'
import Foundation
struct DiskProfileStore {
    let root: String
    func write(_ text: String, _ name: String) throws {
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: URL(fileURLWithPath: root + "/" + name))
    }
}
SWIFT
check "P9 the router writing its OWN store is not a finding" 0

# Instrument failures.
reset
rm -f "$SANDBOX/app/Sources/RouterCore/Profiles/SkillRootInventory.swift" \
      "$SANDBOX/app/Sources/RouterCore/Profiles/SkillRootLocation.swift" \
      "$SANDBOX/app/Sources/RouterCore/Profiles/ProfileProjection.swift" \
      "$SANDBOX/app/Sources/RouterCore/Profiles/ProfileProjector.swift"
plant "RouterCore/Somewhere/Unrelated.swift" <<'SWIFT'
import Foundation
enum Unrelated { static let x = 1 }
SWIFT
check "P10 a tree with no seam file is an instrument failure, not a pass" 2

rm -rf "$SANDBOX/app"
mkdir -p "$SANDBOX/app/Sources"
check "P11 a tree with no Swift file at all compared nothing" 2

# Every alternative in the mutating vocabulary must be exercised by something above, or the gate is
# carrying a route nobody has watched fire. Checked mechanically rather than by hand.
missing=0
while IFS= read -r token; do
  [ -n "$token" ] || continue
  # Turn the regex alternative back into something a probe can literally contain: drop the
  # escaping backslashes and the leading character class, which the plant supplies as a space.
  probe="${token//\\/}"
  # Quoted, so bash treats it as a literal to delete rather than as a glob class that
  # would strip every non-letter from the probe — which silently emptied 11 of them.
  probe="${probe//"[^A-Za-z]"/}"
  reset
  plant "RouterCore/Profiles/ProfileProjector.swift" <<SWIFT
import Foundation
enum Probe { static func go() { _ = "x" ; $probe } }
SWIFT
  "$GATE" "$SANDBOX" >"$SANDBOX/vocab.txt" 2>&1
  if [ "$?" -ne 1 ]; then
    echo "  FAIL  vocabulary alternative never fires: $token"
    missing=$((missing + 1))
  fi
done < <(sed -n 's/^VOCAB=.\(.*\).$/\1/p' "$GATE" | tr '|' '\n')

if [ "$missing" -gt 0 ]; then
  echo "  instrument: $missing vocabulary alternative(s) matched no probe"
  fail=$((fail + 1))
else
  echo "  ok    every vocabulary alternative fires on a probe"
  pass=$((pass + 1))
fi

echo "no-harness-skill-writes-selftest: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
