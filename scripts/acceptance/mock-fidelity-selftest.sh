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
# The three standing gates on this item, with their commands. One of them spent four briefs in the
# gate list as "B 3 with a ledger written" with no surface, no command and no fixture recorded
# anywhere, so every pass reported it and no pass could run it — a gate in a standing list that
# nobody can run is a claim rather than a check.
#
#   A  ./scripts/acceptance/mock-fidelity-gate.sh
#      The real surface end to end. Needs the MEASURE build, so about three minutes and not
#      hermetic. Exit 1 with findings, and the ledger at planning/fidelity/servers.ledger.md.
#   B  python3 scripts/acceptance/mock_fidelity.py planning/fidelity/servers.layers.json \
#        /tmp/no-such-dumps --report /tmp/mock-fidelity-B.ledger.md
#      The third exit against the real manifest: a layer the verdict depends on could not read its
#      artifact. Exit 3, the obituary written to the report path and the marker emitted. Hermetic,
#      no build, and it writes nowhere the repo reads. Established 21 Aug 2026 — what pass 2 ran
#      under this letter was never written down and is not recoverable, so this is an equivalent
#      rather than a reproduction, and it is recorded here so the next pass has one to run.
#   C  this file. Exit 0, hermetic, about a second, and it reaches all three exits including B's.
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

  # The shipped inventory tool disambiguates two identical affordances as `…/shared` and
  # `…/shared#2`, so the engine is never handed a duplicate id BY IT. The engine does not require
  # that and nothing checks it, and the injectivity check reads a list keyed by id — so this
  # wrapper runs the real tool and drops the suffix, which is the inventory a hand-written pairing
  # tool, or the next version of this one, can hand it.
  if [ "${FIXTURE_DUP_ID:-0}" = "1" ]; then
    rm -f "$root/scripts/acceptance/mock-affordances.py"
    cat > "$root/scripts/acceptance/mock-affordances.py" <<DUP
import json, subprocess, sys
out = subprocess.run([sys.executable, "$AFFORDANCES"] + sys.argv[1:], capture_output=True, text=True)
if out.returncode != 0:
    sys.stderr.write(out.stderr)
    sys.exit(out.returncode)
data = json.loads(out.stdout)
for affordance in data["affordances"]:
    affordance["id"] = affordance["id"].split("#")[0]
print(json.dumps(data))
DUP
  fi

  cat > "$root/scripts/lint/no-raw-design-values.sh" <<'LINT'
#!/bin/bash
# Stub stand-in for the real colour-literal lint. Prints the same scan line the real one does,
# because the engine reads the file count off it and treats its absence as inconclusive.
echo "no-raw-design-values: scanning ${STUB_LINT_SCANNED:-3} files"
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
if [ "${STUB_TOKENS_GARBLED:-0}" = "1" ]; then
  # What the real suite prints with MCP_ROUTER_WRITE_TOKEN_REGISTER=1 in the environment: it
  # rewrites the register and returns BEFORE the census, so the marker is there and carries no
  # name=value fields at all.
  echo "MOCK-FIDELITY-TOKENS: register rewritten at planning/fidelity/token-register.json"
  exit 0
fi
# `matched` is derived rather than written, so the census partitions the row count the way the
# real suite's does. It used to be the constant 8 beside `rows=${STUB_TOKEN_ROWS:-12}`, so the
# shrunken-census case handed the engine `rows=4 matched=8 pending=4` — a marker claiming to
# account for 12 rows out of 4. The floor case passed on that, which is a fixture the engine's own
# census arithmetic now refuses, and rightly.
STUB_ROWS=${STUB_TOKEN_ROWS:-12}
STUB_PENDING=${STUB_TOKEN_PENDING:-4}
STUB_MATCHED=$((STUB_ROWS - STUB_PENDING))
if [ "${STUB_TOKENS_MISCOUNT:-0}" = "1" ]; then
  # A census that does not add up: the marker names a population this layer reports as its
  # `observations`, and nothing derived it. `rows` is whatever the suite says it is.
  STUB_MATCHED=$((STUB_MATCHED + 3))
fi
echo "MOCK-FIDELITY-TOKENS: rows=$STUB_ROWS matched=$STUB_MATCHED pending=$STUB_PENDING uncited=${STUB_TOKENS_UNCITED:-0}"
echo "MOCK-FIDELITY-PENDING: metric/jack-lane mock=44px swift=absent citation=M21-metric-rows"
echo "MOCK-FIDELITY-MOCK-LITERALS: stray=${STUB_MOCK_LITERALS:-0}"
exit "${STUB_TOKENS_EXIT:-0}"
SWIFT
  chmod +x "$root/bin/swift"

  python3 "$SCRATCH/build-fixture.py" "$root"
}

# Extends a scratch root so `mock-fidelity-gate.sh` itself can be driven against it. $1 = directory.
#
# The gate script's console decision — the three-branch block that turns REPORT_MARKER into
# `ledger written to <path>`, `NO ledger was written by this run` or `there is no file at <path>`
# — was declared uncoverable here until 21 Aug 2026, on the grounds that reaching it needs the
# MEASURE build and four rendered dumps: "three minutes and not hermetic". That was measurably
# false, and this helper is the disproof. The script resolves its root from `$0` and bash does not
# resolve a symlink there, so a link inside the scratch tree makes every path it touches resolve
# inside the scratch tree — the same trick the engine cases and the lint probe already use.
# `swift build --product MeasureDump` is answered by the `swift` stub `build` already writes, which
# exits 0 whatever it is handed. `MeasureDump` is the twelve lines below. The decision is reached
# in about a second and all three of its branches are driven, which is what stops the marker's only
# consumer being the one link in the chain nothing pulls on.
build_gate_root() {
  local root=$1
  build "$root"
  ln -sf "$REPO/scripts/acceptance/mock-fidelity-gate.sh" \
         "$root/scripts/acceptance/mock-fidelity-gate.sh"
  mkdir -p "$root/app/.build/debug" "$root/planning/fidelity/dumps"
  cat > "$root/app/.build/debug/MeasureDump" <<'MEASURE'
#!/bin/bash
# Stub stand-in for the MeasureDump product, with the two behaviours the gate script reads: it
# exits 3 on a --state it does not recognise and writes nothing — which is the gate's own preflight,
# asserted on every run — and otherwise writes that state's dump to --out. The dump is the one
# `build` has already generated, so the fixture the gate measures is the fixture the engine cases
# measure.
here=$(cd "$(dirname "$0")/../../.." && pwd)
state=""; out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --state) state=$2; shift 2;;
    --out) out=$2; shift 2;;
    *) shift;;
  esac
done
if [ "$state" != "ideal" ]; then
  echo "MeasureDump: unknown state '$state' — refusing rather than defaulting to ideal"
  exit 3
fi
cp "$here/dumps/fixture.ideal.json" "$out"
MEASURE
  chmod +x "$root/app/.build/debug/MeasureDump"
}

# $1 = case name, $2 = expected exit, $3 = scratch root, $4... = strings the report must contain.
# Several rather than one because an exit code and a reason are not the same claim as a STATUS: a
# row that reads `divergent` and one that reads `unclassified` print the same finding here, and
# only the layer's count line tells them apart.
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
    shift 3
    for want in "$@"; do
      [ -z "$want" ] && continue
      # A want written `!text` is a REFUTATION: the run must not say it. Two layers reading one
      # pairing can only be shown to agree by asserting that the second one stayed quiet, and an
      # assertion that only ever looks for presence cannot express that.
      if [ "${want:0:1}" = "!" ]; then
        if grep -qF -- "${want:1}" <<<"$out"; then
          echo "FAIL  $name — the report said what it must not: ${want:1}"
          echo "$out" | sed 's/^/        /'
          fail=1
        fi
        continue
      fi
      if ! grep -qF -- "$want" <<<"$out"; then
        echo "FAIL  $name — exit was right but the report never said: $want"
        echo "$out" | sed 's/^/        /'
        fail=1
      fi
    done
  fi
}

cat > "$SCRATCH/build-fixture.py" <<'PY'
"""Writes the scratch mock, manifest, pairing and dump for one selftest case."""
import json, os, sys

root = sys.argv[1]

extra_mock = ""
# A glyph with no label on either side. The mock's census carries it, the build draws it, and
# neither reports a string — which is the shape six of the servers ledger's ten `present` rows had.
if os.environ.get("FIXTURE_EMPTY_BOTH") == "1":
    extra_mock += '    <svg><use href="#i-warn"></use></svg>\n'
# A card, to be paired against a build node that calls itself something else entirely.
if os.environ.get("FIXTURE_KIND_MISMATCH") == "1":
    extra_mock += '    <div class="card">Panel</div>\n'
# Both sides carry one codepoint that renders as nothing. FIXTURE_INVISIBLE picks which, so the
# named route (U+200B) and a route of this runner's own (U+FEFF, U+00AD) are the same case with a
# different codepoint rather than three hand-written fixtures.
INVISIBLE = os.environ.get("FIXTURE_INVISIBLE") or ""
if INVISIBLE:
    extra_mock += f'    <h2>{INVISIBLE}</h2>\n'
# Two mock affordances pointed at one build control. `same` is the route the finding named — two
# headings, both vouched against that control and both reading its text, so nothing but the
# injectivity check can speak and the case is isolated. `cross` is this runner's own and the
# likelier accident: a heading and a sentence both answered by the one label the build draws,
# which also shows the check is on the node rather than on the kind.
CLAIM = os.environ.get("FIXTURE_DOUBLE_CLAIM") or ""
if CLAIM == "same":
    extra_mock += '    <h3>Shared</h3>\n    <h3>Shared</h3>\n'
elif CLAIM == "cross":
    extra_mock += '    <h3>Shared</h3>\n    <p>Shared</p>\n'
elif CLAIM == "same-copy":
    # Two headings with DIFFERENT labels, both pointed at one control. Both are vouched against it,
    # so the claimant test is the only thing that can speak — and the copy layer, which reads the
    # same pairings, has a genuine string difference to report on a pairing the breadth layer has
    # just recorded as unmeasurable.
    extra_mock += '    <h3>Alpha</h3>\n    <h3>Beta</h3>\n'
# A card the mock fills with TWO rows, against a build that draws three.
if os.environ.get("FIXTURE_SURPLUS_CHILD") == "1":
    extra_mock += (
        '    <div class="card">Rows\n'
        '      <div class="skel-row">Row one</div>\n'
        '      <div class="skel-row">Row two</div>\n'
        '    </div>\n'
    )

