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
if [ "$status32" = 3 ] && grep -q 'This run did not produce a table' "$LEDGER32" \
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
root="$SCRATCH/multiline"; export FIXTURE_MULTILINE=1; build "$root"; unset FIXTURE_MULTILINE
expect "the type layer reports comparisons and census separately" 1 "$root" \
  "2 per-role comparison(s) over 3 text nodes" "1 multi-line node(s) excluded"

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
if [ "$status49" = 3 ] && grep -qF 'no artifact at' "$LEDGER49" \
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
if grep -qF "mock-fidelity: report written to $LEDGER51" <<<"$out51" \
   && ! grep -qF "report written to" <<<"$out51_none"; then
  echo "ok    the engine claims a written report only when it wrote one"
else
  echo "FAIL  the report-written marker does not track the write"
  echo "$out51" | sed 's/^/        /'
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
if [ "$status43" = 3 ] && grep -qF 'UnicodeEncodeError' <<<"$out43" \
   && ! grep -qF 'STALE-FROM-AN-EARLIER-RUN' "$LEDGER43" \
   && grep -qF 'Present / divergent / absent' "$LEDGER43" \
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
cases=$((cases + 1))
PATH="$root/bin:$PATH" python3 "$root/scripts/acceptance/mock_fidelity.py" \
  "$root/planning/fidelity/fixture.layers.json" "$root/dumps" > >(:) 2>/dev/null
status44=$?
if [ "$status44" = 3 ]; then
  echo "ok    stdout with no reader returns 3, not the interpreter's 120 — exit $status44"
else
  echo "FAIL  stdout with no reader returned $status44, not 3"
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

# `D-m23-y` — the gate script's `ledger written to …` sentence — is NOT armed here, and the reason
# is worth writing down rather than leaving as a gap in the count. Every path this selftest can
# drive the gate script down (`no-such-surface`, a manifest that will not parse) returns before the
# engine is ever invoked, so the sentence is not reached and a case here would pass whether the fix
# existed or not — a vacuous check, which is the failure this whole item is about. Reaching that
# line needs the MEASURE build and four rendered dumps, which is three minutes and not hermetic.
# It is armed for real against the live surface instead, and the red and green are recorded in
# planning/evidence/M23-gapfix-3.md.

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
