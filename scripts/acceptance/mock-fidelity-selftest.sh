#!/bin/bash
#
# Proves M23's conversion gate can reach all three of its exits — and, more to the point, that it
# reaches 3 where a two-state gate would reach 0.
#
# "A gate never observed failing is a gate nobody has written" is the M23 brief's line, and the
# repo has the receipt: `parity-lane-selftest.sh` exists because a lane that had never been seen
# red was trusted for weeks. So this drives the real layer engine against a scratch tree built for
# each case, and fails if any case comes back with an exit the case was not built to produce.
#
# It is hermetic and takes about a second. The scratch tree is a whole fake repo root: the engine
# computes its root from its own __file__, so a SYMLINK to it inside a temp directory makes every
# path it resolves — the mock, the pairing, the lint, the app — resolve inside that directory. The
# two external tools the layers shell out to are stubbed there: `no-raw-design-values.sh` as a file
# in the scratch tree, and `swift` as a shim first on PATH. Nothing in the shipped engine has a
# test hook in it, which is the point: a gate with a bypass has a bypass.
set -uo pipefail

cd "$(dirname "$0")/../.."
REPO=$(pwd)
ENGINE="$REPO/scripts/acceptance/mock_fidelity.py"
AFFORDANCES="$REPO/scripts/acceptance/mock-affordances.py"

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

fail=0
cases=0

# Builds a scratch root. $1 = directory. The fixtures are written by build-fixture.py below.
build() {
  local root=$1
  mkdir -p "$root/scripts/acceptance" "$root/scripts/lint" "$root/app" "$root/design" \
           "$root/planning/fidelity" "$root/dumps" "$root/bin"
  ln -sf "$ENGINE" "$root/scripts/acceptance/mock_fidelity.py"
  ln -sf "$AFFORDANCES" "$root/scripts/acceptance/mock-affordances.py"

  cat > "$root/scripts/lint/no-raw-design-values.sh" <<'LINT'
#!/bin/bash
# Stub stand-in for the real colour-literal lint. Prints the same scan line the real one does,
# because the engine reads the file count off it and treats its absence as inconclusive.
echo "no-raw-design-values: scanning 3 files"
if [ "${STUB_LINT_FINDING:-0}" = "1" ]; then
  echo "app/Sources/Fixture/Thing.swift:12: Color(red: 1, green: 0, blue: 0)  — colour literal; use ColorToken"
  exit 1
fi
exit 0
LINT
  chmod +x "$root/scripts/lint/no-raw-design-values.sh"

  cat > "$root/bin/swift" <<'SWIFT'
#!/bin/bash
# Stub stand-in for `swift test --filter MockToken`. Emits the markers the tokens layer parses.
if [ "${STUB_TOKENS_SILENT:-0}" = "1" ]; then
  echo "Test run with 0 tests in 0 suites"
  exit 0
fi
echo "MOCK-FIDELITY-TOKENS: rows=${STUB_TOKEN_ROWS:-12} matched=8 pending=4 uncited=${STUB_TOKENS_UNCITED:-0}"
echo "MOCK-FIDELITY-PENDING: metric/jack-lane mock=44px swift=absent citation=M21-metric-rows"
echo "MOCK-FIDELITY-MOCK-LITERALS: stray=${STUB_MOCK_LITERALS:-0}"
exit "${STUB_TOKENS_EXIT:-0}"
SWIFT
  chmod +x "$root/bin/swift"

  python3 "$SCRATCH/build-fixture.py" "$root"
}

# $1 = case name, $2 = expected exit, $3 = scratch root, $4 = a string the report must contain.
# Any STUB_* variables the case needs are exported by the caller and unset after, rather than
# prefixed onto the call: a prefix assignment on a shell FUNCTION does not reliably reach the
# commands the function runs, and a stub that silently did not take effect would make a case pass
# for the wrong reason.
expect() {
  local name=$1 want=$2 root=$3
  cases=$((cases + 1))
  local out status
  out=$(PATH="$root/bin:$PATH" python3 "$root/scripts/acceptance/mock_fidelity.py" \
        "$root/planning/fidelity/fixture.layers.json" "$root/dumps" 2>&1)
  status=$?
  if [ "$status" != "$want" ]; then
    echo "FAIL  $name — expected exit $want, got $status"
    echo "$out" | sed 's/^/        /'
    fail=1
  else
    echo "ok    $name — exit $status"
    if [ -n "${4:-}" ] && ! grep -qF -- "$4" <<<"$out"; then
      echo "FAIL  $name — exit was right but the report never said: $4"
      echo "$out" | sed 's/^/        /'
      fail=1
    fi
  fi
}