open(os.path.join(root, "design/fixture.html"), "w").write("""<!doctype html>
<section id="b-fixture">
  <div class="v v-ideal">
    <h1>Fixture</h1>
    <p>One sentence.</p>
    <button class="btn primary">Do the thing</button>
""" + extra_mock + """  </div>
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
        node("heading", "board-title", "text", (0, 0, 120, 26), text="Fixture", type_role="Title1"),
        node("sentence", "board-subtitle", "text", (0, 30, 200, 16), text="One sentence.",
             type_role="Body"),
        node("action", "primary-action", "leaf", (0, 50, 110, 24), text="Do the thing", type_role="Body"),
    ]),
}
if os.environ.get("FIXTURE_COPY_BLANK") == "1":
    # Every paired build node loses its string. The copy layer skips a pairing with nothing
    # readable on a side, so it runs with an empty population: it raises nothing, finds nothing,
    # and printed `clean`. No floor in the manifest covers `copy` and the layer has no guard of its
    # own — unlike type-metrics, which carries one, which is why this fixture uses copy.
    for child in dump["root"]["children"]:
        child["text"] = None
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
if os.environ.get("FIXTURE_EMPTY_BOTH") == "1":
    dump["root"]["children"].append(node("glyph", "state-illustration", "leaf", (0, 80, 16, 16)))
if INVISIBLE:
    # A vouched heading pair whose two strings are each one invisible codepoint. Truthy, equal, and
    # nothing a reader could see on either side.
    dump["root"]["children"].append(
        node("ghost", "board-title", "text", (0, 80, 40, 26), text=INVISIBLE, type_role="Title1")
    )
if CLAIM:
    dump["root"]["children"].append(
        node("shared", "board-title", "text", (0, 110, 90, 26),
             text="Alpha" if CLAIM == "same-copy" else "Shared", type_role="Title1")
    )
if os.environ.get("FIXTURE_MULTILINE") == "1":
    # A Body node laid out well past 1.5x the role's floor: a wrap count rather than a line box, so
    # the per-role height check excludes it. It is counted as an eligible text node and NOT as a
    # comparison, which is the split this fixture exists to show in the note.
    dump["root"]["children"].append(
        node("wrapped", "state-detail", "text", (0, 130, 200, 40), text="Two lines of copy here",
             type_role="Body")
    )
if os.environ.get("FIXTURE_DUP_PATH") == "1":
    # Two siblings carrying one id, so `flatten` produces one path twice and `dict(flatten(...))`
    # keeps whichever came last. A pairing naming that path does not name a control (`D-m23-m`).
    dump["root"]["children"].append(
        node("sentence", "board-subtitle", "text", (0, 150, 200, 16), text="Impostor",
             type_role="Body")
    )
if os.environ.get("FIXTURE_NO_AXIS") == "1":
    # Every `axis` key gone, and nothing else touched. The structure layer's job is corroborating a
    # declared axis against where the children landed, so this tree gives it nothing to corroborate
    # — while carrying the same 4 nodes, so the `dumpNodes` floor is untouched. It used to print
    # the identical `4 nodes across 1 states · clean` line as a fully instrumented tree and exit 0.
    # `axis` is nil wherever the kind does not stack, so a surface annotating leaves and skipping
    # containers reaches this.
    def strip_axis(n):
        n.pop("axis", None)
        for kid in n.get("children", []):
            strip_axis(kid)
    strip_axis(dump["root"])
if os.environ.get("FIXTURE_KIND_MISMATCH") == "1":
    # The label agrees exactly, so nothing but the control-kind check can speak here: a mock `card`
    # answered by a build node calling itself a `skeleton`.
    # FIXTURE_PANEL_TEXT is what the BUILD node reads. Left at "Panel" the two labels agree
    # exactly, so nothing but the control-kind check can speak. Set to something else, the copy
    # layer has a real string difference to report on a pairing the breadth layer has just filed as
    # one it could not establish was the same control at all.
    dump["root"]["children"].append(
        node("panel", "skeleton", "vstack", (0, 80, 200, 40),
             text=os.environ.get("FIXTURE_PANEL_TEXT") or "Panel")
    )
if os.environ.get("FIXTURE_SURPLUS_CHILD") == "1":
    dump["root"]["children"].append(
        node("rows", "table", "vstack", (0, 80, 200, 60),
             text="Rows Row one Row two", children=[
            node("skel-0", "skeleton-row", "hstack", (0, 80, 200, 16), text="Row one"),
            node("skel-1", "skeleton-row", "hstack", (0, 100, 200, 16), text="Row two"),
            node("skel-2", "skeleton-row", "hstack", (0, 120, 200, 16), text="Row three"),
        ])
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
    "floors": {"tokenRows": 10, "dumpNodes": 4, "affordances": 3, "lintFiles": 3},
    "layers": declared,
}, indent=1))

pairing = (
    "ideal\tv-ideal/heading/fixture\tfixture.ideal/heading\n"
    "ideal\tv-ideal/sentence/one-sentence\tfixture.ideal/sentence\n"
)
if os.environ.get("FIXTURE_DROP_PAIRING") != "1":
    pairing += "ideal\tv-ideal/button/do-the-thing\tfixture.ideal/action\n"
if os.environ.get("FIXTURE_EMPTY_BOTH") == "1":
    pairing += "ideal\tv-ideal/icon/unlabelled\tfixture.ideal/glyph\n"
if INVISIBLE:
    pairing += "ideal\tv-ideal/heading/unlabelled\tfixture.ideal/ghost\n"
if CLAIM == "same" and os.environ.get("FIXTURE_DUP_ID") == "1":
    # One pairing row, and an inventory whose two headings share the id it names. Both affordances
    # resolve through it, so the collision is inside the id rather than inside the pairing — and a
    # check that filtered the claimant list by `!= my_id` would remove both of them and see none.
    pairing += "ideal\tv-ideal/heading/shared\tfixture.ideal/shared\n"
elif CLAIM == "same":
    # Both are headings, both vouched against this control, both reading its text. Without the
    # injectivity check both read `present` and the tree is clean.
    pairing += ("ideal\tv-ideal/heading/shared\tfixture.ideal/shared\n"
                "ideal\tv-ideal/heading/shared#2\tfixture.ideal/shared\n")
elif CLAIM == "cross":
    pairing += ("ideal\tv-ideal/heading/shared\tfixture.ideal/shared\n"
                "ideal\tv-ideal/sentence/shared\tfixture.ideal/shared\n")
elif CLAIM == "same-copy":
    pairing += ("ideal\tv-ideal/heading/alpha\tfixture.ideal/shared\n"
                "ideal\tv-ideal/heading/beta\tfixture.ideal/shared\n")
if os.environ.get("FIXTURE_KIND_MISMATCH") == "1":
    pairing += "ideal\tv-ideal/card/panel\tfixture.ideal/panel\n"
if os.environ.get("FIXTURE_SURPLUS_CHILD") == "1":
    pairing += (
        "ideal\tv-ideal/card/rows-row-one-row-two\tfixture.ideal/rows\n"
        "ideal\tv-ideal/skeleton-row/row-one\tfixture.ideal/rows/skel-0\n"
        "ideal\tv-ideal/skeleton-row/row-two\tfixture.ideal/rows/skel-1\n"
    )
open(os.path.join(root, "planning/fidelity/fixture.pairing.tsv"), "w").write(pairing)

if os.environ.get("FIXTURE_NO_DUMP") == "1":
    os.remove(os.path.join(root, "dumps/fixture.ideal.json"))

# Four malformed artifacts, each raising a DIFFERENT exception type from a different frame. The
# point is the class rather than the list: every one of them used to escape main() uncaught, exit 1
# — the code that means differences were found — and leave the previous run's ledger on disk.
manifest_path = os.path.join(root, "planning/fidelity/fixture.layers.json")
broken = os.environ.get("FIXTURE_BROKEN") or ""
if broken == "manifest-no-floors":
    # KeyError in Context.__init__, which used to sit outside every try in main().
    m = json.load(open(manifest_path)); del m["floors"]
    json.dump(m, open(manifest_path, "w"), indent=1)
elif broken == "node-no-role":
    # KeyError deep inside layer_breadth, one frame further in than any guarded call.
    d = json.load(open(os.path.join(root, "dumps/fixture.ideal.json")))
    del d["root"]["children"][0]["role"]
    json.dump(d, open(os.path.join(root, "dumps/fixture.ideal.json"), "w"), indent=1)
elif broken == "floor-is-a-string":
    # A floor quoted rather than written as a number, the likeliest slip in a hand-authored
    # manifest. It used to raise TypeError from `int < str` inside layer_tokens; it is now caught
    # by the floor validation before any layer runs, which is why this case asserts that message
    # and `nodes-not-a-list` below carries the raw-TypeError route instead.
    m = json.load(open(manifest_path)); m["floors"]["tokenRows"] = "10"
    json.dump(m, open(manifest_path, "w"), indent=1)
elif broken == "duplicate-layer":
    # The dict comprehension that builds `declared` keeps the LAST entry of any repeated name, so
    # a required entry followed by an optional one for the same layer is silently demoted. The list
    # is longer than the dict built from it, and nothing compared the two lengths.
    #
    # `font-weight-face` rather than a livelier layer, so the case isolates: it is the one name in
    # `ALLOWED_OPTIONAL`, so both entries pass the optional validation and nothing but the length
    # check can speak. Without that check this manifest reads the trailing optional entry, exits 0,
    # and the required declaration at the top of the list has no effect on anything.
    m = json.load(open(manifest_path))
    m["layers"].insert(0, {"name": "font-weight-face", "required": True})
    json.dump(m, open(manifest_path, "w"), indent=1)
elif broken == "manifest-not-json":
    # The manifest replaced with bytes `json.load` refuses. `load_json` raises `Inconclusive` from
    # inside `measuring("manifest")`, which is the FIRST of `write_unmeasured_report`'s five callers
    # and the one the trace found nothing through: on the 59-case suite that shipped before the
    # sixth pass, 145 python3 processes, 52 of them engine runs and 10 of those carrying
    # `--report`, produced eight marker emissions and none on this route. Only an engine run can
    # reach it, both emission sites being engine code, and case 61 below is what reaches it now.
    open(manifest_path, "w").write("{ this is not json\n")
elif broken == "unknown-layer":
    # Not an exception at all — a manifest that fails validation. It returned 3 correctly and
    # returned it from a `print`/`return 3` pair that never touched the report, so the previous
    # run's table stayed on disk under a run that measured nothing. Same stale ledger, reached by
    # a check that failed rather than by a raise.
    m = json.load(open(manifest_path)); m["layers"].append({"name": "colour", "required": True})
    json.dump(m, open(manifest_path, "w"), indent=1)
elif broken == "floor-is-zero":
    # A floor of zero is not a floor: `observations < 0` is false for a layer that measured
    # nothing, so `lintFiles: 0` restores the exact defect the floor was added to close.
    m = json.load(open(manifest_path)); m["floors"]["lintFiles"] = 0
    json.dump(m, open(manifest_path, "w"), indent=1)
elif broken == "nodes-not-a-list":
    # A raw TypeError from a frame inside a layer, kept because the two floor fixtures above are
    # now caught by an explicit check and no longer exercise the generic boundary.
    d = json.load(open(os.path.join(root, "dumps/fixture.ideal.json")))
    d["root"]["children"] = "not a list of nodes"
    json.dump(d, open(os.path.join(root, "dumps/fixture.ideal.json"), "w"), indent=1)
elif broken == "ladder-no-size":
    # This runner's second: a type ladder whose role carries no size. KeyError inside
    # layer_type_metrics' ordering pass, which no lane enumerated either.
    d = json.load(open(os.path.join(root, "dumps/fixture.ideal.json")))
    del d["typeLadder"]["Body"]["size"]
    json.dump(d, open(os.path.join(root, "dumps/fixture.ideal.json"), "w"), indent=1)
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

# 13 — breadth, G1(a): a pairing where NEITHER side carries a string. Agreement between two
# absences is not a measurement, so this is `unclassified` rather than `present`. Six of the ten
# `present` rows in planning/fidelity/servers.ledger.md had exactly this shape.
root="$SCRATCH/emptyboth"; export FIXTURE_EMPTY_BOTH=1; build "$root"; unset FIXTURE_EMPTY_BOTH
expect "a pair with no string on either side returns 1" 1 "$root" "Agreement between two absences is not a measurement"

# 14 — breadth, G1(b): the labels agree exactly and the CONTROL does not. Two controls doing the
# same job are not a match, so the mock kind is checked against the role and kind the view reported.
root="$SCRATCH/kind"; export FIXTURE_KIND_MISMATCH=1; build "$root"; unset FIXTURE_KIND_MISMATCH
# The two labels agree exactly here, so the old `divergent` was claiming a measured difference
# that does not exist. `D-m23-l`: a pairing the gate has never vouched for is a comparison it could
# not make, which is `unclassified`. Asserted on the layer's own count line, because both statuses
# print the same finding text.
expect "a mock card answered by a build skeleton returns 1" 1 "$root" "never vouched for" "unclassified 1"

# 15 — breadth, G2: the mock's census reaches this granularity and names two rows; the build draws
# three. Under the blanket `inside_a_pair` exemption this read `covered-by-pair` and said nothing.
root="$SCRATCH/surplus"; export FIXTURE_SURPLUS_CHILD=1; build "$root"; unset FIXTURE_SURPLUS_CHILD
expect "a build child past the mock's count returns 1" 1 "$root" "and this one answers none"

# 16 — tokens, G3: the marker is printed and carries no census fields. It is what the real suite
# prints with MCP_ROUTER_WRITE_TOKEN_REGISTER=1 in the environment, and unguarded it raised an
# uncaught ValueError — exit 1, the code that means differences were found, with the report never
# written and a stale ledger left on disk beside it.
root="$SCRATCH/garbled"; build "$root"
export STUB_TOKENS_GARBLED=1
expect "an unparseable token marker returns 3, not 1" 3 "$root" "does not carry the name=value census fields"
unset STUB_TOKENS_GARBLED

# 17 — B1: a required layer that scanned nothing. The literals layer reads the lint's file count
# because a lint that scanned nothing and one that found nothing print the same exit code — and it
# compared that count to nothing, so this returned `literals ran · scanning 0 files · clean` and the
# whole gate exited 0. A required layer measuring nothing, reported as a pass.
root="$SCRATCH/scan0"; build "$root"
export STUB_LINT_SCANNED=0
expect "a lint that scanned nothing returns 3, not 0" 3 "$root" "below the floor of 3"
unset STUB_LINT_SCANNED

# 18 — B1, a route the finding did not name: a scan that is NON-ZERO and below its floor. A
# zero-check would pass this; a floor does not. It is the difference between testing the sentinel
# and testing the quantity.
root="$SCRATCH/scan2"; build "$root"
export STUB_LINT_SCANNED=2
expect "a lint scanning fewer files than its floor returns 3" 3 "$root" "the lint scanned 2 files"
unset STUB_LINT_SCANNED

# 19-22 — B2: four malformed artifacts, four exception types, four frames. Each used to escape
# main() uncaught and exit 1 with the previous run's ledger still on disk. The last two are routes
# this runner chose rather than ones the findings named.
for case in manifest-no-floors node-no-role ladder-no-size nodes-not-a-list; do
  root="$SCRATCH/broken-$case"; export FIXTURE_BROKEN=$case; build "$root"; unset FIXTURE_BROKEN
  expect "a malformed artifact ($case) returns 3, not 1" 3 "$root" "Nothing this covers was measured"
done

# 23 — B2: the ledger a run that measured nothing leaves behind. Fixing the exit code fixes half of
# the stale-ledger failure; a reader who opens the file still finds the last good run's table.
root="$SCRATCH/stale"; build "$root"
cases=$((cases + 1))
LEDGER="$SCRATCH/stale-ledger.md"
printf '# Breadth ledger — fixture\n\n| Layer | Result |\n|---|---|\n| `breadth` | clean |\n' > "$LEDGER"
export FIXTURE_BROKEN=manifest-no-floors; build "$root"; unset FIXTURE_BROKEN
PATH="$root/bin:$PATH" python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$root/planning/fidelity/fixture.layers.json" "$root/dumps" --report "$LEDGER" > /dev/null 2>&1
if grep -q 'This run did not produce a table' "$LEDGER" && ! grep -q '`breadth` | clean' "$LEDGER"; then
  echo "ok    a run that measured nothing overwrites the stale ledger"
else
  echo "FAIL  the stale ledger survived a run that measured nothing"
  fail=1
fi

# 24-28 — B3: `present` required truthiness, not readable content. Each of these is one codepoint
# that renders as nothing and that `str.split()` does not drop, on a vouched heading pair whose two
# strings are equal. U+200B is the route the finding named; the rest are not. U+3164 HANGUL FILLER
# is the interesting one: it is category `Lo`, a LETTER, so the category test that catches the other
# three cannot see it, and it is the reason `readable()` carries a codepoint list as well as a
# category test.
while IFS='	' read -r label codepoint; do
  [ -z "$label" ] && continue
  root="$SCRATCH/invis-$label"
  export FIXTURE_INVISIBLE=$codepoint; build "$root"; unset FIXTURE_INVISIBLE
  expect "two $label strings read unclassified, not present" 1 "$root" "render as nothing"
done <<SPELLINGS
U+200B	​
U+FEFF	﻿
U+00AD	­
U+3164	ㅤ
U+034F	͏
SPELLINGS

# 28 — B4: one build control named by two mock affordances. Neither was measured: whichever the
# control answers, the other earned `present` off a measurement of something else. Different kinds
# rather than the two headings the finding named — the likelier accident, and it proves the check
# is on the node rather than on the kind.
root="$SCRATCH/claim-same"; export FIXTURE_DOUBLE_CLAIM=same; build "$root"; unset FIXTURE_DOUBLE_CLAIM
expect "one control named by two headings returns 1, not 0" 1 "$root" "affordances name in total"

# 29 — B4, this runner's own route: the two claimants are different KINDS, which is the likelier
# accident and shows the check is on the node rather than on the kind.
root="$SCRATCH/claim-cross"; export FIXTURE_DOUBLE_CLAIM=cross; build "$root"; unset FIXTURE_DOUBLE_CLAIM
expect "one control named by a heading and a sentence returns 1" 1 "$root" "affordances name in total"

# 30 — B1, the floor's own hole: `observations < floor` is false at `0 < 0`, so a manifest that
# writes `lintFiles: 0` restores the defect the floor closes, through the floor. The comparison
# cannot catch this, because the comparison is what is being defeated.
root="$SCRATCH/floor0"; export FIXTURE_BROKEN=floor-is-zero; build "$root"; unset FIXTURE_BROKEN
expect "a floor of zero returns 3, not 0" 3 "$root" "has to be a positive"

# 31 — the same check's other half: a floor quoted as a string. It used to reach layer_tokens and
# raise; it is now named before any layer runs.
root="$SCRATCH/floorstr"; export FIXTURE_BROKEN=floor-is-a-string; build "$root"; unset FIXTURE_BROKEN
expect "a floor that is a string returns 3" 3 "$root" "has to be a positive"

# 32 — B2 through a door that is not an exception: a manifest naming a layer this gate cannot run
# fails validation, which returned 3 from a `print`/`return` pair that never wrote a report. Exit
# and ledger are separate claims, so this asserts both.
root="$SCRATCH/unknown-layer"; LEDGER32="$SCRATCH/unknown-layer-ledger.md"
printf '# Breadth ledger — fixture\n\n| Layer | Result |\n|---|---|\n| `breadth` | clean |\n' > "$LEDGER32"
export FIXTURE_BROKEN=unknown-layer; build "$root"; unset FIXTURE_BROKEN
cases=$((cases + 1))
out32=$(PATH="$root/bin:$PATH" python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$root/planning/fidelity/fixture.layers.json" "$root/dumps" --report "$LEDGER32" 2>&1)
status32=$?
# The marker clause covers the SECOND of `write_unmeasured_report`'s five callers — the
# `unmeasured()` helper, which is where all six manifest-validation returns leave the run. Case 49
# covers the third (an `Inconclusive` from `Context`), and until this clause those were the same
# assertion: moving `emit(REPORT_MARKER + path)` out of `write_unmeasured_report` and into case
# 49's own call site left all 59 cases green while this route lost the marker and the gate denied
# an obituary it had just written.
if [ "$status32" = 3 ] && grep -q 'This run did not produce a table' "$LEDGER32" \
   && grep -qF "mock-fidelity: report written to $LEDGER32" <<<"$out32" \
   && ! grep -q '`breadth` | clean' "$LEDGER32"; then
  echo "ok    a manifest that fails validation returns 3 AND replaces the stale ledger"
else
  echo "FAIL  a validation failure returned $status32 and left this ledger: $(head -3 "$LEDGER32" | tr '\n' ' ')"
  echo "$out32" | sed 's/^/        /'
  fail=1
fi

# 33 — and when the ledger cannot be replaced at all. Suppressing the error made "replaced" and
# "could not replace, so what you are reading is an earlier run" print the same nothing, which is
# the stale ledger with a permission bit in front of it. The exit stays 3 and the run says so.
root="$SCRATCH/nowrite-root"; export FIXTURE_BROKEN=manifest-no-floors; build "$root"; unset FIXTURE_BROKEN
mkdir -p "$SCRATCH/nowrite"; chmod 500 "$SCRATCH/nowrite"
cases=$((cases + 1))
out33=$(PATH="$root/bin:$PATH" python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$root/planning/fidelity/fixture.layers.json" "$root/dumps" \
  --report "$SCRATCH/nowrite/ledger.md" 2>&1)
status33=$?
chmod 700 "$SCRATCH/nowrite"
if [ "$status33" = 3 ] && grep -qF 'could not be replaced' <<<"$out33"; then
  echo "ok    a ledger that cannot be written is reported rather than suppressed"
else
  echo "FAIL  an unwritable ledger returned $status33 and said nothing about it"
  echo "$out33" | sed 's/^/        /'
  fail=1
fi

# 34 — B4, the route the injectivity check itself could be defeated through: two inventory entries
# carrying ONE id, both naming one control. `[o for o in claimants if o != my_id]` removes both
# occurrences, so each row sees an empty list and earns `present` off a single measurement — the
# original defect, reached through the duplicate rather than through the pairing. Counting the
# claimants reads the quantity the check is named for.
root="$SCRATCH/dup-id"
export FIXTURE_DOUBLE_CLAIM=same FIXTURE_DUP_ID=1; build "$root"; unset FIXTURE_DOUBLE_CLAIM FIXTURE_DUP_ID
expect "two affordances sharing one id return 1, not 0" 1 "$root" "affordances name in total"

# 35 — B1 at the scope of the property rather than of the layer that had the defect. Every paired
# build node loses its string, so `copy` runs with an empty population: it raises nothing, finds
# nothing, and no floor in the manifest covers it. Writing one floor per layer closes a list; a
# required layer that measured nothing reading inconclusive closes the class.
root="$SCRATCH/no-type"; export FIXTURE_COPY_BLANK=1; build "$root"; unset FIXTURE_COPY_BLANK
expect "a required layer with an empty population returns 3, not 0" 3 "$root" "measured nothing — 0"

# 36 — a manifest that names one layer twice. The second entry, optional and substituted, replaces
# the first in the dict `declared` is built from, and the required layer stops being required
# without anything saying so.
root="$SCRATCH/dup-layer"; export FIXTURE_BROKEN=duplicate-layer; build "$root"; unset FIXTURE_BROKEN
expect "a manifest naming one layer twice returns 3" 3 "$root" "appears twice"

# ---------------------------------------------------------------- the out-of-family panel's five
# Every case below came back from `gpt-5.6-sol`, `gemini-3.7-flash-high` or `grok-4.6` against the
# diff that closed BL-1 to BL-3. Two of the three enumerations were incomplete when they read them.

# 47 — BL-2 from the node side. The claimant test establishes that one control answers one mock
# affordance, and it rests on a pairing's node path naming ONE control. `dict(flatten(...))` keeps
# the last node of a repeated path silently, so two siblings sharing an id make a pairing to that
# path vouch for whichever survived. Registered as `D-m23-m` and reached again here by
# `gpt-5.6-sol`, which is why it is closed rather than deferred a third time.
root="$SCRATCH/duppath"; export FIXTURE_DUP_PATH=1; build "$root"; unset FIXTURE_DUP_PATH
expect "two siblings sharing a path return 3, not a vouched comparison" 3 "$root" \
  "does not name a control"

# 48 — BL-3 in the layer two lanes reached independently after the first three were closed.
# `layer_type_metrics` counted every text node naming a role and then excluded the multi-line ones
# from the per-role check with a `continue`, so its population was the eligibility census rather
# than the comparisons it ran. The zero-guard cannot be fooled here — `floor = min(...)` keeps one
# node per role — so this is asserted on the note, which is where the overstatement was printed.
#
# Both assertions read the comparison count, because the second one used to not. `1 multi-line
# node(s) excluded` is a true sentence about a quantity the mutation does not touch: reverting
# `observations` to the eligibility census takes the note to `3 per-role comparison(s) over 3 text
# nodes · … · 1 multi-line node(s) excluded`, which reddens the first want and leaves the second
# one word-for-word intact (measured). So the case was armed by one of its two assertions, and the
# other was this item's own defect — an assertion satisfied by something that survives the mutation
# it is written under — sitting inside the instrument that proves the gate (`D-m23-ah`).
#
# The repair is to assert the PARTITION rather than the two sentences. Every text node that names a
# ladder role either gets compared or gets excluded as a wrap count, so `comparisons + excluded ==
# census` is an identity of the layer rather than a fact about this fixture, and it is the sentence
# `reports comparisons and census separately` actually claims.
#
# The identity has to be asserted BEFORE the fixture's numbers, and that is `D-m23-aj`. Written as a
# fifth conjunct after `cmp = 2`, `census = 3` and `excl = 1`, it could only ever reduce to 3 = 3:
# any value that differs reddens a literal and the `&&` chain short-circuits before the identity is
# reached, so under both of this case's own mutations it was never evaluated. Decoration inside the
# instrument that proves the gate is the same defect this item exists to catch, one level in.
#
# So the identity leads and the fixture's shape follows it as floors. `cmp >= 2`, `excl >= 1` and
# `census = 3` give up nothing the three literals caught — with the identity they pin cmp to 2 and
# excl to 1 exactly — while leaving the identity room to fire. The census mutation gives 3 + 1 = 3
# and dropping the exclusion counter gives 2 + 0 = 3; both are now red AT THE IDENTITY, and deleting
# the identity takes the census mutation green, which is the measurement that says it carries load.
# The floors are what stop a fixture that quietly stopped producing a multi-line node satisfying the
# identity at 0 + 0 == 0.
root="$SCRATCH/multiline"; export FIXTURE_MULTILINE=1; build "$root"; unset FIXTURE_MULTILINE
cases=$((cases + 1))
out48=$(PATH="$root/bin:$PATH" python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$root/planning/fidelity/fixture.layers.json" "$root/dumps" 2>&1)
status48=$?
RE_CMP='([0-9]+) per-role comparison\(s\) over ([0-9]+) text nodes'
RE_EXCL='([0-9]+) multi-line node\(s\) excluded'
# `excl48` starts at 0 rather than the empty string because the note only prints the excluded clause
# when something was excluded, so an absent clause means zero excluded rather than an unreadable
# note — and the floor below needs a number. An unmatched RE_CMP leaves cmp48 and census48 empty,
# where the identity reads 0 = "" and reddens, short-circuiting before either floor sees a non-integer.
cmp48=""; census48=""; excl48=0
[[ "$out48" =~ $RE_CMP ]] && { cmp48=${BASH_REMATCH[1]}; census48=${BASH_REMATCH[2]}; }
[[ "$out48" =~ $RE_EXCL ]] && excl48=${BASH_REMATCH[1]}
if [ "$status48" = 1 ] && [ "$((cmp48 + excl48))" = "$census48" ] \
   && [ "$cmp48" -ge 2 ] && [ "$excl48" -ge 1 ] && [ "$census48" = 3 ]; then
  echo "ok    the type layer reports comparisons and census separately — $cmp48 + $excl48 = $census48"
else
  echo "FAIL  the type layer's note does not partition its census: exit $status48, comparisons"
  echo "      '$cmp48', census '$census48', excluded '$excl48'"
  echo "$out48" | sed 's/^/        /'
  fail=1
fi

# 49 — BL-1: the reporting of a failure must not itself be able to fail. `gate()`'s INCONCLUSIVE
# handlers used a raw `print`, so an unencodable console raised BEFORE `write_unmeasured_report`,
# the top-level boundary caught the encoding error instead, and the ledger recorded that rather
# than the reason the run was actually inconclusive (`gemini-3.7-flash-high`).
root="$SCRATCH/ascii-domain"; export FIXTURE_NO_DUMP=1; build "$root"; unset FIXTURE_NO_DUMP
LEDGER49="$SCRATCH/ascii-domain-ledger.md"
cases=$((cases + 1))
out49=$(PATH="$root/bin:$PATH" PYTHONIOENCODING=ascii python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$root/planning/fidelity/fixture.layers.json" "$root/dumps" --report "$LEDGER49" 2>&1)
status49=$?
# The marker clause covers the WRITABLE obituary, which nothing else here reaches.
# `write_unmeasured_report` emits `REPORT_MARKER` too, and case 51's failing write points at an
# UNwritable directory where `open()` raises and the marker is correctly absent — so this is the
# only run in the file that replaces a ledger with an obituary a path actually accepted. Dropping
# `emit(REPORT_MARKER + path)` from `write_unmeasured_report` leaves all 59 cases green while
# `mock-fidelity-gate.sh` denies a ledger it did write (`gemini-3.7-flash-high`, asked to break
# rather than review).
if [ "$status49" = 3 ] && grep -qF 'no artifact at' "$LEDGER49" \
   && grep -qF "mock-fidelity: report written to $LEDGER49" <<<"$out49" \
   && ! grep -qF 'UnicodeEncodeError' "$LEDGER49"; then
  echo "ok    an unencodable console does not replace the reason a run was inconclusive"
else
  echo "FAIL  the domain reason was lost: exit $status49, ledger: $(head -12 "$LEDGER49" | tr '\n' ' ' | cut -c1-220)"
  echo "$out49" | sed 's/^/        /'
  fail=1
fi

# 50 — BL-1, region two, both standard streams. `> >(:) 2>&1` points stderr at the same dead pipe,
# which is the ordinary spelling of the `| head` route this gate was measured against. Flushing and
# hushing stdout alone left the interpreter's shutdown flush of stderr to exit 120
# (`gemini-3.7-flash-high`, `grok-4.6` — both, independently).
root="$SCRATCH/bothpipes"; build "$root"
cases=$((cases + 1))
PATH="$root/bin:$PATH" python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$root/planning/fidelity/fixture.layers.json" "$root/dumps" > >(:) 2>&1
status50=$?
if [ "$status50" = 3 ]; then
  echo "ok    stdout and stderr on one dead pipe returns 3, not 120 — exit $status50"
else
  echo "FAIL  both streams on a dead pipe returned $status50, not 3"
  fail=1
fi

# 51 — the ledger claim is the WRITER's, not an inference from the clock. An mtime is not an
# ownership token: a stale ledger with a future timestamp is already newer than any stamp the gate
# script could take, and a concurrent run writing the same path satisfies the same test
# (`gpt-5.6-sol`). The engine prints the marker the script reads, and prints it only after a write
# that returned.
root="$SCRATCH/marker"; build "$root"
LEDGER51="$SCRATCH/marker-ledger.md"
cases=$((cases + 1))
out51=$(PATH="$root/bin:$PATH" python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$root/planning/fidelity/fixture.layers.json" "$root/dumps" --report "$LEDGER51" 2>&1)
out51_none=$(PATH="$root/bin:$PATH" python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$root/planning/fidelity/fixture.layers.json" "$root/dumps" 2>&1)
# The third invocation, and the only one of the three that can discriminate. In the first the write
# succeeds, so the marker is printed whichever side of `write_report` the `emit` sits on; in the
# second there is no `--report` at all, so `if report_path:` is false and the marker is unreachable
# either way. Both of those stay green with the `emit` moved BEFORE the write — measured, and it is
# what the fourth verification bounced this item for. The one configuration in which the two
# orderings differ is a `--report` path whose WRITE FAILS, and it is case 33's `chmod 500` fixture
# under a root that reaches the report block: a clean tree, eight layers measured, and an OSError
# from `open()`. The marker moved before the write prints `report written to` on a run that wrote
# nothing, and `mock-fidelity-gate.sh` greps for exactly that string to decide whether to print
# `ledger written to` — so this assertion is the one holding `D-m23-y` shut.
#
# Its own directory rather than case 33's, which is chmod'ed back to 700 as that case ends: sharing
# the path would make this case's result depend on the order the two run in.
mkdir -p "$SCRATCH/nowrite51"; chmod 500 "$SCRATCH/nowrite51"
out51_fail=$(PATH="$root/bin:$PATH" python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$root/planning/fidelity/fixture.layers.json" "$root/dumps" \
  --report "$SCRATCH/nowrite51/ledger.md" 2>&1)
status51_fail=$?
chmod 700 "$SCRATCH/nowrite51"

# The fourth invocation passes a `--report` the caller spelled RELATIVE, and it is what pins the
# marker to the path the engine was HANDED rather than one it derived. `mock-fidelity-gate.sh`
# greps for `REPORT_MARKER + $LEDGER` with `$LEDGER` relative to the repo root, so wrapping
# `report_path` in `os.path.abspath()` — an edit that reads as a tidy-up — makes the real gate deny
# its own table. Every other `--report` in this file is already an absolute path under `$SCRATCH`,
# where `abspath` is the identity, so that edit left all 59 cases green. Measured on the live gate:
# the engine wrote the table and exited 1 at 132 findings, and the wrapper printed `NO ledger was
# written by this run (exit 1) … is an earlier run's and does not describe this one` over it. The
# engine resolves its own root from `__file__`, so running from `$root` changes nothing but this
# argument (`claude-fable-5`, asked to break rather than review).
#
# The leading `./` is `D-m23-ap` a second time, and it is not decoration. `abspath` was one of a
# family of path-tidying edits, and the two spellings that closure pinned — an absolute path under
# `$SCRATCH`, and a bare relative name — are both FIXED POINTS of `os.path.normpath`, so
# `emit(REPORT_MARKER + os.path.normpath(report_path))` left all 59 cases green. `./rel-ledger.md`
# is a fixed point of neither: it normalises to `rel-ledger.md` and absolutises to `$root/…`, so
# one spelling now reds every member of the family rather than one of them. It is still the path
# the caller handed over, which is the property being pinned — `mock-fidelity-gate.sh` greps for
# `REPORT_MARKER + $LEDGER` verbatim, so any spelling the engine prefers to the caller's makes the
# real gate deny its own table.
out51_rel=$(cd "$root" && PATH="$root/bin:$PATH" python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$root/planning/fidelity/fixture.layers.json" "$root/dumps" --report "./rel-ledger.md" 2>&1)
if grep -qF "mock-fidelity: report written to $LEDGER51" <<<"$out51" \
   && ! grep -qF "report written to" <<<"$out51_none" \
   && [ "$status51_fail" = 3 ] \
   && ! grep -qF "report written to" <<<"$out51_fail" \
   && grep -qF "could not be replaced" <<<"$out51_fail" \
   && grep -qF "mock-fidelity: report written to ./rel-ledger.md" <<<"$out51_rel" \
   && [ -f "$root/rel-ledger.md" ]; then
  echo "ok    the engine claims a written report only when it wrote one"
else
  echo "FAIL  the report-written marker does not track the write (unwritable run exited $status51_fail)"
  echo "$out51" | sed 's/^/        /'
  echo "$out51_fail" | sed 's/^/        /'
  fail=1
fi

# ---------------------------------------------------------------- the third gap-fix's three
# Each of the three below is a property whose previous fix landed at the site the finding named
# while the property quantified over something wider — the failure mode that produced three
# Needs-More-Work verdicts in a row. The cases are written against the widest member.

# 39 — BL-3: a dump with every `axis` key removed. The structure layer corroborates declared axes
# against child geometry, and this tree declares none, so it makes zero comparisons — while
# carrying the same node count, so its floor is untouched. `observations` was the node census, so
# the layer-wide zero-observation guard read a quantity this layer never compares and this printed
# the same `clean` line as a fully instrumented surface, at exit 0.
root="$SCRATCH/no-axis"; export FIXTURE_NO_AXIS=1; build "$root"; unset FIXTURE_NO_AXIS
expect "a dump with no declared axis returns 3, not 0" 3 "$root" "structure: the layer ran, raised nothing and measured nothing"

# 40 — BL-3 in the other layer whose `observations` is a number it is handed rather than one it
# derives. The tokens layer reports `rows` as its population and the `tokenRows` floor reads it;
# nothing checked that the census it prints beside it adds up to that number (`D-m23-o`).
root="$SCRATCH/miscount"; build "$root"
export STUB_TOKENS_MISCOUNT=1
expect "a token census that does not partition its rows returns 3" 3 "$root" "does not partition the population"
unset STUB_TOKENS_MISCOUNT

# 41 — BL-2 / `D-m23-s`: an unvouched pairing whose two labels differ. The breadth layer records
# that it could not establish the two are the same control; the copy layer read the same
# `ctx.pairs` with no such test and stated the difference between their labels as a measured one,
# three lines below in the same log. Both tests now live in the structure, so the second reader
# cannot contradict the first.
root="$SCRATCH/unvouched-copy"
export FIXTURE_KIND_MISMATCH=1 FIXTURE_PANEL_TEXT="Different words"; build "$root"
unset FIXTURE_KIND_MISMATCH FIXTURE_PANEL_TEXT
expect "copy stays silent on a pairing breadth could not vouch for" 1 "$root" \
  "never vouched for" '!Different words" in the build'

# 42 — BL-2, the claimant half of the same property. Two headings with different labels naming one
# control: breadth reports that neither was measured, and copy reported the difference between one
# of those labels and the control's text as a finding.
root="$SCRATCH/claim-copy"; export FIXTURE_DOUBLE_CLAIM=same-copy; build "$root"; unset FIXTURE_DOUBLE_CLAIM
expect "copy stays silent on a control two affordances name" 1 "$root" \
  "affordances name in total" '!in the mock and'

# 43 — BL-1: a console that cannot encode what the gate prints. The layer lines carry `·`, so
# `PYTHONIOENCODING=ascii` raises inside the print loop — which sat between the layers and the
# report write, outside every boundary. It exited 1, the code that means differences were found,
# with the report never written and the previous run's table intact on disk. The report is now
# written first and the whole of the run is inside one boundary, so this is exit 3 AND the ledger
# on disk is this run's real table rather than an earlier run's.
root="$SCRATCH/ascii"; build "$root"
LEDGER43="$SCRATCH/ascii-ledger.md"
printf '# Breadth ledger — fixture\n\n| Layer | Result |\n|---|---|\n| `breadth` | STALE-FROM-AN-EARLIER-RUN |\n' > "$LEDGER43"
cases=$((cases + 1))
out43=$(PATH="$root/bin:$PATH" PYTHONIOENCODING=ascii python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$root/planning/fidelity/fixture.layers.json" "$root/dumps" --report "$LEDGER43" 2>&1)
status43=$?
# The last clause is the diagnostic's own honesty: a failure AFTER the report was written has
# measured eight layers, and saying "nothing this covers was measured" one line above "the ledger
# describes the layers that ran" is the gate contradicting itself (`gpt-5.6-sol`).
#
# The marker clause is what makes the ledger's DELIVERY armed rather than only its write. `emit`
# falls back to stderr precisely so "a console that cannot encode the report still delivers it",
# and `mock-fidelity-gate.sh` greps for that one literal to decide between `ledger written to <path>`
# and `NO ledger was written by this run`. Before this clause the suite pinned the marker's presence
# on success (case 51's first invocation) and its absence on a failed write (its third), and nothing
# at all about the case where the write SUCCEEDS and a later print raises. Deferring the emit to
# after the console loop under `if report_path and run.report_written:` leaves every other assertion
# in this case word-for-word true — exit 3, this run's table on disk, both diagnostics — while the
# marker reaches neither stream and the gate denies its own ledger (`gemini-3.7-flash-high`).
if [ "$status43" = 3 ] && grep -qF 'UnicodeEncodeError' <<<"$out43" \
   && ! grep -qF 'STALE-FROM-AN-EARLIER-RUN' "$LEDGER43" \
   && grep -qF 'Present / divergent / absent' "$LEDGER43" \
   && grep -qF "mock-fidelity: report written to $LEDGER43" <<<"$out43" \
   && grep -qF 'The layers ran and the ledger was written' <<<"$out43" \
   && ! grep -qF 'Nothing this covers was measured' <<<"$out43"; then
  echo "ok    a console that cannot encode the report returns 3 with this run's table on disk"
else
  echo "FAIL  a non-encodable console returned $status43, ledger head: $(head -5 "$LEDGER43" | tr '\n' ' ')"
  echo "$out43" | sed 's/^/        /'
  fail=1
fi

# 44 — BL-1 at the widest member there is: outside `main()` altogether. A `print` to a pipe whose
# reader has gone does not raise at the print — the text sits in the buffer — so CPython raises
# during the shutdown flush, after `main()` has returned and after every boundary in the file has
# been left. It prints `Exception ignored` and exits **120**, which is not one of this gate's three
# exits and which `mock-fidelity-gate.sh` passes through as though it were a verdict. Flushing
# stdout inside the boundary is what moves it back in. `>(:)` is a process substitution whose
# reader exits immediately, which is the deterministic form of `| head`.
root="$SCRATCH/brokenpipe"; build "$root"
LEDGER44="$SCRATCH/brokenpipe-ledger.md"
LEDGER44U="$SCRATCH/brokenpipe-unbuffered-ledger.md"
# stderr goes to a file rather than to /dev/null, and that is `D-m23-ar`. Both invocations below
# drive stdout-dead-with-stderr-open — the one configuration in which `emit`'s fallback is the only
# thing that can carry the marker — and both used to throw the fallback away, so replacing
# `emit(REPORT_MARKER + report_path)` with a bare `print` left the suite at 59 green while the
# marker reached no stream at all. The register said this route was driven by no case; it was
# driven by two and asserted by neither.
ERR44="$SCRATCH/brokenpipe-stderr.txt"
ERR44U="$SCRATCH/brokenpipe-unbuffered-stderr.txt"
printf '# Breadth ledger — fixture\n\n| Layer | Result |\n|---|---|\n| `breadth` | STALE-FROM-AN-EARLIER-RUN |\n' > "$LEDGER44"
cases=$((cases + 1))
PATH="$root/bin:$PATH" python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$root/planning/fidelity/fixture.layers.json" "$root/dumps" --report "$LEDGER44" > >(:) 2>"$ERR44"
status44=$?
# The second invocation is the same dead pipe with the buffer taken away, and it is what makes this
# route ORDERING-sensitive. Buffered, the print loop never reaches a `write(2)`: the text sits under
# the 8 KB stdout buffer, nothing raises inside `gate()`, and the report is written whichever side
# of the loop it sits on — so the first invocation alone cannot tell the shipped order from the
# reverted one, which is `D-m23-ag`. Measured here, and reached independently by
# `gemini-3.7-flash-high` and `grok-4.6` from the code alone. `PYTHONUNBUFFERED=1` makes the first
# `print` in the loop write immediately and raise there, inside `gate()`: with the report written
# first the ledger on disk is this run's table, and with the write moved after the loop it is the
# stale one, because the write is never reached. It is not a contrived environment either — it is
# what CI sets to keep interleaved logs readable.
printf '# Breadth ledger — fixture\n\n| Layer | Result |\n|---|---|\n| `breadth` | STALE-FROM-AN-EARLIER-RUN |\n' > "$LEDGER44U"
PATH="$root/bin:$PATH" PYTHONUNBUFFERED=1 python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$root/planning/fidelity/fixture.layers.json" "$root/dumps" --report "$LEDGER44U" > >(:) 2>"$ERR44U"
status44u=$?
# The two marker clauses read the STDERR file, and they are the only assertions in this suite that
# the marker survived a stream failure. `emit` prints, flushes, and falls back to stderr when the
# flush raises; here the flush always raises, buffered or not, because the pipe's reader has gone.
# So a marker that is delivered by anything but `emit` — a bare `print`, a `sys.stdout.write`, a
# `print(..., file=sys.stdout)` — is lost on both invocations, `mock-fidelity-gate.sh` denies a
# ledger this run did write, and nothing else in the file notices.
if [ "$status44" = 3 ] && ! grep -qF 'STALE-FROM-AN-EARLIER-RUN' "$LEDGER44" \
   && grep -qF 'Present / divergent / absent' "$LEDGER44" \
   && grep -qF "mock-fidelity: report written to $LEDGER44" "$ERR44" \
   && [ "$status44u" = 3 ] && ! grep -qF 'STALE-FROM-AN-EARLIER-RUN' "$LEDGER44U" \
   && grep -qF 'Present / divergent / absent' "$LEDGER44U" \
   && grep -qF "mock-fidelity: report written to $LEDGER44U" "$ERR44U"; then
  echo "ok    stdout with no reader returns 3 and the marker still reaches stderr — exit $status44"
else
  echo "FAIL  stdout with no reader returned $status44 buffered / $status44u unbuffered; ledgers:"
  echo "      buffered:   $(head -5 "$LEDGER44" | tr '\n' ' ')"
  echo "      unbuffered: $(head -5 "$LEDGER44U" | tr '\n' ' ')"
  echo "      stderr:     $(cat "$ERR44" 2>/dev/null | tr '\n' ' ' | cut -c1-200)"
  echo "      stderr(u):  $(cat "$ERR44U" 2>/dev/null | tr '\n' ' ' | cut -c1-200)"
  fail=1
fi

# 68 — R5 with a report path, on the same fixture, which the route table below called unreachable.
#
# The completeness argument for that row was sound about `gate()`'s interior and silent about
# `main()`, which flushes stdout AFTER `gate()` has returned. Point the same dead pipe at a run
# whose manifest is missing and `gate()` takes R1: it writes the obituary naming
# `manifest: no artifact at …`, emits the marker, and returns 3. The flush then raises
# `BrokenPipeError` into the boundary with `report_written` False and `report_path` set — so the
# obituary was written a SECOND time, the marker emitted a second time, and the ledger a reader
# opens named a downstream symptom where the first write had named the cause. Measured 3/3 on the
# shipped engine with no mutation, which is what makes this a defect rather than a hardening.
#
# The two invocations are case 44's buffered/unbuffered pair and they are not equivalent here
# either: `PYTHONUNBUFFERED=1` makes `emit`'s own write raise at the print, so nothing is left in
# the buffer for `main()`'s flush to re-raise on, the route is never entered, and the unbuffered
# run is green on the shipped engine. The buffered one is the load-bearing invocation, and a case
# built only on the unbuffered spelling would have seen nothing (`claude-fable-5`).
LEDGER68="$SCRATCH/brokenpipe-obituary-ledger.md"
LEDGER68U="$SCRATCH/brokenpipe-obituary-unbuffered-ledger.md"
ERR68="$SCRATCH/brokenpipe-obituary-stderr.txt"
ERR68U="$SCRATCH/brokenpipe-obituary-unbuffered-stderr.txt"
MISSING68="$root/planning/fidelity/no-such-manifest.layers.json"
printf '# Breadth ledger — fixture\n\n| Layer | Result |\n|---|---|\n| `breadth` | STALE-FROM-AN-EARLIER-RUN |\n' > "$LEDGER68"
printf '# Breadth ledger — fixture\n\n| Layer | Result |\n|---|---|\n| `breadth` | STALE-FROM-AN-EARLIER-RUN |\n' > "$LEDGER68U"
cases=$((cases + 1))
PATH="$root/bin:$PATH" python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$MISSING68" "$root/dumps" --report "$LEDGER68" > >(:) 2>"$ERR68"
status68=$?
PATH="$root/bin:$PATH" PYTHONUNBUFFERED=1 python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$MISSING68" "$root/dumps" --report "$LEDGER68U" > >(:) 2>"$ERR68U"
status68u=$?
markers68=$(grep -cF "mock-fidelity: report written to $LEDGER68" "$ERR68")
markers68u=$(grep -cF "mock-fidelity: report written to $LEDGER68U" "$ERR68U")
# The symptom belongs on the console and the cause belongs in the file. Both clauses matter: an
# engine that stopped reporting the broken pipe at all would satisfy the ledger clauses while
# losing the failure, and one that reports it into the ledger is the defect this case exists for.
if [ "$status68" = 3 ] && [ "$status68u" = 3 ] \
   && grep -qF 'no artifact at' "$LEDGER68" && ! grep -qF 'BrokenPipeError' "$LEDGER68" \
   && ! grep -qF 'STALE-FROM-AN-EARLIER-RUN' "$LEDGER68" && [ "$markers68" = 1 ] \
   && grep -qF 'INCONCLUSIVE gate: BrokenPipeError' "$ERR68" \
   && grep -qF 'no artifact at' "$LEDGER68U" && ! grep -qF 'BrokenPipeError' "$LEDGER68U" \
   && ! grep -qF 'STALE-FROM-AN-EARLIER-RUN' "$LEDGER68U" && [ "$markers68u" = 1 ]; then
  echo "ok    a pipe that breaks after the verdict leaves the obituary naming the cause — exit $status68"
else
  echo "FAIL  the obituary was overwritten after the verdict: exit $status68 buffered / $status68u unbuffered,"
  echo "      markers $markers68 buffered / $markers68u unbuffered (1 each expected)"
  echo "      ledger:     $(grep -m2 -E 'gate:|manifest:|STALE' "$LEDGER68" | tr '\n' ' ' | cut -c1-200)"
  echo "      ledger(u):  $(grep -m2 -E 'gate:|manifest:|STALE' "$LEDGER68U" | tr '\n' ' ' | cut -c1-200)"
  fail=1
fi

# 46 — BL-2's enumeration, checked rather than asserted. The fix for a property that quantifies
# over "every reader of this structure" is only as good as the enumeration behind it, and the
# enumeration was wrong twice: the claimant test went into `layer_breadth` while `layer_copy` read
# the same dict with no such test. So the reader set is now read out of the engine's own syntax
# tree on every run, and a new layer that reaches past `ctx.comparable` to the raw declaration goes
# red here rather than in whatever the next verifier happens to try.
cases=$((cases + 1))
if python3 - "$ENGINE" <<'ENUM'
import ast, sys

tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
# Every function whose body reads the `.pairs` attribute of anything. `ctx.pairs` and `self.pairs`
# are the same structure under two names, and there is no `getattr` anywhere in this file, so an
# attribute read is the only way to reach it and this walk finds all of them.
readers = set()
for parent in ast.walk(tree):
    if not isinstance(parent, (ast.FunctionDef, ast.AsyncFunctionDef)):
        continue
    for node in ast.walk(parent):
        if isinstance(node, ast.Attribute) and node.attr == "pairs":
            readers.add(parent.name)

# `__init__` declares it, `load` writes it, `derive_pairings` turns it into the set a layer may
# compare, and `layer_breadth` is the layer whose subject IS pairing integrity, so it reads the raw
# declaration on purpose to report what is wrong with it. Any other name here is a layer comparing
# two sides of a pairing nothing has vouched for.
allowed = {"__init__", "load", "derive_pairings", "layer_breadth"}
if readers != allowed:
    print(f"readers of .pairs are {sorted(readers)}, expected {sorted(allowed)}")
    sys.exit(1)
# An attribute walk enumerates the readers only while an attribute read is the only way in.
# `getattr(ctx, "pairs")`, `vars(ctx)["pairs"]` and `ctx.__dict__["pairs"]` all reach the same
# structure without an `ast.Attribute` named `pairs` (`gpt-5.6-sol`), so their presence anywhere in
# the engine invalidates this check and is reported as such rather than passing quietly.
source = open(sys.argv[1], encoding="utf-8").read()
for escape in ("getattr(", "vars(", "__dict__"):
    if escape in source:
        print(f"the engine contains {escape!r}, so an attribute walk no longer enumerates its readers")
        sys.exit(1)
ENUM
then
  echo "ok    only the layer that reports on pairing integrity reads the raw pairing declaration"
else
  echo "FAIL  a reader of ctx.pairs appeared that does not apply the claimant and vouched tests"
  fail=1
fi

# ------------------------------------------------------ the sixth gap-fix: the marker, enumerated
#
# Five passes armed REPORT_MARKER route by route, and each next verification found another route.
# What was missing was not one more case but the enumeration, so here it is — argued from the
# engine's structure rather than from how hard anybody looked, and checked by case 60 below rather
# than left as this comment's word.
#
# `mock-fidelity-gate.sh` decides between `ledger written to <path>` and `NO ledger was written by
# this run` on one `grep -qF "mock-fidelity: report written to $LEDGER"`. Anything that satisfies
# that grep has to put those bytes on a stream the script captures, so the question closes by
# finding every place the engine can print them:
#
#   * the byte string exists once in the engine, as the module constant `REPORT_MARKER` — no
#     second literal, no f-string, no `.format`;
#   * that constant is read at exactly two places, both spelled `emit(REPORT_MARKER + …)`;
#   * nothing in the engine reaches a module global under another name — no `getattr`, no `vars`,
#     no `__dict__`. This enumeration rests on that, which is why case 60 re-checks it here
#     instead of relying on case 46 having checked it for a different reason.
#
# Two emission sites, therefore:
#
#   S1  `gate()`, immediately after `write_report` returned and `run.report_written` was set. One
#       predecessor — the `if report_path:` block — so it is reached only with `--report`, and only
#       on a write that returned.
#   S2  the tail of `write_unmeasured_report`, after the obituary was written. Reached through that
#       function's callers, and only when `path` is truthy and `open()` accepted it; otherwise the
#       function returns at `if not path` or emits the WARNING instead.
#
# `write_unmeasured_report` is called at exactly five sites, which is the other half of the
# enumeration and is checked by the same case:
#
#   R1  gate()               — the manifest failed to load          … case 61
#   R2  gate().unmeasured()  — one of six validation returns        … case 32
#   R3  gate()               — Context construction or load raised  … case 49
#   R4  gate()               — write_report raised                  … case 51, third invocation
#   R5  main()               — gate() raised with nothing written   … case 68
#
# Six route classes, and what each is worth:
#
#   S1 is asserted four ways: case 43 (the marker survives a console that cannot encode the
#      report), case 44 (it reaches stderr when stdout is dead), and case 51's first and fourth
#      invocations (present on a write that returned, and spelled the way the CALLER spelled the
#      path rather than however the engine would prefer to spell it).
#   R1-R4 are asserted at the cases named above. R4's assertion is that the marker is ABSENT,
#      because that is the route whose write failed.
#   R5 WAS reachable with a report path, and this row now says what was measured rather than what
#      was argued. The argument — with `--report` set, `gate()` either returns 3 from R1-R4
#      without raising, or it reaches the report block, after which `run.report_written` is true
#      before anything downstream can raise — is sound about `gate()`'s INTERIOR and silent about
#      `main()`, which flushed stdout AFTER `gate()` had returned. Point a dead pipe at a run whose
#      manifest is missing and that flush raised into the boundary with `report_written` False and
#      `report_path` set: R5 executed with a real path, the obituary was written a second time,
#      and the ledger a reader opens said `gate: BrokenPipeError` where the first write had said
#      `manifest: no artifact at …`. Measured 3/3 on the engine as shipped, no mutation.
#      The engine now catches that flush where it happens, one frame before the boundary, so what
#      reaches R5 is `gate()` RAISING with the report unwritten — which is the part the interior
#      argument does cover. Case 68 is the regression test and it was watched red on the shipped
#      engine before it was green on this one; the `Run` wiring R5 depends on is checked in case 60.
#      The lesson is the row rather than the fix: the completeness argument was derived from this
#      engine and did not read the comment sitting directly above the line that falsified it.
#
# Measured against the 59-case suite that shipped before the sixth pass, by tracing every python3
# process it starts: 145 processes, of which 52 are the engine and 10 of those carry `--report`.
# Eight emissions — five at S1, three at S2, through R2 once and R3 twice. R1 was executed by
# nothing at all, and R2's emission was read by nothing. Both are closed above and below.
# "145 engine runs" was this file's own wording for that trace and it is wrong: 145 is every
# python3 process the suite starts, the fixture builder and the affordance tool included, and the
# engine is 52 of them. Re-measured on the same suite with a `sitecustomize.py` logging argv.
#
# The correction filed against that wording said 53 and named an inline `-c` script as the extra
# process. This file has never run one: no `-c` form appears at any of the 11 revisions
# `git log --follow` names for it. What 53 was counted from is not recoverable — the correction
# did not say — but the one thing in the suite that would produce it is case 46, which hands the
# engine's path to a `python3 -` stdin heredoc. That heredoc `ast.parse`s the engine's source and
# never executes it, and its `sys.argv[0]` is `-`, so it is an engine READER rather than an engine
# run: a count keyed on the path appearing in a command line takes it, a count keyed on
# `sys.argv[0]` does not. That suite held one such heredoc; the sixth pass added case 60's second,
# which reads the engine the same way. 52 is the `sys.argv[0]` figure — the number of times the
# engine's own code ran — and is the one this table rests on.

# 60 — the enumeration itself, checked against the engine's syntax tree on every run.
#
# This is `D-m23-aw`, which is this item's own defect one level up: the suite states in prose what
# it cannot reach, and a bound that is wrong reads exactly like one that is right. The gate-script
# declaration that used to sit here was measured false this pass. So the reachability claims that
# CAN be made checkable are made checkable, and this is the one that matters — if a third emission
# site or a sixth caller appears, the route table above is incomplete and the suite says so, rather
# than a seventh verification finding it.
cases=$((cases + 1))
if python3 - "$ENGINE" "$REPO/scripts/acceptance/mock-fidelity-gate.sh" <<'ENUM'
import ast, sys

engine, gate = sys.argv[1], sys.argv[2]
source = open(engine, encoding="utf-8").read()
tree = ast.parse(source)
problems = []

# The marker's spelling, derived from the syntax tree rather than from a substring scan of the
# file. `source.count("report written to")` reads a comment as a spelling and misses one the
# parser would fold: `"mock-fidelity: report" " written to "` is a single Constant carrying the
# marker's bytes and adds nothing to that count, so a second emitter spelled that way satisfies
# the consumer's grep byte for byte while the guard stays silent.
MARKER = "mock-fidelity: report written to "


def folded(node):
    """The constant string a node denotes, or None.

    Implicit concatenation is already one Constant by the time the parser is done; `+` of two
    foldable sides and an f-string whose pieces are all constants are the other two spellings.
    Bytes are folded too, because `os.write(1, b"...")` reaches the consumer's stream without
    going anywhere near `print`.
    """
    if isinstance(node, ast.Constant):
        value = node.value
        if isinstance(value, bytes):
            try:
                value = value.decode("utf-8")
            except UnicodeDecodeError:
                return None
        return value if isinstance(value, str) else None
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left, right = folded(node.left), folded(node.right)
        return None if left is None or right is None else left + right
    if isinstance(node, ast.JoinedStr):
        pieces = [folded(value) for value in node.values]
        return None if any(piece is None for piece in pieces) else "".join(pieces)
    return None


spellings = [node for node in ast.walk(tree)
             if (value := folded(node)) is not None and MARKER in value]
if len(spellings) != 1:
    problems.append(f"the marker's bytes are spelled {len(spellings)} times in the engine's syntax "
                    "tree, expected 1 — every emitter has to reach the consumer through the one "
                    "constant, or an enumeration of the emitters means nothing")

# Assembly, which is the same evasion one layer down: `"mock-fidelity: %s to %s" % ("report
# written", path)` puts the consumer's bytes on the stream without any fold ever seeing them, and
# so does a `.format`, a `.join`, or `os.write(1, b"mock-fidelity: ")`. Nothing else in this engine
# needs a long fragment of the marker, so a constant that is one is either the marker being
# reassembled or a message that should be using REPORT_MARKER. Seven is the shortest bound this
# file admits, measured rather than chosen: at six `'report'` collides and at four `'mock'` does.
for node in ast.walk(tree):
    if not isinstance(node, ast.Constant):
        continue
    value = folded(node)
    if value is not None and value != MARKER and len(value) >= 7 and value in MARKER:
        problems.append(f"line {node.lineno} carries {value!r}, a {len(value)}-character piece of "
                        "the marker. Assembled at run time — `%`, `.format`, `.join`, split bytes "
                        "through os.write — those bytes reach the consumer with no spelling to find")

# The walk below finds a global through the name it is bound to. Each of these reaches one without
# it, and `sys.modules[__name__].REPORT_MARKER` is an Attribute rather than a Name load, so it
# reads the constant while the walk records nothing.
for escape in ("getattr(", "vars(", "__dict__", "globals(", "locals(", "setattr(", "eval(",
               "exec(", "compile(", "__import__", "importlib", "sys.modules", "os.write("):
    if escape in source:
        problems.append(f"the engine contains {escape!r}, so walking for the name REPORT_MARKER no "
                        "longer enumerates everything that can print it")

# A sibling module is the third way to add an emitter without touching anything the walk above
# reads: this is a walk of THIS file's syntax tree and it says nothing about a file this one
# imports. Standard library only, and no relative import, keeps the enumeration's population equal
# to the file it walks. If the engine is ever split into a package this fails, and that is the
# signal to re-derive the enumeration across the package rather than a false alarm — the single
# file is what the completeness argument rests on, so the cost is accepted deliberately.
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        imported = [(alias.name.split(".")[0], 0) for alias in node.names]
    elif isinstance(node, ast.ImportFrom):
        imported = [((node.module or "").split(".")[0], node.level)]
    else:
        continue
    for name, level in imported:
        if level:
            problems.append(f"line {node.lineno} imports relatively from {'.' * level}{name}, so "
                            "the marker can be emitted from a file this enumeration never reads")
        elif name not in sys.stdlib_module_names:
            problems.append(f"line {node.lineno} imports {name!r}, which is not in the standard "
                            "library, so the marker can be emitted from a file this enumeration "
                            "never reads")

# Innermost enclosing function for every node, so `unmeasured` is attributed to itself rather than
# to `gate` around it.
marker_reads, wur_reads = [], []


def walk(node, owner):
    for child in ast.iter_child_nodes(node):
        inner = child.name if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)) else owner
        if isinstance(child, ast.Name) and isinstance(child.ctx, ast.Load):
            if child.id == "REPORT_MARKER":
                marker_reads.append(owner)
            elif child.id == "write_unmeasured_report":
                wur_reads.append(owner)
        walk(child, inner)


walk(tree, "<module>")

if sorted(marker_reads) != ["gate", "write_unmeasured_report"]:
    problems.append(f"REPORT_MARKER is read in {sorted(marker_reads)}, expected "
                    "['gate', 'write_unmeasured_report'] — a new emission site is a route the "
                    "suite has no assertion for")

# Every read has to be the marker going out through `emit`, because `emit` is the only thing in the
# file that falls back to stderr — a marker delivered by a bare `print` is lost exactly when the
# gate needs it, and that is invisible to any case that does not read a dead stdout's stderr.
emitted = sum(
    1 for node in ast.walk(tree)
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "emit"
    and len(node.args) == 1 and isinstance(node.args[0], ast.BinOp)
    and isinstance(node.args[0].op, ast.Add)
    and isinstance(node.args[0].left, ast.Name) and node.args[0].left.id == "REPORT_MARKER")
if emitted != len(marker_reads):
    problems.append(f"{len(marker_reads)} reads of REPORT_MARKER and {emitted} of them are "
                    "`emit(REPORT_MARKER + …)`; the rest cannot reach a second stream")

defs = [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == "emit"]
if len(defs) != 1:
    problems.append(f"{len(defs)} definitions of emit(), expected 1")
elif "stderr" not in ast.dump(defs[0]):
    problems.append("emit() no longer names stderr, so the marker has no second stream and the "
                    "engine's own docstring — 'a console that cannot encode the report still "
                    "delivers it on stderr' — is false")

# R5 is the one route with no behavioural assertion, because it cannot execute with a report path
# set. What can be checked is that it stays WIRED: `gate()` records the path on `Run` as it parses
# it, and `main()`'s handler hands that recorded path to the obituary. Dropping the `Run` field and
# keeping only the local — a redundant-assignment cleanup, and the local is what every reachable
# route already uses — leaves all 67 cases green and leaves `main()` writing the obituary to `None`,
# so the first ordering change after it silently loses the ledger (`gemini-3.7-flash-high`, asked to
# break rather than review).
stores = [n for n in ast.walk(tree)
          if isinstance(n, ast.Attribute) and n.attr == "report_path"
          and isinstance(n.ctx, ast.Store)]
if not stores:
    problems.append("nothing assigns run.report_path any more, so main()'s handler writes the "
                    "obituary to None on the one route this suite cannot drive")
handler = [n for n in ast.walk(tree)
           if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
           and n.func.id == "write_unmeasured_report" and n.args
           and isinstance(n.args[0], ast.Attribute) and n.args[0].attr == "report_path"]
if len(handler) != 1:
    problems.append(f"{len(handler)} calls of write_unmeasured_report take run.report_path, "
                    "expected 1 — main()'s handler is the only route that cannot read the local")

expected_callers = ["gate", "gate", "gate", "main", "unmeasured"]
if sorted(wur_reads) != expected_callers:
    problems.append(f"write_unmeasured_report is reached from {sorted(wur_reads)}, expected "
                    f"{expected_callers}. Every caller is a route to the marker, and the suite "
                    "asserts one per route: R1 case 61, R2 case 32, R3 case 49, R4 case 51")

# The producer and the consumer have to be the same claim. Loosening this grep — dropping $LEDGER,
# or guarding it on the exit code — makes the gate script deny a ledger it wrote, and no engine
# case can see that (`gemini-3.7-flash-high`, asked to break rather than review).
consumer = open(gate, encoding="utf-8").read()
wanted = 'grep -qF "mock-fidelity: report written to $LEDGER" "$ENGINE_LOG"'
if consumer.count(wanted) != 1:
    problems.append("mock-fidelity-gate.sh no longer reads the marker at the path it asked for, "
                    f"as `{wanted}` — the producer and the consumer have drifted apart")

# What this does NOT catch, measured rather than left to a reader's optimism. Every check above is
# static, and a static check on an emitter is one-directional by construction: it catches the
# marker being LOST or MOVED, and it catches the classes of new emitter enumerated above, but it
# cannot enumerate every way bytes can be assembled at run time. Measured against this engine:
# a chained `+` of constants, a `.format`, a `.join`, a `%`, split bytes through `os.write` and a
# subprocess handed the marker as implicitly-concatenated pieces all go red here; an assembly from
# constants of SIX characters or fewer — six pieces or more — stays green, because seven is the
# shortest fragment bound this file admits. The other half of the guard is behavioural and it is
# what covers a marker that goes missing: cases 43, 44, 49, 51 and 61 assert the marker per route
# on real runs, and 62-67 assert what the consumer does with it.
for line in problems:
    print(line)
sys.exit(1 if problems else 0)
ENUM
then
  echo "ok    the marker is emitted at two sites and its obituary has five callers, all enumerated"
else
  echo "FAIL  the marker's emission sites or routes have changed, so the route table is incomplete"
  fail=1
fi

# 61 — R1: the manifest itself will not parse. This is the first of `write_unmeasured_report`'s
# five callers and the one the trace found nothing through — measured, not assumed: across the 52
# engine runs in that 59-case suite (145 python3 processes in all, per the route table above), a
# trace of the two emission lines recorded zero hits here. Engine runs are the whole population
# that can reach it, since both emission sites are engine code. This case is what reaches it.
# Every other route to an obituary was covered and this one was not, which is what happens when a
# marker is armed route by route against a route set nobody enumerated.
root="$SCRATCH/manifest-unparseable"; LEDGER61="$SCRATCH/manifest-unparseable-ledger.md"
export FIXTURE_BROKEN=manifest-not-json; build "$root"; unset FIXTURE_BROKEN
printf '# Breadth ledger — fixture\n\n| Layer | Result |\n|---|---|\n| `breadth` | STALE-FROM-AN-EARLIER-RUN |\n' > "$LEDGER61"
cases=$((cases + 1))
out61=$(PATH="$root/bin:$PATH" python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$root/planning/fidelity/fixture.layers.json" "$root/dumps" --report "$LEDGER61" 2>&1)
status61=$?
if [ "$status61" = 3 ] && grep -qF 'did not parse' <<<"$out61" \
   && grep -qF "mock-fidelity: report written to $LEDGER61" <<<"$out61" \
   && grep -qF 'This run did not produce a table' "$LEDGER61" \
   && ! grep -qF 'STALE-FROM-AN-EARLIER-RUN' "$LEDGER61"; then
  echo "ok    a manifest that will not parse replaces the ledger and says so — exit $status61"
else
  echo "FAIL  an unparseable manifest returned $status61, ledger: $(head -8 "$LEDGER61" | tr '\n' ' ' | cut -c1-200)"
  echo "$out61" | sed 's/^/        /'
  fail=1
fi

# 62-67 — the marker's only consumer, driven hermetically.
#
# `mock-fidelity-gate.sh` lines 126-141 are where the marker is finally read, and until this pass
# no case reached them: the two gate-script routes the suite could drive (`no-such-surface`, an
# unparseable manifest) both return before the engine is invoked. The file said so, and gave a
# reason that was measurably false — that reaching the decision needs the MEASURE build and four
# rendered dumps, "three minutes and not hermetic". It needs a symlinked script, the `swift` stub
# this file already writes and twelve lines of `MeasureDump`, and it takes about a second.
#
# All three branches are driven, plus both emission sites and both non-zero verdicts, because the
# block's failure modes are not symmetric: deleting the grep, inverting it, collapsing the two
# denial branches into one, and guarding the affirmation on `$status` are four different edits and
# only the last of them is invisible to a clean fixture.

gate_case() {
  # $1 = name, $2 = expected exit, $3 = root, $4... = strings the gate's own output must carry
  # (a leading `!` refutes, as in `expect`).
  local name=$1 want=$2 root=$3 out status
  cases=$((cases + 1))
  shift 3
  out=$(cd "$root" && PATH="$root/bin:$PATH" ./scripts/acceptance/mock-fidelity-gate.sh fixture 2>&1)
  status=$?
  if [ "$status" != "$want" ]; then
    echo "FAIL  $name — the gate script exited $status, expected $want"
    echo "$out" | sed 's/^/        /'
    fail=1
    return
  fi
  local w
  for w in "$@"; do
    [ -z "$w" ] && continue
    if [ "${w:0:1}" = "!" ]; then
      if grep -qF -- "${w:1}" <<<"$out"; then
        echo "FAIL  $name — the gate script said what it must not: ${w:1}"
        echo "$out" | sed 's/^/        /'
        fail=1
        return
      fi
      continue
    fi
    if ! grep -qF -- "$w" <<<"$out"; then
      echo "FAIL  $name — the gate script never said: $w"
      echo "$out" | sed 's/^/        /'
      fail=1
      return
    fi
  done
  echo "ok    $name — exit $status"
}

CLAIM_YES="mock-fidelity-gate: ledger written to planning/fidelity/fixture.ledger.md"
CLAIM_NO="mock-fidelity-gate: NO ledger was written by this run"
CLAIM_NONE="mock-fidelity-gate: no ledger was written by this run"

# 62 — a clean surface: the engine writes the table, emits at S1, and the script repeats the claim.
root="$SCRATCH/gate-clean"; build_gate_root "$root"
gate_case "the gate claims a ledger the engine said it wrote" 0 "$root" "$CLAIM_YES" "!$CLAIM_NO"
grep -qF 'Present / divergent / absent' "$root/planning/fidelity/fixture.ledger.md" || {
  echo "FAIL  the gate script's clean run left no table at planning/fidelity/fixture.ledger.md"; fail=1; }

# 63 — findings. The exit has to be the ENGINE's, not `tee`'s: the engine is on the left of a pipe
# and `status=${PIPESTATUS[0]}` is the line that keeps exit 1 from arriving as exit 0.
root="$SCRATCH/gate-drift"; export FIXTURE_DRIFT=1; build_gate_root "$root"; unset FIXTURE_DRIFT
gate_case "the gate passes the engine's findings exit through the pipe" 1 "$root" \
  "$CLAIM_YES" "label differs" "!$CLAIM_NO"

# 64 — a ledger that could not be replaced, with an earlier run's table sitting at the path. No
# marker, a file on disk: the denial branch, and the one sentence in the whole gate that stops a
# stale table being read as this run's. The FILE is read-only rather than its directory, because
# `open(path, "w")` on an existing writable file succeeds in a directory nobody may write to.
root="$SCRATCH/gate-deny"; build_gate_root "$root"
printf '# Breadth ledger — fixture\n\n| Layer | Result |\n|---|---|\n| `breadth` | STALE-FROM-AN-EARLIER-RUN |\n' \
  > "$root/planning/fidelity/fixture.ledger.md"
chmod 400 "$root/planning/fidelity/fixture.ledger.md"
gate_case "the gate denies a ledger this run did not write" 3 "$root" \
  "$CLAIM_NO" "is an earlier run's and does not describe this one" "!$CLAIM_YES"
chmod 600 "$root/planning/fidelity/fixture.ledger.md"
grep -qF 'STALE-FROM-AN-EARLIER-RUN' "$root/planning/fidelity/fixture.ledger.md" || {
  echo "FAIL  case 64's stale table was replaced after all, so the denial was about something else"
  fail=1; }

# 65 — the same run with nothing at the path at all. A third sentence rather than the second one
# naming a file that is not there.
root="$SCRATCH/gate-nofile"; build_gate_root "$root"
chmod 500 "$root/planning/fidelity"
gate_case "the gate says so when there is no ledger at all" 3 "$root" \
  "$CLAIM_NONE" "and there is no" "!$CLAIM_NO" "!$CLAIM_YES"
chmod 700 "$root/planning/fidelity"

# 66 — exit 3 WITH a table. The decision reads the marker, not the exit code, and those are
# different claims: a run that measured eight layers, wrote the table and then found a required
# layer blocked exits 3 having written the very file the script is about to describe. Guarding the
# affirmation on `[ $status -ne 3 ]` reads as a tidy-up, leaves every engine case green, and makes
# the gate deny its own table (`gemini-3.7-flash-high`, asked to break rather than review).
root="$SCRATCH/gate-blocked"; export FIXTURE_NO_AXIS=1; build_gate_root "$root"; unset FIXTURE_NO_AXIS
gate_case "the gate claims a ledger written by a run that then went inconclusive" 3 "$root" \
  "$CLAIM_YES" "measured nothing" "!$CLAIM_NO"
grep -qF 'Present / divergent / absent' "$root/planning/fidelity/fixture.ledger.md" || {
  echo "FAIL  case 66's run exited 3 without leaving the table it claimed"; fail=1; }

# 67 — the same decision reached from the OTHER emission site. Here the run never measures
# anything: `Context.__init__` raises, `write_unmeasured_report` replaces the ledger with the
# obituary and emits the marker from S2, and the gate has to affirm — the file at that path IS
# this run's, and saying otherwise would send a reader to a table that no longer exists.
root="$SCRATCH/gate-obituary"; export FIXTURE_BROKEN=manifest-no-floors; build_gate_root "$root"
unset FIXTURE_BROKEN
gate_case "the gate claims the obituary as this run's ledger" 3 "$root" \
  "$CLAIM_YES" "!$CLAIM_NO"
grep -qF 'This run did not produce a table' "$root/planning/fidelity/fixture.ledger.md" || {
  echo "FAIL  case 67 left something other than the obituary at the ledger path"; fail=1; }

# 37 — the real colour-literal lint, against every colour-constructor spelling the `literals` layer
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

# 38 — the gate script's own preflight, driven for real
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