cat > "$SCRATCH/build-fixture.py" <<'PY'
"""Writes the scratch mock, manifest, pairing and dump for one selftest case."""
import json, os, sys

root = sys.argv[1]

open(os.path.join(root, "design/fixture.html"), "w").write("""<!doctype html>
<section id="b-fixture">
  <div class="v v-ideal">
    <h1>Fixture</h1>
    <p>One sentence.</p>
    <button class="btn primary">Do the thing</button>
  </div>
</section>
""")

ladder = {"Caption": {"size": 10, "lineHeight": 13, "emphasis": "Semibold"},
          "Body": {"size": 13, "lineHeight": 16, "emphasis": "Semibold"},
          "Title1": {"size": 22, "lineHeight": 26, "emphasis": "Bold"}}


def node(nid, role, kind, frame, children=(), text=None, type_role=None, axis=None):
    out = {"id": nid, "role": role, "kind": kind, "path": [], "alignment": None,
           "frame": dict(zip(("x", "y", "width", "height"), frame)),
           "tokens": {"type": type_role} if type_role else {}, "resolved": {},
           "text": text, "children": list(children)}
    if axis:
        out["axis"] = axis
    return out


dump = {
    "surface": "fixture.ideal", "appearance": "dark",
    "size": {"x": 0, "y": 0, "width": 400, "height": 200},
    "typeLadder": ladder,
    "layers": ["structure", "geometry", "resolved-colour", "copy", "tokens"],
    "inconclusive": [{"layer": "resolved-font", "covers": "size, weight and face",
                      "evidence": "a SwiftUI Font is opaque",
                      "confirmedInsteadBy": "the type-metrics layer"}],
    "root": node("fixture.ideal", "surface", "vstack", (0, 0, 400, 200), axis="vertical", children=[
        node("heading", "heading", "text", (0, 0, 120, 26), text="Fixture", type_role="Title1"),
        node("sentence", "sentence", "text", (0, 30, 200, 16), text="One sentence.", type_role="Body"),
        node("action", "primary-action", "leaf", (0, 50, 110, 24), text="Do the thing", type_role="Body"),
    ]),
}
if os.environ.get("FIXTURE_DRIFT") == "1":
    dump["root"]["children"][2]["text"] = "Do the other thing"

# One mutation per layer that had no arming case until 21 Aug 2026. The out-of-family review
# (planning/evidence/M23-review-codex.md, finding 8) made the point the brief already makes:
# proving one route to exit 1 and one to exit 3 leaves every other layer free to be constant-green
# without the selftest noticing. Each of these makes exactly one layer speak.
if os.environ.get("FIXTURE_AXIS_LIE") == "1":
    # The children stay where they are; only the label changes. A structure layer that trusted the
    # annotation instead of the geometry would report this tree clean.
    dump["root"]["axis"] = "horizontal"
    dump["root"]["kind"] = "hstack"
if os.environ.get("FIXTURE_ZERO_AREA") == "1":
    dump["root"]["children"][1]["frame"]["width"] = 0
if os.environ.get("FIXTURE_CASCADE_LOST") == "1":
    # Two nodes naming Body, laid out at different single-line heights: an ancestor .font() won on
    # one of them. This is the residue the font-weight-face layer cannot see, so if type-metrics
    # does not catch it nothing does.
    dump["root"]["children"][2]["kind"] = "text"
    dump["root"]["children"][2]["frame"]["height"] = 24
if os.environ.get("FIXTURE_EXTRA_NODE") == "1":
    dump["root"]["children"].append(
        node("invented", "card", "leaf", (0, 80, 200, 40), text="Nothing in the mock says this")
    )

open(os.path.join(root, "dumps/fixture.ideal.json"), "w").write(json.dumps(dump, indent=1))

layers = ["tokens", "literals", "structure", "geometry", "type-metrics", "copy", "breadth"]
declared = [{"name": name, "required": True} for name in layers]
if os.environ.get("FIXTURE_SILENCE_STRUCTURE") == "1":
    declared[2] = {"name": "structure", "required": False, "substitute": "checked by eye"}
declared.append({"name": "font-weight-face", "required": False,
                 "substitute": "a SwiftUI Font is opaque; the type-metrics layer carries what can be read"})

open(os.path.join(root, "planning/fidelity/fixture.layers.json"), "w").write(json.dumps({
    "surface": "fixture", "mock": "design/fixture.html", "section": "b-fixture",
    "pairing": "planning/fidelity/fixture.pairing.tsv", "states": ["ideal"],
    "floors": {"tokenRows": 10, "dumpNodes": 4, "affordances": 3},
    "layers": declared,
}, indent=1))

pairing = (
    "ideal\tv-ideal/heading/fixture\tfixture.ideal/heading\n"
    "ideal\tv-ideal/sentence/one-sentence\tfixture.ideal/sentence\n"
)
if os.environ.get("FIXTURE_DROP_PAIRING") != "1":
    pairing += "ideal\tv-ideal/button/do-the-thing\tfixture.ideal/action\n"
open(os.path.join(root, "planning/fidelity/fixture.pairing.tsv"), "w").write(pairing)

if os.environ.get("FIXTURE_NO_DUMP") == "1":
    os.remove(os.path.join(root, "dumps/fixture.ideal.json"))
PY

echo "mock-fidelity-selftest: driving the layer engine against scratch trees"

# 1 — clean and complete
root="$SCRATCH/clean"; build "$root"
expect "clean tree returns 0" 0 "$root" "EXIT 0"

# 2 — a finding: the build renders a label the mock does not
root="$SCRATCH/drift"; export FIXTURE_DRIFT=1; build "$root"; unset FIXTURE_DRIFT
expect "a label the mock does not carry returns 1" 1 "$root" "label differs"

# 3 — a finding from the layer that shells out to the real colour-literal lint
root="$SCRATCH/lint"; build "$root"
export STUB_LINT_FINDING=1; expect "a colour literal returns 1" 1 "$root" "raw design value"; unset STUB_LINT_FINDING

# 4 — the artifact a required layer reads is gone
root="$SCRATCH/nodump"; export FIXTURE_NO_DUMP=1; build "$root"; unset FIXTURE_NO_DUMP
expect "a missing dump returns 3, not 0" 3 "$root" "INCONCLUSIVE"

# 5 — the deliberately disabled layer the brief asks for by name
root="$SCRATCH/silenced"; export FIXTURE_SILENCE_STRUCTURE=1; build "$root"; unset FIXTURE_SILENCE_STRUCTURE
expect "a required layer marked optional returns 3, not 0" 3 "$root" "Only ['font-weight-face'] may be"

# 6 — a layer that ran and measured nothing, which is the failure mode this whole item is about
root="$SCRATCH/silent"; build "$root"
export STUB_TOKENS_SILENT=1; expect "a token suite that printed no marker returns 3, not 0" 3 "$root" "cannot be told from one that did not run"; unset STUB_TOKENS_SILENT

# 7 — a census smaller than its floor: the P4 failure, where coverage rises as measurement falls
root="$SCRATCH/shrunk"; build "$root"
export STUB_TOKEN_ROWS=4; expect "a shrunken token census returns 3, not 0" 3 "$root" "below the floor"; unset STUB_TOKEN_ROWS

# 8 — structure: a node that calls itself horizontal while its children stack vertically.
root="$SCRATCH/axis"; export FIXTURE_AXIS_LIE=1; build "$root"; unset FIXTURE_AXIS_LIE
expect "an axis the geometry contradicts returns 1" 1 "$root" "declares axis horizontal"

# 9 — geometry: a node that laid out to nothing. A zero-area frame diffs clean against every
# other zero-area frame, which is agreement between two absences.
root="$SCRATCH/zero"; export FIXTURE_ZERO_AREA=1; build "$root"; unset FIXTURE_ZERO_AREA
expect "a zero-area frame returns 1" 1 "$root" "zero-area frame"

# 10 — type-metrics: two nodes naming one type role, laid out at different single-line heights.
root="$SCRATCH/cascade"; export FIXTURE_CASCADE_LOST=1; build "$root"; unset FIXTURE_CASCADE_LOST
expect "one role measured at two heights returns 1" 1 "$root" "lost the cascade"

# 11 — breadth, forwards: a section in the build that nothing in the mock accounts for. Matching a
# mock means removing what it does not have, not only adding what it lacks.
root="$SCRATCH/extra"; export FIXTURE_EXTRA_NODE=1; build "$root"; unset FIXTURE_EXTRA_NODE
expect "a section the mock has no affordance for returns 1" 1 "$root" "is in the build and not in the mock"

# 12 — breadth, backwards: delete the pairing row for an affordance the mock draws. The review
# lane's finding 4 predicted this hides the row and returns 0, on the reading that the ledger
# trusts its own denominator. It does not: the inventory is re-derived from the mock every run, so
# a deleted pairing makes the affordance read `absent`, which is a finding.
root="$SCRATCH/unpaired"; export FIXTURE_DROP_PAIRING=1; build "$root"; unset FIXTURE_DROP_PAIRING
expect "deleting a pairing row returns 1, not 0" 1 "$root" "is absent from the build"

# 13 — the real colour-literal lint, against every colour-constructor spelling the `literals` layer
# claims to catch. Not the stub: this layer's whole value is that it EXECUTES that script, and on
# 21 Aug 2026 three of these spellings passed it clean while the M23 spec claimed otherwise.
#
# Driven through a scratch root, the same symlink trick the engine cases use: the script derives its
# root from its own `BASH_SOURCE`, and bash does not resolve a symlink there, so a link inside a temp
# directory makes every path it scans resolve inside that directory. The probe therefore never
# touches `app/Sources`, which matters because a run killed mid-loop would otherwise leave a file
# there that breaks the build and the board census — and a selftest that can damage the tree it is
# testing is worse than no selftest.
LINT_REAL="$REPO/scripts/lint/no-raw-design-values.sh"
LINT_ROOT="$SCRATCH/lintprobe"
# Every directory the script insists on finding. It exits 1 on a missing one by design — a `find`
# that matched nothing must not read as a clean pass — so the scratch root has to carry the whole
# shape, and a directory added to the real script's list makes the control below go red here rather
# than making these cases quietly meaningless.
mkdir -p "$LINT_ROOT/scripts/lint" "$LINT_ROOT/app/Sources/MCPRouterUI" \
         "$LINT_ROOT/app/Sources/MCPRouterUI/Shell" "$LINT_ROOT/app/Sources/MCPRouterUI/Activity" \
         "$LINT_ROOT/app/Sources/MCPRouterUI/Boards" \
         "$LINT_ROOT/app/Sources/MCPRouterKit" \
         "$LINT_ROOT/app/MCPRouter" "$LINT_ROOT/app/MCPRouterIOS"
ln -sf "$LINT_REAL" "$LINT_ROOT/scripts/lint/no-raw-design-values.sh"
# One file that must stay clean, so a lint that is red whatever you feed it cannot pass the cases
# below by accident.
cat > "$LINT_ROOT/app/Sources/MCPRouterUI/Boards/Control.swift" <<'CLEAN'
import SwiftUI
enum ControlProbe {
    static let tint = ColorToken.accent.color
    static var body: some View {
        Text("clean").typeRole(.body).frame(width: ServersBoardMetrics.nameColumn)
    }
}
CLEAN
: > "$LINT_ROOT/app/MCPRouter/Empty.swift"
: > "$LINT_ROOT/app/MCPRouterIOS/Empty.swift"
# The probe sits under Boards/ so it is read by the geometry rules as well as the colour ones,
# which is the directory a real violation would be written in.
PROBE="$LINT_ROOT/app/Sources/MCPRouterUI/Boards/Probe.swift"

cases=$((cases + 1))
if "$LINT_ROOT/scripts/lint/no-raw-design-values.sh" > /dev/null 2>&1; then
  echo "ok    the colour-literal lint is clean on a tree with no raw value in it"
else
  echo "FAIL  the colour-literal lint is red on a clean tree, so the spelling cases prove nothing"
  fail=1
fi

while IFS= read -r spelling; do
  [ -z "$spelling" ] && continue
  cases=$((cases + 1))
  printf 'import SwiftUI\nenum Probe { static let probe = %s }\n' "$spelling" > "$PROBE"
  if "$LINT_ROOT/scripts/lint/no-raw-design-values.sh" > /dev/null 2>&1; then
    echo "FAIL  the colour-literal lint let '$spelling' through"
    fail=1
  else
    echo "ok    the colour-literal lint catches $spelling"
  fi
  rm -f "$PROBE"
done <<'SPELLINGS'
Color(white: 0.5)
Color(hue: 0.5, saturation: 0.5, brightness: 0.5)
Color(red: 0.1, green: 0.2, blue: 0.3)
Color(.sRGB, red: 0.1, green: 0.2, blue: 0.3)
Color(.sRGBLinear, red: 0.1, green: 0.2, blue: 0.3)
Color(.displayP3, red: 0.1, green: 0.2, blue: 0.3)
Color(cgColor: someCGColor)
"#FF00FF"
SPELLINGS

# 14 — the gate script's own preflight, driven for real
cases=$((cases + 1))
./scripts/acceptance/mock-fidelity-gate.sh no-such-surface > /dev/null 2>&1
if [ $? = 3 ]; then
  echo "ok    an unknown surface returns 3 from the gate script — exit 3"
else
  echo "FAIL  an unknown surface should return 3 from the gate script"
  fail=1
fi

echo "mock-fidelity-selftest: $cases cases"
if [ "$fail" != 0 ]; then
  echo "mock-fidelity-selftest: FAILED — an exit the gate is supposed to reach was not reached."
  exit 1
fi
echo "mock-fidelity-selftest: all three exits observed"
exit 0
